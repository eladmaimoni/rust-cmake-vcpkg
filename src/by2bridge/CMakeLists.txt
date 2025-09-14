

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


# get_library_names_and_paths(ccore_deps ccore_libs ccore_paths)

# message(STATUS "ZZZ: ccore_deps=${ccore_deps}")
# message(STATUS "ZZZ: ccore_libs=${ccore_libs}")
# message(STATUS "ZZZ: ccore_paths=${ccore_paths}")

# generate_pkgconfig(ccore VERSION 1.2.3 DESCRIPTION "Cool Core Library")

get_target_link_dependencies(by2bridge dependencies)
# Build dependency manifests directly from resolved target properties (config-aware)
set(_ccore_debug_libs "")
set(_ccore_release_libs "")
set(_ccore_debug_dirs "")
set(_ccore_release_dirs "")



# Explicitly query both configs for each target dep
foreach(dep IN LISTS dependencies)
    if(TARGET ${dep})
        foreach(_cfg Debug RelWithDebInfo)
            string(TOUPPER "${_cfg}" _CFG_UP)
            set(_loc "")
            foreach(prop IMPORTED_IMPLIB_${_CFG_UP} IMPORTED_LOCATION_${_CFG_UP} IMPORTED_IMPLIB IMPORTED_LOCATION)
                get_target_property(_try ${dep} ${prop})
                if(NOT _loc AND _try)
                    set(_loc "${_try}")
                endif()
            endforeach()
            # If RelWithDebInfo not found, fall back to RELEASE artifacts (vcpkg provides only Release/Debug)
            if(_cfg STREQUAL RelWithDebInfo AND NOT _loc)
                foreach(prop IMPORTED_IMPLIB_RELEASE IMPORTED_LOCATION_RELEASE IMPORTED_IMPLIB IMPORTED_LOCATION)
                    get_target_property(_try2 ${dep} ${prop})
                    if(NOT _loc AND _try2)
                        set(_loc "${_try2}")
                    endif()
                endforeach()
            endif()
            if(_loc)
                get_filename_component(_dir "${_loc}" DIRECTORY)
                get_filename_component(_name_we "${_loc}" NAME_WE)
                if(_name_we MATCHES "^lib.+" AND NOT _name_we STREQUAL "lib")
                    string(REGEX REPLACE "^lib" "" _name_we "${_name_we}")
                endif()
                if(_cfg STREQUAL Debug)
                    list(FIND _ccore_debug_libs "${_name_we}" _i1)
                    if(_i1 EQUAL -1)
                        list(APPEND _ccore_debug_libs "${_name_we}")
                    endif()
                    list(FIND _ccore_debug_dirs "${_dir}" _i2)
                    if(_i2 EQUAL -1)
                        list(APPEND _ccore_debug_dirs "${_dir}")
                    endif()
                else()
                    list(FIND _ccore_release_libs "${_name_we}" _i3)
                    if(_i3 EQUAL -1)
                        list(APPEND _ccore_release_libs "${_name_we}")
                    endif()
                    list(FIND _ccore_release_dirs "${_dir}" _i4)
                    if(_i4 EQUAL -1)
                        list(APPEND _ccore_release_dirs "${_dir}")
                    endif()
                endif()
            endif()
        endforeach()
    elseif(dep MATCHES "^-l(.+)$")
        string(REGEX REPLACE "^-l" "" _lname "${dep}")
        list(APPEND _ccore_debug_libs "${_lname}")
        list(APPEND _ccore_release_libs "${_lname}")
    endif()
endforeach()

list(REMOVE_DUPLICATES _ccore_debug_libs)
list(REMOVE_DUPLICATES _ccore_release_libs)
list(REMOVE_DUPLICATES _ccore_debug_dirs)
list(REMOVE_DUPLICATES _ccore_release_dirs)

set(_debug_manifest "${CMAKE_CURRENT_BINARY_DIR}/ccore-dependencies-Debug.txt")
set(_rel_manifest   "${CMAKE_CURRENT_BINARY_DIR}/ccore-dependencies-RelWithDebInfo.txt")

file(WRITE  "${_debug_manifest}" "# ccore dependency manifest (configuration: Debug)\n# Libraries\n")
foreach(n IN LISTS _ccore_debug_libs)
    file(APPEND "${_debug_manifest}" "${n}\n")
endforeach()
file(APPEND "${_debug_manifest}" "# Library Paths\n")
foreach(d IN LISTS _ccore_debug_dirs)
    file(APPEND "${_debug_manifest}" "${d}\n")
endforeach()

file(WRITE  "${_rel_manifest}" "# ccore dependency manifest (configuration: RelWithDebInfo)\n# Libraries\n")
foreach(n IN LISTS _ccore_release_libs)
    file(APPEND "${_rel_manifest}" "${n}\n")
endforeach()
file(APPEND "${_rel_manifest}" "# Library Paths\n")
foreach(d IN LISTS _ccore_release_dirs)
    file(APPEND "${_rel_manifest}" "${d}\n")
endforeach()

install(FILES "${_debug_manifest}" DESTINATION lib/Debug RENAME ccore-dependencies-Debug.txt)
install(FILES "${_rel_manifest}"   DESTINATION lib/RelWithDebInfo RENAME ccore-dependencies-RelWithDebInfo.txt)
