/* snesrun: runs a SNES ROM headless on a libretro core (snes9x), presses
 * scripted buttons, and saves chosen frames as BMP files. Used by the SNES
 * workflow to check that ROMs boot and play, without a console or a window.
 *
 *   snesrun <core.so> <rom.sfc> <frames> [frame:buttons ...] [shot:frame:file.bmp ...]
 *
 * buttons: any of up down left right a b x y l r start select, joined by '+'
 * (held for that one frame; "120-180:a" holds A for frames 120..180).
 * Exits 0 after <frames> frames; 1 if the core or ROM won't load; 2 if every
 * saved frame was a single colour (the ROM didn't draw anything).
 *
 * Build: cc -O2 -I<snes9x>/libretro snesrun.c -ldl -o snesrun */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libretro.h"

#define MAX_EVENTS 256

typedef struct { int from, to; unsigned mask; } press;
typedef struct { int frame; const char *file; } shot;

static press presses[MAX_EVENTS];
static int npresses;
static shot shots[MAX_EVENTS];
static int nshots;
static int frame_no;
static unsigned pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
static int flat_frames, saved_frames;

static unsigned button_bit(const char *name, size_t n)
{
    static const struct { const char *name; unsigned id; } map[] = {
        {"up", RETRO_DEVICE_ID_JOYPAD_UP}, {"down", RETRO_DEVICE_ID_JOYPAD_DOWN},
        {"left", RETRO_DEVICE_ID_JOYPAD_LEFT}, {"right", RETRO_DEVICE_ID_JOYPAD_RIGHT},
        {"a", RETRO_DEVICE_ID_JOYPAD_A}, {"b", RETRO_DEVICE_ID_JOYPAD_B},
        {"x", RETRO_DEVICE_ID_JOYPAD_X}, {"y", RETRO_DEVICE_ID_JOYPAD_Y},
        {"l", RETRO_DEVICE_ID_JOYPAD_L}, {"r", RETRO_DEVICE_ID_JOYPAD_R},
        {"start", RETRO_DEVICE_ID_JOYPAD_START}, {"select", RETRO_DEVICE_ID_JOYPAD_SELECT},
    };
    for (size_t i = 0; i < sizeof map / sizeof map[0]; ++i)
        if (strlen(map[i].name) == n && strncmp(map[i].name, name, n) == 0) return 1u << map[i].id;
    fprintf(stderr, "snesrun: unknown button '%.*s'\n", (int)n, name);
    exit(1);
}

static void parse_arg(const char *arg)
{
    if (strncmp(arg, "shot:", 5) == 0) {
        const char *p = arg + 5;
        char *end;
        int f = (int)strtol(p, &end, 10);
        if (*end != ':' || nshots >= MAX_EVENTS) { fprintf(stderr, "snesrun: bad shot '%s'\n", arg); exit(1); }
        shots[nshots].frame = f;
        shots[nshots].file = end + 1;
        ++nshots;
        return;
    }
    char *end;
    int from = (int)strtol(arg, &end, 10), to = from;
    if (*end == '-') to = (int)strtol(end + 1, &end, 10);
    if (*end != ':' || npresses >= MAX_EVENTS) { fprintf(stderr, "snesrun: bad press '%s'\n", arg); exit(1); }
    unsigned mask = 0;
    const char *b = end + 1;
    while (*b) {
        const char *e = strchr(b, '+');
        size_t n = e ? (size_t)(e - b) : strlen(b);
        mask |= button_bit(b, n);
        b += n + (e ? 1 : 0);
    }
    presses[npresses].from = from;
    presses[npresses].to = to;
    presses[npresses].mask = mask;
    ++npresses;
}

static void save_bmp(const char *path, const void *data, unsigned w, unsigned h, size_t pitch)
{
    FILE *f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "snesrun: can't write %s\n", path); return; }
    uint32_t row = w * 3, pad = (4 - row % 4) % 4, size = 54 + (row + pad) * h;
    uint8_t hdr[54] = {'B', 'M'};
    #define PUT32(o, v) (hdr[o] = (uint8_t)(v), hdr[o + 1] = (uint8_t)((v) >> 8), hdr[o + 2] = (uint8_t)((v) >> 16), hdr[o + 3] = (uint8_t)((v) >> 24))
    PUT32(2, size); PUT32(10, 54); PUT32(14, 40); PUT32(18, w); PUT32(22, h);
    hdr[26] = 1; hdr[28] = 24;
    fwrite(hdr, 1, 54, f);
    uint32_t first = 0;
    int flat = 1;
    for (unsigned y = h; y-- > 0;) {
        const uint8_t *src = (const uint8_t *)data + y * pitch;
        for (unsigned x = 0; x < w; ++x) {
            uint32_t r, g, b;
            if (pixel_format == RETRO_PIXEL_FORMAT_XRGB8888) {
                uint32_t p = ((const uint32_t *)src)[x];
                r = (p >> 16) & 255; g = (p >> 8) & 255; b = p & 255;
            } else if (pixel_format == RETRO_PIXEL_FORMAT_RGB565) {
                uint16_t p = ((const uint16_t *)src)[x];
                r = ((p >> 11) & 31) << 3; g = ((p >> 5) & 63) << 2; b = (p & 31) << 3;
            } else {
                uint16_t p = ((const uint16_t *)src)[x];
                r = ((p >> 10) & 31) << 3; g = ((p >> 5) & 31) << 3; b = (p & 31) << 3;
            }
            uint32_t rgb = r << 16 | g << 8 | b;
            if (x == 0 && y == h - 1) first = rgb;
            else if (rgb != first) flat = 0;
            uint8_t px[3] = {(uint8_t)b, (uint8_t)g, (uint8_t)r};
            fwrite(px, 1, 3, f);
        }
        static const uint8_t zero[3] = {0, 0, 0};
        fwrite(zero, 1, pad, f);
    }
    fclose(f);
    ++saved_frames;
    flat_frames += flat;
    printf("snesrun: frame %d -> %s (%ux%u)%s\n", frame_no, path, w, h, flat ? " [single colour]" : "");
}

