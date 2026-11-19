// Sound effects. Each NAME_FX item in FILE0000.GLB is an empty marker that is
// followed by unnamed items, one per sound device; the digitized one is a DMX
// sound: u16 format (3), u16 rate, u32 samples, unsigned 8-bit mono PCM.
#pragma once
#include <cstdint>
#include <vector>

#include "formats/glb.h"

namespace raptua {

struct Sound {
    int rate = 11025;
    std::vector<uint8_t> samples;   // unsigned 8-bit
};

bool decode_dmx_sound(const Bytes& data, Sound& out);

// Finds the digitized variant of effect `name` ("EXPLO_FX") in the set.
bool find_digital_sound(const GlbSet& glb, const std::string& name, Sound& out);

} // namespace raptua
