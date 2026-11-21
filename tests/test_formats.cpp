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
#include "formats/mus.h"
#include "formats/swd.h"
#include "music.h"

#include <cmath>

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
    s[468 + 58] = 0x48;                     // path_y[29] = 72 (last entry, ends the record)
    std::vector<SpriteDef> defs;
    CHECK(decode_sprite_lib(s, defs) && defs.size() == 2);
    CHECK(defs[0].name == "SHIP01G1_PIC" && defs[0].f[13] == 7 && defs[0].path_x[1] == -64
          && defs[0].path_y[29] == 72);

    Bytes fl;
    for (int v : {420, 0, 15, 50, 5, 0, -1, 0}) put16(fl, int16_t(v));
    std::vector<FlatDef> flats;
    CHECK(decode_flats(fl, flats) && flats.size() == 2);
    CHECK(flats[0].linkflat == 420 && flats[0].hits == 15 && flats[0].bounty == 50 && flats[1].hits == -1);
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

static Bytes tiny_mus() {
    Bytes m = {'M', 'U', 'S', 0x1A};
    Bytes score = {
        0x40, 0x00, 30,          // controller 0 (instrument) = 30 on channel 0
        0x90, 0x80 | 60, 100, 70,  // play note 60 vol 100, then delay 70 ticks
        0x00, 60,                // release note 60
        0x60,                    // score end
    };
    put16(m, int16_t(score.size())); put16(m, 18); put16(m, 1); put16(m, 0); put16(m, 1); put16(m, 0);
    put16(m, 30);
    m.insert(m.end(), score.begin(), score.end());
    return m;
}

static GenMidi tiny_bank() {
    Bytes b = {'#', 'O', 'P', 'L', '_', 'I', 'I', '#'};
    for (int i = 0; i < 175; ++i) {
        Bytes ins(36, 0);
        ins[2] = 128;
        // modulator: mult 1, fast attack, sustain; carrier the same, level 0
        ins[4] = 0x21; ins[5] = 0xF2; ins[6] = 0x44; ins[9] = 0x10;
        ins[10] = 0x06;
        ins[11] = 0x21; ins[12] = 0xF2; ins[13] = 0x44; ins[16] = 0x00;
        b.insert(b.end(), ins.begin(), ins.end());
    }
    for (int i = 0; i < 175; ++i) { Bytes n(32, 0); n[0] = 'X'; b.insert(b.end(), n.begin(), n.end()); }
    GenMidi g;
    CHECK(decode_genmidi(b, g));
    return g;
}

static double rms(const std::vector<float>& v) {
    double s = 0;
    for (float x : v) s += double(x) * x;
    return v.empty() ? 0 : std::sqrt(s / double(v.size()));
}

static void test_music() {
    MusScore sc;
    CHECK(decode_mus(tiny_mus(), sc));
    CHECK(sc.instruments.size() == 1 && sc.instruments[0] == 30);
    CHECK(sc.events.size() == 4 && sc.events[1].type == MusEventType::Play && sc.events[1].a == 60
          && sc.events[1].b == 100 && sc.events[1].delay == 70 && sc.length_ticks == 70);
    CHECK(sc.events.back().type == MusEventType::End);
    Bytes bad = tiny_mus();
    bad[0] = 'X';
    CHECK(!decode_mus(bad, sc));

    GenMidi g = tiny_bank();
    CHECK(g.ins[30].voice[0].car.attack_decay == 0xF2 && g.ins[0].name == "X");

    OplMusic m;
    CHECK(!m.play(sc, false));   // no bank yet
    m.set_bank(g);
    CHECK(decode_mus(tiny_mus(), sc));
    CHECK(m.play(sc, false));
    std::vector<float> out(44100 / 4 * 2, 0.0f);   // the first quarter second: note sounding
    m.render(out.data(), 44100 / 4, 44100, 1.0f);
    CHECK(rms(out) > 0.01);
    std::vector<float> rest(44100 * 2 * 2, 0.0f);   // past the end: stops by itself
    m.render(rest.data(), 44100 * 2, 44100, 1.0f);
    CHECK(!m.playing());
}

