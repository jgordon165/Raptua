#include "audio.h"

#include <algorithm>
#include <cmath>

namespace raptua {

bool Audio::open() {
    SDL_AudioSpec want{}, have{};
    want.freq = 44100;
    want.format = AUDIO_F32SYS;
    want.channels = 2;
    want.samples = 1024;
    want.callback = &Audio::callback;
    want.userdata = this;
    dev_ = SDL_OpenAudioDevice(nullptr, 0, &want, &have, SDL_AUDIO_ALLOW_FREQUENCY_CHANGE);
    if (!dev_) return false;
    rate_ = have.freq;
    SDL_PauseAudioDevice(dev_, 0);
    return true;
}

void Audio::close() {
    if (dev_) SDL_CloseAudioDevice(dev_);
    dev_ = 0;
}

int Audio::add(Sound s) {
    compat::Lock lk(mu_);
    sounds_.push_back(std::move(s));
    return int(sounds_.size()) - 1;
}

void Audio::play(int id, float vol, float pan) {
    compat::Lock lk(mu_);
    if (id < 0 || id >= int(sounds_.size()) || sounds_[size_t(id)].samples.empty()) return;
    // Same effect already playing: restart it. Else a free voice, else the
    // one furthest through its sample.
    Voice* v = nullptr;
    for (auto& c : voices_) if (c.id == id) { v = &c; break; }
    if (!v) for (auto& c : voices_) if (c.id < 0) { v = &c; break; }
    if (!v) v = &*std::max_element(std::begin(voices_), std::end(voices_),
                                   [](const Voice& a, const Voice& b) { return a.pos < b.pos; });
    pan = std::clamp(pan, -1.0f, 1.0f);
    v->id = id;
    v->pos = 0;
    v->step = double(sounds_[size_t(id)].rate) / rate_;
    v->l = vol * std::min(1.0f, 1.0f - pan);
    v->r = vol * std::min(1.0f, 1.0f + pan);
}

bool Audio::playing(int id) {
    compat::Lock lk(mu_);
    for (auto& v : voices_) if (v.id == id) return true;
    return false;
}

void Audio::stop_all() {
    compat::Lock lk(mu_);
    for (auto& v : voices_) v.id = -1;
}

void Audio::set_music_bank(const GenMidi& bank) {
    compat::Lock lk(mu_);
    music_.set_bank(bank);
}

bool Audio::play_music(MusScore score, bool loop) {
    compat::Lock lk(mu_);
    return music_.play(std::move(score), loop);
}

void Audio::stop_music() {
    compat::Lock lk(mu_);
    music_.stop();
}

bool Audio::music_playing() {
    compat::Lock lk(mu_);
    return music_.playing();
}

void Audio::callback(void* self_, Uint8* out_, int len) {
    auto* self = static_cast<Audio*>(self_);
    auto* out = reinterpret_cast<float*>(out_);
    int frames = len / int(sizeof(float) * 2);
    std::fill(out, out + frames * 2, 0.0f);
    compat::Lock lk(self->mu_);
    if (self->music_.playing() && self->music_volume > 0.0f)
        self->music_.render(out, frames, self->rate_, self->music_volume * 1.1f);
    for (auto& v : self->voices_) {
        if (v.id < 0) continue;
        const auto& smp = self->sounds_[size_t(v.id)].samples;
        for (int i = 0; i < frames; ++i) {
            size_t p = size_t(v.pos);
            if (p + 1 >= smp.size()) { v.id = -1; break; }
            double t = v.pos - double(p);
            float s = float((smp[p] * (1 - t) + smp[p + 1] * t - 128.0) / 128.0) * 0.5f;
            out[i * 2] += s * v.l * self->master;
            out[i * 2 + 1] += s * v.r * self->master;
            v.pos += v.step;
        }
    }
    for (int i = 0; i < frames * 2; ++i) out[i] = std::tanh(out[i]);
}

} // namespace raptua
