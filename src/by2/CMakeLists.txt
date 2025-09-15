

add_library(
    by2
    by2/by2.h
    by2.cpp
)

target_link_libraries(
    by2
    PUBLIC
    ccore
)

setup_target_includes_for_install(by2 by2)
add_target_to_global_export_set(by2)


# get_library_names_and_paths(ccore_deps ccore_libs ccore_paths)

# message(STATUS "ZZZ: ccore_deps=${ccore_deps}")
# message(STATUS "ZZZ: ccore_libs=${ccore_libs}")
# message(STATUS "ZZZ: ccore_paths=${ccore_paths}")

# generate_pkgconfig(ccore VERSION 1.2.3 DESCRIPTION "Cool Core Library")



install_dependency_manifest_for_target("by2")


# At install time, include it and print IMPORTED_* properties.
# install(CODE "install_dependency_manifest_for_target(\"by2\")")

# install(CODE [=[
#     message(STATUS "Running install step for by2 manifest")
#     message(STATUS "CMAKE_SOURCE_DIR=${CMAKE_SOURCE_DIR}")
#     message(STATUS "PROJECT_SOURCE_DIR=${PROJECT_SOURCE_DIR}")
#     message(STATUS "CMAKE_PROJECT_SOURCE_DIR=${CMAKE_PROJECT_SOURCE_DIR}")
#     include("C:/workspace/rust-cmake-vcpkg/cmake/target_helpers.cmake")
#     include("C:/workspace/rust-cmake-vcpkg/cmake/installation.cmake")
#     # include("${CMAKE_PROJECT_SOURCE_DIR}/cmake/target_helpers.cmake")
#     # include("${CMAKE_PROJECT_SOURCE_DIR}/cmake/installation.cmake")
#     install_dependency_manifest_for_target("by2")
# ]=])