

add_library(
    by2bridge
    by2/by2.h
    by2.cpp
)

target_link_libraries(
    by2bridge
    PUBLIC
    ccore
)

setup_target_for_install(
    by2bridge
    by2
)