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

            let (cmake_preset_workflow, cmake_lib_path, vcpkg_lib_path) = match build_profile {
                "debug" => ("windows-debug-install", "lib/Debug", "debug/lib"),
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
            if entry.path().is_file() {
                libs.push(entry.path().display().to_string());
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
    let vcpkg_installed_include_dir =
        workspace_root.join(&build_details.vcpkg_installed_include_dir);
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
        println!("cargo:warning=Linking to CMake lib: {}", lib);
        println!("cargo:rustc-link-lib=static={}", lib);
    }

    for lib in &vcpkg_libraries {
        println!("cargo:rustc-link-lib=static={}", lib);
    }

    // // Configure cxx build: include C++ headers from the ccore source dir and vcpkg include
    // let ccore_include = workspace_root.join("src").join("ccore");
    // let mut bridge = cxx_build::bridge("src/lib.rs");
    // bridge.include(&ccore_include);
    // bridge.include(&vcpkg_installed_include_dir);
    // // Add the ccore cpp source so it's compiled into the bridge
    // let ccore_cpp = workspace_root.join("src").join("ccore").join("ccore.cpp");
    // bridge.file(ccore_cpp);

    // // Compile the bridge (this will compile the cxx-generated glue and ccore.cpp)
    // bridge.compile("app-cxx-bridge");

    // // Re-run build if the C++ header/source changes
    // println!(
    //     "cargo:rerun-if-changed={}",
    //     workspace_root.join("src/ccore/ccore/ccore.hpp").display()
    // );
}
