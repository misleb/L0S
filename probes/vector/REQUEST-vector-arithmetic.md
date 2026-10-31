# Feature request: vector arithmetic over bytes, so a model's inference runs at the CPU's speed

Status: landed, as L0's roadmap 0148 and 0149 (commit 6fecb07) and 0150
(3949d93): all six builtins as asked, the float order fixed by the spec
(6.6), `bytes_axpy_f32` consuming `x` as well as `y`; the aarch64
targets now assume a Cortex-A76, so the int8 dot is `sdot` on the Pi 5
and under QEMU. On the x86_64 host this probe went from 1898 to 71 ps
per multiply-add; the Pi 5 itself is not yet measured. Install from a
commit at or after 3949d93; `roadmap/l0s-adoption.md` §14 and §15 in L0
say how to use them.
Project: L0S, a microkernel in L0 for QEMU's virt boards and the
Raspberry Pi 5

L0S wants to hear speech on the board, with no host: Cactus Compute's
Whistle, an open speech recognition model of 16.9 MB, its weights
quantised to 2 to 4 bits and its activations to int8, written again in
L0 from its C++ engine (L0S's roadmap 0060). Almost all of its time is
one loop: a row of weights times a vector of activations, summed. L0
has no way to write that loop as the CPU runs it best, with NEON on
aarch64 (and the vector extension on riscv64), and without it the model
is too slow to answer someone who speaks to it.

## What could not be written

An int8 or float32 dot product, or a scaled vector added to another,
over ranges of `bytes`, that runs at what the CPU's vector unit gives.

Measured with [dot.l0](dot.l0) and [dot.c](dot.c) beside this file: a
768 by 768 matrix of int8 weights times an int8 vector, 50 times, the
same generator, sizes and checksum (32286750) in each, on an x86_64
host (the boards' own timing on QEMU says nothing):

| Version | Time per multiply-add | Against L0 |
| --- | --- | --- |
| L0 as it is: `bytes_get`, a sign fix, `mul`, `add`, a tail call | 1930 ps | 1 |
| C, `-O2 -fno-tree-vectorize`: scalar | 274 ps | 7 times faster |
| C, `-O3 -march=native`: the compiler's vector code | 35 ps | 55 times faster |

Whistle's encoder runs every weight once per 80 ms of audio, and its
decoder every decoder weight once per token, so a 10 s clip is billions
of multiply-adds. At L0's rate that is tens of seconds on a host, more
on a Pi 5's Cortex-A76; at the vector rate, under a second. The Pi 5's
A76 has `sdot` (sixteen int8 multiply-adds into four int32 lanes in one
instruction) and FP16 arithmetic, which Whistle's engine is built
around.

## Why L0S cannot do it alone

Every L0 value is one 64-bit word (spec 10.1): `float` is binary64,
`(array int)` and `(array float)` a word an element, and `bytes` the
only narrow storage, read a byte at a time. Nothing reads a float32 or
float16 from `bytes`, and nothing works on several elements at once.
L0S writes no assembly a program can call: a kernel's thread is
machine code (`asm.l0`), but a program has no way into its own
instructions. And the scalar gap, 7 times, is partly L0's checks and
calls, which a loop in L0 cannot shed either.

## Smallest change that would help

Bulk builtins over ranges of `bytes`, which fit L0 as it is (no new
value type, every value still a word), and which the runtime writes
with the target's vector instructions, or in scalar code where it has
none, with the same results on every target:

- `(bytes_dot_i8 a i b j n)`: the sum over k below n of the signed
  bytes `a[i+k]` times `b[j+k]`, an exact `int`. The int8 kernel of
  every quantised model.
- `(bytes_dot_f32 a i b j n)`: the float32s at byte offsets `i` and `j`
  (4 bytes each, little-endian), multiplied and summed in float32 and
  returned as a `float`, in an order the spec fixes (say, four lanes,
  each summed in order, then the lanes added 0+1, 2+3, then together),
  so a result is the same on every target and every compiler.
- `(bytes_axpy_f32 y i a x j n)`: the float32s of `y` from `i` made
  `y + a·x`, `x`'s from `j`, `a` a `float` rounded to float32, in place
  under the rules `array_set` follows (10.3), returning `y`.
- Reading and writing one narrow float in bytes:
  `(bytes_get_f32 b i)` and `(bytes_get_f16 b i)` to a `float`, and
  `(bytes_set_f32 b i x)`, with `float`'s rounding to nearest, so
  weights stored as FP16 and activations as float32 are read in place.

Each range out of its bytes is a runtime error (section 8), checked
once for the call, not per element. The integer one is exact, so it
needs no order; the float ones need theirs fixed, as above, or L0 gives
up its promise that a program means the same everywhere.

## How L0S would use it

Whistle's library (roadmap 0060) keeps its weights as the `.cact` file
has them, in `bytes`, and its activations in `bytes` too. Its
matrix-vector products become a `bytes_dot_i8` a row, after the
codebook's dequantisation of a group of 128 into a scratch row; its
attention's softmax and norms use `bytes_dot_f32` and
`bytes_axpy_f32`; its FP16 norms and biases are read with
`bytes_get_f16`. The board run of 0060 measures a 10 s clip's time,
with and without these, and a host test checks the library's token IDs
against the reference byte for byte either way. The four CPUs of a
Pi 5 (`cpu_run`) then divide the rows between them.

## Left out, on purpose

- **A vector type of values.** A 128-bit value does not fit L0's one
  word a value, and would bring lanes, shuffles and masks into the
  language; bulk calls over bytes keep it to a few builtins.
- **Matrix multiply, convolution, FFT.** They are loops over the calls
  above, and L0S can write them; only the innermost loop must be fast.
- **Threads within a program.** L0S already runs a process on each
  CPU; this asks only for each CPU's own speed.

## Which deliberate restriction this breaks

None, if the float results are fixed by the spec as above: the calls
are pure functions of their bytes, as `bytes_get` is. If L0 would
rather leave the float order to the target, that breaks the rule that a
program's result is the same everywhere, and L0S would take only the
exact integer `bytes_dot_i8`, doing its float work in `float` as now.

## Alternatives considered

- **Unrolling in L0.** Reading a word with `le_u64_at`-style reads and
  multiplying packed lanes in an `int` would help a little, but `mul`
  carries between lanes and L0 has no widening multiply; it does not
  come near the vector rate.
- **The model on the host**, as L0S first wrote 0060: it works with no
  change to L0, but the user wants the Pi to hear on its own.
- **A smaller model.** Whistle is already small for its kind; a smaller
  one hears worse, and is still mostly this loop.
