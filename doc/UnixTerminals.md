# UnixTerminals: A terminal's echo, and a pseudo-terminal

<!-- Made by doc/mkref.py from UnixTerminals.Mod; edit the source, then make doc. -->

A program asking for a password or another secret turns the terminal's echo off while it is typed, and back on after; rtl has no way to (pogeminilib's browser, for a Gemini server's status 11). The secret is read as anything else is, from the descriptor; only the echo changes.

A program killed while echo is off leaves the terminal so: the shell doesn't restore it, and "stty echo" (or "stty sane") does.

OpenPseudo gives a pseudo-terminal, so a test can drive a program, or these procedures, as if from a terminal, where make's standard input is /dev/null.

## Procedures

#### IsTerminal

```oberon
PROCEDURE IsTerminal*(fd: LONGINT): BOOLEAN;
```

Whether descriptor fd is a terminal; FALSE, too, if it isn't open. A negative fd halts (110).

#### Echo

```oberon
PROCEDURE Echo*(fd: LONGINT; VAR on: BOOLEAN; VAR err: UnixErrors.Error): BOOLEAN;
```

Whether fd's terminal echoes what is typed, in on: FALSE, with err, if it can't be told, ENOTTY if fd isn't a terminal. A negative fd halts (110).

#### SetEcho

```oberon
PROCEDURE SetEcho*(fd: LONGINT; on: BOOLEAN; VAR err: UnixErrors.Error): BOOLEAN;
```

Turns fd's terminal's echo on or off, at once, changing nothing else: FALSE, with err, if it can't be, ENOTTY if fd isn't a terminal. A negative fd halts (110).

#### OpenPseudo

```oberon
PROCEDURE OpenPseudo*(VAR controller, terminal: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
```

A new pseudo-terminal: what is written to controller is typed at terminal, and what is written to terminal, and echoed there, is read from controller. Both are read-write and close-on-exec, and neither becomes the process's controlling terminal; whoever opened them closes them (UnixFiles.Close). FALSE, with err, if it can't be made, and both -1.
