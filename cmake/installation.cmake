include(CMakePackageConfigHelpers)

set(ULTRA_INSTALL_CONFIG $<IF:$<CONFIG:Debug>,Debug,Release>)

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

    #install(DIRECTORY ${public_include_folder} DESTINATION include FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp")

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
    install(
        TARGETS ${target_name}
        EXPORT ${export_set} # when installing, generate a "targets" file. clients can include this

        # DESTINATION lib/$<CONFIG>
        ARCHIVE DESTINATION lib/${ULTRA_INSTALL_CONFIG}
        LIBRARY DESTINATION lib/${ULTRA_INSTALL_CONFIG}
        RUNTIME DESTINATION bin/${ULTRA_INSTALL_CONFIG}
        INCLUDES DESTINATION include
        # RUNTIME_DEPENDENCY_SET FLUTTER_EMBEDDER_API_RUNTIME_DEPENDENCY_SET
        # DESTINATION lib/${ULTRA_INSTALL_CONFIG}
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
            DESTINATION lib/${ULTRA_INSTALL_CONFIG}
            OPTIONAL
        )

    elseif(
        target_type STREQUAL SHARED_LIBRARY OR
        target_type STREQUAL EXECUTABLE
    )
        install(
            FILES $<TARGET_PDB_FILE:${target_name}>
            DESTINATION lib/${ULTRA_INSTALL_CONFIG}
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


function(get_vcpkg_lib_and_include_dirs out_lib_dir out_include_dir)
    # if vcpkg is being used, detect its installed dir and triplet 
    # (when available)
    if(DEFINED VCPKG_INSTALLED_DIR)
        set(vcpkg_install_root "${VCPKG_INSTALLED_DIR}")
    elseif(DEFINED ENV{VCPKG_INSTALLED_DIR})
        set(vcpkg_install_root "$ENV{VCPKG_INSTALLED_DIR}")
    else()
        set(vcpkg_install_root "")
    endif()

    if(vcpkg_install_root)
        if(DEFINED VCPKG_TARGET_TRIPLET)
            set(_vcpkg_triplet "${VCPKG_TARGET_TRIPLET}")
        elseif(DEFINED ENV{VCPKG_DEFAULT_TRIPLET})
            set(_vcpkg_triplet "$ENV{VCPKG_DEFAULT_TRIPLET}")
        else()
            set(_vcpkg_triplet "")
        endif()

        # Determine the prefix (with or without triplet)
        if(_vcpkg_triplet)
            set(vcpkg_triplet_install_root "${vcpkg_install_root}/${_vcpkg_triplet}")
        else()
            set(vcpkg_triplet_install_root "${vcpkg_install_root}")
        endif()

        # For debug configuration vcpkg places libs under debug/lib; use a generator expression
        # so multi-config (MSVC) or single-config (Ninja) builds both resolve correctly.
        # NOTE: include directory is the same for all configurations.
        set(vcpkg_libdir "$<IF:$<CONFIG:Debug>,${vcpkg_triplet_install_root}/debug/lib,${vcpkg_triplet_install_root}/lib>")
        set(vcpkg_includedir "${vcpkg_triplet_install_root}/include")
    else()
        set(vcpkg_libdir "")
        set(vcpkg_includedir "")
    endif()

    set(${out_lib_dir} "${vcpkg_libdir}" PARENT_SCOPE)
    set(${out_include_dir} "${vcpkg_includedir}" PARENT_SCOPE)
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

    get_vcpkg_lib_and_include_dirs(vcpkg_libdir vcpkg_includedir)
    
    get_target_link_dependencies(${target} link_dependencies) # Collect link deps

    # We'll generate config-specific .pc files for multi-config generators (Debug and RelWithDebInfo)
    set(_configs Debug;RelWithDebInfo)

    foreach(_cfg IN LISTS _configs)
        set(LIBS_PRIVATE "")
        set(_libdirs_added "")

        foreach(dep IN LISTS link_dependencies)
            string(STRIP "${dep}" dep_trimmed)

            if(dep_trimmed MATCHES "^(-l|-L)")
                # Already a linker flag
                set(LIBS_PRIVATE "${LIBS_PRIVATE} ${dep_trimmed}")
            elseif(TARGET ${dep_trimmed})
                # Map namespaced target to a reasonable -l name by taking the last component after ::
                string(REPLACE "::" ";" _parts "${dep_trimmed}")
                list(GET _parts -1 _shortname)
                string(REGEX REPLACE "[^A-Za-z0-9_]" "_" _shortname "${_shortname}")

                # Try to discover where this target's library file lives for this config
                set(_libdir_candidate "")

                # 1) Prefer config-specific imported location
                get_target_property(_imp_loc_cfg ${dep_trimmed} "IMPORTED_LOCATION_${_cfg}")

                if(_imp_loc_cfg)
                    get_filename_component(_libdir_candidate "${_imp_loc_cfg}" DIRECTORY)
                endif()

                # 2) Fallback to single-config imported location or implib
                if(NOT _libdir_candidate)
                    get_target_property(_imported_loc ${dep_trimmed} IMPORTED_LOCATION)

                    if(_imported_loc)
                        get_filename_component(_libdir_candidate "${_imported_loc}" DIRECTORY)
                    endif()
                endif()

                if(NOT _libdir_candidate)
                    get_target_property(_imported_implib ${dep_trimmed} IMPORTED_IMPLIB)

                    if(_imported_implib)
                        get_filename_component(_libdir_candidate "${_imported_implib}" DIRECTORY)
                    endif()
                endif()

                # 3) As a last resort, try to get TARGET_FILE location
                if(NOT _libdir_candidate)
                    get_target_property(_tfile ${dep_trimmed} LOCATION)

                    if(_tfile)
                        get_filename_component(_libdir_candidate "${_tfile}" DIRECTORY)
                    endif()
                endif()

                if(_libdir_candidate)
                    string(REPLACE "\\" "/" _libdir_unix "${_libdir_candidate}")

                    # For this config, choose the vcpkg libdir variant (debug vs release)
                    set(_vcpkg_libdir_cfg "${vcpkg_libdir}")

                    if(vcpkg_install_root)
                        if(_cfg STREQUAL Debug)
                            # debug libs live in .../debug/lib for vcpkg
                            set(_vcpkg_libdir_cfg "${vcpkg_install_root}/${_vcpkg_triplet}/debug/lib")
                        else()
                            set(_vcpkg_libdir_cfg "${vcpkg_install_root}/${_vcpkg_triplet}/lib")
                        endif()

                        string(REPLACE "\\" "/" _vcpkg_prefix_unix "${vcpkg_install_root}")

                        if(_libdir_unix MATCHES "^${_vcpkg_prefix_unix}")
                            set(_libdir_to_use "${_vcpkg_libdir_cfg}")
                        else()
                            set(_libdir_to_use "${_libdir_unix}")
                        endif()
                    else()
                        set(_libdir_to_use "${_libdir_unix}")
                    endif()

                    # Avoid adding the package's own install libdir (we'll add per-cfg libdir later)
                    set(_install_libdir_cfg "${exec_prefix}/${CMAKE_INSTALL_LIBDIR}/${_cfg}")

                    if(NOT _libdir_to_use STREQUAL "${_install_libdir_cfg}")
                        if(NOT _libdirs_added MATCHES "(^|;| )${_libdir_to_use}($|;| )")
                            set(LIBS_PRIVATE "${LIBS_PRIVATE} -L${_libdir_to_use}")
                            set(_libdirs_added "${_libdirs_added};${_libdir_to_use}")
                        endif()
                    endif()
                endif()

                set(LIBS_PRIVATE "${LIBS_PRIVATE} -l${_shortname}")
            else()
                # Raw token (could be -pthread or -lm or an absolute path) - keep as-is
                set(LIBS_PRIVATE "${LIBS_PRIVATE} ${dep_trimmed}")
            endif()
        endforeach()

        # For this config write a .pc file and install it under pkgconfig/<cfg>
        set(prefix "${CMAKE_INSTALL_PREFIX}")
        set(exec_prefix "${prefix}")
        set(libdir_cfg "${exec_prefix}/${CMAKE_INSTALL_LIBDIR}/${_cfg}")
        set(includedir "${prefix}/${CMAKE_INSTALL_INCLUDEDIR}")

        # vcpkg dir variant for this config
        if(vcpkg_install_root)
            if(_cfg STREQUAL Debug)
                set(vcpkg_libdir_cfg "${vcpkg_install_root}/${_vcpkg_triplet}/debug/lib")
                set(vcpkg_includedir_cfg "${vcpkg_install_root}/${_vcpkg_triplet}/include")
            else()
                set(vcpkg_libdir_cfg "${vcpkg_install_root}/${_vcpkg_triplet}/lib")
                set(vcpkg_includedir_cfg "${vcpkg_install_root}/${_vcpkg_triplet}/include")
            endif()
        else()
            set(vcpkg_libdir_cfg "")
            set(vcpkg_includedir_cfg "")
        endif()

        set(pc_file_cfg "${CMAKE_CURRENT_BINARY_DIR}/${target}-${_cfg}.pc")
        file(WRITE "${pc_file_cfg}" "prefix=${prefix}\n")
        file(APPEND "${pc_file_cfg}" "exec_prefix=\${prefix}\n")
        file(APPEND "${pc_file_cfg}" "libdir=${libdir_cfg}\n")
        file(APPEND "${pc_file_cfg}" "includedir=${includedir}\n\n")

        if(vcpkg_install_root)
            file(APPEND "${pc_file_cfg}" "# External dependencies from vcpkg\n")
            file(APPEND "${pc_file_cfg}" "vcpkg_prefix=${vcpkg_install_root}\n")
            file(APPEND "${pc_file_cfg}" "vcpkg_libdir=${vcpkg_libdir_cfg}\n")
            file(APPEND "${pc_file_cfg}" "vcpkg_includedir=${vcpkg_includedir_cfg}\n\n")
        endif()

        file(APPEND "${pc_file_cfg}" "Name: ${target}\n")
        file(APPEND "${pc_file_cfg}" "Description: ${GPC_DESCRIPTION}\n")
        file(APPEND "${pc_file_cfg}" "Version: ${GPC_VERSION}\n")
        file(APPEND "${pc_file_cfg}" "Libs: -L${libdir_cfg} -l${target}\n")

        if(LIBS_PRIVATE)
            string(STRIP "${LIBS_PRIVATE}" LIBS_PRIVATE_STRIPPED)
            file(APPEND "${pc_file_cfg}" "Libs.private: ${LIBS_PRIVATE_STRIPPED}\n")
        endif()

        if(vcpkg_includedir_cfg)
            file(APPEND "${pc_file_cfg}" "Cflags: -I${includedir} -I${vcpkg_includedir_cfg}\n")
        else()
            file(APPEND "${pc_file_cfg}" "Cflags: -I${includedir}\n")
        endif()

        # Install this config-specific .pc file into a config specific pkgconfig folder
        install(FILES "${pc_file_cfg}" DESTINATION "pkgconfig/${_cfg}")
    endforeach()

    # Paths written into the .pc should use pkg-config variables so consumers can relocate
    set(prefix "${CMAKE_INSTALL_PREFIX}")
    set(exec_prefix "${prefix}")
    set(libdir "${exec_prefix}/${CMAKE_INSTALL_LIBDIR}")
    set(includedir "${prefix}/${CMAKE_INSTALL_INCLUDEDIR}")

    # Create the .pc file in the build tree and install it
    set(pc_file "${CMAKE_CURRENT_BINARY_DIR}/${target}.pc")
    file(WRITE "${pc_file}" "prefix=${prefix}\n")
    file(APPEND "${pc_file}" "exec_prefix=\${prefix}\n")
    file(APPEND "${pc_file}" "libdir=\${exec_prefix}/${CMAKE_INSTALL_LIBDIR}\n")
    file(APPEND "${pc_file}" "includedir=\${prefix}/${CMAKE_INSTALL_INCLUDEDIR}\n\n")

    # If vcpkg detected, emit its variables for consumers
    if(vcpkg_install_root)
        file(APPEND "${pc_file}" "# External dependencies from vcpkg\n")
        file(APPEND "${pc_file}" "vcpkg_prefix=${vcpkg_install_root}\n")
        file(APPEND "${pc_file}" "vcpkg_libdir=${vcpkg_libdir}\n")
        file(APPEND "${pc_file}" "vcpkg_includedir=${vcpkg_includedir}\n\n")
    endif()

    file(APPEND "${pc_file}" "Name: ${target}\n")
    file(APPEND "${pc_file}" "Description: ${GPC_DESCRIPTION}\n")
    file(APPEND "${pc_file}" "Version: ${GPC_VERSION}\n")
    file(APPEND "${pc_file}" "Libs: -L\${libdir} -l${target}\n")

    if(LIBS_PRIVATE)
        # Ensure proper spacing and leading space after the colon
        string(STRIP "${LIBS_PRIVATE}" LIBS_PRIVATE_STRIPPED)

        # Write as a single line, but keep tokens intact. Consumers can parse or wrap it.
        file(APPEND "${pc_file}" "Libs.private: ${LIBS_PRIVATE_STRIPPED}\n")
    endif()

    # Add vcpkg include dir to Cflags when available
    if(vcpkg_includedir)
        file(APPEND "${pc_file}" "Cflags: -I\${includedir} -I${vcpkg_includedir}\n")
    else()
        file(APPEND "${pc_file}" "Cflags: -I\${includedir}\n")
    endif()

    install(FILES "${pc_file}" DESTINATION "pkgconfig")
endfunction()

