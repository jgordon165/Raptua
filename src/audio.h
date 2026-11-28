// Sound effect mixer: 8 voices of 8-bit DMX samples, resampled to the device.
#pragma once
#include <SDL.h>

#include "compat_mutex.h"
#include <vector>

#include "formats/sound.h"
#include "music.h"

namespace raptua {

class Audio {
public:
    bool open();
    void close();
    int add(Sound s);   // returns a sound id
    // vol 0..1, pan -1..1. A sound already playing on `exclusive` voices is
    // restarted rather than stacked (the original's per-effect priority).
    void play(int id, float vol, float pan);
    bool playing(int id);          // is sound `id` on any voice?
    void stop_all();
    float master = 1.0f;         // sound effects
    float music_volume = 0.7f;
    void set_music_tempo(float t) { music_.tempo.store(t, std::memory_order_relaxed); }

    // Music. play_music() swaps the song in under the mixer lock.
    void set_music_bank(const GenMidi& bank);
    bool play_music(MusScore score, bool loop);
    void stop_music();
    bool music_playing();

private:
    static void callback(void* self, Uint8* out, int len);
    struct Voice { int id = -1; double pos = 0, step = 0; float l = 0, r = 0; };
    SDL_AudioDeviceID dev_ = 0;
    int rate_ = 44100;
    std::vector<Sound> sounds_;
    OplMusic music_;
    Voice voices_[8];
    compat::Mutex mu_;
};

} // namespace raptua
