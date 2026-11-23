/*
 * Raptua for the Super Nintendo: sector 1, wave 1 (PVSnesLib, mode 1).
 *
 * The art and the wave come from tools/snes_art.py (art.h, art.inc): by
 * default Raptua's own, or with snes/build.sh --data, converted from the
 * player's own Raptor files.
 *
 * Screen: BG1 is the map, 288 pixels wide (9 tiles of 32), shown 256 wide
 * and panned with the ship; 4bpp characters stream into a 1024-character
 * VRAM cache as rows of the map come into view. Sprites are the ship, the
 * enemies, shots and explosions.
 *
 * Timing: as in the original, the game runs in game frames of about 23.3 Hz
 * (every third vertical blank of its 70 Hz screen): here 7 of every 18 SNES
 * frames. The map scrolls one pixel per game frame; enemies fly and fire per
 * game frame by their sprite-library records. The ship moves every frame.
 *
 * Pad: D-pad flies, B or Y fires, Start pauses. Leave the pad alone and the
 * ship flies itself (the demo the smoke test watches).
 */
#include <snes.h>

#include "art.h"

#define VRAM_BG_CHARS 0x0000   /* 1024 characters, 16 words each */
#define VRAM_BG_MAP   0x4000   /* 64 x 64: 16 map rows of 32 pixels, so the row
                                  coming in never shares tilemap rows with one on screen */
#define VRAM_OBJ      0x6000   /* 512 characters */

#define MAP_W 9
#define MAP_H 150
#define TILE 32
#define SCREEN_H 224
#define PLAY_W 288
#define FP 4                   /* positions in 1/16 pixel */

/* ---- ROM tables ------------------------------------------------------------ */

#define TYPE_WORDS 92          /* 32 header words, 30 (x, y) path points */
enum { T_PIC, T_HP, T_BOUNTY, T_FLIGHT, T_SPEED, T_NPATH, T_REPOS, T_BOSS, T_COUNTDOWN, T_SHOOTSTART,
       T_SHOOTCNT, T_SHOOTFRAME, T_SHOOTSPACE, T_NGUNS, T_GUNS };
enum { F_REPEAT, F_LINEAR, F_KAMI, F_GROUND, F_GROUNDLEFT, F_GROUNDRIGHT };

static s16 *type_rec(u8 t) { return ((s16 *)&art_types) + t * TYPE_WORDS; }
#define TW(e, i) ((e)->tp[i])

typedef struct { u8 ux, uy, pal, pad; u16 unit[16]; } Pic;
static Pic *pic(u8 n) { return ((Pic *)&art_pics) + n; }

typedef struct { s16 row; u8 col, type, level, pad; } Actor;

/* The BG characters, a 32 KB bank (1024 characters) at a time. */
static u8 *bg_char(u16 rom) {
    u16 off = (rom & 1023) << 5;
#if ART_BG_PARTS > 2
    if (rom >= 2048) return &art_bgchars2 + off;
#endif
#if ART_BG_PARTS > 1
    if (rom >= 1024) return &art_bgchars1 + off;
#endif
    return &art_bgchars0 + off;
}

/* ---- state (the smoke test reads `game` from work RAM) ------------------------ */

typedef struct {
    u16 frames;        /* 0  SNES frames run */
    s16 cam;           /* 2  top of the screen in map pixels (scrolls to 0) */
    u16 kills;         /* 4 */
    u16 score;         /* 6  bounty / 10 */
    s16 shield;        /* 8 */
    u16 deaths;        /* 10 */
    u16 waves;         /* 12 waves won */
    u16 spawned;       /* 14 */
    u16 free_min;      /* 16 fewest free VRAM character slots seen */
    u16 q_max;         /* 18 longest upload queue seen */
} Game;
Game game;

