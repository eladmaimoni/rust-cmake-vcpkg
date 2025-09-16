

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

generate_pkgconfig(by2)
