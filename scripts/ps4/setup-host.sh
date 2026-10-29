#!/usr/bin/env bash
# setup-host.sh: report the apt packages the port needs and install the pinned
# OpenOrbis toolchain (v0.5.4, asset toolchain-llvm-18.tar.gz) under
# $OO_PS4_TOOLCHAIN. Never runs sudo: missing packages are printed as one
# apt line for the user.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

OO_TAG=v0.5.4
OO_ASSET=toolchain-llvm-18.tar.gz
# sha256 of the asset as downloaded on 2026-10-29; ps4-mesa-docs
# (HANDOFF-toolchain-macos-20260917.md) records the same hash.
OO_SHA256=3c7cd5bb593ca74fa1c13fd59f3938dc0fc07985167f7275063019e63abe4526
# PkgTool.Core is a .NET Core 3.0 single-file app: pkg_build needs OpenSSL 1.0/1.1 ("No usable
# version of libssl was found"), which Ubuntu 26.04 no longer ships, and the runtime's shim cannot
# use OpenSSL 3 ("Cannot get required symbol ERR_put_error"). A private 1.1.1w, used only by
# PkgTool through LD_LIBRARY_PATH (common.sh pkgtool()), is built from source. sha256 as published
# by openssl.org and on the GitHub release (both checked 2026-10-29).
OPENSSL11_VER=1.1.1w
OPENSSL11_SHA256=cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
APT_PKGS=(clang-18 lld-18 llvm-18 cmake ninja-build meson bison flex pkg-config
          mingw-w64 glslang-tools python3-mako python3-yaml python3-packaging
          lftp shellcheck ffmpeg v4l-utils curl netcat-openbsd git gh)

usage() {
    cat <<USAGE
usage: scripts/ps4/setup-host.sh [--check-apt] [--install-toolchain [--force]] [--install-openssl11]

  --check-apt          list the apt packages that are not installed and print the
                       sudo apt install line for them (default when no option is given)
  --install-toolchain  download OpenOrbis $OO_TAG $OO_ASSET with gh into
                       build/downloads/openorbis-$OO_TAG/, verify sha256, extract into
                       \$OO_PS4_TOOLCHAIN ($OO_PS4_TOOLCHAIN) and smoke-test its tools
  --force              replace an existing \$OO_PS4_TOOLCHAIN
  --install-openssl11  build OpenSSL $OPENSSL11_VER (shared libs only) into \$OPENSSL11_PREFIX
                       ($OPENSSL11_PREFIX) for PkgTool.Core's pkg_build
USAGE
}

check_apt() {
    local missing=() p
    for p in "${APT_PKGS[@]}"; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
    done
    if [ "${#missing[@]}" -eq 0 ]; then log "apt: all ${#APT_PKGS[@]} packages installed"; return 0; fi
    log "apt: missing ${#missing[@]} package(s); run:"
    printf '  sudo apt install %s\n' "${missing[*]}"
    return 1
}

install_toolchain() {
    local force="$1" dl="$BUILD_DIR/downloads/openorbis-$OO_TAG" tmp sum
    if [ -e "$OO_PS4_TOOLCHAIN/link.x" ] && [ "$force" = 0 ]; then
        log "toolchain already at $OO_PS4_TOOLCHAIN (use --force to replace)"
    else
        need_cmd gh; need_cmd sha256sum; need_cmd tar
        mkdir -p "$dl"
        if [ ! -f "$dl/$OO_ASSET" ]; then
            log "downloading OpenOrbis $OO_TAG $OO_ASSET"
            gh release download "$OO_TAG" -R OpenOrbis/OpenOrbis-PS4-Toolchain -p "$OO_ASSET" -D "$dl"
        fi
        sum="$(sha256sum "$dl/$OO_ASSET" | cut -d' ' -f1)"
        [ "$sum" = "$OO_SHA256" ] || die "sha256 mismatch for $OO_ASSET: got $sum, pinned $OO_SHA256"
        printf '%s  %s\n' "$sum" "$OO_ASSET" > "$dl/SHA256SUMS"
        tmp="$(mktemp -d "$BUILD_DIR/downloads/oo-extract.XXXXXX")"
        tar -xzf "$dl/$OO_ASSET" -C "$tmp"
        [ -f "$tmp/OpenOrbis/PS4Toolchain/link.x" ] || die "unexpected layout in $OO_ASSET (no OpenOrbis/PS4Toolchain/link.x)"
        rm -rf "$OO_PS4_TOOLCHAIN"
        mkdir -p "$(dirname "$OO_PS4_TOOLCHAIN")"
        mv "$tmp/OpenOrbis/PS4Toolchain" "$OO_PS4_TOOLCHAIN"
        rm -rf "$tmp"
        log "installed OpenOrbis $OO_TAG into $OO_PS4_TOOLCHAIN"
    fi
    smoke_toolchain
}

