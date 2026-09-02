"""Twelve curl-pattern references in the kit's line language: ink strokes on
the tile's own milk, no fills, round caps. One generator so the twelve share
one hand — the same stroke weight ramp, the same margins, the same three
strands growing to five as the pattern packs tighter."""
import math, os
W = H = 120
INK = "#1B1917"
TOP, BOT = 14, 106

def poly(points):
    return "M " + " L ".join(f"{x:.2f} {y:.2f}" for x, y in points)

def smooth(points):
    # catmull-rom -> cubic bezier, so waves and loops read as drawn, not plotted
    if len(points) < 3: return poly(points)
    d = f"M {points[0][0]:.2f} {points[0][1]:.2f}"
    for i in range(len(points) - 1):
        p0 = points[i - 1] if i > 0 else points[i]
        p1, p2 = points[i], points[i + 1]
        p3 = points[i + 2] if i + 2 < len(points) else p2
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f" C {c1[0]:.2f} {c1[1]:.2f} {c2[0]:.2f} {c2[1]:.2f} {p2[0]:.2f} {p2[1]:.2f}"
    return d

def straight(cx, bend=0.0, flick=0.0):
    pts = []
    for i in range(0, 41):
        t = i / 40
        y = TOP + (BOT - TOP) * t
        x = cx + bend * (t ** 3) * 10 + flick * math.sin(t * math.pi) * 2
        pts.append((x, y))
    return smooth(pts)

def wave(cx, amp, periods, phase=0.0):
    pts = []
    for i in range(0, 61):
        t = i / 60
        y = TOP + (BOT - TOP) * t
        x = cx + amp * math.sin(2 * math.pi * periods * t + phase)
        pts.append((x, y))
    return smooth(pts)

def loops(cx, r, k, phase=0.0):
    # prolate cycloid: loops when k < r; tighter as r shrinks
    pts = []
    t = 0.0
    while True:
        x = cx + r * math.cos(t + phase)
        y = TOP + k * t + r * math.sin(t + phase) - r
        if y > BOT: break
        pts.append((x, y))
        t += 0.35
    return smooth(pts)

def zigzag(cx, amp, period, phase=0.0):
    pts = []
    y = TOP
    i = 0
    while y <= BOT:
        x = cx + (amp if (i + phase) % 2 == 0 else -amp)
        pts.append((x, y))
        y += period
        i += 1
    return poly(pts)

def spread(n, width=44):
    if n == 1: return [W / 2]
    return [W / 2 - width / 2 + width * i / (n - 1) for i in range(n)]

patterns = {
    "1a": dict(sw=1.6, strands=[straight(cx) for cx in spread(3, 36)]),
    "1b": dict(sw=2.1, strands=[straight(cx, bend=0.5 * (i - 1)) for i, cx in enumerate(spread(3, 38))]),
    "1c": dict(sw=2.6, strands=[straight(cx, bend=0.9 * (i - 1), flick=0.8) for i, cx in enumerate(spread(3, 40))]),
    "2a": dict(sw=2.1, strands=[wave(cx, 4, 1.25, i * 0.5) for i, cx in enumerate(spread(3, 40))]),
    "2b": dict(sw=2.1, strands=[wave(cx, 6.5, 1.75, i * 0.6) for i, cx in enumerate(spread(3, 42))]),
    "2c": dict(sw=2.4, strands=[wave(cx, 8.5, 2.25, i * 0.7) for i, cx in enumerate(spread(3, 46))]),
    "3a": dict(sw=2.1, strands=[loops(cx, 8.5, 5.2, i * 1.1) for i, cx in enumerate(spread(3, 50))]),
    "3b": dict(sw=2.1, strands=[loops(cx, 7, 4.0, i * 1.3) for i, cx in enumerate(spread(3, 48))]),
    "3c": dict(sw=2.1, strands=[loops(cx, 5.5, 3.0, i * 1.5) for i, cx in enumerate(spread(4, 52))]),
    "4a": dict(sw=2.0, strands=[loops(cx, 4, 2.2, i * 1.7) for i, cx in enumerate(spread(4, 54))]),
    "4b": dict(sw=2.0, strands=[zigzag(cx, 4.5, 7, i) for i, cx in enumerate(spread(4, 54))]),
    "4c": dict(sw=1.9, strands=[zigzag(cx, 3.2, 4.5, i) for i, cx in enumerate(spread(5, 60))]),
}

os.makedirs("svg", exist_ok=True)
for code, p in patterns.items():
    paths = "\n".join(
        f'  <path d="{d}" opacity="{[1, 0.82, 0.92, 0.76, 0.86][i % 5]}"/>' for i, d in enumerate(p["strands"])
    )
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">
<g fill="none" stroke="{INK}" stroke-width="{p["sw"]}" stroke-linecap="round" stroke-linejoin="round">
{paths}
</g>
</svg>
'''
    open(f"svg/hair-{code}.svg", "w").write(svg)

tiles = "".join(
    f'<figure><div class="tile"><img src="svg/hair-{c}.svg"></div><figcaption>{c}</figcaption></figure>'
    for c in patterns
)
open("sheet.html", "w").write(f'''<!doctype html><meta charset="utf-8">
<style>body{{background:#EFEDE7;font:12px "Space Mono",monospace;color:#1B1917;padding:24px}}
.grid{{display:grid;grid-template-columns:repeat(3,120px);gap:16px 24px}}
figure{{margin:0;text-align:center}}
.tile{{background:#FFFFFF;border:1px solid #DED9CF;border-radius:12px;width:120px;height:120px;overflow:hidden}}
img{{width:120px;height:120px;display:block}}</style>
<div class="grid">{tiles}</div>''')
print("wrote", len(patterns))
