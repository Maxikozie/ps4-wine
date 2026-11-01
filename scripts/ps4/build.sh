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
  compat             orbis-compat + patches/orbis-compat -> build/orbis-compat (+ build/orbis-compat-stage)  (milestone a)
  mesa               mesa-ps4 RADV + patches/mesa-ps4/*.patch -> build/mesa-ps4/src/amd/vulkan/libvulkan_radeon.a
                     (--prx: the copy for libvulkan.prx, with emulated TLS -> build/mesa-ps4-prx; milestone e)
  probe              probes/ -> build/probe/probe.elf + probe_mod.prx -> dist/probe-<id>.pkg
                     (milestone a; the probe is also the hello-world: it prints "PS4WINE a hello")
  probe-test         host unit tests: the probe's and the triangle's pure helpers, check.sh's rules (a-f, p1-p6)
  triangle           probes/triangle.c + RADV + the kit's vkloader -> build/triangle/triangle.elf
                     -> dist/triangle-<id>.pkg (title $TRIANGLE_TITLE_ID; milestone b)
  wine               Wine for the PS4 through the fork (third_party/prospero-win, branch orbis):
                     the host Wine (PE modules, nls, a wine for prefixes and host tests) and the
                     Orbis Unix side (ntdll.prx, wineserver.prx, win32u.prx + report.json)  (milestone c)
                     and libvulkan.prx from build.sh mesa --prx                               (milestone e)
                     and wowprospero (.dll in the host tree, .prx on the Orbis side)          (milestone f)
  title              the ps4-wine title: the fork's native/orbis -> build/title/eboot.elf
                     -> dist/ps4-wine-<id>.pkg (title $TITLE_ID; the runtime is uploaded
                     separately by scripts/ps4/runtime.sh)                               (milestone c)
  all                wine + title
  Options after the target: --jobs N (wine), --skip-host (wine: the Orbis side only), --prx (mesa)
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

# The clone at $ORBIS_COMPAT_COMMIT plus patches/orbis-compat/*.patch, as mesa_patch does for
# mesa-ps4: a stamp of the series and the resulting diff skips an unchanged series. The clone is
# ours (build/src), never refs/.
compat_patch() {
    local stamp="$ORBIS_COMPAT_SRC/.git/ps4wine-patches" want p
    if [ ! -d "$ORBIS_COMPAT_SRC/.git" ]; then
        log "orbis-compat: cloning $ORBIS_COMPAT_DIR -> $ORBIS_COMPAT_SRC"
        mkdir -p "$(dirname "$ORBIS_COMPAT_SRC")"
        git clone --quiet --no-checkout "$ORBIS_COMPAT_DIR" "$ORBIS_COMPAT_SRC"
    fi
    want="$({ echo "$ORBIS_COMPAT_COMMIT"; for p in "$REPO_ROOT"/patches/orbis-compat/*.patch; do [ -f "$p" ] && sha256sum < "$p"; done; } | sha256sum | cut -d' ' -f1)"
    if [ -f "$stamp" ] && [ "$(git -C "$ORBIS_COMPAT_SRC" rev-parse HEAD)" = "$ORBIS_COMPAT_COMMIT" ] && \
       [ "$(sed -n 1p "$stamp")" = "$want" ] && \
       [ "$(sed -n 2p "$stamp")" = "$(git -C "$ORBIS_COMPAT_SRC" diff --no-ext-diff HEAD | sha256sum | cut -d' ' -f1)" ]; then
        log "orbis-compat: $ORBIS_COMPAT_COMMIT with patches/orbis-compat already applied"; return
    fi
    git -C "$ORBIS_COMPAT_SRC" -c advice.detachedHead=false checkout --quiet --force "$ORBIS_COMPAT_COMMIT" ||
        die "$ORBIS_COMPAT_DIR does not have orbis-compat $ORBIS_COMPAT_COMMIT"
    git -C "$ORBIS_COMPAT_SRC" reset --quiet --hard "$ORBIS_COMPAT_COMMIT"
    for p in "$REPO_ROOT"/patches/orbis-compat/*.patch; do
        [ -f "$p" ] || continue
        log "orbis-compat: applying $(basename "$p")"
        git -C "$ORBIS_COMPAT_SRC" apply "$p" || die "$(basename "$p") does not apply to orbis-compat $ORBIS_COMPAT_COMMIT"
    done
    printf '%s\n%s\n' "$want" "$(git -C "$ORBIS_COMPAT_SRC" diff --no-ext-diff HEAD | sha256sum | cut -d' ' -f1)" > "$stamp"
}

# orbis-compat out of tree, from the patched clone; refs/orbis-compat stays untouched. The stage
# directory gives consumers the <dir>/include + <dir>/build/liborbis-compat.a layout that
# mesa-ps4's scripts and the kit's cross file hardcode.
build_compat() {
    [ -f "$OO_PS4_TOOLCHAIN/link.x" ] || die "no OpenOrbis toolchain at $OO_PS4_TOOLCHAIN (scripts/ps4/setup-host.sh --install-toolchain)"
    compat_patch
    log "orbis-compat: $ORBIS_COMPAT_SRC -> $ORBIS_COMPAT_BUILD"
    "$ORBIS_COMPAT_SRC/build.sh" --out "$ORBIS_COMPAT_BUILD"
    rm -rf "$ORBIS_COMPAT_STAGE"
    mkdir -p "$ORBIS_COMPAT_STAGE"
    ln -s "$ORBIS_COMPAT_SRC/include" "$ORBIS_COMPAT_STAGE/include"
    ln -s "$ORBIS_COMPAT_BUILD" "$ORBIS_COMPAT_STAGE/build"
    [ -f "$ORBIS_COMPAT_STAGE/build/liborbis-compat.a" ] || die "no liborbis-compat.a after the build"
    log "orbis-compat: ok ($ORBIS_COMPAT_STAGE)"
}

# The clone at $MESA_PS4_COMMIT plus patches/mesa-ps4/*.patch, in order. A stamp records the patch
# series and the resulting diff; when both still match nothing is touched (ninja then rebuilds
# nothing), otherwise the clone is reset and the series re-applied. The clone is ours (build/), never refs/.
mesa_patch() {
    local stamp="$MESA_SRC_DIR/.git/ps4wine-patches" want p
    want="$({ echo "$MESA_PS4_COMMIT"; for p in "$REPO_ROOT"/patches/mesa-ps4/*.patch; do [ -f "$p" ] && sha256sum < "$p"; done; } | sha256sum | cut -d' ' -f1)"
    if [ -f "$stamp" ] && [ "$(git -C "$MESA_SRC_DIR" rev-parse --short=7 HEAD)" = "${MESA_PS4_COMMIT:0:7}" ] && \
       [ "$(sed -n 1p "$stamp")" = "$want" ] && \
       [ "$(sed -n 2p "$stamp")" = "$(git -C "$MESA_SRC_DIR" diff --no-ext-diff HEAD | sha256sum | cut -d' ' -f1)" ]; then
        log "mesa: $MESA_PS4_COMMIT with patches/mesa-ps4 already applied"; return
    fi
    git -C "$MESA_SRC_DIR" -c advice.detachedHead=false checkout --quiet --force "$MESA_PS4_COMMIT"
    git -C "$MESA_SRC_DIR" reset --quiet --hard "$MESA_PS4_COMMIT"
    for p in "$REPO_ROOT"/patches/mesa-ps4/*.patch; do
        [ -f "$p" ] || continue
        log "mesa: applying $(basename "$p")"
        git -C "$MESA_SRC_DIR" apply "$p" || die "$(basename "$p") does not apply to mesa-ps4 $MESA_PS4_COMMIT"
    done
    printf '%s\n%s\n' "$want" "$(git -C "$MESA_SRC_DIR" diff --no-ext-diff HEAD | sha256sum | cut -d' ' -f1)" > "$stamp"
}

# mesa-ps4's RADV + zink/EGL, configured as build-support/orbis/build.sh does but
# without nix (Mesa's host deps come from apt) and out of the reference tree: we
# build a local clone at $MESA_PS4_COMMIT in a separate meson build directory.
# --prx builds the copy that goes into libvulkan.prx (milestone e): the same source and options plus
# -femulated-tls -march=btver2 -fno-omit-frame-pointer. A -pie PRX gets its TLS relaxed to local-exec
# (offsets into the eboot's block, measured on ntdll.shared.elf), and the SDK's link.x does not collect
# RADV's .tbss.* sections, so RADV's thread-locals must not be native TLS there; the fork's
# wine/orbis/pw_emutls_orbis.c provides __emutls_get_address when the PRX is linked.
# From: orbis-ports/mesa-ps4 build-support/orbis/build.sh @ 1a59cc1 (MIT)
build_mesa() {
    local cross="$BUILD_DIR/mesa-cross" head work_sha build_id cross_sha stamp setup=() blog prx=0 a
    local MESA_BUILD_DIR="$MESA_BUILD_DIR"
    for a in "$@"; do case "$a" in --prx) prx=1 ;; *) die "build mesa: unknown option $a" ;; esac; done
    if [ "$prx" = 1 ]; then cross="$BUILD_DIR/mesa-cross-prx"; MESA_BUILD_DIR="$MESA_PRX_BUILD_DIR"; fi
    [ -f "$ORBIS_COMPAT_STAGE/build/liborbis-compat.a" ] || die "build orbis-compat first: scripts/ps4/build.sh compat"
    [ -f "$ORBIS_KIT_DIR/cmake/orbis.ini.in" ] || die "no $ORBIS_KIT_DIR/cmake/orbis.ini.in (clone orbis-porting-kit into refs/)"
    need_cmd meson; need_cmd ninja; need_cmd glslangValidator; need_cmd bison; need_cmd flex
    python3 -c 'import mako, yaml, packaging' 2>/dev/null || die "python3 mako/yaml/packaging missing (apt: python3-mako python3-yaml python3-packaging)"

    if [ ! -d "$MESA_SRC_DIR/.git" ]; then
        log "mesa: cloning $MESA_PS4_DIR -> $MESA_SRC_DIR"
        mkdir -p "$(dirname "$MESA_SRC_DIR")"
        git clone --quiet --no-checkout "$MESA_PS4_DIR" "$MESA_SRC_DIR"
    fi
    mesa_patch

    log "mesa: cross file -> $cross/orbis.ini"
    rm -rf "$cross"; mkdir -p "$cross/lib/pkgconfig"
    sed -e "s|@OO_PS4_TOOLCHAIN@|$OO_PS4_TOOLCHAIN|g" -e "s|@ORBIS_CROSS@|$cross|g" \
        -e "s|@ORBIS_COMPAT@|$ORBIS_COMPAT_STAGE|g" -e "s|@ORBIS_KIT@|$ORBIS_KIT_DIR|g" \
        -e "s|@ORBIS_CC@|${ORBIS_CC:-clang}|g" -e "s|@ORBIS_CXX@|${ORBIS_CXX:-clang++}|g" \
        -e "s|@ORBIS_AR@|${ORBIS_AR:-llvm-ar}|g" -e "s|@ORBIS_STRIP@|${ORBIS_STRIP:-llvm-strip}|g" \
        "$ORBIS_KIT_DIR/cmake/orbis.ini.in" > "$cross/orbis.ini"
    grep -q -- "-lorbis-compat" "$cross/orbis.ini" || die "generated cross file has no -lorbis-compat"
    if [ "$prx" = 1 ]; then
        sed -i -E "/^(c|cpp)_args/ s/\]\$/,'-femulated-tls','-march=btver2','-fno-omit-frame-pointer']/" "$cross/orbis.ini"
        [ "$(grep -c "^c.*_args .*'-femulated-tls'" "$cross/orbis.ini")" = 2 ] || die "could not add the PRX flags to $cross/orbis.ini"
    fi

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
    if [ "$prx" = 1 ]; then
        # No native TLS may be left, and the emulated variables must be there. mesa's link probe links an
        # executable without an emutls runtime, so it does not apply to this copy.
        local tls
        tls="$(llvm-objdump -h "$MESA_BUILD_DIR/src/amd/vulkan/libvulkan_radeon.a" | grep -cE ' \.t(bss|data)' || true)"
        [ "$tls" = 0 ] || die "mesa --prx: $tls native TLS sections left in libvulkan_radeon.a"
        local emu
        emu="$(llvm-nm "$MESA_BUILD_DIR/src/amd/vulkan/libvulkan_radeon.a" 2>/dev/null | grep -c ' __emutls_v\.' || true)"
        [ "${emu:-0}" -gt 0 ] || die "mesa --prx: no __emutls_v.* symbols; was -femulated-tls applied?"
        log "mesa --prx: ok ($(stat -c %s "$MESA_BUILD_DIR/src/amd/vulkan/libvulkan_radeon.a") bytes, no native TLS, $emu emulated; zlib: $(echo "$MESA_BUILD_DIR"/subprojects/zlib-*/libz.a))"
        return
    fi
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

