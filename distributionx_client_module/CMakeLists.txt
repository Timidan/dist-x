cmake_minimum_required(VERSION 3.14)
project(LogosDistributionXClientPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

configure_file(${CMAKE_CURRENT_SOURCE_DIR}/metadata.json ${CMAKE_CURRENT_BINARY_DIR}/metadata.json COPYONLY)

logos_module(
    NAME distributionx_client
    SOURCES
        src/distributionx_client_impl.h
        src/distributionx_client_impl.cpp
        generated_code/distributionx_client_qt_glue.h
        generated_code/distributionx_client_dispatch.cpp
    INCLUDE_DIRS
        ${CMAKE_CURRENT_SOURCE_DIR}/generated_code
)
