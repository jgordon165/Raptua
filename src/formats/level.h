// Levels (MAPnGn_MAP), the sprite library (SPRITEn_ITM) and tile flags
// (FLATSGn_ITM). See docs/formats.md for what is known and what is a guess.
#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "formats/glb.h"

namespace raptua {

constexpr int kMapW = 9, kMapH = 150, kTile = 32;

struct MapCell { uint16_t tile, tileset; };

struct MapActor {
    int32_t link;    // spawn-group chaining (0 continues, 1/-1 ends)
    int32_t slib;    // index into the sprite library
    int32_t x, y;    // tile column / row
    int32_t game;    // sprite library bank (SPRITE{game+1}_ITM)
    int32_t level;   // difficulty gate
};

struct Level {
    std::array<MapCell, kMapW * kMapH> cells{};
    std::vector<MapActor> actors;
};

bool decode_level(const Bytes& data, Level& out);

// One 528-byte sprite library record. Fields are kept raw: Lua names them
// (scripts/game/splib.lua) while their meanings are being worked out.
struct SpriteDef {
    std::string name;                 // first frame's GLB item name
    std::array<int32_t, 26> f{};      // header ints after the name
    std::array<std::array<int16_t, 24>, 6> table{};   // six short[24] tables
    std::array<int16_t, 29> path_x{}, path_y{};       // flight path (guess)
    int32_t tail = 0;
};
constexpr size_t kSpriteDefSize = 528;

bool decode_sprite_lib(const Bytes& data, std::vector<SpriteDef>& out);

// One per tile of a tile set: the tile it turns into when destroyed, an
// always-zero field, hit points (-1 = indestructible) and the bounty paid.
struct FlatDef { int16_t linkflat, unused, hits, bounty; };
bool decode_flats(const Bytes& data, std::vector<FlatDef>& out);

} // namespace raptua
