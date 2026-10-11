#!/usr/bin/env python3
"""Read only selected packaged CFStrings in the hash-pinned helper arm64 slice.

This is a narrow reproduction of STATIC-07's pointer-offset observation, not
a general dyld chained-fixups decoder. It never opens a user settings file.
"""
import hashlib
import json
import struct
from pathlib import Path

TARGET = Path('/Applications/SteerMouse.app/Contents/Library/LoginItems/SteerMouse Manager.app/Contents/MacOS/SteerMouse Manager')
EXPECTED = 'b2070391939b6f3f5431cb3fc1c7d89040b5a667ab89917cb653c6f0aca1f30c'
data = TARGET.read_bytes()
if hashlib.sha256(data).hexdigest() != EXPECTED:
    raise SystemExit('Target changed; re-establish identity and pointer layout first.')
magic, count = struct.unpack_from('>II', data)
assert magic == 0xcafebabe
for i in range(count):
    cpu, subtype, offset, size, align = struct.unpack_from('>IIIII', data, 8 + i * 20)
    if cpu == 0x100000c:
        binary = data[offset:offset + size]
        break
else:
    raise SystemExit('No arm64 slice')
assert struct.unpack_from('<I', binary)[0] == 0xfeedfacf
command_count = struct.unpack_from('<I', binary, 16)[0]
position = 32
sections = []
for _ in range(command_count):
    command, length = struct.unpack_from('<II', binary, position)
    if command == 0x19:
        section_count = struct.unpack_from('<I', binary, position + 64)[0]
        for i in range(section_count):
            sec = position + 72 + i * 80
            va, size, file_offset = struct.unpack_from('<QQI', binary, sec + 32)
            sections.append((va, size, file_offset))
    position += length

def map_va(va, length):
    for start, size, offset in sections:
        if start <= va and va + length <= start + size:
            return offset + va - start
    raise ValueError(f'Unmapped VA {va:#x}')

addresses = [0x100085a08, 0x100085ae8, 0x100085b08, 0x100085ba8,
             0x100085bc8, 0x100085be8, 0x100085f48, 0x100087928,
             0x100087948, 0x100087988, 0x100088128, 0x10008a368,
             0x10008a0e8, 0x10008a108, 0x10008a128, 0x10008a148,
             0x10008a168, 0x100085508, 0x10008a1e8, 0x10008a208,
             0x10008a228, 0x10008a248]
records = []
for va in addresses:
    record = map_va(va, 32)
    pointer, length = struct.unpack_from('<QQ', binary, record + 16)
    string_va = 0x100000000 + (pointer & 0xffffffff)
    location = map_va(string_va, length)
    assert 0 <= length <= 256
    text = binary[location:location + length].decode('utf-8')
    records.append({'record_va': hex(va), 'string_va': hex(string_va), 'text': text})
print(json.dumps({'target_sha256': EXPECTED, 'slice': 'arm64', 'records': records}, indent=2))
