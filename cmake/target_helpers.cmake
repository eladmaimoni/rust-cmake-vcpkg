macro(set_source_group name)
    set(${name} "${ARGN}")  
    source_group(${name} FILES ${ARGN}) 
endmacro(set_source_group)

function(target_disable_console_but_use_normal_main target_name)
    if (WIN32)
        # /ENTRY:mainCRTStartup keeps the same "main" function instead of requiring "WinMain"
        set(SUBSYSTEM_LINKER_OPTIONS /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup)
    else()
        set(SUBSYSTEM_LINKER_OPTIONS -mwindows)
    endif()
endfunction()

# Usage:
# get_target_link_dependencies(myTarget OUT_VAR)
# message("Deps: ${OUT_VAR}")
#
function(get_target_link_dependencies target out_var)
    set(_seen "")
    set(_result "")

    macro(_collect_deps tgt)
        # Prevent infinite recursion
        if("${tgt}" IN_LIST _seen)
        # already processed - do nothing
        else()
            list(APPEND _seen "${tgt}")

            # Get this target's interface link libs and regular link libraries
            get_target_property(_iface_libs ${tgt} INTERFACE_LINK_LIBRARIES)
            get_target_property(_link_libs ${tgt} LINK_LIBRARIES)

            set(_libs "")

            if(_iface_libs)
                list(APPEND _libs ${_iface_libs})
            endif()

            if(_link_libs)
                list(APPEND _libs ${_link_libs})
            endif()

            # debug output removed
            if(NOT _libs)
            # nothing to collect
            else()
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
            endif()
        endif()
    endmacro()

    _collect_deps(${target})

    # Return unique list
    list(REMOVE_DUPLICATES _result)
    set(${out_var} "${_result}" PARENT_SCOPE)
endfunction()