#define MAX_ENEMIES 20
typedef struct {
    u8 on, type, ground, flight, leg, dir, flash, shoot_on, volleys, dove;
    s16 x, y;          /* top-left, 1/16 px, screen space (x: the 288-wide playfield) */
    s16 sx, sy;        /* path origin */
    s16 dx, dy;        /* dive step */
    s16 hp, countdown, wait, resting;
    s16 speed;         /* 1/16 px per game frame */
    s16 stx, sty, left;  /* this leg: step per game frame, distance to go */
    u8 leg_ready;
    u8 w, h, pic;
    s16 *tp;           /* its sprite-library record (ROM) */
} Enemy;
Enemy enemies[MAX_ENEMIES];

#define MAX_SHOTS 24
typedef struct { u8 on, enemy; s16 x, y, dx, dy; } Shot;
Shot shots[MAX_SHOTS];

#define MAX_BOOMS 10
typedef struct { u8 on, t; s16 x, y; } Boom;
Boom booms[MAX_BOOMS];

s16 px, py;            /* the ship's top-left, whole pixels (x in the playfield) */
s8 bank;               /* -1 left, 0 level, 1 right */
u8 fire_wait, dead_t, end_t, paused, demo;
u16 idle;
u8 tick_acc;
s8 demo_dir;
u16 next_actor;
u16 pad, pad_prev;

/* ---- the BG character cache ---------------------------------------------------- */

#define SLOTS 1024
#define NO_SLOT 0xFFFF
u16 slot_of[ART_BG_CHARS];
u16 rom_of[SLOTS];
u16 refs[SLOTS];   /* one character can be on every cell of a screenful (open sea): past 255 */
u16 free_slots[SLOTS];
u16 free_top;
#define QUEUE 512
u16 queue_slot[QUEUE], queue_rom[QUEUE];
u16 q_head, q_tail;
u16 tmap[4][32 * 32];        /* the four 32 x 32 screens of the 64 x 64 map */
u8 dirty[64];
u8 dirty_list[64], ndirty;   /* the changed tilemap rows, for plan_vram() */
s16 loaded_lo, loaded_hi;   /* map rows held in VRAM: lo..hi (lo <= hi), or lo > hi none */

static u16 acquire(u16 rom) {
    u16 s = slot_of[rom];
    if (s != NO_SLOT) { refs[s]++; return s; }
    if (free_top == 0) return 0;             /* full: show slot 0 rather than crash */
    s = free_slots[--free_top];
    if (free_top < game.free_min) game.free_min = free_top;
    slot_of[rom] = s; rom_of[s] = rom; refs[s] = 1;
    queue_slot[q_tail] = s; queue_rom[q_tail] = rom;
    q_tail = (q_tail + 1) & (QUEUE - 1);
    if (((q_tail - q_head) & (QUEUE - 1)) > game.q_max) game.q_max = (q_tail - q_head) & (QUEUE - 1);
    return s;
}

static void release(u16 rom) {
    u16 s = slot_of[rom];
    if (s == NO_SLOT || refs[s] == 0) return;
    if (--refs[s] == 0) { slot_of[rom] = NO_SLOT; free_slots[free_top++] = s; }
}

static u8 *tile_entries(u8 tile) { return ((u8 *)&art_tiles) + (u16)tile * 64; }
static u8 map_tile(s16 row, u8 col) { return ((u8 *)&art_map)[row * MAP_W + col]; }

static void load_row(s16 row) {
    u8 col, c;
    u16 tr;
    for (col = 0; col < MAP_W; col++) {
        u8 *e = tile_entries(map_tile(row, col));
        for (c = 0; c < 16; c++) {
            u16 rom = e[c * 4] | (e[c * 4 + 1] << 8);
            u16 s = acquire(rom);
            u16 mx = col * 4 + (c & 3);
            tr = (u16)((row * 4 + (c >> 2)) & 63);
            tmap[((tr >> 5) << 1) | (mx >> 5)][(tr & 31) * 32 + (mx & 31)] = s | ((u16)e[c * 4 + 2] << 10);
            if (!dirty[tr]) { dirty[tr] = 1; dirty_list[ndirty++] = (u8)tr; }
        }
    }
}

