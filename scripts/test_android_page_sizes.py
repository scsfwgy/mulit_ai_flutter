import struct
import tempfile
import unittest
from pathlib import Path
import zipfile

from check_android_page_sizes import check_archive, elf_issues


def elf(alignment=16384, memory=0x8000, relro_end=None):
    headers = [(1, 6, 0, 0, 0, 512, memory, alignment)]
    if relro_end is not None:
        headers.append((0x6474E552, 4, 0, 0, 0, 0, relro_end, 1))
    data = bytearray(512)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<HH", data, 54, 56, len(headers))
    for i, header in enumerate(headers):
        struct.pack_into("<IIQQQQQQ", data, 64 + i * 56, *header)
    return data


class AndroidPageSizeTests(unittest.TestCase):
    def test_rejects_old_sdk_4k_load_segments(self):
        self.assertTrue(elf_issues(elf(alignment=4096)))

    def test_accepts_16k_and_64k_segments(self):
        for size in [16384, 65536]:
            self.assertEqual(elf_issues(elf(alignment=size)), [])

    def test_rejects_relro_with_writable_data_in_same_page(self):
        self.assertTrue(any('RELRO' in issue for issue in elf_issues(elf(relro_end=0x5000))))

    def test_accepts_aligned_relro_or_relro_occupying_load_remainder(self):
        self.assertEqual(elf_issues(elf(relro_end=0x4000)), [])
        self.assertEqual(elf_issues(elf(memory=0x5000, relro_end=0x5000)), [])

    def test_rejects_malformed_or_truncated_headers(self):
        for value in [b'', b'not an elf', elf()[:70]]:
            self.assertTrue(elf_issues(value))

    def test_checks_both_64bit_abis_and_ignores_32bit(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'app.aab'
            with zipfile.ZipFile(path, 'w') as archive:
                for abi in ['arm64-v8a', 'x86_64', 'armeabi-v7a']:
                    archive.writestr(f'base/lib/{abi}/libtest.so', elf(alignment=4096))
            count, issues = check_archive(path)
            self.assertEqual(count, 2)
            self.assertEqual(len(issues), 2)

    def test_apk_zip_alignment_is_separate_from_elf_alignment(self):
        with tempfile.TemporaryDirectory() as directory:
            for aligned in [False, True]:
                path = Path(directory) / f'app-{aligned}.apk'
                info = zipfile.ZipInfo('lib/arm64-v8a/libtest.so')
                if aligned:
                    padding = (-(30 + len(info.filename.encode()))) % 16384
                    info.extra = struct.pack('<HH', 0xCAFE, padding - 4) + bytes(padding - 4)
                with zipfile.ZipFile(path, 'w') as archive:
                    archive.writestr(info, elf())
                _, issues = check_archive(path)
                self.assertEqual(bool(issues), not aligned)

    def test_no_native_libraries_is_valid_for_wear(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'wear.aab'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('base/dex/classes.dex', b'dex')
            self.assertEqual(check_archive(path), (0, []))


if __name__ == '__main__':
    unittest.main()
