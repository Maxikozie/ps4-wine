#!/usr/bin/env bash
# build.sh: host build entry point. Targets are filled in per milestone
# (see docs/ps4/MILESTONES.md); the unimplemented ones print their intended steps.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/build.sh --check-toolchain
       scripts/ps4/build.sh <compat|mesa|probe|probe-test|triangle|wine|title|all>

  --check-toolchain  report every host tool, SDK path and reference checkout the
                     port needs; exit 1 if a required one is missing
  compat             orbis-compat -> build/orbis-compat (+ build/orbis-compat-stage)  (milestone a)
  mesa               mesa-ps4 RADV -> build/mesa-ps4/src/amd/vulkan/libvulkan_radeon.a  (milestone a)
  probe              probes/ -> build/probe/probe.elf + probe_mod.prx -> dist/probe-<id>.pkg
                     (milestone a; the probe is also the hello-world: it prints "PS4WINE a hello")
  probe-test         host unit tests of the probe's pure helpers and of check.sh a
  triangle           Vulkan triangle + capability dump                  (milestone b)
  wine               Wine PE side (host) + Orbis PRX side via the fork  (milestone c)
  title              the ps4-wine title (native/orbis in the fork)      (milestone c)
  all                wine + title
USAGE
}

check_toolchain() {
    local missing=0
    row() { printf '  %-8s %-34s %s\n' "$1" "$2" "$3"; }
    chk_cmd() { # chk_cmd required|optional name [alternative...]
        local kind="$1"; shift; local name="$1"; shift; local found=""
        for c in "$name" "$@"; do have "$c" && { found="$(command -v "$c")"; break; }; done
        if [ -n "$found" ]; then row OK "$name" "$found"
        else row MISSING "$name" "($kind)"; if [ "$kind" = required ]; then missing=1; fi; fi
    }
    chk_path() { # chk_path required|optional label path
        if [ -e "$3" ]; then row OK "$2" "$3"
        else row MISSING "$2" "$3 ($1)"; if [ "$1" = required ]; then missing=1; fi; fi
    }
    echo "Host tools"
    chk_cmd required clang clang-18
    chk_cmd required ld.lld ld.lld-18
    chk_cmd required llvm-symbolizer llvm-symbolizer-18
    chk_cmd required cmake
    chk_cmd required ninja
    chk_cmd required meson
    chk_cmd required python3
    chk_cmd required git
    chk_cmd required curl
    chk_cmd required nc
    chk_cmd required ffmpeg
    chk_cmd required v4l2-ctl
    chk_cmd required x86_64-w64-mingw32-gcc
    chk_cmd required i686-w64-mingw32-gcc
    chk_cmd required bison
    chk_cmd required flex
    chk_cmd required pkg-config
    chk_cmd optional glslangValidator glslang
    chk_cmd optional lftp
    chk_cmd optional shellcheck
    echo "OpenOrbis toolchain (OO_PS4_TOOLCHAIN=$OO_PS4_TOOLCHAIN)"
    chk_path required "toolchain dir" "$OO_PS4_TOOLCHAIN"
    chk_path required "link.x" "$OO_PS4_TOOLCHAIN/link.x"
    chk_path required "lib/crt1.o" "$OO_PS4_TOOLCHAIN/lib/crt1.o"
    chk_path required "lib/crtlib.o (PRX)" "$OO_PS4_TOOLCHAIN/lib/crtlib.o"
    for t in create-fself create-gp4 PkgTool.Core; do
        if p="$(oo_tool "$t")"; then row OK "$t" "$p"; else row MISSING "$t" "bin/linux/$t (required)"; missing=1; fi
    done
    chk_path required "samples right.sprx" "$OO_PS4_TOOLCHAIN/samples/piglet/sce_sys/about/right.sprx"
    chk_path required "samples libc.prx" "$OO_PS4_TOOLCHAIN/samples/piglet/sce_module/libc.prx"
    chk_path required "samples libSceFios2.prx" "$OO_PS4_TOOLCHAIN/samples/piglet/sce_module/libSceFios2.prx"
    echo "Reference checkouts and built inputs"
    chk_path required "orbis-compat" "$ORBIS_COMPAT_DIR"
    chk_path optional "liborbis-compat.a" "$ORBIS_COMPAT_BUILD/liborbis-compat.a"
    chk_path required "orbis-porting-kit" "$ORBIS_KIT_DIR"
    chk_path required "kit orbis.ini.in" "$ORBIS_KIT_DIR/cmake/orbis.ini.in"
    chk_path required "kit orbis-tls.ld" "$ORBIS_KIT_DIR/cmake/orbis-tls.ld"
    chk_path required "mesa-ps4" "$MESA_PS4_DIR"
    chk_path optional "libvulkan_radeon.a" "$MESA_BUILD_DIR/src/amd/vulkan/libvulkan_radeon.a"
    chk_path optional "prospero-win fork (submodule)" "$PROSPERO_WIN_DIR/Makefile"
    chk_path required "prospero-win ref" "$REFS_DIR/prospero-win/Makefile"
    echo "Console reachability"
    if nc -z -w2 "$PS4_HOST" "$PS4_FTP_PORT" 2>/dev/null; then row OK "ftp $PS4_FTP_PORT" "$PS4_HOST"; else row MISSING "ftp $PS4_FTP_PORT" "$PS4_HOST unreachable (optional now)"; fi
    if nc -z -w2 "$PS4_HOST" "$PS4_KLOG_PORT" 2>/dev/null; then row OK "klog $PS4_KLOG_PORT" "$PS4_HOST"; else row MISSING "klog $PS4_KLOG_PORT" "$PS4_HOST unreachable (optional now)"; fi
    if [ "$missing" = 1 ]; then log "toolchain check: required items missing"; return 1; fi
    log "toolchain check: all required items present"
}

