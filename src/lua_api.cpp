#include <cctype>
#include "lua_api.h"
#ifdef RAPTUA_XENON_LAYOUT
extern "C" {
#include "xenon_platform.h"
}
#endif

#include <cstring>
#include <memory>
#include <unordered_map>

#include "formats/level.h"
#include "formats/mus.h"
#include "formats/swd.h"
#include "formats/agx.h"

namespace raptua {

namespace {

Engine* E(lua_State* L) {
    return static_cast<Engine*>(lua_touserdata(L, lua_upvalueindex(1)));
}

// Decoded images and fonts are cached by GLB handle; Lua passes handles
// (integers) or item names.
struct Caches {
    std::unordered_map<uint32_t, std::unique_ptr<Pic>> pics;
    std::unordered_map<uint32_t, std::unique_ptr<Font>> fonts;
    std::unordered_map<uint32_t, int> sounds;
};
Caches g_cache;

std::optional<uint32_t> handle_arg(lua_State* L, Engine* e, int idx) {
    if (lua_type(L, idx) == LUA_TNUMBER) return uint32_t(lua_tointeger(L, idx));
    if (lua_type(L, idx) == LUA_TSTRING) return e->glb.find(lua_tostring(L, idx));
    return std::nullopt;
}

const Pic* get_pic(lua_State* L, Engine* e, int idx) {
    auto h = handle_arg(L, e, idx);
    if (!h) return nullptr;
    auto it = g_cache.pics.find(*h);
    if (it != g_cache.pics.end()) return it->second.get();
    auto p = std::make_unique<Pic>();
    if (!decode_pic(e->glb.read(*h), *p)) p.reset();
    return (g_cache.pics[*h] = std::move(p)).get();
}

const Font* get_font(lua_State* L, Engine* e, int idx) {
    auto h = handle_arg(L, e, idx);
    if (!h) return nullptr;
    auto it = g_cache.fonts.find(*h);
    if (it != g_cache.fonts.end()) return it->second.get();
    auto f = std::make_unique<Font>();
    if (!decode_font(e->glb.read(*h), *f)) f.reset();
    return (g_cache.fonts[*h] = std::move(f)).get();
}

void set_int(lua_State* L, const char* k, lua_Integer v) { lua_pushinteger(L, v); lua_setfield(L, -2, k); }

// ---- archive -------------------------------------------------------------------

int l_have_data(lua_State* L) { lua_pushboolean(L, E(L)->glb.file_count() >= 2); return 1; }
int l_data_error(lua_State* L) { lua_pushstring(L, E(L)->data_error.c_str()); return 1; }
int l_data_dir(lua_State* L) { lua_pushstring(L, E(L)->data_dir.c_str()); return 1; }

// can_exit() -> bool: whether Quit makes sense here (always on a PC; on the
// Xbox 360 only the .xex, which goes back to the dashboard).
int l_can_exit(lua_State* L) {
#ifdef RAPTUA_XENON_LAYOUT
    lua_pushboolean(L, xp_can_exit());
#else
    lua_pushboolean(L, 1);
#endif
    return 1;
}

// sys_text(str, x, y [, color]) -> width: the built-in 5x8 font, for
// messages when the game's fonts aren't there.
int l_sys_text(lua_State* L) {
    auto* e = E(L);
    int w = e->screen.sys_text(luaL_checkstring(L, 1), int(luaL_checkinteger(L, 2)), int(luaL_checkinteger(L, 3)),
                               uint8_t(luaL_optinteger(L, 4, 255)));
    lua_pushinteger(L, w);
    return 1;
}

// data_file(name) -> bytes | nil: a loose file in the data folder (next to the
// GLBs), e.g. the original's pilot saves. Tries the name as given, upper and
// lower case.
int l_data_file(lua_State* L) {
    std::string name = luaL_checkstring(L, 1);
    if (name.find('/') != std::string::npos || name.find('\\') != std::string::npos || name.find("..") != std::string::npos) {
        lua_pushnil(L); return 1;
    }
    std::string up = name, low = name;
    for (auto& c : up) c = (char)std::toupper((unsigned char)c);
    for (auto& c : low) c = (char)std::tolower((unsigned char)c);
    std::string dir = E(L)->data_dir;
    if (!dir.empty() && dir.back() != '/' && dir.back() != '\\') dir += '/';
    for (const std::string& n : {name, up, low}) {
        FILE* f = std::fopen((dir + n).c_str(), "rb");
        if (!f) continue;
        std::string s;
        char buf[4096];
        size_t r;
        while ((r = std::fread(buf, 1, sizeof buf, f)) > 0) s.append(buf, r);
        std::fclose(f);
        lua_pushlstring(L, s.data(), s.size());
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

int l_find(lua_State* L) {
    auto h = E(L)->glb.find(luaL_checkstring(L, 1));
    if (h) lua_pushinteger(L, *h); else lua_pushnil(L);
    return 1;
}

int l_item(lua_State* L) {   // handle -> {name, length, flags} | nil
    auto e = E(L)->glb.entry(uint32_t(luaL_checkinteger(L, 1)));
    if (!e) { lua_pushnil(L); return 1; }
    lua_createtable(L, 0, 3);
    lua_pushstring(L, e->name.c_str()); lua_setfield(L, -2, "name");
    set_int(L, "length", e->length);
    set_int(L, "flags", e->flags);
    return 1;
}

int l_item_count(lua_State* L) {
    auto* e = E(L);
    size_t f = size_t(luaL_checkinteger(L, 1));
    lua_pushinteger(L, f < e->glb.file_count() ? lua_Integer(e->glb.file(f).entries().size()) : 0);
    return 1;
}

int l_file_count(lua_State* L) { lua_pushinteger(L, lua_Integer(E(L)->glb.file_count())); return 1; }

int l_read(lua_State* L) {   // raw bytes as a Lua string
    auto* e = E(L);
    auto h = handle_arg(L, e, 1);
    if (!h) { lua_pushnil(L); return 1; }
    Bytes b = e->glb.read(*h);
    lua_pushlstring(L, reinterpret_cast<const char*>(b.data()), b.size());
    return 1;
}

// ---- graphics --------------------------------------------------------------------

int l_palette(lua_State* L) {   // palette(name|handle) -> bool
    auto* e = E(L);
    auto h = handle_arg(L, e, 1);
    bool ok = h && decode_palette(e->glb.read(*h), e->screen.pal);
    e->screen.palette_changed();
    lua_pushboolean(L, ok);
    return 1;
}

int l_palette_rgb(lua_State* L) {   // index -> r, g, b  (or set with r, g, b)
    auto& p = E(L)->screen.pal;
    int i = int(luaL_checkinteger(L, 1)) & 255;
    if (lua_gettop(L) >= 4) {
        for (int c = 0; c < 3; ++c) p[size_t(i * 3 + c)] = uint8_t(luaL_checkinteger(L, 2 + c));
        E(L)->screen.palette_changed();
        return 0;
    }
    for (int c = 0; c < 3; ++c) lua_pushinteger(L, p[size_t(i * 3 + c)]);
    return 3;
}

int l_fade(lua_State* L) {
    auto* e = E(L);
    if (lua_gettop(L) >= 1) e->screen.fade = float(luaL_checknumber(L, 1));
    lua_pushnumber(L, e->screen.fade);
    return 1;
}

int l_clear(lua_State* L) { E(L)->screen.clear(uint8_t(luaL_optinteger(L, 1, 0))); return 0; }

int l_rect(lua_State* L) {
    E(L)->screen.rect(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)),
                      int(luaL_checkinteger(L, 3)), int(luaL_checkinteger(L, 4)),
                      uint8_t(luaL_checkinteger(L, 5)));
    return 0;
}

int l_pixel(lua_State* L) {
    E(L)->screen.pixel(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)), uint8_t(luaL_checkinteger(L, 3)));
    return 0;
}

