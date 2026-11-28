#include "input.h"

#include <cctype>

#ifdef RAPTUA_XENON_LAYOUT
extern "C" unsigned XENON_PadButtons(void);        // platform/xenon/sdl/SDL_xenon_video.c
extern "C" void XENON_SetPadKeyMask(unsigned mask);
extern "C" unsigned XENON_PadButtonsPort(int port);
extern "C" void XENON_SetPadKeyPorts(unsigned ports);
#endif

namespace raptua {

namespace {
// In the bits' order (platform/xenon/xenon_platform.h, XP_BTN_).
const char* const kPadNames[] = {"A", "B", "X", "Y", "LB", "RB", "LT", "RT",
                                 "LS", "RS", "START", "BACK", "UP", "DOWN", "LEFT", "RIGHT"};
const int kPadCount = int(sizeof kPadNames / sizeof *kPadNames);
}  // namespace

unsigned Input::pad_bit(const std::string& button) {
    std::string b;
    for (char c : button) b += char(std::toupper(static_cast<unsigned char>(c)));
    for (int i = 0; i < kPadCount; ++i)
        if (b == kPadNames[i]) return 1u << i;
    return 0;
}

void Input::poll_pad() {
#ifdef RAPTUA_XENON_LAYOUT
    pad_now_ = XENON_PadButtons();
    for (int i = 0; i < 4; ++i) port_now_[i] = XENON_PadButtonsPort(i);
#endif
}

bool Input::pad_held(const std::string& button, int port) const {
    const unsigned b = pad_bit(button);
    if (port >= 1 && port <= 4) return b && (port_now_[port - 1] & b);
    return b && (pad_now_ & b);
}

bool Input::pad_pressed(const std::string& button, int port) const {
    const unsigned b = pad_bit(button);
    if (port >= 1 && port <= 4) return b && (port_now_[port - 1] & b) && !(port_prev_[port - 1] & b);
    return b && (pad_now_ & b) && !(pad_prev_ & b);
}

void Input::pad_keys_first_only(bool on) {
#ifdef RAPTUA_XENON_LAYOUT
    XENON_SetPadKeyPorts(on ? 1u : 0xFu);
#else
    (void)on;
#endif
}

std::string Input::pad_first() const {
    const unsigned went = pad_now_ & ~pad_prev_;
    for (int i = 0; i < kPadCount; ++i)
        if (went & (1u << i)) return kPadNames[i];
    return {};
}

void Input::pad_take(const std::vector<std::string>& buttons) {
    unsigned m = 0;
    for (const auto& b : buttons) m |= pad_bit(b);
#ifdef RAPTUA_XENON_LAYOUT
    XENON_SetPadKeyMask(m);
#else
    (void)m;
#endif
}

#ifndef RAPTUA_XENON_LAYOUT
// 1 for the first controller, 2 for the second (by SDL joystick instance).
int Input::pad_index(SDL_JoystickID id) const {
    if (pad2_ && SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(pad2_)) == id) return 2;
    return 1;
}
#endif

void Input::begin_frame() {
    pressed_.clear();
    text.clear();
    key_down.clear();
    pad_prev_ = pad_now_;
    for (int i = 0; i < 4; ++i) port_prev_[i] = port_now_[i];
    mouse_dx = mouse_dy = 0;
    mouse_moved = false;
}

void Input::set(const std::string& n, bool down) {
    if (down && !held_[n]) pressed_[n] = true;
    held_[n] = down;
}

void Input::event(const SDL_Event& e) {
    switch (e.type) {
    case SDL_KEYDOWN:
    case SDL_KEYUP:
        if (e.key.repeat) {
            if (e.type == SDL_KEYDOWN) pressed_[std::string("repeat_") + SDL_GetKeyName(e.key.keysym.sym)] = true;
            break;
        }
        set(SDL_GetKeyName(e.key.keysym.sym), e.type == SDL_KEYDOWN);
        if (e.type == SDL_KEYDOWN && key_down.empty()) key_down = SDL_GetKeyName(e.key.keysym.sym);
        if (e.type == SDL_KEYDOWN) pressed_[std::string("repeat_") + SDL_GetKeyName(e.key.keysym.sym)] = true;
        break;
    case SDL_TEXTINPUT:
        text += e.text.text;
        break;
    case SDL_MOUSEBUTTONDOWN:
    case SDL_MOUSEBUTTONUP:
        set(e.button.button == SDL_BUTTON_LEFT ? "mouse_left"
            : e.button.button == SDL_BUTTON_RIGHT ? "mouse_right" : "mouse_middle",
            e.type == SDL_MOUSEBUTTONDOWN);
        break;
    case SDL_MOUSEMOTION:
        mouse_dx += e.motion.xrel;
        mouse_dy += e.motion.yrel;
        mouse_moved = true;
        break;
#ifndef RAPTUA_XENON_LAYOUT
    // (The Xbox 360's SDL has no game-controller module: its pad arrives as
    // keyboard keys instead, platform/xenon/sdl/SDL_xenon_video.c.)
    // Two controllers: the first is "pad_...", a second (co-op's player
    // two) "pad2_...".
    case SDL_CONTROLLERDEVICEADDED:
        if (!pad_) pad_ = SDL_GameControllerOpen(e.cdevice.which);
        else if (!pad2_) pad2_ = SDL_GameControllerOpen(e.cdevice.which);
        break;
    case SDL_CONTROLLERDEVICEREMOVED:
        if (pad_ && SDL_GameControllerGetAttached(pad_) == SDL_FALSE) { SDL_GameControllerClose(pad_); pad_ = nullptr; }
        if (pad2_ && SDL_GameControllerGetAttached(pad2_) == SDL_FALSE) { SDL_GameControllerClose(pad2_); pad2_ = nullptr; }
        break;
    case SDL_CONTROLLERBUTTONDOWN:
    case SDL_CONTROLLERBUTTONUP: {
        const char* pre = pad_index(e.cbutton.which) == 2 ? "pad2_" : "pad_";
        set(std::string(pre) + SDL_GameControllerGetStringForButton(SDL_GameControllerButton(e.cbutton.button)),
            e.type == SDL_CONTROLLERBUTTONDOWN);
        break;
    }
    case SDL_CONTROLLERAXISMOTION: {
        const int dead = 12000;
        int v = e.caxis.value;
        const std::string pre = pad_index(e.caxis.which) == 2 ? "pad2_" : "pad_";
        if (e.caxis.axis == SDL_CONTROLLER_AXIS_LEFTX) { set(pre + "stick_left", v < -dead); set(pre + "stick_right", v > dead); }
        if (e.caxis.axis == SDL_CONTROLLER_AXIS_LEFTY) { set(pre + "stick_up", v < -dead); set(pre + "stick_down", v > dead); }
        if (e.caxis.axis == SDL_CONTROLLER_AXIS_TRIGGERRIGHT) set(pre + "trigger_right", v > dead);
        if (e.caxis.axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT) set(pre + "trigger_left", v > dead);
        break;
    }
#endif
    default:
        break;
    }
}

bool Input::held(const std::string& n) const {
    auto it = held_.find(n);
    return it != held_.end() && it->second;
}

bool Input::pressed(const std::string& n) const { return pressed_.count(n) != 0; }

} // namespace raptua
