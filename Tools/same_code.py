"""Check that two versions of the addon/tools differ only in comments and docstrings.

Usage:  python -I same_code.py <old folder> <new folder> [file ...]

For .lua files both versions are tokenized with comments dropped; for .py files the syntax trees are compared with
docstrings dropped. Prints every file whose code changed.
"""
import ast
import os
import re
import sys

LUA_TOKEN = re.compile(r"""
    (?P<long>\[(?P<eq>=*)\[.*?\](?P=eq)\])
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<num>0[xX][0-9a-fA-F.]+(?:[pP][+-]?\d+)?|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|\.\.|==|~=|<=|>=|::|//|<<|>>|[-+*/%^#&~|<>=(){}\[\];:,.])
  | (?P<ws>\s+)
""", re.S | re.X)
LONG_COMMENT = re.compile(r"--\[(=*)\[.*?\]\1\]", re.S)


def lua_tokens(text):
    out, i = [], 0
    while i < len(text):
        if text.startswith("--", i):
            m = LONG_COMMENT.match(text, i)
            if m:
                i = m.end()
            else:
                j = text.find("\n", i)
                i = len(text) if j < 0 else j
            continue
        m = LUA_TOKEN.match(text, i)
        if not m:
            raise ValueError("can't read Lua at offset %d: %r" % (i, text[i:i + 20]))
        if not m.group("ws"):
            out.append(m.group(0))
        i = m.end()
    return out


def py_tree(text):
    tree = ast.parse(text)
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if isinstance(body, list) and body and isinstance(body[0], ast.Expr) \
                and isinstance(getattr(body[0], "value", None), ast.Constant) and isinstance(body[0].value.value, str):
            node.body = body[1:] or [ast.Pass()]
    return ast.dump(tree, include_attributes=False)


def same(old, new):
    with open(old, "rb") as fh:
        ra = fh.read()
    with open(new, "rb") as fh:
        rb = fh.read()
    if ra.startswith(b"\xef\xbb\xbf") != rb.startswith(b"\xef\xbb\xbf") or (b"\r\n" in ra) != (b"\r\n" in rb):
        print("  byte-order mark or line endings changed:", os.path.basename(new))
        return False
    a, b = ra.decode("utf-8-sig"), rb.decode("utf-8-sig")
    if old.endswith(".lua"):
        return lua_tokens(a) == lua_tokens(b)
    if old.endswith(".py"):
        return py_tree(a) == py_tree(b)
    return a == b


def main():
    old_dir, new_dir, names = sys.argv[1], sys.argv[2], sys.argv[3:]
    if not names:
        names = sorted(n for n in os.listdir(old_dir) if n.endswith((".lua", ".py", ".toc")))
    bad = 0
    for n in names:
        o, w = os.path.join(old_dir, n), os.path.join(new_dir, n)
        if not os.path.exists(w):
            print("MISSING", n)
            bad += 1
        elif not same(o, w):
            print("CODE CHANGED", n)
            bad += 1
    print("%d file(s) checked, %d with code changes" % (len(names), bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
