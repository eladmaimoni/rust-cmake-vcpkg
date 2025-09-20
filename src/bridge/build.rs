use std::env;
use std::path::PathBuf;
use std::process::Command;

const CMAKE_INSTALLED_DIR: &str = "installed";
const VCPKG_INSTALLED_DIR: &str = "vcpkg_installed";

#[derive(Debug)]
struct BuildDetails {
    /// The CMake preset to use for this build (e.g. "vs2022r-install")
    cmake_config_preset: &'static str,
    cmake_build_preset: &'static str,
}

fn deduce_build_details(target_os: &str, _target_arch: &str, build_profile: &str) -> BuildDetails {
    match target_os {
        "windows" => {
            // NOTE: The C/C++ objects produced by the cxx crate and its build
            // infrastructure are typically compiled with the release CRT
            // settings. Mixing MSVC debug CRT (MDd) and release CRT (MD) will
            // trigger LNK2038 mismatch errors. To avoid this when running
            // `cargo test` (PROFILE=debug) we map the debug profile to the
            // CMake RelWithDebInfo install preset so the installed C++ libs
            // use release-like runtime settings and match the cxx bridge.
            let (cmake_config_preset, cmake_build_preset, _package_config_path) =
                match build_profile {
                    // Build using the release install preset. The project's
                    // installation step places artifacts under lib/Release (see
                    // cmake/installation.cmake which maps RelWithDebInfo -> Release
                    // for install layout), so use lib/Release here.
                    // "debug" => {
                    //     // https://github.com/rust-lang/rust/issues/39016#issuecomment-2391095973
                    //     // Don't link the default CRT
                    //     // println!("cargo::rustc-link-arg=/nodefaultlib:msvcrt");
                    //     // Link the debug CRT instead
                    //     // println!("cargo::rustc-link-arg=/defaultlib:msvcrtd");
                    //     ("windows-debug-install", "lib/Debug", "debug/lib")
                    // }
                    "debug" => (
                        "msvc-mt",
                        "msvc-mt-debug-install",
                        "debug/lib/pkgconfig/by2.pc",
                    ),
                    "release" => ("msvc-md", "msvc-md-release-install", "lib/pkgconfig/by2.pc"),
                    _ => {
                        panic!("Unsupported build profile: {}", build_profile);
                    }
                };

            BuildDetails {
                cmake_config_preset,
                cmake_build_preset,
            }
        }
        _ => {
            panic!("Unsupported target OS: {}", target_os);
        }
    }
}

fn get_workspace_root() -> PathBuf {
    let current_directory = env::current_dir().unwrap(); // the build script’s current directory is the source directory of the build script’s package

    // Determine workspace root (two levels up from this crate: .../src/app)
    // let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    current_directory
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf()
}