// agx(item [, first]) -> drawn?  Paints a movie frame over what's on
// screen (frames after the first only hold what changed). `first`: the
// movie's first frame, which clears the screen to its fill colour.
int l_agx(lua_State* L) {
    auto* e = E(L);
    auto h = handle_arg(L, e, 1);
    AgxFrame f;
    bool ok = h && decode_agx(e->glb.read(*h), f, lua_toboolean(L, 2));
    if (ok) apply_agx(f, e->screen.px.data());
    lua_pushboolean(L, ok);
    return 1;
}

int l_shade(lua_State* L) {   // shade(x, y, w, h, level): -2..2, darker..lighter
    E(L)->screen.shade(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)), int(luaL_checkinteger(L, 3)),
                       int(luaL_checkinteger(L, 4)), int(luaL_checkinteger(L, 5)));
    return 0;
}

int l_clip(lua_State* L) {   // clip() resets; clip(x, y, w, h)
    auto& c = E(L)->screen.clip;
    if (lua_gettop(L) == 0) { c = Clip{}; return 0; }
    int x = int(luaL_checkinteger(L, 1)), y = int(luaL_checkinteger(L, 2));
    c.x0 = std::max(0, x); c.y0 = std::max(0, y);
    c.x1 = std::min(kScreenW, x + int(luaL_checkinteger(L, 3)));
    c.y1 = std::min(kScreenH, y + int(luaL_checkinteger(L, 4)));
    return 0;
}

