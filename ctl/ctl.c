/* ctl.c: the ctl ELF (docs/ps4/HANDOFF-loop.md, phase 1). Sent to GoldHEN's BinLoader, it closes,
 * installs and launches PSWN00001 with no hands, one command per send. The command is the 4 KiB
 * block of ctl_cmd.h, patched into the file by scripts/ps4/ctl.sh.
 *
 * Every step writes one line
 *     PS4CTL <nonce> step=<name> rc=0x%08x ms=<n> [k=v ...]
 * to netlog (UDP to the host) and appends it, fsync'd, to /data/ps4-wine/ctl/<nonce>.txt; the run
 * ends with "PS4CTL <nonce> done ok= refused= failed=". The hello and done lines also go to klog.
 *
 * It links libkernel (and libSceNet for netlog) only, plus libc.a in the fSELF form. Every other
 * system library is loaded with sceKernelLoadStartModule and its calls found with sceKernelDlsym,
 * so a refused library fails one step and the step says so. The code uses no libc at all, so the
 * same source also links as a plain ELF that imports only libkernel_web.sprx and libSceNet.sprx
 * (CTL_PLAIN, the ps4-payload-sdk import set).
 *
 * The prototypes follow the OpenOrbis headers (include/orbis/{SystemService,SysCore,AppInstUtil,
 * UserService,Bgft,libkernel}.h, v0.5.4) and the export names of its stub libraries; MetaInfo's
 * layout for sceAppInstUtilAppInstallPkg is a documented fact (six string pointers). No code is
 * taken from any other project.
 *
 * Safety, compiled in: a kill needs one proof that the big app is PSWN00001 and none against, and is
 * refused when ctl's own pid is the title's or ctl's own app ID is the big app's; an install takes
 * only a package whose title ID is PSWN00001 and never runs while PSWN00001 does; a launch starts
 * only PSWN00001.
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "ctl_cmd.h"

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

#ifndef CTL_BUILD_ID
#define CTL_BUILD_ID "unknown"
#endif
#ifndef CTL_FORM
#define CTL_FORM "self"
#endif
#ifndef CTL_TITLE_ID
#define CTL_TITLE_ID "PSWN00001"
#endif
#ifndef CTL_CONTENT_ID
#define CTL_CONTENT_ID "IV0000-PSWN00001_00-PS4WINE000000000"
#endif
#ifndef CTL_DATA_ROOT
#define CTL_DATA_ROOT "/data/ps4-wine"
#endif

/* ---- libkernel (OpenOrbis include/orbis/libkernel.h) */
extern int32_t     ctl_k_load_start_module( const char *path, size_t argc, const void *argv, uint32_t flags,
                                            void *opt, int *result ) __asm__("sceKernelLoadStartModule");
extern int32_t     ctl_k_dlsym( int32_t handle, const char *sym, void **addr ) __asm__("sceKernelDlsym");
extern int32_t     ctl_k_usleep( uint32_t us ) __asm__("sceKernelUsleep");
extern uint64_t    ctl_k_process_time(void) __asm__("sceKernelGetProcessTime");
extern int32_t     ctl_k_debug_out( int ch, const char *text ) __asm__("sceKernelDebugOutText");
extern int32_t     ctl_k_open( const char *path, int32_t flags, uint16_t mode ) __asm__("sceKernelOpen");
extern int64_t     ctl_k_write( int32_t fd, const void *buf, size_t len ) __asm__("sceKernelWrite");
extern int32_t     ctl_k_fsync( int32_t fd ) __asm__("sceKernelFsync");
extern int32_t     ctl_k_close( int32_t fd ) __asm__("sceKernelClose");
extern int32_t     ctl_k_mkdir( const char *path, uint16_t mode ) __asm__("sceKernelMkdir");
extern int         ctl_k_getpid(void) __asm__("getpid");
extern int32_t     ctl_k_get_app_info( int pid, void *info ) __asm__("sceKernelGetAppInfo");
extern const char *ctl_k_sandbox_word(void) __asm__("sceKernelGetFsSandboxRandomWord");

/* FreeBSD open flags (the SDK's musl headers carry Linux's). */
#define CTL_O_WRONLY 0x0001
#define CTL_O_APPEND 0x0008
#define CTL_O_CREAT  0x0200

/* ---- probe_netlog.c */
int  probe_netlog_init(void);
void probe_netlog_send( const char *line, size_t len );

/* OrbisAppInfo (OpenOrbis include/orbis/_types/kernel.h): 0x48 bytes. */
struct ctl_app_info
{
    int32_t app_id;
    int32_t unk;
    char    unk0x8[4];
    int32_t app_type;
    char    title_id[10];
    char    unk0x1a[0x2e];
};

