"""Wordmark constructed from geometry (no font). Cap height 100, baseline y=100.
Each letter returns (solids, holes, width) as SVG path strings; build.py unions
the solids and subtracts the holes. `word(text)` lays a string out."""
def P(x,y): return f"{x:.2f} {y:.2f}"
H=100.0; T=20.0; TH=17.0; OV=2.0
def rect(x,y,w,h): return f"M{P(x,y)}h{w:.2f}v{h:.2f}h{-w:.2f}Z"
def ell(cx,cy,rx,ry): return f"M{P(cx-rx,cy)}A{rx:.2f} {ry:.2f} 0 1 0 {P(cx+rx,cy)}A{rx:.2f} {ry:.2f} 0 1 0 {P(cx-rx,cy)}Z"
def O(x):
    w=104; cx=x+w/2; rx,ry=w/2,H/2+OV
    return [ell(cx,H/2,rx,ry)],[ell(cx,H/2,rx-T*1.05,ry-T*0.92)],w
def C(x):
    w=98; cx=x+w/2; rx,ry=w/2,H/2+OV
    return [ell(cx,H/2,rx,ry)],[ell(cx,H/2,rx-T*1.05,ry-T*0.92),rect(cx+6,H/2-19,w,38)],w
def V(x):
    w=94; t=T*1.13; tb=T*0.56
    return [f"M{P(x,0)}L{P(x+t,0)}L{P(x+w/2,H-T*1.3)}L{P(x+w-t,0)}L{P(x+w,0)}L{P(x+w/2+tb,H)}L{P(x+w/2-tb,H)}Z"],[],w
def E(x):
    w=68; return [rect(x,0,T,H),rect(x,0,w,TH),rect(x,H/2-TH/2,w*0.88,TH),rect(x,H-TH,w,TH)],[],w
def R(x):
    w=84; bh=60; ro=bh/2; bx=x+w-ro-4; cy=bh/2
    bowl=f"M{P(x,0)}H{bx:.2f}A{ro:.2f} {ro:.2f} 0 0 1 {P(bx,bh)}H{x:.2f}Z"
    hole=f"M{P(x+T,TH)}H{bx:.2f}A{ro-T:.2f} {cy-TH:.2f} 0 0 1 {P(bx,bh-TH)}H{x+T:.2f}Z"
    leg=f"M{P(x+T+14,bh-TH)}L{P(x+T+14+T*1.15,bh-TH)}L{P(x+w,H)}L{P(x+w-T*1.18,H)}Z"
    return [rect(x,0,T,H),bowl,leg],[hole],w
def D(x):
    w=90; ro=H/2; bx=x+w-ro
    outer=f"M{P(x,0)}H{bx:.2f}A{ro:.2f} {ro+OV/2:.2f} 0 0 1 {P(bx,H)}H{x:.2f}Z"
    hole=f"M{P(x+T,TH)}H{bx:.2f}A{ro-T*1.05:.2f} {H/2-TH:.2f} 0 0 1 {P(bx,H-TH)}H{x+T:.2f}Z"
    return [outer],[hole],w
def A(x):  # round top, like the logo's headband
    w=92; r=w/2; ri=r-T
    d=(f"M{P(x,H)}V{r:.2f}A{r} {r} 0 0 1 {P(x+w,r)}V{H}H{x+w-T:.2f}V{r:.2f}"
       f"A{ri:.2f} {ri:.2f} 0 0 0 {P(x+T,r)}V{H}Z")
    return [d,rect(x+T-1,H*0.6,w-2*T+2,TH)],[],w
def U(x):
    w=90; r=w/2; ri=r-T
    d=(f"M{P(x,0)}V{H-r:.2f}A{r} {r+OV/2:.2f} 0 0 0 {P(x+w,H-r)}V0H{x+w-T:.2f}V{H-r:.2f}"
       f"A{ri:.2f} {ri:.2f} 0 0 1 {P(x+T,H-r)}V0Z")
    return [d],[],w
def N(x):
    w=88; t=T*1.25
    return [rect(x,0,T,H),rect(x+w-T,0,T,H),f"M{P(x,0)}L{P(x+t,0)}L{P(x+w,H)}L{P(x+w-t,H)}Z"],[],w
def Tt(x):
    w=80; return [rect(x,0,w,TH),rect(x+w/2-T/2,0,T,H)],[],w
def S(x, ts=19.0, xs=1.2, a_top=8.0, a_bot=8.0):
    """One stroke along two stacked arcs (the spine is where they meet),
    butt-capped, then widened horizontally so the sides match the stems."""
    import math
    from pathops import Path, LineCap, LineJoin
    from fontTools.svgLib.path import parse_path
    from fontTools.pens.svgPathPen import SVGPathPen
    rc=(H/2+OV-ts/2)/2; c1=H/2-rc; c2=H/2+rc
    def pt(cy,a): return (rc*math.cos(math.radians(a)), cy-rc*math.sin(math.radians(a)))
    s0=pt(c1,a_top); s1=pt(c2,180+a_bot)
    # top: from the right terminal, anticlockwise over the top to the spine;
    # bottom: from the spine, clockwise round the right and under to the left terminal
    d=(f"M{P(*s0)}A{rc:.3f} {rc:.3f} 0 1 0 {P(0,H/2)}"
       f"A{rc:.3f} {rc:.3f} 0 1 1 {P(*s1)}")
    c=Path(); parse_path(d,c.getPen())
    c.stroke(ts, LineCap.BUTT_CAP, LineJoin.ROUND_JOIN, 4)
    w=2*(rc+ts/2)*xs
    c=c.transform(xs,0,0,1,x+w/2,0)
    pen=SVGPathPen(None); c.draw(pen)
    return [pen.getCommands()],[],w
GLYPH={"O":O,"C":C,"V":V,"E":E,"R":R,"D":D,"A":A,"U":U,"N":N,"T":Tt,"S":S}
ROUND=set("OCS")
def gap(a,b):
    if a=="V" or b=="V": return 4 if (a in ROUND or b in ROUND) else 10
    if a in ROUND and b in ROUND: return 8
    if a in ROUND or b in ROUND: return 11
    return 15
SPACE=44
def word(text):
    """List of (solids, holes) per letter, and the total advance width."""
    x=0; out=[]; prev=None
    for ch in text:
        if ch==" ": x+=SPACE; prev=None; continue
        if prev: x+=gap(prev,ch)
        so,ho,w=GLYPH[ch](x); out.append((so,ho)); x+=w; prev=ch
    return out,x
