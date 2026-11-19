// Keyboard, mouse and game controller state, by action name for Lua.
#pragma once
#include <SDL.h>

#include <string>
#include <unordered_map>

namespace raptua {

class Input {
public:
    void begin_frame();             // clears "pressed this tick"
    void event(const SDL_Event& e);
    bool held(const std::string& name) const;
    bool pressed(const std::string& name) const;
    int mouse_x = 0, mouse_y = 0, mouse_dx = 0, mouse_dy = 0;
    bool mouse_moved = false;
    std::string text;               // typed characters this tick (name entry)

private:
    // Names are SDL key names ("Left", "Space", "Return") plus pad_* and
    // mouse_left/right.
    std::unordered_map<std::string, bool> held_, pressed_;
    SDL_GameController* pad_ = nullptr;
    void set(const std::string& n, bool down);
};

} // namespace raptua