static void unload_row(s16 row) {
    u8 col, c;
    for (col = 0; col < MAP_W; col++) {
        u8 *e = tile_entries(map_tile(row, col));
        for (c = 0; c < 16; c++) release(e[c * 4] | (e[c * 4 + 1] << 8));
    }
}

/* Rows from two above the screen to its bottom stay loaded (the uploads
 * trickle in over many frames: what fits in a vertical blank). One new row
 * per call at most, so its characters (up to 144) fit the upload queue;
 * returns 1 if more rows are still to come. */
static u8 update_rows(void) {
    s16 lo = (game.cam >> 5) - 2, hi = (game.cam + SCREEN_H - 1) >> 5;
    if (lo < 0) lo = 0;
    if (hi > MAP_H - 1) hi = MAP_H - 1;
    while (loaded_hi > hi && loaded_hi >= loaded_lo) unload_row(loaded_hi--);
    if (loaded_lo > lo) { load_row(--loaded_lo); return loaded_lo > lo; }
    return 0;
}

/* VRAM writes only work in vertical blank, and 816-tcc's code is slow, so
 * the work is split: plan_vram() (any time) picks what to send, as a short
 * list of DMAs: up to `maxrows` changed tilemap rows, then up to `n` queued
 * characters in at most `calls` DMAs, as runs where consecutive slots hold
 * consecutive characters. send_vram() (in vertical blank) only runs them. */
#define JOBS 16
u8 *job_src[JOBS];
u16 job_dst[JOBS], job_len[JOBS];
u8 njobs;
static void plan_vram(u16 n, u8 maxrows, u8 calls) {
    njobs = 0;
    while (ndirty && maxrows && njobs + 2 <= JOBS) {
        u8 r = dirty_list[--ndirty], sc = (r >> 5) << 1;
        dirty[r] = 0;
        job_src[njobs] = (u8 *)&tmap[sc][(r & 31) * 32];
        job_dst[njobs] = VRAM_BG_MAP + sc * 0x400 + (r & 31) * 32; job_len[njobs++] = 64;
        job_src[njobs] = (u8 *)&tmap[sc + 1][(r & 31) * 32];
        job_dst[njobs] = VRAM_BG_MAP + (sc + 1) * 0x400 + (r & 31) * 32; job_len[njobs++] = 64;
        maxrows--;
    }
    while (q_head != q_tail && n && calls && njobs < JOBS) {
        u16 slot = queue_slot[q_head], rom = queue_rom[q_head], len = 1;
        u16 next = (q_head + 1) & (QUEUE - 1);
        while (next != q_tail && len < n && queue_slot[next] == slot + len && queue_rom[next] == rom + len
               && ((rom + len) & 1023) != 0) {
            len++;
            next = (next + 1) & (QUEUE - 1);
        }
        job_src[njobs] = bg_char(rom); job_dst[njobs] = VRAM_BG_CHARS + (slot << 4); job_len[njobs++] = len << 5;
        q_head = next;
        n -= len;
        calls--;
    }
}

static void send_vram(void) {
    u8 i;
    for (i = 0; i < njobs; i++) dmaCopyVram(job_src[i], job_dst[i], job_len[i]);
    njobs = 0;
}

/* ---- sprites ------------------------------------------------------------------- */

u16 oam_n, oam_prev;
u16 shot_chr, eshot_chr;
u8 shot_attr, eshot_attr;

u8 oam_hi[32];

