/* xenon_platform.h on a PC, so the 360's SDL build can be tested without a
 * console (cmake -DRAPTUA_XENON_SIM=ON). Settings from the environment:
 *   XENON_SIM_ROOT   the port's folder (default: the current folder), with '/'
 *   XENON_SIM_SIZE   the "TV" size, WxH (default 1280x720)
 *   XENON_SIM_PAD    button presses, "frame:button ..." (buttons: up down left
 *                    right a b x y lb rb start back lt rt), each held 2 frames;
 *                    "n-m:button" holds it from frame n to m. A "2" before the
 *                    button ("2a", "2left") is the second pad's (co-op), which
 *                    is plugged in once the script names one.
 *   XENON_SIM_SHOT   "frame:file.bmp ...": saves those presented frames
 *   XENON_SIM_FRAMES quits after that many presented frames */
#define _POSIX_C_SOURCE 200809L
#include "xenon_platform.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int started;
static char root[512] = "./";
static int tv_w = 1280, tv_h = 720;
static long frames;
static xp_pad pad, pad2;
static uint64_t audio_bytes_submitted;
static uint64_t audio_start;
static int audio_on;

int xp_init(void)
{
    const char *r, *s;
    if (started) return 0;
    started = 1;
    r = getenv("XENON_SIM_ROOT");
    if (r && *r) snprintf(root, sizeof root, "%s%s", r, r[strlen(r) - 1] == '/' ? "" : "/");
    s = getenv("XENON_SIM_SIZE");
    if (s) sscanf(s, "%dx%d", &tv_w, &tv_h);
    return 0;
}

const char *xp_root(void) { return root; }

void xp_display_size(int *w, int *h)
{
    xp_init();
    *w = tv_w;
    *h = tv_h;
}

static void save_bmp(const char *path, const uint32_t *argb, int w, int h, int pitch)
{
    FILE *f = fopen(path, "wb");
    int y, x, row = w * 3, pad_bytes = (4 - row % 4) % 4;
    unsigned char hdr[54] = { 'B', 'M' };
    unsigned size = 54 + (unsigned)(row + pad_bytes) * (unsigned)h;
    if (!f) return;
#define P32(o, v) do { hdr[o] = (unsigned char)(v); hdr[o + 1] = (unsigned char)((v) >> 8); \
        hdr[o + 2] = (unsigned char)((v) >> 16); hdr[o + 3] = (unsigned char)((v) >> 24); } while (0)
    P32(2, size); P32(10, 54); P32(14, 40); P32(18, (unsigned)w); P32(22, (unsigned)h);
    hdr[26] = 1; hdr[28] = 24;
    fwrite(hdr, 1, 54, f);
    for (y = h - 1; y >= 0; --y) {
        const uint32_t *src = (const uint32_t *)((const unsigned char *)argb + (size_t)y * pitch);
        for (x = 0; x < w; ++x) {
            unsigned char px[3] = { (unsigned char)src[x], (unsigned char)(src[x] >> 8), (unsigned char)(src[x] >> 16) };
            fwrite(px, 1, 3, f);
        }
        fwrite("\0\0\0", 1, (size_t)pad_bytes, f);
    }
    fclose(f);
}

void xp_present(const uint32_t *argb, int w, int h, int pitch)
{
    const char *shots = getenv("XENON_SIM_SHOT"), *quit = getenv("XENON_SIM_FRAMES");
    ++frames;
    if (shots) {
        const char *p = shots;
        while (*p) {
            long n;
            char file[400];
            if (sscanf(p, "%ld:%399s", &n, file) == 2 && n == frames) save_bmp(file, argb, w, h, pitch);
            p = strchr(p, ' ');
            if (!p) break;
            ++p;
        }
    }
    if (quit && frames >= atol(quit)) exit(0);
}

