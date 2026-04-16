#!/usr/bin/env python3
"""
generate_corpus.py
==================

Source of truth for the fuzzing seed corpus. Run:

    python3 .lab/fuzzing/corpus/generate_corpus.py

This rewrites the seed files under .lab/fuzzing/corpus/mqtt/ and
.lab/fuzzing/corpus/cjson/. The output is deterministic — every run
produces byte-identical files, so committing the generated seeds is
safe and regeneration is verifiable via `git status`.

The goal of these seeds is to give libFuzzer / AFL++ a minimal but
**valid** starting point for each fuzzer. Valid seeds save hours of
fuzzing budget that would otherwise be spent discovering packet shape.

MQTT 3.1.1 is used on purpose: its frame layout is smaller and more
constraining than MQTT 5, so a 3.1.1 seed is automatically a subset of
5.0-reachable inputs, while the fuzzer is free to mutate into MQTT 5
property sections.
"""

from __future__ import annotations

import os
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MQTT_DIR = HERE / "mqtt"
CJSON_DIR = HERE / "cjson"


def encode_remaining_length(n: int) -> bytes:
    """Encode an MQTT 'remaining length' variable-byte integer.

    The MQTT spec (3.1.1, section 2.2.3) encodes the remaining length as
    1..4 bytes, 7 bits per byte, MSB set to indicate continuation. This
    helper reproduces the reference encoding exactly — any fuzzer
    mutating the continuation bit reaches the same parser states the
    real broker sees from the wire.
    """
    if n < 0 or n > 268_435_455:
        raise ValueError("remaining length out of range")
    out = bytearray()
    while True:
        byte = n % 128
        n //= 128
        if n > 0:
            byte |= 0x80
            out.append(byte)
        else:
            out.append(byte)
            break
    return bytes(out)


def mqtt_string(s: str) -> bytes:
    """MQTT UTF-8 encoded string: 2-byte big-endian length + bytes."""
    data = s.encode("utf-8")
    return struct.pack(">H", len(data)) + data


def build_connect_minimal() -> bytes:
    """Minimal valid CONNECT packet (MQTT 3.1.1, QoS 0, clean session).

    Fixed header:
        byte 0: 0x10 (CMD_CONNECT, no flags)
        byte 1..:  remaining length (var-int)
    Variable header:
        protocol name: "MQTT" (length-prefixed)
        protocol level: 0x04   (v3.1.1)
        connect flags:  0x02   (clean session only)
        keep alive:     0x003C (60 seconds)
    Payload:
        client id: "fuzz" (length-prefixed)
    """
    variable_header = (
        mqtt_string("MQTT")         # protocol name
        + b"\x04"                    # protocol level = v3.1.1
        + b"\x02"                    # connect flags = clean session
        + struct.pack(">H", 60)      # keep alive
    )
    payload = mqtt_string("fuzz")    # client id
    remaining = variable_header + payload
    return b"\x10" + encode_remaining_length(len(remaining)) + remaining


def build_publish_minimal() -> bytes:
    """Minimal valid PUBLISH packet (MQTT 3.1.1, QoS 0).

    Fixed header:
        byte 0: 0x30 (CMD_PUBLISH, no flags — QoS 0, no DUP, no RETAIN)
        byte 1..: remaining length (var-int)
    Variable header:
        topic name: "t"  (length-prefixed)
        (no packet identifier because QoS = 0)
    Payload:
        message body: "p"
    """
    variable_header = mqtt_string("t")
    payload = b"p"                     # any byte sequence is legal
    remaining = variable_header + payload
    return b"\x30" + encode_remaining_length(len(remaining)) + remaining


def build_subscribe_minimal() -> bytes:
    """Minimal valid SUBSCRIBE packet (MQTT 3.1.1).

    Fixed header:
        byte 0: 0x82 (CMD_SUBSCRIBE | reserved bits 0010b — MUST be 0010)
        byte 1..: remaining length (var-int)
    Variable header:
        packet identifier: 0x0001 (2 bytes, big-endian)
    Payload (one topic filter):
        topic filter: "t" (length-prefixed)
        requested QoS: 0x00
    """
    variable_header = struct.pack(">H", 1)  # packet id = 1
    payload = mqtt_string("t") + b"\x00"
    remaining = variable_header + payload
    return b"\x82" + encode_remaining_length(len(remaining)) + remaining


def write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def write_text(path: Path, data: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Write with UNIX newlines so the file is byte-identical across hosts.
    path.write_bytes(data.encode("utf-8"))


def generate_mqtt_seeds() -> list[tuple[Path, int]]:
    """Emit the three MQTT 3.1.1 seeds. Returns (path, first_byte) tuples
    so the caller can print a verification summary."""
    seeds = [
        (MQTT_DIR / "connect_minimal.bin",   build_connect_minimal(),   0x10),
        (MQTT_DIR / "publish_minimal.bin",   build_publish_minimal(),   0x30),
        (MQTT_DIR / "subscribe_minimal.bin", build_subscribe_minimal(), 0x82),
    ]
    report = []
    for path, data, expected_first in seeds:
        write_bytes(path, data)
        assert data[0] == expected_first, (
            f"{path.name} first byte should be 0x{expected_first:02x}, "
            f"got 0x{data[0]:02x}"
        )
        report.append((path, data[0]))
    return report


def generate_cjson_seeds() -> list[Path]:
    """Emit six JSON seeds exercising different parser shapes."""
    seeds = {
        "empty.json":   "{}",
        "simple.json":  '{"k":"v"}',
        "nested.json":  '{"a":{"b":{"c":1}}}',
        # Deliberately includes non-ASCII characters so the property-string
        # decoding path is exercised when feeding these into the MQTT 5
        # property-string parser via the fuzzer's mutator.
        "unicode.json": '{"name":"café","emoji":"snowman"}',
        # Deep nesting bounded below typical parser stack limits so the seed
        # is a *starting point* rather than a crash input.
        "deep.json":    "{" + "\"x\":{" * 16 + "\"y\":1" + "}" * 16 + "}",
        # Covers the full numeric grammar the property parser understands.
        "numbers.json": '{"int":42,"neg":-7,"exp":1e9,"frac":0.5,"zero":0}',
    }
    written: list[Path] = []
    for name, body in seeds.items():
        path = CJSON_DIR / name
        write_text(path, body)
        written.append(path)
    return written


def main() -> int:
    mqtt_report = generate_mqtt_seeds()
    cjson_report = generate_cjson_seeds()

    print("MQTT seeds:")
    for path, first_byte in mqtt_report:
        rel = path.relative_to(HERE.parent.parent.parent) if path.is_absolute() else path
        print(f"  {rel}  first_byte=0x{first_byte:02x}")

    print("cJSON seeds:")
    for path in cjson_report:
        rel = path.relative_to(HERE.parent.parent.parent) if path.is_absolute() else path
        print(f"  {rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
