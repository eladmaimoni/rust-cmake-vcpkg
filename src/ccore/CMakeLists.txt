

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
    PRIVATE
    by2_default_compiler_flags
)

set_default_library_properties(ccore)

# Always setup include directories for the target so other targets that
# link to `ccore` (for example `by2`) can consume its INTERFACE include
# directories during the build. Only skip installation/export when
# BY2_SHARED=ON because the standalone static `ccore` shouldn't be
# installed when building a single shared `by2` library.
setup_target_includes_for_install(ccore ccore)

if(NOT BY2_SHARED)
    add_target_to_global_export_set(ccore)
endif()

# setup_target_for_install(
# ccore
# ccore
# )
