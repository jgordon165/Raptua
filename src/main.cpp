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
#include <string>
#include <vector>

#include "formats/fsx.h"
#include "lua_api.h"
#ifdef RAPTUA_XENON_LAYOUT
extern "C" {
#include "xenon_platform.h"
}
#endif

using namespace raptua;

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
#ifdef RAPTUA_XENON_LAYOUT
    // The Xbox 360 starts with no arguments: the GLB files go in data/ in
    // the port's folder on the USB stick (README, "Xbox 360").
    return exe_dir() + "data";
#else
    return exe_dir();
#endif
}

std::string locate_scripts(const std::string& given) {
    if (!given.empty()) return given;
    for (auto d : {exe_dir() + "scripts", std::string("scripts")})
        if (fsx::exists(fsx::join(d, "main.lua"))) return d;
    return exe_dir() + "scripts";
}

// A line for stderr and, on the Xbox 360 (which has no console to read),
// raptua.log in the port's folder.
void log_line(const std::string& msg) {
    std::fprintf(stderr, "%s\n", msg.c_str());
#ifdef RAPTUA_XENON_LAYOUT
    if (FILE* f = std::fopen((exe_dir() + "raptua.log").c_str(), "a")) {
        std::fprintf(f, "%s\n", msg.c_str());
        std::fclose(f);
    }
#endif
}

std::string g_last_error;

// A script error, on screen in the built-in font until a key or button is
// pressed, so a failure is never just a blank screen.
void fatal_screen(Engine* eng, const std::string& msg) {
    if (eng->window.headless()) return;
    Screen& s = eng->screen;
    for (int i = 0; i < 256; ++i) { s.pal[size_t(i * 3)] = uint8_t(i); s.pal[size_t(i * 3 + 1)] = uint8_t(i); s.pal[size_t(i * 3 + 2)] = uint8_t(i); }
    s.fade = 1.0f;
    s.clip = Clip{};
    s.clear(0);
    std::vector<std::string> lines = {"RAPTUA STOPPED WITH AN ERROR", ""};
    std::string text = msg, line;
    for (char c : text) {
        if (c == '\n' || line.size() >= 52) { lines.push_back(line); line.clear(); if (c == '\n') continue; }
        line += c;
    }
    if (!line.empty()) lines.push_back(line);
    lines.push_back("");
#ifdef RAPTUA_XENON_LAYOUT
    lines.push_back("(also in raptua.log)  PRESS START TO EXIT");
#else
    lines.push_back("PRESS ESC TO EXIT");
#endif
    for (size_t i = 0; i < lines.size() && i < 23; ++i) s.sys_text(lines[i], 4, 4 + int(i) * 8, i == 0 ? 255 : 200);
    const Uint32 start = SDL_GetTicks();
    for (;;) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) return;
            // Ignore keys held from before the error for half a second.
            if (ev.type == SDL_KEYDOWN && SDL_GetTicks() - start > 500 &&
                (ev.key.keysym.sym == SDLK_ESCAPE || ev.key.keysym.sym == SDLK_RETURN)) return;
        }
        eng->window.present(s);
        SDL_Delay(16);
    }
}

bool call(lua_State* L, const char* fn, int nargs = 0) {
    lua_getglobal(L, fn);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1 + nargs); return true; }
    if (nargs) lua_insert(L, -1 - nargs);
    if (lua_pcall(L, nargs, 0, 0) != LUA_OK) {
        g_last_error = std::string("lua error in ") + fn + ": " + lua_tostring(L, -1);
        log_line(g_last_error);
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

#ifdef RAPTUA_XENON_LAYOUT
    // The Xbox 360's SDL has no threads, so no timer or game-controller
    // subsystems (the pad arrives as keys).
    Uint32 sdl_flags = SDL_INIT_VIDEO | SDL_INIT_EVENTS | SDL_INIT_AUDIO;
#else
    Uint32 sdl_flags = SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER;
#endif
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
    // Headless runs open audio too (CI sets SDL_AUDIODRIVER=dummy), so the
    // boot tests exercise the music and sound paths.
    eng->audio_ok = eng->audio.open();

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
    log_line("data: " + eng->data_dir + (eng->data_error.empty() ? "" : " (" + eng->data_error + ")"));
    log_line("scripts: " + sdir);
    if (luaL_dofile(L, main_lua.c_str()) != LUA_OK) {
        g_last_error = std::string("lua: ") + lua_tostring(L, -1);
        log_line(g_last_error);
        fatal_screen(eng, g_last_error + "\n\nThe scripts folder must sit next to the game: " + sdir);
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
    if (rc == 2 && !selftest) fatal_screen(eng, g_last_error);
#ifdef RAPTUA_XENON_LAYOUT
    // On the Xbox 360 the title ends here and the console goes back to its
    // dashboard: a black frame, then the platform stops the sound and ends
    // the title. Not a return from main, whose clean-up would run while the
    // sound feeder is still mixing.
    if (!eng->window.headless() && xp_can_exit()) {
        eng->screen.fade = 0.0f;
        eng->window.present(eng->screen);
        xp_exit_title(rc);
    }
#endif
    call(L, "shutdown");
    lua_close(L);
    eng->audio.close();
    eng->window.close();
    delete eng;
    SDL_Quit();
    return rc;
}
