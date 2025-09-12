

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

# target_include_directories(
# ccore
# PUBLIC
# INTERFACE
# $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/> # when using within the build, the include directories is the current source dir
# $<INSTALL_INTERFACE:include/> # when used from installation folder, the include directories is the exported path
# )