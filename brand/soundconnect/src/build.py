"""Overear brand kit: master geometry with real boolean cut-outs (skia-pathops).

Run with a Python that has skia-pathops and fontTools:  python build.py
Everything is written to ../svg and ../png.
"""
import math, os
from pathops import Path, op, PathOp
from fontTools.pens.svgPathPen import SVGPathPen

HERE=os.path.dirname(os.path.abspath(__file__))
OUT_SVG=os.path.join(HERE,"..","svg"); os.makedirs(OUT_SVG,exist_ok=True)

BRAND="Sound Connect"; SLUG="soundconnect"
ORANGE="#FF5A1F"; PEACH="#FFD6C2"; INK="#1A1A1A"; PAPER="#FFF6F1"; NIGHT="#161616"
K=0.5522847498

def circle(cx,cy,r):
    p=Path(); pen=p.getPen()
    pen.moveTo((cx+r,cy))
    pen.curveTo((cx+r,cy+K*r),(cx+K*r,cy+r),(cx,cy+r))
    pen.curveTo((cx-K*r,cy+r),(cx-r,cy+K*r),(cx-r,cy))
    pen.curveTo((cx-r,cy-K*r),(cx-K*r,cy-r),(cx,cy-r))
    pen.curveTo((cx+K*r,cy-r),(cx+r,cy-K*r),(cx+r,cy))
    pen.closePath(); return p
def rect(x0,y0,x1,y1):
    p=Path(); pen=p.getPen()
    pen.moveTo((x0,y0)); pen.lineTo((x1,y0)); pen.lineTo((x1,y1)); pen.lineTo((x0,y1)); pen.closePath(); return p
def U(*ps):
    r=ps[0]
    for q in ps[1:]: r=op(r,q,PathOp.UNION)
    return r
def D(a,b): return op(a,b,PathOp.DIFFERENCE)
def I(a,b): return op(a,b,PathOp.INTERSECTION)
def capsule(x0,x1,cy,r): return U(rect(x0,cy-r,x1,cy+r),circle(x0,cy,r),circle(x1,cy,r))
def xf(p,m):
    a,b,c,d,e,f=m; return p.transform(a,b,c,d,e,f)
def mul(m1,m2):  # m1 ∘ m2 (apply m2 first)
    a1,b1,c1,d1,e1,f1=m1; a2,b2,c2,d2,e2,f2=m2
    return (a1*a2+c1*b2, b1*a2+d1*b2, a1*c2+c1*d2, b1*c2+d1*d2, a1*e2+c1*f2+e1, b1*e2+d1*f2+f1)
def rot(deg,cx,cy):
    t=math.radians(deg); c,s=math.cos(t),math.sin(t)
    return (c,s,-s,c,cx-c*cx+s*cy,cy-s*cx-c*cy)
def tr(dx,dy): return (1,0,0,1,dx,dy)
def sc(s): return (s,0,0,s,0,0)
def d_of(p):
    pen=SVGPathPen(None); p.draw(pen); return pen.getCommands()
def bounds(p): return p.bounds

# ---- master geometry (256 canvas), before tilt ----
CY=152; T=74; R=T/2
SW_X0,SW_X1=64,192
BAND_RO,BAND_RI=100,54
KNOB_R=R-9

def parts(gap=0.0, knob_r=KNOB_R, band_ri=None, hole=False):
    """Band, switch, knob. The band's feet end 12 above the switch's centre
    line, so they always finish hidden behind it (no slivers). `gap` opens a
    clear space between band and switch (one-colour use); `hole` cuts the knob
    out of the switch instead of drawing it."""
    ri=BAND_RI if band_ri is None else band_ri
    band=I(D(circle(128,CY,BAND_RO),circle(128,CY,ri)), rect(0,0,256,CY-12))
    sw=capsule(SW_X0,SW_X1,CY,R)
    knob=circle(SW_X1,CY,knob_r)
    band_vis=D(band, capsule(SW_X0,SW_X1,CY,R+gap)) if gap>0 else D(band,sw)
    sw_vis=D(sw,knob)
    return band_vis, sw_vis, (None if hole else knob)