/* Straight into PVSnesLib's OAM copy (the NMI sends it): faster than oamSet. */
static void put(s16 x, s16 y, u16 chr, u8 pal, u8 large) {
    u8 *o;
    u8 bits;
    if (oam_n >= 128) return;
    if (x <= -32 || x >= 256 || y <= -32 || y >= SCREEN_H) return;
    o = oamMemory + (oam_n << 2);
    o[0] = (u8)x;
    o[1] = (u8)y;
    o[2] = (u8)chr;
    o[3] = (u8)(0x30 | (pal << 1) | ((chr >> 8) & 1));   /* priority 3 */
    bits = (u8)(((x >> 8) & 1) | (large ? 2 : 0));
    oam_hi[oam_n >> 2] |= bits << ((oam_n & 3) << 1);
    oam_n++;
}

/* A converted picture with its top-left at screen (x, y). */
static void draw_pic(u8 n, s16 x, s16 y) {
    Pic *p = pic(n);
    u8 vx, vy, k = 0;
    for (vy = 0; vy < p->uy; vy++)
        for (vx = 0; vx < p->ux; vx++, k++)
            if (p->unit[k] != 0xFFFF) put(x + vx * 16, y + vy * 16, p->unit[k], p->pal, 0);
}

/* ---- the game ----------------------------------------------------------------- */

static s16 scroll_x(void) {
    s16 s = px + 16 - 128;
    if (s < 0) s = 0;
    if (s > PLAY_W - 256) s = PLAY_W - 256;
    return s;
}

static void boom(s16 x, s16 y) {
    u8 i;
    for (i = 0; i < MAX_BOOMS; i++)
        if (!booms[i].on) { booms[i].on = 1; booms[i].t = 0; booms[i].x = x - 8; booms[i].y = y - 8; return; }
}

static void shoot(u8 enemy, s16 x, s16 y, s16 dx, s16 dy) {
    u8 i;
    for (i = 0; i < MAX_SHOTS; i++)
        if (!shots[i].on) {
            shots[i].on = 1; shots[i].enemy = enemy;
            shots[i].x = x << FP; shots[i].y = y << FP; shots[i].dx = dx; shots[i].dy = dy;
            return;
        }
}

/* Roughly |(dx, dy)|: max + min / 2 (no square roots on the 65816). */
static s16 approx_len(s16 dx, s16 dy) {
    if (dx < 0) dx = -dx;
    if (dy < 0) dy = -dy;
    return dx > dy ? dx + (dy >> 1) : dy + (dx >> 1);
}

static void spawn(Actor *a, s16 sy) {
    u8 i, t = a->type;
    Enemy *e = 0;
    Pic *p;
    for (i = 0; i < MAX_ENEMIES; i++) if (!enemies[i].on) { e = &enemies[i]; break; }
    if (!e) return;
    e->tp = type_rec(t);
    e->pic = (u8)TW(e, T_PIC);
    p = pic(e->pic);
    e->on = 1; e->type = t; e->w = p->ux * 16; e->h = p->uy * 16;
    e->speed = TW(e, T_SPEED) << FP;
    e->flight = (u8)TW(e, T_FLIGHT);
    e->ground = e->flight >= F_GROUND;
    e->hp = TW(e, T_HP);
    e->x = (s16)(a->col * TILE + 16 - e->w / 2) << FP;
    e->y = (s16)(sy + 16 - e->h / 2) << FP;
    if (e->flight == F_GROUNDRIGHT) e->x -= e->w << FP;
    if (e->flight == F_GROUNDLEFT) e->x += e->w << FP;
    e->sx = e->x; e->sy = (s16)(100 - e->h / 2) << FP;
    e->leg = 0; e->dir = 1; e->dove = 0; e->flash = 0; e->leg_ready = 0;
    e->countdown = TW(e, T_COUNTDOWN) - (sy + 16 - e->h / 2);
    e->shoot_on = 0;
    e->volleys = (u8)TW(e, T_SHOOTCNT);
    e->wait = TW(e, T_SHOOTSTART);
    e->resting = 0;
    game.spawned++;
}

