"""Decode the QuestieDB Forever baked TOC metadata store into plain JSON.

Usage: python -I decode_questiedb.py <QuestieDB-Forever.zip> <out_dir>

Values are `## X-<Entity>-<id>-<field or S>: <base64 CBOR>`, `X-<Entity>-IDS` is base64 zlib CBOR,
`~N~` means chunked into `<key>-1..N`.
"""
import base64
import json
import os
import re
import struct
import sys
import zipfile
import zlib


class CBOR:
    def __init__(self, data):
        self.d = data
        self.i = 0

    def byte(self):
        b = self.d[self.i]
        self.i += 1
        return b

    def arg(self, info):
        if info < 24:
            return info
        n = {24: 1, 25: 2, 26: 4, 27: 8}[info]
        v = int.from_bytes(self.d[self.i:self.i + n], "big")
        self.i += n
        return v

    def item(self):
        ib = self.byte()
        major, info = ib >> 5, ib & 31
        if major == 0:
            return self.arg(info)
        if major == 1:
            return -1 - self.arg(info)
        if major in (2, 3):
            n = self.arg(info)
            s = self.d[self.i:self.i + n]
            self.i += n
            return s.decode("utf-8", "replace") if major == 3 else s.decode("latin-1")
        if major == 4:
            n = self.arg(info)
            return [self.item() for _ in range(n)]
        if major == 5:
            n = self.arg(info)
            out = {}
            for _ in range(n):
                k = self.item()
                out[k] = self.item()
            return out
        if major == 6:
            self.arg(info)
            return self.item()
        if major == 7:
            if info == 20:
                return False
            if info == 21:
                return True
            if info in (22, 23):
                return None
            if info == 25:
                h = int.from_bytes(self.d[self.i:self.i + 2], "big")
                self.i += 2
                return struct.unpack(">e", h.to_bytes(2, "big"))[0]
            if info == 26:
                v = struct.unpack(">f", self.d[self.i:self.i + 4])[0]
                self.i += 4
                return v
            if info == 27:
                v = struct.unpack(">d", self.d[self.i:self.i + 8])[0]
                self.i += 8
                return v
            return None
        raise ValueError("bad cbor major %d" % major)


def cbor(data):
    return CBOR(data).item()


def jsonable(v):
    if isinstance(v, dict):
        return {str(k): jsonable(x) for k, x in v.items()}
    if isinstance(v, list):
        return [jsonable(x) for x in v]
    if isinstance(v, float) and v.is_integer() and abs(v) < 2**53:
        return v  # keep floats (coords)
    return v


def load_names(meta_src):
    m = re.search(r"names\s*=\s*\{(.*?)\}", meta_src, re.S)
    return {int(a): b for a, b in re.findall(r"\[(\d+)\]='(\w+)'", m.group(1))}


def main():
    zpath, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    z = zipfile.ZipFile(zpath)
    toc_name = [n for n in z.namelist() if n.endswith("QuestieDB_Forever.toc")][0]
    store = {}
    for line in z.read(toc_name).decode("utf-8", "replace").splitlines():
        if line.startswith("## X-"):
            k, _, v = line[3:].partition(":")
            store[k.strip()] = v.strip()

    def get(key):
        v = store.get(key)
        if v and v.startswith("~"):
            m = re.match(r"^~(\d+)~$", v)
            if m:
                v = "".join(store[key + "-" + str(i)] for i in range(1, int(m.group(1)) + 1))
        return v

    for ent, meta in (("Quest", "questMeta"), ("Npc", "npcMeta"), ("Object", "objectMeta"), ("Item", "itemMeta")):
        names = load_names(z.read("QuestieDB/src/meta/%s.lua" % meta).decode())
        prefix = "X-%s-" % ent
        ids = cbor(zlib.decompress(base64.b64decode(get(prefix + "IDS"))))
        result = {}
        for eid in ids:
            row = {}
            srow = get("%s%d-S" % (prefix, eid))
            if srow:
                sc = cbor(base64.b64decode(srow))
                items = sc.items() if isinstance(sc, dict) else enumerate(sc, 1)
                for k, v in items:
                    if isinstance(k, int) and k in names:
                        row[names[k]] = v
            for f, fname in names.items():
                raw = get("%s%d-%d" % (prefix, eid, f))
                if raw:
                    row[fname] = jsonable(cbor(base64.b64decode(raw)))
            result[str(eid)] = row
        with open(os.path.join(out, ent.lower() + "s.json"), "w", encoding="utf-8") as fh:
            json.dump(result, fh, ensure_ascii=False)
        print(ent, len(result))


if __name__ == "__main__":
    main()
