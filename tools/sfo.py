"""Minimal PS Vita param.sfo writer (same layout as VitaSDK's vita-mksfoex)."""
import struct


def make_param_sfo(title, title_id, app_ver="01.00", version="01.00"):
    entries = [  # (key, kind, value, max_len)
        ("APP_VER", "s", app_ver, 8),
        ("ATTRIBUTE", "i", 0x8000, 4),
        ("ATTRIBUTE2", "i", 12, 4),
        ("ATTRIBUTE_MINOR", "i", 16, 4),
        ("CATEGORY", "s", "gd", 4),
        ("CONTENT_ID", "s", "HB0001-%s_00-0000000000000000" % title_id, 48),
        ("GC_RO_SIZE", "i", 0, 4),
        ("GC_RW_SIZE", "i", 0, 4),
        ("PARENTAL_LEVEL", "i", 0, 4),
        ("PSP2_DISP_VER", "s", "00.000", 8),
        ("PSP2_SYSTEM_VER", "i", 0, 4),
        ("REGION_DENY", "i", 0, 4),
        ("SAVEDATA_MAX_SIZE", "i", 1048576, 4),
        ("STITLE", "s", title[:51], 52),
        ("TITLE", "s", title[:127], 128),
        ("TITLE_ID", "s", title_id, 12),
        ("VERSION", "s", version, 8),
    ]
    keys, data, index = b"", b"", b""
    for key, kind, value, max_len in entries:
        if kind == "s":
            raw = value.encode("utf-8") + b"\0"
            fmt, length = 0x0204, len(raw)
            blob = raw.ljust(max_len, b"\0")
        else:
            fmt, length = 0x0404, 4
            blob = struct.pack("<I", value)
        index += struct.pack("<HHIII", len(keys), fmt, length, max_len, len(data))
        keys += key.encode() + b"\0"
        data += blob
    keys = keys.ljust((len(keys) + 3) // 4 * 4, b"\0")
    key_start = 20 + len(index)
    data_start = key_start + len(keys)
    header = struct.pack("<4sIIII", b"\0PSF", 0x101, key_start, data_start, len(entries))
    return header + index + keys + data


def parse_sfo(data):
    """Read any SFO into a list of (key, value) pairs, keeping order. Values are str or int."""
    _, _, key_start, data_start, count = struct.unpack("<4sIIII", data[:20])
    out = []
    for i in range(count):
        ko, fmt, length, max_len, do = struct.unpack("<HHIII", data[20 + i * 16:36 + i * 16])
        key = data[key_start + ko:data.index(b"\0", key_start + ko)].decode()
        raw = data[data_start + do:data_start + do + max_len]
        if fmt == 0x0404:
            out.append((key, struct.unpack("<I", raw[:4])[0], max_len))
        else:
            out.append((key, raw[:length].rstrip(b"\0").decode("utf-8", "replace"), max_len))
    return out


def patch_sfo_string(data, key, value):
    """Change one string value inside an existing SFO without moving anything else."""
    data = bytearray(data)
    _, _, key_start, data_start, count = struct.unpack("<4sIIII", bytes(data[:20]))
    for i in range(count):
        pos = 20 + i * 16
        ko, fmt, length, max_len, do = struct.unpack("<HHIII", bytes(data[pos:pos + 16]))
        name = bytes(data[key_start + ko:data.index(b"\0", key_start + ko)]).decode()
        if name == key:
            raw = value.encode("utf-8")[:max_len - 1] + b"\0"
            data[data_start + do:data_start + do + max_len] = raw.ljust(max_len, b"\0")
            struct.pack_into("<I", data, pos + 4, len(raw))
            return bytes(data)
    raise KeyError(key)
