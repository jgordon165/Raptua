// Sound effect mixer: 8 voices of 8-bit DMX samples, resampled to the device.
#pragma once
#include <SDL.h>

#include <mutex>
#include <vector>

#include "formats/sound.h"

namespace raptua {

class Audio {
public:
    bool open();
    void close();
    int add(Sound s);   // returns a sound id
    // vol 0..1, pan -1..1. A sound already playing on `exclusive` voices is
    // restarted rather than stacked (the original's per-effect priority).
    void play(int id, float vol, float pan);
    void stop_all();
    float master = 1.0f;

private:
    static void callback(void* self, Uint8* out, int len);
    struct Voice { int id = -1; double pos = 0, step = 0; float l = 0, r = 0; };
    SDL_AudioDeviceID dev_ = 0;
    int rate_ = 44100;
    std::vector<Sound> sounds_;
    Voice voices_[8];
    std::mutex mu_;
};

} // namespace raptua
