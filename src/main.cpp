// Raptua: Raptor: Call of the Shadows (v1.2) on SDL2, with the game in Lua.
//
//   raptua [--data <dir>] [--scripts <dir>] [--scale N] [--fullscreen]
//          [--headless <ticks>] [--selftest]
//
// The game data (FILE0000.GLB, FILE0001.GLB) comes from the player's own copy
// and is never shipped. Without --data, the executable's folder, the current
// folder and a RAPTOR/ folder beside them are searched.
#include <SDL.h>
#include "lua_inc.h"

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#include "lua_api.h"

using namespace raptua;
namespace fs = std::filesystem;

namespace {

std::string exe_dir() {
    char* b = SDL_GetBasePath();
    std::string s = b ? b : "./";
    SDL_free(b);
    return s;
}

bool has_glb(const std::string& dir) {
    return !find_file_nocase(dir, "FILE0000.GLB").empty() && !find_file_nocase(dir, "FILE0001.GLB").empty();
}

std::string locate_data(const std::string& given) {
    if (!given.empty()) return given;
    std::vector<std::string> c = {exe_dir(), ".", exe_dir() + "RAPTOR", "RAPTOR", exe_dir() + "data", "data"};
    for (auto& d : c) if (has_glb(d)) return d;
    return exe_dir();
}

std::string locate_scripts(const std::string& given) {
    if (!given.empty()) return given;
    for (auto d : {exe_dir() + "scripts", std::string("scripts")})
        if (fs::exists(fs::path(d) / "main.lua")) return d;
    return exe_dir() + "scripts";
}

bool call(lua_State* L, const char* fn, int nargs = 0) {
    lua_getglobal(L, fn);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1 + nargs); return true; }
    if (nargs) lua_insert(L, -1 - nargs);
    if (lua_pcall(L, nargs, 0, 0) != LUA_OK) {
        std::fprintf(stderr, "lua error in %s: %s\n", fn, lua_tostring(L, -1));
        lua_pop(L, 1);
        return false;
    }
    return true;
}

} // namespace

int main(int argc, char** argv) {
    std::string data_arg, scripts_arg;
    int scale = 3, headless_ticks = -1;
    bool fullscreen = false, selftest = false, autoplay = false;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
        if (a == "--data") data_arg = next();
        else if (a == "--scripts") scripts_arg = next();
        else if (a == "--scale") scale = std::max(1, std::atoi(next().c_str()));
        else if (a == "--fullscreen") fullscreen = true;
        else if (a == "--headless") headless_ticks = std::max(0, std::atoi(next().c_str()));
        else if (a == "--autoplay") autoplay = true;
        else if (a == "--selftest") { selftest = true; headless_ticks = 0; }
        else if (a == "--version") { std::printf("raptua %s\n", RAPTUA_VERSION); return 0; }
        else if (a == "--help" || a == "-h") {
            std::printf("usage: raptua [--data DIR] [--scripts DIR] [--scale N] [--fullscreen]\n"
                        "              [--headless TICKS] [--autoplay] [--selftest]\n");
            return 0;
        }
    }
    const bool headless = headless_ticks >= 0;

    Uint32 sdl_flags = SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER;
    if (SDL_Init(sdl_flags) != 0 && SDL_Init(SDL_INIT_TIMER) != 0) {
        std::fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }

    auto* eng = new Engine();
    eng->data_dir = locate_data(data_arg);
    {
        std::string err;
        int n = eng->glb.open_dir(eng->data_dir, &err);
        if (n < 2) eng->data_error = n < 0 ? err : "FILE0000.GLB and FILE0001.GLB not found in " + eng->data_dir;
    }
    if (!eng->window.open("Raptua", scale, fullscreen, headless)) {
        std::fprintf(stderr, "window: %s\n", SDL_GetError());
        return 1;
    }
    eng->audio_ok = !headless && eng->audio.open();

    lua_State* L = luaL_newstate();
    luaL_openlibs(L);
    register_lua_api(L, eng);
    std::string sdir = locate_scripts(scripts_arg);
    {   // require() looks in the scripts folder
        lua_getglobal(L, "package");
        std::string path = sdir + "/?.lua;" + sdir + "/?/init.lua";
        lua_pushstring(L, path.c_str());
        lua_setfield(L, -2, "path");
        lua_pop(L, 1);
        lua_pushboolean(L, selftest);
        lua_setglobal(L, "RAPTUA_SELFTEST");
        lua_pushboolean(L, autoplay);
        lua_setglobal(L, "RAPTUA_AUTOPLAY");
    }
    std::string main_lua = sdir + "/main.lua";
    if (luaL_dofile(L, main_lua.c_str()) != LUA_OK) {
        std::fprintf(stderr, "lua: %s\n", lua_tostring(L, -1));
        return 2;
    }
    int rc = 0;
    if (!call(L, "init")) rc = 2;
    if (selftest) {
        lua_getglobal(L, "selftest");
        if (!lua_isfunction(L, -1) || lua_pcall(L, 0, 1, 0) != LUA_OK || !lua_toboolean(L, -1)) {
            std::fprintf(stderr, "selftest failed: %s\n", lua_isstring(L, -1) ? lua_tostring(L, -1) : "");
            rc = 3;
        }
    }

    const Uint64 freq = SDL_GetPerformanceFrequency();
    Uint64 last = SDL_GetPerformanceCounter(), acc = 0;
    int ticks = 0;
    if (!eng->window.headless()) SDL_StartTextInput();
    while (rc == 0 && !eng->quit && !selftest) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) eng->quit = true;
            if (ev.type == SDL_KEYDOWN && ev.key.keysym.sym == SDLK_RETURN && (ev.key.keysym.mod & KMOD_ALT)) {
                eng->window.toggle_fullscreen();
                continue;
            }
            eng->input.event(ev);
        }
        int mx, my;
        SDL_GetMouseState(&mx, &my);
        eng->window.to_screen(mx, my, eng->input.mouse_x, eng->input.mouse_y);

        // Fixed-rate game ticks; rendering once per loop.
        Uint64 now = SDL_GetPerformanceCounter();
        acc += now - last;
        last = now;
        Uint64 step = freq / Uint64(eng->tick_rate);
        int steps = 0;
        if (headless) { acc = 0; steps = 1; }
        else { while (acc >= step && steps < 8) { acc -= step; ++steps; } if (steps == 8) acc = 0; }
        for (int s = 0; s < steps && rc == 0; ++s) {
            if (!call(L, "update")) rc = 2;
            eng->input.begin_frame();
            ++ticks;
        }
        if (steps && !call(L, "draw")) rc = 2;
        eng->window.present(eng->screen);
        if (headless && ticks >= headless_ticks) break;
        if (!steps) SDL_Delay(1);
    }
    call(L, "shutdown");
    lua_close(L);
    eng->audio.close();
    eng->window.close();
    delete eng;
    SDL_Quit();
    return rc;
}
