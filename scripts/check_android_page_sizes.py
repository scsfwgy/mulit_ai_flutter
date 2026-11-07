#!/usr/bin/env python3
"""Check 64-bit ELF/RELRO alignment in APK/AAB and stored APK library ZIP alignment.

See https://developer.android.com/guide/practices/page-sizes.
AAB-generated APK alignment also depends on BundleConfig (AGP >= 8.5.1).
"""
import argparse
from pathlib import Path
import struct
import zipfile

PAGE_SIZE = 16384
ABIS = {"arm64-v8a", "x86_64"}


def elf_issues(data):
    if len(data) < 64 or data[:5] != b"\x7fELF\x02" or data[5] not in (1, 2):
        return ["invalid 64-bit ELF header"]
    endian = "<" if data[5] == 1 else ">"
    offset = struct.unpack_from(endian + "Q", data, 32)[0]
    size, count = struct.unpack_from(endian + "HH", data, 54)
    if size < 56 or offset + size * count > len(data):
        return ["invalid ELF program headers"]
    headers = [struct.unpack_from(endian + "IIQQQQQQ", data, offset + i * size)
               for i in range(count)]
    loads = [h for h in headers if h[0] == 1]
    if not loads:
        return ["missing ELF LOAD segments"]
    issues = []
    for h in loads:
        if h[7] < PAGE_SIZE or h[2] % PAGE_SIZE != h[3] % PAGE_SIZE:
            issues.append(f"LOAD alignment {h[7]} / incompatible file offset")
    for h in headers:
        if h[0] != 0x6474E552 or not h[6]:
            continue
        end = h[3] + h[6]
        if end % PAGE_SIZE and any(
            load[1] & 2 and load[3] <= h[3] and end < load[3] + load[6]
            for load in loads
        ):
            issues.append("RELRO ends inside a 16 KB page containing writable data")
    return issues


def check_archive(path):
    issues = []
    count = 0
    with zipfile.ZipFile(path) as archive, path.open("rb") as raw:
        for info in archive.infolist():
            name = Path(info.filename)
            if name.suffix != ".so" or name.parent.name not in ABIS:
                continue
            count += 1
            issues.extend(f"{info.filename}: {issue}" for issue in elf_issues(archive.read(info)))
            if path.suffix.lower() == ".apk" and info.compress_type == zipfile.ZIP_STORED:
                raw.seek(info.header_offset)
                header = raw.read(30)
                if len(header) != 30 or header[:4] != b"PK\x03\x04":
                    issues.append(f"{info.filename}: invalid ZIP local header")
                    continue
                name_size, extra_size = struct.unpack_from("<HH", header, 26)
                start = info.header_offset + 30 + name_size + extra_size
                if start % PAGE_SIZE:
                    issues.append(f"{info.filename}: APK ZIP offset {start} is not 16 KB aligned")
    return count, issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archives", type=Path, nargs="+")
    args = parser.parse_args()
    failed = False
    for path in args.archives:
        try:
            count, issues = check_archive(path)
        except (OSError, zipfile.BadZipFile, RuntimeError) as error:
            count, issues = 0, [str(error)]
        print(f"{path}: {'FAIL' if issues else 'PASS'} — {count} 64-bit native libraries")
        for issue in issues:
            print(f"  {issue}")
        failed |= bool(issues)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
