

set(BY2_LIBRARY_TYPE STATIC)
set(BY2_LIBRARY_LINKAGE PUBLIC)

if(BY2_SHARED)
    set(BY2_LIBRARY_TYPE SHARED)
    set(BY2_LIBRARY_LINKAGE PRIVATE)
endif()

add_library(
    by2
    ${BY2_LIBRARY_TYPE}
    by2/by2.h
    by2.cpp
)

# Define export/import related compile definitions when building a shared lib
target_compile_definitions(
    by2
    PRIVATE
        $<$<BOOL:${BY2_SHARED}>:BY2_BUILD_SHARED>
    PUBLIC
        $<$<BOOL:${BY2_SHARED}>:BY2_USE_SHARED>
)

target_link_libraries(
    by2
    ${BY2_LIBRARY_LINKAGE}
    ccore
    PRIVATE
    by2_default_compiler_flags
)

set_default_library_properties(by2)

setup_target_includes_for_install(by2 by2)
add_target_to_global_export_set(by2)

generate_pkgconfig(by2)