static int pressed(const char *name)
{
    const char *script = getenv("XENON_SIM_PAD"), *p;
    if (!script) return 0;
    for (p = script; *p;) {
        long n, m;
        char b[16];
        if (sscanf(p, "%ld-%ld:%15s", &n, &m, b) == 3) {
            if (strcmp(b, name) == 0 && frames >= n && frames <= m) return 1;
        } else if (sscanf(p, "%ld:%15s", &n, b) == 2 && strcmp(b, name) == 0 && frames >= n && frames < n + 2) {
            return 1;
        }
        p = strchr(p, ' ');
        if (!p) break;
        ++p;
    }
    return 0;
}

/* One pad's buttons; pre: "" for the first pad, "2" for the second. */
static void read_pad(xp_pad *d, const char *pre)
{
    char n[20];
#define B(f, name) (snprintf(n, sizeof n, "%s%s", pre, name), d->f = pressed(n))
    memset(d, 0, sizeof *d);
    B(up, "up"); B(down, "down"); B(left, "left"); B(right, "right");
    B(a, "a"); B(b, "b"); B(x, "x"); B(y, "y");
    B(lb, "lb"); B(rb, "rb"); B(start, "start"); B(back, "back");
    B(lt, "lt"); B(rt, "rt");
    if (d->lt) d->lt = 255;
    if (d->rt) d->rt = 255;
#undef B
}

void xp_poll(void)
{
    const char *script = getenv("XENON_SIM_PAD");
    read_pad(&pad, "");
    pad.connected = 1;
    read_pad(&pad2, "2");
    pad2.connected = script && (strstr(script, ":2") != NULL);
}

void xp_get_pad(int port, xp_pad *out)
{
    if (port == 0) *out = pad;
    else if (port == 1) *out = pad2;
    else memset(out, 0, sizeof *out);
}

uint64_t xp_counter(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

uint64_t xp_frequency(void) { return 1000000000ull; }

void xp_delay_ms(uint32_t ms)
{
    struct timespec ts = { (time_t)(ms / 1000), (long)(ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

/* Sound plays at 48 kHz x 4 bytes in real time into a 64 KB buffer. */
void xp_audio_init(void)
{
    audio_on = 1;
    audio_start = xp_counter();
    audio_bytes_submitted = 0;
}

int xp_audio_free(void)
{
    const uint64_t rate = XP_AUDIO_RATE * 4ull;
    uint64_t now, played, queued;
    if (!audio_on) return 0;
    now = xp_counter();
    played = (now - audio_start) * rate / 1000000000ull;
    if (played > audio_bytes_submitted) {          /* ran dry: the clock restarts */
        audio_start = now - audio_bytes_submitted * 1000000000ull / rate;
        played = audio_bytes_submitted;
    }
    queued = audio_bytes_submitted - played;
    return queued >= 65536 ? 0 : (int)(65536 - queued);
}

void xp_audio_submit(const void *s16le, int bytes)
{
    (void)s16le;
    audio_bytes_submitted += (uint64_t)bytes;
}

int xp_audio_start_feeder(void (*fill)(void))
{
    (void)fill;
    return 0;    /* no threads: the game's thread fills the sound */
}

void xp_audio_stop_feeder(void) {}

void xp_lock(void) {}
void xp_unlock(void) {}

void xp_log(const char *msg) { fprintf(stderr, "%s\n", msg); }

/* The stand-in plays the xsdk title here: it can exit, and says so. */
int xp_can_exit(void) { return 1; }
/* The stand-in's command line: XENON_SIM_CMDLINE, as the loader's would be. */
const char *xp_command_line(void)
{
    const char *c = getenv("XENON_SIM_CMDLINE");
    return c ? c : "\"game:\\raptua.xex\"";
}

void xp_exit_title(int status)
{
    char commands[1024], target[512];
    const char *c = commands;
    int from_args = 0;
    if (!xp_exit_commands(commands, sizeof commands, &from_args)) commands[0] = '\0';
    else fprintf(stderr, "exit: commands from %s: %s\n", from_args ? "the command line" : "dashboard.txt", commands);
    /* The stand-in has no drives to look on: it launches the first one. */
    if (xp_exit_next(&c, target, sizeof target) == XP_EXIT_LAUNCH) fprintf(stderr, "exit: launching %s\n", target);
    else fprintf(stderr, "exit: back to the dashboard\n");
    exit(status);
}
