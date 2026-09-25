# Adds banner_logo/banner_hero to the hermes skin: the pinned banner.py art
# with its golds swapped for palette hexes. argv: banner.py, skin.json,
# colour map (json {"FFD700": "#rrggbb", ...}), out.
import ast
import json
import re
import sys

banner, skin_path, map_path, out = sys.argv[1:]
cmap = json.load(open(map_path))
consts = {
    n.targets[0].id: n.value.value
    for n in ast.parse(open(banner, encoding="utf-8").read()).body
    if isinstance(n, ast.Assign)
    and len(n.targets) == 1
    and isinstance(n.targets[0], ast.Name)
    and isinstance(n.value, ast.Constant)
    and isinstance(n.value.value, str)
}
skin = json.load(open(skin_path))
for key, const in (("banner_logo", "HERMES_AGENT_LOGO"), ("banner_hero", "HERMES_CADUCEUS")):
    art = consts.get(const)
    if art is None:
        sys.exit(f"{const} not found in {banner}")
    found = {h.upper() for h in re.findall(r"#([0-9A-Fa-f]{6})", art)}
    if found - cmap.keys():
        sys.exit(f"{const}: unmapped colours {sorted(found - cmap.keys())}")
    skin[key] = re.sub(r"#([0-9A-Fa-f]{6})", lambda m: cmap[m.group(1).upper()], art)
json.dump(skin, open(out, "w"), ensure_ascii=False, indent=1)
