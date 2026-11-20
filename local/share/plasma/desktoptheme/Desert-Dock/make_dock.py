#!/usr/bin/env python3
"""Add macOS-dock-style 'south-*' / 'north-*' frame elements (bottom dock + top bar) to a Plasma theme.

Usage: make_dock.py <theme_dir> [radius] [fill] [fill_opacity] [border_opacity]
Re-runnable: removes a previous dock group before adding a new one.
"""
import re, sys
from pathlib import Path

theme = Path(sys.argv[1])
R = int(sys.argv[2]) if len(sys.argv) > 2 else 16          # corner radius / corner piece size
FILL = sys.argv[3] if len(sys.argv) > 3 else "#3a3a40"      # dock tint
FILL_OP = float(sys.argv[4]) if len(sys.argv) > 4 else 0.45  # tint opacity (blurred variant)
BORDER_OP = float(sys.argv[5]) if len(sys.argv) > 5 else 0.20  # thin light rim
MARGIN = 4  # content margins, same as the original theme

# opacity per variant: translucent = blur available, widgets = no blur fallback, solid/opaque = opaque mode
VARIANTS = {
    "translucent/widgets": FILL_OP,
    "widgets": min(1.0, FILL_OP + 0.35),
    "solid/widgets": 0.96,
    "opaque/widgets": 0.96,
}

TOP_R = 10  # top bar (north) corner radius: smaller so it stays a bar, not a pill
EDGES = {"south": R, "north": TOP_R}  # panel edges that get the dock style

_slot = [0]
def pieces(prefix, fill, fop, bop, with_border=True, r=R):
    """Return SVG for a 9-slice rounded frame laid out on a grid at y>=1000 (off the visible canvas)."""
    ox, oy = 0, 1000 + 200 * _slot[0]
    _slot[0] += 1
    # grid: corners r x r; edges/center big enough that KSvg never has to tile them
    # (tiling small pieces leaves visible seams)
    EW, EH = 3000, 96
    x0, x1, x2 = ox, ox + r, ox + r + EW
    y0, y1, y2 = oy, oy + r, oy + r + EH
    f = f'fill="{fill}" fill-opacity="{fop}" stroke="none"'
    # rim is drawn as filled 1px shapes (not strokes) so every piece's bounds stay exactly on the grid
    s = f'fill="#ffffff" fill-opacity="{bop}" stroke="none"'
    q = r - 1
    out = []
    def g(id_, body):
        out.append(f'<g id="{prefix}{id_}">{body}</g>')
    def rim(d):
        return f'<path {s} d="{d}"/>' if with_border else ""
    def rimrect(x, y, w, h):
        return f'<rect {s} x="{x}" y="{y}" width="{w}" height="{h}"/>' if with_border else ""
    # corners: fill path spans the full r x r box so the element bounds are exact
    g("topleft", f'<path {f} d="M{x0},{y1} A{r},{r} 0 0 1 {x1},{y0} L{x1},{y1} Z"/>'
                 + rim(f"M{x0},{y1} A{r},{r} 0 0 1 {x1},{y0} V{y0+1} A{q},{q} 0 0 0 {x0+1},{y1} Z"))
    g("topright", f'<path {f} d="M{x2},{y0} A{r},{r} 0 0 1 {x2+r},{y1} L{x2},{y1} Z"/>'
                  + rim(f"M{x2},{y0} A{r},{r} 0 0 1 {x2+r},{y1} H{x2+r-1} A{q},{q} 0 0 0 {x2},{y0+1} Z"))
    g("bottomleft", f'<path {f} d="M{x0},{y2} L{x1},{y2} L{x1},{y2+r} A{r},{r} 0 0 1 {x0},{y2} Z"/>'
                    + rim(f"M{x1},{y2+r} A{r},{r} 0 0 1 {x0},{y2} H{x0+1} A{q},{q} 0 0 0 {x1},{y2+r-1} Z"))
    g("bottomright", f'<path {f} d="M{x2},{y2} L{x2+r},{y2} A{r},{r} 0 0 1 {x2},{y2+r} Z"/>'
                     + rim(f"M{x2+r},{y2} A{r},{r} 0 0 1 {x2},{y2+r} V{y2+r-1} A{q},{q} 0 0 0 {x2+r-1},{y2} Z"))
    # edges
    g("top", f'<rect {f} x="{x1}" y="{y0}" width="{EW}" height="{r}"/>' + rimrect(x1, y0, EW, 1))
    g("bottom", f'<rect {f} x="{x1}" y="{y2}" width="{EW}" height="{r}"/>' + rimrect(x1, y2+r-1, EW, 1))
    g("left", f'<rect {f} x="{x0}" y="{y1}" width="{r}" height="{EH}"/>' + rimrect(x0, y1, 1, EH))
    g("right", f'<rect {f} x="{x2}" y="{y1}" width="{r}" height="{EH}"/>' + rimrect(x2+r-1, y1, 1, EH))
    out.append(f'<rect id="{prefix}center" {f} x="{x1}" y="{y1}" width="{EW}" height="{EH}"/>')
    return "\n".join(out)

def hints(prefix):
    hx, hy = 3100, 1000 + 200 * _slot[0]
    t = 'fill="#008080" opacity="0.01"'
    m = MARGIN
    return "\n".join([
        f'<rect id="{prefix}hint-top-margin" {t} x="{hx}" y="{hy}" width="{m}" height="{m}"/>',
        f'<rect id="{prefix}hint-bottom-margin" {t} x="{hx}" y="{hy+10}" width="{m}" height="{m}"/>',
        f'<rect id="{prefix}hint-left-margin" {t} x="{hx}" y="{hy+20}" width="{m}" height="{m}"/>',
        f'<rect id="{prefix}hint-right-margin" {t} x="{hx}" y="{hy+30}" width="{m}" height="{m}"/>',
    ])

START, END = "<!-- dock-style:start -->", "<!-- dock-style:end -->"
for rel, fop in VARIANTS.items():
    p = theme / rel / "panel-background.svg"
    if not p.exists():
        continue
    svg = p.read_text()
    svg = re.sub(re.escape(START) + r".*?" + re.escape(END) + r"\n?", "", svg, flags=re.S)
    _slot[0] = 0
    parts = [START, '<g id="dock-style">']
    for edge, r in EDGES.items():
        parts += [
            pieces(f"{edge}-", FILL, fop, BORDER_OP, r=r),
            hints(f"{edge}-"),
            # blur/input mask for the same shape (both naming schemes KSvg may look up)
            pieces(f"{edge}-mask-", "#000000", 1, 0, with_border=False, r=r),
            pieces(f"mask-{edge}-", "#000000", 1, 0, with_border=False, r=r),
        ]
    block = "\n".join(parts + ["</g>", END, ""])
    svg = svg.replace("</svg>", block + "</svg>", 1) if svg.rstrip().endswith("</svg>") else svg
    i = svg.rfind("</svg>")
    if START not in svg:
        svg = svg[:i] + block + svg[i:]
    p.write_text(svg)
    print("patched", p)
