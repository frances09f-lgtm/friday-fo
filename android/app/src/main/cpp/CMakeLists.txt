cmake_minimum_required(VERSION 3.22.1)
project(friday_shruti CXX)

# Prebuilt needle speech engine (Apache-2.0, Cactus-Compute/needle3 on
# HuggingFace). The static library is fetched by CI into
# needle/lib/arm64-v8a (see .github/workflows/build-apk.yml) and is not
# committed to the repo.
add_library(needle STATIC IMPORTED GLOBAL)
set_target_properties(needle PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/needle/lib/${ANDROID_ABI}/libneedle.a)

add_library(friday_shruti SHARED shruti_jni.cpp)
target_include_directories(friday_shruti
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/needle/include)
find_library(log-lib log)
target_link_libraries(friday_shruti needle ${log-lib})
