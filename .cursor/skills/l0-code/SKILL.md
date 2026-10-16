---
name: l0-code
description: Read, write, and edit L0 source code (.l0 files). Covers L0 syntax, the standard library, the idioms that keep generated output linear rather than quadratic, the mandatory l0 check validation loop, and the testing convention. Use whenever creating or modifying .l0 files, reading L0 code, diagnosing L0 type errors, or writing tests. Also use when this skill, the spec, or l0 doc is wrong or incomplete, to report the correction so it can go back to L0.
---

# Writing L0

L0 is a small, statically typed language with no mutable state, whose only
effects are its I/O builtins. **There is almost certainly no
L0 in your training data.** Anything you recall about Lisp, Scheme, Clojure,
ML, or Haskell is either wrong here or accidentally right. Two rules follow,
and they matter more than everything else in this file:

1. **The specification is the only source of truth.** If a construct is not in
   it, it does not exist. Do not infer syntax from other languages.
2. **Never claim L0 code works until `l0 check` passes on it.** You cannot
   pattern-match your way to correct L0. The checker is your only reliable
   signal.

Read the specification before writing L0 for the first time in a session;
`l0 spec --path` says where it is. Sections 1 to 9 and 11 are the language,
and all of them matter. Section 10 is how the compiler and runtime work, and
you need only its memory rules, in 10.3, which the section on memory below
summarises. Then skim the examples,
`l0 examples --path`, which are working programs and their tests. All of
this comes from the installed toolchain, so it describes the compiler you
are using.

## Every program is three files, and has tests

A program is one directory with three kinds of file, and this holds for the
smallest program too:

```
hello/
  hello.l0        what the program does, as functions
  hello_test.l0   tests of those functions, beside the file they test
  main.l0         only main: reads arguments and input, calls in, exits
```

**`main` is always in `main.l0`, alone.** `l0 test` supplies its own `main`,
so code in a file that defines one cannot be tested. Keep `main.l0` to
reading arguments and input, calling into the program, and returning the exit
status, so that nothing worth testing is left in it. A larger program splits
`hello.l0` into several files, each with its own `_test.l0` beside it. There
is no tests directory, since `l0 test` runs the files it is given.

Hello world, in full:

```
; hello.l0
(def greeting () (list int) "Hello, world!")
```

```
; hello_test.l0
(def test_greeting () int
  (check_str "greeting" (greeting) "Hello, world!"))
```

```
; main.l0
(def main () int
  (write_line (greeting)))
```

**A program is done when its tests pass,** not when it has run once:

```bash
l0 check hello.l0 main.l0             # type check; prints ok, or diagnostics
l0 test  hello.l0 hello_test.l0       # every test: every file but main.l0
l0 build hello.l0 main.l0             # the executable ./hello, named after the first file
l0 run   hello.l0 main.l0 < input     # build and run, reading stdin
l0 run   hello.l0 main.l0 -- a b      # the same, with arguments a and b
```

Diagnostics are `file:line:column: error: message`. A declaration that does
not parse is reported once and dropped, and its uses are not reported as
unknown, so fix it and check again. The files given are
compiled together, because L0 has no module system. The standard library is
linked automatically; never pass its files on the command line. Defining a
function with the same name as one of its functions is fine.

## Syntax you will get wrong if you guess

**`nil` takes its element type.** There is no bare `(nil)` and no inference.

```
(nil int)           (nil Token)           (nil (list int))
```

**Types are parenthesised.** A list type is `(list int)`, never bare `list`.

**Case is meaningful.** Functions, parameters, and bindings start lowercase or
with `_`. Types and constructors start uppercase. This is how the reader tells
a constructor from a variable, so it is not a style preference.

**`let` binds exactly one name and has a body.** It is not `let*`, and there
is no binding list. Sequential bindings are nested lets.

```
(let a 1
  (let b (add a 1)
    (add a b)))
```

**Every `match` arm is `((Ctor names...) result)`,** one name per field,
patterns one level deep, every constructor present exactly once, and **no
wildcard or default arm**. Nullary constructors keep their parentheses, in
patterns and in expressions: `(Red)`, never `Red`.

**There are no function values, closures, or higher-order functions.**
Recursion replaces both loops and iteration combinators.

