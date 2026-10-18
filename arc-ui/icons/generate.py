#!/usr/bin/env python3
# =============================================================================
#  arc icons — icone delle app di arc UI, disegnate in stile macOS
#
#    <out>/icons/arc-icons/index.theme          (Inherits=WhiteSur-dark,...)
#    <out>/icons/arc-icons/scalable/apps/*.svg
#
#  Uso: generate.py --out /usr/share
#
#  Griglia come le icone di macOS 27: tela 128×128, corpo ad angoli continui
#  (raggio 22,37% del lato, smussatura 60%) con ombra morbida, ingrandito a
#  112×112 come le icone WhiteSur che restano per le altre app; colori di
#  sistema di Apple e bordo di vetro (luce in alto, riflesso in basso); sopra, oggetti in
#  tridimensione con gradienti, luci, riflessi e ombre di contatto. Disegni
#  originali (nessuna icona Apple). Le app senza un'arc icon prendono le icone
#  di WhiteSur (Inherits), poi Papirus.
#  Le sfocature usano feGaussianBlur: Qt SVG lo supporta dalla 6.7.
# =============================================================================
import argparse
import math
import os
import shutil

X0, Y0, S = 12.5, 10.5, 103.0
RADIUS = 0.2237      # raggio degli angoli, frazione del lato (macOS 27)
SMOOTHING = 0.6      # smussatura continua degli angoli (60%, "iOS" in Figma)


def squircle(dx=0.0, dy=0.0, inset=0.0):
    """Rettangolo ad angoli continui come le icone di macOS 27: raggio 22,37%
    del lato con smussatura 60% (curva di Bézier + arco, metodo di Figma)."""
    x, y, size = X0 + dx + inset, Y0 + dy + inset, S - 2 * inset
    r = RADIUS * size
    p = min((1 + SMOOTHING) * r, size / 2)
    arc_measure = 90 * (1 - SMOOTHING)
    arc = math.sin(math.radians(arc_measure / 2)) * r * math.sqrt(2)
    alpha = (90 - arc_measure) / 2
    p3p4 = r * math.tan(math.radians(alpha / 2))
    beta = 45 * SMOOTHING
    c = p3p4 * math.cos(math.radians(beta))
    d = c * math.tan(math.radians(beta))
    b = (p - arc - c - d) / 3
    a = 2 * b
    w = h = size
    f = lambda v: "%.3f" % v
    return " ".join([
        "M", f(x + w - p), f(y),
        "c", f(a), "0", f(a + b), "0", f(a + b + c), f(d),
        "a", f(r), f(r), "0 0 1", f(arc), f(arc),
        "c", f(d), f(c), f(d), f(b + c), f(d), f(a + b + c),
        "L", f(x + w), f(y + h - p),
        "c", "0", f(a), "0", f(a + b), f(-d), f(a + b + c),
        "a", f(r), f(r), "0 0 1", f(-arc), f(arc),
        "c", f(-c), f(d), f(-(b + c)), f(d), f(-(a + b + c)), f(d),
        "L", f(x + p), f(y + h),
        "c", f(-a), "0", f(-(a + b)), "0", f(-(a + b + c)), f(-d),
        "a", f(r), f(r), "0 0 1", f(-arc), f(-arc),
        "c", f(-d), f(-c), f(-d), f(-(b + c)), f(-d), f(-(a + b + c)),
        "L", f(x), f(y + p),
        "c", "0", f(-a), "0", f(-(a + b)), f(d), f(-(a + b + c)),
        "a", f(r), f(r), "0 0 1", f(arc), f(-arc),
        "c", f(c), f(-d), f(b + c), f(-d), f(a + b + c), f(-d),
        "Z"])


def lg(gid, stops, x1=0, y1=0, x2=0, y2=1, units=None, transform=None):
    attrs = 'id="%s" x1="%s" y1="%s" x2="%s" y2="%s"' % (gid, x1, y1, x2, y2)
    if units:
        attrs += ' gradientUnits="%s"' % units
    if transform:
        attrs += ' gradientTransform="%s"' % transform
    body = "".join('<stop offset="%s" stop-color="%s"%s/>' % (o, c, (' stop-opacity="%s"' % a) if a is not None else "")
                   for o, c, a in [(s + (None,))[:3] for s in stops])
    return "<linearGradient %s>%s</linearGradient>" % (attrs, body)


