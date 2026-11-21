#include "formats/mus.h"

#include <cstring>

namespace raptua {

namespace {
uint16_t rd16(const uint8_t* p) { return uint16_t(p[0] | p[1] << 8); }
} // namespace

bool decode_mus(const Bytes& d, MusScore& out, std::string* err) {
    auto fail = [&](const char* m) { if (err) *err = m; return false; };
    out = MusScore{};
    if (d.size() < 16 || std::memcmp(d.data(), "MUS\x1A", 4) != 0) return fail("not a MUS file");
    uint16_t len = rd16(&d[4]), start = rd16(&d[6]), ninstr = rd16(&d[12]);
    if (16 + size_t(ninstr) * 2 > d.size() || start > d.size()) return fail("MUS header out of range");
    for (int i = 0; i < ninstr; ++i) out.instruments.push_back(rd16(&d[16 + size_t(i) * 2]));
    size_t end = std::min(d.size(), size_t(start) + len);
    size_t p = start;
    auto byte = [&](uint8_t& v) { if (p >= end) return false; v = d[p++]; return true; };
    while (p < end) {
        uint8_t ev;
        byte(ev);
        MusEvent e{MusEventType((ev >> 4) & 7), uint8_t(ev & 15)};
        bool ok = true;
        switch (e.type) {
        case MusEventType::Release: ok = byte(e.a); e.a &= 0x7F; break;
        case MusEventType::Play: {
            uint8_t n = 0;
            ok = byte(n);
            e.a = n & 0x7F;
            e.b = 0xFF;
            if (ok && (n & 0x80)) { ok = byte(e.b); e.b &= 0x7F; }
            break;
        }
        case MusEventType::PitchBend: ok = byte(e.a); break;
        case MusEventType::System: ok = byte(e.a); e.a &= 0x7F; break;
        case MusEventType::Controller: ok = byte(e.a) && byte(e.b); e.a &= 0x7F; e.b &= 0x7F; break;
        case MusEventType::Measure: break;
        case MusEventType::End: break;
        default: return fail("unknown MUS event type");
        }
        if (!ok) return fail("MUS score truncated");
        if (ev & 0x80) {
            uint32_t delay = 0;
            uint8_t b;
            do {
                if (!byte(b)) return fail("MUS delay truncated");
                delay = (delay << 7) | (b & 0x7F);
            } while (b & 0x80);
            e.delay = delay;
        }
        out.length_ticks += e.delay;
        out.events.push_back(e);
        if (e.type == MusEventType::End) break;
    }
    if (out.events.empty() || out.events.back().type != MusEventType::End)
        out.events.push_back({MusEventType::End, 0});
    return true;
}

bool decode_genmidi(const Bytes& d, GenMidi& out) {
    constexpr size_t kIns = 36, kName = 32, kCount = 175;
    if (d.size() < 8 + kCount * kIns || std::memcmp(d.data(), "#OPL_II#", 8) != 0) return false;
    for (size_t i = 0; i < kCount; ++i) {
        const uint8_t* p = &d[8 + i * kIns];
        OplInstrument& in = out.ins[i];
        in.flags = rd16(p);
        in.finetune = p[2];
        in.fixed_note = p[3];
        for (int v = 0; v < 2; ++v) {
            const uint8_t* q = p + 4 + v * 16;
            OplVoice& vo = in.voice[size_t(v)];
            vo.mod = {q[0], q[1], q[2], q[3], q[4], q[5]};
            vo.feedback_conn = q[6];
            vo.car = {q[7], q[8], q[9], q[10], q[11], q[12]};
            vo.note_offset = int16_t(rd16(q + 14));
        }
        size_t np = 8 + kCount * kIns + i * kName;
        if (np + kName <= d.size()) {
            const char* s = reinterpret_cast<const char*>(&d[np]);
            in.name.assign(s, strnlen(s, kName));
        }
    }
    return true;
}

} // namespace raptua