// pic(item, x, y [, flip [, remap [, lut]]]) -> drawn?
// lut: a 256-byte string, each colour's replacement (co-op ship colours).
int l_pic(lua_State* L) {
    auto* e = E(L);
    const Pic* p = get_pic(L, e, 1);
    size_t n = 0;
    const char* lut = lua_type(L, 6) == LUA_TSTRING ? lua_tolstring(L, 6, &n) : nullptr;
    if (p) e->screen.pic(*p, int(luaL_checknumber(L, 2)), int(luaL_checknumber(L, 3)),
                         int(luaL_optinteger(L, 4, 0)), int(luaL_optinteger(L, 5, -1)),
                         n == 256 ? reinterpret_cast<const uint8_t*>(lut) : nullptr);
    lua_pushboolean(L, p != nullptr);
    return 1;
}

int l_pic_info(lua_State* L) {   // -> w, h, is_sprite | nil
    const Pic* p = get_pic(L, E(L), 1);
    if (!p) { lua_pushnil(L); return 1; }
    lua_pushinteger(L, p->width);
    lua_pushinteger(L, p->height);
    lua_pushboolean(L, p->sprite);
    return 3;
}

// Pixel-exact mask test used for collisions: is (x, y) opaque in the pic?
int l_pic_hit(lua_State* L) {
    const Pic* p = get_pic(L, E(L), 1);
    int x = int(luaL_checknumber(L, 2)), y = int(luaL_checknumber(L, 3));
    bool hit = false;
    if (p && x >= 0 && y >= 0 && x < p->width && y < p->height) {
        if (!p->sprite) hit = true;
        else for (const Span& s : p->spans) if (s.y == y && x >= s.x && x < s.x + s.count) { hit = true; break; }
    }
    lua_pushboolean(L, hit);
    return 1;
}

int l_text(lua_State* L) {   // text(font, str, x, y [, color [, base_mode]]) -> width
    auto* e = E(L);
    const Font* f = get_font(L, e, 1);
    if (!f) { lua_pushinteger(L, 0); return 1; }
    int w = e->screen.text(*f, luaL_checkstring(L, 2), int(luaL_checknumber(L, 3)),
                           int(luaL_checknumber(L, 4)), int(luaL_optinteger(L, 5, -1)), lua_toboolean(L, 6));
    lua_pushinteger(L, w);
    return 1;
}

