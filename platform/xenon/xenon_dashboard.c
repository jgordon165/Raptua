/* Where Quit goes on the Xbox 360: exit commands, tried in order.
 *
 *   launch <path>   start that .xex in place of Raptua: Aurora's default.xex,
 *                   or any homebrew (unsigned) .xex while the console's
 *                   patches (BadUpdate / FreeMyXe) are in place. If the file
 *                   isn't there the next command is tried.
 *   dashboard       end the title: the console goes to its default dashboard
 *
 * With no command that works, it's the default dashboard.
 *
 * The commands come from Raptua's command line if whatever started it gave
 * one, else from dashboard.txt in the raptua folder:
 *
 *   raptua.xex --exit "launch Usb0:\Aurora\default.xex; dashboard"
 *   (--exit may be given more than once, and --exit=... works too)
 *
 *   dashboard.txt: one command per line ("#" starts a comment); a line with
 *   just a path is "launch" that path, as the file used to be.
 *
 * Paths may use the drive names people know from Aurora and file managers,
 * which become the kernel's device paths:
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

/* Appends the --exit values of a command line to out, ";"-separated.
 * Quotes group words; the first word (the program) is skipped. */
static int commands_from_args(const char *cl, char *out, size_t out_bytes)
{
    char word[1024];
    int found = 0, first = 1, want = 0;
    out[0] = '\0';
    if (!cl) return 0;
    while (*cl) {
        size_t n = 0;
        int quoted = 0;
        while (*cl == ' ' || *cl == '\t') ++cl;
        if (!*cl) break;
        while (*cl && (quoted || (*cl != ' ' && *cl != '\t'))) {
            if (*cl == '"') { quoted = !quoted; ++cl; continue; }
            if (n + 1 < sizeof word) word[n++] = *cl;
            ++cl;
        }
        word[n] = '\0';
        if (first) { first = 0; continue; }
        if (want) {
            want = 0;
        } else if (strcmp(word, "--exit") == 0) {
            want = 1;
            continue;
        } else if (strncmp(word, "--exit=", 7) == 0) {
            memmove(word, word + 7, strlen(word + 7) + 1);
        } else {
            continue;
        }
        if (found && strlen(out) + 1 < out_bytes) strcat(out, ";");
        if (strlen(out) + strlen(word) < out_bytes) strcat(out, word);
        found = 1;
    }
    return found;
}

/* dashboard.txt's lines as one ";"-separated list (comments and blanks out). */
static int commands_from_file(char *out, size_t out_bytes)
{
    char path[512], line[512];
    FILE *f;
    int found = 0;
    out[0] = '\0';
    snprintf(path, sizeof path, "%sdashboard.txt", xp_root());
    f = fopen(path, "r");
    if (!f) return 0;
    while (fgets(line, sizeof line, f)) {
        char *s = line, *e;
        while (*s == ' ' || *s == '\t') ++s;
        e = s + strlen(s);
        while (e > s && (e[-1] == '\n' || e[-1] == '\r' || e[-1] == ' ' || e[-1] == '\t')) *--e = '\0';
        if (!*s || *s == '#' || *s == ';') continue;
        if (found && strlen(out) + 1 < out_bytes) strcat(out, ";");
        if (strlen(out) + strlen(s) < out_bytes) strcat(out, s);
        found = 1;
    }
    fclose(f);
    return found;
}

int xp_exit_commands(char *out, size_t out_bytes, int *from_args)
{
    *from_args = commands_from_args(xp_command_line(), out, out_bytes);
    if (*from_args) return 1;
    return commands_from_file(out, out_bytes);
}

int xp_exit_next(const char **cursor, char *path_out, size_t out_bytes)
{
    char cmd[512];
    const char *c = *cursor;
    while (c && *c) {
        size_t n = 0;
        char *s, *e, *arg;
        while (*c && *c != ';' && n + 1 < sizeof cmd) cmd[n++] = *c++;
        while (*c && *c != ';') ++c;
        if (*c == ';') ++c;
        cmd[n] = '\0';
        s = cmd;
        while (*s == ' ' || *s == '\t') ++s;
        e = s + strlen(s);
        while (e > s && (e[-1] == ' ' || e[-1] == '\t')) *--e = '\0';
        if (!*s) continue;
        *cursor = c;
        if ((starts_with_nocase(s, "dashboard") && s[9] == '\0') || (starts_with_nocase(s, "default") && s[7] == '\0'))
            return XP_EXIT_DASHBOARD;
        arg = s;
        if (starts_with_nocase(s, "launch") && (s[6] == ' ' || s[6] == '\t')) {
            arg = s + 6;
            while (*arg == ' ' || *arg == '\t') ++arg;
        }
        if (xp_dashboard_map(arg, path_out, out_bytes)) return XP_EXIT_LAUNCH;
        {
            char msg[640];
            snprintf(msg, sizeof msg, "exit: don't know \"%s\" (launch <Usb0:\\..., Hdd:\\..., game:\\... or \\Device\\...> or dashboard)", s);
            xp_log(msg);
        }
        c = *cursor;
    }
    *cursor = c;
    return XP_EXIT_END;
}