# orbis-compat out of tree; refs/orbis-compat stays untouched. The stage directory
# gives consumers the <dir>/include + <dir>/build/liborbis-compat.a layout that
# mesa-ps4's scripts and the kit's cross file hardcode.
build_compat() {
    [ -f "$OO_PS4_TOOLCHAIN/link.x" ] || die "no OpenOrbis toolchain at $OO_PS4_TOOLCHAIN (scripts/ps4/setup-host.sh --install-toolchain)"
    log "orbis-compat: $ORBIS_COMPAT_DIR -> $ORBIS_COMPAT_BUILD"
    "$ORBIS_COMPAT_DIR/build.sh" --out "$ORBIS_COMPAT_BUILD"
    rm -rf "$ORBIS_COMPAT_STAGE"
    mkdir -p "$ORBIS_COMPAT_STAGE"
    ln -s "$ORBIS_COMPAT_DIR/include" "$ORBIS_COMPAT_STAGE/include"
    ln -s "$ORBIS_COMPAT_BUILD" "$ORBIS_COMPAT_STAGE/build"
    [ -f "$ORBIS_COMPAT_STAGE/build/liborbis-compat.a" ] || die "no liborbis-compat.a after the build"
    log "orbis-compat: ok ($ORBIS_COMPAT_STAGE)"
}

