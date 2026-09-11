cmake_minimum_required(VERSION 3.20)
project(pvsutil VERSION 1.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT MSVC)
    foreach(_flags CMAKE_CXX_FLAGS CMAKE_SHARED_LINKER_FLAGS)
        set(${_flags} "${${_flags}} -m32")
    endforeach()
endif()

set(PVSUTIL_AMXX_ROOT "" CACHE PATH "Root of an amxmodx checkout")

if(NOT PVSUTIL_AMXX_ROOT)
    get_filename_component(_default_amxx "${CMAKE_CURRENT_SOURCE_DIR}/../amxmodx" ABSOLUTE)
    set(PVSUTIL_AMXX_ROOT "${_default_amxx}" CACHE PATH "" FORCE)
endif()

set(_hlsdk "${PVSUTIL_AMXX_ROOT}/build_deps/hlsdk")
set(_metamod "${PVSUTIL_AMXX_ROOT}/build_deps/metamod-hl1/metamod")

foreach(_required
    "${_hlsdk}/common"
    "${_hlsdk}/dlls"
    "${_hlsdk}/engine"
    "${_hlsdk}/public"
    "${_metamod}"
    "${PVSUTIL_AMXX_ROOT}/public"
    "${PVSUTIL_AMXX_ROOT}/public/sdk")
    if(NOT IS_DIRECTORY "${_required}")
        message(FATAL_ERROR "Missing SDK directory: ${_required}. Set PVSUTIL_AMXX_ROOT to an amxmodx checkout with its submodules present.")
    endif()
endforeach()

add_library(pvsutil SHARED
    src/pvsutil.cpp
    "${PVSUTIL_AMXX_ROOT}/public/sdk/amxxmodule.cpp")

if(WIN32)
    target_sources(pvsutil PRIVATE src/pvsutil.def)
endif()

target_include_directories(pvsutil PRIVATE src)
target_include_directories(pvsutil SYSTEM PRIVATE
    "${_hlsdk}/common"
    "${_hlsdk}/dlls"
    "${_hlsdk}/engine"
    "${_hlsdk}/public"
    "${_metamod}"
    "${PVSUTIL_AMXX_ROOT}/public"
    "${PVSUTIL_AMXX_ROOT}/public/sdk")

target_compile_definitions(pvsutil PRIVATE
    HAVE_STDINT_H
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    _CRT_SECURE_NO_WARNINGS
    PVSUTIL_VERSION="${PROJECT_VERSION}")

set(_sdk_source "${PVSUTIL_AMXX_ROOT}/public/sdk/amxxmodule.cpp")

if(MSVC)
    target_compile_options(pvsutil PRIVATE /W4 /EHsc /MT$<$<CONFIG:Debug>:d>)
    target_link_options(pvsutil PRIVATE /MACHINE:X86)
    set_source_files_properties("${_sdk_source}" PROPERTIES COMPILE_OPTIONS "/w")
else()
    target_compile_options(pvsutil PRIVATE -Wall -Wextra -Wno-write-strings)
    set_source_files_properties("${_sdk_source}" PROPERTIES COMPILE_OPTIONS "-w")
    target_compile_options(pvsutil PRIVATE -include cmath)
    target_link_options(pvsutil PRIVATE
        -static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL)
    set_target_properties(pvsutil PROPERTIES
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON)
endif()

if(WIN32 AND NOT MSVC)
    message(WARNING "Non-MSVC Windows toolchain: <cbase.h> will not parse. Use a Visual Studio generator.")
endif()

set_target_properties(pvsutil PROPERTIES
    PREFIX ""
    OUTPUT_NAME $<IF:$<BOOL:${WIN32}>,pvsutil_amxx,pvsutil_amxx_i386>)

include(CheckTypeSize)
check_type_size("void*" PVSUTIL_POINTER_SIZE LANGUAGE CXX)
if(NOT PVSUTIL_POINTER_SIZE EQUAL 4)
    message(FATAL_ERROR
        "HLDS/Metamod is 32-bit but this configuration builds ${PVSUTIL_POINTER_SIZE}-byte "
        "pointers. Use a Win32/x86 generator, or install 32-bit development libraries "
        "(g++-multilib, libc6-dev-i386).")
endif()
