// Format tests. The plain run uses synthetic data only (CI has no game data);
// `--data <dir>` also checks the decoders against a real Raptor v1.2 install.
#include <cstdio>
#include <cstring>
#include <string>

#include "formats/font.h"
#include "formats/glb.h"
#include "formats/level.h"
#include "formats/pic.h"
#include "formats/sound.h"

using namespace raptua;

static int g_fail = 0;
#define CHECK(c) do { if (!(c)) { std::fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__, __LINE__, #c); ++g_fail; } } while (0)

static void put32(Bytes& b, int32_t v) { for (int i = 0; i < 4; ++i) b.push_back(uint8_t(uint32_t(v) >> (8 * i))); }
static void put16(Bytes& b, int16_t v) { b.push_back(uint8_t(v)); b.push_back(uint8_t(uint16_t(v) >> 8)); }

static void test_cipher() {
    Bytes b = {'H', 'e', 'l', 'l', 'o', 0, 255, 1};
    Bytes c = b;
    glb_encrypt(c.data(), c.size());
    CHECK(c != b);
    glb_decrypt(c.data(), c.size());
    CHECK(c == b);
    // An all-zero header entry encrypts to the archive signature 64 9B D1 09.
    uint8_t z[4] = {};
    glb_encrypt(z, 4);
    CHECK(z[0] == 0x64 && z[1] == 0x9B && z[2] == 0xD1 && z[3] == 0x09);
}

static void test_glb() {
    std::vector<std::pair<GlbEntry, Bytes>> items = {
        {{"PLAIN_DAT", 0, 0, 0}, Bytes{1, 2, 3}},
        {{"SECRET_TXT", 1, 0, 0}, Bytes{'h', 'i'}},
        {{"", 0, 0, 0}, Bytes{}},
        {{"PLAIN_DAT", 0, 0, 0}, Bytes{9}},
    };
    Bytes arc = GlbFile::build(items);
    GlbFile g;
    std::string err;
    CHECK(g.parse(arc, &err));
    CHECK(g.entries().size() == 4);
    CHECK(g.entries()[1].name == "SECRET_TXT");
    CHECK(g.read(1) == (Bytes{'h', 'i'}));
    CHECK(g.read(0) == (Bytes{1, 2, 3}));
    GlbSet set;
    set.add(GlbFile{});
    set.add(g);
    auto h = set.find("PLAIN_DAT");
    CHECK(h && *h == (1u << 16 | 0));   // first match wins
    CHECK(set.read("SECRET_TXT") == (Bytes{'h', 'i'}));
    CHECK(set.read("MISSING").empty());
    Bytes bad = arc;
    bad[0] ^= 0xFF;
    CHECK(!g.parse(bad));
}

static void test_pic() {
    Bytes raw;
    put32(raw, 1); put32(raw, 1); put32(raw, 0); put32(raw, 2); put32(raw, 2);
    raw.insert(raw.end(), {10, 11, 12, 13});
    Pic p;
    CHECK(decode_pic(raw, p) && !p.sprite && p.width == 2 && p.pixels[3] == 13);

    Bytes spr;
    put32(spr, 0); put32(spr, 0); put32(spr, 1); put32(spr, 4); put32(spr, 3);
    put32(spr, 1); put32(spr, 2); put32(spr, 1 + 2 * 320); put32(spr, 2); spr.push_back(7); spr.push_back(8);
    put32(spr, -1); put32(spr, -1); put32(spr, -1); put32(spr, -1);
    CHECK(decode_pic(spr, p) && p.sprite && p.spans.size() == 1);
    CHECK(p.spans[0].x == 1 && p.spans[0].y == 2 && p.spans[0].count == 2 && p.pixels[1] == 8);

    Bytes pal(768, 63);
    Palette out;
    CHECK(decode_palette(pal, out) && out[0] == 255);
}

static void test_level() {
    Bytes m;
    put32(m, 0); put32(m, 0x1524); put32(m, 1);
    for (int i = 0; i < kMapW * kMapH; ++i) { put16(m, int16_t(i % 7)); put16(m, 0); }
    for (int v : {0, 5, 3, 139, 0, 4}) put32(m, v);
    m[0] = uint8_t(m.size()); m[1] = uint8_t(m.size() >> 8);
    Level lv;
    CHECK(decode_level(m, lv));
    CHECK(lv.cells[8].tile == 1 && lv.actors.size() == 1 && lv.actors[0].y == 139 && lv.actors[0].slib == 5);

    Bytes s(kSpriteDefSize * 2, 0);
    std::memcpy(s.data(), "SHIP01G1_PIC", 12);
    s[16 + 13 * 4] = 7;     // f[13]
    s[408 + 2] = 0xC0; s[408 + 3] = 0xFF;   // path_x[1] = -64
    std::vector<SpriteDef> defs;
    CHECK(decode_sprite_lib(s, defs) && defs.size() == 2);
    CHECK(defs[0].name == "SHIP01G1_PIC" && defs[0].f[13] == 7 && defs[0].path_x[1] == -64);
}

static void test_font_sound() {
    Bytes f;
    put32(f, 2);
    for (int i = 0; i < 256; ++i) put16(f, i == 'A' ? 0 : -1);
    for (int i = 0; i < 256; ++i) f.push_back(i == 'A' ? 3 : 0);
    f.insert(f.end(), {1, 0, 1, 0, 1, 0});
    Font fn;
    CHECK(decode_font(f, fn) && fn.has('A') && !fn.has('B') && fn.width['A'] == 3);

    Bytes snd = {3, 0, 0x11, 0x2B, 4, 0, 0, 0, 128, 255, 0, 128};
    Sound s;
    CHECK(decode_dmx_sound(snd, s) && s.rate == 11025 && s.samples.size() == 4);
    Bytes other = {2, 0, 1, 0};
    CHECK(!decode_dmx_sound(other, s));
}

static void test_real_data(const std::string& dir) {
    GlbSet set;
    std::string err;
    int n = set.open_dir(dir, &err);
    CHECK(n >= 2);
    if (n < 2) { std::fprintf(stderr, "%s\n", err.c_str()); return; }
    Palette pal;
    CHECK(decode_palette(set.read("PALETTE_DAT"), pal));
    Pic p;
    CHECK(decode_pic(set.read("HANGER_PIC"), p) && p.width == 320 && p.height == 200);
    Level lv;
    CHECK(decode_level(set.read("MAP1G1_MAP"), lv) && !lv.actors.empty());
    std::vector<SpriteDef> defs;
    CHECK(decode_sprite_lib(set.read("SPRITE1_ITM"), defs) && !defs.empty());
    for (const auto& a : lv.actors) CHECK(a.slib >= 0 && size_t(a.slib) < defs.size());
    auto t = set.find("STARTG1TILES");
    CHECK(t && decode_pic(set.read(*t + 1), p) && p.width == 32 && p.height == 32);
    Font fn;
    CHECK(decode_font(set.read("GAME_FNT"), fn) && fn.has('A'));
    Sound s;
    CHECK(find_digital_sound(set, "EXPLO_FX", s) && !s.samples.empty());
    Bytes txt = set.read("CREDITS_TXT");
    CHECK(!txt.empty());
}

int main(int argc, char** argv) {
    test_cipher();
    test_glb();
    test_pic();
    test_level();
    test_font_sound();
    if (argc >= 3 && std::strcmp(argv[1], "--data") == 0) test_real_data(argv[2]);
    if (g_fail) { std::fprintf(stderr, "%d check(s) failed\n", g_fail); return 1; }
    std::printf("all format tests passed\n");
    return 0;
}