# mesa-ps4's RADV + zink/EGL, configured as build-support/orbis/build.sh does but
# without nix (Mesa's host deps come from apt) and out of the reference tree: we
# build a local clone at $MESA_PS4_COMMIT in a separate meson build directory.
# From: orbis-ports/mesa-ps4 build-support/orbis/build.sh @ 1a59cc1 (MIT)
build_mesa() {
    local cross="$BUILD_DIR/mesa-cross" head work_sha build_id cross_sha stamp setup=() blog
    [ -f "$ORBIS_COMPAT_STAGE/build/liborbis-compat.a" ] || die "build orbis-compat first: scripts/ps4/build.sh compat"
    [ -f "$ORBIS_KIT_DIR/cmake/orbis.ini.in" ] || die "no $ORBIS_KIT_DIR/cmake/orbis.ini.in (clone orbis-porting-kit into refs/)"
    need_cmd meson; need_cmd ninja; need_cmd glslangValidator; need_cmd bison; need_cmd flex
    python3 -c 'import mako, yaml, packaging' 2>/dev/null || die "python3 mako/yaml/packaging missing (apt: python3-mako python3-yaml python3-packaging)"

    if [ ! -d "$MESA_SRC_DIR/.git" ]; then
        log "mesa: cloning $MESA_PS4_DIR -> $MESA_SRC_DIR"
        mkdir -p "$(dirname "$MESA_SRC_DIR")"
        git clone --quiet --no-checkout "$MESA_PS4_DIR" "$MESA_SRC_DIR"
    fi
    git -C "$MESA_SRC_DIR" -c advice.detachedHead=false checkout --quiet "$MESA_PS4_COMMIT"
    [ -z "$(git -C "$MESA_SRC_DIR" status --porcelain --untracked-files=no)" ] || die "$MESA_SRC_DIR has local changes"

    log "mesa: cross file -> $cross/orbis.ini"
    rm -rf "$cross"; mkdir -p "$cross/lib/pkgconfig"
    sed -e "s|@OO_PS4_TOOLCHAIN@|$OO_PS4_TOOLCHAIN|g" -e "s|@ORBIS_CROSS@|$cross|g" \
        -e "s|@ORBIS_COMPAT@|$ORBIS_COMPAT_STAGE|g" -e "s|@ORBIS_KIT@|$ORBIS_KIT_DIR|g" \
        -e "s|@ORBIS_CC@|${ORBIS_CC:-clang}|g" -e "s|@ORBIS_CXX@|${ORBIS_CXX:-clang++}|g" \
        -e "s|@ORBIS_AR@|${ORBIS_AR:-llvm-ar}|g" -e "s|@ORBIS_STRIP@|${ORBIS_STRIP:-llvm-strip}|g" \
        "$ORBIS_KIT_DIR/cmake/orbis.ini.in" > "$cross/orbis.ini"
    grep -q -- "-lorbis-compat" "$cross/orbis.ini" || die "generated cross file has no -lorbis-compat"

    # Same build id recipe as upstream: commit + hash of the (empty) working diff.
    head="$(git -C "$MESA_SRC_DIR" rev-parse HEAD)"
    work_sha="$(git -C "$MESA_SRC_DIR" diff --no-ext-diff -U0 HEAD | sha256sum | cut -d' ' -f1)"
    build_id="$(printf '%s-%s' "$head" "$(printf '%s-%s' "$head" "$work_sha" | sha256sum | cut -d' ' -f1)" | sha256sum | cut -c1-40)"

    # A changed cross file must wipe the build dir: meson caches its lookups.
    stamp="$MESA_BUILD_DIR.cross-stamp"
    cross_sha="$(sha256sum "$cross/orbis.ini" | cut -d' ' -f1)"
    if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$cross_sha" ]; then rm -rf "$MESA_BUILD_DIR"; rm -f "$stamp"; fi

    if [ ! -d "$MESA_SRC_DIR/subprojects/zlib-1.3.1" ]; then
        log "mesa: fetching the zlib wrap"
        (cd "$MESA_SRC_DIR" && env -u MESON_PACKAGE_CACHE_DIR meson subprojects download zlib)
    fi
    [ -d "$MESA_BUILD_DIR" ] && setup=(--reconfigure)
    log "mesa: meson setup $MESA_BUILD_DIR"
    (cd "$MESA_SRC_DIR" && env PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR="$cross/lib/pkgconfig" \
        meson setup "$MESA_BUILD_DIR" "${setup[@]}" --cross-file "$cross/orbis.ini" \
        -Ddefault_library=static -Dwrap_mode=nodownload \
        -Dzstd=disabled -Dvalgrind=disabled -Dlmsensors=disabled -Dlibunwind=disabled \
        -Dvulkan-drivers=amd -Dgallium-drivers=zink \
        -Dopengl=true -Dgles1=enabled -Dgles2=enabled \
        -Degl=enabled -Dglx=disabled -Dgbm=disabled -Dglvnd=disabled \
        -Dvideo-codecs= -Dllvm=disabled -Dxmlconfig=disabled -Dbuildtype=release \
        -Dplatforms=orbis -Dzlib=enabled -Dshader-cache=enabled -Dforce_fallback_for=zlib \
        "-Dradv-build-id=$build_id")
    echo "$cross_sha" > "$stamp"
    grep -q 'Checking for function "sysconf" : YES' "$MESA_BUILD_DIR/meson-logs/meson-log.txt" || \
        die "configure did not find sysconf (HAVE_SYSCONF unset -> '#error Unsupported *BSD'); is liborbis-compat.a current?"

    blog="$MESA_BUILD_DIR/build-orbis.log"
    log "mesa: ninja (log $blog)"
    local rc=0
    ninja -C "$MESA_BUILD_DIR" > "$blog" 2>&1 || rc=$?
    if [ "$rc" != 0 ]; then
        grep -E '^FAILED|error:' "$blog" | head -n 20 >&2 || true
        die "mesa build failed (ninja exit $rc); see $blog"
    fi
    [ -f "$MESA_BUILD_DIR/src/amd/vulkan/libvulkan_radeon.a" ] || die "no libvulkan_radeon.a"
    log "mesa: link probe"
    ORBIS_COMPAT_DIR="$ORBIS_COMPAT_STAGE" ORBIS_KIT_DIR="$ORBIS_KIT_DIR" \
        "$MESA_SRC_DIR/build-support/orbis/tools/linkprobe.sh" "$MESA_BUILD_DIR" "$OO_PS4_TOOLCHAIN"
    log "mesa: ok ($(stat -c %s "$MESA_BUILD_DIR/src/amd/vulkan/libvulkan_radeon.a") bytes libvulkan_radeon.a; zlib: $(echo "$MESA_BUILD_DIR"/subprojects/zlib-*/libz.a))"
}

