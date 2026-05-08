cmake_minimum_required(VERSION 3.14)
project(DistributionXClientTests LANGUAGES CXX)

include(LogosTest)

logos_test(
    NAME distributionx_client_tests
    MODULE_SOURCES ../src/distributionx_client_impl.cpp
    TEST_SOURCES
        main.cpp
        test_distributionx_client.cpp
)