def rg(gid, stops, cx=0.5, cy=0.5, r=0.5, fx=None, fy=None, units=None):
    attrs = 'id="%s" cx="%s" cy="%s" r="%s"' % (gid, cx, cy, r)
    if fx is not None:
        attrs += ' fx="%s" fy="%s"' % (fx, fy)
    if units:
        attrs += ' gradientUnits="%s"' % units
    body = "".join('<stop offset="%s" stop-color="%s"%s/>' % (o, c, (' stop-opacity="%s"' % a) if a is not None else "")
                   for o, c, a in [(s + (None,))[:3] for s in stops])
    return "<radialGradient %s>%s</radialGradient>" % (attrs, body)


def blur(fid, std):
    return ('<filter id="%s" x="-40%%" y="-40%%" width="180%%" height="180%%">'
            '<feGaussianBlur stdDeviation="%s"/></filter>' % (fid, std))


def shadow(d, std=2.0, dy=2.0, opacity=0.3, fid="soft"):
    """Ombra sfocata di una forma (va prima della forma)."""
    return '<path d="%s" fill="#000" fill-opacity="%s" filter="url(#%s%s)" transform="translate(0 %s)"/>' % (
        d, opacity, fid, str(std).replace(".", "_"), dy)


def rr(x, y, w, h, r):
    return ("M%g %g H%g A%g %g 0 0 1 %g %g V%g A%g %g 0 0 1 %g %g H%g A%g %g 0 0 1 %g %g V%g A%g %g 0 0 1 %g %g Z"
            % (x + r, y, x + w - r, r, r, x + w, y + r, y + h - r, r, r, x + w - r, y + h, x + r, r, r, x, y + h - r,
               y + r, r, r, x + r, y))


def circ(cx, cy, r):
    return "M%g %g A%g %g 0 1 1 %g %g A%g %g 0 1 1 %g %g Z" % (cx - r, cy, r, r, cx + r, cy, r, r, cx - r, cy)


BLURS = [0.6, 1.0, 1.6, 2.4, 3.5, 6.0]


def icon(bg, content, defs=""):
    """bg: (colore in alto, colore in basso). Corpo, ombra, bordo di luce, contenuto."""
    q = squircle()
    filters = "".join(blur("soft%s" % str(s).replace(".", "_"), s) for s in BLURS)
    base = "".join([
        lg("bg", [(0, bg[0]), (1, bg[1])], 0, Y0, 0, Y0 + S, "userSpaceOnUse"),
        lg("rim", [(0, "#ffffff", 0.5), (0.45, "#ffffff", 0.06), (0.8, "#ffffff", 0.1), (1, "#ffffff", 0.28)], 0, Y0, 0, Y0 + S, "userSpaceOnUse"),
        lg("sheen", [(0, "#ffffff", 0.16), (0.45, "#ffffff", 0)], 0, Y0, 0, Y0 + S, "userSpaceOnUse"),
    ])
    return """<?xml version="1.0" encoding="UTF-8"?>
<!-- arc icons — generato da arc-ui/icons/generate.py -->
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<defs>%s%s%s</defs>
<g transform="translate(64 62) scale(1.087) translate(-64 -62)">
<path d="%s" fill="#000" fill-opacity="0.32" filter="url(#soft3_5)"/>
<path d="%s" fill="#000" fill-opacity="0.18" filter="url(#soft1_0)"/>
<path d="%s" fill="url(#bg)"/>
<path d="%s" fill="url(#sheen)"/>
%s
<path d="%s" fill="none" stroke="url(#rim)" stroke-width="1.6"/>
<path d="%s" fill="none" stroke="#000" stroke-opacity="0.14" stroke-width="0.6"/>
</g>
</svg>
""" % (filters, base, defs, squircle(dy=2.6), squircle(dy=0.8), q, q, content, squircle(inset=0.8), q)


