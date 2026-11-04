/* ctl_fake_console.c: the console's side of ctl/ctl.c on the host (tests/ctl_test.sh). ctl.c is
 * compiled for the host unchanged and linked with this file, which defines the libkernel names it
 * imports (the same asm names) and hands it fake LncUtil, SystemService, SysCore, AppInstUtil and
 * UserService calls through sceKernelDlsym. A scenario comes from the environment:
 *
 *   CTLT_OP=status|kill|install|launch|cycle|probe   CTLT_DRY=1
 *   CTLT_RUNNING=1         PSWN00001 is the big app (else another title is)
 *   CTLT_BACKGROUND=1      PSWN00001 runs but another title is the big app
 *   CTLT_PID=N CTLT_TITLE_PID=N   the ctl's pid and the title's pid in the block
 *   CTLT_SELF_APP=1        the ctl's own app ID is the big app's
 *   CTLT_PKG_TITLE=ID      what GetTitleIdFromPkg returns (default PSWN00001)
 *   CTLT_NO_LIB=libSceAppInstUtil  a library that does not load
 *   CTLT_KILL_FAILS=1 (LncUtil's kill fails; 2: SystemService's too) CTLT_DIRECT_FAILS=1 CTLT_LNC_LAUNCH_FAILS=1
 *   CTLT_NONCE=TEXT        the block's nonce (default host-test)
 *
 * Each step line goes to stdout. Copyright (C) 2026 the ps4-wine authors.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#define _GNU_SOURCE
#include "ctl_cmd.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

extern struct ctl_block ctl_cmd;

#define APP_TITLE 0x60000010
#define APP_OTHER 0x60000020
#define E_NOT_FOUND ((int32_t)0x80940005)

static int running, background, self_app, kill_fails, direct_fails, lnc_launch_fails, prepared, progress_calls;
static int fake_pid = 1234;
static const char *pkg_title = "PSWN00001", *no_lib = "";

static int env_int( const char *name, int dflt ) { const char *v = getenv( name ); return v && *v ? atoi( v ) : dflt; }

__attribute__((constructor)) static void setup(void)
{
    static const char *const ops[] = { "none", "status", "kill", "install", "launch", "cycle", "probe" };
    const char *op = getenv( "CTLT_OP" ), *nonce = getenv( "CTLT_NONCE" ), *t;
    running = env_int( "CTLT_RUNNING", 0 );
    background = env_int( "CTLT_BACKGROUND", 0 );
    self_app = env_int( "CTLT_SELF_APP", 0 );
    kill_fails = env_int( "CTLT_KILL_FAILS", 0 );
    direct_fails = env_int( "CTLT_DIRECT_FAILS", 0 );
    lnc_launch_fails = env_int( "CTLT_LNC_LAUNCH_FAILS", 0 );
    fake_pid = env_int( "CTLT_PID", 1234 );
    if ((t = getenv( "CTLT_PKG_TITLE" ))) pkg_title = t;
    if ((t = getenv( "CTLT_NO_LIB" ))) no_lib = t;
    if ((t = getenv( "CTLT_BLOCK_FILE" )) && *t)
    {
        /* The block as ctl.sh patched it into the payload (ELF or fSELF): exactly one magic. */
        static unsigned char data[16 << 20];
        size_t n, found = 0, at = 0;
        FILE *f = fopen( t, "rb" );
        if (!f) { fprintf( stderr, "ctl_fake_console: cannot open %s\n", t ); exit( 1 ); }
        n = fread( data, 1, sizeof(data), f );
        fclose( f );
        /* The magic from ctl_cmd's own initializer: a string literal here would put a second copy in
         * this executable, which tests/ctl_test.sh uses as the payload template. */
        for (size_t i = 0; i + CTL_MAGIC_LEN <= n; i++) if (!memcmp( data + i, ctl_cmd.magic, CTL_MAGIC_LEN )) { if (!found++) at = i; }
        if (found != 1 || at + sizeof(ctl_cmd) > n) { fprintf( stderr, "ctl_fake_console: %zu magics in %s\n", found, t ); exit( 1 ); }
        memcpy( &ctl_cmd, data + at, sizeof(ctl_cmd) );
        return;
    }
    for (uint32_t i = 0; op && i < sizeof(ops) / sizeof(ops[0]); i++) if (!strcmp( op, ops[i] )) ctl_cmd.op = i;
    ctl_cmd.title_pid = env_int( "CTLT_TITLE_PID", 0 );
    ctl_cmd.flags = env_int( "CTLT_DRY", 0 ) ? CTL_FLAG_DRY : 0;
    snprintf( ctl_cmd.nonce, sizeof(ctl_cmd.nonce), "%s", nonce ? nonce : "host-test" );
    snprintf( ctl_cmd.pkg, sizeof(ctl_cmd.pkg), "/data/pkg/ps4-wine-test.pkg" );
    ctl_cmd.argc = 1;
    snprintf( ctl_cmd.args[0], sizeof(ctl_cmd.args[0]), "--ctl-x1" );
}

