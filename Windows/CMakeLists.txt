cmake_minimum_required(VERSION 3.21)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../Info.plist" app_info)
string(REGEX MATCH "<key>CFBundleShortVersionString</key>[ \t\r\n]*<string>([0-9]+\\.[0-9]+(\\.[0-9]+)?)</string>" version_match "${app_info}")
if(NOT version_match)
    message(FATAL_ERROR "Could not read the release version from Info.plist")
endif()
project(NoCaps VERSION "${CMAKE_MATCH_1}" LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(MSVC)
    add_compile_options(
        $<$<COMPILE_LANGUAGE:CXX>:/W4>
        $<$<COMPILE_LANGUAGE:CXX>:/WX>
        $<$<COMPILE_LANGUAGE:CXX>:/permissive->
        $<$<COMPILE_LANGUAGE:CXX>:/utf-8>)
else()
    add_compile_options(-Wall -Wextra -Wpedantic -Werror)
endif()

enable_testing()
add_executable(NoCapsChecks Tests.cpp)
if(MSVC)
    target_compile_options(NoCapsChecks PRIVATE /UNDEBUG)
else()
    target_compile_options(NoCapsChecks PRIVATE -UNDEBUG)
endif()
add_test(NAME NoCapsChecks COMMAND NoCapsChecks)

if(WIN32)
    enable_language(RC)
    add_executable(NoCaps WIN32 main.cpp NoCaps.rc)
    add_executable(NoCapsRemapperChecks main.cpp)
    target_include_directories(NoCaps PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    foreach(target NoCaps NoCapsRemapperChecks)
        target_compile_definitions(${target} PRIVATE
            UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
            _WIN32_WINNT=0x0A00 NOCAPS_VERSION="${PROJECT_VERSION}")
        target_link_libraries(${target} PRIVATE user32 shell32 advapi32 wtsapi32)
        if(MINGW)
            target_link_options(${target} PRIVATE -static)
        endif()
    endforeach()
    target_compile_definitions(NoCapsRemapperChecks PRIVATE NOCAPS_CHECKS)
    if(MSVC)
        target_link_options(NoCaps PRIVATE /MANIFEST:NO)
        target_compile_options(NoCapsRemapperChecks PRIVATE /UNDEBUG)
    elseif(MINGW)
        target_link_options(NoCaps PRIVATE -municode)
        target_compile_options(NoCapsRemapperChecks PRIVATE -UNDEBUG)
    endif()
    add_test(NAME NoCapsRemapperChecks COMMAND NoCapsRemapperChecks)
endif()
