#!/usr/bin/env python3
"""Inspect a freshly built QField / RTK APK without any Android tooling.

Checks that the build actually carries this fork's changes:

  * package name (manifest string pool)
  * application label (resources.arsc) and the zh-CN label
  * bundled ABI(s)
  * translated Qt strings inside the compiled binaries (the .qm files are
    embedded as Qt resources, i.e. UTF-16 data inside the .so files)
  * presence of the Qianxun preset strings and the NTRIP socket errors

Usage::

    python3 tools/dev/verify_apk.py rtkapp-arm64-debug.apk
"""

import re
import sys
import zipfile

MARKERS = {
    "app label (zh)": "RTK 外业助手",
    "app label (en)": "RTK Field",
    "package name": "cn.zpyzs.rtkapp",
    "qianxun preset": "千寻位置",
    "service provider label": "服务商",
    "ntrip auth error": "NTRIP 认证失败",
    "ntrip reconnect": "reconnecting in",
    "antenna height": "天线高校正",
    "tracking settings": "跟踪设置",
}


def contains(haystack, needle):
    return needle.encode("utf-8") in haystack or needle.encode("utf-16-le") in haystack


def main(path):
    with zipfile.ZipFile(path) as apk:
        names = apk.namelist()
        libs = [n for n in names if n.startswith("lib/") and n.endswith(".so")]
        abis = sorted({n.split("/")[1] for n in libs})
        print(f"file      : {path}")
        print(f"entries   : {len(names)}")
        print(f"abis      : {', '.join(abis) if abis else 'none'}")

        payload = apk.read("resources.arsc") if "resources.arsc" in names else b""
        payload += b"".join(apk.read(lib) for l in libs)
        for extra in ("AndroidManifest.xml",):
            if extra in names:
                payload += apk.read(extra)

        print("\nmarkers:")
        missing = 0
        for label, needle in MARKERS.items():
            ok = contains(payload, needle)
            missing += 0 if ok else 1
            print(f"  [{'x' if ok else ' '}] {label}: {needle}")

        version = re.search(rb"versionName", payload)
        print(f"\nversionName token present: {bool(version)}")
        print(f"\n{'OK' if missing == 0 else f'MISSING {missing} marker(s)'}")
        return 0 if missing == 0 else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