# =============================================================================
#  Le icone
# =============================================================================

def files():
    back = "M27 38 A6 6 0 0 1 33 32 H52 L58.5 38.5 H95 A6 6 0 0 1 101 44.5 V88 A6 6 0 0 1 95 94 H33 A6 6 0 0 1 27 88 Z"
    front = "M25 55 A5.5 5.5 0 0 1 30.5 49.5 H97.5 A5.5 5.5 0 0 1 103 55 L100.2 90 A6 6 0 0 1 94.2 95.5 H33.8 A6 6 0 0 1 27.8 90 Z"
    defs = "".join([
        lg("back", [(0, "#ffffff", 0.62), (1, "#ffffff", 0.42)]),
        lg("front", [(0, "#ffffff"), (1, "#e3edff")]),
        lg("paper", [(0, "#ffffff"), (1, "#e7ecf3")]),
    ])
    content = "".join([
        shadow(back, 2.4, 2, 0.28),
        '<path d="%s" fill="url(#back)"/>' % back,
        '<path d="M33 37.5 H51.2 L56 42.3" fill="none" stroke="#ffffff" stroke-opacity="0.25" stroke-width="1"/>',
        '<g transform="rotate(-4 64 56)"><path d="%s" fill="#dfe6ef"/></g>' % rr(35, 42, 56, 32, 2.5),
        '<g transform="rotate(2.5 64 56)"><path d="%s" fill="url(#paper)"/></g>' % rr(37, 43, 54, 32, 2.5),
        '<path d="M44 51 H82 M44 56 H76" stroke="#c9d3e0" stroke-width="2" stroke-linecap="round"/>',
        shadow(front, 2.4, -1.5, 0.22),
        '<path d="%s" fill="url(#front)"/>' % front,
        '<path d="M30.5 50.3 H97.5" stroke="#ffffff" stroke-opacity="0.75" stroke-width="1.2" stroke-linecap="round"/>',
        '<path d="%s" fill="#0a6dff" fill-opacity="0.32"/>' % rr(54, 66, 20, 5, 2.5),
    ])
    return icon(("#4aa3ff", "#0a6dff"), content, defs)


def store():
    bag = "M37 46 H91 L88.5 97 A6 6 0 0 1 82.5 102.5 H45.5 A6 6 0 0 1 39.5 97 Z"
    star = "M64 60 L67.6 70.4 L78 74 L67.6 77.6 L64 88 L60.4 77.6 L50 74 L60.4 70.4 Z"
    defs = "".join([lg("w", [(0, "#ffffff"), (1, "#eef1f6")]), lg("star", [(0, "#ff7095"), (1, "#ff2d55")])])
    content = "".join([
        '<path d="M51 50 V42 A13 13 0 0 1 77 42 V50" fill="none" stroke="#ffffff" stroke-width="5" stroke-linecap="round"/>',
        shadow(bag, 2.4, 2.5, 0.28),
        '<path d="%s" fill="url(#w)"/>' % bag,
        '<path d="%s" fill="url(#star)"/>' % star,
    ])
    return icon(("#ff7095", "#ff2d55"), content, defs)


def installer():
    arrow = "M57 22 H71 V52 H83 L64 74 L45 52 H57 Z"
    tray = "M28 70 H44 L50 80 H78 L84 70 H100 V92 A8 8 0 0 1 92 100 H36 A8 8 0 0 1 28 92 Z"
    defs = lg("w", [(0, "#ffffff"), (1, "#eef1f6")])
    content = "".join([
        shadow(arrow, 2.4, 2.5, 0.28),
        '<path d="%s" fill="url(#w)"/>' % arrow,
        shadow(tray, 2.4, 2.5, 0.28),
        '<path d="%s" fill="url(#w)"/>' % tray,
    ])
    return icon(("#7f7dff", "#5856d6"), content, defs)


