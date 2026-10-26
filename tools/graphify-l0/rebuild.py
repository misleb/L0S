"""Rebuild graphify-out/ from the code as it is now, keeping the docs.

  python rebuild.py [ROOT]

Runs with graphify's own Python (graphify-out/.graphify_python, which
/graphify wrote). Re-extracts all the code: the L0 sources with
l0_graph.py, the scripts and Python with graphify's AST extractor. It
replaces those files' nodes in graph.json, prunes the nodes of code
files that are gone, and keeps every node the LLM extracted from the
docs, which only /graphify --update refreshes. Then it clusters again,
names each community as before when most of its nodes were in one
community that had a name (else by its main directory), and writes
graph.json, GRAPH_REPORT.md and graph.html. No LLM, no tokens.
"""
import json
import os
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import l0_graph  # noqa: E402

from graphify.analyze import god_nodes, suggest_questions, surprising_connections  # noqa: E402
from graphify.build import build_merge  # noqa: E402
from graphify.cluster import cluster, score_all  # noqa: E402
from graphify.detect import detect  # noqa: E402
from graphify.export import to_json  # noqa: E402
from graphify.extract import collect_files, extract  # noqa: E402
from graphify.report import generate  # noqa: E402

# graphify's extensions skipped: SVG icons are images to it, and its JSON
# rule reads .mcp.json, which says nothing of the code.
SKIP_SUFFIXES = {'.svg'}


def code_extraction(root, files):
    """graphify's AST extraction of the code files it detected."""
    paths = []
    for f in files:
        p = Path(f)
        paths.extend(collect_files(p) if p.is_dir() else [p])
    if not paths:
        return {'nodes': [], 'edges': []}
    return extract(paths, cache_root=root, root=root)


def community_names(G, communities, old_names):
    """A name for each community: the old one most of its nodes had, if
    they are most and no bigger community took it; else its directory."""
    names, taken, per_dir = {}, set(), Counter()
    for c in sorted(communities, key=lambda c: -len(communities[c])):
        members = communities[c]
        olds = Counter(old_names[n] for n in members if n in old_names)
        best = olds.most_common(1)
        if best and best[0][1] * 2 > len(members) and best[0][0] not in taken:
            names[c] = best[0][0]
            taken.add(best[0][0])
            continue
        dirs = Counter('/'.join(Path(G.nodes[n].get('source_file') or '').parts[:-1][-2:]) or 'root'
                       for n in members)
        d = dirs.most_common(1)[0][0]
        per_dir[d] += 1
        names[c] = f'{d} ({per_dir[d]})'
    return names


def rebuild(root):
    """Rebuilds root's graphify-out/; the graph's size, as a line."""
    root = Path(root).resolve()
    out = root / 'graphify-out'
    graph_path = out / 'graph.json'
    if not graph_path.exists():
        sys.exit('graph-l0: no graphify-out/graph.json; run /graphify once first')
    old = json.loads(graph_path.read_text(encoding='utf-8'))
    old_names = {n['id']: n['community_name'] for n in old['nodes'] if n.get('community_name')}

    det = detect(root)
    code = [f for f in det['files'].get('code', []) if Path(f).suffix not in SKIP_SUFFIXES]
    l0 = l0_graph.extract(root)
    chunks = [code_extraction(root, code), {'nodes': l0['nodes'], 'edges': l0['edges']}]

    # Code files the graph has that are gone: their nodes go. A doc that is
    # gone keeps its nodes until /graphify --update, which knows it was one.
    gone = sorted({n['source_file'] for n in old['nodes']
                   if n.get('_origin') == 'ast' and n.get('source_file')
                   and not (root / n['source_file']).exists()})
    G = build_merge(chunks, graph_path=graph_path, prune_sources=gone or None,
                    root=root, directed=False)
    if G.number_of_nodes() == 0:
        sys.exit('graph-l0: the rebuilt graph is empty; graph.json left as it was')

    communities = cluster(G)
    cohesion = score_all(G, communities)
    labels = community_names(G, communities, old_names)
    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)
    questions = suggest_questions(G, communities, labels)
    # A graph smaller than before is right after code was deleted, so the
    # shrink guard is passed over: the docs' nodes are kept regardless.
    to_json(G, communities, str(graph_path), force=True, community_labels=labels)
    tokens = {'input': 0, 'output': 0}
    report = generate(G, communities, cohesion, labels, gods, surprises, det, tokens,
                      str(root), suggested_questions=questions)
    (out / 'GRAPH_REPORT.md').write_text(report, encoding='utf-8')
    (out / '.graphify_labels.json').write_text(
        json.dumps({str(k): v for k, v in labels.items()}, ensure_ascii=False), encoding='utf-8')
    subprocess.run([sys.executable, '-m', 'graphify', 'export', 'html'], cwd=root, check=True,
                   stdout=subprocess.DEVNULL, env={**os.environ, 'PYTHONHASHSEED': '0'})
    return (f'graph-l0: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, '
            f'{len(communities)} communities; {len(gone)} files pruned; L0 {l0["stats"]}')


if __name__ == '__main__':
    print(rebuild(sys.argv[1] if len(sys.argv) > 1 else '.'))
