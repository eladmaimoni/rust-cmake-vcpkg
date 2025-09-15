macro(set_source_group name)
    set(${name} "${ARGN}")
    source_group(${name} FILES ${ARGN})
endmacro(set_source_group)

function(target_disable_console_but_use_normal_main target_name)
    if(WIN32)
        # /ENTRY:mainCRTStartup keeps the same "main" function instead of requiring "WinMain"
        set(SUBSYSTEM_LINKER_OPTIONS /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup)
    else()
        set(SUBSYSTEM_LINKER_OPTIONS -mwindows)
    endif()
endfunction()


# Usage:
#   get_target_output_name(<target> <out_debug_var> <out_release_var>)
#
# Computes the effective output base name for Debug and Release configurations at configure time.
# - Prefers OUTPUT_NAME_DEBUG/OUTPUT_NAME_RELEASE if set.
# - Falls back to OUTPUT_NAME or the target's logical name.
# - Applies *_POSTFIX (target or global) when per-config OUTPUT_NAME is not set.
function(get_target_output_name tgt out_debug out_release)
  if(NOT TARGET "${tgt}")
    message(FATAL_ERROR "get_target_output_name: '${tgt}' is not an existing target.")
  endif()

  # Resolve alias targets to their real targets.
  get_target_property(_aliased "${tgt}" ALIASED_TARGET)
  if(_aliased)
    set(_tgt "${_aliased}")
  else()
    set(_tgt "${tgt}")
  endif()

  # Base name: OUTPUT_NAME or target logical name.
  get_target_property(_base_name "${_tgt}" OUTPUT_NAME)
  if(NOT _base_name OR _base_name STREQUAL "NOTFOUND" OR _base_name STREQUAL "")
    set(_base_name "${_tgt}")
  endif()

  # Debug name: OUTPUT_NAME_DEBUG or base + debug postfix.
  set(_debug_name "${_base_name}")
  get_target_property(_on_debug "${_tgt}" OUTPUT_NAME_DEBUG)
  if(_on_debug AND NOT _on_debug STREQUAL "NOTFOUND" AND NOT _on_debug STREQUAL "")
    set(_debug_name "${_on_debug}")
  else()
    get_target_property(_dbg_postfix "${_tgt}" DEBUG_POSTFIX)
    if(NOT _dbg_postfix OR _dbg_postfix STREQUAL "NOTFOUND")
      if(DEFINED CMAKE_DEBUG_POSTFIX)
        set(_dbg_postfix "${CMAKE_DEBUG_POSTFIX}")
      else()
        set(_dbg_postfix "")
      endif()
    endif()
    set(_debug_name "${_debug_name}${_dbg_postfix}")
  endif()

  # Release name: OUTPUT_NAME_RELEASE or base + release postfix (usually empty).
  set(_release_name "${_base_name}")
  get_target_property(_on_release "${_tgt}" OUTPUT_NAME_RELEASE)
  if(_on_release AND NOT _on_release STREQUAL "NOTFOUND" AND NOT _on_release STREQUAL "")
    set(_release_name "${_on_release}")
  else()
    get_target_property(_rel_postfix "${_tgt}" RELEASE_POSTFIX)
    if(NOT _rel_postfix OR _rel_postfix STREQUAL "NOTFOUND")
      if(DEFINED CMAKE_RELEASE_POSTFIX)
        set(_rel_postfix "${CMAKE_RELEASE_POSTFIX}")
      else()
        set(_rel_postfix "")
      endif()
    endif()
    set(_release_name "${_release_name}${_rel_postfix}")
  endif()

  # Return values to the caller.
  set(${out_debug} "${_debug_name}" PARENT_SCOPE)
  set(${out_release} "${_release_name}" PARENT_SCOPE)
endfunction()

