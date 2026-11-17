# UnixProcesses: Programs run as child processes

<!-- Made by doc/mkref.py from UnixProcesses.Mod; edit the source, then make doc. -->

Runs a program with its arguments as a list, with no shell between, so nothing in them needs quoting; each of its standard streams inherited, /dev/null, or a pipe to the caller. A program that can't be run fails Start with its errno, not a child exiting 127.

For example:

```
cmd := UnixProcesses.NewCommand("openssl");
UnixProcesses.Add(cmd, "req"); UnixProcesses.Add(cmd, "-new");
UnixProcesses.SetOutput(cmd, UnixProcesses.null);
IF UnixProcesses.Start(cmd, p, err) & UnixProcesses.Wait(p, err)
  & p.exited & (p.status = 0) THEN ...
```

The child gets SIGPIPE back at its default, though the caller may ignore it (posockets' Sockets.IgnoreBrokenPipe), and an empty signal mask. No descriptor UnixProcesses opens reaches a later child.

A Process has no finalizer: one dropped unwaited for stays a zombie, and its pipes stay open, as a descriptor dropped unclosed does. Whoever starts a process waits for it, and closes its pipes.

## Constants

```oberon
inherit* = 0;   (* the caller's own (the default) *)
null* = 1;      (* /dev/null: no input, output thrown away *)
pipe* = 2;      (* a pipe, whose other end is the Process's in, out
                   or err *)
toOutput* = 3;  (* SetError only: wherever standard output goes *)
```

What a standard stream of the child is: SetInput, SetOutput, SetError

## Types

```oberon
Command* = POINTER TO CommandDesc;
CommandDesc* = RECORD
END;
```

A program, its arguments, and its standard streams.

```oberon
Process* = POINTER TO ProcessDesc;
ProcessDesc* = RECORD
  pid-, in-, out-, err-: LONGINT;
  waited-, exited-: BOOLEAN;
  status-: INTEGER;
END;
```

A started program. in is the write end of its standard input's pipe, out and err the read ends of its output's and error's, -1 for none. Once waited for, exited is TRUE if it exited, with its exit status in status, and FALSE if a signal ended it, with the signal in status.

## Variables

```oberon
interrupt-, terminate-, kill-: INTEGER;
```

Signals for Signal: SIGINT, SIGTERM, SIGKILL

## Procedures

#### NewCommand

```oberon
PROCEDURE NewCommand*(program: ARRAY OF CHAR): Command;
```

A command to run program, with no arguments yet and every stream inherited. A program with no "/" is looked for on PATH. Halts for the empty name.

#### Add

```oberon
PROCEDURE Add*(cmd: Command; arg: ARRAY OF CHAR);
```

Adds arg to cmd's arguments, as it is: no shell sees it.

#### SetInput

```oberon
PROCEDURE SetInput*(cmd: Command; mode: INTEGER);
```

What the child's standard input is: inherit, null or pipe.

#### SetOutput

```oberon
PROCEDURE SetOutput*(cmd: Command; mode: INTEGER);
```

What the child's standard output is: inherit, null or pipe.

#### SetError

```oberon
PROCEDURE SetError*(cmd: Command; mode: INTEGER);
```

What the child's standard error is: inherit, null, pipe or toOutput.

#### SetNonBlockingPipes

```oberon
PROCEDURE SetNonBlockingPipes*(cmd: Command; on: BOOLEAN);
```

Whether the caller's ends of the pipes are non-blocking, for a program that waits on them through Tasks; blocking by default.

#### Start

```oberon
PROCEDURE Start*(cmd: Command; VAR p: Process; VAR err: UnixErrors.Error): BOOLEAN;
```

Starts cmd's program, as p: FALSE, with err and p NIL, if it can't, such as for a program not found (ENOENT) or not executable (EACCES).

#### Wait

```oberon
PROCEDURE Wait*(p: Process; VAR err: UnixErrors.Error): BOOLEAN;
```

Waits for p to end, then sets exited and status. Halts if p was already waited for.

#### Signal

```oberon
PROCEDURE Signal*(p: Process; sig: INTEGER; VAR err: UnixErrors.Error): BOOLEAN;
```

Sends p the signal sig: interrupt, terminate or kill. Halts if p was already waited for, since its pid may now be another process's.

#### CloseInput

```oberon
PROCEDURE CloseInput*(p: Process);
```

Closes p's in, if open, so the child reads the end of its input.

#### Close

```oberon
PROCEDURE Close*(p: Process);
```

Closes whichever of p's pipes are still open. It neither waits for p nor ends it.