static void test_swd() {
    // A window with one button whose text sits after the fields.
    Bytes w(120, 0);
    auto at32 = [](Bytes& b, size_t o, int32_t v) { for (int i = 0; i < 4; ++i) b[o + size_t(i)] = uint8_t(uint32_t(v) >> (8 * i)); };
    std::memcpy(&w[32], "TEST", 4);
    std::memcpy(&w[48], "TEXTURE_PIC", 11);
    at32(w, 68, 1); at32(w, 76, 120); at32(w, 96, 1);
    at32(w, 100, 72); at32(w, 104, 23); at32(w, 108, 176); at32(w, 112, 154); at32(w, 116, 1);
    Bytes f(148, 0);
    at32(f, 0, 2); at32(f, 4, 7);
    std::memcpy(&f[32], "GO", 2);
    std::memcpy(&f[68], "FONT2_FNT", 9);
    at32(f, 88, 82); at32(f, 92, 6); at32(f, 96, 1); at32(f, 120, 1);
    at32(f, 124, 35); at32(f, 128, 40); at32(f, 132, 100); at32(f, 136, 12);
    at32(f, 140, 148);   // the text right after this (only) field
    w.insert(w.end(), f.begin(), f.end());
    for (char c : std::string("HELLO")) w.push_back(uint8_t(c));
    w.push_back(0);
    SwdWindow win;
    CHECK(decode_swd(w, win));
    CHECK(win.name == "TEST" && win.item_name == "TEXTURE_PIC" && win.fill == 1 && win.w == 176 && win.shadow == 1);
    CHECK(win.fields.size() == 1);
    const SwdField& b = win.fields[0];
    CHECK(b.type == int(SwdFieldType::Button) && b.id == 7 && b.name == "GO" && b.font_name == "FONT2_FNT");
    CHECK(b.font_base == 82 && b.x == 35 && b.h == 12 && b.text == "HELLO");
    Bytes bad = w;
    bad[96] = 200;   // more fields than the data holds
    CHECK(!decode_swd(bad, win));
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
    for (const auto& d : defs) {
        CHECK(d.f[19] >= 0 && d.f[19] <= 30);            // numflight fits the 30-entry path
        CHECK(d.f[20] >= 0 && d.f[20] <= d.f[19]);       // repos: a position on the path
        CHECK(d.f[21] >= 0 && d.f[21] <= 5);             // flight type
    }
    auto t = set.find("STARTG1TILES");
    CHECK(t && decode_pic(set.read(*t + 1), p) && p.width == 32 && p.height == 32);
    std::vector<FlatDef> flats;
    CHECK(decode_flats(set.read("FLATSG1_ITM"), flats) && flats.size() == 672);
    int destructible = 0;
    for (size_t i = 0; i < flats.size(); ++i) {
        if (flats[i].hits < 0) CHECK(flats[i].linkflat == int(i) || flats[i].linkflat >= 0);
        else { ++destructible; CHECK(flats[i].linkflat != int(i) && flats[i].linkflat < 672); }
    }
    CHECK(destructible > 0);
    Font fn;
    CHECK(decode_font(set.read("GAME_FNT"), fn) && fn.has('A'));
    Sound s;
    CHECK(find_digital_sound(set, "EXPLO_FX", s) && !s.samples.empty());
    GenMidi bank;
    CHECK(decode_genmidi(set.read("GENMIDI_OP2"), bank) && !bank.ins[0].name.empty());
    int songs = 0;
    for (const char* name : {"APOGEE_MUS", "RINTRO_MUS", "MAINMENU_MUS", "HANGAR_MUS", "RAP1_MUS", "RAP2_MUS",
                             "RAP3_MUS", "RAP4_MUS", "RAP5_MUS", "RAP6_MUS", "RAP7_MUS", "RAP8_MUS",
                             "BOSS1_MUS", "BOSS2_MUS", "BOSS3_MUS", "BOSS4_MUS"}) {
        MusScore sc;
        std::string err;
        bool ok = decode_mus(set.read(name), sc, &err);
        if (!ok) std::fprintf(stderr, "%s: %s\n", name, err.c_str());
        CHECK(ok && sc.length_ticks > 0);
        songs += ok;
    }
    CHECK(songs == 16);
    {   // RAP1 through the OPL3: audible, stereo, not clipping.
        MusScore sc;
        CHECK(decode_mus(set.read("RAP1_MUS"), sc));
        OplMusic m;
        m.set_bank(bank);
        CHECK(m.play(sc, true));
        std::vector<float> out(44100 * 4 * 2, 0.0f);
        m.render(out.data(), 44100 * 4, 44100, 1.0f);
        float peak = 0;
        for (float x : out) peak = std::max(peak, std::fabs(x));
        CHECK(rms(out) > 0.01 && peak < 1.5f);
        CHECK(m.playing());
    }
    for (const char* fx : {"EXPLO_FX", "EXPLO2_FX", "BONUS_FX", "CRASH_FX", "GEXPLO_FX", "GUN_FX", "HIT_FX",
                           "ESHOT_FX", "WARN_FX", "MISSLE_FX", "LASER_FX", "TURRET_FX", "FLYBY_FX", "SWEP_FX",
                           "JETSND_FX", "BOSS_FX", "DOOR_FX", "EGRAB_FX", "THEME_FX"}) {
        Sound snd;
        bool ok = find_digital_sound(set, fx, snd);
        if (!ok) std::fprintf(stderr, "no digital sound for %s\n", fx);
        CHECK(ok);
    }
    // Window layouts: structure only (their text stays in the player's data).
    for (const char* name : {"MAIN_SWD", "OPTS_SWD", "ASKDIFF_SWD", "ASK_SWD", "MSG_SWD", "CREDIT_SWD", "ORDER_SWD",
                             "HANGAR_SWD", "SHIPCOMP_SWD", "STORE_SWD"}) {
        SwdWindow w;
        bool ok = decode_swd(set.read(name), w);
        if (!ok) std::fprintf(stderr, "can't decode %s\n", name);
        CHECK(ok && !w.fields.empty() && w.w > 0 && w.h > 0);
    }
    {
        SwdWindow m;
        CHECK(decode_swd(set.read("MAIN_SWD"), m));
        int buttons = 0;
        for (const auto& f : m.fields) buttons += f.type == int(SwdFieldType::Button);
        CHECK(buttons == 7);
        SwdWindow o;
        CHECK(decode_swd(set.read("OPTS_SWD"), o));
        int labelled = 0, sliders = 0;
        for (const auto& f : o.fields) { labelled += !f.text.empty() && f.type == int(SwdFieldType::Text); sliders += f.type == int(SwdFieldType::Slider); }
        CHECK(labelled >= 3 && sliders == 2);
    }
    Bytes txt = set.read("CREDITS_TXT");
    CHECK(!txt.empty());
}

int main(int argc, char** argv) {
    test_cipher();
    test_glb();
    test_pic();
    test_level();
    test_font_sound();
    test_music();
    test_swd();
    if (argc >= 3 && std::strcmp(argv[1], "--data") == 0) test_real_data(argv[2]);
    if (g_fail) { std::fprintf(stderr, "%d check(s) failed\n", g_fail); return 1; }
    std::printf("all format tests passed\n");
    return 0;
}