**There are no tuples.** A function returning two things declares a small
`data` type; see `Split` in `l0 examples`.

**There are no exceptions.** A function that can fail returns a `data` type
with a case per outcome; see `Parsed` in `l0 examples`. When success is one
value, the standard library's `Result` is that type (`l0 doc Result`), and
`Option` is the one for a value that may be missing.

**A `data` type may take type parameters.** Declare the shape once and use
it at every type it holds, instead of one type per element type. The
standard library declares `Option` and `Result` this way, so use those
rather than declaring your own:

```
(data (Result T E) (Ok T) (Err E))      ; as the library declares it
(Ok 5)                                  ; wrong: nothing says what E is
((Ok int (list int)) 5)                 ; right: a (Result int (list int))
```

A construction takes its type from its arguments, as `cons` does, so
`(Some 5)` needs nothing more. A constructor whose fields leave a parameter
out, such as `(None)`, is written with the type's arguments first,
`((None int))`, as `nil` is. See `first_even` and `parse_number` in
`l0 examples`.

**A function may take type parameters too,** so write a helper over lists,
arrays, or `Option` once rather than once per element type:

```
(def (last_or T) ((xs (list T)) (fallback T)) T
  (if (is_empty xs) fallback (last_or (tail xs) (head xs))))

(last_or "abc" 0)                       ; an int
(last_or (split_spaces "a b") "")       ; a (list int)
```

A call writes no types: its arguments say what `T` is, so every type
parameter must appear in some parameter's type, and `(def (empty T) ()
(list T) ...)` is an error. Inside the body `T` is a type of its own, so a
`T` can be kept, passed, consed, stored, compared with `eq`, hashed with
`hash`, and ordered with `compare`, but not ordered with `lt` or taken apart
with `match`. So a membership test, a lookup, a hash table, a heap, or a
sorted set is written once, for every element type, and the library already
has `sort`.

**`and` and `or` are strict.** Both arguments are always evaluated, so they do
not guard against errors. This still calls `head` on an empty list:

```
(and (not (is_empty xs)) (gt (head xs) 0))   ; wrong
(if (is_empty xs) false (gt (head xs) 0))    ; right
```

**`eq` compares two values of any one type by what they hold:** `(eq "ab"
(cons 97 "b"))` and `(eq (Some "x") (Some "x"))` are true, and so is `eq` on
two lists of strings, two arrays, or two `bytes` with the same contents. Both
arguments must have the same type.

**`compare` orders two values of any one type by what they hold** (spec
6.11): -1, 0, or 1, so `(lt (compare a b) 0)` is "a before b". Strings,
lists, arrays, and `bytes` go element by element with a shorter prefix
first, and data values by constructor, in declaration order, then field by
field. `lt`, `le`, `gt`, and `ge` still take only `int`. To sort by an
order of your own, build a key whose structure is that order: count highest
first, then word, is `(Rank (neg count) word)` for `(data Rank (Rank int
(list int)))`. The order is of contents, not meaning: a number kept as
digits least significant first does not compare numerically, so give it a
key. An order no key expresses, such as ignoring case, is a function you
write, at its element type.

The library's `(sort xs)` sorts a list of any type by `compare`, ascending,
in n log n and with no stack, and `min` and `max` take the lesser and the
greater of two values: write neither a sort nor a max of your own. To list a
map's keys in order, `(sort (map_keys m))`; `examples.l0`'s `by_frequency`
sorts words by a `Rank` key.

**`hash` gives any value a non-negative `int`** (spec 6.9), the same for two
values `eq` calls the same, so `(mod (hash key) n)` is a key's slot in a
table of `n`, for keys of any type. Two different keys can share a hash, so
a table compares the keys it finds with `eq`. The hash is defined by the
spec, the same on every machine and run, so a test can pin one.

**A name in call position is never a local.** `(f 1)` always means a builtin
or a `def`, so a parameter named `f` cannot be called and does not shadow a
function named `f`.

**Your definition wins over the standard library's, and over a builtin.**
Defining `length` when the prelude already has one, or `flush` when it is a
builtin, is legal rather than a collision: yours is used everywhere in your
program, with your signature, and the prelude goes on calling its own and
the builtin, so redefining something the prelude uses internally cannot
break it, and a builtin added to L0 later cannot break your program. Your
types and constructors win over the library's the same way, `IoFile` or any
other: the library's are then out of reach, so a `match` on a library type
one of whose constructors you redeclared cannot be written. Short library
names are the ones to watch: a program that declares its own `Done`,
`NotDone`, `Some`, or `Ok` can no longer match what `file_close`, `map_get`,
or a `Result` returns. Spec sections 7 and 7.1.

## The one performance rule

**Build output as a reversed accumulator and reverse once at the end.**

Appending to the end of a list copies the whole list, so building output with
repeated appends is quadratic in the size of the output. Code written that way
passes every small test and then appears to hang on real input.

```
(def render ((n int)) (list int)
  (let a (push "count=" (nil int))
    (let b (push (digits n) a)
      (rev (push "\n" b)))))
