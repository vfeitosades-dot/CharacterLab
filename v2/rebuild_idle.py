"""Reconstruct Standard Idle motion from its 91 frames, 159 source curves.
Quantized to 0.05 degrees/cm, transferred using the matching Mixamo jump rig.
The source FBX asset itself is not copied.
"""
import base64, struct, zlib, sys
from pathlib import Path
root=Path(sys.argv[1])
dest=root/'assets/idle.fbx'
if dest.exists():
    print('Original idle already present')
    sys.exit(0)
b=(root/'assets/jump.fbx').read_bytes()
version=struct.unpack_from('<I',b,23)[0]
header='<QQQB' if version>=7500 else '<IIIB'
hs=struct.calcsize(header)
fmt={'Y':'h','C':'?','I':'i','L':'q','F':'f','D':'d'}
def read_props(p,n):
    props=[]
    for i in range(n):
        start=p;k=chr(b[p]);p+=1
        if k in fmt:
            f='<'+fmt[k];v=struct.unpack_from(f,b,p)[0];p+=struct.calcsize(f)
        elif k in 'SR':
            length=struct.unpack_from('<I',b,p)[0];p+=4
            v=b[p:p+length];p+=length
            if k=='S':v=v.decode('utf-8','replace')
        elif k in 'fdilbc':
            count,encoding,length=struct.unpack_from('<III',b,p);p+=12
            raw=b[p:p+length];p+=length
            v=(count,encoding,length)
        else:raise ValueError(k)
        props.append([v,b[start:p]])
    return props,p
def parse(p,end):
    nodes=[]
    while p+hs<=end:
        off,n,plen,nlen=struct.unpack_from(header,b,p)
        if not off:return nodes,p+hs
        name=b[p+hs:p+hs+nlen].decode()
        props,cp=read_props(p+hs+nlen,n)
        assert cp==p+hs+nlen+plen
        children,_=parse(cp,off) if cp<off else ([],cp)
        nodes.append([name,props,children,cp<off])
        p=off
    return nodes,p
nodes,footer=parse(27,len(b))
def val(node,i):return node[1][i][0]
def child(node,name):return next(x for x in node[2] if x[0]==name)
def arr(node,kind,values):
    raw=struct.pack('<'+str(len(values))+kind,*values)
    node[1]=[[None,kind.encode()+struct.pack('<III',len(values),0,len(raw))+raw]]
def scalar(node,i,kind,v):
    node[1][i]=[v,kind.encode()+struct.pack('<'+fmt[kind],v)]
objects=next(n[2] for n in nodes if n[0]=='Objects')
connections=next(n[2] for n in nodes if n[0]=='Connections')
byid={val(x,0):x for x in objects}
cn={};layer={};stack={}
for c in connections:
    v=[p[0] for p in c[1]]
    if len(v)<3 or v[1] not in byid or v[2] not in byid:continue
    a,d=byid[v[1]],byid[v[2]]
    if a[0]=='AnimationCurveNode' and d[0]=='Model':cn[v[1]]=(val(d,1).split('\0')[0],v[3])
    elif a[0]=='AnimationCurveNode' and d[0]=='AnimationLayer':layer[v[1]]=v[2]
    elif a[0]=='AnimationLayer' and d[0]=='AnimationStack':stack[v[1]]=val(d,1).split('\0')[0]
curves={}
for c in connections:
    v=[p[0] for p in c[1]]
    if len(v)==4 and v[1] in byid and byid[v[1]][0]=='AnimationCurve' and v[2] in cn:
        curves[(stack.get(layer.get(v[2]),'?'),*cn[v[2]],v[3])]=byid[v[1]]
assert len(curves)==159,len(curves)
raw=zlib.decompress(base64.b64decode("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"))
samples=struct.unpack('<'+str(159*91)+'h',raw)
duration=138558474000
times=[i*1539538600 for i in range(91)]
for index,key in enumerate(sorted(curves)):
    curve=curves[key];q=0;values=[]
    for delta in samples[index*91:(index+1)*91]:
        q=((q+delta+32768)%65536)-32768
        values.append(q/20)
    if key[2]=='Lcl Translation' and key[3]=='d|Y':
        # Offset to the target skeleton height; preserve the source hip motion.
        values=[v+3.41633 for v in values]
    arr(child(curve,'KeyTime'),'l',times)
    arr(child(curve,'KeyValueFloat'),'f',values)
    arr(child(curve,'KeyAttrFlags'),'i',[4])
    arr(child(curve,'KeyAttrDataFloat'),'f',[0.0,0.0,0.0,0.0])
    arr(child(curve,'KeyAttrRefCount'),'i',[91])
for n in objects:
    if n[0]=='AnimationStack' and val(n,1).startswith('mixamo.com'):
        for p in child(n,'Properties70')[2]:
            if val(p,0) in ('LocalStop','ReferenceStop'):scalar(p,4,'L',duration)
for n in nodes:
    if n[0]=='Takes':
        for take in n[2]:
            if take[0]=='Take' and val(take,0)=='mixamo.com':
                for p in take[2]:
                    if p[0] in ('LocalTime','ReferenceTime'):scalar(p,1,'L',duration)
def emit(n,offset):
    name,props,kids,has_children=n
    name=name.encode();payload=b''.join(p[1] for p in props)
    start=offset+hs+len(name)+len(payload)
    parts=[]
    for k in kids:
        v=emit(k,start);parts.append(v);start+=len(v)
    if has_children:parts.append(bytes(hs));start+=hs
    return struct.pack(header,start,len(props),len(payload),len(name))+name+payload+b''.join(parts)
out=bytearray(b[:27])
for n in nodes:out.extend(emit(n,len(out)))
out.extend(bytes(hs))
out.extend(b[footer:])
dest.write_bytes(out)
print('Recovered 159 idle curves, 91 frames each:',len(out))
