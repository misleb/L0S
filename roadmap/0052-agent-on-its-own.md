# 0052: The agent acts on its own: a time to wake, what it did, and a budget

Track: Agent · Status: idea · Needs: 0043 · Spec: agent.md

## Why

0043's agent only answers: it acts when someone talks to it at the
console, and at no other time. An agent that lives on a board can do
more than that: look at something every morning, finish a task it was
given while no one watches, tidy its own memory. That needs a time of
its own to wake, a way to see afterwards what it did, and a bound on
what it may spend while no one is there to stop it.

## Done when

- `agentd` wakes at times it keeps (the kernel's `alarm_at`), set by
  the person or by the agent itself through a tool, each with what it
  is to do, and runs a turn with no one at the console.
- What it did while no one watched is kept in its home, a log a
  conversation at a time, and shown at the console (and later in 0049's
  app) the next time someone talks to it.
- A budget of its own, in tokens or in money a day, which a turn it
  started itself may not pass; turns someone asked for are not held to
  it. The proxy's counts (0042) are the check on the host's side.
- Host tests with the stand-in model wake it, run a turn, and keep it
  in the log; one past the budget stops.

## Steps

To be written. Open: whether its times survive a reboot (they are a
file in its home, as 0044's history is, read at start); what a turn
alone may do that one with someone there may not, if anything, since
0043 asks no one's yes; whether the budget is counted by `agentd` from
each answer's usage or asked of the proxy.

## Spec changes

- agent.md: waking, the log of what it did alone, the budget.

## Log

- 2026-10-29: written with 0043's steps, when the user decided 0043's
  agent only answers and acting on its own is a goal of its own.