def photos():
    frame = rr(26, 30, 76, 66, 8)
    defs = "".join([
        lg("w", [(0, "#ffffff"), (1, "#eef1f6")]),
        lg("sky", [(0, "#ffd29a"), (1, "#ff8f7e")], 0, 38, 0, 88, "userSpaceOnUse"),
        lg("mnt", [(0, "#6f5ce0"), (1, "#3a2c97")], 0, 52, 0, 88, "userSpaceOnUse"),
    ])
    content = "".join([
        shadow(frame, 2.4, 2.5, 0.3),
        '<path d="%s" fill="url(#w)"/>' % frame,
        '<path d="%s" fill="url(#sky)"/>' % rr(33, 37, 62, 52, 4),
        '<circle cx="80" cy="52" r="7" fill="#fff6d8"/>',
        '<path d="M33 89 V77 L50 58 L62 71 L72 61 L95 84 V89 Z" fill="url(#mnt)"/>',
    ])
    return icon(("#64d8ec", "#30b0c7"), content, defs)


def documents():
    page = "M38 22 H74 L92 40 V100 A6 6 0 0 1 86 106 H44 A6 6 0 0 1 38 100 Z"
    defs = lg("w", [(0, "#ffffff"), (1, "#eef1f6")])
    content = "".join([
        shadow(page, 2.4, 2.5, 0.3),
        '<path d="%s" fill="url(#w)"/>' % page,
        '<path d="M74 22 V34 A6 6 0 0 0 80 40 H92 Z" fill="#ffd0cc"/>',
        '<path d="M48 56 H82 M48 68 H82 M48 80 H70" stroke="#ff3b30" stroke-opacity="0.85" stroke-width="5" stroke-linecap="round"/>',
    ])
    return icon(("#ff7a70", "#ff3b30"), content, defs)


def archive():
    box = rr(28, 34, 72, 62, 10)
    defs = lg("w", [(0, "#ffffff"), (1, "#eef1f6")])
    content = "".join([
        shadow(box, 2.4, 2.5, 0.3),
        '<path d="%s" fill="url(#w)"/>' % box,
        '<path d="M64 34 V96" stroke="#ff9f0a" stroke-width="4" stroke-dasharray="4 3.5"/>',
        '<path d="%s" fill="#ff9f0a"/>' % rr(56, 52, 16, 20, 6),
        '<path d="%s" fill="#ffffff"/>' % rr(60.5, 63, 7, 5, 2.5),
    ])
    return icon(("#ffc94a", "#ff9f0a"), content, defs)


def settings():
    defs = lg("w", [(0, "#ffffff"), (1, "#eef1f6")])
    content = "".join([
        shadow(rr(28, 36, 72, 24, 12), 2.4, 2.5, 0.28),
        '<path d="%s" fill="#34c759"/>' % rr(28, 36, 72, 24, 12),
        '<circle cx="88" cy="48" r="9" fill="url(#w)"/>',
        shadow(rr(28, 70, 72, 24, 12), 2.4, 2.5, 0.28),
        '<path d="%s" fill="url(#w)"/>' % rr(28, 70, 72, 24, 12),
        '<circle cx="40" cy="82" r="9" fill="#8e8e93"/>',
    ])
    return icon(("#a8a8b0", "#636366"), content, defs)


def terminal():
    screen = rr(26, 30, 76, 68, 9)
    defs = "".join([
        lg("bezel", [(0, "#4a5060"), (1, "#20232b")]),
        lg("glass", [(0, "#16301f"), (1, "#0b1510")]),
        lg("glare", [(0, "#ffffff", 0.16), (1, "#ffffff", 0)]),
    ])
    content = "".join([
        shadow(screen, 3.5, 3, 0.4),
        '<path d="%s" fill="url(#bezel)"/>' % screen,
        '<path d="%s" fill="url(#glass)"/>' % rr(31, 35, 66, 58, 6),
        '<path d="M39 52 L51 62 L39 72" fill="none" stroke="#7cf2b0" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" filter="url(#soft1_6)" opacity="0.7"/>',
        '<path d="M39 52 L51 62 L39 72" fill="none" stroke="#a6ffd0" stroke-width="4.2" stroke-linecap="round" stroke-linejoin="round"/>',
        '<path d="M57 73 H75" stroke="#7cf2b0" stroke-width="5" stroke-linecap="round" filter="url(#soft1_6)" opacity="0.7"/>',
        '<path d="M57 73 H75" stroke="#a6ffd0" stroke-width="4.2" stroke-linecap="round"/>',
        '<path d="M31 41 A6 6 0 0 1 37 35 H91 A6 6 0 0 1 97 41 V52 Q64 58 31 50 Z" fill="url(#glare)"/>',
        '<path d="M35 30.6 H93" stroke="#ffffff" stroke-opacity="0.35" stroke-width="1" stroke-linecap="round"/>',
    ])
    return icon(("#4a4a50", "#1c1c1e"), content, defs)