/* ---- the console's state */
static int32_t big_app(void) { return running && !background ? APP_TITLE : APP_OTHER; }

static int32_t f_lnc_init(void) { return 0; }
static int32_t f_get_app_id( const char *title ) { return !strcmp( title, "PSWN00001" ) && running ? APP_TITLE : E_NOT_FOUND; }
static int32_t f_big(void) { return big_app(); }
static int32_t f_kill( uint32_t app ) { if (kill_fails) return (int32_t)0x80aa0003; if (app == APP_TITLE) running = 0; return 0; }
static int32_t f_result_kill( uint32_t app ) { (void)app; return 0; }
struct lnc_param { uint32_t size, user; uint32_t opt; uint64_t crash; uint32_t flag; };
static int32_t f_lnc_launch( const char *title, const char **argv, void *out )
{
    struct lnc_param *p = out;
    printf( "FAKE lnc_launch title=%s arg0=%s size=%u user=%u flag=%u\n", title, argv[0] ? argv[0] : "-", p->size, p->user, p->flag );
    if (lnc_launch_fails) return (int32_t)0x80940018;
    running = 1; background = 0; return APP_TITLE;
}
static int32_t f_sys_launch( const char *title, const char **argv, void *p )
{
    (void)argv; (void)p;
    printf( "FAKE sys_launch title=%s\n", title );
    running = 1; background = 0; return 0;
}
static int32_t f_sys_kill( uint32_t app, int32_t a, int32_t b, int32_t c )
{
    (void)a; (void)b; (void)c;
    if (kill_fails >= 2) return (int32_t)0x80aa0003;
    if (app == APP_TITLE) running = 0;
    return 0;
}
static int32_t f_app_init(void) { return 0; }
struct app_info { int32_t app_id, unk; char unk8[4]; int32_t type; char title[10]; char rest[0x2e]; };
/* ctl.c calls through its own struct types; these take void * so the call types match (UBSan's
 * -fsanitize=function) and cast inside. */
static int32_t f_app_info( int32_t app, void *out )
{
    struct app_info *info = out;
    memset( info, 0, sizeof(*info) );
    info->app_id = app;
    memcpy( info->title, app == APP_TITLE ? "PSWN00001" : "CUSA00001", 9 );
    return 0;
}
static int32_t f_ai_init(void) { return 0; }
static int32_t f_exists( const char *title, void *exists ) { *(int32_t *)exists = !strcmp( title, "PSWN00001" ); return 0; }
static int32_t f_title_from_pkg( const char *pkg, char *tid, int32_t *is_app ) { (void)pkg; strcpy( tid, pkg_title ); *is_app = 1; return 0; }
struct meta { const char *uri, *ex_uri, *playgo, *content_id, *name, *icon; };
static int32_t f_install( const char *pkg, void *out )
{
    struct meta *m = out;
    printf( "FAKE install pkg=%s uri=%s content=%s\n", pkg, m->uri, m->content_id );
    if (running) return (int32_t)0x80a30009;
    if (direct_fails && !prepared) return (int32_t)0x80990015;
    return 0;
}
static int32_t f_prepare( const char *pkg ) { (void)pkg; prepared = 1; return 0; }
static int32_t f_progress( const char *cid, uint32_t *state, uint32_t *progress, uint32_t *size, uint32_t *total, uint32_t *rest )
{
    (void)cid;
    progress_calls++;
    if (progress_calls > 3) return (int32_t)0x80990002;
    *state = 1; *progress = progress_calls * 30; *size = 0; *total = 100; *rest = 3;
    return 0;
}
static int32_t f_us_init( void *p ) { (void)p; return 0; }
static int32_t f_us_user( void *u ) { *(int32_t *)u = 0x1000; return 0; }
static int32_t f_bgft_init( void *p ) { (void)p; return 0; }

