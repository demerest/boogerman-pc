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
genesisrecomp_runner_sources(RUNNER TRACE ON REVERSE_DEBUG ON)

# Two owned-dump profiles: EU (PAL) and US (NTSC). ROMs stay outside the
# checkout; paths are relative to each profile's game dir.
foreach(PROF eu us)
    if(PROF STREQUAL "eu")
        set(_rom "../../../Boogerman (E) [!].gen")
    else()
        set(_rom "../../../Boogerman (U) [!].gen")
    endif()
    set(_game "${CMAKE_SOURCE_DIR}/profiles/${PROF}")
    genesisrecomp_add_generated_sources(GEN_${PROF} boogerman_${PROF}
        "${_game}" "${_rom}" REVERSE_DEBUG ON)
    add_executable(BoogermanRecomp_${PROF} ${RUNNER} ${GEN_${PROF}}
        "${_game}/spec.c")
    add_dependencies(BoogermanRecomp_${PROF} ${GEN_${PROF}_TARGET})
    target_include_directories(BoogermanRecomp_${PROF} PRIVATE
        "${GEN_${PROF}_DIR}" "${RUNNER_ROOT}" "${RUNNER_ROOT}/include"
        "${RUNNER_ROOT}/video" "${RUNNER_ROOT}/external/ymfm/src"
        "${RUNNER_ROOT}/external/superzazu" "${RUNNER_ROOT}/external/clowncommon"
        "${RECOMP_ROOT}/recompiler/src" "${_game}")
    target_compile_definitions(BoogermanRecomp_${PROF} PRIVATE
        INCLUDE_GENERATED_CODE=1 ENABLE_RECOMPILED_CODE=1 DEFAULT_DEBUG_PORT=4400
        GEN_ENABLE_TRACE=1 SONIC_REVERSE_DEBUG=1 GEN_DEV_TRACE=1)
    genesisrecomp_runner_target(BoogermanRecomp_${PROF})
    target_link_libraries(BoogermanRecomp_${PROF} PRIVATE ${BOOGERMAN_SDL_TARGET})
    if(TARGET SDL2::SDL2main)
        target_link_libraries(BoogermanRecomp_${PROF} PRIVATE SDL2::SDL2main)
    endif()
    if(WIN32)
        target_link_libraries(BoogermanRecomp_${PROF} PRIVATE ws2_32 comdlg32)
        if(TARGET SDL2::SDL2)
            add_custom_command(TARGET BoogermanRecomp_${PROF} POST_BUILD
                COMMAND "${CMAKE_COMMAND}" -E copy_if_different
                        "${SDL2_ROOT}/lib/x64/SDL2.dll"
                        "$<TARGET_FILE_DIR:BoogermanRecomp_${PROF}>"
                COMMENT "Copying SDL2.dll next to BoogermanRecomp_${PROF}")
        endif()
    endif()
endforeach()