def screenshot():
    corners = ("M30 48 V40 A10 10 0 0 1 40 30 H48 M80 30 H88 A10 10 0 0 1 98 40 V48 "
               "M98 80 V88 A10 10 0 0 1 88 98 H80 M48 98 H40 A10 10 0 0 1 30 88 V80")
    content = "".join([
        '<path d="%s" fill="none" stroke="#000" stroke-opacity="0.2" stroke-width="8" stroke-linecap="round" filter="url(#soft1_6)" transform="translate(0 2)"/>' % corners,
        '<path d="%s" fill="none" stroke="#ffffff" stroke-width="7" stroke-linecap="round"/>' % corners,
        shadow(circ(64, 64, 12), 1.6, 2, 0.25),
        '<circle cx="64" cy="64" r="12" fill="#ffffff"/>',
    ])
    return icon(("#74d8ff", "#32ade6"), content)


def info():
    defs = "".join([
        lg("disc", [(0, "#ffffff"), (1, "#e3e6f6")]),
        lg("glyph", [(0, "#c16cf0"), (1, "#9a3ccc")]),
    ])
    content = "".join([
        shadow(circ(64, 64, 30), 3.5, 3, 0.35),
        '<circle cx="64" cy="64" r="30" fill="url(#disc)"/>',
        '<path d="M40 56 A26 26 0 0 1 88 56" fill="none" stroke="#ffffff" stroke-width="1.5" stroke-linecap="round"/>',
        '<circle cx="64" cy="49" r="5" fill="url(#glyph)"/>',
        '<path d="%s" fill="url(#glyph)"/>' % rr(59.5, 58, 9, 24, 4.5),
    ])
    return icon(("#d27fff", "#af52de"), content, defs)


def calculator():
    body = rr(34, 22, 60, 84, 12)
    defs = "".join([lg("w", [(0, "#ffffff"), (1, "#eef1f6")]), lg("eq", [(0, "#4aa3ff"), (1, "#0a84ff")])])
    content = "".join([
        shadow(body, 2.4, 2.5, 0.3),
        '<path d="%s" fill="url(#w)"/>' % body,
        '<path d="%s" fill="#ffd9a3"/>' % rr(42, 30, 44, 18, 5),
        '<path d="%s" fill="#ffd9a3"/>' % rr(42, 56, 20, 20, 6),
        '<path d="%s" fill="#ffd9a3"/>' % rr(66, 56, 20, 20, 6),
        '<path d="%s" fill="#ffd9a3"/>' % rr(42, 80, 20, 18, 6),
        '<path d="%s" fill="url(#eq)"/>' % rr(66, 80, 20, 18, 6),
    ])
    return icon(("#ffb340", "#ff9500"), content, defs)


def editor():
    page = rr(32, 22, 54, 84, 10)
    pencil = "M96 38 L106 48 L74 80 L60 84 L64 70 Z"
    defs = "".join([lg("w", [(0, "#ffffff"), (1, "#eef1f6")]), lg("pbody", [(0, "#4aa3ff"), (1, "#0a6dff")])])
    content = "".join([
        shadow(page, 2.4, 2.5, 0.3),
        '<path d="%s" fill="url(#w)"/>' % page,
        '<path d="M44 44 H72 M44 56 H72 M44 68 H62" stroke="#ffcc00" stroke-width="5" stroke-linecap="round"/>',
        shadow(pencil, 1.6, 2, 0.3),
        '<path d="%s" fill="url(#pbody)"/>' % pencil,
    ])
    return icon(("#ffe066", "#ffcc00"), content, defs)