TILT=mul(rot(-40,128,128),tr(0,-10))
def placed(ps, size=256, fill=0.78, optical=-0.012):
    allp=U(*[xf(p,TILT) for p in ps])
    x0,y0,x1,y1=bounds(allp); w,h=x1-x0,y1-y0
    s=fill*size/max(w,h)
    m=mul(tr(size/2-(x0+w/2)*s, size*(0.5+optical)-(y0+h/2)*s), sc(s))
    return [xf(xf(p,TILT),m) for p in ps]

def svg(name, body, vb="0 0 256 256", title=None):
    title=title or BRAND
    open(os.path.join(OUT_SVG,name.replace("overear",SLUG)),"w").write(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}"><title>{title}</title>{body}</svg>\n')

# Symbol, full colour (layers do not overlap: each shape is cut by the one above)
b,s,k=placed(list(parts()))
svg("overear-symbol.svg",f'<path d="{d_of(b)}" fill="{PEACH}"/><path d="{d_of(s)}" fill="{ORANGE}"/><path d="{d_of(k)}" fill="{INK}"/>')
# On dark: peach band dims to a warm grey so the switch leads
svg("overear-symbol-on-dark.svg",f'<path d="{d_of(b)}" fill="#5A4038"/><path d="{d_of(s)}" fill="{ORANGE}"/><path d="{d_of(k)}" fill="{INK}"/>')

# One colour: a clear gap between band and switch; the knob is cut out.
bm,sm,_=parts(gap=9, hole=True)
bm,sm=placed([bm,sm])
mono=d_of(U(bm,sm))
svg("overear-symbol-mono-black.svg",f'<path d="{mono}" fill="{INK}"/>')
svg("overear-symbol-mono-white.svg",f'<path d="{mono}" fill="#FFFFFF"/>')
svg("overear-symbol-mono-orange.svg",f'<path d="{mono}" fill="{ORANGE}"/>')
# Small-size cut (≤ 32 px, menu bar): thinner band with a wider opening, a
# wider gap and a larger knob, so the shapes stay apart at 16-18 px.
bs,ss,_=parts(gap=15, hole=True, band_ri=64, knob_r=KNOB_R+2)
bs,ss=placed([bs,ss], fill=0.9, optical=0)
small=d_of(U(bs,ss))
svg("overear-symbol-small.svg",f'<path d="{small}" fill="{INK}"/>')
bsc,ssc,ksc=parts(gap=0, band_ri=64, knob_r=KNOB_R+2)
bsc,ssc,ksc=placed([bsc,ssc,ksc], fill=0.9, optical=0)
svg("overear-symbol-small-colour.svg",f'<path d="{d_of(bsc)}" fill="{PEACH}"/><path d="{d_of(ssc)}" fill="{ORANGE}"/><path d="{d_of(ksc)}" fill="{INK}"/>')

# App icons (1024): macOS grid — 824 body at 100, radius 185
def icon(name, bg, band_fill, edge):
    b2,s2,k2=placed(list(parts()), size=824, fill=0.70, optical=-0.01)
    g=f'<g transform="translate(100 100)"><path d="{d_of(b2)}" fill="{band_fill}"/><path d="{d_of(s2)}" fill="{ORANGE}"/><path d="{d_of(k2)}" fill="{INK}"/></g>'
    svg(name,f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{bg}"/>{g}'
        f'<rect x="100.5" y="100.5" width="823" height="823" rx="184.5" fill="none" stroke="{edge}" stroke-width="1"/>', vb="0 0 1024 1024")
icon("overear-appicon-light.svg", PAPER, PEACH, "#000000\" stroke-opacity=\".06")
icon("overear-appicon-dark.svg", NIGHT, "#5A4038", "#FFFFFF\" stroke-opacity=\".12")
print("symbols and icons written")

# ---- Wordmark and lockups ----
import sys; sys.path.insert(0,HERE)
from wordmark import word, H as CAP
from fontTools.svgLib.path import parse_path
def from_d(d):
    p=Path(); parse_path(d,p.getPen()); return p
def letter_path(solids,holes):
    r=U(*[from_d(d) for d in solids])
    for h in holes: r=D(r,from_d(h))
    return r
