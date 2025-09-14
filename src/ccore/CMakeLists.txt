

add_library(
    ccore
    STATIC
    ccore/ccore.hpp
    ccore.cpp
)

target_link_libraries(
    ccore
    PUBLIC
    spdlog::spdlog
)

setup_target_for_install(
    ccore
    ccore
)

get_target_link_dependencies(ccore ccore_deps)
get_library_names_and_paths(ccore_deps ccore_libs ccore_paths)

message(STATUS "ZZZ: ccore_deps=${ccore_deps}")
message(STATUS "ZZZ: ccore_libs=${ccore_libs}")
message(STATUS "ZZZ: ccore_paths=${ccore_paths}")

generate_pkgconfig(ccore VERSION 1.2.3 DESCRIPTION "Cool Core Library")

# target_include_directories(
# ccore
# PUBLIC
# INTERFACE
# $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/> # when using within the build, the include directories is the current source dir
# $<INSTALL_INTERFACE:include/> # when used from installation folder, the include directories is the exported path
# )