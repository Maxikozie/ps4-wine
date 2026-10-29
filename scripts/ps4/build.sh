#!/usr/bin/env bash
# build.sh: host build entry point. Only --check-toolchain does real work today;
# the build targets are filled in per milestone (see docs/ps4/MILESTONES.md).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<USAGE
usage: scripts/ps4/build.sh --check-toolchain
       scripts/ps4/build.sh <probe|hello|triangle|wine|title|all> [--release]

  --check-toolchain  report every host tool, SDK path and reference checkout the
                     port needs; exit 1 if a required one is missing
  probe              probes/probe.c -> build/probe/probe.elf            (milestone a)
  hello              the hello-world title with klog + netlog           (milestone a)
  triangle           Vulkan triangle + capability dump                  (milestone b)
  wine               Wine PE side (host) + Orbis PRX side via the fork  (milestone c)
  title              the ps4-wine title (native/orbis in the fork)      (milestone c)
  all                wine + title
USAGE
}

check_toolchain() {
    local missing=0 req opt
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
    chk_cmd optional dotnet
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
    chk_path optional "liborbis-compat.a" "$ORBIS_COMPAT_DIR/build/liborbis-compat.a"
    chk_path required "orbis-porting-kit" "$ORBIS_KIT_DIR"
    chk_path optional "orbsdk" "$REFS_DIR/orbsdk"
    chk_path required "mesa-ps4" "$MESA_PS4_DIR"
    chk_path optional "libvulkan_radeon.a" "$MESA_PS4_DIR/build-orbis/src/amd/vulkan/libvulkan_radeon.a"
    chk_path optional "prospero-win fork (submodule)" "$PROSPERO_WIN_DIR/Makefile"
    chk_path required "prospero-win ref" "$REFS_DIR/prospero-win/Makefile"
    echo "Console reachability"
    if nc -z -w2 "$PS4_HOST" "$PS4_FTP_PORT" 2>/dev/null; then row OK "ftp $PS4_FTP_PORT" "$PS4_HOST"; else row MISSING "ftp $PS4_FTP_PORT" "$PS4_HOST unreachable (optional now)"; fi
    if nc -z -w2 "$PS4_HOST" "$PS4_KLOG_PORT" 2>/dev/null; then row OK "klog $PS4_KLOG_PORT" "$PS4_HOST"; else row MISSING "klog $PS4_KLOG_PORT" "$PS4_HOST unreachable (optional now)"; fi
    if [ "$missing" = 1 ]; then log "toolchain check: required items missing"; return 1; fi
    log "toolchain check: all required items present"
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
    probe) stub probe a \
        "clang --target=x86_64-pc-freebsd12-elf -fPIC -funwind-tables -isysroot \$OO_PS4_TOOLCHAIN -isystem \$ORBIS_COMPAT_DIR/include -include orbis_prefix.h -D__ORBIS__ -D_BSD_SOURCE -march=btver2 -femulated-tls -fno-omit-frame-pointer -c probes/probe.c" \
        "ld.lld -m elf_x86_64 -pie --script \$ORBIS_KIT_DIR/cmake/orbis-tls.ld --eh-frame-hdr -L\$OO_PS4_TOOLCHAIN/lib --whole-archive \$ORBIS_COMPAT_DIR/build/liborbis-compat.a --no-whole-archive -lc -lkernel -lSceNet -lSceVideoOut -lScePad -lSceAudioOut -lSceUserService -lSceSystemService \$OO_PS4_TOOLCHAIN/lib/crt1.o -o build/probe/probe.elf" \
        "cp build/probe/probe.elf build/elf/probe-\$(build_id).elf   # keep for llvm-symbolizer" \
        "scripts/ps4/pkg.sh --elf build/probe/probe.elf --name probe" ;;
    hello) stub hello a "same as probe with native/orbis/hello_main.c (klog + netlog + idle loop)" ;;
    triangle) stub triangle b \
        "mesa-ps4: ps4/build.sh (cross file from \$ORBIS_KIT_DIR/cmake/orbis.ini.in) -> build-orbis/src/amd/vulkan/libvulkan_radeon.a" \
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
