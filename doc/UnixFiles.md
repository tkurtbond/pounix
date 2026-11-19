# UnixFiles: Paths resolved, files by descriptor, directories

<!-- Made by doc/mkref.py from UnixFiles.Mod; edit the source, then make doc. -->

What rtl's Files doesn't give: a path with its symbolic links resolved, and a file opened with the options a server needs, as a descriptor its caller reads, can wait on through Tasks, or hands to another library; a file written, renamed and removed with every failure reported, where Files halts (it stops a program that can't create or rename a file); and the names in a directory. A descriptor is a LONGINT, as in posockets and polibtls; whoever opened it closes it, and so with a Directory.

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
create* = 2;       (* O_CREAT: made if it doesn't exist *)
truncate* = 3;     (* O_TRUNC: emptied if it does *)
exclusive* = 4;    (* O_EXCL: with create, EEXIST if it exists, even
                      as a symbolic link, which isn't followed *)
append* = 5;       (* O_APPEND: every write at the end *)
```

OpenWrite's too, besides those two

```oberon
regular* = 1; directory* = 2; other* = 3;
```

KindOf's kinds

```oberon
NameLen* = 512;
```

Room enough for any name NextName gives, and its 0X: NetBSD's may be 511 bytes, the others' 255

## Types

```oberon
Directory* = POINTER TO DirectoryDesc;
DirectoryDesc = RECORD
  handle: SYSTEM.ADDRESS  (* its DIR, 0 once closed *)
```

A directory open for reading its names (OpenDirectory)

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

#### OpenWrite

```oberon
PROCEDURE OpenWrite*(path: ARRAY OF CHAR; options: SET; mode: LONGINT; VAR fd: LONGINT;
    VAR err: UnixErrors.Error): BOOLEAN;
```

Opens path for writing, with options, a set of nonBlocking, noFollow, create, truncate, exclusive and append: its descriptor in fd, or FALSE, with err, and fd -1. A file created has mode, its permission bits as chmod's octal number gives them (600 octal is 180H, 644 is 1A4H), less the umask. Halts for a mode outside 0..7777 octal (0FFFH).

#### ModeOf

```oberon
PROCEDURE ModeOf*(fd: LONGINT; VAR mode: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
```

The permission bits of the file open on fd, by fstat, as OpenWrite takes them (with set-user-ID 800H, set-group-ID 400H and sticky 200H).

#### ChangeMode

```oberon
PROCEDURE ChangeMode*(path: ARRAY OF CHAR; mode: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
```

Sets the permission bits of the file or directory path names to mode, as OpenWrite and ModeOf give them, by chmod, which follows a symbolic link and ignores the umask: such as a directory made for private files made only its owner's (700 octal, 1C0H). Halts for a mode outside 0..7777 octal (0FFFH).

#### Sync

```oberon
PROCEDURE Sync*(fd: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
```

Writes what the system holds of fd's file out to the disk (fsync), reporting a failure to write it that close would not: a file written to be renamed over another is synced first, so a crash leaves the old file or the whole new one.

#### Rename

```oberon
PROCEDURE Rename*(from, to: ARRAY OF CHAR; VAR err: UnixErrors.Error): BOOLEAN;
```

Renames from as to, replacing any file to names, in one step (both in one file system, else EXDEV).

#### Remove

```oberon
PROCEDURE Remove*(path: ARRAY OF CHAR; VAR err: UnixErrors.Error): BOOLEAN;
```

Removes the name path, not a directory's (unlink).

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

Closes fd. Its result is ignored: a file written is synced first (Sync), which reports what close could. Halts for a negative fd.

#### OpenDirectory

```oberon
PROCEDURE OpenDirectory*(path: ARRAY OF CHAR; options: SET; VAR d: Directory;
    VAR err: UnixErrors.Error): BOOLEAN;
```

Opens the directory path for reading its names, with options, of which only noFollow counts: d, or FALSE, with err (ENOTDIR for anything not a directory), and d NIL. Its descriptor is close-on-exec. Close it with CloseDirectory.

#### NextName

```oberon
PROCEDURE NextName*(d: Directory; VAR name: ARRAY OF CHAR; VAR err: UnixErrors.Error): BOOLEAN;
```

The next name in d, in the order the system keeps them, never "." or "..": "" at the end, and again after it. A name that doesn't fit in name fails with ENAMETOOLONG and is passed over; one of NameLen holds any. Any name, hidden ones too: what to show is the caller's to decide. Halts for d NIL or closed.

#### CloseDirectory

```oberon
PROCEDURE CloseDirectory*(d: Directory);
```

Closes d and its descriptor; nothing if it is already closed. Halts for d NIL.
