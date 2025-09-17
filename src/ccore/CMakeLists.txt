

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
setup_target_includes_for_install(ccore ccore)
add_target_to_global_export_set(ccore)


# setup_target_for_install(
#     ccore
#     ccore
# )


