# Helper script to robustly delete the install directory.
# Usage: cmake -P cmake/clear_install.cmake

if(NOT DEFINED ENV{VSCODE_CWD})
  # VS Code tasks usually set workspaceFolder, but we rely on script location relative path.
endif()

get_filename_component(WORKSPACE_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(INSTALL_DIR "${WORKSPACE_DIR}/installed")

if(EXISTS "${INSTALL_DIR}")
  message(STATUS "Removing directory: ${INSTALL_DIR}")
  # On Windows sometimes read-only bits or in-use PDBs block removal. Try to remove children first.
  file(GLOB_RECURSE ALL_PATHS LIST_DIRECTORIES true "${INSTALL_DIR}/*")
  foreach(P IN LISTS ALL_PATHS)
    if(EXISTS "${P}")
      # Clear read-only attribute if set (Windows) by requesting write permission
      file(TO_CMAKE_PATH "${P}" P_NORM)
      # No direct chmod in CMake; rely on remove to ignore attributes.
    endif()
  endforeach()
  file(REMOVE_RECURSE "${INSTALL_DIR}")
  if(EXISTS "${INSTALL_DIR}")
    message(WARNING "Directory still exists after file(REMOVE_RECURSE). Some files may be locked (DLL or PDB in use). Close running processes using installed binaries.")
  else()
    message(STATUS "Directory removed.")
  endif()
else()
  message(STATUS "Install directory not present: ${INSTALL_DIR}")
endif()
