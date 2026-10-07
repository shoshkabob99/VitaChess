#!/usr/bin/env python3
"""Build Vita Chess.

    python tools/build.py           build the Vita VPK  (dist/VitaChess-<version>.vpk, dist/index.lua)
    python tools/build.py --psp     also build the PSP test version (dist/VitaChess-PSP-<version>.zip)
    python tools/build.py --desktop also build the desktop preview (dist/VitaChess-desktop-<version>.love)
    python tools/build.py --deploy 192.168.1.50
                                    send index.lua to the Vita over Wi-Fi (VitaShell's FTP server,
                                    or the vitacompanion plugin) and restart the game if possible
    python tools/build.py --test    also run the tests (needs LuaJIT on your PATH)

Vita steps:
  1. Bundle every module in src/ into one index.lua (Lua Player Plus Vita
     runs a single file, so the modules are packed into it).
  2. Copy assets (pieces, sounds, fonts, puzzles, LiveArea art) next to it.
  3. Write param.sfo (title, title ID, version).
  4. Add the Lua Player Plus Vita eboot (downloaded once and cached).
  5. Zip everything into a .vpk.

PSP steps: the same bundle as script.lua, with platform_psp.lua as the
platform layer, plus the LuaDEV R0 EBOOT.PBP retitled with our own icon.

Only the Python standard library is needed.
"""
import os
import re
import ftplib
import shutil
import socket
import subprocess
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from sfo import make_param_sfo, patch_sfo_string  # noqa: E402
import pbp  # noqa: E402

TITLE = "Vita Chess"
TITLE_ID = "SNCH00001"
# Load order: each module may only require modules listed before it.
MODULES = ["platform", "config", "chess", "ai", "book", "pgn", "settings", "puzzles", "lessons", "learn", "stats", "trophies", "ui", "app"]
EBOOT_URL = "https://github.com/Rinnegatamante/lpp-vita/releases/download/Nightly/eboot_safe.bin"
PSP_EBOOT_URL = "https://github.com/jcnmsg/LuaDEV-R0-PSP/raw/main/EBOOT.PBP"
PSP_TITLE = "Vita Chess (PSP test)"

SRC = os.path.join(ROOT, "src")
ASSETS = os.path.join(ROOT, "assets")
STAGE = os.path.join(ROOT, "build", "VitaChess")
DIST = os.path.join(ROOT, "dist")
CACHE = os.path.join(ROOT, "tools", "cache")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def game_version():
    m = re.search(r'config\.VERSION\s*=\s*"v?([\d.]+)"', read(os.path.join(SRC, "config.lua")))
    return m.group(1) if m else "0.0.0"


def app_ver(version):
    """'0.2.1' -> '00.21' (the Vita wants XX.YY)."""
    parts = [int(p) for p in (version.split(".") + ["0", "0"])[:3]]
    return "%02d.%02d" % (parts[0], min(99, parts[1] * 10 + parts[2]))


def bundle(version, platform_file="platform"):
    """Pack the modules into one Lua file with a tiny built-in require()."""
    out = ["-- Vita Chess %s - built by tools/build.py from src/." % version,
           "-- Edit the files in src/ and rebuild rather than editing this file.",
           "local __modules, __loaded = {}, {}",
           "local function require(name)",
           "  local v = __loaded[name]",
           "  if v == nil then",
           "    local load = __modules[name]",
           "    if not load then error(\"module not found: \" .. name) end",
           "    v = load(name)",
           "    if v == nil then v = true end",
           "    __loaded[name] = v",
           "  end",
           "  return v",
           "end",
           ""]
    for name in MODULES:
        source = platform_file if name == "platform" else name
        code = read(os.path.join(SRC, source + ".lua")).rstrip()
        if re.search(r"\bgoto\b", code):
            sys.exit("%s.lua uses goto, which the PSP's Lua 5.1 doesn't support" % source)
        out.append('__modules["%s"] = function(...)' % name)
        out.append(code)
        out.append("end")
        out.append("")
    out.append(read(os.path.join(SRC, "main.lua")).rstrip())
    return "\n".join(out) + "\n"


def cached_download(url, name, magic):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        print("Downloading %s..." % name)
        urllib.request.urlretrieve(url, path)
    with open(path, "rb") as f:
        if f.read(len(magic)) != magic:
            sys.exit("Cached %s doesn't look valid; delete %s and try again." % (name, path))
    return path


def get_eboot():
    return cached_download(EBOOT_URL, "eboot_safe.bin", b"SCE\0")