int l_text_size(lua_State* L) {   // -> width, height
    const Font* f = get_font(L, E(L), 1);
    if (!f) { lua_pushinteger(L, 0); lua_pushinteger(L, 0); return 2; }
    lua_pushinteger(L, Screen::text_width(*f, luaL_checkstring(L, 2)));
    lua_pushinteger(L, f->height);
    return 2;
}

// ---- game data ---------------------------------------------------------------------

int l_level(lua_State* L) {   // level(name) -> {cells = {{tile, set}...}, actors = {...}}
    auto* e = E(L);
    auto h = handle_arg(L, e, 1);
    Level lv;
    if (!h || !decode_level(e->glb.read(*h), lv)) { lua_pushnil(L); return 1; }
    lua_createtable(L, 0, 2);
    lua_createtable(L, int(lv.cells.size()), 0);
    for (size_t i = 0; i < lv.cells.size(); ++i) {
        lua_createtable(L, 2, 0);
        lua_pushinteger(L, lv.cells[i].tile); lua_rawseti(L, -2, 1);
        lua_pushinteger(L, lv.cells[i].tileset); lua_rawseti(L, -2, 2);
        lua_rawseti(L, -2, lua_Integer(i + 1));
    }
    lua_setfield(L, -2, "cells");
    lua_createtable(L, int(lv.actors.size()), 0);
    for (size_t i = 0; i < lv.actors.size(); ++i) {
        const auto& a = lv.actors[i];
        lua_createtable(L, 0, 6);
        set_int(L, "link", a.link); set_int(L, "slib", a.slib);
        set_int(L, "x", a.x); set_int(L, "y", a.y);
        set_int(L, "game", a.game); set_int(L, "level", a.level);
        lua_rawseti(L, -2, lua_Integer(i + 1));
    }
    lua_setfield(L, -2, "actors");
    return 1;
}

void push_shorts(lua_State* L, const int16_t* v, size_t n) {
    lua_createtable(L, int(n), 0);
    for (size_t i = 0; i < n; ++i) { lua_pushinteger(L, v[i]); lua_rawseti(L, -2, lua_Integer(i + 1)); }
}

int l_sprite_lib(lua_State* L) {   // -> array of {name, f = {26 ints}, table = {6 x 24}, path_x, path_y}
    auto* e = E(L);
    auto h = handle_arg(L, e, 1);
    std::vector<SpriteDef> defs;
    if (!h || !decode_sprite_lib(e->glb.read(*h), defs)) { lua_pushnil(L); return 1; }
    lua_createtable(L, int(defs.size()), 0);
    for (size_t i = 0; i < defs.size(); ++i) {
        const auto& d = defs[i];
        lua_createtable(L, 0, 6);
        lua_pushstring(L, d.name.c_str()); lua_setfield(L, -2, "name");
        lua_createtable(L, 26, 0);
        for (size_t k = 0; k < d.f.size(); ++k) { lua_pushinteger(L, d.f[k]); lua_rawseti(L, -2, lua_Integer(k + 1)); }
        lua_setfield(L, -2, "f");
        lua_createtable(L, 6, 0);
        for (size_t t = 0; t < 6; ++t) { push_shorts(L, d.table[t].data(), 24); lua_rawseti(L, -2, lua_Integer(t + 1)); }
        lua_setfield(L, -2, "table");
        push_shorts(L, d.path_x.data(), d.path_x.size()); lua_setfield(L, -2, "path_x");
        push_shorts(L, d.path_y.data(), d.path_y.size()); lua_setfield(L, -2, "path_y");
        lua_rawseti(L, -2, lua_Integer(i + 1));
    }
    return 1;
}

