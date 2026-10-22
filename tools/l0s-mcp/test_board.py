"""test_board.py -- tests of board.py's pure parts, with no board: keys,
the tablet's axes, pictures, and parsing what the shell prints. Run by
make test-mcp, with plain python3."""

import struct
import unittest
import zlib

from board import (BoardError, axis, button, crop, key_combo, parse_combo, parse_ppm,
                   parse_dmesg, parse_ps, parse_windows, png, reply_of, wheel)


class Keys(unittest.TestCase):
    def test_letters_and_digits(self):
        self.assertEqual(key_combo("h"), ["h"])
        self.assertEqual(key_combo("7"), ["7"])

    def test_capitals_are_shifted(self):
        self.assertEqual(key_combo("H"), ["shift", "h"])

    def test_punctuation(self):
        # As tests/vt.sh's typekeys types them.
        self.assertEqual(key_combo(" "), ["spc"])
        self.assertEqual(key_combo("&"), ["shift", "7"])
        self.assertEqual(key_combo("/"), ["slash"])
        self.assertEqual(key_combo("."), ["dot"])

    def test_unknown_character(self):
        with self.assertRaises(BoardError):
            key_combo("é")

    def test_combos(self):
        self.assertEqual(parse_combo("ctrl-c"), ["ctrl", "c"])
        self.assertEqual(parse_combo("Esc"), ["esc"])


class Tablet(unittest.TestCase):
    def test_ends_of_the_axes(self):
        self.assertEqual(axis(0, 1280), 0)
        self.assertEqual(axis(1279, 1280), 32767)

    def test_as_vt_sh_scales(self):
        # $(( 640 * 32767 / 1279 ))
        self.assertEqual(axis(640, 1280), 16396)

    def test_off_the_screen_is_its_edge(self):
        self.assertEqual(axis(-5, 800), 0)
        self.assertEqual(axis(5000, 800), 32767)

    def test_wheel_down(self):
        self.assertEqual(wheel(0, 1), button(True, "wheel-down") + button(False, "wheel-down"))

    def test_wheel_up_and_left(self):
        up = button(True, "wheel-up") + button(False, "wheel-up")
        left = button(True, "wheel-left") + button(False, "wheel-left")
        self.assertEqual(wheel(-1, -2), up + up + left)


def ppm(w, h, rgb):
    return b"P6\n%d %d\n255\n" % (w, h) + rgb


class Pictures(unittest.TestCase):
    rgb = bytes(range(2 * 3 * 3))  # 3 wide, 2 high

    def test_parse_ppm(self):
        self.assertEqual(parse_ppm(ppm(3, 2, self.rgb)), (3, 2, self.rgb))

    def test_parse_ppm_with_a_comment(self):
        data = b"P6\n# by qemu\n3 2\n255\n" + self.rgb
        self.assertEqual(parse_ppm(data), (3, 2, self.rgb))

    def test_short_ppm(self):
        with self.assertRaises(BoardError):
            parse_ppm(ppm(3, 2, self.rgb[:-1]))

    def test_crop(self):
        # The right column: pixels 2 and 5.
        self.assertEqual(crop(3, 2, self.rgb, 2, 0, 5, 5), (1, 2, bytes([6, 7, 8, 15, 16, 17])))

    def test_crop_off_the_picture(self):
        with self.assertRaises(BoardError):
            crop(3, 2, self.rgb, 3, 0, 1, 1)

    def test_png_holds_the_rows(self):
        data = png(3, 2, self.rgb)
        self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertEqual(struct.unpack(">II", data[16:24]), (3, 2))
        start = data.index(b"IDAT") + 4
        (length,) = struct.unpack(">I", data[start - 8:start - 4])
        raw = zlib.decompress(data[start:start + length])
        self.assertEqual(raw, b"\x00" + self.rgb[:9] + b"\x00" + self.rgb[9:])


class Shell(unittest.TestCase):
    def test_reply_drops_the_echo_and_prompt(self):
        self.assertEqual(reply_of("ps\n  PID\n    1\nl0s> ", "ps"), "  PID\n    1\n")

    def test_reply_without_echo(self):
        self.assertEqual(reply_of("hi\nl0s> ", "echo hi"), "hi\n")

    def test_reply_not_yet_finished(self):
        self.assertEqual(reply_of("run spin\n", "run spin"), "")

    def test_ps(self):
        text = ("  PID  PARENT  PROGRAM       STATE\n"
                "    1       0  sh            running\n"
                "   10       7  sh            waiting for a message on port 13\n")
        self.assertEqual(parse_ps(text), [
            {"pid": 1, "parent": 0, "program": "sh", "state": "running"},
            {"pid": 10, "parent": 7, "program": "sh", "state": "waiting for a message on port 13"},
        ])

    def test_dmesg(self):
        text = ("[    0.000123] l0s: aarch64, booted with no arguments\n"
                "[   12.500000] sdhci: disk1: an SD card of 268.4 MB, 524288 sectors\n")
        self.assertEqual(parse_dmesg(text), {"messages": [
            {"time": 0.000123, "text": "l0s: aarch64, booted with no arguments"},
            {"time": 12.5, "text": "sdhci: disk1: an SD card of 268.4 MB, 524288 sectors"},
        ], "dropped": 0})

    def test_dmesg_dropped(self):
        text = "(36 earlier messages dropped)\n[    1.000000] l0s: x\nl0s> "
        got = parse_dmesg(text)
        self.assertEqual(got["dropped"], 36)
        self.assertEqual(len(got["messages"]), 1)

    def test_windows(self):
        got = parse_windows("1 vt2 100 90 640 384 front\n0 vt1 40 40 640 384 -\npointer 3 4\n")
        self.assertEqual(got["pointer"], {"x": 3, "y": 4, "cursor": "default"})
        self.assertEqual([w["title"] for w in got["windows"]], ["vt2", "vt1"])
        self.assertEqual(got["windows"][0], {"id": 1, "title": "vt2", "x": 100, "y": 90,
                                             "width": 640, "height": 384, "front": True})

    def test_windows_resize_pointer(self):
        got = parse_windows("1 vt2 100 90 640 384 front\npointer 99 200 ew-resize\n")
        self.assertEqual(got["pointer"], {"x": 99, "y": 200, "cursor": "ew-resize"})

    def test_window_title_with_spaces(self):
        got = parse_windows("2 my window 1 2 3 4 -\n")
        self.assertEqual(got["windows"][0]["title"], "my window")

    def test_windows_error(self):
        got = parse_windows("windows: no compositor\n")
        self.assertEqual(got, {"windows": [], "pointer": None, "errors": ["no compositor"]})


if __name__ == "__main__":
    unittest.main()
