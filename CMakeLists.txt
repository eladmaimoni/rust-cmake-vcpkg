
cmake_minimum_required(VERSION 3.25)

set(LOG_SEPARATOR "===============================================================")
project(by2)
message(STATUS "${LOG_SEPARATOR}")
message(STATUS "Project: ${PROJECT_NAME}")
message(STATUS "${LOG_SEPARATOR}")

option(BY2_SHARED "Build one shared library instead of per-lib static libraries" OFF)

if(BY2_SHARED)
    message(STATUS "Building shared library")
    # Use position-independent code when building shared (dynamic) libraries,
    # or when building static libraries intended to be linked into shared libraries.
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
    # set_target_properties(alpha PROPERTIES POSITION_INDEPENDENT_CODE ON)
endif()


include(cmake/version_details.cmake)
include(cmake/compiler_flags.cmake)
include(cmake/global_setup.cmake)
include(cmake/debugging_utils.cmake)
include(cmake/dynamic_library_link.cmake)
include(cmake/code_analysis.cmake)
include(cmake/target_helpers.cmake)
include(cmake/installation.cmake)






include(GNUInstallDirs)
# the export set that collects all targets to be exported
# using the install(TARGETS ... EXPORT ...) command
set(export_set "${PROJECT_NAME}_exported_targets")
add_target_to_global_export_set(by2_default_compiler_flags)
# Use GNU install dirs for sensible defaults (CMAKE_INSTALL_LIBDIR / INCLUDEDIR)

find_package(Eigen3 CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)

add_subdirectory(src)


# Project-level installs (once per project).
install(EXPORT "${export_set}"
  NAMESPACE "${PROJECT_NAME}::"
  FILE "${PROJECT_NAME}Targets.cmake"
  DESTINATION "${INSTALL_LIBDIR}/cmake/${PROJECT_NAME}"
)