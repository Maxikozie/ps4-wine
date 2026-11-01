#!/usr/bin/env python3
"""pe_bases.py: where the PE images of a 32-bit game want to load, and whether they can move.

Reads every .exe/.dll/.asi (any case) under the given directories, or every file that starts with
"MZ" with --all (plugins under other names: Bloodlines' Bin/loader/*.vtm), or the given files: machine,
ImageBase, SizeOfImage, IMAGE_FILE_RELOCS_STRIPPED, a .reloc section, the base-relocation
directory's size, DYNAMIC_BASE. An image is relocatable when its relocations are not stripped and
its relocation directory is not empty. Then the verdict for the PS4 (milestone f measured the
address space below 4 GiB before Wine starts: only the title's eboot, 0x400000-0x650000):
  - fixed images (not relocatable) overlapping the eboot cannot load at all;
  - fixed images overlapping each other cannot both load;
  - relocatable images that want 0x400000 are moved (wow32.exe was, f1).
Prints a Markdown table and the verdict; exit 0 when no fixed image is blocked, 1 otherwise,
2 on a usage error. Python 3 standard library only; reads headers, writes nothing.
"""
from __future__ import annotations

import argparse
import os
import struct
import sys
from pathlib import Path

EBOOT = (0x400000, 0x650000)   # the title's eboot below 4 GiB (milestone f1, LOG.md 2026-11-01 15:59)
MACHINES = {0x14C: "i386", 0x8664: "x86_64"}


def parse(path: Path) -> dict | None:
    """The header fields of one PE image, or None when it is not one."""
    with path.open("rb") as f:
        head = f.read(4096)
        if len(head) < 64 or head[:2] != b"MZ":
            return None
        pe = struct.unpack_from("<I", head, 0x3C)[0]
        if pe + 24 > len(head):
            f.seek(pe)
            head = head[:pe] + f.read(4096)
        if head[pe:pe + 4] != b"PE\0\0":
            return None
        machine, sections, _, _, _, opt_size, characteristics = struct.unpack_from("<HHIIIHH", head, pe + 4)
        opt = pe + 24
        magic = struct.unpack_from("<H", head, opt)[0]
        if magic == 0x10B:      # PE32
            base = struct.unpack_from("<I", head, opt + 28)[0]
            dirs_at = opt + 96
        elif magic == 0x20B:    # PE32+
            base = struct.unpack_from("<Q", head, opt + 24)[0]
            dirs_at = opt + 112
        else:
            return None
        size_of_image = struct.unpack_from("<I", head, opt + 56)[0]
        dll_chars = struct.unpack_from("<H", head, opt + 70)[0]
        count = struct.unpack_from("<I", head, dirs_at - 4)[0]
        reloc_rva, reloc_size = struct.unpack_from("<II", head, dirs_at + 5 * 8) if count > 5 else (0, 0)
        names = []
        table = opt + opt_size
        for i in range(sections):
            raw = head[table + 40 * i:table + 40 * i + 8]
            names.append(raw.rstrip(b"\0").decode("latin-1"))
    stripped = bool(characteristics & 0x1)
    return {
        "machine": MACHINES.get(machine, hex(machine)), "base": base, "end": base + size_of_image,
        "size": size_of_image, "stripped": stripped, "reloc_section": ".reloc" in names,
        "reloc_dir": reloc_size, "dynamic_base": bool(dll_chars & 0x40),
        "relocatable": not stripped and reloc_size > 0,
    }


def overlaps(a: tuple, b: tuple) -> bool:
    return a[0] < b[1] and b[0] < a[1]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument("paths", nargs="+", help="directories (searched recursively) or files")
    ap.add_argument("--root", help="print paths relative to this directory")
    ap.add_argument("--all", action="store_true", help="every file starting with MZ, whatever its name")
    args = ap.parse_args()
    files: list[Path] = []
    for p in map(Path, args.paths):
        if p.is_dir():
            files += sorted(f for f in p.rglob("*") if f.is_file() and
                            (f.suffix.lower() in (".exe", ".dll", ".asi") or (args.all and f.open("rb").read(2) == b"MZ")))
        elif p.is_file():
            files.append(p)
        else:
            ap.error(f"no such file or directory: {p}")
    root = Path(args.root) if args.root else None
    rows = []
    for f in files:
        info = parse(f)
        if info:
            info["path"] = str(f.relative_to(root)) if root and f.is_relative_to(root) else str(f)
            rows.append(info)
    print("| Image | Machine | ImageBase | End | RELOCS_STRIPPED | .reloc | Reloc dir | DYNAMIC_BASE | Relocatable |")
    print("|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        print(f"| `{r['path']}` | {r['machine']} | 0x{r['base']:08x} | 0x{r['end']:08x} | "
              f"{'yes' if r['stripped'] else 'no'} | {'yes' if r['reloc_section'] else 'no'} | {r['reloc_dir']} | "
              f"{'yes' if r['dynamic_base'] else 'no'} | {'yes' if r['relocatable'] else '**no**'} |")
    fixed = [r for r in rows if not r["relocatable"]]
    blocked = [r for r in fixed if overlaps((r["base"], r["end"]), EBOOT)]
    clashes = [(a, b) for i, a in enumerate(fixed) for b in fixed[i + 1:]
               if overlaps((a["base"], a["end"]), (b["base"], b["end"]))]
    moved = [r for r in rows if r["relocatable"] and overlaps((r["base"], r["end"]), EBOOT)]
    print()
    print(f"{len(rows)} images, {len(fixed)} fixed (not relocatable), {len(rows) - len(fixed)} relocatable.")
    print(f"Fixed images overlapping the eboot (0x{EBOOT[0]:x}-0x{EBOOT[1]:x}): "
          + (", ".join(f"`{r['path']}`" for r in blocked) if blocked else "none."))
    print("Fixed images overlapping each other: "
          + ("; ".join(f"`{a['path']}` and `{b['path']}`" for a, b in clashes) if clashes else "none."))
    print("Relocatable images wanting the eboot's range (Wine moves them): "
          + (", ".join(f"`{r['path']}`" for r in moved) if moved else "none."))
    return 1 if blocked or clashes else 0


if __name__ == "__main__":
    sys.exit(main())
