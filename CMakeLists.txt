
cmake_minimum_required(VERSION 3.25)

project(by2)

find_package(Eigen3 CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)

add_subdirectory(src)