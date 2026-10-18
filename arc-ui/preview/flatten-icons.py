#!/usr/bin/env python3
# Anteprima: copia le icone delle app di un tema (es. i sorgenti di WhiteSur)
# in una cartella piatta <nome>.svg, risolvendo i collegamenti simbolici come
# farebbe install.sh. Uso: flatten-icons.py <sorgenti del tema> <destinazione>
import os
import re
import shutil
import sys

src, dest = sys.argv[1], sys.argv[2]
real, links = {}, {}
for root, _, files in os.walk(src):
    if "symbolic" in root or re.search(r"/(16|22|24|32)(/|$)", root) or re.search(r"/(alternative|bold|bolder)(/|$)", root):
        continue
    if not any(part in root for part in ("apps", "places", "devices")):
        continue
    for name in files:
        if not name.endswith(".svg"):
            continue
        path = os.path.join(root, name)
        icon = name[:-4]
        if os.path.islink(path):
            links.setdefault(icon, os.path.basename(os.readlink(path))[:-4])
        elif icon not in real or "scalable" in root:
            real[icon] = path


def resolve(icon, depth=0):
    if icon in real:
        return real[icon]
    if icon in links and depth < 6:
        return resolve(links[icon], depth + 1)
    return None


os.makedirs(dest, exist_ok=True)
count = 0
for icon in set(real) | set(links):
    path = resolve(icon)
    if path:
        shutil.copyfile(path, os.path.join(dest, icon + ".svg"))
        count += 1
print("%d icone in %s" % (count, dest))