# The flags every Orbis C object is built with (CLAUDE.md "PS4 traps").
orbis_cflags() {
    printf '%s\n' --target=x86_64-pc-freebsd12-elf -fPIC -funwind-tables \
        -isysroot "$OO_PS4_TOOLCHAIN" -isystem "$ORBIS_COMPAT_STAGE/include" -isystem "$OO_PS4_TOOLCHAIN/include" \
        -include orbis_prefix.h -D__ORBIS__ -D_BSD_SOURCE -march=btver2 -femulated-tls \
        -fno-omit-frame-pointer -O2 -Wall -Wextra -Werror
}

# probes/ -> build/probe/probe.elf + assets/probe_mod.prx -> dist/probe-<build_id>.pkg
build_probe() {
    local out="$BUILD_DIR/probe" oo="$OO_PS4_TOOLCHAIN" bid cf=() f bad
    [ -f "$ORBIS_COMPAT_BUILD/liborbis-compat.a" ] || die "build orbis-compat first: scripts/ps4/build.sh compat"
    [ -n "$PS4_NETLOG_HOST" ] || die "cannot work out this host's address towards $PS4_HOST; set PS4_NETLOG_HOST"
    bid="$(build_id)"
    mapfile -t cf < <(orbis_cflags)
    rm -rf "$out"; mkdir -p "$out/obj" "$out/assets"
    log "probe: build $bid, netlog -> $PS4_NETLOG_HOST:$PS4_NETLOG_PORT"
    for f in probe probe_util probe_netlog probe_mod; do
        clang "${cf[@]}" -DPROBE_BUILD_ID="\"$bid\"" -DPROBE_NETLOG_HOST="\"$PS4_NETLOG_HOST\"" \
            -DPROBE_NETLOG_PORT="$PS4_NETLOG_PORT" -c "$REPO_ROOT/probes/$f.c" -o "$out/obj/$f.o"
    done
    # A raw syscall instruction outside libkernel kills the process: none in our objects.
    bad="$(llvm-objdump -d "$out"/obj/*.o | grep -cw syscall || true)"
    [ "$bad" = 0 ] || die "probe objects contain $bad raw syscall instruction(s)"

    # orbis-compat is linked as a plain archive (only the members the probe uses: its boot member
    # would install crash handlers of its own); it is partly C++, hence -lc++.
    ld.lld -m elf_x86_64 -pie --script "$oo/link.x" --eh-frame-hdr \
        "$out/obj/probe.o" "$out/obj/probe_util.o" "$out/obj/probe_netlog.o" \
        -L"$ORBIS_COMPAT_BUILD" -lorbis-compat \
        -L"$oo/lib" -lc -lkernel -lc++ -lSceNet -lSceVideoOut -lSceAudioOut -lSceSystemService -lSceUserService \
        "$oo/lib/crt1.o" -o "$out/probe.elf" --Map="$out/probe.map"

    # The PRX for the dlsym stage: orbis-compat's crtlib.o, because the SDK's turns
    # __init_array_start/end into two empty .bss slots and module_start then runs no constructors;
    # --export-dynamic so the exports are in .dynsym for create-fself.
    ld.lld -m elf_x86_64 -pie --export-dynamic --script "$oo/link.x" --eh-frame-hdr \
        "$out/obj/probe_mod.o" -L"$oo/lib" -lc -lkernel "$ORBIS_COMPAT_BUILD/crt/crtlib.o" \
        -o "$out/probe_mod.elf" 2> >(grep -v 'cannot find entry symbol' >&2)
    [[ "$(llvm-readelf --dyn-syms "$out/probe_mod.elf")" == *" probe_mod_value"* ]] || die "probe_mod.prx does not export probe_mod_value"
    (cd "$out" && "$(oo_tool create-fself)" -in=probe_mod.elf -out=probe_mod.oelf --lib=assets/probe_mod.prx \
        --paid 0x3800000000000011 >/dev/null)
    rm -f "$out/probe_mod.oelf"
    [ -s "$out/assets/probe_mod.prx" ] || die "create-fself produced no probe_mod.prx"
    log "probe: ELF $(stat -c %s "$out/probe.elf") bytes, needs: $(llvm-readelf -d "$out/probe.elf" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' ')"
    "$SCRIPT_DIR/pkg.sh" --elf "$out/probe.elf" --name probe --assets "$out/assets"
}

