cmake_minimum_required(VERSION 3.19)
project(BoogermanRecomp VERSION 0.0.1 LANGUAGES C CXX)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(GENESIS_GAME_VERSION "${PROJECT_VERSION}")

set(RECOMP_ROOT "${CMAKE_SOURCE_DIR}/segagenesisrecomp" CACHE PATH "Genesis framework checkout")
set(RUNNER_ROOT "${RECOMP_ROOT}/runner")
set(SDL2_ROOT "${RECOMP_ROOT}/runner/external/SDL2/SDL2-2.28.5" CACHE PATH "SDL2 devel (VC) tree")

find_package(SDL2 REQUIRED CONFIG NO_DEFAULT_PATH PATHS "${SDL2_ROOT}/cmake")
set(BOOGERMAN_SDL_TARGET SDL2::SDL2)
if(TARGET SDL2::SDL2-static)
    set(BOOGERMAN_SDL_TARGET SDL2::SDL2-static)
endif()

include("${RECOMP_ROOT}/cmake/GenesisRecompGenerated.cmake")

# ROM stays outside the checkout; path relative to the game dir (this root).
set(BOOGERMAN_ROM "../Boogerman (E) [!].gen" CACHE STRING "Owned cartridge dump")
genesisrecomp_add_generated_sources(GENERATED boogerman "${CMAKE_SOURCE_DIR}" "${BOOGERMAN_ROM}" REVERSE_DEBUG ON)
genesisrecomp_runner_sources(RUNNER TRACE ON REVERSE_DEBUG ON)

add_executable(BoogermanRecomp ${RUNNER} ${GENERATED} game/boogerman_spec.c)
add_dependencies(BoogermanRecomp ${GENERATED_TARGET})
target_include_directories(BoogermanRecomp PRIVATE
    "${GENERATED_DIR}" "${RUNNER_ROOT}" "${RUNNER_ROOT}/include" "${RUNNER_ROOT}/video"
    "${RUNNER_ROOT}/external/ymfm/src" "${RUNNER_ROOT}/external/superzazu"
    "${RUNNER_ROOT}/external/clowncommon" "${RECOMP_ROOT}/recompiler/src"
    "${CMAKE_SOURCE_DIR}/game")
target_compile_definitions(BoogermanRecomp PRIVATE
    INCLUDE_GENERATED_CODE=1 ENABLE_RECOMPILED_CODE=1 DEFAULT_DEBUG_PORT=4400
    GEN_ENABLE_TRACE=1 SONIC_REVERSE_DEBUG=1 GEN_DEV_TRACE=1)
genesisrecomp_runner_target(BoogermanRecomp)
target_link_libraries(BoogermanRecomp PRIVATE ${BOOGERMAN_SDL_TARGET})
if(TARGET SDL2::SDL2main)
    target_link_libraries(BoogermanRecomp PRIVATE SDL2::SDL2main)
endif()
if(WIN32)
    target_link_libraries(BoogermanRecomp PRIVATE ws2_32 comdlg32)
endif()

if(WIN32 AND TARGET SDL2::SDL2)
    add_custom_command(TARGET BoogermanRecomp POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
                "${SDL2_ROOT}/lib/x64/SDL2.dll" "$<TARGET_FILE_DIR:BoogermanRecomp>"
        COMMENT "Copying SDL2.dll next to the executable")
endif()
