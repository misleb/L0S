"""Tests of l0_graph.py on small sources written to a temporary tree."""
import tempfile
import unittest
from pathlib import Path

import l0_graph

LIB = """; lib.l0 -- a library
; A pair.
(data Pair (MkPair int int))

; x doubled.
(def twice ((x int)) int (add x x))

; The pair's first, twice.
(def first_twice ((p Pair)) int
  (match p ((MkPair a b) (twice a))))
"""

PROG = """; prog.l0 -- a program
; Makes a pair; twice is passed, not called; n shadows a def.
(def run ((n int)) int
  (let twice_of (MkPair n n)
    (apply twice n)))

; A def named like a parameter elsewhere.
(def n () int 1)
"""

OTHER = """; other.l0 -- defines twice again, far away
; Another twice.
(def twice ((x int)) int x)
"""


class L0GraphTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        for rel, text in (('lib/lib.l0', LIB), ('app/prog.l0', PROG), ('far/other.l0', OTHER)):
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(text)
        self.g = l0_graph.extract(root, ['lib/lib.l0', 'app/prog.l0', 'far/other.l0'])
        self.edges = {(e['source'], e['relation'], e['target']) for e in self.g['edges']}
        self.nodes = {n['id']: n for n in self.g['nodes']}

    def tearDown(self):
        self.tmp.cleanup()

    def test_nodes(self):
        self.assertEqual(self.nodes['lib_lib']['metadata']['summary'], 'lib.l0 -- a library')
        self.assertEqual(self.nodes['lib_lib_twice']['label'], 'twice()')
        self.assertEqual(self.nodes['lib_lib_twice']['rationale'], 'x doubled.')
        self.assertEqual(self.nodes['lib_lib_pair']['label'], 'Pair')
        self.assertEqual(self.nodes['lib_lib_twice']['source_location'], 'L6')

    def test_file_edges(self):
        self.assertIn(('lib_lib', 'contains', 'lib_lib_twice'), self.edges)
        self.assertIn(('lib_lib', 'defines', 'lib_lib_pair'), self.edges)

    def test_same_file_wins(self):
        self.assertIn(('lib_lib_first_twice', 'calls', 'lib_lib_twice'), self.edges)

    def test_a_name_defined_twice_is_dropped(self):
        # app/prog.l0 can't tell lib's twice from far's: no edge, counted.
        self.assertFalse(any(s == 'app_prog_run' and t.endswith('_twice')
                             for s, _, t in self.edges))
        self.assertGreater(self.g['stats']['ambiguous_dropped'], 0)

    def test_constructor_uses_its_type(self):
        self.assertIn(('app_prog_run', 'uses', 'lib_lib_pair'), self.edges)
        self.assertIn(('lib_lib_first_twice', 'references', 'lib_lib_pair'), self.edges)

    def test_constructor_named_as_its_type_references_it(self):
        root = Path(self.tmp.name)
        (root / 'box.l0').write_text('; A box.\n(data Box (Box int))\n; One.\n(def one () Box (Box 1))\n')
        g = l0_graph.extract(root, ['box.l0'])
        edges = {(e['source'], e['relation'], e['target']) for e in g['edges']}
        self.assertIn(('box_one', 'references', 'box_box'), edges)

    def test_bound_names_shadow(self):
        # run's parameter n is not the def n; first_twice's a and b are bound.
        self.assertNotIn(('app_prog_run', 'references', 'app_prog_n'), self.edges)

    def extract_one(self, text):
        """The edges of one file, new.l0, holding text."""
        root = Path(self.tmp.name)
        (root / 'new.l0').write_text(text)
        g = l0_graph.extract(root, ['new.l0'])
        return g, {(e['source'], e['relation'], e['target']) for e in g['edges']}

    def test_named_fields_are_not_defs(self):
        # The field pid is not the def pid; its type Life is a type.
        g, edges = self.extract_one(
            '; Life.\n(data Life (Life (n int)))\n'
            '; A proc.\n(data Proc (Proc (pid int) (life Life)))\n'
            '; A def named as a field.\n(def pid () int 1)\n'
            '; Its pid.\n(def of ((p Proc)) int (.pid p))\n')
        self.assertIn(('new_proc', 'references', 'new_life'), edges)
        self.assertFalse(any(t == 'new_pid' and s != 'new' for s, _, t in edges))
        self.assertIn(('new_of', 'references', 'new_proc'), edges)

    def test_let_of_several_binds_each(self):
        g, edges = self.extract_one(
            '; A def.\n(def a () int 1)\n; Another.\n(def b () int 2)\n'
            '; Binds a and b.\n(def f () int (let (a 1 b (add a 1)) (add a b)))\n')
        self.assertNotIn(('new_f', 'calls', 'new_a'), edges)
        self.assertNotIn(('new_f', 'references', 'new_a'), edges)
        self.assertNotIn(('new_f', 'references', 'new_b'), edges)

    def test_generic_def_and_function_parameter(self):
        g, edges = self.extract_one(
            '; A type named T.\n(data T (MkT int))\n'
            '; A def named key.\n(def key () int 0)\n'
            '; By key.\n(def (find_by K T) ((key (fn (T) K)) (xs (list T))) (Option T)\n'
            '  (if (is_empty xs) ((None T)) (Some (head xs))))\n'
            '; Its name.\n(def name_of ((x int)) int x)\n'
            '; A use.\n(def use () (Option int) (find_by name_of (nil int)))\n')
        self.assertIn(('new', 'contains', 'new_find_by'), edges)
        self.assertIn(('new_use', 'calls', 'new_find_by'), edges)
        self.assertIn(('new_use', 'references', 'new_name_of'), edges)
        # key is the parameter, T the type parameter.
        self.assertNotIn(('new_find_by', 'calls', 'new_key'), edges)
        self.assertNotIn(('new_find_by', 'references', 'new_t'), edges)

    def test_comments_and_strings_are_not_code(self):
        self.assertEqual(l0_graph.parse('; (def x)\n"(def y)" (def z () int 1)')[-1][2][0], 'z')

    def test_extracted_files_count_as_code(self):
        root = Path(self.tmp.name)
        (root / 'new.l0').write_text('; not in git\n')
        (root / 'Makefile').write_text('all:\n')
        unclassified = [str(root / f) for f in ('lib/lib.l0', 'new.l0', 'Makefile')]
        det = {'files': {'code': ['x.py']}, 'unclassified': unclassified,
               'total_files': 4, 'total_words': 10}
        got = l0_graph.counted_as_code(det, root, self.g['files'])
        self.assertEqual(got['files']['code'], ['x.py', str(root / 'lib/lib.l0')])
        self.assertEqual(got['unclassified'], [str(root / 'new.l0'), str(root / 'Makefile')])
        self.assertEqual(got['total_files'], 5)
        self.assertEqual(got['total_words'], 10 + len(LIB.split()))
        self.assertEqual(det['total_files'], 4)


if __name__ == '__main__':
    unittest.main()
