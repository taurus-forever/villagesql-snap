cmake_minimum_required(VERSION 3.18)
project(vsql_hello_extension)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(EXTENSION_NAME "vsql_hello")

# The SDK is found through CMAKE_PREFIX_PATH (the unpacked SDK tarball).
find_package(VillageSQLExtensionFramework REQUIRED)
include_directories(${VillageSQLExtensionFramework_INCLUDE_DIR})

add_library(extension SHARED src/extension.cc)
target_compile_options(extension PRIVATE -fPIC)

VEF_CREATE_VEB(
    NAME ${EXTENSION_NAME}
    LIBRARY_TARGET extension
    MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/manifest.json
)