def monitor():
    card = rr(26, 32, 76, 58, 10)
    line = "M36 70 L48 62 L58 72 L70 50 L80 62 L92 46"
    defs = lg("w", [(0, "#ffffff"), (1, "#eef1f6")])
    content = "".join([
        shadow(card, 2.4, 2.5, 0.3),
        '<path d="%s" fill="url(#w)"/>' % card,
        '<path d="%s" fill="none" stroke="#34c759" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>' % line,
        '<path d="%s" fill="#ffffff" fill-opacity="0.9"/>' % rr(52, 94, 24, 6, 3),
    ])
    return icon(("#5fe08a", "#34c759"), content, defs)


def trash():
    can = "M38 46 H90 L86 98 A7 7 0 0 1 79 104.5 H49 A7 7 0 0 1 42 98 Z"
    lid = rr(32, 36, 64, 10, 5)
    defs = "".join([
        lg("can", [(0, "#c9d2df"), (0.5, "#a8b3c4"), (1, "#8a95a8")], 0, 0, 1, 0),
        lg("lid", [(0, "#e8edf4"), (1, "#a9b3c3")]),
        lg("inner", [(0, "#ffffff", 0.55), (1, "#ffffff", 0)]),
    ])
    ribs = "".join('<path d="M%g 52 L%g 97" stroke="#ffffff" stroke-opacity="0.45" stroke-width="2.6" stroke-linecap="round"/>' % (x, x + (x - 64) * -0.06) for x in (52, 64, 76))
    ribs += "".join('<path d="M%g 52 L%g 97" stroke="#6c778a" stroke-opacity="0.35" stroke-width="1.2" stroke-linecap="round"/>' % (x + 2.4, x + 2.4 + (x - 64) * -0.06) for x in (52, 64, 76))
    content = "".join([
        shadow(can, 3.5, 3, 0.3),
        '<path d="%s" fill="url(#can)"/>' % can,
        ribs,
        '<path d="M43 50 H85" stroke="#000" stroke-opacity="0.12" stroke-width="3"/>',
        shadow(lid, 1.6, 2, 0.35),
        '<path d="%s" fill="url(#lid)"/>' % lid,
        '<path d="%s" fill="url(#lid)" stroke="#9aa5b6" stroke-width="1"/>' % rr(54, 28.5, 20, 9, 4),
        '<path d="M37 37 H91" stroke="#ffffff" stroke-width="1.2" stroke-linecap="round"/>',
    ])
    return icon(("#ffffff", "#e5e5ea"), content, defs)


def launchpad():
    colors = [("#ff6961", "#ff3b30"), ("#ffb340", "#ff9500"), ("#ffe066", "#ffcc00"),
              ("#5fe08a", "#34c759"), ("#64d8ec", "#30b0c7"), ("#4aa3ff", "#0a84ff"),
              ("#7f7dff", "#5856d6"), ("#d27fff", "#af52de"), ("#ff7095", "#ff2d55")]
    defs = "".join(lg("t%d" % k, [(0, a), (1, b)]) for k, (a, b) in enumerate(colors))
    tiles = ""
    for k in range(9):
        r, c = divmod(k, 3)
        x, y = 30 + c * 24, 28 + r * 24
        tiles += shadow(rr(x, y, 20, 20, 6), 1.0, 1.4, 0.4)
        tiles += '<path d="%s" fill="url(#t%d)"/>' % (rr(x, y, 20, 20, 6), k)
        tiles += '<path d="%s" fill="#ffffff" fill-opacity="0.28"/>' % rr(x + 2, y + 1.5, 16, 7, 3.5)
    return icon(("#4a4a50", "#1c1c1e"), tiles, defs)


