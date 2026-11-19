#include "input.h"

namespace raptua {

void Input::begin_frame() {
    pressed_.clear();
    text.clear();
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
    case SDL_CONTROLLERDEVICEADDED:
        if (!pad_) pad_ = SDL_GameControllerOpen(e.cdevice.which);
        break;
    case SDL_CONTROLLERDEVICEREMOVED:
        if (pad_ && SDL_GameControllerGetAttached(pad_) == SDL_FALSE) { SDL_GameControllerClose(pad_); pad_ = nullptr; }
        break;
    case SDL_CONTROLLERBUTTONDOWN:
    case SDL_CONTROLLERBUTTONUP:
        set(std::string("pad_") + SDL_GameControllerGetStringForButton(SDL_GameControllerButton(e.cbutton.button)),
            e.type == SDL_CONTROLLERBUTTONDOWN);
        break;
    case SDL_CONTROLLERAXISMOTION: {
        const int dead = 12000;
        int v = e.caxis.value;
        if (e.caxis.axis == SDL_CONTROLLER_AXIS_LEFTX) { set("pad_stick_left", v < -dead); set("pad_stick_right", v > dead); }
        if (e.caxis.axis == SDL_CONTROLLER_AXIS_LEFTY) { set("pad_stick_up", v < -dead); set("pad_stick_down", v > dead); }
        if (e.caxis.axis == SDL_CONTROLLER_AXIS_TRIGGERRIGHT) set("pad_trigger_right", v > dead);
        if (e.caxis.axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT) set("pad_trigger_left", v > dead);
        break;
    }
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
