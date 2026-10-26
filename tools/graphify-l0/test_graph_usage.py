"""Tests of graph-usage's reading of tool calls."""
import importlib.machinery
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

_path = str(Path(__file__).resolve().parent / 'graph-usage')
_loader = importlib.machinery.SourceFileLoader('graph_usage', _path)
_spec = importlib.util.spec_from_loader('graph_usage', _loader)
gu = importlib.util.module_from_spec(_spec)
_loader.exec_module(gu)


def bash(cmd):
    """A Bash tool use."""
    return ('Bash', {'command': cmd})


class GraphUsageTest(unittest.TestCase):
    def calls(self, *uses):
        return list(gu.graph_calls(uses))

    def test_commands(self):
        self.assertEqual(self.calls(bash('cd /x && graphify explain "port_ask()" 2>&1 | head')),
                         [('explain', 'graphify explain "port_ask()"')])
        self.assertEqual(self.calls(bash('graphify affected Rect')), [('affected', 'graphify affected Rect')])

    def test_prose_is_not_a_call(self):
        # A commit message, a skill's text being written, an echo.
        self.assertEqual(self.calls(bash('git commit -m "ask the graph (graphify explain, affected)"')), [])
        self.assertEqual(self.calls(bash('echo use graphify explain to look')), [])
        self.assertEqual(self.calls(('Edit', {'new_string': 'graphify affected Rect'})), [])

    def test_reads_of_the_graph(self):
        self.assertEqual(self.calls(('Read', {'file_path': '/r/graphify-out/GRAPH_REPORT.md'})),
                         [('read', '/r/graphify-out/GRAPH_REPORT.md')])
        self.assertEqual(self.calls(bash('jq .nodes graphify-out/graph.json')),
                         [('read', 'graphify-out/graph.json')])

    def test_the_build_is_not_a_read(self):
        self.assertEqual(self.calls(('Read', {'file_path': '/r/graphify-out/.graphify_ast.json'})), [])
        self.assertEqual(self.calls(bash('cat graphify-out/.graphify_python')), [])

    def test_mcp(self):
        self.assertEqual(self.calls(('mcp__graphify__query', {})), [('mcp', 'mcp__graphify__query')])

    def test_transcript(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / 's.jsonl'
            lines = [{'type': 'user', 'message': {'content': 'graphify explain x'}},
                     {'type': 'assistant', 'message': {'content': [
                         {'type': 'text', 'text': 'graphify explain y'},
                         {'type': 'tool_use', 'name': 'Bash', 'input': {'command': 'graphify path a b'}}]}}]
            f.write_text('\n'.join(json.dumps(x) for x in lines) + '\nnot json\n')
            self.assertEqual(list(gu.graph_calls(gu.tool_uses(f))), [('path', 'graphify path a b')])

    def test_projects_dir(self):
        self.assertEqual(gu.projects_dir('/home/u/projects/L0S').name, '-home-u-projects-L0S')


if __name__ == '__main__':
    unittest.main()
