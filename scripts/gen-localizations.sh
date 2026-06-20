#!/usr/bin/env bash
# Compile Localizable.xcstrings -> <target>/<locale>.lproj/Localizable.strings
# (SwiftPM copies .xcstrings verbatim; no .xcodeproj, so we emit .strings here).
# Usage: scripts/gen-localizations.sh <target-Resources-dir>

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT/Sources/ArcherKit/Resources/Localizable.xcstrings"
TARGET="${1:?usage: gen-localizations.sh <target-Resources-dir>}"

[ -f "$CATALOG" ] || { echo "gen-localizations: catalog not found: $CATALOG" >&2; exit 1; }

CATALOG="$CATALOG" TARGET="$TARGET" python3 - <<'PY'
import json, os

catalog = os.environ["CATALOG"]
target = os.environ["TARGET"]

with open(catalog, encoding="utf-8") as f:
    data = json.load(f)

source = data.get("sourceLanguage", "en")
strings = data.get("strings", {})

locales = {source}
for entry in strings.values():
    locales.update(entry.get("localizations", {}).keys())


def escape(s):
    return (s.replace("\\", "\\\\").replace("\"", "\\\"")
             .replace("\n", "\\n").replace("\t", "\\t"))


def value_for(entry, locale, key):
    unit = entry.get("localizations", {}).get(locale, {}).get("stringUnit")
    if unit and unit.get("value"):
        return unit["value"]
    return key  # fall back to key = English source string


for locale in sorted(locales):
    lproj = os.path.join(target, f"{locale}.lproj")
    os.makedirs(lproj, exist_ok=True)
    lines = [f'"{escape(k)}" = "{escape(value_for(strings[k], locale, k))}";'
             for k in sorted(strings)]
    with open(os.path.join(lproj, "Localizable.strings"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"  wrote {locale}.lproj/Localizable.strings ({len(lines)} keys)")
PY
