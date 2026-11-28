#include "music.h"

#include <algorithm>
#include <cmath>

#include "ymfm_opl.h"

namespace raptua {

struct OplMusic::Chip : ymfm::ymfm_interface {
    ymfm::ymf262 opl{*this};
};

namespace {

// Operator offsets of the nine two-op channels in one register bank.
constexpr int kOpOffset[9] = {0, 1, 2, 8, 9, 10, 16, 17, 18};
constexpr int kPercChannel = 15;

// Loudness curve shared by note velocity and channel volume: MUS 0..127 to
// linear gain. Squared, roughly as DMX's volume table falls off.
double vol_gain(int v) {
    double x = std::clamp(v, 0, 127) / 127.0;
    return x * x;
}

} // namespace

OplMusic::OplMusic() : chip_(std::make_unique<Chip>()) { reset_chip(); }
OplMusic::~OplMusic() = default;

void OplMusic::write(int reg, int val) {
    // Port 0/1: address/data for bank 0; port 2/3 for bank 1 (0x100+).
    uint32_t port = reg >= 0x100 ? 2 : 0;
    chip_->opl.write(port, uint8_t(reg & 0xFF));
    chip_->opl.write(port + 1, uint8_t(val));
}

void OplMusic::reset_chip() {
    chip_->opl.reset();
    write(0x105, 0x01);   // OPL3 mode: 18 channels, stereo
    write(0x104, 0x00);   // no 4-operator pairs
    write(0x01, 0x20);    // waveform select
    write(0x08, 0x40);    // note select
    write(0xBD, 0x00);    // melodic mode (no rhythm section)
    for (int v = 0; v < kVoices; ++v) {
        int bank = v >= 9 ? 0x100 : 0;
        int c = v % 9;
        write(bank + 0xB0 + c, 0);
        write(bank + 0x40 + kOpOffset[c], 0x3F);
        write(bank + 0x40 + kOpOffset[c] + 3, 0x3F);
    }
    voices_ = {};
}

bool OplMusic::play(MusScore score, bool loop) {
    if (!have_bank_) return false;
    score_ = std::move(score);
    loop_ = loop;
    pos_ = 0;
    wait_ = 0;
    channels_ = {};
    reset_chip();
    timer_acc_ = 0;
    playing_ = true;
    return true;
}

void OplMusic::stop() {
    all_off();
    playing_ = false;
}

void OplMusic::all_off() {
    for (int v = 0; v < kVoices; ++v) if (voices_[size_t(v)].on) voice_key(v, false);
    for (auto& v : voices_) v.channel = -1;
}

void OplMusic::tick() {
    if (!playing_) return;
    if (wait_ > 0) { --wait_; if (wait_ > 0) return; }
    // Run every event due now; each may carry a delay before the next.
    for (int guard = 0; guard < 4096; ++guard) {
        if (pos_ >= score_.events.size()) pos_ = score_.events.size() - 1;
        const MusEvent& e = score_.events[pos_++];
        if (e.type == MusEventType::End) {
            if (!loop_) { stop(); return; }
            all_off();
            channels_ = {};
            pos_ = 0;
            wait_ = 1;
            return;
        }
        event(e);
        if (e.delay) { wait_ = e.delay; return; }
    }
}

void OplMusic::event(const MusEvent& e) {
    Channel& c = channels_[e.channel];
    switch (e.type) {
    case MusEventType::Release: note_off(e.channel, e.a); break;
    case MusEventType::Play:
        if (e.b != 0xFF) c.last_volume = e.b;
        note_on(e.channel, e.a, c.last_volume);
        break;
    case MusEventType::PitchBend:
        c.bend = e.a;
        for (int v = 0; v < kVoices; ++v) if (voices_[size_t(v)].channel == e.channel) voice_freq(v);
        break;
    case MusEventType::System:
        if (e.a == 10 || e.a == 11) {   // all sounds / notes off
            for (int v = 0; v < kVoices; ++v)
                if (voices_[size_t(v)].channel == e.channel) { voice_key(v, false); voices_[size_t(v)].channel = -1; }
        } else if (e.a == 14) {         // reset controllers
            c.volume = 100; c.pan = 64; c.bend = 128;
        }
        break;
    case MusEventType::Controller:
        switch (e.a) {
        case 0: c.instrument = e.b; break;
        case 3:
            c.volume = e.b;
            for (int v = 0; v < kVoices; ++v) if (voices_[size_t(v)].channel == e.channel) voice_level(v);
            break;
        case 4:
            c.pan = e.b;
            for (int v = 0; v < kVoices; ++v) if (voices_[size_t(v)].channel == e.channel) voice_pan(v);
            break;
        default: break;   // bank, modulation, expression, reverb, chorus, pedals: not used by DMX on OPL
        }
        break;
    default: break;
    }
}

int OplMusic::alloc_voice() {
    // A free voice whose note has ended, the oldest first; else steal the
    // oldest sounding one (DMX steals the same way).
    int best = -1;
    for (int v = 0; v < kVoices; ++v) {
        const Voice& vo = voices_[size_t(v)];
        if (vo.channel < 0 && (best < 0 || vo.age < voices_[size_t(best)].age)) best = v;
    }
    if (best >= 0) return best;
    for (int v = 0; v < kVoices; ++v)
        if (best < 0 || voices_[size_t(v)].age < voices_[size_t(best)].age) best = v;
    voice_key(best, false);
    return best;
}

void OplMusic::note_on(int ch, int note, int vol) {
    const OplInstrument* ins;
    int key = note;
    if (ch == kPercChannel) {
        if (note < GenMidi::kPercFirst || note > GenMidi::kPercLast) return;
        ins = &bank_.ins[size_t(128 + note - GenMidi::kPercFirst)];
    } else {
        ins = &bank_.ins[size_t(channels_[size_t(ch)].instrument & 127)];
    }
    if (ins->fixed()) key = ins->fixed_note;
    int halves = ins->double_voice() ? 2 : 1;
    for (int h = 0; h < halves; ++h) {
        int v = alloc_voice();
        Voice& vo = voices_[size_t(v)];
        vo.channel = ch;
        vo.note = note;
        vo.note_volume = vol;
        vo.ins = ins;
        vo.ins_voice = h;
        vo.age = ++age_;
        int n = key + ins->voice[size_t(h)].note_offset;
        while (n < 0) n += 12;
        while (n > 127) n -= 12;
        vo.played = n;
        voice_patch(v);
        voice_level(v);
        voice_pan(v);
        voice_freq(v);
        voice_key(v, true);
    }
}

void OplMusic::note_off(int ch, int note) {
    for (int v = 0; v < kVoices; ++v) {
        Voice& vo = voices_[size_t(v)];
        if (vo.channel == ch && vo.note == note) {
            voice_key(v, false);
            vo.channel = -1;
        }
    }
}

void OplMusic::voice_patch(int v) {
    const Voice& vo = voices_[size_t(v)];
    const OplVoice& p = vo.ins->voice[size_t(vo.ins_voice)];
    int bank = v >= 9 ? 0x100 : 0, c = v % 9;
    int m = bank + kOpOffset[c], k = m + 3;
    write(m + 0x20, p.mod.tremolo_vibrato_sustain_ksr_mult);
    write(m + 0x60, p.mod.attack_decay);
    write(m + 0x80, p.mod.sustain_release);
    write(m + 0xE0, p.mod.waveform & 7);
    write(k + 0x20, p.car.tremolo_vibrato_sustain_ksr_mult);
    write(k + 0x60, p.car.attack_decay);
    write(k + 0x80, p.car.sustain_release);
    write(k + 0xE0, p.car.waveform & 7);
}

void OplMusic::voice_level(int v) {
    const Voice& vo = voices_[size_t(v)];
    if (!vo.ins) return;
    const OplVoice& p = vo.ins->voice[size_t(vo.ins_voice)];
    double g = vol_gain(vo.note_volume) * vol_gain(channels_[size_t(vo.channel < 0 ? 0 : vo.channel)].volume);
    // Attenuation in OPL total-level steps (0.75 dB each) on top of the patch.
    int att = g <= 0.0001 ? 63 : int(std::lround(-20.0 * std::log10(g) / 0.75));
    int bank = v >= 9 ? 0x100 : 0, c = v % 9;
    int m = bank + kOpOffset[c], k = m + 3;
    int car = std::min(63, (p.car.level & 63) + att);
    write(k + 0x40, (p.car.ksl & 0xC0) | car);
    // Additive (AM) connection: the modulator is heard directly, scale it too.
    int mod = (p.feedback_conn & 1) ? std::min(63, (p.mod.level & 63) + att) : (p.mod.level & 63);
    write(m + 0x40, (p.mod.ksl & 0xC0) | mod);
}

void OplMusic::voice_pan(int v) {
    const Voice& vo = voices_[size_t(v)];
    if (!vo.ins) return;
    const OplVoice& p = vo.ins->voice[size_t(vo.ins_voice)];
    int pan = channels_[size_t(vo.channel < 0 ? 0 : vo.channel)].pan;
    int lr = pan < 48 ? 0x10 : pan > 80 ? 0x20 : 0x30;   // OPL3 output A = left, B = right
    int bank = v >= 9 ? 0x100 : 0;
    write(bank + 0xC0 + v % 9, lr | (p.feedback_conn & 0x0F));
}

// Writes the voice's frequency (A0/B0) with the key-on bit as given.
void OplMusic::write_freq(int v, bool key) {
    const Voice& vo = voices_[size_t(v)];
    double semis = vo.played + (channels_[size_t(vo.channel < 0 ? 0 : vo.channel)].bend - 128) / 64.0;
    if (vo.ins_voice == 1) semis += (vo.ins->finetune - 128) / 64.0;   // detuned second voice
    double hz = 440.0 * std::pow(2.0, (semis - 69.0) / 12.0);
    int block = 0;
    double fnum = hz * double(1 << 20) / kChipRate;
    while (fnum >= 1024.0 && block < 7) { fnum /= 2.0; ++block; }
    int f = std::clamp(int(std::lround(fnum)), 0, 1023);
    int bank = v >= 9 ? 0x100 : 0, c = v % 9;
    write(bank + 0xA0 + c, f & 0xFF);
    write(bank + 0xB0 + c, (key ? 0x20 : 0) | block << 2 | f >> 8);
}

void OplMusic::voice_freq(int v) {
    if (voices_[size_t(v)].ins) write_freq(v, voices_[size_t(v)].on);
}

void OplMusic::voice_key(int v, bool on) {
    Voice& vo = voices_[size_t(v)];
    vo.on = on;
    if (vo.ins) write_freq(v, on);
}

void OplMusic::render(float* out, int frames, int rate, float gain) {
    if (rate <= 0) return;
    const double step = kChipRate / rate;
    const float scale = gain / 32768.0f;
    for (int i = 0; i < frames; ++i) {
        resample_pos_ += step;
        while (resample_pos_ >= 1.0) {
            resample_pos_ -= 1.0;
            timer_acc_ -= 1.0;
            while (timer_acc_ < 0) {
                const float t = tempo.load(std::memory_order_relaxed);
                timer_acc_ += kChipRate / (MusScore::kTickHz * double(t > 0.25f ? t : 1.0f));
                tick();
            }
            ymfm::ymf262::output_data o;
            chip_->opl.generate(&o, 1);
            prev_[0] = cur_[0]; prev_[1] = cur_[1];
            cur_[0] = float(o.data[0]);
            cur_[1] = float(o.data[1]);
        }
        float t = float(resample_pos_);
        out[2 * i] += (prev_[0] + (cur_[0] - prev_[0]) * t) * scale;
        out[2 * i + 1] += (prev_[1] + (cur_[1] - prev_[1]) * t) * scale;
    }
}

} // namespace raptua