static void take_spawns(void) {
    Actor *a;
    for (;;) {
        a = ((Actor *)&art_actors) + next_actor;
        if (a->row == -32768) return;
        if (a->row * TILE < game.cam - 3 * TILE) return;
        next_actor++;
        if (a->level == 3) spawn(a, a->row * TILE - game.cam);   /* easy actors (rookie) */
    }
}

/* Moves e toward (tx, ty) (1/16 px) by up to `budget`; returns what's left
 * on arrival. The step is worked out once per leg (32-bit division is slow
 * on the 65816). */
static s16 travel(Enemy *e, s16 tx, s16 ty, s16 budget) {
    if (!e->leg_ready) {
        s16 dx = tx - e->x, dy = ty - e->y;
        e->left = approx_len(dx, dy);
        if (e->left > 0) {
            e->stx = (s16)((s32)dx * e->speed / e->left);
            e->sty = (s16)((s32)dy * e->speed / e->left);
        }
        e->leg_ready = 1;
    }
    if (e->left <= budget) { e->x = tx; e->y = ty; e->leg_ready = 0; return budget - e->left; }
    if (budget == e->speed) { e->x += e->stx; e->y += e->sty; }
    else { e->x += (s16)((s32)e->stx * budget / e->speed); e->y += (s16)((s32)e->sty * budget / e->speed); }
    e->left -= budget;
    return 0;
}

static void fly(Enemy *e) {
    u8 t = e->type, n = (u8)TW(e, T_NPATH), guard;
    s16 budget = e->speed;
    if (n == 0) { e->y += budget; return; }
    for (guard = 0; guard < 8; guard++) {
        if (e->dove) { e->x += e->dx; e->y += e->dy; return; }
        budget = travel(e, e->sx + (TW(e, TYPE_WORDS - 60 + e->leg * 2) << FP),
                        e->sy + (TW(e, TYPE_WORDS - 60 + e->leg * 2 + 1) << FP), budget);
        if (budget <= 0) return;
        if (e->flight == F_REPEAT) {
            u8 repos = (u8)TW(e, T_REPOS);
            if (n <= 1) return;
            if (e->dir) { if (e->leg + 1 >= n) { e->dir = 0; e->leg = n - 2; } else e->leg++; }
            else { if (e->leg <= repos) { e->dir = 1; e->leg = repos + 1; } else e->leg--; }
        } else if (e->flight == F_KAMI) {
            if (e->leg + 1 < n) e->leg++;
            else {
                s16 dx = ((px + 16 - e->w / 2) << FP) - e->x, dy = ((py + 16 - e->h / 2) << FP) - e->y;
                s16 d = approx_len(dx, dy), sp = e->speed;
                if (d == 0) d = 1;
                e->dx = (s16)((s32)dx * sp / d); e->dy = (s16)((s32)dy * sp / d); e->dove = 1;
            }
        } else {
            if (++e->leg >= n) { e->on = 0; return; }
        }
    }
}

static void enemy_fire(Enemy *e, u8 idx) {
    u8 t = e->type, g, guns = (u8)TW(e, T_NGUNS);
    s16 ex, ey;
    if (!e->shoot_on || dead_t || guns == 0) return;
    if (e->resting > 0) {
        if (--e->resting == 0) { e->volleys = (u8)TW(e, T_SHOOTCNT); e->wait = TW(e, T_SHOOTSPACE); }
        return;
    }
    if (--e->wait >= 0) return;
    e->wait = TW(e, T_SHOOTSPACE);
    ex = e->x >> FP; ey = e->y >> FP;
    if (ey + e->h < 0 || ey > SCREEN_H) return;
    for (g = 0; g < guns && g < 4; g++) {
        s16 gx = ex + TW(e, T_GUNS + g * 2), gy = ey + TW(e, T_GUNS + g * 2 + 1);
        s16 dx = (px + 16) - gx, dy = (py + 16) - gy, d = approx_len(dx, dy);
        if (d == 0) d = 1;
        shoot(1, gx - 4, gy - 4, (s16)((s32)dx * (5 << FP) / d), (s16)((s32)dy * (5 << FP) / d));
    }
    if (e->volleys) e->volleys--;
    if (e->volleys < 1) e->resting = TW(e, T_SHOOTFRAME) > 0 ? TW(e, T_SHOOTFRAME) : 1;
    (void)idx;
}

