cmake_minimum_required(VERSION 3.16)
project(celery3d_reference C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Find SDL2
find_package(SDL2 REQUIRED)

# Compiler flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra -O2")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -g -O0 -DDEBUG")

# Source files
set(SOURCES
    src/main.c
    src/rasterizer.c
    src/framebuffer.c
    src/texture.c
    src/math_utils.c
)

# Include directories
include_directories(include ${SDL2_INCLUDE_DIRS})

# Executable
add_executable(celery_ref ${SOURCES})
target_link_libraries(celery_ref ${SDL2_LIBRARIES} m)

# On macOS, we may need to link differently
if(APPLE)
    target_link_libraries(celery_ref "-framework Cocoa")
endif()
