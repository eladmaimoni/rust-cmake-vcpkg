include(CMakePackageConfigHelpers)

function(setup_target_includes_for_install
    target_name
    public_include_folder # the public include folder
)
    target_include_directories(
        ${target_name}
        INTERFACE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/> # when using within the build, the include directories is the current source dir
        $<INSTALL_INTERFACE:include/> # when used from installation folder, the include directories is the exported path
    )

    install(DIRECTORY ${public_include_folder} DESTINATION include FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp")

    # when installing, copy the public header files to the include directory
    # file(GLOB_RECURSE
    # LIST_DIRECTORIES true
    # public_include_list
    # "${public_include_folder}/*.h"
    # "${public_include_folder}/*.hpp"
    # )
    #
    # install(FILES ${public_include_list} DESTINATION include/${public_include_folder})

    # message(STATUS "public include list ${public_include_list}")
endfunction()

function(setup_target_for_find_package
    target_name
)
    # message("ZZZZZZZZZZZ configure_package_config_file ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/Config.cmake.in -> ${CMAKE_CURRENT_BINARY_DIR}/${target_name}.cmake")

    # when installing, generate a "targets" file. clients can include this
    # The EXPORT argument in install() is about generating an importable
    # “targets file” for consumers of your project. It does not install
    # the target itself; instead, it writes a CMake script that defines
    # imported targets corresponding to targets you previously marked for
    # export during their own install() calls.
    install(
        EXPORT ${target_name}
        FILE ${target_name}-targets.cmake
        DESTINATION cmake
    )

    # generate a "config" file that includes the generated target file cmake file
    # this is for 'find_package' to work
    configure_package_config_file(
        ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/Config.cmake.in # input template
        ${CMAKE_CURRENT_BINARY_DIR}/${target_name}-config.cmake # output file
        INSTALL_DESTINATION cmake
        NO_SET_AND_CHECK_MACRO
        NO_CHECK_REQUIRED_COMPONENTS_MACRO
    )

    install(
        FILES
        ${CMAKE_CURRENT_BINARY_DIR}/${target_name}-config.cmake
        DESTINATION cmake
    )
endfunction()

function(add_target_to_global_export_set
    target_name
)
    # when installing,
    # - copy the target artifacts (in this case .lib & .dll) to the lib directory withing the install path
    # - create a cmake files that defines cmake targets with all relevant stuff that clients could link to

    # this causes the dependant runtime artifacts such as dlls
    # to be copied into the bin directory

    #
    # Use conditional generator expression: emits 'debug' for Debug config, empty otherwise
    # NOTE: Previous logic produced an empty prefix for non-Debug configs and then
    # constructed "/lib" (leading slash) causing installs to go to C:/lib.
    # Embed the trailing slash in the generator expression and concatenate without
    # inserting an unconditional slash so non-Debug resolves to "lib" not "/lib".
    set(lib_bin_prefix $<$<CONFIG:Debug>:debug/>)
    set(lib_dest ${lib_bin_prefix}lib)
    set(bin_dest ${lib_bin_prefix}bin)

    install(
        TARGETS ${target_name}
        EXPORT ${export_set} # when installing, generate a "targets" file. clients can include this

        # DESTINATION lib/$<CONFIG>
        ARCHIVE DESTINATION ${lib_dest}
        LIBRARY DESTINATION ${lib_dest}
        RUNTIME DESTINATION ${bin_dest}
        INCLUDES DESTINATION include

        # RUNTIME_DEPENDENCY_SET FLUTTER_EMBEDDER_API_RUNTIME_DEPENDENCY_SET
    )

    # this piece of SHIT does not generate correct IMPORTED_CONFIGURATIONS. WHY????
    # install(
    # TARGETS ${target_name}
    # EXPORT ${target_name}
    # CONFIGURATIONS Debug
    # RUNTIME DESTINATION bin/Debug
    # ARCHIVE DESTINATION lib/Debug
    # )
    #
    # install(
    # TARGETS ${target_name}
    # CONFIGURATIONS Release RelWithDebInfo
    # RUNTIME DESTINATION bin/Release
    # ARCHIVE DESTINATION lib/Release
    # )
    get_target_property(target_type ${target_name} TYPE)

    # PDB FILES
    if(target_type STREQUAL STATIC_LIBRARY)
        install(

            # FILES $<TARGET_COMPILE_PDB_FILE:${target_name}> # https://gitlab.kitware.com/cmake/cmake/-/issues/16935
            FILES $<TARGET_FILE_DIR:${target_name}>/${target_name}.pdb
            DESTINATION ${lib_dest}
            OPTIONAL
        )

    elseif(
        target_type STREQUAL SHARED_LIBRARY OR
        target_type STREQUAL EXECUTABLE
    )
        # For shared libraries/executables we want the PDB to be installed
        # next to the runtime artifact (DLL/exe). Install it into the
        # runtime/bin destination so consumers who copy the DLL also get
        # the corresponding PDB beside it on Windows.
        install(
            FILES $<TARGET_PDB_FILE:${target_name}>
            DESTINATION ${bin_dest}
            OPTIONAL
        )

        # install(
        # IMPORTED_RUNTIME_ARTIFACTS
        # ${target_name}
        # DESTINATION bin/$<CONFIG>
        # )
    endif()
endfunction()

function(setup_target_for_install
    target_name
    public_include_folder # the public include folder
)
    setup_target_includes_for_install(${target_name} ${public_include_folder})
    setup_target_for_find_package(${target_name})
    add_target_to_global_export_set(${target_name})
endfunction()

# Main: generate and install a pkg-config file for a CMake target
#
# Usage:
# generate_pkgconfig(myTarget VERSION 1.0.0 DESCRIPTION "My Core Library")
#
function(generate_pkgconfig target)
    # The names of boolean flags this function accepts (e.g., QUIET)
    set(options)

    # The names of keywords that must be followed by one value
    set(oneValueArgs VERSION DESCRIPTION)

    # The names of keywords that can be followed by multiple values
    set(multiValueArgs)

    cmake_parse_arguments(
        arg # prefix for output variables
        "${options}"
        "${oneValueArgs}"
        "${multiValueArgs}"
        ${ARGN}
    )

    if(NOT arg_VERSION)
        set(arg_VERSION "0.1.0")
    endif()

    # Collect dependencies of target (transitively)
    get_target_link_dependencies(${target} dependencies)

    set(debug_libs "")
    set(release_libs "")
    set(debug_dirs "")
    set(release_dirs "")
    set(include_dirs "")

    # Gather outputs for the main target
    append_target_output_file_and_output_dir(${target} debug_libs debug_dirs release_libs release_dirs)
    get_target_property(_target_type ${target} TYPE)

    # Merge transitive dependencies. For SHARED main targets we only
    # advertise the main target's debug import library (release keeps full list).
    foreach(dep IN LISTS dependencies)
        append_target_output_file_and_output_dir(${dep} _d_libs _d_dirs _r_libs _r_dirs)
        list(APPEND release_libs ${_r_libs})
        list(APPEND release_dirs ${_r_dirs})

        if(NOT _target_type MATCHES "SHARED")
            list(APPEND debug_libs ${_d_libs})
            list(APPEND debug_dirs ${_d_dirs})
        endif()

        if(TARGET ${dep})
            get_target_property(_inc ${dep} INTERFACE_INCLUDE_DIRECTORIES)

            if(_inc)
                list(APPEND include_dirs ${_inc})
            endif()
        endif()
    endforeach()

    # Ensure main target import lib appears for shared libs in debug .pc
    if(_target_type MATCHES "SHARED")
        get_target_output_name(${target} _out_debug _out_release)
        append_to_list_if_not_found(debug_libs "${_out_debug}")
        append_to_list_if_not_found(debug_dirs "${CMAKE_INSTALL_PREFIX}/debug/lib")
        append_to_list_if_not_found(debug_dirs "${CMAKE_INSTALL_PREFIX}/lib")
    endif()

    # Move any entries that look like paths into dirs so we never emit -l<path>
    function(_move_pathlike src_list dst_dirs dst_libs)
        foreach(_e IN LISTS ${src_list})
            if(_e MATCHES "^.*/.*" OR _e MATCHES "^[A-Za-z]:.*")
                list(APPEND ${dst_dirs} ${_e})
            else()
                list(APPEND ${dst_libs} ${_e})
            endif()
        endforeach()

        set(${dst_dirs} "${${dst_dirs}}" PARENT_SCOPE)
        set(${dst_libs} "${${dst_libs}}" PARENT_SCOPE)
    endfunction()

    set(_dbg_libs "")
    set(_rel_libs "")
    _move_pathlike(debug_libs debug_dirs _dbg_libs)
    _move_pathlike(release_libs release_dirs _rel_libs)
    set(debug_libs "${_dbg_libs}")
    set(release_libs "${_rel_libs}")

    list(REMOVE_DUPLICATES debug_libs)
    list(REMOVE_DUPLICATES release_libs)
    list(REMOVE_DUPLICATES debug_dirs)
    list(REMOVE_DUPLICATES release_dirs)
    list(REMOVE_DUPLICATES include_dirs)

    # Build space-separated -L/-l strings (no filesystem probing)
    string(CONCAT _libpaths_debug "")

    foreach(d IN LISTS debug_dirs)
        if(NOT d STREQUAL "")
            file(TO_CMAKE_PATH "${d}" _d_norm)
            string(APPEND _libpaths_debug "-L${_d_norm} ")
        endif()
    endforeach()

    string(CONCAT _libpaths_release "")

    foreach(d IN LISTS release_dirs)
        if(NOT d STREQUAL "")
            file(TO_CMAKE_PATH "${d}" _d_norm)
            string(APPEND _libpaths_release "-L${_d_norm} ")
        endif()
    endforeach()

    string(CONCAT _libs_debug "")

    foreach(n IN LISTS debug_libs)
        if(NOT n STREQUAL "")
            string(APPEND _libs_debug "-l${n} ")
        endif()
    endforeach()

    string(CONCAT _libs_release "")

    foreach(n IN LISTS release_libs)
        if(NOT n STREQUAL "")
            string(APPEND _libs_release "-l${n} ")
        endif()
    endforeach()

    # Normalize include dirs into _cflags (skip generator expressions)
    set(_cflags "")

    foreach(inc IN LISTS include_dirs)
        if(inc AND NOT inc MATCHES "^[\\$<]" AND EXISTS "${inc}")
            file(TO_CMAKE_PATH "${inc}" _inc_norm)
            string(APPEND _cflags "-I${_inc_norm} ")
        endif()
    endforeach()

    # Compose pkg-config contents
    set(_prefix "${CMAKE_INSTALL_PREFIX}")
    file(TO_CMAKE_PATH "${_prefix}" _prefix_norm)

    set(pc_file_debug "${CMAKE_CURRENT_BINARY_DIR}/${target}-debug.pc")
    set(pc_file_release "${CMAKE_CURRENT_BINARY_DIR}/${target}.pc")

    # For multi-config installs on Windows we always emit the conventional
    # multi-config libdir layout: ${prefix}/debug/lib for Debug and
    # ${prefix}/lib for Release. Emit these as pkg-config variables so
    # consumers can resolve them relative to the install prefix. We must
    # escape the "$" when writing the file so pkg-config sees the
    # literal "${prefix}" variable.

    # Emit prefix without escaping so pkg-config understands paths on Windows
    set(_content_debug "prefix=${_prefix_norm}\n")
    string(APPEND _content_debug "exec_prefix=\${prefix}\n")
    string(APPEND _content_debug "libdir=\${prefix}/debug/lib\n")
    string(APPEND _content_debug "includedir=\${prefix}/include\n\n")
    string(APPEND _content_debug "Name: ${target}-debug\n")
    string(APPEND _content_debug "Description: ${arg_DESCRIPTION} (debug)\n")
    string(APPEND _content_debug "Version: ${arg_VERSION}\n")
    string(APPEND _content_debug "Cflags: ${_cflags} -I\${includedir}\n")

    # If main target is a shared library, explicitly reference its import
    # library in the debug pkg-config so consumers link the DLL import lib.
    if(_target_type MATCHES "SHARED")
        get_target_output_name(${target} _out_debug _out_release)
        string(APPEND _content_debug "Libs: -L\${libdir} ${_libpaths_debug} -l${_out_debug}\n")
    else()
        string(APPEND _content_debug "Libs: -L\${libdir} ${_libpaths_debug} ${_libs_debug}\n")
    endif()

    file(WRITE "${pc_file_debug}" "${_content_debug}")

    set(_content_release "prefix=${_prefix_norm}\n")
    string(APPEND _content_release "exec_prefix=\${prefix}\n")
    string(APPEND _content_release "libdir=\${prefix}/lib\n")
    string(APPEND _content_release "includedir=\${prefix}/include\n\n")
    string(APPEND _content_release "Name: ${target}\n")
    string(APPEND _content_release "Description: ${arg_DESCRIPTION}\n")
    string(APPEND _content_release "Version: ${arg_VERSION}\n")
    string(APPEND _content_release "Cflags: ${_cflags} -I\${includedir}\n")
    string(APPEND _content_release "Libs: -L\${libdir} ${_libpaths_release} ${_libs_release}\n")

    file(WRITE "${pc_file_release}" "${_content_release}")

    install(FILES "${pc_file_release}" DESTINATION "lib/pkgconfig")
    install(FILES "${pc_file_debug}" DESTINATION "debug/lib/pkgconfig" RENAME "${target}.pc")
endfunction()