/* LncAppParam (OpenOrbis include/orbis/_types/sys_service.h). */
struct ctl_lnc_param
{
    uint32_t size;
    uint32_t user_id;
    uint32_t app_opt;
    uint64_t crash_report;
    uint32_t check_flag; /* LaunchApp_Flag: 2 = SkipSystemUpdate */
};

/* MetaInfo, the second argument of sceAppInstUtilAppInstallPkg. */
struct ctl_meta_info
{
    const char *uri;
    const char *ex_uri;
    const char *playgo_scenario_id;
    const char *content_id;
    const char *content_name;
    const char *icon_url;
};

/* ------------------------------------------------------------------ the command block */
__attribute__((used, aligned(16))) struct ctl_block ctl_cmd = {
    .magic = CTL_MAGIC,
    .version = CTL_VERSION,
    .op = CTL_OP_NONE,
};
static struct ctl_block cmd;

/* ------------------------------------------------------------------ tiny runtime (no libc) */

static int ctl_streq( const char *a, const char *b )
{
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

/* Title IDs are 9 characters without a guaranteed NUL in OrbisAppInfo. */
static int ctl_title_eq( const char *field, size_t cap, const char *want )
{
    size_t i;
    for (i = 0; i < cap && want[i]; i++) if (field[i] != want[i]) return 0;
    return !want[i] && (i == cap || field[i] == 0);
}

static void ctl_copy_title( char *out, const char *field, size_t cap )
{
    size_t i;
    for (i = 0; i < cap && field[i] && i < 15; i++)
        out[i] = (field[i] > ' ' && field[i] < 127) ? field[i] : '?';
    out[i] = 0;
    if (!i) { out[0] = '-'; out[1] = 0; }
}

struct ctl_buf { char *p; size_t cap, n; };

static void buf_c( struct ctl_buf *b, char c ) { if (b->n + 1 < b->cap) b->p[b->n++] = c; }

static void buf_u( struct ctl_buf *b, unsigned long long v, unsigned base, int width, char padc )
{
    char t[24];
    int i = 0;
    do { unsigned d = (unsigned)(v % base); t[i++] = (char)(d < 10 ? '0' + d : 'a' + d - 10); v /= base; } while (v && i < 24);
    while (i < width && i < 24) t[i++] = padc;
    while (i) buf_c( b, t[--i] );
}

/* %s %c %d %u %x %p with an optional 0-padded width and l/ll; enough for the step lines. */
static int ctl_vfmt( char *out, size_t cap, const char *f, va_list ap )
{
    struct ctl_buf b = { out, cap, 0 };
    for (; *f; f++)
    {
        int width = 0, longs = 0;
        char padc = ' ';
        if (*f != '%') { buf_c( &b, *f ); continue; }
        f++;
        if (*f == '0') { padc = '0'; f++; }
        while (*f >= '0' && *f <= '9') width = width * 10 + (*f++ - '0');
        while (*f == 'l') { longs++; f++; }
        switch (*f)
        {
        case 's': { const char *s = va_arg( ap, const char * ); if (!s) s = "(null)"; while (*s) buf_c( &b, *s++ ); break; }
        case 'c': buf_c( &b, (char)va_arg( ap, int ) ); break;
        case 'd':
        {
            long long v = longs ? va_arg( ap, long long ) : va_arg( ap, int );
            if (v < 0) { buf_c( &b, '-' ); buf_u( &b, (unsigned long long)(-(v + 1)) + 1, 10, width, padc ); }
            else buf_u( &b, (unsigned long long)v, 10, width, padc );
            break;
        }
        case 'u': buf_u( &b, longs ? va_arg( ap, unsigned long long ) : va_arg( ap, unsigned ), 10, width, padc ); break;
        case 'x': buf_u( &b, longs ? va_arg( ap, unsigned long long ) : va_arg( ap, unsigned ), 16, width, padc ); break;
        case 'p': buf_c( &b, '0' ); buf_c( &b, 'x' ); buf_u( &b, (uintptr_t)va_arg( ap, void * ), 16, 0, '0' ); break;
        case '%': buf_c( &b, '%' ); break;
        default: buf_c( &b, '%' ); if (*f) buf_c( &b, *f ); else f--; break;
        }
    }
    if (b.cap) b.p[b.n < b.cap ? b.n : b.cap - 1] = 0;
    return (int)b.n;
}

static int ctl_fmt( char *out, size_t cap, const char *f, ... )
{
    va_list ap;
    int n;
    va_start( ap, f );
    n = ctl_vfmt( out, cap, f, ap );
    va_end( ap );
    return n;
}

/* ------------------------------------------------------------------ results */
static int result_fd = -1;
static uint64_t t0_us;
static const char *nonce = "nononce";
static int nonce_valid;
static int n_ok, n_refused, n_failed;

static uint32_t ms_since( uint64_t t ) { return (uint32_t)((ctl_k_process_time() - t) / 1000); }

static void emit( int klog, const char *fmt, ... )
{
    char line[600];
    va_list ap;
    int n = ctl_fmt( line, sizeof(line) - 1, "PS4CTL %s ", nonce );
    va_start( ap, fmt );
    n += ctl_vfmt( line + n, sizeof(line) - 1 - n, fmt, ap );
    va_end( ap );
    if (n > (int)sizeof(line) - 2) n = sizeof(line) - 2;
    line[n++] = '\n';
    line[n] = 0;
    probe_netlog_send( line, (size_t)n );
    if (result_fd >= 0) { ctl_k_write( result_fd, line, (size_t)n ); ctl_k_fsync( result_fd ); }
    if (klog) ctl_k_debug_out( 0, line );
}

enum { R_OK, R_REFUSED, R_FAILED, R_INFO };
static void tally( int r ) { if (r == R_OK) n_ok++; else if (r == R_REFUSED) n_refused++; else if (r == R_FAILED) n_failed++; }

static int valid_app_id( int32_t v ) { return v > 0; }

/* ------------------------------------------------------------------ system libraries */
enum { L_SYS, L_LNC, L_SYSCORE, L_APPINST, L_USER, L_BGFT, L_COUNT };
static const char *const lib_names[L_COUNT] = {
    "libSceSystemService", "libSceLncUtil", "libSceSysCore", "libSceAppInstUtil", "libSceUserService", "libSceBgft",
};
static const char *const lib_dirs[] = { "/system/common/lib/", "/system/priv/lib/" };
static int32_t lib_handle[L_COUNT];

struct ctl_sym { int lib, alt; const char *name; void *addr; };
enum {
    S_LNC_INIT, S_LNC_GET_APP_ID, S_LNC_BIG, S_LNC_KILL, S_LNC_RESULT_KILL, S_LNC_LAUNCH,
    S_SYS_BIG, S_SYS_LAUNCH, S_SYS_KILL,
    S_APP_INIT, S_APP_INFO,
    S_AI_INIT, S_AI_EXISTS, S_AI_TITLE_FROM_PKG, S_AI_INSTALL, S_AI_PREPARE, S_AI_PROGRESS,
    S_US_INIT, S_US_USER,
    S_BGFT_INIT,
    S_COUNT
};
static struct ctl_sym syms[S_COUNT] = {
    [S_LNC_INIT]         = { L_SYS, L_LNC, "sceLncUtilInitialize", 0 },
    [S_LNC_GET_APP_ID]   = { L_SYS, L_LNC, "sceLncUtilGetAppId", 0 },
    [S_LNC_BIG]          = { L_SYS, L_LNC, "sceLncUtilGetAppIdOfBigApp", 0 },
    [S_LNC_KILL]         = { L_SYS, L_LNC, "sceLncUtilKillApp", 0 },
    [S_LNC_RESULT_KILL]  = { L_SYS, L_LNC, "sceLncUtilGetResultKillApp", 0 },
    [S_LNC_LAUNCH]       = { L_SYS, L_LNC, "sceLncUtilLaunchApp", 0 },
    [S_SYS_BIG]          = { L_SYS, -1, "sceSystemServiceGetAppIdOfBigApp", 0 },
    [S_SYS_LAUNCH]       = { L_SYS, -1, "sceSystemServiceLaunchApp", 0 },
    [S_SYS_KILL]         = { L_SYS, -1, "sceSystemServiceKillApp", 0 },
    [S_APP_INIT]         = { L_SYSCORE, -1, "sceApplicationInitialize", 0 },
    [S_APP_INFO]         = { L_SYSCORE, -1, "sceApplicationGetAppInfoByAppId", 0 },
    [S_AI_INIT]          = { L_APPINST, -1, "sceAppInstUtilInitialize", 0 },
    [S_AI_EXISTS]        = { L_APPINST, -1, "sceAppInstUtilAppExists", 0 },
    [S_AI_TITLE_FROM_PKG]= { L_APPINST, -1, "sceAppInstUtilGetTitleIdFromPkg", 0 },
    [S_AI_INSTALL]       = { L_APPINST, -1, "sceAppInstUtilAppInstallPkg", 0 },
    [S_AI_PREPARE]       = { L_APPINST, -1, "sceAppInstUtilAppPrepareOverwritePkg", 0 },
    [S_AI_PROGRESS]      = { L_APPINST, -1, "sceAppInstUtilGetInstallProgressInfo", 0 },
    [S_US_INIT]          = { L_USER, -1, "sceUserServiceInitialize", 0 },
    [S_US_USER]          = { L_USER, -1, "sceUserServiceGetInitialUser", 0 },
    [S_BGFT_INIT]        = { L_BGFT, -1, "sceBgftServiceIntInit", 0 },
};

typedef int32_t (*fn_void)(void);
typedef int32_t (*fn_ptr)(void *);
typedef int32_t (*fn_u32)(uint32_t);
typedef int32_t (*fn_str)(const char *);
typedef int32_t (*fn_str_ptr)(const char *, void *);
typedef int32_t (*fn_app_info)(int32_t, void *);
typedef int32_t (*fn_launch)(const char *, const char **, void *);
typedef int32_t (*fn_sys_kill)(uint32_t, int32_t, int32_t, int32_t);
typedef int32_t (*fn_title_from_pkg)(const char *, char *, int32_t *);
typedef int32_t (*fn_progress)(const char *, uint32_t *, uint32_t *, uint32_t *, uint32_t *, uint32_t *);

#define HAVE(s) (syms[s].addr != 0)
#define CALL(type, s) ((type)syms[s].addr)

static void step_libs(void)
{
    uint64_t t = ctl_k_process_time();
    int loaded = 0, found = 0;
    for (int l = 0; l < L_COUNT; l++)
    {
        int32_t h = -1;
        char path[96];
        const char *where = "-";
        for (size_t d = 0; d < sizeof(lib_dirs) / sizeof(lib_dirs[0]); d++)
        {
            int res = 0;
            ctl_fmt( path, sizeof(path), "%s%s.sprx", lib_dirs[d], lib_names[l] );
            h = ctl_k_load_start_module( path, 0, 0, 0, 0, &res );
            emit( 0, "step=load lib=%s path=%s rc=0x%08x res=%d", lib_names[l], path, (uint32_t)h, res );
            if (h > 0) { where = lib_dirs[d]; break; }
        }
        lib_handle[l] = h > 0 ? h : 0;
        if (h > 0) loaded++;
        (void)where;
    }
    for (int s = 0; s < S_COUNT; s++)
    {
        int32_t rc = -1;
        int lib = syms[s].lib;
        if (lib_handle[lib]) rc = ctl_k_dlsym( lib_handle[lib], syms[s].name, &syms[s].addr );
        if ((rc != 0 || !syms[s].addr) && syms[s].alt >= 0 && lib_handle[syms[s].alt])
        {
            lib = syms[s].alt;
            rc = ctl_k_dlsym( lib_handle[lib], syms[s].name, &syms[s].addr );
        }
        if (rc != 0) syms[s].addr = 0;
        if (syms[s].addr) found++;
        else emit( 0, "step=dlsym sym=%s rc=0x%08x", syms[s].name, (uint32_t)rc );
    }
    emit( 0, "step=libs rc=0x%08x ms=%u loaded=%d/%d syms=%d/%d sys=%x lnc=%x syscore=%x appinst=%x user=%x bgft=%x",
          (uint32_t)(found == S_COUNT ? 0 : -1), ms_since( t ), loaded, L_COUNT, found, S_COUNT,
          (uint32_t)lib_handle[L_SYS], (uint32_t)lib_handle[L_LNC], (uint32_t)lib_handle[L_SYSCORE],
          (uint32_t)lib_handle[L_APPINST], (uint32_t)lib_handle[L_USER], (uint32_t)lib_handle[L_BGFT] );
    tally( R_INFO );
}

/* ------------------------------------------------------------------ steps */
static int32_t self_pid, self_app_id = -1;
static int32_t user_id = -1;

static void step_hello(void)
{
    struct ctl_app_info info;
    char title[16];
    const char *word;
    int32_t rc;
    for (size_t i = 0; i < sizeof(info); i++) ((char *)&info)[i] = 0;
    self_pid = ctl_k_getpid();
    rc = ctl_k_get_app_info( self_pid, &info );
    if (rc == 0) self_app_id = info.app_id;
    ctl_copy_title( title, info.title_id, sizeof(info.title_id) );
    word = ctl_k_sandbox_word();
    emit( 1, "step=hello rc=0x%08x ms=%u form=%s build=%s op=%u flags=%u pid=%d title_pid=%d same_pid=%d "
          "app_info_rc=0x%08x app_id=0x%x app_type=%d app_title=%s sandbox=%s data=%s",
          (uint32_t)rc, ms_since( t0_us ), CTL_FORM, CTL_BUILD_ID, cmd.op, cmd.flags, self_pid, cmd.title_pid,
          cmd.title_pid && cmd.title_pid == self_pid, (uint32_t)rc, (uint32_t)info.app_id, info.app_type, title,
          word && word[0] ? word : "-", result_fd >= 0 ? "ok" : "fail" );
}

static void step_user(void)
{
    uint64_t t = ctl_k_process_time();
    int32_t rc_init = -1, rc = -1;
    if (HAVE(S_US_INIT)) rc_init = CALL(fn_ptr, S_US_INIT)( 0 );
    if (HAVE(S_US_USER)) rc = CALL(fn_ptr, S_US_USER)( &user_id );
    emit( 0, "step=user rc=0x%08x ms=%u init_rc=0x%08x user=%d", (uint32_t)rc, ms_since( t ), (uint32_t)rc_init, user_id );
    tally( R_INFO );
}

struct bigapp
{
    int32_t lnc_big, sys_big, title_app;   /* app IDs, or the error each call returned */
    int32_t info_rc;
    char    big_title[16];
    int     proof_info, proof_lnc, contra_info, contra_lnc;
};

static int32_t title_app_id(void)
{
    return HAVE(S_LNC_GET_APP_ID) ? CALL(fn_str, S_LNC_GET_APP_ID)( CTL_TITLE_ID ) : -1;
}

static int32_t lnc_big_app(void)
{
    return HAVE(S_LNC_BIG) ? CALL(fn_void, S_LNC_BIG)() : -1;
}

static void read_bigapp( struct bigapp *b, int log, const char *label )
{
    uint64_t t = ctl_k_process_time();
    struct ctl_app_info info;
    for (size_t i = 0; i < sizeof(info); i++) ((char *)&info)[i] = 0;
    b->lnc_big = lnc_big_app();
    b->sys_big = HAVE(S_SYS_BIG) ? CALL(fn_void, S_SYS_BIG)() : -1;
    b->title_app = title_app_id();
    b->info_rc = -1;
    if (HAVE(S_APP_INFO) && valid_app_id( b->lnc_big )) b->info_rc = CALL(fn_app_info, S_APP_INFO)( b->lnc_big, &info );
    ctl_copy_title( b->big_title, info.title_id, sizeof(info.title_id) );
    b->proof_info = b->info_rc == 0 && ctl_title_eq( info.title_id, sizeof(info.title_id), CTL_TITLE_ID );
    b->contra_info = b->info_rc == 0 && !b->proof_info;
    b->proof_lnc = valid_app_id( b->title_app ) && b->title_app == b->lnc_big;
    b->contra_lnc = valid_app_id( b->title_app ) && valid_app_id( b->lnc_big ) && b->title_app != b->lnc_big;
    if (log)
        emit( 0, "step=%s rc=0x%08x ms=%u lnc_big=0x%x sys_big=0x%x title_app=0x%x info_rc=0x%08x big_title=%s "
              "proof_info=%d proof_lnc=%d contra_info=%d contra_lnc=%d",
              label, (uint32_t)b->info_rc, ms_since( t ), (uint32_t)b->lnc_big, (uint32_t)b->sys_big,
              (uint32_t)b->title_app, (uint32_t)b->info_rc, b->big_title, b->proof_info, b->proof_lnc,
              b->contra_info, b->contra_lnc );
}

static void step_init_services(void)
{
    uint64_t t = ctl_k_process_time();
    int32_t lnc = -1, app = -1, ai = -1;
    if (HAVE(S_LNC_INIT)) lnc = CALL(fn_void, S_LNC_INIT)();
    if (HAVE(S_APP_INIT)) app = CALL(fn_void, S_APP_INIT)();
    if (HAVE(S_AI_INIT)) ai = CALL(fn_void, S_AI_INIT)();
    emit( 0, "step=init rc=0x%08x ms=%u lnc_init=0x%08x app_init=0x%08x appinst_init=0x%08x",
          (uint32_t)lnc, ms_since( t ), (uint32_t)lnc, (uint32_t)app, (uint32_t)ai );
    tally( R_INFO );
}

static void step_exists(void)
{
    uint64_t t = ctl_k_process_time();
    int32_t exists = -1, rc = -1;
    if (HAVE(S_AI_EXISTS)) rc = CALL(fn_str_ptr, S_AI_EXISTS)( CTL_TITLE_ID, &exists );
    emit( 0, "step=exists rc=0x%08x ms=%u exists=%d", (uint32_t)rc, ms_since( t ), exists );
    tally( R_INFO );
}

/* GetTitleIdFromPkg: 1 when the package is PSWN00001's. */
static int step_pkg_title(void)
{
    uint64_t t = ctl_k_process_time();
    char tid[32];
    int32_t is_app = -1, rc = -1;
    for (size_t i = 0; i < sizeof(tid); i++) tid[i] = 0;
    if (!cmd.pkg[0]) { emit( 0, "step=pkg_title rc=0x%08x ms=0 pkg=-", 0u ); return 0; }
    if (HAVE(S_AI_TITLE_FROM_PKG)) rc = CALL(fn_title_from_pkg, S_AI_TITLE_FROM_PKG)( cmd.pkg, tid, &is_app );
    tid[sizeof(tid) - 1] = 0;
    {
        int match = rc == 0 && ctl_streq( tid, CTL_TITLE_ID );
        char shown[16];
        ctl_copy_title( shown, tid, 12 );
        emit( 0, "step=pkg_title rc=0x%08x ms=%u pkg=%s title=%s is_app=%d match=%d", (uint32_t)rc, ms_since( t ),
              cmd.pkg, shown, is_app, match );
        return match;
    }
}

/* Returns 1 when PSWN00001 is no longer running (killed, or it was not running). */
static int step_kill(void)
{
    uint64_t t = ctl_k_process_time();
    struct bigapp b;
    int32_t rc = -1, rc_sys = -1, rc_result = -1, target;
    int gone = 0, refused = 0;
    const char *why = "-";

    read_bigapp( &b, 1, "bigapp" );
    if (!valid_app_id( b.title_app ) && !b.proof_info)
    {
        emit( 0, "step=kill rc=0x%08x ms=%u result=not_running", 0u, ms_since( t ) );
        tally( R_INFO );
        return 1;
    }
    target = valid_app_id( b.lnc_big ) ? b.lnc_big : b.title_app;
    if (!(b.proof_info || b.proof_lnc)) { refused = 1; why = "no_proof"; }
    else if (b.contra_info || b.contra_lnc) { refused = 1; why = "contra_proof"; }
    else if (cmd.title_pid && cmd.title_pid == self_pid) { refused = 1; why = "same_pid"; }
    else if (valid_app_id( self_app_id ) && self_app_id == target) { refused = 1; why = "same_app"; }
    else if (!HAVE(S_LNC_KILL)) { refused = 1; why = "no_kill_call"; }
    if (refused)
    {
        emit( 0, "step=kill rc=0x%08x ms=%u result=refused why=%s target=0x%x self_app=0x%x", 0xffffffffu,
              ms_since( t ), why, (uint32_t)target, (uint32_t)self_app_id );
        tally( R_REFUSED );
        return 0;
    }
    if (cmd.flags & CTL_FLAG_DRY)
    {
        emit( 0, "step=kill rc=0x%08x ms=%u result=dry target=0x%x", 0u, ms_since( t ), (uint32_t)target );
        tally( R_INFO );
        return 0;
    }
    emit( 0, "step=kill_begin target=0x%x", (uint32_t)target );
    rc = CALL(fn_u32, S_LNC_KILL)( (uint32_t)target );
    if (rc < 0 && HAVE(S_SYS_KILL)) rc_sys = CALL(fn_sys_kill, S_SYS_KILL)( (uint32_t)target, -1, 0, 0 );
    if (HAVE(S_LNC_RESULT_KILL)) rc_result = CALL(fn_u32, S_LNC_RESULT_KILL)( (uint32_t)target );
    for (int i = 0; i < 40 && !gone; i++)
    {
        int32_t now = title_app_id(), big = lnc_big_app();
        if (!valid_app_id( now ) || big != target) gone = 1;
        else ctl_k_usleep( 250000 );
    }
    emit( 0, "step=kill rc=0x%08x ms=%u result=%s target=0x%x lnc_kill=0x%08x sys_kill=0x%08x result_kill=0x%08x "
          "title_app_after=0x%x big_after=0x%x",
          (uint32_t)(gone ? 0 : (rc < 0 ? rc : -1)), ms_since( t ), gone ? "ok" : "fail", (uint32_t)target,
          (uint32_t)rc, (uint32_t)rc_sys, (uint32_t)rc_result, (uint32_t)title_app_id(), (uint32_t)lnc_big_app() );
    tally( gone ? R_OK : R_FAILED );
    return gone;
}

static int install_once( const char *label, int32_t *rc_out )
{
    struct ctl_meta_info meta = { cmd.pkg, "", "", CTL_CONTENT_ID, "ps4-wine", "" };
    uint64_t t = ctl_k_process_time();
    emit( 0, "step=%s_begin pkg=%s", label, cmd.pkg );
    *rc_out = CALL(fn_str_ptr, S_AI_INSTALL)( cmd.pkg, &meta );
    emit( 0, "step=%s rc=0x%08x ms=%u", label, (uint32_t)*rc_out, ms_since( t ) );
    return *rc_out == 0;
}

static int step_install(void)
{
    uint64_t t = ctl_k_process_time();
    int32_t rc1 = -1, rc_prep = -1, rc2 = -1, exists = -1, rc_exists = -1;
    int ok = 0, seen = 0, done = 0;
    uint32_t state = 0, progress = 0, psize = 0, total = 0, rest = 0, last_state = 0, last_progress = 0;
    int32_t last_prc = -1;
    const char *seq = "-";

    if (!step_pkg_title())
    {
        emit( 0, "step=install rc=0x%08x ms=%u result=refused why=pkg_title", 0xffffffffu, ms_since( t ) );
        tally( R_REFUSED );
        return 0;
    }
    if (valid_app_id( title_app_id() ))
    {
        emit( 0, "step=install rc=0x%08x ms=%u result=refused why=title_running", 0xffffffffu, ms_since( t ) );
        tally( R_REFUSED );
        return 0;
    }
    if (!HAVE(S_AI_INSTALL))
    {
        emit( 0, "step=install rc=0x%08x ms=%u result=refused why=no_install_call", 0xffffffffu, ms_since( t ) );
        tally( R_REFUSED );
        return 0;
    }
    if (cmd.flags & CTL_FLAG_DRY)
    {
        emit( 0, "step=install rc=0x%08x ms=%u result=dry", 0u, ms_since( t ) );
        tally( R_INFO );
        return 0;
    }
    if (install_once( "install_direct", &rc1 )) seq = "direct";
    else
    {
        /* Change 3: an installed title may need PrepareOverwritePkg first; all three rcs are logged. */
        if (HAVE(S_AI_PREPARE))
        {
            uint64_t tp = ctl_k_process_time();
            rc_prep = CALL(fn_str, S_AI_PREPARE)( cmd.pkg );
            emit( 0, "step=install_prepare rc=0x%08x ms=%u", (uint32_t)rc_prep, ms_since( tp ) );
        }
        if (install_once( "install_overwrite", &rc2 )) seq = "overwrite";
    }
    if (rc1 == 0 || rc2 == 0)
    {
        /* Poll the install task: <= 300 s, a line every 5 s. */
        for (int i = 0; i < 600 && !done; i++)
        {
            int32_t prc = HAVE(S_AI_PROGRESS)
                ? CALL(fn_progress, S_AI_PROGRESS)( CTL_CONTENT_ID, &state, &progress, &psize, &total, &rest ) : -1;
            if (prc == 0) { seen = 1; last_state = state; last_progress = progress; }
            if (i % 10 == 0 || prc != last_prc)
                emit( 0, "step=install_progress rc=0x%08x ms=%u state=%u progress=%u size=%u total=%u rest_s=%u",
                      (uint32_t)prc, ms_since( t ), state, progress, psize, total, rest );
            last_prc = prc;
            if ((seen && prc != 0) || (prc == 0 && progress >= 100)) done = 1;
            else if (!seen && i >= 20) done = 1; /* no task visible after 10 s: AppExists decides */
            else ctl_k_usleep( 500000 );
        }
        if (HAVE(S_AI_EXISTS)) rc_exists = CALL(fn_str_ptr, S_AI_EXISTS)( CTL_TITLE_ID, &exists );
        ok = done && rc_exists == 0 && exists == 1;
    }
    emit( 0, "step=install rc=0x%08x ms=%u result=%s seq=%s direct=0x%08x prepare=0x%08x overwrite=0x%08x "
          "progress_seen=%d last_state=%u last_progress=%u polled_out=%d exists=%d exists_rc=0x%08x",
          (uint32_t)(ok ? 0 : -1), ms_since( t ), ok ? "ok" : "fail", seq, (uint32_t)rc1, (uint32_t)rc_prep,
          (uint32_t)rc2, seen, last_state, last_progress, !done, exists, (uint32_t)rc_exists );
    tally( ok ? R_OK : R_FAILED );
    return ok;
}

static int step_launch(void)
{
    uint64_t t = ctl_k_process_time();
    struct ctl_lnc_param param = { sizeof(struct ctl_lnc_param), (uint32_t)user_id, 0, 0, 2 };
    const char *argv[CTL_ARGS_MAX + 1];
    int32_t rc = -1, rc_sys = -1, app = -1;
    uint32_t n = cmd.argc > CTL_ARGS_MAX ? CTL_ARGS_MAX : cmd.argc;
    const char *via = "-";
    int ok = 0;

    for (uint32_t i = 0; i < n; i++) argv[i] = cmd.args[i];
    argv[n] = 0;
    if (!HAVE(S_LNC_LAUNCH) && !HAVE(S_SYS_LAUNCH))
    {
        emit( 0, "step=launch rc=0x%08x ms=%u result=refused why=no_launch_call", 0xffffffffu, ms_since( t ) );
        tally( R_REFUSED );
        return 0;
    }
    if (cmd.flags & CTL_FLAG_DRY)
    {
        emit( 0, "step=launch rc=0x%08x ms=%u result=dry argc=%u", 0u, ms_since( t ), n );
        tally( R_INFO );
        return 0;
    }
    emit( 0, "step=launch_begin title=%s argc=%u arg0=%s user=%d", CTL_TITLE_ID, n, n ? argv[0] : "-", user_id );
    if (HAVE(S_LNC_LAUNCH)) { rc = CALL(fn_launch, S_LNC_LAUNCH)( CTL_TITLE_ID, argv, &param ); if (rc >= 0) via = "lnc"; }
    if (rc < 0 && HAVE(S_SYS_LAUNCH))
    {
        rc_sys = CALL(fn_launch, S_SYS_LAUNCH)( CTL_TITLE_ID, argv, &param );
        if (rc_sys >= 0) via = "sys";
    }
    for (int i = 0; i < 60 && (rc >= 0 || rc_sys >= 0); i++)
    {
        app = title_app_id();
        if (valid_app_id( app )) { ok = 1; break; }
        ctl_k_usleep( 250000 );
    }
    emit( 0, "step=launch rc=0x%08x ms=%u result=%s via=%s lnc_launch=0x%08x sys_launch=0x%08x title_app=0x%x",
          (uint32_t)(ok ? 0 : -1), ms_since( t ), ok ? "ok" : "fail", via, (uint32_t)rc, (uint32_t)rc_sys, (uint32_t)app );
    tally( ok ? R_OK : R_FAILED );
    return ok;
}

/* ------------------------------------------------------------------ main */
static int nonce_ok( const char *s )
{
    size_t n = 0;
    for (; n < CTL_NONCE_MAX && s[n]; n++)
    {
        char c = s[n];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-')) return 0;
    }
    return n > 0 && n < CTL_NONCE_MAX;
}

static const char *op_name( uint32_t op )
{
    static const char *const names[] = { "none", "status", "kill", "install", "launch", "cycle", "probe" };
    return op < sizeof(names) / sizeof(names[0]) ? names[op] : "unknown";
}

static int ctl_run(void)
{
    char path[160];
    const volatile unsigned char *src = (const volatile unsigned char *)&ctl_cmd;
    t0_us = ctl_k_process_time();

    /* A volatile copy: the block is rewritten in the file, never by this program. */
    for (size_t i = 0; i < sizeof(cmd); i++) ((unsigned char *)&cmd)[i] = src[i];
    cmd.nonce[CTL_NONCE_MAX - 1] = 0;
    cmd.pkg[CTL_PATH_MAX - 1] = 0;
    for (int i = 0; i < CTL_ARGS_MAX; i++) cmd.args[i][CTL_ARG_LEN - 1] = 0;
    if (nonce_ok( cmd.nonce )) { nonce = cmd.nonce; nonce_valid = 1; }

    probe_netlog_init();
    ctl_k_mkdir( CTL_DATA_ROOT, 0777 );
    ctl_k_mkdir( CTL_DATA_ROOT "/ctl", 0777 );
    ctl_fmt( path, sizeof(path), "%s/ctl/%s.txt", CTL_DATA_ROOT, nonce );
    result_fd = ctl_k_open( path, CTL_O_WRONLY | CTL_O_CREAT | CTL_O_APPEND, 0666 );
    if (result_fd < 0) result_fd = -1;

    step_hello();
    if (cmd.version != CTL_VERSION || (cmd.op != CTL_OP_NONE && !nonce_valid))
    {
        emit( 1, "done ok=0 refused=1 failed=0 op=%s why=bad_block version=%u", op_name( cmd.op ), cmd.version );
        return 0;
    }
    if (cmd.op == CTL_OP_NONE || cmd.op > CTL_OP_PROBE)
    {
        emit( 1, "done ok=0 refused=%d failed=0 op=%s", cmd.op != CTL_OP_NONE, op_name( cmd.op ) );
        return 0;
    }

    step_libs();
    step_init_services();
    step_user();
    {
        struct bigapp b;
        read_bigapp( &b, 1, "bigapp" );
    }
    step_exists();

    switch (cmd.op)
    {
    case CTL_OP_STATUS:
        if (cmd.pkg[0]) step_pkg_title();
        break;
    case CTL_OP_KILL:
        step_kill();
        break;
    case CTL_OP_INSTALL:
        step_install();
        break;
    case CTL_OP_LAUNCH:
        step_launch();
        break;
    case CTL_OP_CYCLE:
    case CTL_OP_PROBE:
        /* Each step needs the one before it: install only once the title is gone, launch only after an install. */
        if (step_kill() && step_install()) step_launch();
        else emit( 0, "step=cycle_stop ok=%d refused=%d failed=%d", n_ok, n_refused, n_failed );
        break;
    }
    emit( 1, "done ok=%d refused=%d failed=%d op=%s ms=%u", n_ok, n_refused, n_failed, op_name( cmd.op ), ms_since( t0_us ) );
    if (result_fd >= 0) ctl_k_close( result_fd );
    return 0;
}

#ifdef CTL_PLAIN
/* The plain ELF's entry: a loader that maps it calls here (its argument, if any, is ignored). */
__attribute__((force_align_arg_pointer, used)) int _start( void *args )
{
    (void)args;
    return ctl_run();
}
#else
/* The fSELF form: OpenOrbis's crt1.o and libc.a call main; returning ends the process (step 8). */
int main( int argc, char **argv )
{
    (void)argc;
    (void)argv;
    return ctl_run();
}
#endif
