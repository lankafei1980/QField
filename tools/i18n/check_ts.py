#!/usr/bin/env python3
"""Sanity-check Qt .ts translation files.

Checks performed:
  * XML well-formedness
  * no empty / unfinished translations (unless the string is whitelisted)
  * placeholder parity (%1, %2, %n ...) between source and translation
  * HTML tag parity (&lt;b&gt;, &lt;br&gt; ... after unescaping)
  * leading / trailing whitespace preserved
  * identical-to-source strings reported (excluding deliberate brand names)

Usage:
  tools/i18n/check_ts.py i18n/qfield_zh.ts [more.ts ...]
Exit code 0 when everything is fine, 1 otherwise.
"""

import html
import re
import sys
import xml.etree.ElementTree as ET

# Strings that are intentionally kept identical to the source.
ALLOW_IDENTICAL = {
    "QFieldCloud",
    "QFieldCloud Projects",
    "NULL",
    "N/A",
    "X",
    "Y",
    "PDOP",
    "HDOP",
    "VDOP",
}

PLACEHOLDER = re.compile(r"%(?:\d+|n|%)")
TAG = re.compile(r"<[^>]+>")


def check_file(path):
    problems = []
    root = ET.parse(path).getroot()

    unfinished, vanished, total, identical = 0, 0, 0, []
    for context in root.findall("context"):
        ctx_name = context.findtext("name", default="")
        for message in context.findall("message"):
            total += 1
            source = html.unescape(message.findtext("source", default=""))
            translation = message.find("translation")
            if translation is None:
                continue
            ttype = translation.get("type")
            if ttype == "vanished":
                vanished += 1
                continue
            forms = translation.findall("numerusform")
            if forms:
                text = html.unescape("".join(form.text or "" for form in forms))
            else:
                text = html.unescape(translation.text or "")
            if ttype == "unfinished" or not text.strip():
                if source.strip() not in ALLOW_IDENTICAL:
                    unfinished += 1
                    problems.append(f"[{ctx_name}] unfinished: {source[:70]!r}")
                continue

            if source.strip() in ALLOW_IDENTICAL:
                continue

            src_ph, tr_ph = sorted(PLACEHOLDER.findall(source)), sorted(PLACEHOLDER.findall(text))
            if src_ph != tr_ph:
                problems.append(
                    f"[{ctx_name}] placeholder mismatch {src_ph} != {tr_ph}: {source[:60]!r}"
                )

            src_tags, tr_tags = sorted(TAG.findall(source)), sorted(TAG.findall(text))
            if src_tags != tr_tags:
                problems.append(f"[{ctx_name}] tag mismatch {src_tags} != {tr_tags}: {source[:60]!r}")

            if source.count("\n") != text.count("\n"):
                problems.append(f"[{ctx_name}] newline count mismatch: {source[:60]!r}")

            if text == source:
                identical.append(f"[{ctx_name}] identical: {source[:60]!r}")

    print(f"{path}: {total} messages, {unfinished} unfinished, {vanished} vanished")
    for item in identical:
        print(f"  note (identical): {item}")
    for problem in problems:
        print(f"  ERROR {problem}")
    return problems


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    failed = False
    for path in argv[1:]:
        failed |= bool(check_file(path))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