static u8 hit(s16 ax, s16 ay, u8 aw, u8 ah, s16 bx, s16 by, u8 bw, u8 bh) {
    return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah;
}

static void damage(Enemy *e, s16 dmg) {
    e->hp -= dmg;
    e->flash = 2;
    if (e->hp <= 0) {
        e->on = 0;
        game.kills++;
        game.score += TW(e, T_BOUNTY);
        boom((e->x >> FP) + e->w / 2, (e->y >> FP) + e->h / 2);
    }
}

static void hurt_player(s16 n) {
    if (dead_t) return;
    game.shield -= n;
    if (game.shield <= 0) { game.shield = 0; dead_t = 1; game.deaths++; boom(px + 16, py + 16); }
}

static u8 any_enemy(void) {
    u8 i;
    for (i = 0; i < MAX_ENEMIES; i++) if (enemies[i].on) return 1;
    return 0;
}

static void start_wave(void);

u8 na, act[MAX_ENEMIES];
s16 ax1[MAX_ENEMIES], ay1[MAX_ENEMIES], ax2[MAX_ENEMIES], ay2[MAX_ENEMIES];

/* One game frame (~23.3 Hz). */
static void game_tick(void) {
    u8 i, j;
    s16 scroll = 0;
    if (game.cam > 0) { game.cam--; scroll = 1; }
    take_spawns();
    for (i = 0; i < MAX_ENEMIES; i++) {
        Enemy *e = &enemies[i];
        s16 ex, ey;
        if (!e->on) continue;
        if (e->flash) e->flash--;
        if (e->countdown < 1) e->shoot_on = 1; else e->countdown -= (e->speed >> FP);
        if (e->flight == F_GROUND) e->y += scroll << FP;
        else if (e->flight == F_GROUNDLEFT || e->flight == F_GROUNDRIGHT) {
            e->y += scroll << FP;
            if (e->y >= 0) e->x += (e->flight == F_GROUNDRIGHT ? 1 : -1) * (e->speed);
        } else fly(e);
        if (!e->on) continue;
        enemy_fire(e, i);
        ex = e->x >> FP; ey = e->y >> FP;
        if (ey > SCREEN_H + 12 || ex > PLAY_W + e->w || ex + e->w < -e->w || (e->dove && ey + e->h < -40)) { e->on = 0; continue; }
        if (!e->ground && !dead_t && hit(ex + 4, ey + 4, e->w - 8, e->h - 8, px + 6, py + 6, 20, 20)) {
            hurt_player(12);
            damage(e, 6);
        }
    }
    /* The live enemies' boxes, once, for the shots below. */
    na = 0;
    for (i = 0; i < MAX_ENEMIES; i++) {
        Enemy *e = &enemies[i];
        if (!e->on) continue;
        act[na] = i; ax1[na] = e->x >> FP; ay1[na] = e->y >> FP;
        ax2[na] = ax1[na] + e->w; ay2[na] = ay1[na] + e->h; na++;
    }
    for (i = 0; i < MAX_SHOTS; i++) {
        Shot *s = &shots[i];
        s16 sx, sy;
        if (!s->on) continue;
        s->x += s->dx; s->y += s->dy;
        sx = s->x >> FP; sy = s->y >> FP;
        if (sy < -16 || sy > SCREEN_H || sx < -16 || sx > PLAY_W) { s->on = 0; continue; }
        if (s->enemy) {
            if (!dead_t && hit(sx + 2, sy + 2, 4, 4, px + 8, py + 6, 16, 20)) { s->on = 0; hurt_player(4); }
        } else {
            for (j = 0; j < na; j++) {
                if (sy >= ay2[j] || sy + 12 <= ay1[j] || sx >= ax2[j] || sx + 8 <= ax1[j]) continue;
                if (!enemies[act[j]].on) continue;
                s->on = 0; damage(&enemies[act[j]], 1); break;
            }
        }
    }
    for (i = 0; i < MAX_BOOMS; i++) if (booms[i].on && ++booms[i].t >= 8) booms[i].on = 0;
    /* Won: every actor out and every enemy gone; the ship flies off the top. */
    if (!dead_t && !end_t && ((Actor *)&art_actors)[next_actor].row == -32768 && !any_enemy()) end_t = 1;
    if (end_t && ++end_t > 60) { game.waves++; start_wave(); }
    if (dead_t && ++dead_t > 70) start_wave();
    /* The ship's guns: two shots every second game frame while fire is held. */
    if (fire_wait) fire_wait--;
}