def generic():
    defs = "".join([
        lg("top", [(0, "#ffffff"), (1, "#eef1f6")]),
        lg("left", [(0, "#dfe4ec"), (1, "#c3cad6")]),
        lg("right", [(0, "#c8cfda"), (1, "#a6afbe")]),
    ])
    top, left, right = "M64 28 L96 44 L64 60 L32 44 Z", "M32 44 L64 60 V98 L32 82 Z", "M96 44 L64 60 V98 L96 82 Z"
    content = "".join([
        shadow(left + " " + right, 3.5, 3, 0.35),
        '<path d="%s" fill="url(#left)"/><path d="%s" fill="url(#right)"/><path d="%s" fill="url(#top)"/>' % (left, right, top),
        '<path d="M32 44 L64 60 L96 44" fill="none" stroke="#ffffff" stroke-width="1"/>',
    ])
    return icon(("#aeaeb2", "#636366"), content, defs)


ICONS = {
    files: ["system-file-manager", "org.kde.dolphin", "dolphin", "file-manager", "nautilus", "org.gnome.Nautilus"],
    store: ["plasmadiscover", "org.kde.discover", "system-software-center", "software-store", "gnome-software",
            "org.gnome.Software"],
    installer: ["system-software-install", "arcbase-install", "system-installer"],
    photos: ["gwenview", "org.kde.gwenview", "image-viewer", "eog", "multimedia-photo-viewer", "shotwell",
             "gnome-photos", "org.gnome.Photos"],
    documents: ["okular", "org.kde.okular", "document-viewer", "accessories-document-viewer", "evince",
                "org.gnome.Evince"],
    archive: ["ark", "org.kde.ark", "utilities-file-archiver", "file-roller", "org.gnome.FileRoller"],
    settings: ["preferences-system", "systemsettings", "org.kde.systemsettings", "preferences-desktop",
               "gnome-control-center", "org.gnome.Settings"],
    terminal: ["utilities-terminal", "org.kde.konsole", "konsole", "terminal", "org.gnome.Terminal", "xterm"],
    trash: ["user-trash", "user-trash-full", "trash-empty"],
    screenshot: ["spectacle", "org.kde.spectacle", "applets-screenshooter", "accessories-screenshot", "screenshot",
                 "gnome-screenshot"],
    info: ["hwinfo", "kinfocenter", "org.kde.kinfocenter"],
    calculator: ["accessories-calculator", "org.kde.kcalc", "kcalc", "calc", "gnome-calculator",
                 "org.gnome.Calculator"],
    editor: ["accessories-text-editor", "text-editor", "kwrite", "org.kde.kwrite", "gedit", "org.gnome.TextEditor"],
    monitor: ["utilities-system-monitor", "org.kde.plasma-systemmonitor", "ksysguard", "gnome-system-monitor"],
    launchpad: ["arc-launchpad", "start-here", "applications-all"],
    generic: ["application-x-executable", "applications-other"],
}

INDEX = """[Icon Theme]
Name=arc icons
Comment=Icone di arc UI disegnate in stile macOS (le altre da WhiteSur)
Inherits=WhiteSur-dark,WhiteSur,Papirus-Dark,hicolor
Directories=scalable/apps

[scalable/apps]
Size=128
MinSize=16
MaxSize=512
Type=Scalable
Context=Applications
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, help="cartella di destinazione (es. /usr/share)")
    out = os.path.join(parser.parse_args().out, "icons", "arc-icons")
    shutil.rmtree(out, ignore_errors=True)  # niente icone avanzate da versioni precedenti
    apps = os.path.join(out, "scalable", "apps")
    os.makedirs(apps, exist_ok=True)
    with open(os.path.join(out, "index.theme"), "w", encoding="utf-8") as fh:
        fh.write(INDEX)
    for make, names in ICONS.items():
        svg = make()
        for name in ["arc-" + make.__name__] + names:
            with open(os.path.join(apps, name + ".svg"), "w", encoding="utf-8") as fh:
                fh.write(svg)


if __name__ == "__main__":
    main()