# Host tests: the probe's and the triangle's pure helpers, check.sh's milestone a and b rules.
probe_test() {
    local out="$BUILD_DIR/test"
    mkdir -p "$out"
    clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -I"$REPO_ROOT/probes" \
        "$REPO_ROOT/tests/probe_util_test.c" "$REPO_ROOT/probes/probe_util.c" -o "$out/probe_util_test"
    "$out/probe_util_test"
    clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -I"$REPO_ROOT/probes" \
        "$REPO_ROOT/tests/triangle_caps_test.c" "$REPO_ROOT/probes/triangle_caps.c" "$REPO_ROOT/probes/probe_util.c" \
        -o "$out/triangle_caps_test"
    "$out/triangle_caps_test"
    "$REPO_ROOT/tests/check_a_test.sh"
    "$REPO_ROOT/tests/check_b_test.sh"
    "$REPO_ROOT/tests/check_c_test.sh"
    "$REPO_ROOT/tests/check_d_test.sh"
    "$REPO_ROOT/tests/check_e_test.sh"
    "$REPO_ROOT/tests/check_f_test.sh"
    "$REPO_ROOT/tests/check_p1_test.sh"
    "$REPO_ROOT/tests/check_p2_test.sh"
    "$REPO_ROOT/tests/check_p3_test.sh"
    "$REPO_ROOT/tests/check_p4_test.sh"
    "$REPO_ROOT/tests/check_p5_test.sh"
    "$REPO_ROOT/tests/check_p5w_test.sh"
    "$REPO_ROOT/tests/check_p6_test.sh"
}

