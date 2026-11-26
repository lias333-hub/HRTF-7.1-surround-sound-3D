cmake_minimum_required(VERSION 3.10)
project(dacore CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Release speed without -ffast-math: sound quality first (fast-math changes results).
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")
# The Android debug build type would use -O0, which makes the DSP and any benchmark meaningless: always optimise.
if(ANDROID)
  set(CMAKE_CXX_FLAGS_DEBUG "-O3 -g")
endif()
if(NOT CMAKE_BUILD_TYPE AND NOT ANDROID)
  set(CMAKE_BUILD_TYPE Release)
endif()
add_compile_options(-Wall -Wextra -Wno-psabi)

set(DA_SOURCES src/da_core.cpp src/kernels.cpp src/bench.cpp)

# 32-bit ARM: only the kernels file may use NEON instructions. It is called only after a run-time NEON check.
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
