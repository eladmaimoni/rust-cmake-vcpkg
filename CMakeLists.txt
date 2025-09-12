
cmake_minimum_required(VERSION 3.25)

include(cmake/version_details.cmake)
include(cmake/compiler_flags.cmake)
include(cmake/global_setup.cmake)
include(cmake/debugging_utils.cmake)
include(cmake/dynamic_library_link.cmake)
include(cmake/code_analysis.cmake)
include(cmake/target_helpers.cmake)
include(cmake/installation.cmake)

project(by2)

find_package(Eigen3 CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)

add_subdirectory(src)