# Milestone b: probes/triangle.c drawing through RADV linked into the title. The link line is the
# orbis-porting-kit's title link (cmake/ps4-openorbis.cmake: orbis-tls.ld, --no-rosegment,
# orbis-compat --whole-archive + its libc16 objects) plus the driver as mesa-ps4's linkprobe.sh
# links it (--whole-archive libvulkan_radeon.a, zlib, SceGnmDriver, SceVideoOut). The kit's
# vkloader supplies the vk* symbols; its thunks are generated from our own objects on every build.
build_triangle() {
    local out="$BUILD_DIR/triangle" oo="$OO_PS4_TOOLCHAIN" bid cf=() f bad radv zlib
    radv="$MESA_BUILD_DIR/src/amd/vulkan/libvulkan_radeon.a"
    [ -f "$radv" ] || die "build mesa first: scripts/ps4/build.sh mesa"
    zlib="$(echo "$MESA_BUILD_DIR"/subprojects/zlib-*/libz.a)"
    [ -f "$zlib" ] || die "no zlib archive under $MESA_BUILD_DIR/subprojects"
    [ -f "$ORBIS_COMPAT_BUILD/liborbis-compat.a" ] || die "build orbis-compat first: scripts/ps4/build.sh compat"
    [ -n "$PS4_NETLOG_HOST" ] || die "cannot work out this host's address towards $PS4_HOST; set PS4_NETLOG_HOST"
    need_cmd glslangValidator
    bid="$(build_id)"
    mapfile -t cf < <(orbis_cflags)
    rm -rf "$out"; mkdir -p "$out/obj" "$out/kit"
    log "triangle: build $bid, netlog -> $PS4_NETLOG_HOST:$PS4_NETLOG_PORT"

    for f in vert frag; do
        glslangValidator -V --quiet "$REPO_ROOT/probes/triangle.$f" --vn "triangle_${f}_spv" -o "$out/triangle_${f}_spv.h" >/dev/null
    done
    for f in triangle triangle_caps probe_util probe_netlog; do
        clang "${cf[@]}" -I"$MESA_SRC_DIR/include" -I"$out" -DPROBE_BUILD_ID="\"$bid\"" \
            -DPROBE_NETLOG_HOST="\"$PS4_NETLOG_HOST\"" -DPROBE_NETLOG_PORT="$PS4_NETLOG_PORT" \
            -c "$REPO_ROOT/probes/$f.c" -o "$out/obj/$f.o"
    done
    bad="$(llvm-objdump -d "$out"/obj/*.o | grep -cw syscall || true)"
    [ "$bad" = 0 ] || die "triangle objects contain $bad raw syscall instruction(s)"

    # The kit's loader: compiled from refs/ as is (its own style, so no -Werror).
    python3 -I "$ORBIS_KIT_DIR/vkloader/gen.py" --objs "$out/obj" \
        --header "$MESA_SRC_DIR/include/vulkan/vulkan_core.h" --out "$out/kit/vkthunks.c" >&2
    for f in "$ORBIS_KIT_DIR/vkloader/vkloader.c" "$out/kit/vkthunks.c"; do
        clang "${cf[@]/-Werror/}" -Wno-unused-parameter -I"$MESA_SRC_DIR/include" -I"$ORBIS_KIT_DIR/vkloader" \
            -c "$f" -o "$out/kit/$(basename "${f%.c}").o"
    done

    clang --target=x86_64-pc-freebsd12-elf --sysroot="$oo" -nostdlib -fuse-ld=lld -pie -Wl,-m,elf_x86_64 \
        -Wl,--script="$ORBIS_KIT_DIR/cmake/orbis-tls.ld" -Wl,--eh-frame-hdr -Wl,--no-rosegment \
        -Wl,--Map="$out/triangle.map" \
        "$out"/obj/*.o "$out"/kit/*.o \
        -Wl,--whole-archive "$ORBIS_COMPAT_BUILD/liborbis-compat.a" -Wl,--no-whole-archive \
        "$ORBIS_COMPAT_BUILD"/libc16/libc16_*.o \
        -Wl,--whole-archive "$radv" -Wl,--no-whole-archive "$zlib" \
        -L"$oo/lib" -lc -lkernel -lc++ -lSceGnmDriver -lSceVideoOut -lSceNet \
        "$oo/lib/crt1.o" -o "$out/triangle.elf"
    log "triangle: ELF $(stat -c %s "$out/triangle.elf") bytes, needs: $(llvm-readelf -d "$out/triangle.elf" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' ')"
    "$SCRIPT_DIR/pkg.sh" --elf "$out/triangle.elf" --name triangle --title-id "$TRIANGLE_TITLE_ID" --title "$TRIANGLE_TITLE_NAME"
}

# The fork's scripts take the toolchain and orbis-compat from the environment.
fork_env() {
    [ -d "$PROSPERO_WIN_DIR/.git" ] || [ -f "$PROSPERO_WIN_DIR/.git" ] ||
        die "no fork at $PROSPERO_WIN_DIR: git submodule update --init third_party/prospero-win"
    [ -f "$ORBIS_COMPAT_BUILD/liborbis-compat.a" ] || die "build orbis-compat first: scripts/ps4/build.sh compat"
    export OO_PS4_TOOLCHAIN ORBIS_COMPAT="$ORBIS_COMPAT_STAGE" LLVM_BIN
}

# Host Wine (the fork's build_wine_runtime.sh + build_host_wine.sh, headless unless the X11 and
# FreeType development packages are installed), then the Orbis Unix side (build_wine_orbis.sh).
build_wine() {
    local jobs="${JOBS:-$(nproc)}" skip_host=0 extra="" a
    for a in "$@"; do case "$a" in --jobs) ;; --skip-host) skip_host=1 ;; [0-9]*) jobs="$a" ;; *) die "build wine: unknown option $a" ;; esac; done
    fork_env
    if [ "$skip_host" = 0 ]; then
        dpkg -s libx11-dev >/dev/null 2>&1 || extra="$extra --without-x"
        dpkg -s libfreetype-dev >/dev/null 2>&1 || extra="$extra --without-freetype"
        # Vulkan needs only the soname (Wine has its own headers): the host Wine then runs the
        # milestone e test programs (vk64.exe, DXVK) on the host's driver, lavapipe in the tests.
        if [ -e /usr/lib/x86_64-linux-gnu/libvulkan.so.1 ]; then extra="$extra ac_cv_lib_soname_vulkan=libvulkan.so.1"
        else log "host wine: no libvulkan.so.1; the milestone e host tests will be skipped"; fi
        [ -z "$extra" ] || log "host wine: headless build (missing packages; setup-host.sh --check-apt):$extra"
        log "wine: host tools tree (Wine 490f6d5, .deps/wine)"
        (cd "$PROSPERO_WIN_DIR" && PROSPERO_WINE_CONFIGURE_EXTRA="${extra# }" tools/build_wine_runtime.sh --jobs "$jobs" > "$BUILD_DIR/wine-runtime.out" 2>&1) ||
            die "build_wine_runtime.sh failed; see $BUILD_DIR/wine-runtime.out"
        log "wine: host Wine with the series (.deps/wine-host)"
        (cd "$PROSPERO_WIN_DIR" && PROSPERO_WINE_CONFIGURE_EXTRA="${extra# }" tools/build_host_wine.sh --jobs "$jobs" > "$BUILD_DIR/wine-host.out" 2>&1) ||
            die "build_host_wine.sh failed; see $BUILD_DIR/wine-host.out"
        tail -n1 "$BUILD_DIR/wine-host.out" >&2
        # wowprospero (milestone f): the WoW64 CPU backend around the IA-32 translator, built into the
        # host tree (wowprospero.dll for the runtime and the prefix; wowprospero.so for host runs).
        log "wine: wowprospero into the host tree (.deps/wine-host/build/dlls/wowprospero)"
        (cd "$PROSPERO_WIN_DIR" && PROSPERO_WINE_BUILD="$PROSPERO_WIN_DIR/.deps/wine-host/build" \
            PROSPERO_WINE_SOURCE="$PROSPERO_WIN_DIR/.deps/wine-host/source" tools/build_wowprospero.sh --jobs "$jobs" \
            > "$BUILD_DIR/wowprospero-host.out" 2>&1) || die "build_wowprospero.sh failed; see $BUILD_DIR/wowprospero-host.out"
    fi
    # wow64native.dll (phase p2): the hardware WoW64 backend's PE side, against the host tree
    # (its Unix side is wow64native.prx, built with the Orbis PRXs below). Cheap: always rebuilt.
    log "wine: wow64native.dll (.deps/wow64native)"
    (cd "$PROSPERO_WIN_DIR" && PATH="/usr/lib/llvm-18/bin:$PATH" sh tools/build_wow64native.sh \
        --source .deps/wine-host/source --build .deps/wine-host/build --output .deps/wow64native \
        > "$BUILD_DIR/wow64native-host.out" 2>&1) || die "build_wow64native.sh failed; see $BUILD_DIR/wow64native-host.out"
    # libvulkan.prx (milestone e) from the -femulated-tls copy of RADV (build.sh mesa --prx).
    local radv="$MESA_PRX_BUILD_DIR/src/amd/vulkan/libvulkan_radeon.a"
    [ -f "$radv" ] || die "no $radv: scripts/ps4/build.sh mesa --prx (libvulkan.prx needs RADV without native TLS)"
    export PROSPERO_RADV_ARCHIVE="$radv" PW_VULKAN_INCLUDE="$MESA_SRC_DIR/include"
    PROSPERO_RADV_ZLIB="$(echo "$MESA_PRX_BUILD_DIR"/subprojects/zlib-*/libz.a)"; export PROSPERO_RADV_ZLIB
    log "wine: Orbis Unix side (.deps/wine-orbis)"
    (cd "$PROSPERO_WIN_DIR" && tools/build_wine_orbis.sh --jobs "$jobs" 2>&1 | tee "$BUILD_DIR/wine-orbis.out" >&2) ||
        die "build_wine_orbis.sh failed; see $BUILD_DIR/wine-orbis.out and .deps/wine-orbis/report.json"
}