```

`push` costs the length of the chunk, not the length of the accumulator. Call
`rev` exactly once, at the very end, never per chunk. Use `append` only for
short strings such as diagnostics. Nested pushes run innermost first:
`(push "b" (push "a" acc))` adds `"a"`, then `"b"`, so write the nest with the
first chunk deepest, or use a chain of `let`s as above.

## Keep nesting shallow, or you will miscount parentheses

This is the most common way to waste time writing L0. A chain of six `if`s or
ten `or`s ends in a run of a dozen `)`, and the resulting error points at the
start of the form rather than at the mistake.

**Test membership with a word table** instead of an `or` chain:

```
(def is_keyword ((n (list int))) bool
  (any_eq n (split_spaces "def data if let match nil true false")))
```

**Collapse a `match` to a predicate.** Since `match` has no wildcard,
inspecting a six-constructor type inline costs six lines every time. Write the
match once as a function returning an int, then build predicates on it.

**Split the function.** A body nesting more than about four levels should hand
its tail to a helper.

## The standard library

Linked into every program. **Ask `l0 doc` before writing a helper**; it reads
the documentation from the library the compiler links, so it is never out of
date:

```bash
l0 doc                # every function and type, one line of purpose each
l0 doc io             # one file in full: prelude, io, or test
l0 doc split_spaces   # one definition in full; a constructor finds its type
l0 doc decimal        # anything whose name or documentation mentions it
```

The ones you will reach for constantly are `rev`, `push`, `append`,
`list_eq`, and `digits`, which prints a number in decimal; `hex_digits`
prints one in hexadecimal. `rev`, `rev_onto`, `append`, `length`, and `sort`
take a list of any type, and `array_resize` grows an array of any type, so
never write one of them for your own element type. The
builtins, such as `head` and `read_byte`, are in the specification, section
6, not in `l0 doc`.

There is no `map`, `filter`, or `fold`, because L0 has no function values.
Write the recursion directly.

If one of these does not do what you need, define your own with the same name
rather than inventing `my_length`. Yours shadows the prelude's throughout your
program and cannot disturb the prelude's own use of it.

## The shape of a program

`main` takes one of two forms. The first receives stdin as a list of bytes and
returns its output, here computed by `upcase`, a function in the program's own
file and tested there:

```
; main.l0
(def main ((input (list int))) (list int)
  (upcase input))
```

The return type may be `(list int)` for raw bytes, or `int` or `bool`, which
are printed as a decimal or as `true`/`false`. All of stdin is read before
`main` starts, and the result is written after it returns, so this form
cannot prompt, and cannot show anything before its input has ended.

The second takes nothing, reads and writes as it goes, and returns the exit
status. Use it when a program must write before its input ends, such as a
prompt, or must not hold its whole input at once. `main` does the I/O in
order, and `greet`, in the program's own file, builds the reply, so the part
worth testing is tested:

```
; main.l0
(def main () int
  (let w (write_str "What is your name? ")
    (let name (take_line (read_line))
      (write_str (greet name)))))
