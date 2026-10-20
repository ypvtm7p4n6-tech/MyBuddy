import sys, pathlib
import tree_sitter_swift as tss
from tree_sitter import Language, Parser
lang = Language(tss.language()); parser = Parser(lang)
def walk(n):
    yield n
    for c in n.children:
        yield from walk(c)
for path in sys.argv[1:]:
    src = pathlib.Path(path).read_bytes()
    tree = parser.parse(src)
    for n in walk(tree.root_node):
        if n.type == "lambda_literal":
            stm = [c for c in n.children if c.type == "statements"]
            if not stm: continue
            kids = [c for c in stm[0].children if c.is_named and c.type not in ("comment","multiline_comment","property_declaration")]
            if len(kids) > 9:
                print(f"{path}:{n.start_point[0]+1}: {len(kids)} statements")
