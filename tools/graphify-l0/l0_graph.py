"""The L0 sources as a graphify extraction: nodes and edges, no LLM.

graphify does not know .l0 files, so this reads them itself. A node for
each file, each top-level (def NAME ...) and each (data NAME ...); edges
from a file to what it defines, from a def to the defs it calls
(head position) or names as a value, to the types it names, and to the
type of each constructor it uses.

L0 has no modules: a name is the one definition linked with it. Here a
name resolves to the same file's, else the one in the same directory,
else the only one outside the tests. Any other name is dropped and
counted, never guessed. Parameters, let names and the variables a match
pattern binds shadow globals, so they are not references.
"""
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path


def l0_files(root):
    """The repository's .l0 files, relative to root, as git knows them,
    less any deleted since."""
    out = subprocess.run(['git', 'ls-files', '*.l0'], cwd=root,
                         capture_output=True, text=True, check=True).stdout
    return [f for f in out.split() if (Path(root) / f).is_file()]


def norm(s):
    """s as graphify writes an id's part: lower case, [a-z0-9_]."""
    return re.sub(r'[^a-z0-9]', '_', s.lower())


def stem_id(rel):
    """A file's node id: its path without the extension, every part kept."""
    return '_'.join(norm(p) for p in Path(rel).with_suffix('').parts)


def tokenize(text):
    """(kind, symbol, line) for each paren, symbol and string of text."""
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == '\n':
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif c == ';':
            j = text.find('\n', i)
            i = n if j < 0 else j
        elif c == '"':
            i += 1
            while i < n and text[i] != '"':
                if text[i] == '\\':
                    i += 1
                if i < n and text[i] == '\n':
                    line += 1
                i += 1
            i += 1
            yield ('str', None, line)
        elif c in '()':
            yield (c, None, line)
            i += 1
        else:
            j = i
            while j < n and not text[j].isspace() and text[j] not in '();"':
                j += 1
            yield ('sym', text[i:j], line)
            i = j


def parse(text):
    """The top-level forms of text. A form is a list whose first item is
    ('__line', N), its line; a symbol is a (name, line) tuple."""
    stack = [[]]
    for kind, val, line in tokenize(text):
        if kind == '(':
            stack.append([('__line', line)])
        elif kind == ')':
            if len(stack) > 1:
                form = stack.pop()
                stack[-1].append(form)
        elif kind == 'sym':
            stack[-1].append((val, line))
    return stack[0]


def is_leaf(x):
    """Whether x is a symbol rather than a form."""
    return isinstance(x, tuple)


def doc_above(lines, line):
    """The ; block directly above line (1-based), as one string."""
    out = []
    k = line - 2
    while k >= 0 and lines[k].startswith(';'):
        out.append(lines[k].lstrip('; ').rstrip())
        k -= 1
    return ' '.join(reversed(out)).strip()


def edge(src, tgt, relation, rel, line):
    """An extracted edge as graphify takes it."""
    return {'source': src, 'target': tgt, 'relation': relation,
            'confidence': 'EXTRACTED', 'confidence_score': 1.0,
            'source_file': rel, 'source_location': f'L{line}',
            'weight': 1.0, '_origin': 'ast'}


