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

function(setup_target_compiled_artifacts_for_install
    target_name
)
    # when installing,
    # - copy the target artifacts (in this case .lib & .dll) to the lib directory withing the install path
    # - create a cmake files that defines cmake targets with all relevant stuff that clients could link to

    # this causes the dependant runtime artifacts such as dlls
    # to be copied into the bin directory
    install(
        TARGETS ${target_name}
        EXPORT ${target_name} # when installing, generate a "targets" file. clients can include this

        # DESTINATION lib/$<CONFIG>
        ARCHIVE DESTINATION lib/${ULTRA_INSTALL_CONFIG}
        RUNTIME DESTINATION bin/${ULTRA_INSTALL_CONFIG}

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
    setup_target_compiled_artifacts_for_install(${target_name})
endfunction()

# Usage:
# get_link_dependencies(myTarget OUT_VAR)
# message("Deps: ${OUT_VAR}")
#
function(get_link_dependencies target out_var)
    set(_seen "")
    set(_result "")

    function(_collect_deps tgt)
        # Prevent infinite recursion
        if("${tgt}" IN_LIST _seen)
            return()
        endif()

        list(APPEND _seen "${tgt}")

        # Get this target's interface link libs
        get_target_property(_libs ${tgt} INTERFACE_LINK_LIBRARIES)

        if(NOT _libs)
            return()
        endif()

        foreach(lib IN LISTS _libs)
            # Skip generator expressions for simplicity
            if(lib MATCHES "^[\\$<]")
                continue()
            endif()

            list(APPEND _result "${lib}")

            if(TARGET ${lib})
                _collect_deps(${lib})
            endif()
        endforeach()
    endfunction()

    _collect_deps(${target})

    # Return unique list
    list(REMOVE_DUPLICATES _result)
    set(${out_var} "${_result}" PARENT_SCOPE)
endfunction()

# Main: generate and install a pkg-config file for a CMake target
#
# Usage:
# generate_pkgconfig(myTarget VERSION 1.0.0 DESCRIPTION "My Core Library")
#
function(generate_pkgconfig target)
    set(options)
    set(oneValueArgs VERSION DESCRIPTION)
    cmake_parse_arguments(GPC "${options}" "${oneValueArgs}" "" ${ARGN})

    if(NOT GPC_VERSION)
        set(GPC_VERSION "0.1.0")
    endif()

    if(NOT GPC_DESCRIPTION)
        set(GPC_DESCRIPTION "${target} library")
    endif()

    # Collect link deps
    get_link_dependencies(${target} DEPS)

    # Convert deps list into -lfoo style
    set(LIBS_PRIVATE "")

    foreach(dep IN LISTS DEPS)
        if(TARGET ${dep})
            # Use the target name as library name (you might need to refine)
            set(LIBS_PRIVATE "${LIBS_PRIVATE} -l${dep}")
        else()
            # Raw string (e.g. -lm, -lpthread)
            set(LIBS_PRIVATE "${LIBS_PRIVATE} ${dep}")
        endif()
    endforeach()

    # Paths
    set(prefix "${CMAKE_INSTALL_PREFIX}")
    set(exec_prefix "\${prefix}")
    set(libdir "\${exec_prefix}/${CMAKE_INSTALL_LIBDIR}")
    set(includedir "\${prefix}/${CMAKE_INSTALL_INCLUDEDIR}")

    # Create the .pc file
    set(pc_file "${CMAKE_CURRENT_BINARY_DIR}/${target}.pc")
    file(WRITE "${pc_file}" "prefix=${prefix}\n")
    file(APPEND "${pc_file}" "exec_prefix=\${prefix}\n")
    file(APPEND "${pc_file}" "libdir=\${exec_prefix}/${CMAKE_INSTALL_LIBDIR}\n")
    file(APPEND "${pc_file}" "includedir=\${prefix}/${CMAKE_INSTALL_INCLUDEDIR}\n\n")
    file(APPEND "${pc_file}" "Name: ${target}\n")
    file(APPEND "${pc_file}" "Description: ${GPC_DESCRIPTION}\n")
    file(APPEND "${pc_file}" "Version: ${GPC_VERSION}\n")
    file(APPEND "${pc_file}" "Libs: -L\${libdir} -l${target}\n")

    if(LIBS_PRIVATE)
        file(APPEND "${pc_file}" "Libs.private:${LIBS_PRIVATE}\n")
    endif()

    file(APPEND "${pc_file}" "Cflags: -I\${includedir}\n")

    # Install it
    install(FILES "${pc_file}" DESTINATION "pkgconfig")
endfunction()