static void player_frame(void) {
    u16 down = pad & ~pad_prev;
    s8 mx = 0, my = 0;
    if (pad) { idle = 0; demo = 0; } else if (++idle > 300) demo = 1;
    if (down & KEY_START) paused ^= 1;
    if (dead_t) return;
    if (end_t > 20) {   /* the fly-off */
        s16 c = px + 16;
        px += c < 136 ? 2 : c > 152 ? -2 : 0;
        py -= 2;
        bank = 0;
        return;
    }
    if (demo) {
        /* Sweep side to side near the bottom, firing. */
        if (px < 40) demo_dir = 1;
        if (px > PLAY_W - 72) demo_dir = -1;
        if (!demo_dir) demo_dir = 1;
        mx = demo_dir;
        if (py < 160) my = 1;
    } else {
        if (pad & KEY_LEFT) mx = -1;
        if (pad & KEY_RIGHT) mx = 1;
        if (pad & KEY_UP) my = -1;
        if (pad & KEY_DOWN) my = 1;
    }
    px += mx * 3; py += my * 3;
    if (px < 0) px = 0;
    if (px > PLAY_W - 32) px = PLAY_W - 32;
    if (py < 0) py = 0;
    if (py > SCREEN_H - 32) py = SCREEN_H - 32;
    bank = mx;
    if ((demo || (pad & (KEY_B | KEY_Y))) && !fire_wait) {
        shoot(0, px + 5, py, 0, -(12 << FP));
        shoot(0, px + 19, py, 0, -(12 << FP));
        fire_wait = 2;
    }
}

static void draw(void) {
    u8 i;
    s16 sx = scroll_x();
    oam_n = 0;
    for (i = 0; i < 32; i++) oam_hi[i] = 0;
    if (!dead_t) put(px - sx, py, (u16)((bank + 1) * 4), 0, 1);   /* the ship: 32x32 frames 0..2 */
    /* Shots: one 16x16 unit each, written in place (they are the most
     * numerous sprites, and a call per sprite costs on the 65816). */
    for (i = 0; i < MAX_SHOTS; i++) {
        Shot *t = &shots[i];
        s16 x, y;
        u8 *o;
        if (!t->on || oam_n >= 128) continue;
        x = (t->x >> FP) - sx - 4; y = t->y >> FP;
        if (x <= -16 || x >= 256 || y <= -16 || y >= SCREEN_H) continue;
        o = oamMemory + (oam_n << 2);
        o[0] = (u8)x; o[1] = (u8)y;
        if (t->enemy) { o[2] = (u8)eshot_chr; o[3] = eshot_attr; }
        else { o[2] = (u8)shot_chr; o[3] = shot_attr; }
        if (x < 0) oam_hi[oam_n >> 2] |= 1 << ((oam_n & 3) << 1);
        oam_n++;
    }
    for (i = 0; i < MAX_BOOMS; i++)
        if (booms[i].on) draw_pic(PIC_EXPLO0 + (booms[i].t >> 1), booms[i].x - sx, booms[i].y);
    for (i = 0; i < MAX_ENEMIES; i++)
        if (enemies[i].on && !(enemies[i].flash & 1))
            draw_pic(enemies[i].pic, (enemies[i].x >> FP) - sx, enemies[i].y >> FP);
    for (i = (u8)oam_n; i < oam_prev; i++) oamMemory[(i << 2) + 1] = 0xE0;   /* off screen */
    for (i = 0; i < 32; i++) oamMemory[512 + i] = oam_hi[i];
    oam_prev = oam_n;
}

