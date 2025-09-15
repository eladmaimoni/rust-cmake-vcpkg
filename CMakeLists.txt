
cmake_minimum_required(VERSION 3.25)

include(cmake/version_details.cmake)
include(cmake/compiler_flags.cmake)
include(cmake/global_setup.cmake)
include(cmake/debugging_utils.cmake)
include(cmake/dynamic_library_link.cmake)
include(cmake/code_analysis.cmake)
include(cmake/target_helpers.cmake)
include(cmake/installation.cmake)

set(LOG_SEPARATOR "===============================================================")


project(by2)

message(STATUS "${LOG_SEPARATOR}")
message(STATUS "Project: ${PROJECT_NAME}")
message(STATUS "${LOG_SEPARATOR}")

include(GNUInstallDirs)
# the export set that collects all targets to be exported
# using the install(TARGETS ... EXPORT ...) command
set(export_set "${PROJECT_NAME}_exported_targets")

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