// swd(name) -> window table with its fields (formats/swd.h), or nil.
int l_swd(lua_State* L) {
    auto* e = E(L);
    auto h = handle_arg(L, e, 1);
    SwdWindow w;
    if (!h || !decode_swd(e->glb.read(*h), w)) { lua_pushnil(L); return 1; }
    auto str = [&](const char* k, const std::string& v) { lua_pushstring(L, v.c_str()); lua_setfield(L, -2, k); };
    lua_createtable(L, 0, 12);
    str("name", w.name); str("item", w.item_name);
    set_int(L, "fill", w.fill); set_int(L, "color", w.color); set_int(L, "first", w.first_field);
    set_int(L, "x", w.x); set_int(L, "y", w.y); set_int(L, "w", w.w); set_int(L, "h", w.h);
    set_int(L, "shadow", w.shadow);
    lua_createtable(L, int(w.fields.size()), 0);
    for (size_t i = 0; i < w.fields.size(); ++i) {
        const auto& f = w.fields[i];
        lua_createtable(L, 0, 18);
        set_int(L, "type", f.type); set_int(L, "id", f.id); set_int(L, "hotkey", f.hotkey);
        str("name", f.name); str("item", f.item_name); str("font", f.font_name); str("text", f.text);
        set_int(L, "base", f.font_base); set_int(L, "max", f.max_chars); set_int(L, "fill", f.fill);
        set_int(L, "color", f.color); set_int(L, "lite", f.lite); set_int(L, "shadow", f.shadow);
        set_int(L, "selectable", f.selectable);
        set_int(L, "x", f.x); set_int(L, "y", f.y); set_int(L, "w", f.w); set_int(L, "h", f.h);
        lua_rawseti(L, -2, lua_Integer(i + 1));
    }
    lua_setfield(L, -2, "fields");
    return 1;
}

int l_flats(lua_State* L) {
    auto* e = E(L);
    auto h = handle_arg(L, e, 1);
    std::vector<FlatDef> fl;
    if (!h || !decode_flats(e->glb.read(*h), fl)) { lua_pushnil(L); return 1; }
    lua_createtable(L, int(fl.size()), 0);
    for (size_t i = 0; i < fl.size(); ++i) {
        lua_createtable(L, 0, 3);
        set_int(L, "linkflat", fl[i].linkflat); set_int(L, "hits", fl[i].hits); set_int(L, "bounty", fl[i].bounty);
        lua_rawseti(L, -2, lua_Integer(i + 1));
    }
    return 1;
}

// ---- sound ------------------------------------------------------------------------

int l_sound(lua_State* L) {   // sound(name) -> id | nil (digitized variant)
    auto* e = E(L);
    const char* name = luaL_checkstring(L, 1);
    auto h = e->glb.find(name);
    if (!h) { lua_pushnil(L); return 1; }
    auto it = g_cache.sounds.find(*h);
    if (it == g_cache.sounds.end()) {
        Sound s;
        int id = find_digital_sound(e->glb, name, s) ? e->audio.add(std::move(s)) : -1;
        it = g_cache.sounds.emplace(*h, id).first;
    }
    if (it->second < 0) lua_pushnil(L); else lua_pushinteger(L, it->second);
    return 1;
}

int l_play(lua_State* L) {
    auto* e = E(L);
    if (e->audio_ok && !lua_isnoneornil(L, 1))
        e->audio.play(int(luaL_checkinteger(L, 1)), float(luaL_optnumber(L, 2, 1.0)), float(luaL_optnumber(L, 3, 0.0)));
    return 0;
}

int l_sound_playing(lua_State* L) {
    auto* e = E(L);
    lua_pushboolean(L, e->audio_ok && !lua_isnoneornil(L, 1) && e->audio.playing(int(luaL_checkinteger(L, 1))));
    return 1;
}

int l_volume(lua_State* L) {
    auto* e = E(L);
    if (lua_gettop(L) >= 1) e->audio.master = float(luaL_checknumber(L, 1));
    lua_pushnumber(L, e->audio.master);
    return 1;
}