# Collect library filenames (-l names or actual library files) and library directories
# from a list of dependency tokens (typically the result of get_link_dependencies).
# Handles:
#   - CMake targets (tries to resolve their IMPORTED / build artifacts)
#   - -l<name> tokens
#   - -L<path> tokens (adds to directory list only)
#   - Absolute or relative paths to library files (*.a, *.so, *.dylib, *.lib)
# Outputs two parent-scope variables without duplicates:
#   out_lib_names_var  -> list of library names (no duplicate, no path, no extension)
#   out_lib_dirs_var   -> list of absolute directories containing libs (no duplicates)
# Usage example:
#   get_link_dependencies(myTarget deps)
#   get_library_names_and_paths("${deps}" LIB_NAMES LIB_DIRS)
#   message(STATUS "Lib names: ${LIB_NAMES}")
#   message(STATUS "Lib dirs:  ${LIB_DIRS}")
function(get_library_names_and_paths dependency_list out_lib_names_var out_lib_dirs_var)
    # Caller passes either:
    #   get_library_names_and_paths("${deps}" OUT_LIBS OUT_DIRS)  -> expanded list (quoted to preserve semicolons)
    # or
    #   get_library_names_and_paths(deps OUT_LIBS OUT_DIRS)        -> variable name (unquoted)
    if(DEFINED ${dependency_list})
        set(_raw_tokens ${${dependency_list}})
    else()
        # dependency_list already holds the expanded tokens (possibly separated by semicolons)
        string(REPLACE "\n" ";" _raw_tokens "${dependency_list}")
    endif()
    set(_lib_names "")
    set(_lib_dirs  "")
    set(_lib_bases "")

    # Register base->debug/release mappings to allow generator expressions later
    function(_ulp_register_lib lib_name lib_dir)
        if(lib_name STREQUAL "")
            return()
        endif()
        # Determine base (strip trailing d if present and preceding char is alnum)
        set(_base "${lib_name}")
        if(_base MATCHES ".+[A-Za-z0-9_]d$")
            string(REGEX REPLACE "d$" "" _maybe "${_base}")
            # We'll treat this as debug variant (typical MSVC naming)
            set(_base "${_maybe}")
            set(_is_debug TRUE)
        else()
            set(_is_debug FALSE)
        endif()

        # Track list of bases
        list(FIND _lib_bases "${_base}" _idx)
        if(_idx EQUAL -1)
            list(APPEND _lib_bases "${_base}")
            set(_lib_bases "${_lib_bases}" PARENT_SCOPE)
        endif()

        # Normalize directory path for storage
        file(TO_CMAKE_PATH "${lib_dir}" _norm_dir)

        if(_is_debug)
            set(_dbg_name_var   "_base_${_base}_debug_name")
            set(_dbg_dir_var    "_base_${_base}_debug_dir")
            set(${_dbg_name_var} "${lib_name}" PARENT_SCOPE)
            set(${_dbg_dir_var}  "${_norm_dir}" PARENT_SCOPE)
        else()
            set(_rel_name_var   "_base_${_base}_release_name")
            set(_rel_dir_var    "_base_${_base}_release_dir")
            set(${_rel_name_var} "${lib_name}" PARENT_SCOPE)
            set(${_rel_dir_var}  "${_norm_dir}" PARENT_SCOPE)
        endif()
    endfunction()

    # Helper: add unique item to list variable name passed
    function(_ulp_add_unique listVar value)
        if(NOT "${value}" STREQUAL "")
            set(_tmp_list "${${listVar}}")
            list(FIND _tmp_list "${value}" _idx)
            if(_idx EQUAL -1)
                list(APPEND _tmp_list "${value}")
                set(${listVar} "${_tmp_list}" PARENT_SCOPE)
            else()
                set(${listVar} "${_tmp_list}" PARENT_SCOPE)
            endif()
        endif()
    endfunction()

    # Normalize path (make absolute) if possible
    function(_ulp_normalize_path input_path out_var)
        if(IS_ABSOLUTE "${input_path}")
            file(TO_CMAKE_PATH "${input_path}" _np)
            set(${out_var} "${_np}" PARENT_SCOPE)
        else()
            # Try to resolve relative to current source/binary dirs
            if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${input_path}")
                get_filename_component(_abs "${CMAKE_CURRENT_SOURCE_DIR}/${input_path}" ABSOLUTE)
                file(TO_CMAKE_PATH "${_abs}" _np)
                set(${out_var} "${_np}" PARENT_SCOPE)
            elseif(EXISTS "${CMAKE_CURRENT_BINARY_DIR}/${input_path}")
                get_filename_component(_abs "${CMAKE_CURRENT_BINARY_DIR}/${input_path}" ABSOLUTE)
                file(TO_CMAKE_PATH "${_abs}" _np)
                set(${out_var} "${_np}" PARENT_SCOPE)
            else()
                set(${out_var} "${input_path}" PARENT_SCOPE)
            endif()
        endif()
    endfunction()

    foreach(tok IN LISTS _raw_tokens)
        if(tok STREQUAL "")
            continue()
        endif()

        string(STRIP "${tok}" tok_stripped)

        # Skip generator expressions
        if(tok_stripped MATCHES "^[\\$<]")
            continue()
        endif()

        # -L<dir>
        if(tok_stripped MATCHES "^-L(.+)$")
            string(REGEX REPLACE "^-L" "" _dir "${tok_stripped}")
            _ulp_normalize_path("${_dir}" _dir_norm)
            if(IS_DIRECTORY "${_dir_norm}")
                _ulp_add_unique(_lib_dirs "${_dir_norm}")
            endif()
            continue()
        endif()

        # -l<name>
        if(tok_stripped MATCHES "^-l(.+)$")
            string(REGEX REPLACE "^-l" "" _lname "${tok_stripped}")
            _ulp_add_unique(_lib_names "${_lname}")
            continue()
        endif()

        # Absolute / relative path to library file
        if(tok_stripped MATCHES "\\.(a|so|dylib|lib)$" OR tok_stripped MATCHES "\\.lib$" OR tok_stripped MATCHES "\\.dll$")
            _ulp_normalize_path("${tok_stripped}" _maybe_path)
            if(EXISTS "${_maybe_path}")
                get_filename_component(_libdir "${_maybe_path}" DIRECTORY)
                get_filename_component(_fname  "${_maybe_path}" NAME_WE)
                # Strip common prefixes 'lib' (UNIX) but keep if entire name is just 'lib'
                if(_fname MATCHES "^lib.+" AND NOT _fname STREQUAL "lib")
                    string(REGEX REPLACE "^lib" "" _fname "${_fname}")
                endif()
                _ulp_add_unique(_lib_dirs "${_libdir}")
                _ulp_add_unique(_lib_names "${_fname}")
                _ulp_register_lib("${_fname}" "${_libdir}")
                continue()
            endif()
        endif()

        # If it's a CMake target, attempt to resolve its library artifact(s)
        if(TARGET ${tok_stripped})
            # Try config-aware artifact first
            get_target_property(_tTYPE ${tok_stripped} TYPE)
            if(_tTYPE STREQUAL "INTERFACE_LIBRARY")
                # Interface library has no artifact -> skip (its deps already in list)
            else()
                # Prefer generator expression for file (not evaluated here) is hard; try LOCATION properties
                # Imported / built libs:
                # Iterate potential properties for multi-config
                set(_candidate_files "")
                # Add config-specific properties for common configs to be robust even if CMAKE_BUILD_TYPE empty (multi-config generators)
                foreach(_cfg Debug Release RelWithDebInfo MinSizeRel)
                    foreach(prop IMPORTED_IMPLIB_${_cfg} IMPORTED_LOCATION_${_cfg})
                        get_target_property(_pval ${tok_stripped} ${prop})
                        if(_pval)
                            list(APPEND _candidate_files "${_pval}")
                        endif()
                    endforeach()
                endforeach()
                foreach(prop IMPORTED_IMPLIB_${CMAKE_BUILD_TYPE} IMPORTED_LOCATION_${CMAKE_BUILD_TYPE} IMPORTED_IMPLIB IMPORTED_LOCATION)
                    get_target_property(_pval ${tok_stripped} ${prop})
                    if(_pval)
                        list(APPEND _candidate_files "${_pval}")
                    endif()
                endforeach()
                # Fallback: old LOCATION (may be deprecated)
                get_target_property(_legacy_loc ${tok_stripped} LOCATION)
                if(_legacy_loc)
                    list(APPEND _candidate_files "${_legacy_loc}")
                endif()

                foreach(_cf IN LISTS _candidate_files)
                    if(EXISTS "${_cf}")
                        get_filename_component(_cfd "${_cf}" DIRECTORY)
                        get_filename_component(_cfn "${_cf}" NAME_WE)
                        if(_cfn MATCHES "^lib.+" AND NOT _cfn STREQUAL "lib")
                            string(REGEX REPLACE "^lib" "" _cfn "${_cfn}")
                        endif()
                        _ulp_add_unique(_lib_dirs "${_cfd}")
                        _ulp_add_unique(_lib_names "${_cfn}")
                        _ulp_register_lib("${_cfn}" "${_cfd}")
                    endif()
                endforeach()
                # If no artifact found, still record logical target name (last component after ::)
                if(_lib_names STREQUAL "")
                    string(REPLACE "::" ";" _parts "${tok_stripped}")
                    list(GET _parts -1 _short)
                    _ulp_add_unique(_lib_names "${_short}")
                endif()
            endif()
            continue()
        endif()

        # Fallback: raw token - could be a system lib name (e.g., pthread) -> treat as name
        if(NOT tok_stripped MATCHES "[\\/:]")
            _ulp_add_unique(_lib_names "${tok_stripped}")
        endif()
    endforeach()
    # Build generator-expression aware lists
    set(_gen_lib_names "")
    set(_gen_lib_dirs  "")
    foreach(_base IN LISTS _lib_bases)
        set(_rel_name_var "_base_${_base}_release_name")
        set(_dbg_name_var "_base_${_base}_debug_name")
        set(_rel_dir_var  "_base_${_base}_release_dir")
        set(_dbg_dir_var  "_base_${_base}_debug_dir")

        set(_have_release FALSE)
        set(_have_debug FALSE)
        if(DEFINED ${_rel_name_var})
            set(_have_release TRUE)
            set(_rel_name ${${_rel_name_var}})
        endif()
        if(DEFINED ${_dbg_name_var})
            set(_have_debug TRUE)
            set(_dbg_name ${${_dbg_name_var}})
        endif()
        if(DEFINED ${_rel_dir_var})
            set(_rel_dir ${${_rel_dir_var}})
        endif()
        if(DEFINED ${_dbg_dir_var})
            set(_dbg_dir ${${_dbg_dir_var}})
        endif()

        # Name expression
        if(_have_release AND _have_debug AND NOT _rel_name STREQUAL _dbg_name)
            set(_name_expr "$<IF:$<CONFIG:Debug>,${_dbg_name},${_rel_name}>")
        elseif(_have_release)
            set(_name_expr "${_rel_name}")
        elseif(_have_debug)
            set(_name_expr "${_dbg_name}")
        else()
            # Fallback to base (shouldn't happen)
            set(_name_expr "${_base}")
        endif()

        # Dir expression
        if(_dbg_dir AND _rel_dir AND NOT _dbg_dir STREQUAL _rel_dir)
            set(_dir_expr "$<IF:$<CONFIG:Debug>,${_dbg_dir},${_rel_dir}>")
        elseif(_rel_dir)
            set(_dir_expr "${_rel_dir}")
        elseif(_dbg_dir)
            set(_dir_expr "${_dbg_dir}")
        else()
            set(_dir_expr "")
        endif()

        list(APPEND _gen_lib_names "${_name_expr}")
        if(NOT _dir_expr STREQUAL "")
            list(APPEND _gen_lib_dirs "${_dir_expr}")
        endif()
    endforeach()

    # Deduplicate expressions
    list(REMOVE_DUPLICATES _gen_lib_names)
    list(REMOVE_DUPLICATES _gen_lib_dirs)

    set(${out_lib_names_var} "${_gen_lib_names}" PARENT_SCOPE)
    set(${out_lib_dirs_var}  "${_gen_lib_dirs}"  PARENT_SCOPE)
endfunction()