def extract(root, files=None):
    """The extraction of the .l0 files under root (all git knows, unless
    files names them): {'nodes', 'edges', 'stats'}."""
    root = Path(root)
    files = l0_files(root) if files is None else files
    nodes, edges = [], []
    where = {}                      # node id -> its file
    kinds = {}                      # node id -> 'def' or 'data'
    by_name = defaultdict(list)     # def or type name -> node ids
    ctor_by_name = defaultdict(list)  # constructor name -> its type's ids
    bodies = []                     # (node id, file, the form's rest)

    for rel in files:
        text = (root / rel).read_text(encoding='utf-8', errors='replace')
        lines = text.splitlines()
        fid = stem_id(rel)
        summary = lines[0].lstrip('; ').strip() if lines and lines[0].startswith(';') else ''
        nodes.append({'id': fid, 'label': Path(rel).name, 'file_type': 'code',
                      'source_file': rel, 'source_location': 'L1', '_origin': 'ast',
                      'metadata': {'language': 'l0', 'summary': summary}})
        for form in parse(text):
            if is_leaf(form) or len(form) < 3 or not is_leaf(form[1]) or not is_leaf(form[2]):
                continue
            kw, name, line = form[1][0], form[2][0], form[0][1]
            if kw not in ('def', 'data'):
                continue
            nid = f'{fid}_{norm(name)}'
            if nid in where:
                continue
            where[nid] = rel
            kinds[nid] = kw
            by_name[name].append(nid)
            node = {'id': nid, 'label': name + '()' if kw == 'def' else name,
                    'file_type': 'code', 'source_file': rel,
                    'source_location': f'L{line}', '_origin': 'ast',
                    'metadata': {'language': 'l0', 'kind': kw}}
            doc = doc_above(lines, line)
            if doc:
                node['rationale'] = doc[:400]
            nodes.append(node)
            edges.append(edge(fid, nid, 'contains' if kw == 'def' else 'defines', rel, line))
            if kw == 'data':
                for ctor in form[3:]:
                    if not is_leaf(ctor) and len(ctor) > 1 and is_leaf(ctor[1]):
                        ctor_by_name[ctor[1][0]].append(nid)
            bodies.append((nid, rel, list(form[3:])))

    def resolve(name, rel, table):
        """The node name means in rel, and None or 'ambiguous' if none."""
        cands = table.get(name)
        if not cands:
            return None
        same = [c for c in cands if where[c] == rel]
        if same:
            return same[0]
        d = Path(rel).parent
        near = [c for c in cands if Path(where[c]).parent == d]
        if len(near) == 1:
            return near[0]
        lib = [c for c in cands if not where[c].endswith('_test.l0')]
        if len(lib) == 1:
            return lib[0]
        return 'ambiguous'

    def bound_names(body):
        """The names a def binds: parameters, lets, match variables."""
        out = set()
        if body and not is_leaf(body[0]):
            for p in body[0][1:]:
                if not is_leaf(p) and len(p) > 1 and is_leaf(p[1]):
                    out.add(p[1][0])

        def rec(x):
            if is_leaf(x):
                return
            if len(x) > 2 and is_leaf(x[1]) and x[1][0] in ('let', 'fn', 'lambda') and is_leaf(x[2]):
                out.add(x[2][0])
            if len(x) > 1 and is_leaf(x[1]) and x[1][0] in ctor_by_name:
                out.update(y[0] for y in x[2:] if is_leaf(y))
            for y in x:
                rec(y)
        for b in body:
            rec(b)
        return out

    stats = Counter()
    seen = set()

    def emit(src, tgt, relation, rel, line):
        """Adds one edge, unless it is a loop or already there."""
        if src == tgt or (src, tgt, relation) in seen:
            return
        seen.add((src, tgt, relation))
        edges.append(edge(src, tgt, relation, rel, line))
        stats[relation] += 1

    def walk(nid, rel, items, bound):
        """Edges from nid to every global name in items."""
        for idx, x in enumerate(items):
            if not is_leaf(x):
                walk(nid, rel, x, bound)
                continue
            name, line = x
            if name == '__line' or name in bound:
                continue
            head = idx == 1 and items[0][0] == '__line'
            tgt = resolve(name, rel, by_name)
            if tgt is None:
                tgt = resolve(name, rel, ctor_by_name)
                if tgt not in (None, 'ambiguous'):
                    emit(nid, tgt, 'uses', rel, line)
                    continue
            if tgt == 'ambiguous':
                stats['ambiguous_dropped'] += 1
            elif tgt is not None:
                relation = 'calls' if head and kinds[tgt] == 'def' else 'references'
                emit(nid, tgt, relation, rel, line)

    for nid, rel, body in bodies:
        walk(nid, rel, body, bound_names(body) if kinds[nid] == 'def' else set())

    return {'nodes': nodes, 'edges': edges, 'stats': dict(stats)}
