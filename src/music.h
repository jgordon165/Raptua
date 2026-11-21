// Music: a DMX MUS score played on an emulated OPL3 (ymfm's YMF262, BSD-3)
// with the GENMIDI.OP2 instrument bank, as Raptor sounded on a Sound
// Blaster 16. 18 two-operator voices, stereo from the MUS pan controller.
//
// No SDL here, so the tests render it directly; the mixer (audio.cpp) calls
// render() from the audio thread.
#pragma once
#include <array>
#include <cstdint>
#include <memory>

#include "formats/mus.h"

namespace raptua {

class OplMusic {
public:
    OplMusic();
    ~OplMusic();

    void set_bank(const GenMidi& bank) { bank_ = bank; have_bank_ = true; }
    bool has_bank() const { return have_bank_; }

    // Starts `score` from the beginning. Returns false without a bank.
    bool play(MusScore score, bool loop);
    void stop();
    bool playing() const { return playing_; }

    // Adds `frames` stereo frames at `rate` Hz to `out` (interleaved L/R),
    // scaled by `gain` (1.0 = full scale).
    void render(float* out, int frames, int rate, float gain);

    static constexpr double kChipRate = 14318180.0 / 288.0;   // 49715.9 Hz
    static constexpr int kVoices = 18;

private:
    struct Chip;
    struct Voice {
        int channel = -1;       // MUS channel, -1 = free
        int note = 0;           // the MUS note that started it
        int played = 0;         // the note actually sounding (after offsets)
        int note_volume = 100;
        const OplInstrument* ins = nullptr;
        int ins_voice = 0;      // 0/1: which half of a double-voice instrument
        bool on = false;
        uint32_t age = 0;       // allocation order, for stealing
    };
    struct Channel {
        int instrument = 0, volume = 100, pan = 64, bend = 128, last_volume = 100;
    };

    void reset_chip();
    void write(int reg, int val);
    void tick();                       // one 140 Hz sequencer step
    void event(const MusEvent& e);
    void note_on(int ch, int note, int vol);
    void note_off(int ch, int note);
    void all_off();
    int alloc_voice();
    void voice_key(int v, bool on);
    void voice_freq(int v);
    void write_freq(int v, bool key);
    void voice_level(int v);
    void voice_patch(int v);
    void voice_pan(int v);

    std::unique_ptr<Chip> chip_;
    GenMidi bank_{};
    bool have_bank_ = false;
    MusScore score_;
    bool loop_ = false, playing_ = false;
    size_t pos_ = 0;
    uint32_t wait_ = 0;
    std::array<Voice, kVoices> voices_{};
    std::array<Channel, 16> channels_{};
    uint32_t age_ = 0;
    double timer_acc_ = 0;             // chip samples until the next tick
    double resample_pos_ = 1.0;
    float prev_[2] = {0, 0}, cur_[2] = {0, 0};
};

} // namespace raptua
