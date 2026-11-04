"""words.py -- espeak-ng's phonemes for a sample of CMUdict's words, the
reference phonemes.l0's agreement is counted on (roadmap 0062).

  words.py CMUDICT N [VOICE]

Every (len/N)-th headword of CMUdict that is letters only (no variant,
no apostrophe), with its phonemes as Piper's own phonemizer gives them
for the word alone, en-us unless VOICE says otherwise: a line each,
the word, a tab, its phonemes.
"""
import sys

from piper.phonemize_espeak import EspeakPhonemizer


def main():
    path, n = sys.argv[1], int(sys.argv[2])
    voice = sys.argv[3] if len(sys.argv) > 3 else "en-us"
    words = []
    for line in open(path, encoding="utf-8"):
        w = line.split(" ", 1)[0]
        if w.isalpha() and w.isascii():
            words.append(w)
    step = max(1, len(words) // n)
    p = EspeakPhonemizer()
    for w in words[::step][:n]:
        ph = "".join("".join(s) for s in p.phonemize(voice, w))
        print("%s\t%s" % (w, ph))


main()
