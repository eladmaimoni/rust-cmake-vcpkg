

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


# get_library_names_and_paths(ccore_deps ccore_libs ccore_paths)

# message(STATUS "ZZZ: ccore_deps=${ccore_deps}")
# message(STATUS "ZZZ: ccore_libs=${ccore_libs}")
# message(STATUS "ZZZ: ccore_paths=${ccore_paths}")

# generate_pkgconfig(ccore VERSION 1.2.3 DESCRIPTION "Cool Core Library")

get_target_link_dependencies(by2 dependencies)
# Build dependency manifests directly from resolved target properties (config-aware)
set(debug_libs "")
set(release_libs "")
set(debug_dirs "")
set(release_dirs "")



# Explicitly query both configs for each target dep
foreach(dep IN LISTS dependencies)
    if(TARGET ${dep})
        # this is a cmake target
   


        foreach(build_config Debug Release)
            string(TOUPPER "${build_config}" BUILD_CONFIG)
   
            
        endforeach()

        # IMPORTED_IMPLIB - On DLL platforms, to the location of the ``.lib`` part of the DLL. or the location of the shared library on other platforms.
        # IMPORTED_LOCATION - The location of the actual library file to be linked against.
        get_target_property(imported_implib_release ${dep}  IMPLIB_RELEASE)
        get_target_property(imported_location_release ${dep} IMPORTED_LOCATION_RELEASE)
        get_target_property(imported_implib_debug ${dep} IMPORTED_IMPLIB_DEBUG)
        get_target_property(imported_location_debug ${dep} IMPORTED_LOCATION_DEBUG)


        if (imported_implib_release)
            set(release_location "${imported_implib_release}")
        else()
            set(release_location "${imported_location_release}")
        endif()

        if (imported_implib_debug)
            set(debug_location "${imported_implib_debug}")
        else()
            set(debug_location "${imported_location_debug}")
        endif()

        get_filename_component(debug_dir "${debug_location}" DIRECTORY) # directory
        get_filename_component(debug_lib_name "${debug_location}" NAME_WE) # name without extension

        


        foreach(build_config Debug Release)
            string(TOUPPER "${build_config}" BUILD_CONFIG)
            # for each build config, find the first location among IMPORTED_IMPLIB / IMPORTED_LOCATION
            set(found_lib_location "")
            foreach(prop IMPORTED_IMPLIB_${BUILD_CONFIG} IMPORTED_LOCATION_${BUILD_CONFIG} IMPORTED_IMPLIB IMPORTED_LOCATION)
                get_target_property(possible_lib_location ${dep} ${prop})
                if(NOT found_lib_location AND possible_lib_location)
                    set(found_lib_location "${possible_lib_location}")
                    break()
                endif()
            endforeach()
            if(found_lib_location)
                get_filename_component(lib_directory "${found_lib_location}" DIRECTORY) # directory
                get_filename_component(lib_name_without_extension "${found_lib_location}" NAME_WE) # name without extension
                
                # Strip "lib" prefix if present (e.g. libfoo.so -> foo) for consistency
                if(lib_name_without_extension MATCHES "^lib.+" AND NOT lib_name_without_extension STREQUAL "lib")
                    string(REGEX REPLACE "^lib" "" lib_name_without_extension "${lib_name_without_extension}")
                endif()
                if(build_config STREQUAL Debug)
                    list(FIND debug_libs "${lib_name_without_extension}" _i1)
                    if(_i1 EQUAL -1)
                        list(APPEND debug_libs "${lib_name_without_extension}")
                    endif()
                    list(FIND debug_dirs "${lib_directory}" _i2)
                    if(_i2 EQUAL -1)
                        list(APPEND debug_dirs "${lib_directory}")
                    endif()
                else()
                    list(FIND release_libs "${lib_name_without_extension}" _i3)
                    if(_i3 EQUAL -1)
                        list(APPEND release_libs "${lib_name_without_extension}")
                    endif()
                    list(FIND release_dirs "${lib_directory}" _i4)
                    if(_i4 EQUAL -1)
                        list(APPEND release_dirs "${lib_directory}")
                    endif()
                endif()
            endif()
        endforeach()
    elseif(dep MATCHES "^-l(.+)$")
        # dependency is a raw library dependency
        string(REGEX REPLACE "^-l" "" _lname "${dep}")
        list(APPEND debug_libs "${_lname}")
        list(APPEND release_libs "${_lname}")
    endif()
endforeach()

list(REMOVE_DUPLICATES debug_libs)
list(REMOVE_DUPLICATES release_libs)
list(REMOVE_DUPLICATES debug_dirs)
list(REMOVE_DUPLICATES release_dirs)

set(_debug_manifest "${CMAKE_CURRENT_BINARY_DIR}/ccore-dependencies-Debug.txt")
set(_rel_manifest   "${CMAKE_CURRENT_BINARY_DIR}/ccore-dependencies-RelWithDebInfo.txt")

file(WRITE  "${_debug_manifest}" "# ccore dependency manifest (configuration: Debug)\n# Libraries\n")
foreach(n IN LISTS debug_libs)
    file(APPEND "${_debug_manifest}" "${n}\n")
endforeach()
file(APPEND "${_debug_manifest}" "# Library Paths\n")
foreach(d IN LISTS debug_dirs)
    file(APPEND "${_debug_manifest}" "${d}\n")
endforeach()

file(WRITE  "${_rel_manifest}" "# ccore dependency manifest (configuration: RelWithDebInfo)\n# Libraries\n")
foreach(n IN LISTS release_libs)
    file(APPEND "${_rel_manifest}" "${n}\n")
endforeach()
file(APPEND "${_rel_manifest}" "# Library Paths\n")
foreach(d IN LISTS release_dirs)
    file(APPEND "${_rel_manifest}" "${d}\n")
endforeach()

install(FILES "${_debug_manifest}" DESTINATION lib/Debug RENAME ccore-dependencies-Debug.txt)
install(FILES "${_rel_manifest}"   DESTINATION lib/RelWithDebInfo RENAME ccore-dependencies-RelWithDebInfo.txt)