static bool env_cb(unsigned cmd, void *data)
{
    switch (cmd) {
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
        pixel_format = *(const enum retro_pixel_format *)data;
        return true;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        *(const char **)data = ".";
        return true;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        *(bool *)data = true;
        return true;
    default:
        return false;
    }
}

static void video_cb(const void *data, unsigned w, unsigned h, size_t pitch)
{
    if (!data) return;
    for (int i = 0; i < nshots; ++i)
        if (shots[i].frame == frame_no) save_bmp(shots[i].file, data, w, h, pitch);
}

static void audio_cb(int16_t l, int16_t r) { (void)l; (void)r; }
static size_t audio_batch_cb(const int16_t *d, size_t frames) { (void)d; return frames; }
static void input_poll_cb(void) {}

static int16_t input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id)
{
    (void)index;
    if (port != 0 || device != RETRO_DEVICE_JOYPAD) return 0;
    for (int i = 0; i < npresses; ++i)
        if (frame_no >= presses[i].from && frame_no <= presses[i].to && (presses[i].mask >> id & 1)) return 1;
    return 0;
}

#define LOAD(sym) do { *(void **)&sym = dlsym(core, #sym); if (!sym) { fprintf(stderr, "snesrun: core lacks %s\n", #sym); return 1; } } while (0)

int main(int argc, char **argv)
{
    if (argc < 4) {
        fprintf(stderr, "usage: snesrun <core.so> <rom.sfc> <frames> [frame:buttons ...] [shot:frame:file.bmp ...]\n");
        return 1;
    }
    int frames = atoi(argv[3]);
    for (int i = 4; i < argc; ++i) parse_arg(argv[i]);

    void *core = dlopen(argv[1], RTLD_NOW);
    if (!core) { fprintf(stderr, "snesrun: %s\n", dlerror()); return 1; }
    void (*retro_set_environment)(retro_environment_t);
    void (*retro_set_video_refresh)(retro_video_refresh_t);
    void (*retro_set_audio_sample)(retro_audio_sample_t);
    void (*retro_set_audio_sample_batch)(retro_audio_sample_batch_t);
    void (*retro_set_input_poll)(retro_input_poll_t);
    void (*retro_set_input_state)(retro_input_state_t);
    void (*retro_init)(void);
    bool (*retro_load_game)(const struct retro_game_info *);
    void (*retro_run)(void);
    void (*retro_unload_game)(void);
    void (*retro_deinit)(void);
    LOAD(retro_set_environment); LOAD(retro_set_video_refresh); LOAD(retro_set_audio_sample);
    LOAD(retro_set_audio_sample_batch); LOAD(retro_set_input_poll); LOAD(retro_set_input_state);
    LOAD(retro_init); LOAD(retro_load_game); LOAD(retro_run); LOAD(retro_unload_game); LOAD(retro_deinit);

    retro_set_environment(env_cb);
    retro_init();
    retro_set_video_refresh(video_cb);
    retro_set_audio_sample(audio_cb);
    retro_set_audio_sample_batch(audio_batch_cb);
    retro_set_input_poll(input_poll_cb);
    retro_set_input_state(input_state_cb);

    FILE *f = fopen(argv[2], "rb");
    if (!f) { fprintf(stderr, "snesrun: can't open %s\n", argv[2]); return 1; }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    void *rom = malloc((size_t)size);
    if (!rom || fread(rom, 1, (size_t)size, f) != (size_t)size) { fprintf(stderr, "snesrun: can't read ROM\n"); return 1; }
    fclose(f);
    struct retro_game_info info = {argv[2], rom, (size_t)size, NULL};
    if (!retro_load_game(&info)) { fprintf(stderr, "snesrun: the core refused %s\n", argv[2]); return 1; }

    for (frame_no = 0; frame_no < frames; ++frame_no) retro_run();
    retro_unload_game();
    retro_deinit();
    free(rom);
    if (saved_frames > 0 && flat_frames == saved_frames) {
        fprintf(stderr, "snesrun: every saved frame was a single colour\n");
        return 2;
    }
    return 0;
}
