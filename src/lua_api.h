#pragma once
#include "lua_inc.h"

#include <string>

#include "audio.h"
#include "formats/glb.h"
#include "input.h"
#include "video.h"

namespace raptua {

struct Engine {
    GlbSet glb;
    std::string data_dir;
    std::string data_error;   // why no data was found, for the no-data screen
    Screen screen;
    Window window;
    Audio audio;
    Input input;
    int tick_rate = 70;       // updates per second (VGA mode 13h refreshes at 70 Hz)
    bool quit = false;
    // Smooth motion (Options > ADVANCED): draw every displayed frame, not
    // only after a tick, with `alpha` how far (0..1) the clock is into the
    // next tick, for the scripts to place things between game frames.
    bool smooth = false;
    double alpha = 0.0;
    bool audio_ok = false;
};

// Registers the `rap` table (functions listed at the end of lua_api.cpp).
void register_lua_api(lua_State* L, Engine* e);

} // namespace raptua
