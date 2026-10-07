"""Read and write PSP EBOOT.PBP files (used to give the PSP build its own title and icon)."""
import struct

NAMES = ["PARAM.SFO", "ICON0.PNG", "ICON1.PMF", "PIC0.PNG", "PIC1.PNG", "SND0.AT3", "DATA.PSP", "DATA.PSAR"]


def unpack(data):
    if data[:4] != b"\0PBP":
        raise ValueError("not a PBP file")
    offsets = list(struct.unpack("<8I", data[8:40])) + [len(data)]
    return {NAMES[i]: data[offsets[i]:offsets[i + 1]] for i in range(8)}


def pack(parts, version=0x100):
    out, offsets, pos = b"", [], 40
    for name in NAMES:
        offsets.append(pos)
        blob = parts.get(name, b"")
        out += blob
        pos += len(blob)
    return b"\0PBP" + struct.pack("<I8I", version, *offsets) + out
