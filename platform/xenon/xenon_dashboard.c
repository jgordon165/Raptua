/* Where Quit goes on the Xbox 360: dashboard.txt in the raptua folder names
 * a .xex to launch (Aurora's default.xex on a USB stick, say). With no file,
 * an empty one or "default", the title just ends and the console goes to its
 * default dashboard.
 *
 * The path may be written with the drive names people know from Aurora and
 * file managers, which become the kernel's device paths:
 *   Usb0: .. Usb2:   \Device\Mass0 .. \Device\Mass2   (USB sticks and drives)
 *   Hdd:, Hdd1:      \Device\Harddisk0\Partition1      (the hard drive)
 *   game:            the raptua folder itself
 * and a path already starting with "\Device\" is used as written. Either
 * slash works. */
#include "xenon_platform.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

static const struct { const char *drive, *device; } drives[] = {
    { "usb0:", "\\Device\\Mass0" },
    { "usb1:", "\\Device\\Mass1" },
    { "usb2:", "\\Device\\Mass2" },
    { "hdd1:", "\\Device\\Harddisk0\\Partition1" },
    { "hdd:", "\\Device\\Harddisk0\\Partition1" },
    { "game:", "game:" },
};

static int starts_with_nocase(const char *s, const char *prefix)
{
    for (; *prefix; ++s, ++prefix)
        if (tolower((unsigned char)*s) != *prefix) return 0;
    return 1;
}

int xp_dashboard_map(const char *in, char *out, size_t out_bytes)
{
    size_t i, n;
    const char *rest = NULL, *device = NULL;
    char *p;
    if (!in || !*in || out_bytes < 2) return 0;
    for (i = 0; i < sizeof drives / sizeof drives[0]; ++i) {
        if (starts_with_nocase(in, drives[i].drive)) {
            device = drives[i].device;
            rest = in + strlen(drives[i].drive);
            break;
        }
    }
    if (!device) {
        if (!starts_with_nocase(in, "\\device\\") && !starts_with_nocase(in, "/device/")) return 0;
        device = "";
        rest = in;
    }
    if (*device)   /* a drive name: its device, one separator, the rest */
        while (*rest == '\\' || *rest == '/') ++rest;
    n = (size_t)snprintf(out, out_bytes, "%s%s%s", device, *device ? "\\" : "", rest);
    if (n >= out_bytes) return 0;
    for (p = out; *p; ++p)
        if (*p == '/') *p = '\\';
    return 1;
}

int xp_dashboard_target(char *out, size_t out_bytes)
{
    char path[512], line[512];
    FILE *f;
    int found = 0;
    snprintf(path, sizeof path, "%sdashboard.txt", xp_root());
    f = fopen(path, "r");
    if (!f) return 0;
    while (fgets(line, sizeof line, f)) {
        char *s = line, *e;
        while (*s == ' ' || *s == '\t') ++s;
        e = s + strlen(s);
        while (e > s && (e[-1] == '\n' || e[-1] == '\r' || e[-1] == ' ' || e[-1] == '\t')) *--e = '\0';
        if (!*s || *s == '#' || *s == ';') continue;
        if (starts_with_nocase(s, "default") && s[7] == '\0') break;
        found = xp_dashboard_map(s, out, out_bytes);
        if (!found) {
            char msg[600];
            snprintf(msg, sizeof msg, "dashboard.txt: don't know the drive in \"%s\" (Usb0:, Usb1:, Hdd:, game: or \\Device\\...)", s);
            xp_log(msg);
        }
        break;
    }
    fclose(f);
    return found;
}