macro(append_target_output_file_and_output_dir target debug_libs debug_dirs release_libs release_dirs)
        
    if(TARGET ${target})
        # this is a cmake target
        # Try to get the actual output file for both Debug and Release configurations.
        # Prefer IMPORTED_IMPLIB/IMPORTED_LOCATION properties if set (for imported targets).        
        # IMPORTED_IMPLIB - On DLL platforms, to the location of the ``.lib`` part of the DLL. or the location of the shared library on other platforms.
        # IMPORTED_LOCATION - The location of the actual library file to be linked against.
        get_target_property(imported_implib_release ${target}  IMPLIB_RELEASE)
        get_target_property(imported_location_release ${target} IMPORTED_LOCATION_RELEASE)
        get_target_property(imported_implib_debug ${target} IMPORTED_IMPLIB_DEBUG)
        get_target_property(imported_location_debug ${target} IMPORTED_LOCATION_DEBUG)

        get_target_output_name(${target} output_name_release output_name_debug)
        if (imported_implib_release)
            set(release_location "${imported_implib_release}")
        elseif (imported_location_release)
            set(release_location "${imported_location_release}")
        else()
            # this is a cmake target that hasn't been installed yet, so we just use the installation
            # location
            set(release_location "${CMAKE_INSTALL_PREFIX}/lib/Release/${output_name_release}")
        endif()

        if (imported_implib_debug)
            set(debug_location "${imported_implib_debug}")
        elseif (imported_location_debug)
            set(debug_location "${imported_location_debug}")
        else()
            # this is a cmake target that hasn't been installed yet, so we just use the installation
            # location
            set(debug_location "${CMAKE_INSTALL_PREFIX}/lib/Debug/${output_name_debug}")
        endif()
        get_filename_component(debug_dir "${debug_location}" DIRECTORY) # directory
        get_filename_component(debug_lib_name "${debug_location}" NAME_WE) # name without extension

        get_filename_component(release_dir "${release_location}" DIRECTORY) # directory
        get_filename_component(release_lib_name "${release_location}" NAME_WE) # name without extension

        LIST(APPEND debug_libs "${debug_lib_name}")
        LIST(APPEND debug_dirs "${debug_dir}")
        LIST(APPEND release_libs "${release_lib_name}")
        LIST(APPEND release_dirs "${release_dir}")
    elseif(target MATCHES "^-l(.+)$")
        # dependency is a raw library dependency
        string(REGEX REPLACE "^-l" "" _lname "${target}")
        list(APPEND debug_libs "${_lname}")
        list(APPEND release_libs "${_lname}")
    endif()
endmacro()
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
        set(_dbg_name_var "_base_${_base}_debug_name")
        set(_dbg_dir_var "_base_${_base}_debug_dir")
        set(${_dbg_name_var} "${lib_name}" PARENT_SCOPE)
        set(${_dbg_dir_var} "${_norm_dir}" PARENT_SCOPE)
    else()
        set(_rel_name_var "_base_${_base}_release_name")
        set(_rel_dir_var "_base_${_base}_release_dir")
        set(${_rel_name_var} "${lib_name}" PARENT_SCOPE)
        set(${_rel_dir_var} "${_norm_dir}" PARENT_SCOPE)
    endif()
endfunction()

# append_to_list_if_not_found(listVar value)
# Appends 'value' to the list variable named by 'listVar' only if it is not already present.
# - listVar: Name of the list variable to modify (unquoted), e.g., my_list.
# - value: Item to add; ignored if empty.
# Writes back to the caller via PARENT_SCOPE.
#
# Example:
#   set(my_libs "a;b")
#   append_to_list_if_not_found(my_libs "b")  # unchanged: "a;b"
#   append_to_list_if_not_found(my_libs "c")  # becomes: "a;b;c"
function(append_to_list_if_not_found listVar value)
    if(NOT "${value}" STREQUAL "")
        # Get current contents of the target list variable.
        set(_tmp_list "${${listVar}}")

        # Check if value already exists.
        list(FIND _tmp_list "${value}" _idx)

        # Append if missing.
        if(_idx EQUAL -1)
            list(APPEND _tmp_list "${value}")
        endif()
        # Write back to caller's scope.
        set(${listVar} "${_tmp_list}" PARENT_SCOPE)
    endif()
endfunction()

# make_absolute_if_possible(input_path out_var)
# Convert input_path to an absolute, normalized (forward-slash) path when possible.
# Behavior:
#   - If input_path is already absolute: normalize separators and return it.
#   - Else if a matching path exists under CMAKE_CURRENT_SOURCE_DIR: resolve to absolute.
#   - Else if a matching path exists under CMAKE_CURRENT_BINARY_DIR: resolve to absolute.
#   - Else: leave the original relative path unchanged.
# Params:
#   - input_path: A path (absolute or relative).
#   - out_var:   Name of the variable to set in the caller (unquoted).
# Writes back via PARENT_SCOPE.
#
# Example:
#   set(rel "include/mylib")
#   make_absolute_if_possible("${rel}" ABS_OUT)  # Resolves if it exists under source or build dir.
#   message(STATUS "Resolved: ${ABS_OUT}")
function(make_absolute_if_possible input_path out_var)
    # Already absolute: just normalize separators.
    if(IS_ABSOLUTE "${input_path}")
        file(TO_CMAKE_PATH "${input_path}" _np)
        set(${out_var} "${_np}" PARENT_SCOPE)
        return()
    endif()

    # Try to resolve relative to the current source/binary dirs.
    set(_candidate "")
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${input_path}")
        set(_candidate "${CMAKE_CURRENT_SOURCE_DIR}/${input_path}")
    elseif(EXISTS "${CMAKE_CURRENT_BINARY_DIR}/${input_path}")
        set(_candidate "${CMAKE_CURRENT_BINARY_DIR}/${input_path}")
    endif()

    if(NOT _candidate STREQUAL "")
        get_filename_component(_abs "${_candidate}" ABSOLUTE)
        file(TO_CMAKE_PATH "${_abs}" _np)
        set(${out_var} "${_np}" PARENT_SCOPE)
    else()
        # Leave unresolved relative path as-is (preserve original behavior).
        set(${out_var} "${input_path}" PARENT_SCOPE)
    endif()
