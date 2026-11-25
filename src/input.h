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
    bool pad_held(const std::string& button) const;
    bool pad_pressed(const std::string& button) const;
    std::string pad_first() const;  // a button that went down this tick, or ""
    // The buttons in the list stop being keys too until the next call (an
    // empty list gives them back).
    void pad_take(const std::vector<std::string>& buttons);
    static unsigned pad_bit(const std::string& button);

private:
    // Names are SDL key names ("Left", "Space", "Return") plus pad_* and
    // mouse_left/right.
    std::unordered_map<std::string, bool> held_, pressed_;
    SDL_GameController* pad_ = nullptr;
    unsigned pad_now_ = 0, pad_prev_ = 0;
    void set(const std::string& n, bool down);
};

} // namespace raptua
