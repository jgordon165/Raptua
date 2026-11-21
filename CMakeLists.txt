cmake_minimum_required(VERSION 3.20)
project(Raptua VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(RAPTUA_TESTS "Build the test suite" ON)
# Folder holding the player's own FILE0000.GLB / FILE0001.GLB. When set, the
# tests that need real game data ([data]) run too; CI never has it.
set(RAPTUA_DATA "" CACHE PATH "Raptor v1.2 data folder for the [data] tests")

# One static MSVC runtime for everything (SDL, Lua and the engine), so
# releases need no Visual C++ redistributable.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

include(FetchContent)

# ---- SDL2 (static) ---------------------------------------------------------
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON  CACHE BOOL "" FORCE)
set(SDL_TEST   OFF CACHE BOOL "" FORCE)
FetchContent_Declare(SDL2
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG        release-2.30.9
    GIT_SHALLOW    TRUE)
FetchContent_MakeAvailable(SDL2)

# ---- Lua 5.4 (built from source; upstream has no CMake) ---------------------
FetchContent_Declare(lua
    GIT_REPOSITORY https://github.com/lua/lua.git
    GIT_TAG        v5.4.7
    GIT_SHALLOW    TRUE)
FetchContent_MakeAvailable(lua)

file(GLOB LUA_SOURCES ${lua_SOURCE_DIR}/*.c)
list(FILTER LUA_SOURCES EXCLUDE REGEX ".*/(lua|luac|onelua|ltests)\\.c$")
add_library(lua_static STATIC ${LUA_SOURCES})
target_include_directories(lua_static PUBLIC ${lua_SOURCE_DIR})
set_target_properties(lua_static PROPERTIES LINKER_LANGUAGE C)
if(UNIX AND NOT APPLE)
    target_compile_definitions(lua_static PRIVATE LUA_USE_LINUX)
    target_link_libraries(lua_static PUBLIC m dl)
elseif(APPLE)
    target_compile_definitions(lua_static PRIVATE LUA_USE_MACOSX)
endif()

# ---- ymfm (Yamaha FM chip emulators, BSD-3; we use its OPL3) ---------------
# Same pinned commit as Meguarace (the project has no release tags).
# SOURCE_SUBDIR points at a folder with no CMakeLists.txt, so only the
# sources are fetched (ymfm's own CMake would build every chip it has).
FetchContent_Declare(ymfm
    GIT_REPOSITORY https://github.com/aaronsgiles/ymfm.git
    GIT_TAG        81aec25ccbb98f4873a255f7551ac4dadac59b4a
    SOURCE_SUBDIR  sources-only)
FetchContent_MakeAvailable(ymfm)
add_library(ymfm_opl STATIC
    ${ymfm_SOURCE_DIR}/src/ymfm_opl.cpp
    ${ymfm_SOURCE_DIR}/src/ymfm_adpcm.cpp
    ${ymfm_SOURCE_DIR}/src/ymfm_pcm.cpp)
target_include_directories(ymfm_opl SYSTEM PUBLIC ${ymfm_SOURCE_DIR}/src)
target_compile_options(ymfm_opl PRIVATE $<IF:$<CXX_COMPILER_ID:MSVC>,/W0,-w>)   # third-party code

function(raptua_warnings target)
    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /permissive- /utf-8)
    else()
        target_compile_options(${target} PRIVATE -Wall -Wextra)
    endif()
endfunction()

# ---- Formats: no SDL, no Lua, so tools and tests can use them alone ---------
add_library(raptua_formats STATIC
    src/formats/glb.cpp
    src/formats/pic.cpp
    src/formats/level.cpp
    src/formats/font.cpp
    src/formats/sound.cpp
    src/formats/mus.cpp)
target_include_directories(raptua_formats PUBLIC src)

# ---- Music synth: no SDL, so the tests can render it ---------------------------
add_library(raptua_music STATIC src/music.cpp)
target_link_libraries(raptua_music PUBLIC raptua_formats ymfm_opl)
raptua_warnings(raptua_music)
raptua_warnings(raptua_formats)

# ---- The game -----------------------------------------------------------------
add_executable(raptua WIN32
    src/main.cpp
    src/video.cpp
    src/audio.cpp
    src/input.cpp
    src/lua_api.cpp)
target_link_libraries(raptua PRIVATE raptua_formats raptua_music lua_static SDL2::SDL2-static)
if(TARGET SDL2::SDL2main)
    target_link_libraries(raptua PRIVATE SDL2::SDL2main)
endif()
raptua_warnings(raptua)
target_compile_definitions(raptua PRIVATE RAPTUA_VERSION="${PROJECT_VERSION}")

# Lua scripts sit next to the executable (scripts/), so the game can be
# modified without a rebuild. Copied on every build, not just when the
# executable relinks, so a Lua-only change always reaches the build folder.
add_custom_target(raptua_scripts ALL
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${CMAKE_SOURCE_DIR}/scripts $<TARGET_FILE_DIR:raptua>/scripts
    COMMENT "Copying Lua scripts")
add_dependencies(raptua_scripts raptua)

# ---- raptua-glb: list / extract / pack the GLB archives ----------------------
add_executable(raptua-glb src/tools/glbtool.cpp)
target_link_libraries(raptua-glb PRIVATE raptua_formats)
raptua_warnings(raptua-glb)

# ---- Tests ----------------------------------------------------------------------
if(RAPTUA_TESTS)
    enable_testing()
    add_executable(raptua_tests tests/test_formats.cpp)
    target_link_libraries(raptua_tests PRIVATE raptua_formats raptua_music)
    raptua_warnings(raptua_tests)
    add_test(NAME formats COMMAND raptua_tests)
    if(RAPTUA_DATA)
        add_test(NAME formats_data COMMAND raptua_tests --data ${RAPTUA_DATA})
        add_test(NAME boot_data COMMAND raptua --headless 120 --data ${RAPTUA_DATA})
    endif()
    # Boots the engine with no game data: it must reach the no-data screen,
    # run the Lua self-tests and exit cleanly.
    add_test(NAME boot_nodata COMMAND raptua --headless 30 --data ${CMAKE_BINARY_DIR}/_nodata)
    add_test(NAME lua_selftest COMMAND raptua --selftest)
    set_tests_properties(boot_nodata lua_selftest PROPERTIES
        ENVIRONMENT "SDL_VIDEODRIVER=dummy;SDL_AUDIODRIVER=dummy")
    if(RAPTUA_DATA)
        set_tests_properties(boot_data PROPERTIES
            ENVIRONMENT "SDL_VIDEODRIVER=dummy;SDL_AUDIODRIVER=dummy")
    endif()
endif()

install(TARGETS raptua raptua-glb RUNTIME DESTINATION .)
install(DIRECTORY scripts DESTINATION .)
install(FILES README.md DESTINATION .)