# The title: the fork's build_native_orbis.sh -> build/title/eboot.elf -> dist/ps4-wine-<id>.pkg.
build_title() {
    local out="$BUILD_DIR/title" bid elf
    fork_env
    export PW_VULKAN_INCLUDE="$MESA_SRC_DIR/include"   # the milestone e stages call libvulkan.prx
    [ -n "$PS4_NETLOG_HOST" ] || die "cannot work out this host's address towards $PS4_HOST; set PS4_NETLOG_HOST"
    bid="$(build_id "$PROSPERO_WIN_DIR")"
    log "title: fork build $bid, netlog -> $PS4_NETLOG_HOST:$PS4_NETLOG_PORT"
    (cd "$PROSPERO_WIN_DIR" && tools/build_native_orbis.sh --out "$out" --build-id "$bid"         --netlog-host "$PS4_NETLOG_HOST" --netlog-port "$PS4_NETLOG_PORT" --data-root "$PS4_DATA_ROOT" >&2)
    elf="$out/eboot.elf"
    [ -f "$elf" ] || die "no $elf"
    log "title: ELF $(stat -c %s "$elf") bytes, needs: $(llvm-readelf -d "$elf" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' ')"
    # The probe module rides in the package (loaded from the runtime directory on /data too).
    mkdir -p "$out/assets"; cp "$out/pw_probe_mod.prx" "$out/pw_probe_tls.prx" "$out/assets/"
    BUILD_ID_OVERRIDE="$bid" "$SCRIPT_DIR/pkg.sh" --elf "$elf" --name ps4-wine --title-id "$TITLE_ID" --title "$TITLE_NAME"         --content-id "$CONTENT_ID" --assets "$out/assets"
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
    mesa) shift; build_mesa "$@" ;;
    probe) build_probe ;;
    probe-test) probe_test ;;
    triangle) build_triangle ;;
    wine) shift; build_wine "$@" ;;
    title) build_title ;;
    all) build_wine; build_title ;;
    *) usage; exit 1 ;;
esac