static const struct { const char *name; void *fn; } fakes[] = {
    { "sceLncUtilInitialize", (void *)f_lnc_init }, { "sceLncUtilGetAppId", (void *)f_get_app_id },
    { "sceLncUtilGetAppIdOfBigApp", (void *)f_big }, { "sceLncUtilKillApp", (void *)f_kill },
    { "sceLncUtilGetResultKillApp", (void *)f_result_kill }, { "sceLncUtilLaunchApp", (void *)f_lnc_launch },
    { "sceSystemServiceGetAppIdOfBigApp", (void *)f_big }, { "sceSystemServiceLaunchApp", (void *)f_sys_launch },
    { "sceSystemServiceKillApp", (void *)f_sys_kill }, { "sceApplicationInitialize", (void *)f_app_init },
    { "sceApplicationGetAppInfoByAppId", (void *)f_app_info }, { "sceAppInstUtilInitialize", (void *)f_ai_init },
    { "sceAppInstUtilAppExists", (void *)f_exists }, { "sceAppInstUtilGetTitleIdFromPkg", (void *)f_title_from_pkg },
    { "sceAppInstUtilAppInstallPkg", (void *)f_install }, { "sceAppInstUtilAppPrepareOverwritePkg", (void *)f_prepare },
    { "sceAppInstUtilGetInstallProgressInfo", (void *)f_progress }, { "sceUserServiceInitialize", (void *)f_us_init },
    { "sceUserServiceGetInitialUser", (void *)f_us_user }, { "sceBgftServiceIntInit", (void *)f_bgft_init },
};

/* ---- libkernel */
static const char *const libs[] = { "libSceSystemService", "libSceLncUtil", "libSceSysCore", "libSceAppInstUtil",
                                    "libSceUserService", "libSceBgft" };
static const char *const lib_of[] = { "sceLncUtil", "sceSystemService", "sceApplication", "sceAppInstUtil",
                                      "sceUserService", "sceBgft" };
static const int lib_index_of[] = { 0, 0, 2, 3, 4, 5 };

int32_t sceKernelLoadStartModule( const char *path, size_t argc, const void *argv, uint32_t flags, void *opt, int *res )
{
    (void)argc; (void)argv; (void)flags; (void)opt;
    if (res) *res = 0;
    if (strncmp( path, "/system/common/lib/", 19 )) return (int32_t)0x80020002; /* only common/ in the fake */
    for (int i = 0; i < 6; i++)
    {
        size_t n = strlen( libs[i] );
        if (!strncmp( path + 19, libs[i], n ) && !strcmp( path + 19 + n, ".sprx" ))
            return (*no_lib && !strcmp( no_lib, libs[i] )) || i == 1 ? (int32_t)0x80020002 : 0x10 + i;
    }
    return (int32_t)0x80020002;
}

int32_t sceKernelDlsym( int32_t handle, const char *sym, void **addr )
{
    for (int k = 0; k < 6; k++)
    {
        if (strncmp( sym, lib_of[k], strlen( lib_of[k] ) )) continue;
        if (handle != 0x10 + lib_index_of[k]) return (int32_t)0x80020002;
        for (size_t i = 0; i < sizeof(fakes) / sizeof(fakes[0]); i++)
            if (!strcmp( fakes[i].name, sym )) { *addr = fakes[i].fn; return 0; }
    }
    return (int32_t)0x80020002;
}

int32_t sceKernelUsleep( uint32_t us ) { (void)us; return 0; }
uint64_t sceKernelGetProcessTime(void)
{
    struct timespec ts;
    clock_gettime( CLOCK_MONOTONIC, &ts );
    return (uint64_t)ts.tv_sec * 1000000u + (uint64_t)ts.tv_nsec / 1000u;
}
int32_t sceKernelDebugOutText( int ch, const char *text ) { (void)ch; printf( "KLOG %s", text ); return 0; }
int32_t sceKernelOpen( const char *path, int32_t flags, uint16_t mode ) { (void)path; (void)flags; (void)mode; return (int32_t)0x80020001; }
int64_t sceKernelWrite( int32_t fd, const void *buf, size_t len ) { (void)fd; (void)buf; return (int64_t)len; }
int32_t sceKernelFsync( int32_t fd ) { (void)fd; return 0; }
int32_t sceKernelClose( int32_t fd ) { (void)fd; return 0; }
int32_t sceKernelMkdir( const char *path, uint16_t mode ) { (void)path; (void)mode; return 0; }
int32_t sceKernelGetAppInfo( int pid, struct app_info *info )
{
    (void)pid;
    memset( info, 0, sizeof(*info) );
    info->app_id = self_app ? big_app() : 0x60000099;
    memcpy( info->title, "NPXS20000", 9 );
    return 0;
}
const char *sceKernelGetFsSandboxRandomWord(void) { return "abcdefghij"; }
/* ctl.c imports libkernel's getpid by name; on the host the executable's definition wins. */
int getpid(void) { return fake_pid; }

/* ---- probe_netlog.c's two calls */
int probe_netlog_init(void) { return 0; }
void probe_netlog_send( const char *line, size_t len ) { fwrite( line, 1, len, stdout ); }