letters,ww=word(BRAND.upper())
wd=d_of(U(*[letter_path(so,ho) for so,ho in letters]))
# nonzero fill; counters are drawn with opposite winding
svg("overear-wordmark.svg",f'<path d="{wd}" fill="{INK}"/>', vb=f"-10 -12 {ww+20:.1f} {CAP+24:.1f}")
svg("overear-wordmark-white.svg",f'<path d="{wd}" fill="#FFFFFF"/>', vb=f"-10 -12 {ww+20:.1f} {CAP+24:.1f}")

def symbol_group(scale, dx, dy, mono=None, on_dark=False):
    if mono:
        bm,sm,_=parts(gap=9, hole=True); bm,sm=placed([bm,sm])
        inner=f'<path d="{d_of(U(bm,sm))}" fill="{mono}"/>'
    else:
        b,s,k=placed(list(parts()))
        inner=(f'<path d="{d_of(b)}" fill="{"#5A4038" if on_dark else PEACH}"/>'
               f'<path d="{d_of(s)}" fill="{ORANGE}"/><path d="{d_of(k)}" fill="{INK}"/>')
    return f'<g transform="translate({dx:.2f} {dy:.2f}) scale({scale:.4f})">{inner}</g>'

# The symbol's drawn box inside its 256 canvas
b,s,k=placed(list(parts())); x0,y0,x1,y1=bounds(U(b,s,k))
sym_h=y1-y0; sym_w=x1-x0
# Horizontal: symbol 1.7 × cap height, centred on the caps; gap = 0.55 cap
hs=1.45*CAP/sym_h; gap=0.55*CAP
sx=-x0*hs; sy=CAP/2-(y0+sym_h/2)*hs
tx=sym_w*hs+gap
W=tx+ww; top=min(sy+y0*hs,0); bot=max(sy+y1*hs,CAP)
def lockup_h(name, word_fill, mono=None, on_dark=False, bg=None):
    pad=24
    body=(f'<rect x="{-pad}" y="{top-pad:.1f}" width="{W+2*pad:.1f}" height="{bot-top+2*pad:.1f}" fill="{bg}"/>' if bg else "")
    body+=symbol_group(hs,sx,sy,mono,on_dark)+f'<g transform="translate({tx:.2f} 0)"><path d="{wd}" fill="{word_fill}"/></g>'
    svg(name, body, vb=f"{-pad} {top-pad:.1f} {W+2*pad:.1f} {bot-top+2*pad:.1f}")
lockup_h("overear-lockup-horizontal.svg", INK)
lockup_h("overear-lockup-horizontal-dark.svg", "#FFFFFF", on_dark=True, bg=NIGHT)
lockup_h("overear-lockup-horizontal-on-dark.svg", "#FFFFFF", on_dark=True)  # transparent, for dark pages
lockup_h("overear-lockup-horizontal-mono.svg", INK, mono=INK)

# Stacked: symbol 3 × cap height above the word, centred
ss_=3.2*CAP/sym_h; sw_=sym_w*ss_
sxs=(ww-sw_)/2-x0*ss_; sys_=-y0*ss_
wy=sym_h*ss_+0.6*CAP
svg("overear-lockup-stacked.svg", symbol_group(ss_,sxs,sys_)+f'<g transform="translate(0 {wy:.2f})"><path d="{wd}" fill="{INK}"/></g>',
    vb=f"-24 -24 {ww+48:.1f} {wy+CAP+48:.1f}")
print("wordmark and lockups written")

# Full-bleed square (iOS / Android / apple-touch-icon: the system applies the mask)
b3,s3,k3=placed(list(parts()), size=1024, fill=0.62, optical=-0.01)
svg("overear-appicon-fullbleed.svg",f'<rect width="1024" height="1024" fill="{PAPER}"/>'
    f'<path d="{d_of(b3)}" fill="{PEACH}"/><path d="{d_of(s3)}" fill="{ORANGE}"/><path d="{d_of(k3)}" fill="{INK}"/>', vb="0 0 1024 1024")
print("full-bleed icon written")
