// Movie frames (*_AGX). A movie is a run of AGX items (frame 1 is usually a
// big picture, the rest only what changed). Each frame is a list of runs:
// u16 marker (0 ends the frame), u16 unused, u16 offset, u16 length, then
// `length` palette indices copied to (offset) in the 320x200 screen. An
// all-zero frame changes nothing. A movie's first frame starts with one
// extra byte: the colour to clear the screen to before its runs. See
// docs/formats.md.
#pragma once
#include <cstdint>
#include <vector>

#include "formats/glb.h"

namespace raptua {

struct AgxRun { uint16_t offset, length; uint32_t data; };   // data: index into AgxFrame::pixels

struct AgxFrame {
    std::vector<AgxRun> runs;
    std::vector<uint8_t> pixels;
    bool clear = false;     // first frame: clear the screen to `fill` first
    uint8_t fill = 0;
};

// `first`: the movie's first frame (leading fill byte). False if a run is
// cut short or reaches past the 320x200 screen.
bool decode_agx(const Bytes& data, AgxFrame& out, bool first = false);

// Paints the frame onto a 320x200 buffer (what isn't in a run stays).
void apply_agx(const AgxFrame& f, uint8_t* screen);

} // namespace raptua