fn main() {
    let out_dir = env::var("OUT_DIR").unwrap().replace('\\', "/");
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let build_profile = std::env::var("PROFILE").unwrap();

    let build_details = deduce_build_details(&target_os, &target_arch, &build_profile);
    let workspace_root = get_workspace_root();

    println!(
        "cargo:warning=Building for OS={target_os}, ARCH={target_arch}, PROFILE={build_profile}, out_dir={out_dir}"
    );

    println!("cargo:rerun-if-changed=build.rs");

    let cmake_install_dir = out_dir.to_string() + "/" + CMAKE_INSTALLED_DIR;
    let vcpkg_install_dir = out_dir.to_string() + "/" + VCPKG_INSTALLED_DIR;

    println!(
        "cargo:warning=installing CMake artifacts to: {}",
        cmake_install_dir
    );

    let status = Command::new("cmake")
        .arg(format!("--preset={}", build_details.cmake_config_preset))
        .arg(format!("-DCMAKE_INSTALL_PREFIX={}", cmake_install_dir))
        .arg(format!("-DVCPKG_INSTALLED_DIR={}", vcpkg_install_dir))
        .current_dir(&workspace_root)
        .status()
        .expect("failed to run cmake configure");
    if !status.success() {
        panic!("cmake configure failed");
    }

    let status = Command::new("cmake")
        .arg("--build")
        .arg(format!("--preset={}", build_details.cmake_build_preset))
        .current_dir(&workspace_root)
        .status()
        .expect("failed to run cmake build");

    if !status.success() {
        panic!("cmake configure failed");
    }
    let include_dir = cmake_install_dir.to_string() + "/include";
    // The bindgen::Builder is the main entry point
    // to bindgen, and lets you build up options for
    // the resulting bindings.
    let bindings = bindgen::Builder::default()
        // The input header we would like to generate
        // bindings for.
        .header(format!("{}/by2/by2.h", include_dir))
        // Suppress non-CamelCase type lint warnings emitted for C type
        // aliases such as `intmax_t`. Use an outer attribute so the
        // generated file can be included as a module without causing an
        // "inner attribute is not permitted" error.
        .raw_line("#[allow(non_camel_case_types)]")
        // Tell cargo to invalidate the built crate whenever any of the
        // included header files changed.
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        // Finish the builder and generate the bindings.
        .generate()
        // Unwrap the Result and panic on failure.
        .expect("Unable to generate bindings");

    // Write the bindings to the $OUT_DIR/bindings.rs file.
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");

    println!("cargo:warning=Build details: {:#?}", build_details);

    // Parse the generated pkg-config file to determine link paths and libs
    // The package_config_path is relative to the install prefix, so build the
    // absolute path we can read.
    // Use the pkg-config crate to probe the generated .pc file. We set
    // PKG_CONFIG_LIBDIR to the install's pkgconfig dir so probe finds the
    // by2.pc that CMake produced. If probe fails we fall back to the
    // previous manual parsing logic.
    let pkgconfig_dir = PathBuf::from(&cmake_install_dir).join(if build_profile == "debug" {
        "debug/lib/pkgconfig"
    } else {
        "lib/pkgconfig"
    });

    // Try using pkg-config crate. Set PKG_CONFIG_LIBDIR so the probe finds
    // the .pc file that CMake generated inside our install prefix.
    unsafe {
        env::set_var("PKG_CONFIG_LIBDIR", pkgconfig_dir.as_os_str());
    }

    // Disable direct cargo metadata emission from the pkg-config crate so
    // we can inspect and sanitize probe results before printing cargo: lines.
    match pkg_config::Config::new()
        .cargo_metadata(false)
        .env_metadata(false)
        .probe("by2")
    {
        Ok(library) => {
            // Deduplicate and emit link search dirs
            let mut emitted_paths = std::collections::HashSet::new();
            for path in library.link_paths {
                let p = path.to_string_lossy().replace("\\", "/");
                if emitted_paths.insert(p.clone()) {
                    println!("cargo:rustc-link-search=native={}", p);
                }
            }

            // Process libs: promote path-like tokens to -L, otherwise emit -l
            let mut emitted_libs = std::collections::HashSet::new();
            for lib in library.libs {
                let lib_s = lib.replace("\\", "/");
                // kind=name -> split
                let name = if lib_s.contains('=') {
                    let mut parts = lib_s.splitn(2, '=');
                    parts.next();
                    parts.next().unwrap_or("").trim()
                } else {
                    lib_s.as_str()
                };

                // If name looks like a path, add to link search
                if name.contains('/') || name.contains(':') {
                    if emitted_paths.insert(name.to_string()) {
                        println!("cargo:rustc-link-search=native={}", name);
                    }
                    continue;
                }

                if emitted_libs.insert(name.to_string()) {
                    if build_profile == "debug" {
                        println!("cargo:rustc-link-lib=dylib={}", name);
                    } else {
                        println!("cargo:rustc-link-lib=static={}", name);
                    }
                }
            }
        }
        Err(e) => {
            println!("cargo:warning=pkg-config probe failed: {}", e);
            panic!("pkg-config probe failed: {}", e);

            //     if let Ok(contents) = std::fs::read_to_string(&package_config_path) {
            //         // Manual parsing preserved from previous version
            //         let mut link_paths: Vec<String> = Vec::new();
            //         let mut libs: Vec<String> = Vec::new();

            //         for line in contents.lines() {
            //             if line.starts_with("Libs:") {
            //                 let rest = line.trim_start_matches("Libs:").trim();
            //                 for token in rest.split_whitespace() {
            //                     if token.starts_with("-L") {
            //                         let mut path = token.trim_start_matches("-L").to_string();
            //                         if path.contains("${prefix}") {
            //                             path = path.replace("${prefix}", &cmake_install_dir);
            //                         }
            //                         if path.contains("${libdir}") {
            //                             let libdir = if build_profile == "debug" {
            //                                 format!("{}/debug/lib", cmake_install_dir)
            //                             } else {
            //                                 format!("{}/lib", cmake_install_dir)
            //                             };
            //                             path = path.replace("${libdir}", &libdir);
            //                         }
            //                         let path = path.replace("\\", "/");
            //                         link_paths.push(path.clone());
            //                     } else if token.starts_with("-l") {
            //                         let lib = token.trim_start_matches("-l").to_string();
            //                         libs.push(lib);
            //                     }
            //                 }
            //             }
            //         }

            //         let fallback_lib = format!("{}/lib", cmake_install_dir).replace("\\", "/");
            //         let fallback_debug_lib =
            //             format!("{}/debug/lib", cmake_install_dir).replace("\\", "/");
            //         link_paths.push(fallback_lib.clone());
            //         link_paths.push(fallback_debug_lib.clone());

            //         let mut emitted = std::collections::HashSet::new();
            //         for p in &link_paths {
            //             if emitted.insert(p.clone()) {
            //                 println!("cargo:warning=link path: {}", p);
            //                 println!("cargo:rustc-link-search=native={}", p);
            //             }
            //         }

            //         for lib in &libs {
            //             println!("cargo:warning=link lib: {}", lib);
            //             let filename = format!("{}.lib", lib);
            //             let mut found = false;
            //             for p in &link_paths {
            //                 let candidate = Path::new(p).join(&filename);
            //                 if candidate.exists() {
            //                     found = true;
            //                     break;
            //                 }
            //             }
            //             if !found {
            //                 println!(
            //                     "cargo:warning=Skipping link for '{}': {} not found in link paths",
            //                     lib, filename
            //                 );
            //                 continue;
            //             }
            //             if build_profile == "debug" {
            //                 println!("cargo:rustc-link-lib=dylib={}", lib);
            //             } else {
            //                 println!("cargo:rustc-link-lib=static={}", lib);
            //             }
            //         }
            //     }
            // } else {
            //     println!(
            //         "cargo:warning=Pkg-config file not found at {}",
            //         package_config_path.display()
            //     );
            // }
        }
    }

    // Also add conventional install lib directories as fallback so the
    // linker can find import/static libraries regardless of how the pkg-config
    // file was generated. This helps when the import library (by2.lib) is
    // placed in `${prefix}/lib` while the pkg-config references `${prefix}/debug/lib`.
    let fallback_lib = format!("{}/lib", cmake_install_dir);
    let fallback_debug_lib = format!("{}/debug/lib", cmake_install_dir);
    println!(
        "cargo:warning=Adding fallback link search: {}",
        fallback_lib
    );
    println!(
        "cargo:rustc-link-search=native={}",
        fallback_lib.replace("\\", "/")
    );
    println!(
        "cargo:warning=Adding fallback link search: {}",
        fallback_debug_lib
    );
    println!(
        "cargo:rustc-link-search=native={}",
        fallback_debug_lib.replace("\\", "/")
    );

    // Copy any installed DLLs into the test runtime directory so the
    // test harness can find them at runtime. On Windows the loader looks
    // in the executable directory and PATH. Cargo places test binaries
    // under <workspace_root>/target/<profile>/deps so copy DLLs there.
    let workspace_root = get_workspace_root();
    let runtime_deps_dir = workspace_root
        .join("target")
        .join(&build_profile)
        .join("deps");

    // Common install bin directories to check
    let bin_dirs = vec![
        PathBuf::from(format!("{}/bin", cmake_install_dir)),
        PathBuf::from(format!("{}/debug/bin", cmake_install_dir)),
    ];

    // Ensure the runtime deps directory exists
    if let Err(e) = std::fs::create_dir_all(&runtime_deps_dir) {
        println!(
            "cargo:warning=Failed to create runtime deps dir {}: {}",
            runtime_deps_dir.display(),
            e
        );
    }

    for bin in bin_dirs {
        if !bin.exists() {
            continue;
        }
        if let Ok(entries) = std::fs::read_dir(&bin) {
            for entry in entries.flatten() {
                let path = entry.path();
                if let Some(ext) = path.extension()
                    && ext.to_string_lossy().eq_ignore_ascii_case("dll")
                {
                    let file_name = path.file_name().unwrap();
                    let dest = runtime_deps_dir.join(file_name);
                    // Copy the DLL to the runtime deps dir
                    if let Err(e) = std::fs::copy(&path, &dest) {
                        println!(
                            "cargo:warning=Failed to copy DLL {} -> {}: {}",
                            path.display(),
                            dest.display(),
                            e
                        );
                    } else {
                        println!(
                            "cargo:warning=Copied DLL {} -> {}",
                            path.display(),
                            dest.display()
                        );
                    }
                }
            }
        }
    }

    // // Configure cxx build: include C++ headers from the ccore source dir and vcpkg include
    // Configure cxx build: compile the cxx-generated glue so the bridge symbols
    // (e.g. by2$cxxbridge1$ccore_add) are available at link time. We don't
    // compile the ccore implementation here because it's provided by the CMake
    // built/static library (installed/lib/...).
    // let ccore_include = workspace_root.join("src").join("ccore");

    // On Windows/MSVC ensure the cxx bridge is compiled with the same CRT and
    // iterator-debug settings as the prebuilt C++ libraries produced by our
    // CMake workflow. The CMake debug install uses MDd and _ITERATOR_DEBUG_LEVEL=2.
    // We avoid forcing MSVC debug CRT flags here. The build maps CMake to
    // produce Release/RelWithDebInfo install artifacts to keep CRT and
    // iterator settings consistent across the C/C++ and Rust parts.

    // Compile only the cxx-generated glue. The ccore symbols come from the
    // prebuilt ccore.lib which we already tell rustc to link above.

    // The cxx build produces a static library named `cxxbridge1` (and a
    // corresponding import/static archive) in the build output directory. On
    // Windows/MSVC the file is `cxxbridge1.lib`. Ensure rustc links it.
    // println!("cargo:warning=Ensuring linker links the cxx bridge library: cxxbridge1");
    // println!("cargo:rustc-link-lib=static=cxxbridge1");

    // // Re-run build if the C++ header/source changes
    // println!(
    //     "cargo:rerun-if-changed={}",
    //     workspace_root.join("src/ccore/ccore/ccore.hpp").display()
    // );
}
