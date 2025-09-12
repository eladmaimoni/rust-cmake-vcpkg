use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");

    let current_directory = env::current_dir().unwrap(); // the build script’s current directory is the source directory of the build script’s package

    // Determine workspace root (two levels up from this crate: .../src/app)
    // let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let workspace_root = current_directory
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf();

    // Run cmake configure and build for the vs2022 preset. This builds the ccore target.
    // If the user already built the CMake project externally, these commands are fast/no-op.
    let status = Command::new("cmake")
        .arg("--preset=vs2022")
        .current_dir(&workspace_root)
        .status()
        .expect("failed to run cmake configure");
    if !status.success() {
        panic!("cmake configure failed");
    }

    let status = Command::new("cmake")
        .arg("--build")
        .arg("--preset=vs2022r")
        .arg("--target")
        .arg("ccore")
        .current_dir(&workspace_root)
        .status()
        .expect("failed to run cmake build");
    if !status.success() {
        panic!("cmake build failed");
    }

    // Find which CMake config folder actually contains the built ccore.lib
    let mut built_lib_dir = workspace_root
        .join("build")
        .join("vs2022")
        .join("src")
        .join("ccore");
    let candidates = ["Debug", "RelWithDebInfo", "Release"];
    let mut found = false;
    for c in &candidates {
        let p = built_lib_dir.join(c);
        if p.join("ccore.lib").exists() {
            built_lib_dir = p;
            found = true;
            break;
        }
    }
    if !found {
        // fallback: use Debug directory (may still exist)
        built_lib_dir = workspace_root
            .join("build")
            .join("vs2022")
            .join("src")
            .join("ccore")
            .join("Debug");
    }

    // We will build the ccore sources into the bridge rather than link the prebuilt library
    // (this avoids potential ABI/linking mismatches). Keep the build tree discovery above
    // for informational/debugging reasons.
    println!(
        "cargo:warning=ccore built lib dir = {}",
        built_lib_dir.display()
    );

    // vcpkg-installed libraries (project includes a vcpkg_installed folder)
    // Prefer the static-md triplet (exists in the repo) and add include/lib paths.
    let vcpkg_root = workspace_root
        .join("vcpkg_installed")
        .join("x64-windows-static-md");
    let vcpkg_include = vcpkg_root.join("include");
    let vcpkg_lib = vcpkg_root.join("lib");
    println!("cargo:rustc-link-search=native={}", vcpkg_lib.display());
    // Link spdlog (vcpkg provides spdlog.lib)
    println!("cargo:rustc-link-lib=static=spdlog");
    // spdlog depends on fmt; link fmt as well
    println!("cargo:rustc-link-lib=static=fmt");

    // Configure cxx build: include C++ headers from the ccore source dir and vcpkg include
    let mut bridge = cxx_build::bridge("src/lib.rs");
    let ccore_include = workspace_root.join("src").join("ccore");
    bridge.include(&ccore_include);
    bridge.include(&vcpkg_include);
    // Add the ccore cpp source so it's compiled into the bridge
    let ccore_cpp = workspace_root.join("src").join("ccore").join("ccore.cpp");
    bridge.file(ccore_cpp);

    // Compile the bridge (this will compile the cxx-generated glue and ccore.cpp)
    bridge.compile("app-cxx-bridge");

    // Re-run build if the C++ header/source changes
    println!(
        "cargo:rerun-if-changed={}",
        workspace_root.join("src/ccore/ccore/ccore.hpp").display()
    );
}