install_openssl11() {
    local dl="$BUILD_DIR/downloads/openssl-$OPENSSL11_VER" tgz sum src
    tgz="openssl-$OPENSSL11_VER.tar.gz"
    if [ -e "$OPENSSL11_PREFIX/lib/libssl.so.1.1" ]; then log "OpenSSL $OPENSSL11_VER already at $OPENSSL11_PREFIX"; return 0; fi
    mkdir -p "$dl"
    [ -f "$dl/$tgz" ] || curl -sSfL -o "$dl/$tgz" \
        "https://github.com/openssl/openssl/releases/download/OpenSSL_${OPENSSL11_VER//./_}/$tgz"
    sum="$(sha256sum "$dl/$tgz" | cut -d' ' -f1)"
    [ "$sum" = "$OPENSSL11_SHA256" ] || die "sha256 mismatch for $tgz: got $sum, pinned $OPENSSL11_SHA256"
    src="$(mktemp -d "$BUILD_DIR/downloads/openssl-src.XXXXXX")"
    tar -xzf "$dl/$tgz" -C "$src"
    log "building OpenSSL $OPENSSL11_VER into $OPENSSL11_PREFIX"
    ( cd "$src/openssl-$OPENSSL11_VER" &&
      ./config shared no-tests --prefix="$OPENSSL11_PREFIX" --openssldir="$OPENSSL11_PREFIX/ssl" >/dev/null &&
      make -j"$(nproc)" >/dev/null 2>&1 && make install_sw >/dev/null )
    rm -rf "$src"
    [ -e "$OPENSSL11_PREFIX/lib/libssl.so.1.1" ] || die "OpenSSL build produced no libssl.so.1.1"
    log "OpenSSL $OPENSSL11_VER installed"
}

smoke_toolchain() {
    local t p ok=1
    for f in link.x lib/crt1.o lib/crtlib.o lib/libc.a lib/libkernel.so include/orbis/libkernel.h; do
        [ -e "$OO_PS4_TOOLCHAIN/$f" ] || { log "missing $OO_PS4_TOOLCHAIN/$f"; ok=0; }
    done
    for t in create-fself create-gp4 PkgTool.Core; do
        p="$(oo_tool "$t")" || { log "missing tool $t"; ok=0; }
    done
    p="$(oo_tool PkgTool.Core || true)"
    if [ -n "$p" ]; then
        local sfo; sfo="$(mktemp "$BUILD_DIR/downloads/smoke.XXXXXX.sfo")"
        if "$p" sfo_new "$sfo" >/dev/null 2>&1; then log "PkgTool.Core sfo_new: ok"
        else log "PkgTool.Core sfo_new failed (DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=$DOTNET_SYSTEM_GLOBALIZATION_INVARIANT)"; ok=0; fi
        rm -f "$sfo"
    fi
    [ "$ok" = 1 ] || die "toolchain smoke test failed"
    log "toolchain smoke test: ok"
}

CHECK_APT=0; INSTALL=0; FORCE=0; OPENSSL=0
[ $# -gt 0 ] || CHECK_APT=1
while [ $# -gt 0 ]; do
    case "$1" in
        --check-apt) CHECK_APT=1; shift ;;
        --install-toolchain) INSTALL=1; shift ;;
        --force) FORCE=1; shift ;;
        --install-openssl11) OPENSSL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
rc=0
if [ "$CHECK_APT" = 1 ]; then check_apt || rc=1; fi
if [ "$OPENSSL" = 1 ]; then install_openssl11; fi
if [ "$INSTALL" = 1 ]; then mkdir -p "$BUILD_DIR/downloads"; install_toolchain "$FORCE"; fi
exit "$rc"