```

`read_byte` and `write_byte` are the builtins; `read_line`, `write_str`, and
`write_line` are in the standard library, `l0 doc io`. They are effects, and **effects happen in
evaluation order**, so nest `let`s to put one before another. A `let` whose
name you never use is still evaluated, which is exactly what makes it the way
to sequence. `read_line` returns the empty list only at end of input, and
keeps the line's newline, so strip it with `take_line`.

Output written before a read that has to wait is always shown first, so a
prompt appears before the program waits for its answer.

**Files and arguments.** Use the wrappers `l0 doc io` lists, not the raw
builtins. To copy, read in pieces (below), which is faster than any loop
over bytes. Where a loop must run once per byte over several files, the
wrappers cost: copying 100 MB to four outputs through `file_write_byte`
took 2.8 times as long with the `IoFile`s in a list, and 2.1 times with them
in an array, as with the raw handles in an `(array int)` and `write_to`.
Take the handles out once, with `(match f ((IoFile h) h))`, call
`read_from` and `write_to` on them in that loop, and keep the `IoFile`s for
flushing and closing.
`(open_in path)`, `(open_out path)`, and `(open_appending path)` return
`IoOpened`, and `match` makes you handle its `IoFailed` case,
`((IoFailed fault why) ...)`: `why` says what went wrong in words, for a
message, and `fault` says which failure it was, as a case to test with `eq`
or `match`. Opening to read gives an `OpenFault` (`OpenMissing`,
`OpenDenied`, `OpenIsDirectory`, `OpenFailed`), and creating or appending a
`CreateFault` (`CreateDenied`, `CreateNoDirectory`, `CreateIsDirectory`,
`CreateFailed`), so a test for a case that open cannot give, such as `(eq
fault (OpenMissing))` after `open_out`, does not compile. Test the case, not
the words: `(eq fault (OpenMissing))` reads a missing file as empty, where
comparing `why` with "no such file" type checks whatever it is compared
with. Then `file_read_byte`, `file_read_line`, `file_write_str`, and
`file_close` work on the `IoFile` inside.

Renaming, removing, flushing, and closing return an `IoDone`: `(Done)`, or
`((NotDone fault why) ...)` with a fault typed for the operation, a
`RenameFault`, `RemoveFault`, or `WriteFault`; `l0 doc` lists the cases.
`(is_done r)` is the test when only success matters, as after most closes.
Nothing makes a program look at one, so `(let c (file_close f) ...)` with
`c` unused compiles: look at every close of a file you wrote, and at every
rename and remove. `(arg_count)` and `(arg i)` are the command-line
arguments, not counting the program's name. `write_err` writes to standard
error. Report failure by returning a nonzero exit status from `main`.

A file read returns -1 at end of input and another negative number if the
read failed, so test for -1 and for other negatives separately, or a failed
read looks like a short file. `read_line` and `file_read_line` do not: a
failed read ends the line as end of input would. When that matters, use
`next_line` and `file_next_line`, which return an `IoLine`: `(IoLine s)`,
`(IoEnd)`, or `(IoError code)`, where `(io_error code)` says why in words.

**Reading a whole input at once.** `(read_input)` reads all of standard
input, and `(file_read_all f)` the rest of a file, as `bytes` (spec section
6.6), returning `(IoBytes b)`, or `(IoReadFailed code)` if a read failed.
`(bytes_len b)` and `(bytes_get b i)` read them by index, and
`(file_write_bytes f b i j)` writes bytes `i` up to `j` to a file, so a
line or a field goes out by position without becoming a list. Pass
`(IoFile 1)` to write to standard output. `(bytes_to_list b)` and
`(bytes_from_list s)` convert, which is how bytes meet string literals, in
tests especially. Nothing changes a bytes value.

**Reading in pieces.** To stream a file of any size, copying it or checking
it without holding it, `(file_read_some f n)` gives the next piece, at least
one byte and at most `n`, as `(IoBytes b)`, empty only at the end, or
`(IoReadFailed code)`. Call it until the bytes are empty: a pipe or a
terminal gives fewer than `n` while more is still to come. Write each piece
with one `file_write_bytes`; `examples.l0`'s `copy_in_pieces` is the loop.
This is also the fast way to copy: 100 MB to four outputs this way takes
under a tenth of a second, where a loop of `file_read_byte` and
`file_write_byte` takes one to two seconds.

Writes are held back, so a write failure shows up only later: no write
returns it, and a program that must say which write failed can only flush
after it, as often as that matters. `file_close`, or `file_flush` on a file
kept open, returns `NotDone` if any byte written to the file was lost, with
`WriteNoSpace` for a full disk, `WriteBrokenPipe` for a pipe whose reader
has gone, or `WriteFailed`, or `WriteNotOpen` if the file was not open for
writing, as when it was closed already; check it. For standard
output, which is never closed, call `(file_flush (IoFile 1))` once at the
end, as a Unix filter does, and turn a failure into a message and a nonzero
status. Here `run`, in the program's own file, does the work and returns
the exit status:

```
(def main () int
  (let st (run (args))
    (match (file_flush (IoFile 1))
      ((NotDone fault why) (let w (write_err (append "prog: " (append why "\n"))) 1))
      ((Done) st))))