int l_stop_sounds(lua_State* L) { E(L)->audio.stop_all(); return 0; }

// music(name [, loop = true]) -> ok. Plays a MUS song through the OPL3 with
// the GENMIDI_OP2 bank (loaded on first use). Re-requesting the song that's
// already playing leaves it running.
std::string g_music_name;
bool g_bank_loaded = false;
int l_music(lua_State* L) {
    auto* e = E(L);
    const char* name = luaL_checkstring(L, 1);
    bool loop = lua_isnoneornil(L, 2) ? true : lua_toboolean(L, 2);
    if (!e->audio_ok) { lua_pushboolean(L, false); return 1; }
    if (g_music_name == name && e->audio.music_playing()) { lua_pushboolean(L, true); return 1; }
    if (!g_bank_loaded) {
        GenMidi bank;
        if (!decode_genmidi(e->glb.read("GENMIDI_OP2"), bank)) { lua_pushboolean(L, false); return 1; }
        e->audio.set_music_bank(bank);
        g_bank_loaded = true;
    }
    MusScore score;
    bool ok = decode_mus(e->glb.read(name), score) && e->audio.play_music(std::move(score), loop);
    g_music_name = ok ? name : "";
    lua_pushboolean(L, ok);
    return 1;
}

int l_music_stop(lua_State* L) {
    auto* e = E(L);
    if (e->audio_ok) e->audio.stop_music();
    g_music_name.clear();
    return 0;
}

int l_music_volume(lua_State* L) {
    auto* e = E(L);
    if (lua_gettop(L) >= 1) e->audio.music_volume = float(luaL_checknumber(L, 1));
    lua_pushnumber(L, e->audio.music_volume);
    return 1;
}

int l_music_playing(lua_State* L) {
    auto* e = E(L);
    lua_pushstring(L, e->audio_ok && e->audio.music_playing() ? g_music_name.c_str() : "");
    return 1;
}

// ---- input / system -----------------------------------------------------------------

int l_held(lua_State* L) { lua_pushboolean(L, E(L)->input.held(luaL_checkstring(L, 1))); return 1; }
int l_pressed(lua_State* L) { lua_pushboolean(L, E(L)->input.pressed(luaL_checkstring(L, 1))); return 1; }
// music_tempo(t): the music's tempo as a multiple of the original's (1.0).
int l_music_tempo(lua_State* L) {
    double t = luaL_checknumber(L, 1);
    E(L)->audio.set_music_tempo(float(t < 0.5 ? 0.5 : t > 2.0 ? 2.0 : t));
    return 0;
}

// smooth(on): draw every displayed frame (smooth motion); alpha() -> 0..1,
// how far the clock is past the last tick, for placing things between ticks.
int l_smooth(lua_State* L) { E(L)->smooth = lua_toboolean(L, 1) != 0; return 0; }
int l_alpha(lua_State* L) { lua_pushnumber(L, E(L)->alpha); return 1; }

int l_typed(lua_State* L) { lua_pushstring(L, E(L)->input.text.c_str()); return 1; }

// key_down() -> name | nil: the first key pressed this tick (key setup).
int l_key_down(lua_State* L) {
    const auto& k = E(L)->input.key_down;
    if (k.empty()) lua_pushnil(L); else lua_pushstring(L, k.c_str());
    return 1;
}

