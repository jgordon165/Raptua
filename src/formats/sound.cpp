#include "formats/sound.h"

namespace raptua {

bool decode_dmx_sound(const Bytes& d, Sound& out) {
    if (d.size() < 8 || d[0] != 3 || d[1] != 0) return false;
    out.rate = d[2] | d[3] << 8;
    uint32_t n = uint32_t(d[4] | d[5] << 8 | d[6] << 16 | uint32_t(d[7]) << 24);
    if (out.rate < 4000 || out.rate > 48000) return false;
    if (n > d.size() - 8) n = uint32_t(d.size() - 8);
    out.samples.assign(d.begin() + 8, d.begin() + 8 + long(n));
    return true;
}

bool find_digital_sound(const GlbSet& glb, const std::string& name, Sound& out) {
    auto h = glb.find(name);
    if (!h) return false;
    // The variants follow the marker until the next named item.
    for (uint32_t i = *h + 1; i < *h + 8; ++i) {
        auto e = glb.entry(i);
        if (!e || !e->name.empty()) break;
        if (decode_dmx_sound(glb.read(i), out)) return true;
    }
    return false;
}

} // namespace raptua
