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

    if(NOT arg_DESCRIPTION)
        set(arg_DESCRIPTION "${target} library")
    endif()

    # Collect dependencies of target (transitively) as logical names / cmake targets
    get_target_link_dependencies(${target} dependencies)

    set(debug_libs "")
    set(release_libs "") # fixed original typo release_l`ibs
    set(debug_dirs "")
    set(release_dirs "")
    set(include_dirs "")

    # Ensure the target itself is included in the generated pkg-config
    # so consumers know to link with the main library (e.g., -lby2).
    #
    # On Windows with multi-config installs, if the target is a SHARED
    # library then the debug pkg-config should reference only the main
    # target's debug/runtime import library (e.g., by2.dll / by2.lib).
    # The transitive static dependencies should NOT be listed in the
    # debug .pc since the C++ project builds as a single shared binary
    # for debug. For Release (static linking) we keep the full
    # transitive list so consumers can link all required static libs.
    append_target_output_file_and_output_dir(${target} debug_libs debug_dirs release_libs release_dirs)
    get_target_property(_target_type ${target} TYPE)

    # Treat any type containing 'SHARED' as a shared library for robustness
    if(_target_type MATCHES "SHARED")
        # If shared, limit debug_libs/debug_dirs to the main target only.
        # Remove any entries that were added for dependencies.
        set(_only_libs "")
        set(_only_dirs "")
        set(_only_rel_libs "")
        set(_only_rel_dirs "")

        # Recompute using only the main target (macro expects 5 args)
        append_target_output_file_and_output_dir(${target} _only_libs _only_dirs _only_rel_libs _only_rel_dirs)

        # Replace debug lists with the restricted lists. If the temporary
        # list is empty for any reason, compute the debug output name and
        # fallback to the conventional install debug libdir so the .pc
        # always contains the main target import library.
        if(NOT _only_libs)
            # Compute output names (out_debug out_release)
            get_target_output_name(${target} _out_debug _out_release)
            set(debug_libs "${_out_debug}")
            set(debug_dirs "${CMAKE_INSTALL_PREFIX}/debug/lib")
        else()
            set(debug_libs "${_only_libs}")
            set(debug_dirs "${_only_dirs}")
        endif()
    endif()

    if(TARGET ${target})
        get_target_property(target_includes ${target} INTERFACE_INCLUDE_DIRECTORIES)

        if(target_includes)
            list(APPEND include_dirs ${target_includes})
        endif()
    endif()

    # If the main target is a shared library, do not include transitive
    # dependencies in the debug pkg-config. The shared debug build is
    # distributed as a single DLL and consumers only need the import
    # library for the main target at runtime.
    set(_omit_transitive_debug FALSE)

    if(_target_type STREQUAL "SHARED_LIBRARY")
        set(_omit_transitive_debug TRUE)
    endif()

    foreach(dep IN LISTS dependencies)
        # Use temporary containers to collect outputs per-dependency so we can
        # selectively merge only the release-side when omitting transitive
        # debug deps for shared main targets.
        set(_tmp_dbg_libs "")
        set(_tmp_dbg_dirs "")
        set(_tmp_rel_libs "")
        set(_tmp_rel_dirs "")

        append_target_output_file_and_output_dir(${dep} _tmp_dbg_libs _tmp_dbg_dirs _tmp_rel_libs _tmp_rel_dirs)

        if(_omit_transitive_debug)
            # Append only the release-side findings; ignore debug-side for transitive deps.
            foreach(_rl IN LISTS _tmp_rel_libs)
                list(APPEND release_libs ${_rl})
            endforeach()

            foreach(_rd IN LISTS _tmp_rel_dirs)
                list(APPEND release_dirs ${_rd})
            endforeach()
        else()
            # Merge both debug and release findings.
            foreach(_dl IN LISTS _tmp_dbg_libs)
                list(APPEND debug_libs ${_dl})
            endforeach()

            foreach(_dd IN LISTS _tmp_dbg_dirs)
                list(APPEND debug_dirs ${_dd})
            endforeach()

            foreach(_rl IN LISTS _tmp_rel_libs)
                list(APPEND release_libs ${_rl})
            endforeach()

            foreach(_rd IN LISTS _tmp_rel_dirs)
                list(APPEND release_dirs ${_rd})
            endforeach()
        endif()

        # Gather PUBLIC/INTERFACE include directories
        if(TARGET ${dep})
            get_target_property(dep_includes ${dep} INTERFACE_INCLUDE_DIRECTORIES)

            if(dep_includes)
                list(APPEND include_dirs ${dep_includes})
            endif()
        endif()
    endforeach()

    list(REMOVE_DUPLICATES debug_libs)
    list(REMOVE_DUPLICATES release_libs)
    list(REMOVE_DUPLICATES debug_dirs)
    list(REMOVE_DUPLICATES release_dirs)
    list(REMOVE_DUPLICATES include_dirs)

    # Sanitize library name lists: if any entry looks like a path (for
    # example because a caller passed a raw directory or an incorrectly
    # formed -l token), move it into the corresponding dirs list so we
    # don't emit "-lC:/..." later. This keeps the generated pkg-config
    # safe for consumers that expect -l<name> and -L<path> tokens.
    set(_sanitized_debug_libs "")

    foreach(_n IN LISTS debug_libs)
        if(_n MATCHES "^.*/.*" OR _n MATCHES "^[A-Za-z]:.*")
            # treat as directory
            list(APPEND debug_dirs "${_n}")
        else()
            list(APPEND _sanitized_debug_libs "${_n}")
        endif()
    endforeach()

    set(debug_libs "${_sanitized_debug_libs}")

    set(_sanitized_release_libs "")

    foreach(_n IN LISTS release_libs)
        if(_n MATCHES "^.*/.*" OR _n MATCHES "^[A-Za-z]:.*")
            list(APPEND release_dirs "${_n}")
        else()
            list(APPEND _sanitized_release_libs "${_n}")
        endif()
    endforeach()

    set(release_libs "${_sanitized_release_libs}")

    # For shared main targets ensure debug .pc references the main
    # import library and conventional install lib directories so the
    # pkg-config probe can resolve the import library at link time.
    if(_target_type MATCHES "SHARED")
        get_target_output_name(${target} _out_debug _out_release)
        append_to_list_if_not_found(debug_libs "${_out_debug}")
        append_to_list_if_not_found(debug_dirs "${CMAKE_INSTALL_PREFIX}/lib")
        append_to_list_if_not_found(debug_dirs "${CMAKE_INSTALL_PREFIX}/debug/lib")
    endif()

    # Recompute the emitted debug lib paths and libs so the previously
    # emitted `_libpaths_debug` / `_libs_debug` reflect any changes we
    # made above (e.g., ensuring the main target is present).
    set(_tmp_lp "")

    foreach(d IN LISTS debug_dirs)
        if(d AND IS_DIRECTORY "${d}")
            file(TO_CMAKE_PATH "${d}" _d_norm)
            list(APPEND _tmp_lp "-L${_d_norm}")
        endif()
    endforeach()

    string(REPLACE ";" " " _joined "${_tmp_lp}")
    set(_libpaths_debug "${_joined}")

    set(_tmp_l "")

    foreach(n IN LISTS debug_libs)
        if(NOT n STREQUAL "")
            list(APPEND _tmp_l "-l${n}")
        endif()
    endforeach()

    string(REPLACE ";" " " _joined "${_tmp_l}")
    set(_libs_debug "${_joined}")

    # Don't attempt to perform install-time filesystem checks at configure
    # time to decide which libraries should be advertised. The configure
    # step runs before "install" has placed artifacts under
    # ${CMAKE_INSTALL_PREFIX} so such checks are fragile and can cause
    # legitimate transitive dependencies to be omitted from the generated
    # pkg-config file. Instead, emit the computed dependency lists as-is
    # and allow the consumer (build.rs / pkg-config probe) to verify
    # library availability at link time.

    # (debug_libs/release_libs remain as computed above)

    # Normalize include dirs (skip generator expressions)
    set(_norm_includes "")

    foreach(inc IN LISTS include_dirs)
        if(inc AND NOT inc MATCHES "^[\$<]" AND EXISTS "${inc}")
            file(TO_CMAKE_PATH "${inc}" _inc_norm)
            list(APPEND _norm_includes "${_inc_norm}")
        endif()
    endforeach()

    list(REMOVE_DUPLICATES _norm_includes)

    function(_join_with_prefix out_var prefix input_list)
        set(_tmp "")

        foreach(item IN LISTS input_list)
            if(NOT item STREQUAL "")
                list(APPEND _tmp "${prefix}${item}")
            endif()
        endforeach()

        string(REPLACE ";" " " _joined "${_tmp}")
        set(${out_var} "${_joined}" PARENT_SCOPE)
    endfunction()

    _join_with_prefix(_cflags "-I" "${_norm_includes}")

    # Prepare -L paths (validated existing directories only)
    function(_emit_L out_var dirs)
        set(_tmp "")

        foreach(d IN LISTS dirs)
            if(d AND IS_DIRECTORY "${d}")
                file(TO_CMAKE_PATH "${d}" _d_norm)
                list(APPEND _tmp "-L${_d_norm}")
            endif()
        endforeach()

        string(REPLACE ";" " " _joined "${_tmp}")
        set(${out_var} "${_joined}" PARENT_SCOPE)
    endfunction()

    _emit_L(_libpaths_debug "${debug_dirs}")
    _emit_L(_libpaths_release "${release_dirs}")

    function(_emit_l out_var names)
        set(_tmp "")

        foreach(n IN LISTS names)
            if(NOT n STREQUAL "")
                list(APPEND _tmp "-l${n}")
            endif()
        endforeach()

        string(REPLACE ";" " " _joined "${_tmp}")
        set(${out_var} "${_joined}" PARENT_SCOPE)
    endfunction()

    _emit_l(_libs_debug "${debug_libs}")
    _emit_l(_libs_release "${release_libs}")

    # Additional safety: If any generated -l tokens accidentally contain
    # path-like values (for example due to importer properties or
    # previously computed list entries), move those into the corresponding
    # dirs lists and rebuild the -L lists. This prevents emitting
    # "-lC:/..." in the pkg-config output which confuses pkg-config
    # consumers.
    if(NOT _libs_debug STREQUAL "")
        # split the space-separated string into list for inspection
        string(REGEX MATCHALL "[^ ]+" _dbg_tokens "${_libs_debug}")
        set(_filtered_dbg_tokens "")

        foreach(_tok IN LISTS _dbg_tokens)
            if(_tok MATCHES "^-l(.*/.*)$" OR _tok MATCHES "^-l([A-Za-z]:.*)$")
                # strip leading -l and add as a dir entry (normalize slashes)
                string(REGEX REPLACE "^-l" "" _maybe_dir "${_tok}")
                file(TO_CMAKE_PATH "${_maybe_dir}" _maybe_dir)
                append_to_list_if_not_found(debug_dirs "${_maybe_dir}")
            else()
                list(APPEND _filtered_dbg_tokens "${_tok}")
            endif()
        endforeach()

        string(REPLACE ";" " " _joined_dbg "${_filtered_dbg_tokens}")
        set(_libs_debug "${_joined_dbg}")
    endif()

    if(NOT _libs_release STREQUAL "")
        string(REGEX MATCHALL "[^ ]+" _rel_tokens "${_libs_release}")
        set(_filtered_rel_tokens "")

        foreach(_tok IN LISTS _rel_tokens)
            if(_tok MATCHES "^-l(.*/.*)$" OR _tok MATCHES "^-l([A-Za-z]:.*)$")
                string(REGEX REPLACE "^-l" "" _maybe_dir "${_tok}")
                file(TO_CMAKE_PATH "${_maybe_dir}" _maybe_dir)
                append_to_list_if_not_found(release_dirs "${_maybe_dir}")
            else()
                list(APPEND _filtered_rel_tokens "${_tok}")
            endif()
        endforeach()

        string(REPLACE ";" " " _joined_rel "${_filtered_rel_tokens}")
        set(_libs_release "${_joined_rel}")
    endif()

    # Recompute -L lists now that we've possibly mutated the dirs lists
    _emit_L(_libpaths_debug "${debug_dirs}")
    _emit_L(_libpaths_release "${release_dirs}")

    # If we intentionally omitted transitive debug deps for a shared main
    # target, prefer the main-target-only libpaths/libs computed earlier
    # so the debug .pc references only the import library for the shared
    # DLL and not its transitive static deps.
    if(DEFINED _omit_transitive_debug AND _omit_transitive_debug)
        if(DEFINED _only_dirs)
            _emit_L(_libpaths_debug "${_only_dirs}")
        endif()

        if(DEFINED _only_libs)
            _emit_l(_libs_debug "${_only_libs}")
        endif()
    endif()

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
