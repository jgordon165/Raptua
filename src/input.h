// Keyboard, mouse and game controller state, by action name for Lua.
#pragma once
#include <SDL.h>

#include <string>
#include <vector>
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
    std::string key_down;           // the first key pressed this tick (key setup), or ""

    // The Xbox 360 controller's buttons by name (Options > CONTROLLER, the
    // on-screen keyboard): "A", "B", "X", "Y", "LB", "RB", "LT", "RT", "LS",
    // "RS", "START", "BACK", and "UP", "DOWN", "LEFT", "RIGHT" (the D-pad or
    // the left stick). Elsewhere there are none: all false. As in Meguarace.
    void poll_pad();                // after the events: reads the pad
    // port: 0 = any pad, 1..4 = that one (two-player co-op).
    bool pad_held(const std::string& button, int port = 0) const;
    bool pad_pressed(const std::string& button, int port = 0) const;
    // Co-op: only the first pad also makes keys (menus, player one).
    void pad_keys_first_only(bool on);
    std::string pad_first() const;  // a button that went down this tick, or ""
    // The buttons in the list stop being keys too until the next call (an
    // empty list gives them back).
    void pad_take(const std::vector<std::string>& buttons);
    static unsigned pad_bit(const std::string& button);
#ifndef RAPTUA_XENON_LAYOUT
    int pad_index(SDL_JoystickID id) const;
#endif

private:
    // Names are SDL key names ("Left", "Space", "Return") plus pad_* and
    // mouse_left/right.
    std::unordered_map<std::string, bool> held_, pressed_;
    SDL_GameController* pad_ = nullptr;
    unsigned pad_now_ = 0, pad_prev_ = 0;
    unsigned port_now_[4] = {0, 0, 0, 0}, port_prev_[4] = {0, 0, 0, 0};
    SDL_GameController* pad2_ = nullptr;   // a second controller (co-op): "pad2_..." names
    void set(const std::string& n, bool down);
};

} // namespace raptua
