# patch_core_libdir.cmake
#
# Recursive patcher for Triton repositories to support Fedora lib64 and GCC 15.

message(STATUS "patch_core_libdir: starting recursive patch in ${CMAKE_CURRENT_SOURCE_DIR}")

# Pass the patch script path down to nested fetches
if(NOT TRITON_PATCH_SCRIPT)
  set(TRITON_PATCH_SCRIPT "${CMAKE_CURRENT_LIST_FILE}")
endif()

file(GLOB_RECURSE _cmakelists "CMakeLists.txt")

foreach(_file ${_cmakelists})
  file(READ "${_file}" _content)
  set(_patched "${_content}")
  set(_modified OFF)

  # 1. Update existing LIB_DIR detection to include Fedora
  if(_content MATCHES "DISTRO_ID_LIKE")
    if(NOT _content MATCHES "fedora")
      # Use bracket arguments for regex to avoid escaping nightmares
      string(REGEX REPLACE
        [=[file[ \t]*\([ \t]*STRINGS[ \t]*"/etc/os-release"[ \t]*DISTRO_ID_LIKE[ \t]*REGEX[ \t]*"ID_LIKE"[ \t]*\)]=]
        [=[file(STRINGS "/etc/os-release" DISTRO_ID_LIKE REGEX "ID_LIKE")
      file(STRINGS "/etc/os-release" DISTRO_ID REGEX "^ID=")]=]
        _patched "${_patched}"
      )
      string(REGEX REPLACE
        [=[if[ \t]*\([ \t]*\$\{DISTRO_ID_LIKE\}[ \t]*MATCHES[ \t]*"?rhel[|]centos"?[ \t]*\)]=]
        [=[if("${DISTRO_ID_LIKE}" MATCHES "rhel|centos|fedora" OR "${DISTRO_ID}" MATCHES "fedora")]=]
        _patched "${_patched}"
      )
      string(REGEX REPLACE
        [=[endif[ \t]*\([ \t]*\$\{DISTRO_ID_LIKE\}[ \t]*MATCHES[ \t]*"?rhel[|]centos"?[ \t]*\)]=]
        [=[endif()]=]
        _patched "${_patched}"
      )
      set(_modified ON)
    endif()
  endif()

  # 2. Inject LIB_DIR logic before find_package calls
  # Check for find_package with Protobuf/gRPC etc. using string(REGEX MATCH) for safety
  string(REGEX MATCH [=[find_package[ \t]*\([ \t]*(Protobuf|gRPC|Libevent|absl|CURL|re2|nlohmann_json)]=] _fp_found "${_content}")
  if(_fp_found)
    if(NOT _patched MATCHES "DISTRO_ID_LIKE")
      set(_fedora_logic [=[
# Fedora lib64 support injected by patch_core_libdir.cmake
set(LIB_DIR "lib")
if(NOT DEFINED LIB_DIR_SET_BY_PATCH)
  if(EXISTS "/etc/os-release")
    file(STRINGS "/etc/os-release" DISTRO_ID_LIKE REGEX "ID_LIKE")
    file(STRINGS "/etc/os-release" DISTRO_ID REGEX "^ID=")
    if("${DISTRO_ID_LIKE}" MATCHES "rhel|centos|fedora" OR "${DISTRO_ID}" MATCHES "fedora")
      set(LIB_DIR "lib64")
    endif()
  endif()
  set(LIB_DIR_SET_BY_PATCH ON)
endif()
]=])
      string(REGEX REPLACE
        [=[find_package[ \t]*\([ \t]*(Protobuf|gRPC|Libevent|absl|CURL|re2|nlohmann_json)]=]
        "${_fedora_logic}\nfind_package(\\1"
        _patched "${_patched}"
      )
      set(_modified ON)
    endif()
  endif()

  # 3. Patch nested FetchContent_Declare to use this patcher recursively.
  # Only targets Triton's own "repo-*" sub-repositories (e.g. repo-thirdparty).
  # Third-party deps (pybind11, protobuf, …) must NOT be touched — adding
  # PATCH_COMMAND to their declarations breaks FetchContent registration.
  if(_content MATCHES [=[FetchContent_Declare[ \t]*\([ \t]*repo-]=])
    if(NOT _content MATCHES "PATCH_COMMAND")
      string(REGEX REPLACE
        [=[(FetchContent_Declare[ \t]*\([ \t]*repo-[^ \t)]+)]=]
        "\\1 PATCH_COMMAND \${CMAKE_COMMAND} -P \"${TRITON_PATCH_SCRIPT}\""
        _patched "${_patched}"
      )
      set(_modified ON)
    endif()
  endif()

  # 4. Patch ExternalProject_Add to disable Werror for gRPC
  if(_content MATCHES "ExternalProject_Add" AND _content MATCHES "grpc")
     if(NOT _patched MATCHES "gRPC_WERROR")
       string(REGEX REPLACE
         [=[(ExternalProject_Add[ \t]*\([ \t]*grpc[^)]*)]=]
         [=[\1 CMAKE_CACHE_ARGS -DgRPC_WERROR:BOOL=OFF]=]
         _patched "${_patched}"
       )
       set(_modified ON)
     endif()
  endif()

  # 5. GCC 15 Compatibility: Globally downgrade -Werror to -Wno-error
  if(_patched MATCHES "-Werror")
    string(REPLACE "-Werror" "-Wno-error" _patched "${_patched}")
    set(_modified ON)
  endif()

  if(_modified)
    file(WRITE "${_file}" "${_patched}")
    message(STATUS "patch_core_libdir: Patched ${_file}")
    # Verification as requested
    execute_process(COMMAND grep -E "fedora|lib64|-Wno-error|gRPC_WERROR" "${_file}" OUTPUT_VARIABLE _grep_out)
    message(STATUS "patch_core_libdir: Verifying ${_file} content:\n${_grep_out}")
  endif()
endforeach()

# 6. OpenSSL 3 / gRPC ENGINE API fix
# ssl_transport_security.cc uses ENGINE_* calls guarded by !OPENSSL_IS_BORINGSSL.
# On Fedora/OpenSSL 3 these symbols are gone. Since gRPC uses its own bundled
# BoringSSL, setting OPENSSL_IS_BORINGSSL=1 is correct and gates out that block.
if(_content MATCHES "ExternalProject_Add" AND _content MATCHES "grpc")
  if(NOT _patched MATCHES "OPENSSL_IS_BORINGSSL")
    string(REGEX REPLACE
      [=[(CMAKE_CACHE_ARGS)]=]
      [=[\1
    -DCMAKE_CXX_FLAGS:STRING=-DOPENSSL_IS_BORINGSSL=1]=]
      _patched "${_patched}"
    )
    set(_modified ON)
  endif()
endif()