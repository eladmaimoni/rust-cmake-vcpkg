use std::env;
use std::path::Path;
use std::path::PathBuf;
use std::process::Command;

const CMAKE_INSTALLED_DIR: &str = "installed";
const VCPKG_INSTALLED_DIR: &str = "vcpkg_installed";

#[derive(Debug)]
struct BuildDetails {
    /// The CMake preset to use for this build (e.g. "vs2022r-install")
    cmake_preset_workflow: &'static str,
    vcpkg_installed_include_dir: PathBuf,
    vcpkg_installed_lib_dir: PathBuf,
    cmake_installed_include_dir: PathBuf,
    cmake_installed_lib_dir: PathBuf,
}

fn deduce_build_details(target_os: &str, target_arch: &str, build_profile: &str) -> BuildDetails {
    match target_os {
        "windows" => {
            let vcpkg_triplet = match target_arch {
                "x86_64" => "x64-windows-static-md",
                _ => {
                    panic!("Unsupported target architecture: {}", target_arch);
                }
            };

            // NOTE: The C/C++ objects produced by the cxx crate and its build
            // infrastructure are typically compiled with the release CRT
            // settings. Mixing MSVC debug CRT (MDd) and release CRT (MD) will
            // trigger LNK2038 mismatch errors. To avoid this when running
            // `cargo test` (PROFILE=debug) we map the debug profile to the
            // CMake RelWithDebInfo install preset so the installed C++ libs
            // use release-like runtime settings and match the cxx bridge.
            let (cmake_preset_workflow, cmake_lib_path, vcpkg_lib_path) = match build_profile {
                // Build using the release install preset. The project's
                // installation step places artifacts under lib/Release (see
                // cmake/installation.cmake which maps RelWithDebInfo -> Release
                // for install layout), so use lib/Release here.
                "debug" => ("windows-release-install", "lib/Release", "lib"),
                "release" => ("windows-release-install", "lib/Release", "lib"),
                _ => {
                    panic!("Unsupported build profile: {}", build_profile);
                }
            };

            let vcpkg_installed_triplet_path =
                PathBuf::from(VCPKG_INSTALLED_DIR).join(vcpkg_triplet);

            BuildDetails {
                cmake_preset_workflow,
                vcpkg_installed_include_dir: vcpkg_installed_triplet_path.join("include"),
                vcpkg_installed_lib_dir: vcpkg_installed_triplet_path.join(vcpkg_lib_path),
                cmake_installed_include_dir: PathBuf::from(CMAKE_INSTALLED_DIR).join("include"),
                cmake_installed_lib_dir: PathBuf::from(CMAKE_INSTALLED_DIR).join(cmake_lib_path),
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
    let workspace_root = current_directory
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf();

    workspace_root
}

fn find_libraries_in_dir(lib_dir: &Path) -> Vec<String> {
    let mut libs = Vec::new();
    if lib_dir.exists() {
        for entry in lib_dir.read_dir().unwrap() {
            let entry = entry.unwrap();
            let entry_path = entry.path();
            // check if it's a file and has an extension ".lib" or ".a"
            if entry_path.is_file()
                && (entry_path.extension() == Some("lib".as_ref())
                    || entry_path.extension() == Some("a".as_ref()))
            {
                // Extract the library name (file stem). For example, "ccore.lib" -> "ccore".
                if let Some(stem) = entry_path.file_stem().and_then(|s| s.to_str()) {
                    // On some platforms static libs are named "libfoo.a". Since this
                    // build script currently only supports Windows targets, we don't
                    // strip a "lib" prefix here, but if non-windows is added later
                    // we may want to remove a leading "lib".
                    libs.push(stem.to_string());
                }
            }
        }
    }
    libs
}

fn main() {
    // let out_dir = env::var("OUT_DIR").unwrap();
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let build_profile = std::env::var("PROFILE").unwrap();

    let build_details = deduce_build_details(&target_os, &target_arch, &build_profile);
    let workspace_root = get_workspace_root();

    println!(
        "cargo:warning=Building for OS={target_os}, ARCH={target_arch}, PROFILE={build_profile}"
    );

    println!("cargo:rerun-if-changed=build.rs");

    let status = Command::new("cmake")
        .arg("--workflow")
        .arg(format!("--preset={}", build_details.cmake_preset_workflow))
        .current_dir(&workspace_root)
        .status()
        .expect("failed to run cmake configure");
    if !status.success() {
        panic!("cmake configure failed");
    }

    println!("cargo:warning=Build details: {:#?}", build_details);

    let vcpkg_installed_lib_dir = workspace_root.join(&build_details.vcpkg_installed_lib_dir);
    let cmake_installed_lib_dir = workspace_root.join(&build_details.cmake_installed_lib_dir);
    // let vcpkg_installed_include_dir =
    //     workspace_root.join(&build_details.vcpkg_installed_include_dir);
    println!(
        "cargo:rustc-link-search=native={}",
        vcpkg_installed_lib_dir.display()
    );
    println!(
        "cargo:rustc-link-search=native={}",
        cmake_installed_lib_dir.display()
    );

    let cmake_libraries = find_libraries_in_dir(&cmake_installed_lib_dir);
    let vcpkg_libraries = find_libraries_in_dir(&vcpkg_installed_lib_dir);

    for lib in &cmake_libraries {
        println!("cargo:warning=Linking to CMake lib (name): {}", lib);
        println!("cargo:rustc-link-lib=static={}", lib);
    }

    for lib in &vcpkg_libraries {
        println!("cargo:warning=Linking to vcpkg lib (name): {}", lib);
        println!("cargo:rustc-link-lib=static={}", lib);
    }

    // // Configure cxx build: include C++ headers from the ccore source dir and vcpkg include
    // Configure cxx build: compile the cxx-generated glue so the bridge symbols
    // (e.g. by2$cxxbridge1$ccore_add) are available at link time. We don't
    // compile the ccore implementation here because it's provided by the CMake
    // built/static library (installed/lib/...).
    let ccore_include = workspace_root.join("src").join("ccore");
    let vcpkg_installed_include_dir =
        workspace_root.join(&build_details.vcpkg_installed_include_dir);
    let mut bridge = cxx_build::bridge("src/lib.rs");
    bridge.include(&ccore_include);
    bridge.include(&vcpkg_installed_include_dir);

    // On Windows/MSVC ensure the cxx bridge is compiled with the same CRT and
    // iterator-debug settings as the prebuilt C++ libraries produced by our
    // CMake workflow. The CMake debug install uses MDd and _ITERATOR_DEBUG_LEVEL=2.
    // We avoid forcing MSVC debug CRT flags here. The build maps CMake to
    // produce Release/RelWithDebInfo install artifacts to keep CRT and
    // iterator settings consistent across the C/C++ and Rust parts.

    // Compile only the cxx-generated glue. The ccore symbols come from the
    // prebuilt ccore.lib which we already tell rustc to link above.
    bridge.compile("app-cxx-bridge");

    // The cxx build produces a static library named `cxxbridge1` (and a
    // corresponding import/static archive) in the build output directory. On
    // Windows/MSVC the file is `cxxbridge1.lib`. Ensure rustc links it.
    println!("cargo:warning=Ensuring linker links the cxx bridge library: cxxbridge1");
    // println!("cargo:rustc-link-lib=static=cxxbridge1");

    // // Re-run build if the C++ header/source changes
    // println!(
    //     "cargo:rerun-if-changed={}",
    //     workspace_root.join("src/ccore/ccore/ccore.hpp").display()
    // );
}