static void reset_cache(void) {
    u16 i;
    for (i = 0; i < ART_BG_CHARS; i++) slot_of[i] = NO_SLOT;
    for (i = 0; i < SLOTS; i++) { refs[i] = 0; free_slots[i] = SLOTS - 1 - i; }   /* pops 0, 1, 2, ... */
    free_top = SLOTS;
    q_head = q_tail = 0;
    ndirty = 0; njobs = 0;
    for (i = 0; i < 64; i++) dirty[i] = 0;
    loaded_lo = MAP_H; loaded_hi = MAP_H - 1;
}

static void start_wave(void) {
    u8 i, more;
    setScreenOff();
    reset_cache();
    game.cam = MAP_H * TILE - SCREEN_H;
    game.shield = 100;
    next_actor = 0;
    for (i = 0; i < MAX_ENEMIES; i++) enemies[i].on = 0;
    for (i = 0; i < MAX_SHOTS; i++) shots[i].on = 0;
    for (i = 0; i < MAX_BOOMS; i++) booms[i].on = 0;
    px = PLAY_W / 2 - 16; py = 170; bank = 0;
    dead_t = end_t = 0; fire_wait = 0; tick_acc = 0;
    /* The screen is off: load the first screenful a row at a time, each
     * row's characters straight to VRAM. */
    do {
        more = update_rows();
        while (ndirty || q_head != q_tail) { plan_vram(QUEUE, 4, JOBS); send_vram(); }
    } while (more);
    bgSetScroll(0, scroll_x(), (game.cam - 1) & 511);
    setScreenOn();
}

int main(void) {
    setMode(BG_MODE1, 0);
    bgSetGfxPtr(0, VRAM_BG_CHARS);
    bgSetMapPtr(0, VRAM_BG_MAP, SC_64x64);
    bgSetDisable(1);
    bgSetDisable(2);
    dmaCopyCGram(&art_bgpal, 0, 256);
    dmaCopyCGram(&art_objpal, 128, 256);
    dmaCopyVram(&art_objchars, VRAM_OBJ, 16384);
    oamInitGfxAttr(VRAM_OBJ, OBJ_SIZE16_L32);
    oamClear(0, 128);
    shot_chr = pic(PIC_SHOT)->unit[0];
    shot_attr = (u8)(0x30 | (pic(PIC_SHOT)->pal << 1) | ((shot_chr >> 8) & 1));
    eshot_chr = pic(PIC_ESHOT)->unit[0];
    eshot_attr = (u8)(0x30 | (pic(PIC_ESHOT)->pal << 1) | ((eshot_chr >> 8) & 1));
    demo = 1; idle = 301;
    game.free_min = SLOTS;
    start_wave();
    for (;;) {
        pad_prev = pad;
        pad = padsCurrent(0);
        player_frame();
        if (!paused) {
            tick_acc += 7;
            while (tick_acc >= 18) { tick_acc -= 18; game_tick(); }
        }
        update_rows();
        draw();
        game.frames++;
        plan_vram(32, 1, 6);
        WaitForVBlank();
        send_vram();            /* first: the vertical blank is short */
        bgSetScroll(0, scroll_x(), (game.cam - 1) & 511);
    }
    return 0;
}
