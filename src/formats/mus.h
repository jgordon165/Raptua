// DMX music: MUS scores (*_MUS) and the GENMIDI.OP2 instrument bank.
//
// MUS: "MUS\x1A", u16 score_len, u16 score_start, u16 channels,
// u16 secondary_channels, u16 instrument_count, u16 reserved,
// u16 instruments[count], then the score at score_start. Each event is one
// byte (bit 7: a delay follows the event; bits 4-6: type; bits 0-3: channel)
// plus data. Delays are 7-bit groups, high bit = more, in 140 Hz ticks.
// Channel 15 is percussion.
//
// GENMIDI.OP2: "#OPL_II#", 175 instruments of 36 bytes (128 melodic, then
// percussion for keys 35..81), then 175 names of 32 bytes.
#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "formats/glb.h"

namespace raptua {

enum class MusEventType : uint8_t {
    Release = 0, Play = 1, PitchBend = 2, System = 3, Controller = 4, Measure = 5, End = 6
};

struct MusEvent {
    MusEventType type;
    uint8_t channel;
    uint8_t a = 0, b = 0;   // Play: note, volume (0xFF = keep last); Controller: number, value;
                            // PitchBend: bend (128 = centre); System: number; Release: note
    uint32_t delay = 0;     // ticks to wait after this event
};

struct MusScore {
    std::vector<MusEvent> events;
    std::vector<uint16_t> instruments;
    uint32_t length_ticks = 0;
    // Raptor's sequencer runs at 70 Hz, not Doom's 140: its music service
    // advances the score 70 times a second (one delay unit per call), paced
    // by the sound card's sample count, never the CPU. At 140 every song
    // played twice as fast.
    static constexpr int kTickHz = 70;
};

bool decode_mus(const Bytes& data, MusScore& out, std::string* err = nullptr);

struct OplOperator {
    uint8_t tremolo_vibrato_sustain_ksr_mult;   // reg 0x20
    uint8_t attack_decay;                       // reg 0x60
    uint8_t sustain_release;                    // reg 0x80
    uint8_t waveform;                           // reg 0xE0
    uint8_t ksl;                                // reg 0x40 high bits
    uint8_t level;                              // reg 0x40 low 6 bits (0 = loudest)
};

struct OplVoice {
    OplOperator mod, car;
    uint8_t feedback_conn;   // reg 0xC0 low bits
    int16_t note_offset;
};

struct OplInstrument {
    uint16_t flags = 0;           // 1 = fixed pitch, 4 = double voice
    uint8_t finetune = 128;       // second voice detune (128 = none)
    uint8_t fixed_note = 0;
    std::array<OplVoice, 2> voice{};
    std::string name;
    bool fixed() const { return flags & 1; }
    bool double_voice() const { return flags & 4; }
};

struct GenMidi {
    std::array<OplInstrument, 175> ins{};
    static constexpr int kPercFirst = 35, kPercLast = 81;
};

bool decode_genmidi(const Bytes& data, GenMidi& out);

} // namespace raptua
