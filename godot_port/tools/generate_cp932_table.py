#!/usr/bin/env python3
"""Generate the compact Windows-31J/CP932 double-byte map used by GDScript."""

from pathlib import Path
import argparse


PROJECT_DIR = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT_DIR / "assets" / "codepages" / "cp932.tbl"
LEADS = [*range(0x81, 0xA0), *range(0xE0, 0xFD)]
TRAILS = [*range(0x40, 0x7F), *range(0x80, 0xFD)]


def generate_table() -> bytes:
    table = bytearray()
    for lead in LEADS:
        for trail in TRAILS:
            try:
                decoded = bytes((lead, trail)).decode("cp932")
            except UnicodeDecodeError:
                codepoint = 0
            else:
                if len(decoded) != 1 or ord(decoded) > 0xFFFF:
                    raise ValueError(f"unexpected CP932 mapping: {lead:#x} {trail:#x}")
                codepoint = ord(decoded)
            table.extend(codepoint.to_bytes(2, "little"))
    if len(table) != 60 * 188 * 2:
        raise AssertionError(f"unexpected table length: {len(table)}")
    return bytes(table)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the checked-in table without modifying it")
    args = parser.parse_args()
    table = generate_table()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_bytes() != table:
            raise SystemExit(f"CP932 table is missing or stale: {OUTPUT}")
        print(f"Verified {len(table)} bytes at {OUTPUT}")
        return
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(table)
    print(f"Wrote {len(table)} bytes to {OUTPUT}")


if __name__ == "__main__":
    main()
