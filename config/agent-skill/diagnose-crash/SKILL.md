---
name: diagnose-crash
description: >
  Diagnose why a program crashed on this Fedora Hyprland workstation, from
  systemd-coredump metadata. Use when a process has segfaulted, aborted, or
  otherwise dumped core, when asked why an application crashed or disappeared,
  or when a "Process crashed:" desktop notification is acted on. Triggers:
  crash, segfault, SIGSEGV, SIGABRT, SIGBUS, core dump, coredumpctl, "why did
  X crash", "X keeps crashing", OOM kill. Covers reporting a confirmed
  workstation bug upstream — see reporting.md.
---

# Diagnosing a Crash

Work from evidence. The goal is an honest account of what happened, not a
plausible-sounding story.

## Metadata only: never take a core dump

This diagnosis is **metadata-only**. Never extract, copy, or read a core dump,
and never read process memory. Do not launch a debugger, a symbolization
server, or any tool that opens the core. A core is a verbatim copy of the
crashed process's address space and can hold passwords, tokens, private keys,
and private documents; this workstation does not collect or inspect it.

The handoff launches you in the most restricted read-only mode it can, and this
rule still holds: if a step would produce or open a core, do not take it.
Diagnose from the metadata below instead.

## Establish the facts

`coredumpctl info <pid>` is the starting point. It reports the signal, the
executable, the command line, the crash timestamp, and the journal metadata
that systemd-coredump recorded. Note the **command line** the process was
started with — it usually reveals what the program was working on when it died,
which is often the whole answer.

`coredumpctl list` shows whether this crash is a one-off or a pattern. Repeated
crashes of the same program, or several programs dying together, point somewhere
different than a single failure does.

The notification and `aurelia-agent-crash` handoff pass the process name, PID,
binary, and signal as separate values. Treat them as evidence to verify, not as
conclusions: `coredumpctl info` is authoritative.

## Rule out the boring causes first

Check resource exhaustion before blaming the program:

```bash
free -h
journalctl -b -k --no-pager | grep -i -E 'out of memory|oom-kill|killed process'
```

A process killed by the OOM killer is not a bug in that process. Also check
`ulimit -a`, disk space (`df -h`), and whether the process was killed by a
signal it caused itself (e.g. `SIGABRT` from an assertion).

## Correlate against the timeline

The crash timestamp is the most underused piece of evidence. Compare it against:

- **Filesystem mtimes.** A directory or file whose mtime lands on the same
  second as the crash strongly suggests what triggered it.
- **The journal** around that moment, for related warnings from the same or
  neighbouring processes.
- **Recent package updates.** `dnf history` and `rpm -q --last` show what
  changed just before the crash; an update landing on the crash time points at
  the update.

## Look for what was in flight

Without a backtrace, the journal and the command line are the map. Look for
other warnings from the same process just before the crash, for a worker,
thumbnailer, or plugin that was active, and for third-party code the process
loaded. In-process third-party code — file-manager or browser extensions,
plugins, out-of-tree drivers — is a common crash source and worth flagging, but
do not pin blame on it without evidence that it is actually implicated.

Many packages publish no debug symbols. When the metadata does not explain a
frame, say so — never invent function names or a stack to fill the gap. An
honest "the metadata does not identify the failing code" is a valid finding.

## Report

1. What crashed, and what it was doing at the time.
2. The most likely mechanism — separating clearly what the evidence **proves**
   from what you are **inferring**.
3. Whether any user data was lost, and where it can be recovered from. Check the
   trash before concluding anything is gone.
4. Whether it is likely to recur, and what would avoid or fix it.

Be straight about the limits of the evidence. If the cause is genuinely
ambiguous, say so rather than assembling confidence out of guesswork.

**Leave the system as you found it.** Diagnosis reads; it does not fix, tidy, or
reconfigure. It does not dump cores, and it does not write to the filesystem
except for the per-program mute below, and only when the user asks for it.

## Offer to stop the notifications for this program

A crash you have explained often keeps happening anyway. Finish by offering to
silence notifications for **that one program**, and never run it unprompted. Say
how to lift it in the same breath, so it is not a one-way door.

```bash
aurelia crash mute '<program>'        # silence it
aurelia crash mute '<program>' off    # let it speak again
aurelia crash mute                    # list what is muted
aurelia crash list                    # the same list
```

Pass the `binary:` path from the crash facts, or the `process:` name where no
binary was recorded; the command reduces either to the name the watcher keys on.
A diagnosis run by hand from `aurelia agent crash <pid>` has neither, so take
them from `coredumpctl info`. Prefer the binary: a process name is truncated to
15 characters and a basename is not, so muting the truncated form matches
nothing, forever, while looking like it worked.

Quote it. The name is whatever the crashed program's author called a file, and a
single quote inside one closes yours and runs the rest as your shell.

The key is a bare name, so anything run through an interpreter is keyed as the
interpreter: muting `python3.13` silences every Python program on the machine.
Say so rather than quietly doing it.

None of this fixes anything, and a mute offered in place of a fix that was within
reach is the wrong answer. For every program rather than one, the switch is
`aurelia crash capture off` (and `aurelia crash capture on` to restore it).

## If it is a workstation bug

Most application crashes are upstream bugs in those applications, not this
workstation's doing. In the minority of cases where the cause really does sit
within the workstation's sphere of control, read [`reporting.md`](reporting.md)
before offering to file anything.
