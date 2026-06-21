#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# trs2matrix.py - make a Blender-exported .glb usable by a .model converter
# that only honors node transforms stored as a `matrix`.
#
# Blender's glTF exporter writes each node's transform as separate
# translation / rotation / scale fields. Some PD2 glb->.model converters only
# read a `matrix` field, so they silently flatten every node (especially
# locators/empties, which have no geometry to fall back on) to the origin.
# This rewrites every non-identity node's TRS into an equivalent column-major
# `matrix` so those transforms survive the conversion.
#
# Usage:  python trs2matrix.py  in.glb  out.glb
# Then convert out.glb to .model as usual.
#
# NOTE: for this to position MESHES correctly too, export from Blender WITHOUT
# applying transforms (Object > Apply must NOT have been used) - keep each
# object's position as an object-level transform with local vertex data, the
# same way the original game model is built. Applying transforms bakes meshes
# to world space and destroys empty positions.
# ---------------------------------------------------------------------------
import struct, json, sys

def trs_to_matrix(t, q, s):
    tx, ty, tz = t
    x, y, z, w = q
    sx, sy, sz = s
    r00 = 1 - 2 * (y * y + z * z); r01 = 2 * (x * y - w * z); r02 = 2 * (x * z + w * y)
    r10 = 2 * (x * y + w * z);     r11 = 1 - 2 * (x * x + z * z); r12 = 2 * (y * z - w * x)
    r20 = 2 * (x * z - w * y);     r21 = 2 * (y * z + w * x);     r22 = 1 - 2 * (x * x + y * y)
    # glTF matrices are column-major
    return [r00 * sx, r10 * sx, r20 * sx, 0.0,
            r01 * sy, r11 * sy, r21 * sy, 0.0,
            r02 * sz, r12 * sz, r22 * sz, 0.0,
            tx,       ty,       tz,       1.0]

def main(inp, outp):
    data = open(inp, "rb").read()
    assert data[:4] == b"glTF", "not a binary .glb"
    ver, _ = struct.unpack_from("<II", data, 4)
    off = 12; chunks = []
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunks.append((ctype, data[off + 8:off + 8 + clen])); off += 8 + clen
    jidx = [i for i, (t, _) in enumerate(chunks) if t == 0x4E4F534A][0]
    gltf = json.loads(chunks[jidx][1].decode("utf-8"))
    n = 0
    for node in gltf.get("nodes", []):
        if "matrix" in node:
            continue
        t = node.pop("translation", [0, 0, 0])
        q = node.pop("rotation", [0, 0, 0, 1])
        s = node.pop("scale", [1, 1, 1])
        if t == [0, 0, 0] and q == [0, 0, 0, 1] and s == [1, 1, 1]:
            continue
        node["matrix"] = trs_to_matrix(t, q, s); n += 1
    newjson = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(newjson) % 4:
        newjson += b" "
    chunks[jidx] = (0x4E4F534A, newjson)
    body = b""
    for ctype, cdata in chunks:
        pad = (-len(cdata)) % 4
        cdata = cdata + (b" " * pad if ctype == 0x4E4F534A else b"\x00" * pad)
        body += struct.pack("<II", len(cdata), ctype) + cdata
    open(outp, "wb").write(b"glTF" + struct.pack("<II", ver, 12 + len(body)) + body)
    print("converted %d node(s) TRS->matrix -> %s" % (n, outp))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: python trs2matrix.py in.glb out.glb"); sys.exit(1)
    main(sys.argv[1], sys.argv[2])