// The Xbox 360 controller's own buttons (Input::pad_*): pad_held(b),
// pad_pressed(b), pad_button() -> the first pressed this tick or nil,
// pad_take({b, ...}) (those buttons stop also being keys).
int l_pad_held(lua_State* L) {
    lua_pushboolean(L, E(L)->input.pad_held(luaL_checkstring(L, 1), int(luaL_optinteger(L, 2, 0))));
    return 1;
}
int l_pad_pressed(lua_State* L) {
    lua_pushboolean(L, E(L)->input.pad_pressed(luaL_checkstring(L, 1), int(luaL_optinteger(L, 2, 0))));
    return 1;
}
// pad_keys_first_only(on): co-op, only the first pad also makes keys.
int l_pad_keys_first_only(lua_State* L) { E(L)->input.pad_keys_first_only(lua_toboolean(L, 1) != 0); return 0; }
int l_pad_button(lua_State* L) {
    std::string b = E(L)->input.pad_first();
    if (b.empty()) lua_pushnil(L); else lua_pushstring(L, b.c_str());
    return 1;
}
int l_pad_take(lua_State* L) {
    std::vector<std::string> list;
    if (lua_istable(L, 1)) {
        lua_Integer n = luaL_len(L, 1);
        for (lua_Integer i = 1; i <= n; ++i) {
            lua_geti(L, 1, i);
            if (lua_isstring(L, -1)) list.emplace_back(lua_tostring(L, -1));
            lua_pop(L, 1);
        }
    }
    E(L)->input.pad_take(list);
    return 0;
}

int l_mouse(lua_State* L) {   // -> x, y, dx, dy, moved
    auto& in = E(L)->input;
    lua_pushinteger(L, in.mouse_x); lua_pushinteger(L, in.mouse_y);
    lua_pushinteger(L, in.mouse_dx); lua_pushinteger(L, in.mouse_dy);
    lua_pushboolean(L, in.mouse_moved);
    return 5;
}

int l_grab_mouse(lua_State* L) {
    SDL_SetRelativeMouseMode(lua_toboolean(L, 1) ? SDL_TRUE : SDL_FALSE);
    return 0;
}

int l_tick_rate(lua_State* L) {
    auto* e = E(L);
    if (lua_gettop(L) >= 1) e->tick_rate = std::max(1, int(luaL_checkinteger(L, 1)));
    lua_pushinteger(L, e->tick_rate);
    return 1;
}

int l_quit(lua_State* L) { E(L)->quit = true; return 0; }
int l_fullscreen(lua_State* L) { E(L)->window.toggle_fullscreen(); return 0; }
int l_headless(lua_State* L) { lua_pushboolean(L, E(L)->window.headless()); return 1; }
int l_message(lua_State* L) {   // message(title, text): native dialog (works without game data)
    if (!E(L)->window.headless())
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_INFORMATION, luaL_checkstring(L, 1), luaL_checkstring(L, 2), nullptr);
    return 0;
}
int l_screenshot(lua_State* L) {   // screenshot(path) -> ok  (BMP of the 320x200 screen)
    auto* e = E(L);
    SDL_Surface* s = SDL_CreateRGBSurfaceWithFormat(0, kScreenW, kScreenH, 8, SDL_PIXELFORMAT_INDEX8);
    if (!s) { lua_pushboolean(L, false); return 1; }
    SDL_Color c[256];
    for (int i = 0; i < 256; ++i) c[i] = {e->screen.pal[size_t(i * 3)], e->screen.pal[size_t(i * 3 + 1)], e->screen.pal[size_t(i * 3 + 2)], 255};
    SDL_SetPaletteColors(s->format->palette, c, 0, 256);
    for (int y = 0; y < kScreenH; ++y)
        std::memcpy(static_cast<uint8_t*>(s->pixels) + y * s->pitch, e->screen.px.data() + y * kScreenW, kScreenW);
    bool ok = SDL_SaveBMP(s, luaL_checkstring(L, 1)) == 0;
    SDL_FreeSurface(s);
    lua_pushboolean(L, ok);
    return 1;
}
int l_millis(lua_State* L) { lua_pushinteger(L, lua_Integer(SDL_GetTicks64())); return 1; }

int l_save_file(lua_State* L) {   // save_file(name, string) -> ok  (in the user pref dir)
    size_t n;
    const char* name = luaL_checkstring(L, 1);
    const char* data = luaL_checklstring(L, 2, &n);
    char* dir = SDL_GetPrefPath("Raptua", "Raptua");
    bool ok = false;
    if (dir) {
        std::string p = std::string(dir) + name;
        SDL_free(dir);
        if (FILE* f = std::fopen(p.c_str(), "wb")) { ok = std::fwrite(data, 1, n, f) == n; std::fclose(f); }
    }
    lua_pushboolean(L, ok);
    return 1;
}