def build():
    version = game_version()
    print("Building Vita Chess v%s" % version)
    shutil.rmtree(STAGE, ignore_errors=True)
    os.makedirs(STAGE)
    os.makedirs(DIST, exist_ok=True)

    index = bundle(version)
    with open(os.path.join(STAGE, "index.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(index)
    shutil.copy(os.path.join(STAGE, "index.lua"), os.path.join(DIST, "index.lua"))

    for folder in ("pieces", "sounds", "fonts", "puzzles", "art", "sce_sys"):
        shutil.copytree(os.path.join(ASSETS, folder), os.path.join(STAGE, folder))
    with open(os.path.join(STAGE, "sce_sys", "param.sfo"), "wb") as f:
        f.write(make_param_sfo(TITLE, TITLE_ID, app_ver(version)))
    shutil.copy(get_eboot(), os.path.join(STAGE, "eboot.bin"))

    vpk = os.path.join(DIST, "VitaChess-%s.vpk" % version)
    with zipfile.ZipFile(vpk, "w", zipfile.ZIP_DEFLATED) as z:
        for folder, _, files in os.walk(STAGE):
            for name in sorted(files):
                full = os.path.join(folder, name)
                z.write(full, os.path.relpath(full, STAGE).replace(os.sep, "/"))
    print("Wrote %s" % os.path.relpath(vpk, ROOT))
    print("Wrote dist/index.lua (copy to ux0:app/%s/ for quick updates)" % TITLE_ID)


def build_psp():
    version = game_version()
    print("Building Vita Chess v%s for PSP (LuaDEV R0)" % version)
    stage = os.path.join(ROOT, "build", "psp", "VitaChess")
    shutil.rmtree(os.path.dirname(stage), ignore_errors=True)
    os.makedirs(stage)
    with open(os.path.join(stage, "script.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(bundle(version, "platform_psp"))
    psp_assets = os.path.join(ASSETS, "psp")
    shutil.copytree(os.path.join(psp_assets, "pieces"), os.path.join(stage, "pieces"))
    shutil.copytree(os.path.join(psp_assets, "sounds"), os.path.join(stage, "sounds"))
    shutil.copytree(os.path.join(ASSETS, "puzzles"), os.path.join(stage, "puzzles"))

    with open(cached_download(PSP_EBOOT_URL, "luadev_EBOOT.PBP", b"\0PBP"), "rb") as f:
        parts = pbp.unpack(f.read())
    parts["PARAM.SFO"] = patch_sfo_string(parts["PARAM.SFO"], "TITLE", PSP_TITLE)
    with open(os.path.join(psp_assets, "ICON0.PNG"), "rb") as f:
        parts["ICON0.PNG"] = f.read()
    with open(os.path.join(stage, "EBOOT.PBP"), "wb") as f:
        f.write(pbp.pack(parts))

    out = os.path.join(DIST, "VitaChess-PSP-%s.zip" % version)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for folder, _, names in os.walk(stage):
            for name in sorted(names):
                full = os.path.join(folder, name)
                z.write(full, os.path.relpath(full, os.path.dirname(stage)).replace(os.sep, "/"))
    print("Wrote %s (unzip into PSP/GAME/ on the memory stick)" % os.path.relpath(out, ROOT))


def build_desktop():
    """The Vita game running in LOVE (love2d.org) on Windows, Mac or Linux, for quick testing."""
    version = game_version()
    out = os.path.join(DIST, "VitaChess-desktop-%s.love" % version)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("game.lua", bundle(version, "platform_love"))
        for name in ("main.lua", "conf.lua"):
            z.write(os.path.join(ROOT, "tools", "desktop", name), name)
        for folder in ("pieces", "sounds", "fonts", "puzzles", "art"):
            for base, _, names in os.walk(os.path.join(ASSETS, folder)):
                for name in sorted(names):
                    full = os.path.join(base, name)
                    z.write(full, os.path.relpath(full, ASSETS).replace(os.sep, "/"))
    print("Wrote %s (open it with LOVE 11)" % os.path.relpath(out, ROOT))


def deploy(ip):
    """Upload dist/index.lua to the Vita over FTP (port 1337).

    Works with VitaShell's FTP server (press SELECT in VitaShell) or the
    vitacompanion plugin. With vitacompanion, the game is also restarted.
    Only index.lua is sent: install the full VPK when assets change.
    """
    index = os.path.join(DIST, "index.lua")
    remote_dir = "/ux0:/app/%s" % TITLE_ID
    print("Sending index.lua to %s..." % ip)
    try:
        ftp = ftplib.FTP()
        ftp.connect(ip, 1337, timeout=8)
        ftp.login()
        ftp.cwd(remote_dir)
        with open(index, "rb") as f:
            ftp.storbinary("STOR index.lua", f)
        ftp.quit()
    except Exception as e:
        sys.exit("Couldn't upload (%s). Is the FTP server running and the IP right?\n"
                 "In VitaShell, press SELECT to start it. The game must be installed once from the VPK." % e)
    print("Uploaded to ux0:app/%s/index.lua" % TITLE_ID)
    # vitacompanion's command port can restart the game for us
    try:
        for cmd in ("destroy", "launch %s" % TITLE_ID):
            with socket.create_connection((ip, 1338), timeout=3) as s:
                s.sendall((cmd + "\n").encode())
        print("Restarted the game with vitacompanion.")
    except OSError:
        print("Done. Close and reopen Vita Chess to load the update.")


def run_tests():
    luajit = shutil.which("luajit")
    if not luajit:
        sys.exit("LuaJIT not found on PATH; install it to run the tests.")
    tests = ["tests/test_rules.lua", "tests/test_ui.lua"]
    if "--psp" in sys.argv:
        tests.append("tests/test_psp.lua")
    for test in tests:
        print("Running %s" % test)
        if subprocess.call([luajit, test], cwd=ROOT) != 0:
            sys.exit("%s failed" % test)
    print("All tests passed.")


if __name__ == "__main__":
    build()
    if "--psp" in sys.argv:
        build_psp()
    if "--desktop" in sys.argv:
        build_desktop()
    if "--deploy" in sys.argv:
        i = sys.argv.index("--deploy")
        if i + 1 >= len(sys.argv):
            sys.exit("Usage: python tools/build.py --deploy <Vita IP address>")
        deploy(sys.argv[i + 1])
    if "--test" in sys.argv:
        run_tests()
