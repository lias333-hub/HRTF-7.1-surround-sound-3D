cmake_minimum_required(VERSION 3.10)
project(dacore CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Release speed without -ffast-math: sound quality first (fast-math changes results).
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")
# Android Gradle builds "release" as RelWithDebInfo (not Release) and "debug" as Debug (-O0, which would make the DSP and
# any benchmark meaningless): the core is always optimised, whatever the build type.
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-O3 -g -DNDEBUG")
set(CMAKE_CXX_FLAGS_MINSIZEREL "-O3 -DNDEBUG")
if(ANDROID)
  set(CMAKE_CXX_FLAGS_DEBUG "-O3 -g")
endif()
if(NOT CMAKE_BUILD_TYPE AND NOT ANDROID)
  set(CMAKE_BUILD_TYPE Release)
endif()
add_compile_options(-Wall -Wextra -Wno-psabi)

set(DA_SOURCES src/da_core.cpp src/kernels.cpp src/bench.cpp)

# 32-bit ARM: NEON is explicit for the kernels file. NOTE (finding F-02, disassembly of the built library): NDK r23's
# clang already targets NEON by default for armeabi-v7a, so NEON instructions also appear in other files and in libc++
# code. NEON is therefore a baseline requirement of this library on 32-bit ARM, not something we can fence in.
if(ANDROID AND ANDROID_ABI STREQUAL "armeabi-v7a")
  set_source_files_properties(src/kernels.cpp PROPERTIES COMPILE_FLAGS "-mfpu=neon")
endif()

if(ANDROID)
  add_library(dacore SHARED ${DA_SOURCES} jni/da_jni.cpp)
  target_include_directories(dacore PRIVATE include)
  find_library(log-lib log)
  target_link_libraries(dacore ${log-lib})
else()
  # Host build (a normal computer): a static library plus the unit tests.
  add_library(dacore STATIC ${DA_SOURCES})
  target_include_directories(dacore PUBLIC include)
  add_executable(da_tests test/test_core.cpp)
  target_link_libraries(da_tests dacore)
endif()
