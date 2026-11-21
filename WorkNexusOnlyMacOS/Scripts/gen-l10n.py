#!/usr/bin/env python3
"""lib/l10n/app_*.arb -> App/Resources/Localizable.xcstrings (re-run after each upstream sync).
ICU placeholders {name} become %1$@ style positionals in the order they appear.
Also merges App/Resources/Localizable.extra.json (keys the Swift modules need that the .arb files lack)."""
import json, re, sys, pathlib
root = pathlib.Path(__file__).resolve().parents[2]
arbs = {p.stem.split("_",1)[1]: json.loads(p.read_text()) for p in sorted((root/"lib/l10n").glob("app_*.arb"))}
src = "en"
strings = {}
def icu_other(v):
    """`{count, plural, =1{..} other{..}}` -> the `other` branch (languages without plural forms, e.g. Vietnamese);
    anything that is not a single top-level plural is returned unchanged."""
    m = re.match(r"^\{\s*\w+\s*,\s*plural\s*,", v)
    if not m: return v
    i, depth, start, body = m.end(), 1, None, None
    # walk the branches: `selector{...}` pairs until the closing brace of the plural
    while i < len(v) and depth > 0:
        mm = re.compile(r"\s*([=\w]+)\s*\{").match(v, i)
        if not mm: break
        sel, j, d = mm.group(1), mm.end(), 1
        while j < len(v) and d > 0:
            d += {"{": 1, "}": -1}.get(v[j], 0); j += 1
        if sel == "other": body = v[mm.end():j - 1]
        i = j
        if i < len(v) and v[i] == "}": depth = 0
    return body if body is not None and v.rstrip().endswith("}") else v
PH = r"\{\s*(\w+)\s*(?:,[^{}]*)?\}"
def names_of(v):
    out = []
    head = re.match(r"^\{\s*(\w+)\s*,\s*plural\s*,", v)
    if head: out.append(head.group(1))
    for m in re.finditer(PH, v):
        if m.group(1) not in out: out.append(m.group(1))
    return out
def conv(v, order):
    """{name} -> %N$@ with N from `order` (the English placeholder order, so every language numbers alike)."""
    def sub(m):
        n = m.group(1)
        if n not in order: order.append(n)
        return f"%{order.index(n)+1}$@"
    return re.sub(PH, sub, v)
for key, val in arbs[src].items():
    if key.startswith("@") or not isinstance(val, str): continue
    locs = {}
    order = names_of(val)
    for lang, d in arbs.items():
        if key in d and isinstance(d[key], str):
            raw = d[key]
            if "plural," in raw:
                # Vietnamese has one plural form: resolve to it. Other languages keep the raw ICU text, which the
                # modules detect (`plural,`) and replace by their own English plural fallback.
                if lang == "vi": raw = icu_other(raw)
                else:
                    locs[lang] = {"stringUnit": {"state": "translated", "value": raw}}
                    continue
            locs[lang] = {"stringUnit": {"state": "translated", "value": conv(raw, list(order))}}
    strings[key] = {"extractionState": "manual", "localizations": locs}
# App/Resources/Localizable.extra.json: keys the Swift modules use that are not in the .arb files
# ({"key": {"en": "...", "vi": "..."}}, values already printf-style). An .arb key wins; duplicates warn.
extra_file = root/"WorkNexusOnlyMacOS/App/Resources/Localizable.extra.json"
extra_added = 0
if extra_file.exists():
    for key, vals in json.loads(extra_file.read_text()).items():
        if key in strings:
            print(f"warning: extra key '{key}' already exists in lib/l10n/*.arb; arb value kept", file=sys.stderr)
            continue
        strings[key] = {"extractionState": "manual", "localizations": {
            lang: {"stringUnit": {"state": "translated", "value": v}} for lang, v in vals.items()}}
        extra_added += 1
# App/Resources/Localizable.zh-Hans.json: Simplified Chinese for every key ({"key": "...", printf-style like the
# catalog), kept on the macOS side: the Flutter app has no Chinese .arb. An extra key may also carry "zh-Hans" itself.
zh_file = root/"WorkNexusOnlyMacOS/App/Resources/Localizable.zh-Hans.json"
if zh_file.exists():
    zh = json.loads(zh_file.read_text())
    for key, entry in strings.items():
        if "zh-Hans" not in entry["localizations"] and zh.get(key):
            entry["localizations"]["zh-Hans"] = {"stringUnit": {"state": "translated", "value": zh[key]}}
    missing = [k for k, e in strings.items() if "zh-Hans" not in e["localizations"]]
    if missing:
        print(f"warning: {len(missing)} keys have no Simplified Chinese (English shows): {', '.join(missing[:12])}", file=sys.stderr)
out = {"sourceLanguage": src, "strings": strings, "version": "1.0"}
dst = root/"WorkNexusOnlyMacOS/App/Resources/Localizable.xcstrings"
dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_text(json.dumps(out, ensure_ascii=False, indent=2))
locales = sorted({l for e in strings.values() for l in e["localizations"]})
print(f"{len(strings)} keys ({extra_added} from Localizable.extra.json), locales={locales} -> {dst}")