int l_load_file(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    char* dir = SDL_GetPrefPath("Raptua", "Raptua");
    if (!dir) { lua_pushnil(L); return 1; }
    std::string p = std::string(dir) + name;
    SDL_free(dir);
    FILE* f = std::fopen(p.c_str(), "rb");
    if (!f) { lua_pushnil(L); return 1; }
    std::string s;
    char buf[4096];
    size_t r;
    while ((r = std::fread(buf, 1, sizeof buf, f)) > 0) s.append(buf, r);
    std::fclose(f);
    lua_pushlstring(L, s.data(), s.size());
    return 1;
}

} // namespace

void register_lua_api(lua_State* L, Engine* e) {
    static const luaL_Reg fns[] = {
        {"have_data", l_have_data}, {"data_error", l_data_error}, {"data_dir", l_data_dir}, {"data_file", l_data_file},
        {"find", l_find}, {"item", l_item}, {"item_count", l_item_count}, {"file_count", l_file_count},
        {"read", l_read},
        {"palette", l_palette}, {"palette_rgb", l_palette_rgb}, {"fade", l_fade},
        {"clear", l_clear}, {"rect", l_rect}, {"shade", l_shade}, {"agx", l_agx}, {"pixel", l_pixel}, {"clip", l_clip},
        {"pic", l_pic}, {"pic_info", l_pic_info}, {"pic_hit", l_pic_hit},
        {"text", l_text}, {"sys_text", l_sys_text}, {"text_size", l_text_size},
        {"level", l_level}, {"sprite_lib", l_sprite_lib}, {"flats", l_flats}, {"swd", l_swd},
        {"sound", l_sound}, {"play", l_play}, {"sound_playing", l_sound_playing}, {"volume", l_volume}, {"stop_sounds", l_stop_sounds},
        {"music", l_music}, {"music_stop", l_music_stop}, {"music_volume", l_music_volume},
        {"music_playing", l_music_playing},
        {"held", l_held}, {"pressed", l_pressed}, {"typed", l_typed}, {"smooth", l_smooth}, {"music_tempo", l_music_tempo}, {"alpha", l_alpha}, {"key_down", l_key_down},
        {"pad_held", l_pad_held}, {"pad_pressed", l_pad_pressed}, {"pad_button", l_pad_button}, {"pad_take", l_pad_take}, {"pad_keys_first_only", l_pad_keys_first_only},
        {"mouse", l_mouse}, {"grab_mouse", l_grab_mouse},
        {"tick_rate", l_tick_rate}, {"quit", l_quit}, {"can_exit", l_can_exit}, {"fullscreen", l_fullscreen},
        {"headless", l_headless}, {"millis", l_millis}, {"message", l_message}, {"screenshot", l_screenshot},
        {"save_file", l_save_file}, {"load_file", l_load_file},
        {nullptr, nullptr}};
    lua_newtable(L);
    lua_pushlightuserdata(L, e);
    luaL_setfuncs(L, fns, 1);
    lua_pushstring(L, RAPTUA_VERSION); lua_setfield(L, -2, "version");
    // "xenon" on the Xbox 360 (a controller, no keyboard or mouse), else "pc".
#ifdef RAPTUA_XENON_LAYOUT
    lua_pushstring(L, "xenon");
#else
    lua_pushstring(L, "pc");
#endif
    lua_setfield(L, -2, "platform");
    lua_pushinteger(L, kScreenW); lua_setfield(L, -2, "W");
    lua_pushinteger(L, kScreenH); lua_setfield(L, -2, "H");
    lua_setglobal(L, "rap");
}

} // namespace raptua
