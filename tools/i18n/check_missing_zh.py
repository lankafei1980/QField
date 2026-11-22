#!/usr/bin/env python3
"""Check that every qsTr() string in QML sources has a Chinese translation.

Qt's lupdate is not available in this repository's local environment (the app is
built on GitHub Actions), so new strings can silently show up in English. This
script extracts the qsTr() sources from the given QML files/directories and
verifies that a translation exists in i18n/qfield_zh.ts.

Usage:
  tools/i18n/check_missing_zh.py i18n/qfield_zh.ts src/app/qml src/gui/qml

Exit code 0 when every source has a translation, 1 otherwise.
"""

import html
import os
import re
import sys
import xml.etree.ElementTree as ET

QSTR = re.compile(r"qsTr\s*\(\s*(?P<q>['\"])(?P<s>(?:\\.|(?!(?P=q)).)*)(?P=q)", re.S)
ESCAPE = re.compile(r"\\(.)")


def unescape_js(value):
    return ESCAPE.sub(lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), value)


def translations(ts_path):
    root = ET.parse(ts_path).getroot()
    known = set()
    for context in root.findall("context"):
        name = context.findtext("name", default="")
        for message in context.findall("message"):
            translation = message.find("translation")
            if translation is None or translation.get("type") == "vanished":
                continue
            forms = translation.findall("numerusform")
            if forms:
                text = "".join(html.unescape(form.text or "") for form in forms).strip()
            else:
                text = html.unescape((translation.text or "").strip())
            if not text:
                continue
            source = html.unescape(message.findtext("source", default=""))
            known.add((name, source))
    return known


def qml_files(paths):
    for path in paths:
        if os.path.isdir(path):
            for root, _dirs, files in os.walk(path):
                for name in sorted(files):
                    if name.endswith(".qml"):
                        yield os.path.join(root, name)
        elif os.path.isfile(path):
            yield path


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2

    known = translations(argv[1])
    missing = []
    for path in qml_files(argv[2:]):
        with open(path, encoding="utf-8") as handle:
            content = handle.read()
        context = os.path.splitext(os.path.basename(path))[0]
        for match in QSTR.finditer(content):
            source = unescape_js(match.group("s"))
            if (context, source) not in known:
                line = content.count("\n", 0, match.start()) + 1
                missing.append((path, line, context, source))

    if missing:
        print(f"{len(missing)} missing translation(s):")
        for path, line, context, source in missing:
            print(f"  {path}:{line} [{context}] {source!r}")
        return 1

    print("All qsTr() sources have a Chinese translation.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
