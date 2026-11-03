/* profile_parse.c: parse a game profile or an input preset as the PS4 title does (run by
 * tests/profile_parse_test.sh, from scripts/ps4/build.sh probe-test).
 *
 *   profile_parse ini FILE     the fork's load_profile (native/orbis/wine64_main_orbis.c): a 16 KiB read,
 *                              pw_game_profile_parse, the arguments split into words, the DLL overrides;
 *                              prints "OK FILE" and then one "key=value" line per field the test checks
 *   profile_parse input FILE   the fork's g_bindings (native/orbis/pw_milestone_orbis.c): a 4 KiB read
 *                              (a longer file would be cut), pw_game_input_init + pw_game_input_parse
 *
 * Exit 0 when the file parses, 1 when it does not ("FAIL FILE: why"), 2 on usage.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 * Links the fork's LGPL-2.1-or-later sources src/pw_app_profile.c, src/pw_game_profile.c,
 * src/pw_wine_launch.c and src/pw_result.c (third_party/prospero-win).
 */
#include "pw_game_profile.h"
#include "pw_wine_launch.h"

#include <stdio.h>
#include <string.h>

/* The title's buffers: load_profile's text[16384], g_bindings' text[4096]. */
enum { INI_BUFFER = 16384, INPUT_BUFFER = 4096 };

static size_t read_file(const char *path, uint8_t *buffer, size_t size, int *truncated)
{
    FILE *file = fopen(path, "rb");
    size_t got;

    *truncated = 0;
    if (!file) return (size_t)-1;
    got = fread(buffer, 1, size, file);
    /* load_profile refuses a full buffer ("toolarge"); g_bindings parses it cut. */
    if (got == size) *truncated = 1;
    fclose(file);
    return got;
}

static int parse_ini(const char *path)
{
    static uint8_t text[INI_BUFFER];
    static PwGameProfile profile;
    char words[PW_APP_ARGUMENTS_CAPACITY], overrides[PW_APP_DLL_OVERRIDES_CAPACITY];
    const char *argv[PW_WINE_LAUNCH_WORDS];
    int truncated, status, argc;
    size_t got = read_file(path, text, sizeof(text), &truncated);

    if (got == (size_t)-1) { printf("FAIL %s: cannot read\n", path); return 1; }
    if (truncated) { printf("FAIL %s: toolarge (the title reads %d bytes)\n", path, INI_BUFFER); return 1; }
    if ((status = pw_game_profile_parse(text, got, &profile)) != PW_OK) {
        printf("FAIL %s: parse:%s\n", path, pw_result_name(status));
        return 1;
    }
    argc = pw_wine_launch_split(profile.app.arguments, words, sizeof(words), argv, PW_WINE_LAUNCH_WORDS);
    if (argc < 0) { printf("FAIL %s: arguments\n", path); return 1; }
    if ((status = pw_app_profile_effective_dll_overrides(&profile.app, overrides, sizeof(overrides))) != PW_OK) {
        printf("FAIL %s: dll_overrides:%s\n", path, pw_result_name(status));
        return 1;
    }
    printf("OK %s\n", path);
    printf("id=%s\n", profile.app.id);
    printf("executable=%s\n", profile.app.executable);
    printf("working_directory=%s\n", profile.app.working_directory);
    printf("argc=%d\n", argc);
    printf("dll_overrides=%s\n", overrides);
    printf("architecture=%s\n", profile.app.architecture == PW_APP_ARCH_PE32 ? "pe32" : "pe64");
    printf("desktop=%ux%u\n", (unsigned)profile.display.width, (unsigned)profile.display.height);
    printf("preset=%s\n", profile.input.preset);
    printf("winedebug=%s\n", profile.winedebug);
    for (size_t i = 0; i < profile.debug_env_count; i++)
        printf("env=%s=%s\n", profile.debug_env[i].name, profile.debug_env[i].value);
    printf("cpu_native=%d\n", pw_game_cpu_native(&profile));
    printf("saves=%s\n", profile.runtime.saves);
    return 0;
}

static int parse_input(const char *path)
{
    static uint8_t text[INPUT_BUFFER];
    PwGameInput input;
    int truncated, status;
    size_t got = read_file(path, text, sizeof(text), &truncated);

    if (got == (size_t)-1) { printf("FAIL %s: cannot read\n", path); return 1; }
    if (truncated) { printf("FAIL %s: longer than the title's %d-byte read\n", path, INPUT_BUFFER); return 1; }
    pw_game_input_init(&input);
    if ((status = pw_game_input_parse(text, got, &input)) != PW_OK) {
        printf("FAIL %s: parse:%s\n", path, pw_result_name(status));
        return 1;
    }
    printf("OK %s\n", path);
    printf("mode=%s\n", input.mode == PW_GAME_INPUT_XINPUT ? "xinput" : "keyboard");
    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 3) { fprintf(stderr, "usage: profile_parse ini|input FILE\n"); return 2; }
    if (!strcmp(argv[1], "ini")) return parse_ini(argv[2]);
    if (!strcmp(argv[1], "input")) return parse_input(argv[2]);
    fprintf(stderr, "usage: profile_parse ini|input FILE\n");
    return 2;
}