# Host tests: the probe's pure helpers and check.sh's milestone a rule.
probe_test() {
    local out="$BUILD_DIR/test"
    mkdir -p "$out"
    clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -I"$REPO_ROOT/probes" \
        "$REPO_ROOT/tests/probe_util_test.c" "$REPO_ROOT/probes/probe_util.c" -o "$out/probe_util_test"
    "$out/probe_util_test"
    "$REPO_ROOT/tests/check_a_test.sh"
}

stub() { # stub <target> <milestone> <lines...>
    local target="$1" ms="$2"; shift 2
    log "build $target: not implemented until milestone $ms. Intended steps:"
    printf '  %s\n' "$@" >&2
    exit 2
}

[ $# -ge 1 ] || { usage; exit 1; }
case "$1" in
    -h|--help) usage ;;
    --check-toolchain) check_toolchain ;;
    compat) build_compat ;;
    mesa) build_mesa ;;
    probe) build_probe ;;
    probe-test) probe_test ;;
    triangle) stub triangle b \
        "build.sh mesa (done in milestone a) -> build/mesa-ps4/src/amd/vulkan/libvulkan_radeon.a + subprojects/zlib-*/libz.a" \
        "clang ... probes/triangle.c \$ORBIS_KIT_DIR/vkloader/vkloader.c vkthunks.c" \
        "ld.lld ... --whole-archive libvulkan_radeon.a --no-whole-archive libz.a -lSceGnmDriver -lSceVideoOut ..." ;;
    wine) stub wine c \
        "git submodule update --init third_party/prospero-win   (fork, branch orbis)" \
        "third_party/prospero-win/tools/build_host_wine.sh        # PE modules, winebuild, widl" \
        "third_party/prospero-win/tools/build_wine_orbis.sh       # Unix side + PRXs with OpenOrbis clang + orbis-compat" \
        "third_party/prospero-win/tools/build_wowprospero.sh      # 32-bit CPU (milestone f)" ;;
    title) stub title c \
        "third_party/prospero-win/tools/build_native_orbis.sh     # eboot.elf from native/orbis" \
        "scripts/ps4/pkg.sh --elf <eboot.elf> --assets <staged win/wine runtime>" ;;
    all) stub all c "build.sh wine && build.sh title" ;;
    *) usage; exit 1 ;;
esac