```

A write failure the program never checked is not ignored: the program exits
with status 70 and `l0: runtime error: write failed`. Checking is how you
choose the message and status instead.

**Updating a file.** `open_out` empties a file before anything is written, so
never rewrite a file you cannot afford to lose that way. To add to the end,
use `(open_appending path)`, which keeps what the file holds and costs only
what you write. To replace it, write the new contents to another name such
as `path.tmp`, check that `file_close` gave `(Done)`, then `(rename_file tmp
path)`: a crash at any point leaves the old file or the new one, never a
half-written one. If writing or renaming it fails, `(remove_file tmp)`
deletes it, so nothing half-written is left under either name;
`RemoveMissing` from `remove_file` means it was already gone. A directory is
never deleted, and deleting a link leaves what it leads to.
`examples.l0`'s `replace_file` is this, written out.

**Testing code that reads or writes a file.** Write it against `IoFile`
arguments, not against standard input and output, and have `main` pass it
real files or `(IoFile 0)` and `(IoFile 1)`. A test then passes it
`(open_in_bytes s)` to read the string `s`, and `(open_out_buffer)` to
collect what it writes, which `buffer_contents` returns as a string. The code
cannot tell these from files, so the test runs exactly the code the program
runs, with no temporary files. Close both with `file_close`.

**Memory is reclaimed by reference counting**, with nothing for you to do, but
how you write a program decides how much it holds. A value is freed at the
last use of the last name that held it, on each path through a function, not
when that name's scope ends, and a loop in tail position frees each
iteration's garbage before the next. So:

- to process a large input, use the streaming `main` and read it a line, a
  byte, or a piece at a time, the last with `(file_read_some (IoFile 0) n)`;
  that runs in constant memory however long the input is
- a `main` that takes its input gets it as a list built in full before `main`
  starts, one cons cell per byte, about 2.4 GB for 100 MB, however little of
  it `main` then keeps
- to hold a whole input, because the program must see all of it, as a sort
  or a parser must, use the streaming `main` and `(read_input)`: bytes take
  one byte of memory per byte, about 100 MB for 100 MB, and are read by
  index like an array
- write loops as tail calls, so each iteration's values are freed as it goes.
  A tail call uses no stack at all, between functions of any arities and at
  any optimization level (spec section 8), so a loop through tail calls,
  mutual recursion included, can run forever. Recursion that is not a tail
  call, such as `(add 1 (count (tail xs)))`, takes a frame per level, and a
  long enough list exhausts the stack

**Maps.** For anything looked up by a key that is not a small integer —
counts by word, a node's number by its name — use the library's
`(Map K V)` (`l0 doc Map`), not a list of pairs or a table of your own. The
empty map is `((MapEmpty K V))`, written with its types; `(map_put m k v)`
returns the map with `k` mapped to `v`, `(map_get m k)` an `Option`, and
`map_has`, `map_remove`, `map_size`, `map_keys`, and `map_values` the rest.
Any type can be a key. Like an array, a map changes in place while nothing
else holds it and is copied whole when something does, so thread one map
through a loop and keep no other name for the old one. `map_keys` lists in
the table's order, the same on every run but not the order of insertion.
See `word_counts`, `repeated_words`, and `distinct_count`, a map at a type
parameter used as a set, in `l0 examples`.

**Arrays.** For anything indexed by a small integer — counts by byte,
distances by node — use `(array T)`, not a list or a tree of your own: `(array_new
n x)`, `(array_len a)`, `(array_get a i)`, and `(array_set a i x)`, which
returns the updated array. An index out of range is a runtime error.
`array_set` updates in place, in constant time, when nothing else holds the
array, and copies the whole array otherwise. So thread one array through a
tail-recursive loop, pass the result of `array_set` on, and keep no other
name, field, or list holding the old one:

```
(def count ((counts (array int))) (array int)
  (let b (read_byte)
    (if (lt b 0)
        counts
        (count (array_set counts b (add (array_get counts b) 1))))))
