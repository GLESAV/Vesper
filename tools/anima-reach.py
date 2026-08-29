"""A faithful port of AnimaFigure.restReach, for verifying an asset batch
BEFORE it costs a CI cycle.

WHY THIS EXISTS. Phase A batches are verified against two gates: no two pops
in a family may sit on top of each other in the variation plane, and a
family's silhouettes must span a real range of extents. Both need the same
number Swift computes, and Swift cannot be run where the authoring happens.

WHY IT IS A PORT AND NOT AN ESTIMATE. The first four batches were checked
against an analytic guess -- "a part's furthest point is |offset| + scale" --
which assumes a primitive's extreme lies along its offset direction. For a
limacen petal that is exactly backwards: its fat end is at local theta = pi.
The guess reported bloom's spread as 0.286 when the truth was 0.000, and it
was wrong for three of the four families it was used on. It hid a real
rendering defect (petals pointing inward) behind a plausible number.

So this samples outlines and walks the transform stack, as the engine does.
It is a DEVELOPMENT TOOL, not a second implementation of anything shipped:
nothing imports it, and the Swift tests remain the authority.
"""

import math
S = 64
def outline(kind, **kw):
    def ring(f):
        return [(max(1e-4,f(2*math.pi*i/S))*math.cos(2*math.pi*i/S),
                 max(1e-4,f(2*math.pi*i/S))*math.sin(2*math.pi*i/S)) for i in range(S)]
    if kind=='disc': return ring(lambda t: 1.0)
    if kind=='petal':
        s=min(max(kw['sharpness'],0),1); peak=1+s
        return ring(lambda t:(1-s*math.cos(t))/peak)
    if kind=='polygon':
        n=max(3,kw['sides']); r=min(max(kw['roundness'],0),1)
        step=2*math.pi/n; inr=math.cos(math.pi/n)
        def f(t):
            ph=t%step
            return (inr/math.cos(ph-step/2))*(1-r)+r
        return ring(f)
    if kind=='capsule':
        h=max(0,kw['length'])/2; half=S//2; pts=[]
        for i in range(half+1):
            a=-math.pi/2+math.pi*i/half; pts.append((h+math.cos(a), math.sin(a)))
        for i in range(half+1):
            a= math.pi/2+math.pi*i/half; pts.append((-h+math.cos(a), math.sin(a)))
        return pts
    if kind=='arc':
        sw=min(max(kw['sweep'],0.05),2*math.pi); th=min(max(kw['thickness'],0.02),1)
        outer,inner=1.0,max(0.01,1-th); st=max(6,S//2); pts=[]
        for i in range(st+1):
            a=-sw/2+sw*i/st; pts.append((outer*math.cos(a),outer*math.sin(a)))
        for i in range(st+1):
            a= sw/2-sw*i/st; pts.append((inner*math.cos(a),inner*math.sin(a)))
        return pts
    if kind=='ribbon':
        sp=kw['spine']; w=max(0.005,kw['width']/2)
        def nrm(i):
            b=sp[max(0,i-1)]; a=sp[min(len(sp)-1,i+1)]
            dx,dy=a[0]-b[0],a[1]-b[1]; L=math.hypot(dx,dy)
            return (0,1) if L<1e-4 else (-dy/L,dx/L)
        pts=[(sp[i][0]+nrm(i)[0]*w, sp[i][1]+nrm(i)[1]*w) for i in range(len(sp))]
        pts+=[(sp[i][0]-nrm(i)[0]*w, sp[i][1]-nrm(i)[1]*w) for i in range(len(sp)-1,-1,-1)]
        return pts
    raise ValueError(kind)

class T:
    def __init__(s,off=(0,0),rot=0.0,sc=1.0,sq=0.0):
        s.off=off; s.rot=rot; s.sc=sc; s.sq=sq
    def axes(s):
        k=math.exp(min(max(s.sq,-1),1)); return (s.sc*k, s.sc/k)
    def apply(s,p):
        sx,sy=s.axes(); x=p[0]*sx; y=p[1]*sy
        c,si=math.cos(s.rot),math.sin(s.rot)
        return (x*c-y*si+s.off[0], x*si+y*c+s.off[1])
    def under(s,parent):
        o=parent.apply(s.off)
        return T(o, parent.rot+s.rot, parent.sc*s.sc, parent.sq+s.sq)

def world_rest(parts, name):
    by={p['name']:p for p in parts}
    chain=[]; cur=name; guard=0
    while cur is not None and guard<len(parts):
        p=by[cur]; chain.append(p['rest']); cur=p.get('parent'); guard+=1
    out=T()
    for t in reversed(chain): out=t.under(out)
    return out

def rest_reach(parts):
    f=1.0
    for p in parts:
        w=world_rest(parts,p['name'])
        for q in outline(p['kind'],**p['args']):
            x,y=w.apply(q); f=max(f, math.hypot(x,y))
    return f
