use std::env;
use std::path::Path;
use std::path::PathBuf;
use std::process::Command;

const CMAKE_INSTALLED_DIR: &str = "installed";
const VCPKG_INSTALLED_DIR: &str = "vcpkg_installed";

#[derive(Debug)]
struct BuildDetails {
    /// The CMake preset to use for this build (e.g. "vs2022r-install")
    cmake_config_preset: &'static str,
    cmake_build_preset: &'static str,
    package_config_path: PathBuf,
}

fn deduce_build_details(target_os: &str, target_arch: &str, build_profile: &str) -> BuildDetails {
    match target_os {
        "windows" => {
            // NOTE: The C/C++ objects produced by the cxx crate and its build
            // infrastructure are typically compiled with the release CRT
            // settings. Mixing MSVC debug CRT (MDd) and release CRT (MD) will
            // trigger LNK2038 mismatch errors. To avoid this when running
            // `cargo test` (PROFILE=debug) we map the debug profile to the
            // CMake RelWithDebInfo install preset so the installed C++ libs
            // use release-like runtime settings and match the cxx bridge.
            let (cmake_config_preset, cmake_build_preset, package_config_path) = match build_profile
            {
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
                package_config_path: PathBuf::from(&package_config_path),
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

    // The bindgen::Builder is the main entry point
    // to bindgen, and lets you build up options for
    // the resulting bindings.
    let bindings = bindgen::Builder::default()
        // The input header we would like to generate
        // bindings for.
        .header("include/by2.h")
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
