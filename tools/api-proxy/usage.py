"""usage.py -- what a model's answer spent, pure: the usage of an event
stream (read as its bytes pass, message_start's usage, then each
message_delta's over it) or of a JSON answer, the usage file's line for an
answer, and a day's totals from the file's lines.

The four counts are the Messages API's: input_tokens, output_tokens,
cache_creation_input_tokens (the cache written) and
cache_read_input_tokens (the cache read). Times are UTC, written
YYYY-MM-DDTHH:MM:SSZ, so a day is the lines whose time starts with it."""

import json
import time

COUNTS = ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")


def zero():
    """No usage: each count 0."""
    return {k: 0 for k in COUNTS}


def merged(into, usage):
    """into with each count usage holds as an int put over it."""
    if isinstance(usage, dict):
        for k in COUNTS:
            v = usage.get(k)
            if isinstance(v, int) and not isinstance(v, bool):
                into[k] = v
    return into


class StreamUsage:
    """An event stream's usage, fed its bytes as they pass. A line ends at
    LF, a CR before it dropped; a blank line ends an event; data lines
    are joined by newlines, as the stream's format has it."""

    def __init__(self):
        self.held = b""
        self.name = ""
        self.data = []
        self.usage = zero()
        self.model = ""

    def feed(self, piece):
        """The next piece of the stream."""
        self.held += piece
        while True:
            at = self.held.find(b"\n")
            if at < 0:
                return
            line = self.held[:at].rstrip(b"\r")
            self.held = self.held[at + 1:]
            self.line(line)

    def line(self, line):
        """One line of the stream."""
        if line == b"":
            if self.data:
                self.event(self.name, b"\n".join(self.data))
            self.name, self.data = "", []
        elif line.startswith(b":"):
            pass
        else:
            field, _, value = line.partition(b":")
            if value.startswith(b" "):
                value = value[1:]
            if field == b"event":
                self.name = value.decode("utf-8", "replace")
            elif field == b"data":
                self.data.append(value)

    def event(self, name, data):
        """An event ended: message_start's usage and model, and
        message_delta's usage, taken."""
        try:
            v = json.loads(data)
        except ValueError:
            return
        if not isinstance(v, dict):
            return
        if name == "message_start" and isinstance(v.get("message"), dict):
            m = v["message"]
            merged(self.usage, m.get("usage"))
            if isinstance(m.get("model"), str):
                self.model = m["model"]
        elif name == "message_delta":
            merged(self.usage, v.get("usage"))


def stream_usage(body):
    """The usage of a whole event stream's bytes."""
    s = StreamUsage()
    s.feed(body)
    s.feed(b"\n\n")
    return s.usage


def json_usage(body):
    """The usage of a JSON answer's bytes: its usage object's counts, or
    none if it has none or is not JSON."""
    try:
        v = json.loads(body)
    except ValueError:
        return zero()
    if not isinstance(v, dict):
        return zero()
    return merged(zero(), v.get("usage"))


def request_model(body):
    """The model a request's JSON body names, or empty."""
    try:
        v = json.loads(body)
    except ValueError:
        return ""
    if isinstance(v, dict) and isinstance(v.get("model"), str):
        return v["model"]
    return ""


def stamp(t=None):
    """The time t, seconds since the epoch (now if none), as UTC."""
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() if t is None else t))


def log_line(when, path, model, status, usage):
    """The usage file's line for an answer: a JSON object, compact, with
    no newline."""
    rec = {"time": when, "path": path, "model": model, "status": status}
    rec.update({k: usage.get(k, 0) for k in COUNTS})
    return json.dumps(rec, separators=(",", ":"))


def day_totals(lines, day):
    """The totals of the lines of day, YYYY-MM-DD: answers, and each
    count. A line that is not a record is passed over."""
    tot = {"day": day, "answers": 0}
    tot.update(zero())
    for line in lines:
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if not isinstance(rec, dict) or not str(rec.get("time", "")).startswith(day):
            continue
        tot["answers"] += 1
        for k in COUNTS:
            v = rec.get(k, 0)
            if isinstance(v, int):
                tot[k] += v
    return tot


def totals_text(tot):
    """A day's totals as a line to read."""
    return "%s: %d answers, input %d, output %d, cache written %d, cache read %d" % (
        tot["day"], tot["answers"], tot["input_tokens"], tot["output_tokens"],
        tot["cache_creation_input_tokens"], tot["cache_read_input_tokens"])
