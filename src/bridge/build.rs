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

#[derive(PartialEq, Eq, Debug, Clone, Copy)]
enum TargetOS {
    Windows,
    Linux,
    MacOS,
}

fn deduce_target_os(target_os: &str) -> TargetOS {
    match target_os {
        "windows" => TargetOS::Windows,
        "linux" => TargetOS::Linux,
        "macos" => TargetOS::MacOS,
        _ => panic!("Unsupported target OS: {}", target_os),
    }
}

fn deduce_build_details(
    target_os: TargetOS,
    _target_arch: &str,
    build_profile: &str,
) -> BuildDetails {
    match target_os {
        TargetOS::Windows => {
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
        TargetOS::Linux => {
            let (cmake_config_preset, cmake_build_preset, _package_config_path) =
                match build_profile {
                    "debug" => (
                        "clang-20-debug",
                        "clang-20-debug-install",
                        "debug/lib/pkgconfig/by2.pc",
                    ),
                    "release" => (
                        "clang-20-release",
                        "clang-20-release-install",
                        "lib/pkgconfig/by2.pc",
                    ),
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
            panic!("Unsupported target OS: {:?}", target_os);
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

// Credit to ssrlive for this function
// Taken from the following issue: https://github.com/rust-lang/cargo/issues/9661#issuecomment-1722358176
fn get_cargo_target_dir() -> Result<std::path::PathBuf, Box<dyn std::error::Error>> {
    let out_dir = std::path::PathBuf::from(std::env::var("OUT_DIR")?);
    let profile = std::env::var("PROFILE")?;
    let mut target_dir = None;
    let mut sub_path = out_dir.as_path();
    while let Some(parent) = sub_path.parent() {
        if parent.ends_with(&profile) {
            target_dir = Some(parent);
            break;
        }
        sub_path = parent;
    }
    let target_dir = target_dir.ok_or("not found")?;
    Ok(target_dir.to_path_buf())
}

fn main() {
    let out_dir = env::var("OUT_DIR").unwrap().replace('\\', "/");
    let target_os = deduce_target_os(&std::env::var("CARGO_CFG_TARGET_OS").unwrap());
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let build_profile = std::env::var("PROFILE").unwrap();

    let build_details = deduce_build_details(target_os, &target_arch, &build_profile);
    let workspace_root = get_workspace_root();

    println!(
        "cargo:warning=Building for OS={:?}, ARCH={}, PROFILE={}, out_dir={}",
        target_os, target_arch, build_profile, out_dir
    );

    println!("cargo:rerun-if-changed=build.rs");

    // Ensure the build script is re-run whenever any file under src/by2

    // Watch the by2 and ccore source trees in the workspace so changes there
    // will cause the bridge crate to rebuild.
    let by2_dir = workspace_root.join("src").join("by2");
    let ccore_dir = workspace_root.join("src").join("ccore");
    println!("cargo:rerun-if-changed={}", by2_dir.display());
    println!("cargo:rerun-if-changed={}", ccore_dir.display());

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
        // Attributes for the generated bindings are applied in the
        // surrounding module (src/bridge/src/lib.rs). Avoid emitting
        // attributes here to keep the generated file as a plain include.
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
            let mut emitted_link_search_paths = std::collections::HashSet::new();
            for path in &library.link_paths {
                let p = path.to_string_lossy().replace("\\", "/");
                if emitted_link_search_paths.insert(p.clone()) {
                    println!("cargo:rustc-link-search=native={}", p);
                }
            }

            // Process libs: promote path-like tokens to -L, otherwise emit -l
            // For non-path tokens, decide static vs dynamic linking by
            // checking whether a static archive exists in the probe's
            // link_paths. This avoids requesting static linking for
            // system libraries like libstdc++ when a static archive is
            // not available on the system.
            let mut emitted_libs = std::collections::HashSet::new();
            for lib in &library.libs {
                let name = lib.to_string();
                if emitted_libs.insert(name.clone()) {
                    // Determine whether a static archive exists under any of the
                    // pkg-config link paths. On Windows look for <name>.lib, on
                    // Unix look for lib<name>.a. If found, prefer static for
                    // release builds; otherwise fall back to dynamic linking.
                    let mut has_static = false;
                    for search_path in &emitted_link_search_paths {
                        let path = PathBuf::from(search_path);
                        let candidate = if target_os == TargetOS::Windows {
                            path.join(format!("{}.lib", name))
                        } else {
                            path.join(format!("lib{}.a", name))
                        };
                        if candidate.exists() {
                            has_static = true;
                            break;
                        }
                    }

                    if has_static {
                        println!("cargo:rustc-link-lib=static={}", name);
                    } else {
                        // Fall back to dynamic linking when static archive
                        // isn't available (e.g. system stdc++).
                        println!("cargo:rustc-link-lib=dylib={}", name);
                    }
                }
            }
        }
        Err(e) => {
            println!("cargo:warning=pkg-config probe failed: {}", e);
            panic!("pkg-config probe failed: {}", e);
        }
    }

    /*
    links regarding dll search path:
    https://doc.rust-lang.org/cargo/reference/build-scripts.html#rustc-link-search
    https://doc.rust-lang.org/cargo/reference/environment-variables.html#dynamic-library-paths


    On windows debug builds, we can't link the debug crt dynamically and hence may conflict with rust's crt linkage.
    To avoid this, windows debug builds result in a single dll with all dependencies statically linked, including the c++ runtime.

    we copy any installed DLLs into the test runtime directory so the
    test harness can find them at runtime. On Windows the loader looks
    in the executable directory and PATH. Cargo places test binaries
    under <workspace_root>/target/<profile>/deps so copy DLLs there.
     */

    let binary_dir = get_cargo_target_dir().unwrap();
    let runtime_deps_dir = binary_dir.join("deps");

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
                if let Some(ext) = path.extension() {
                    if ext.to_string_lossy().eq_ignore_ascii_case("dll") {
                        let file_name = path.file_name().unwrap();
                        let dest1 = runtime_deps_dir.join(file_name);
                        let dest2 = binary_dir.join(file_name);

                        std::fs::copy(&path, &dest1).unwrap_or_else(|e| {
                            println!(
                                "cargo:warning=Failed to copy DLL {} -> {}: {}",
                                path.display(),
                                dest1.display(),
                                e
                            );
                            0
                        });
                        std::fs::copy(&path, &dest2).unwrap_or_else(|e| {
                            println!(
                                "cargo:warning=Failed to copy DLL {} -> {}: {}",
                                path.display(),
                                dest1.display(),
                                e
                            );
                            0
                        });
                    }
                }
            }
        }
    }
}
