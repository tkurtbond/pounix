# UnixFiles: Paths resolved, and files by descriptor

<!-- Made by doc/mkref.py from UnixFiles.Mod; edit the source, then make doc. -->

What rtl's Files doesn't give: a path with its symbolic links resolved, and a file opened with the options a server needs, as a descriptor its caller reads, can wait on through Tasks, or hands to another library. A descriptor is a LONGINT, as in posockets and polibtls; whoever opened it closes it.

Every descriptor UnixFiles opens is close-on-exec, so no child process inherits it (UnixProcesses, Platform.System).

## Constants

```oberon
nonBlocking* = 0;  (* O_NONBLOCK: a FIFO doesn't stop the open, nor
                      a read with nothing to give, which fails with
                      EAGAIN; a FIFO no writer has yet opened gives
                      the end, 0, except on FreeBSD, EAGAIN *)
noFollow* = 1;     (* O_NOFOLLOW: a symbolic link as the last name
                      fails (ELOOP on Linux and FreeBSD, EMLINK on
                      NetBSD, EMLINK or ELOOP on OpenBSD) *)
```

OpenRead's options

```oberon
regular* = 1; directory* = 2; other* = 3;
```

KindOf's kinds

## Procedures

#### Resolve

```oberon
PROCEDURE Resolve*(path: ARRAY OF CHAR; VAR real: ARRAY OF CHAR;
    VAR err: UnixErrors.Error): BOOLEAN;
```

path with every symbolic link, "." and ".." resolved, in real, as realpath gives it: FALSE, with err, if it can't be, such as for a path that doesn't exist (ENOENT), or one too long for real (ENAMETOOLONG).

#### OpenRead

```oberon
PROCEDURE OpenRead*(path: ARRAY OF CHAR; options: SET; VAR fd: LONGINT;
    VAR err: UnixErrors.Error): BOOLEAN;
```

Opens path for reading, with options, a set of nonBlocking and noFollow: its descriptor in fd, or FALSE, with err, and fd -1.

#### KindOf

```oberon
PROCEDURE KindOf*(fd: LONGINT; VAR kind: INTEGER; VAR err: UnixErrors.Error): BOOLEAN;
```

The kind of file open on fd, by fstat: regular, directory, or other (a FIFO, a device, a socket).

#### Read

```oberon
PROCEDURE Read*(fd: LONGINT; VAR buf: ARRAY OF CHAR; pos, len: LONGINT;
    VAR n: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
```

Reads up to len bytes from fd into buf[pos..]: n, how many, 0 at the end. A non-blocking descriptor with nothing to give fails with EAGAIN. Halts for a negative fd, or pos and len outside buf.

#### Write

```oberon
PROCEDURE Write*(fd: LONGINT; VAR buf: ARRAY OF CHAR; pos, len: LONGINT;
    VAR n: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
```

Writes up to len bytes from buf[pos..] to fd: n, how many, which may be fewer, as for a pipe whose reader is slow. Writing to a pipe no one reads raises SIGPIPE, which ends the program unless it is ignored (posockets' Sockets.IgnoreBrokenPipe); then it fails with EPIPE. Halts for a negative fd, or pos and len outside buf.

#### WaitReadable

```oberon
PROCEDURE WaitReadable*(fd, ms: LONGINT; VAR ready: BOOLEAN;
    VAR err: UnixErrors.Error): BOOLEAN;
```

Waits up to ms milliseconds for fd to have something to read: ready TRUE if it has, or is at its end, or has an error, any of which the next Read gives without waiting; FALSE if ms passed first. A signal doesn't cut the wait short. It waits in the kernel, so it stops every task too: a program running Tasks waits through Tasks.AwaitReadableFor instead. EBADF if fd isn't open. Halts for a negative fd or ms, or ms over 2^31 - 1.

#### Close

```oberon
PROCEDURE Close*(fd: LONGINT);
```

Closes fd. Its result is ignored: nothing UnixFiles opens for writing (a pipe) can lose data in close. Halts for a negative fd.
