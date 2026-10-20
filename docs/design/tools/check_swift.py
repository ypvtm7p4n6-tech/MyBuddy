import sys, pathlib
import tree_sitter_swift as tss
from tree_sitter import Language, Parser

lang = Language(tss.language())
parser = Parser(lang)

def errors(node, src, out):
    if node.type == "ERROR" or node.is_missing:
        out.append(node)
        return
    for c in node.children:
        errors(c, src, out)

total = 0
for path in sys.argv[1:]:
    p = pathlib.Path(path)
    files = [p] if p.is_file() else sorted(p.rglob("*.swift"))
    for f in files:
        src = f.read_bytes()
        tree = parser.parse(src)
        errs = []
        errors(tree.root_node, src, errs)
        if errs:
            total += len(errs)
            for n in errs[:6]:
                line = n.start_point[0] + 1
                text = src.splitlines()[line-1].decode("utf8", "replace").strip()
                print(f"{f}:{line}: {'MISSING ' if n.is_missing else 'ERROR '}{n.type} :: {text[:110]}")
        else:
            print(f"ok  {f}")
print("TOTAL ERROR NODES:", total)
