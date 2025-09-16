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
        install(
            FILES $<TARGET_PDB_FILE:${target_name}>
            DESTINATION ${lib_dest}
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

    get_target_link_dependencies(${target} dependencies)
    set(debug_libs "")
    set(release_l`ibs "")
    set(debug_dirs "")
    set(release_dirs "")
    set(include_dirs "")

    # Explicitly query both configs for each target dep
    foreach(dep IN LISTS dependencies)
        append_target_output_file_and_output_dir(${dep} debug_libs debug_dirs release_libs release_dirs)
        get_target_property(dep_includes ${dep} INTERFACE_INCLUDE_DIRECTORIES)
        if(dep_includes)
            list(APPEND include_dirs ${dep_includes})
        endif()
    endforeach()

    list(REMOVE_DUPLICATES debug_libs)
    list(REMOVE_DUPLICATES release_libs)
    list(REMOVE_DUPLICATES debug_dirs)
    list(REMOVE_DUPLICATES release_dirs)
    list(REMOVE_DUPLICATES include_dirs)

    # construct a string for package config files

    # Create the .pc file in the build tree and install it
    set(pc_file_debug "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-debug.pc")
    set(pc_file_debug "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.pc")
    
    
    file(APPEND "${pc_file}" "Name: ${target}\n")
    file(APPEND "${pc_file}" "Description: ${arg_DESCRIPTION}\n")
    file(APPEND "${pc_file}" "Version: ${arg_VERSION}\n")
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

    install(FILES "${pc_file_debug}" DESTINATION "pkgconfig")
    install(FILES "${pc_file_release}" DESTINATION "pkgconfig")
endfunction()


function(install_dependency_manifest_for_target target_name)
    get_target_link_dependencies(${target_name} dependencies)
    set(debug_libs "")
    set(release_l`ibs "")
    set(debug_dirs "")
    set(release_dirs "")

    # Explicitly query both configs for each target dep
    foreach(dep IN LISTS dependencies)
        append_target_output_file_and_output_dir(${dep} debug_libs debug_dirs release_libs release_dirs)
    endforeach()

    list(REMOVE_DUPLICATES debug_libs)
    list(REMOVE_DUPLICATES release_libs)
    list(REMOVE_DUPLICATES debug_dirs)
    list(REMOVE_DUPLICATES release_dirs)

    set(_debug_manifest "${CMAKE_CURRENT_BINARY_DIR}/ccore-dependencies-Debug.txt")
    set(_rel_manifest "${CMAKE_CURRENT_BINARY_DIR}/ccore-dependencies-Release.txt")

    file(WRITE "${_debug_manifest}" "# ccore dependency manifest (configuration: Debug)\n# Libraries\n")

    foreach(n IN LISTS debug_libs)
        file(APPEND "${_debug_manifest}" "${n}\n")
    endforeach()

    file(APPEND "${_debug_manifest}" "# Library Paths\n")

    foreach(d IN LISTS debug_dirs)
        file(APPEND "${_debug_manifest}" "${d}\n")
    endforeach()

    file(WRITE "${_rel_manifest}" "# ccore dependency manifest (configuration: Release)\n# Libraries\n")

    foreach(n IN LISTS release_libs)
        file(APPEND "${_rel_manifest}" "${n}\n")
    endforeach()

    file(APPEND "${_rel_manifest}" "# Library Paths\n")

    foreach(d IN LISTS release_dirs)
        file(APPEND "${_rel_manifest}" "${d}\n")
    endforeach()

    install(FILES "${_debug_manifest}" DESTINATION lib/Debug RENAME ccore-dependencies-Debug.txt)
    install(FILES "${_rel_manifest}" DESTINATION lib/Release RENAME ccore-dependencies-Release.txt)
endfunction()
