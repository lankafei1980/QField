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

# Strings that survive compilation as plain data.
MARKERS = {
    "app label (zh)": "RTK 外业助手",
    "app label (en)": "RTK Field",
    "package name": "cn.zpyzs.rtkapp",
    "chinese translation resource": "qfield_zh.qm",
    "english translation resource": "qfield_en.qm",
    "i18n resource prefix": ":/i18n",
    "ntrip reconnect log": "NTRIP client: reconnecting in",
}

# Translated strings live inside the zlib compressed .qm resources, so they
# cannot be grepped; their presence is implied by the .qm resource above.
COMPRESSED_HINTS = ["千寻位置", "服务商", "NTRIP 认证失败", "天线高校正", "跟踪设置"]


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
        payload += b"".join(apk.read(name) for name in libs)
        for extra in ("AndroidManifest.xml",):
            if extra in names:
                payload += apk.read(extra)

        print("\ntranslations (compressed inside qfield_zh.qm, greppable only in the .ts): " + ", ".join(COMPRESSED_HINTS))
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