```

An `array_get` that is one of the `array_set`'s own operands, as here, is
fine. What copies, silently, with correct results:

- **a read after an update in the same expression.** In `(array_set
  (array_set h 0 (array_get h k)) 1 (array_get h (add k 1)))` the second
  `array_get` still needs `h` when the inner `array_set` runs, so it copies
  all of `h`, every time. Bind the reads first:

```
(let a (array_get h k)
  (let b (array_get h (add k 1))
    (array_set (array_set h 0 a) 1 b)))
```

- **an array still used after the `array_set`**, or kept in a list of
  earlier versions
- **an array inside another array, unless it goes through a function and
  back in exactly this form:** `(array_set g y (f ... (array_get g y)
  ...))`, with `g` a variable that no other argument of `f` mentions and
  `y` the same variable or literal both times. The element is taken out of
  `g` for `f` and `f`'s result put back, so `f` updates it in place: a
  table of records, each handed to a function that updates it, costs
  nothing to keep. With `f` being `array_set` itself, `(array_set g y
  (array_set (array_get g y) x v))` updates one cell of a grid. Binding
  the element with `let` first, passing `g` to `f` too, or computing `y`
  twice copies it. The same holds for an element that is a list, data, or
  bytes. A flat `(array int)` indexed by `(add (mul y w) x)` is still the
  fastest grid. `(array_new h (array_new w 0))` makes every row the same
  array, so each copies once, on its first update
- **not** an array in a data value, if you take the value apart with `match`
  and don't use it again: then the field is the only holder, and the update
  is in place. Keeping several arrays together in a data type and rebuilding
  it each step is fine

To check a loop, run the program with `L0_ARRAY_STATS=1`: it reports on
standard error how many updates copied.

**Bits.** `bit_and`, `bit_or`, `bit_xor`, `bit_shl`, `bit_shr`, and
`bit_count` work on the 64 bits of an `int` (spec section 6.10); `not`,
`and`, and `or` are for `bool` only. `bit_shr` brings in zeros, so it is the
unsigned shift; shifting by 64 or more gives 0, and by a negative amount is
a runtime error. There is no bitwise not: write `(bit_xor x -1)`. There is
no hexadecimal literal either: write the constant in decimal with its hex
in a comment. `(hex_digits n width)` prints an `int` in hexadecimal, its 64
bits read as unsigned, and `hex_val` reads one hex digit. To keep 32 bits, as a hash does, `(bit_and x 4294967295)` after
each `add` or `mul`. A set of up to 64 small ints fits in one `int`, and a
bitset in an `(array int)` of 64 bits a word.

**Timing part of a program.** `(clock_ns)` reads a clock in nanoseconds
that never goes back (spec section 6.7). Only differences mean anything:
bind a reading with `let` before the part and another after, since `let`
is what fixes when each happens, and write `(sub t1 t0)` to standard error
so standard output stays the program's own. One run can then report every
phase, instead of one build per phase timed from outside.

Factor reads into small functions freely. A parameter of list, data, array,
or bytes type costs no reference counting to pass when the function only
reads it: with `is_empty`, `array_len`, `bytes_len`, `bytes_get`, or `head`
or `array_get` of an int or bool element, by matching on it and reading its
fields the same way, or by passing that same parameter on to another
function that only reads it. So an index loop over an array or bytes, which
passes the array itself to its next iteration, is free to call, and there is
no reason to inline such a helper by hand. A function that walks a list by
passing `(tail xs)` on does not qualify, because `tail` hands out part of the
list: it costs a count per step, which is cheap but not nothing. Spec
section 10.3 has the rule in full.

Don't read input into an `(array int)`: its length is unknown until the end,
so the array doubles as it fills and briefly holds two copies, about as
much memory as a list, 25 bytes per input byte, and even at the right size
an int array takes 8 bytes per byte. Read it with `(read_input)` or
`(file_read_all f)` into `bytes`, which take one. An `(array bytes)` is a
compact table of words or lines: build each with `bytes_from_list`.

There is no network or environment yet.

## Testing

Use `l0 test`. `l0 examples test` prints a worked file of tests; read it
first. `l0 doc test` lists every assertion.

```bash
l0 test wordfreq.l0 wordfreq_test.l0                 # every test, as TAP
l0 test wordfreq.l0 wordfreq_test.l0 --match parse   # only names containing "parse"
```

A test is `(def test_NAME () int ...)`, with `(def test_NAME ()` at the very
start of a line, unindented, since that is how `l0 test` finds it. There is
no list of tests to maintain: `l0 test` finds them, builds
the files once with the assertions linked, and runs each test in its own
process. It prints `ok N - test_NAME` or `not ok N - test_NAME` with what went
wrong underneath, and exits nonzero if any failed. `l0 check --test` checks
test files the same way without running them.

Every test also runs with the runtime checking reference counts, and a test
that ends with memory never freed fails. Correct L0 cannot do that, so such a
failure is a bug in the compiler or runtime, worth reporting as one.

A test returns how many of its assertions failed. Sum several with `add`,
which runs them in order:

```
(def test_parse_digits () int
  (add (check_int "value" (parse_or_zero "42") 42)
       (check_str "rest" (first_line "a\nb") "a")))
```

The assertions are `check_int`, `check_bool`, `check_true`, `check_str`, and
`check_strs`, each taking a name, what the code computed, and what it should
be. A failing string is shown as an L0 literal you can paste back, with the
first byte where it differs. For a data type, `match` on it inside the test,
and in the arm that should not happen return `(fail_because NAME WHY)`,
which reports the assertion as failed for the reason given:

```
(def test_parses () int
  (match (parse_digits "42" 0 false)
    ((Num v rest) (check_int "value" v 42))
    ((Bad msg) (fail_because "value" msg))))
```

`pass` and `fail` are there for writing an assertion of your own.

**Keep each test to one to three assertions, and write many tests.** Long
chains of nested assertions are where closing parentheses get miscounted.

**A runtime error fails only its own test**, and its message is shown. To test
that code must fail, give the test an `expect_NAME` with the same NAME:

```
(def test_empty_head () int (head (nil int)))
(def expect_empty_head () (list int) "head of empty list")
```

The test passes only if the program exits with status 70 and standard error
is exactly `l0: runtime error: ` followed by the message `expect_NAME`
returns. Spec section 8 lists every message: `division by zero`, `modulo by
zero`, `head of empty list`, `tail of empty list`, `array index out of
range`, `negative array length`, `byte index out of range`, `negative
shift`, and `byte count out of range`, and from the host `stack exhausted`,
`heap exhausted`, and `write failed`.

**Golden files** hold expected output too long to write inline:
`(check_file "name" got "path/to/expected.txt")`, with the path relative to
where `l0 test` runs. `l0 test --bless` writes the files instead of comparing,
and lists each one it wrote. Blessing turns whatever the code does now into
what is correct, so read the diff of every file it touched.

**Property tests** use `rand_next`, `rand_below`, and `rand_bytes` (see `l0
doc test`), which give the same sequence on every run, so a failure
reproduces. Check a property over a few hundred inputs, such as two
implementations agreeing, or parsing what was printed.

A test that uses `arg` sees `l0 test`'s arguments, not yours. Test a whole
program by putting its logic in functions and testing those, or by running it
with `l0 run` and comparing what it writes.

## When this skill, or L0, is wrong

If the checker or a test contradicts this skill, `l0 doc`, or the examples,
the documentation is wrong; if it contradicts the specification, the
compiler is. Either way, write code the checker accepts and the tests pass
on, and tell the user plainly: name the file, quote what it says, and say
what it should say, or what the compiler did instead. Do the same when the
documentation is silent about something you needed, or L0 cannot express
it. Do not just correct your project's copy in
`.cursor/skills/`: `l0 init` overwrites it, and every other project keeps
the mistake. L0 and its documentation are fixed in L0's own repository, and
a report that names the file and the correction is what lets that happen.