endfunction()

# Collect library filenames (-l names or actual library files) and library directories
# from a list of dependency tokens (typically the result of get_link_dependencies).
# Handles:
# - CMake targets (tries to resolve their IMPORTED / build artifacts)
# - -l<name> tokens
# - -L<path> tokens (adds to directory list only)
# - Absolute or relative paths to library files (*.a, *.so, *.dylib, *.lib)
# Outputs two parent-scope variables without duplicates:
# out_lib_names_var  -> list of library names (no duplicate, no path, no extension)
# out_lib_dirs_var   -> list of absolute directories containing libs (no duplicates)
# Usage example:
# get_link_dependencies(myTarget deps)
# get_library_names_and_paths("${deps}" LIB_NAMES LIB_DIRS)
# message(STATUS "Lib names: ${LIB_NAMES}")
# message(STATUS "Lib dirs:  ${LIB_DIRS}")
function(get_library_names_and_paths dependency_list out_lib_names_var out_lib_dirs_var)
    # Caller passes either:
    # get_library_names_and_paths("${deps}" OUT_LIBS OUT_DIRS)  -> expanded list (quoted to preserve semicolons)
    # or
    # get_library_names_and_paths(deps OUT_LIBS OUT_DIRS)        -> variable name (unquoted)
    # Simplified: if the argument names an existing variable, use its list value; otherwise treat it as the list itself.

    # the user may pass either a variable by name - func(var), or expanded variable - func("${var}")
    # either way in the function scope dependency_list is a string.
    # but we can check if a variable by that name exists in this scope and expand it to a list if so.
    # the goal of this ugly logic is to support both calling conventions.
    if(DEFINED ${dependency_list})
        # the user passed the variable by name, hence it has a value defined,
        set(_dependency_list "${${dependency_list}}")
    else()
        set(_dependency_list "${dependency_list}")
    endif()

    set(_lib_names "")
    set(_lib_dirs "")
    set(_lib_bases "")

    foreach(dependency IN LISTS _dependency_list)
        if(dependency STREQUAL "")
            continue()
        endif()

        string(STRIP "${dependency}" dependency_stripped)

        # Skip generator expressions
        if(dependency_stripped MATCHES "^[\\$<]")
            continue()
        endif()

        # -L<dir>
        if(dependency_stripped MATCHES "^-L(.+)$")
            string(REGEX REPLACE "^-L" "" _dir "${dependency_stripped}")
            make_absolute_if_possible("${_dir}" _dir_norm)

            if(IS_DIRECTORY "${_dir_norm}")
                append_to_list_if_not_found(_lib_dirs "${_dir_norm}")
            endif()
            continue()
        endif()

        # -l<name>
        if(dependency_stripped MATCHES "^-l(.+)$")
            string(REGEX REPLACE "^-l" "" _lname "${dependency_stripped}")
            append_to_list_if_not_found(_lib_names "${_lname}")
            continue()
        endif()

        # Absolute / relative path to library file
        if(dependency_stripped MATCHES "\\.(a|so|dylib|lib)$" OR dependency_stripped MATCHES "\\.lib$" OR dependency_stripped MATCHES "\\.dll$")
            make_absolute_if_possible("${dependency_stripped}" _maybe_path)

            if(EXISTS "${_maybe_path}")
                get_filename_component(_libdir "${_maybe_path}" DIRECTORY)
                get_filename_component(_fname "${_maybe_path}" NAME_WE)

                # Strip common prefixes 'lib' (UNIX) but keep if entire name is just 'lib'
                if(_fname MATCHES "^lib.+" AND NOT _fname STREQUAL "lib")
                    string(REGEX REPLACE "^lib" "" _fname "${_fname}")
                endif()

                append_to_list_if_not_found(_lib_dirs "${_libdir}")
                append_to_list_if_not_found(_lib_names "${_fname}")
                _ulp_register_lib("${_fname}" "${_libdir}")
                continue()
            endif()
        endif()

        # If it's a CMake target, attempt to resolve its library artifact(s)
    if(TARGET ${dependency_stripped})
            # Try config-aware artifact first
            get_target_property(_tTYPE ${dependency_stripped} TYPE)

            if(_tTYPE STREQUAL "INTERFACE_LIBRARY")
            # Interface library has no artifact -> skip (its deps already in list)
            else()
                # Prefer generator expression for file (not evaluated here) is hard; try LOCATION properties
                # Imported / built libs:
                # Iterate potential properties for multi-config
                set(_candidate_files "")

                # Add config-specific properties for common configs to be robust even if CMAKE_BUILD_TYPE empty (multi-config generators)
                # NOTE: Property suffixes for imported locations are upper-case config names.
                # Ensure we query using upper-case to catch artifacts for all multi-config generators.
                foreach(_cfg Debug Release RELWITHDEBINFO MINSIZEREL)
                    foreach(prop IMPORTED_IMPLIB_${_cfg} IMPORTED_LOCATION_${_cfg})
                        get_target_property(_pval ${dependency_stripped} ${prop})

                        if(_pval)
                            list(APPEND _candidate_files "${_pval}")
                        endif()
                    endforeach()
                endforeach()

                # Also try with current CMAKE_BUILD_TYPE (may be lower/mixed case) and plain properties.
                foreach(prop IMPORTED_IMPLIB_${CMAKE_BUILD_TYPE} IMPORTED_LOCATION_${CMAKE_BUILD_TYPE} IMPORTED_IMPLIB IMPORTED_LOCATION)
                    get_target_property(_pval ${dependency_stripped} ${prop})

                    if(_pval)
                        list(APPEND _candidate_files "${_pval}")
                    endif()
                endforeach()

                # Fallback: old LOCATION (may be deprecated)
                get_target_property(_legacy_loc ${dependency_stripped} LOCATION)

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

                        append_to_list_if_not_found(_lib_dirs "${_cfd}")
                        append_to_list_if_not_found(_lib_names "${_cfn}")
                        _ulp_register_lib("${_cfn}" "${_cfd}")
                    else()
                        # If file not found but looks like a debug variant (ends with d) try sibling without d
                        get_filename_component(_cfd "${_cf}" DIRECTORY)
                        get_filename_component(_cfn_full "${_cf}" NAME_WE)
                        if(_cfn_full MATCHES ".+[A-Za-z0-9_]d$")
                            string(REGEX REPLACE "d$" "" _rel_base "${_cfn_full}")
                            if(EXISTS "${_cfd}/${_rel_base}.lib")
                                append_to_list_if_not_found(_lib_dirs "${_cfd}")
                                append_to_list_if_not_found(_lib_names "${_rel_base}")
                                _ulp_register_lib("${_rel_base}" "${_cfd}")
                            endif()
                        endif()
                    endif()
                endforeach()

                # If no artifact found, still record logical target name (last component after ::)
                if(_lib_names STREQUAL "")
                    string(REPLACE "::" ";" _parts "${dependency_stripped}")
                    list(GET _parts -1 _short)
                    append_to_list_if_not_found(_lib_names "${_short}")
                endif()
            endif()
            continue()
        endif()

        # Fallback: raw token - could be a system lib name (e.g., pthread) -> treat as name
        if(NOT dependency_stripped MATCHES "[\\/:]")
            append_to_list_if_not_found(_lib_names "${dependency_stripped}")
        endif()
    endforeach()

    # Build generator-expression aware lists
    set(_gen_lib_names "")
    set(_gen_lib_dirs "")

    foreach(_base IN LISTS _lib_bases)
        set(_rel_name_var "_base_${_base}_release_name")
        set(_dbg_name_var "_base_${_base}_debug_name")
        set(_rel_dir_var "_base_${_base}_release_dir")
        set(_dbg_dir_var "_base_${_base}_debug_dir")

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

    if(_lib_bases)
        set(${out_lib_names_var} "${_gen_lib_names}" PARENT_SCOPE)
        set(${out_lib_dirs_var} "${_gen_lib_dirs}" PARENT_SCOPE)
    else()
        # No base/debug-release mapping captured; fall back to raw collected lists.
        list(REMOVE_DUPLICATES _lib_names)
        list(REMOVE_DUPLICATES _lib_dirs)
        set(${out_lib_names_var} "${_lib_names}" PARENT_SCOPE)
        set(${out_lib_dirs_var} "${_lib_dirs}" PARENT_SCOPE)
    endif()
endfunction()