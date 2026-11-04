"""dump.py -- a Piper voice's initializers by the onnx package, for
roadmap 0062: the lines onnxdump.l0 prints with format/onnx.l0, so that
a diff of the two is the check of the L0.

  dump.py VOICE.onnx            the lines: count, then each by name
  dump.py VOICE.onnx --nodes    each anonymous one, by the node reading it

A line is a name, its type, its dimensions joined by x, the bits of its
first and last numbers in hexadecimal, and its count. --nodes lists the
initializers whose names are not module paths (onnx::..., sid) with the
node and input that read them, the "NODE#K" onnx.l0 also finds them by,
and the convolutions' attributes.
"""
import sys

import numpy as np
import onnx
from onnx import numpy_helper


def main():
    m = onnx.load(sys.argv[1])
    g = m.graph
    if "--nodes" in sys.argv:
        inits = {t.name: list(t.dims) for t in g.initializer}
        for n in g.node:
            attrs = {a.name: onnx.helper.get_attribute_value(a) for a in n.attribute}
            for k, x in enumerate(n.input):
                if x in inits and (x.startswith("onnx::") or "." not in x):
                    print("%s#%d %s %s" % (n.name, k, x, "x".join(map(str, inits[x]))))
            if n.op_type in ("Conv", "ConvTranspose"):
                print("  %s %s" % (n.name, {k: attrs[k] for k in ("dilations", "pads", "group", "strides") if k in attrs}))
        return
    print("count %d" % len(g.initializer))
    for t in sorted(g.initializer, key=lambda t: t.name.encode()):
        a = numpy_helper.to_array(t).reshape(-1).astype("<f4")
        w = a.view("<u4")
        print("%s %d %s %08x %08x %d" % (t.name, t.data_type, "x".join(map(str, t.dims)), w[0], w[-1], len(a)))


main()
