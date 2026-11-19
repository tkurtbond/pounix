MODULE UnixFiles; (* Paths resolved, files by descriptor, directories *)

(* What rtl's Files doesn't give: a path with its symbolic links
   resolved, and a file opened with the options a server needs, as a
   descriptor its caller reads, can wait on through Tasks, or hands to
   another library; a file written, renamed and removed with every
   failure reported, where Files halts (it stops a program that can't
   create or rename a file); and the names in a directory. A descriptor is a
   LONGINT, as in posockets and polibtls; whoever opened it closes it,
   and so with a Directory.

   Every descriptor UnixFiles opens is close-on-exec, so no child
   process inherits it (UnixProcesses, Platform.System). *)

IMPORT SYSTEM, UnixErrors;

CONST
  (* OpenRead's options *)
  nonBlocking* = 0;  (* O_NONBLOCK: a FIFO doesn't stop the open, nor
                        a read with nothing to give, which fails with
                        EAGAIN; a FIFO no writer has yet opened gives
                        the end, 0, except on FreeBSD, EAGAIN *)
  noFollow* = 1;     (* O_NOFOLLOW: a symbolic link as the last name
                        fails (ELOOP on Linux and FreeBSD, EMLINK on
                        NetBSD, EMLINK or ELOOP on OpenBSD) *)
  (* OpenWrite's too, besides those two *)
  create* = 2;       (* O_CREAT: made if it doesn't exist *)
  truncate* = 3;     (* O_TRUNC: emptied if it does *)
  exclusive* = 4;    (* O_EXCL: with create, EEXIST if it exists, even
                        as a symbolic link, which isn't followed *)
  append* = 5;       (* O_APPEND: every write at the end *)

  (* KindOf's kinds *)
  regular* = 1; directory* = 2; other* = 3;

  (* Room enough for any name NextName gives, and its 0X: NetBSD's may
     be 511 bytes, the others' 255 *)
  NameLen* = 512;

  AssertArgument = 110;  (* PLAN.md, "Halt codes" *)
  AssertDirectory = 114;

TYPE
  (* A directory open for reading its names (OpenDirectory) *)
  Directory* = POINTER TO DirectoryDesc;
  DirectoryDesc = RECORD
    handle: SYSTEM.ADDRESS  (* its DIR, 0 once closed *)
  END;

PROCEDURE ["C", "UnixFiles.-resolve"] CResolve(path: ARRAY OF CHAR;
  VAR out: ARRAY OF CHAR; max: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-open-read"] COpenRead(path: ARRAY OF CHAR;
  options: SYSTEM.INT32; VAR fd: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-open-write"] COpenWrite(path: ARRAY OF CHAR;
  options, mode: SYSTEM.INT32; VAR fd: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-kind"] CKind(fd: SYSTEM.INT64;
  VAR kind: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-mode"] CMode(fd: SYSTEM.INT64;
  VAR mode: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-sync"] CSync(fd: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-rename"] CRename(from, to: ARRAY OF CHAR): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-remove"] CRemove(path: ARRAY OF CHAR): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-read"] CRead(fd: SYSTEM.INT64; VAR buf: ARRAY OF CHAR;
  pos, len: SYSTEM.INT64; VAR n: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-write"] CWrite(fd: SYSTEM.INT64; VAR buf: ARRAY OF CHAR;
  pos, len: SYSTEM.INT64; VAR n: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-wait-readable"] CWaitReadable(fd: SYSTEM.INT64;
  ms: SYSTEM.INT32; VAR ready: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-close"] CClose(fd: SYSTEM.INT64);
PROCEDURE ["C", "UnixFiles.-open-directory"] COpenDirectory(path: ARRAY OF CHAR;
  options: SYSTEM.INT32; VAR dir: SYSTEM.ADDRESS): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-next-name"] CNextName(dir: SYSTEM.ADDRESS;
  VAR name: ARRAY OF CHAR; max: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-close-directory"] CCloseDirectory(dir: SYSTEM.ADDRESS);

(* Halts unless s holds a 0X, so C reads no further than s. *)
PROCEDURE CheckString(VAR s: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
  ASSERT(i < LEN(s), AssertArgument)
END CheckString;

(* Halts unless buf[pos..pos+len-1] is inside buf. *)
PROCEDURE CheckRange(VAR buf: ARRAY OF CHAR; pos, len: LONGINT);
BEGIN
  ASSERT((pos >= 0) & (len >= 0) & (pos <= LEN(buf)) & (len <= LEN(buf) - pos),
    AssertArgument)
END CheckRange;

(* Sets err from the C part's result r, for what; TRUE if r is 0. *)
PROCEDURE Outcome(r: SYSTEM.INT32; what, name: ARRAY OF CHAR;
    VAR err: UnixErrors.Error): BOOLEAN;
  VAR text: ARRAY UnixErrors.TextLen OF CHAR; i, j: LONGINT;
BEGIN
  IF r = 0 THEN UnixErrors.Clear(err); RETURN TRUE END;
  COPY(what, text); i := 0; WHILE text[i] # 0X DO INC(i) END;
  IF (name # "") & (i < LEN(text) - 1) THEN
    text[i] := " "; INC(i); j := 0;
    WHILE (j < LEN(name)) & (name[j] # 0X) & (i < LEN(text) - 1) DO
      text[i] := name[j]; INC(i); INC(j)
    END;
    text[i] := 0X
  END;
  UnixErrors.SetSystem(err, r, text);
  RETURN FALSE
END Outcome;

(* path with every symbolic link, "." and ".." resolved, in real, as
   realpath gives it: FALSE, with err, if it can't be, such as for a
   path that doesn't exist (ENOENT), or one too long for real
   (ENAMETOOLONG). *)
PROCEDURE Resolve*(path: ARRAY OF CHAR; VAR real: ARRAY OF CHAR;
    VAR err: UnixErrors.Error): BOOLEAN;
  VAR r: SYSTEM.INT32;
BEGIN
  CheckString(path);
  r := CResolve(path, real, LEN(real));
  IF r # 0 THEN real[0] := 0X END;
  RETURN Outcome(r, "resolve", path, err)
END Resolve;

(* Opens path for reading, with options, a set of nonBlocking and
   noFollow: its descriptor in fd, or FALSE, with err, and fd -1. *)
PROCEDURE OpenRead*(path: ARRAY OF CHAR; options: SET; VAR fd: LONGINT;
    VAR err: UnixErrors.Error): BOOLEAN;
  VAR r, o: SYSTEM.INT32; d: SYSTEM.INT64;
BEGIN
  CheckString(path);
  o := 0;
  IF nonBlocking IN options THEN o := o + 1 END;
  IF noFollow IN options THEN o := o + 2 END;
  d := -1; r := COpenRead(path, o, d);
  fd := SYSTEM.VAL(LONGINT, d);
  RETURN Outcome(r, "open", path, err)
END OpenRead;

(* Opens path for writing, with options, a set of nonBlocking,
   noFollow, create, truncate, exclusive and append: its descriptor in
   fd, or FALSE, with err, and fd -1. A file created has mode, its
   permission bits as chmod's octal number gives them (600 octal is
   180H, 644 is 1A4H), less the umask. Halts for a mode outside 0..7777
   octal (0FFFH). *)
PROCEDURE OpenWrite*(path: ARRAY OF CHAR; options: SET; mode: LONGINT; VAR fd: LONGINT;
    VAR err: UnixErrors.Error): BOOLEAN;
  VAR r, o: SYSTEM.INT32; d: SYSTEM.INT64;
BEGIN
  CheckString(path);
  ASSERT((mode >= 0) & (mode <= 0FFFH), AssertArgument);
  o := 0;
  IF nonBlocking IN options THEN o := o + 1 END;
  IF noFollow IN options THEN o := o + 2 END;
  IF create IN options THEN o := o + 4 END;
  IF truncate IN options THEN o := o + 8 END;
  IF exclusive IN options THEN o := o + 16 END;
  IF append IN options THEN o := o + 32 END;
  d := -1; r := COpenWrite(path, o, SYSTEM.VAL(SYSTEM.INT32, mode), d);
  fd := SYSTEM.VAL(LONGINT, d);
  RETURN Outcome(r, "open", path, err)
END OpenWrite;

(* The permission bits of the file open on fd, by fstat, as OpenWrite
   takes them (with set-user-ID 800H, set-group-ID 400H and sticky
   200H). *)
PROCEDURE ModeOf*(fd: LONGINT; VAR mode: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
  VAR r, m: SYSTEM.INT32;
BEGIN
  ASSERT(fd >= 0, AssertArgument);
  m := 0; r := CMode(fd, m); mode := m;
  RETURN Outcome(r, "fstat", "", err)
END ModeOf;

(* Writes what the system holds of fd's file out to the disk (fsync),
   reporting a failure to write it that close would not: a file written
   to be renamed over another is synced first, so a crash leaves the
   old file or the whole new one. *)
PROCEDURE Sync*(fd: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
BEGIN
  ASSERT(fd >= 0, AssertArgument);
  RETURN Outcome(CSync(fd), "fsync", "", err)
END Sync;

(* Renames from as to, replacing any file to names, in one step (both
   in one file system, else EXDEV). *)
PROCEDURE Rename*(from, to: ARRAY OF CHAR; VAR err: UnixErrors.Error): BOOLEAN;
BEGIN
  CheckString(from); CheckString(to);
  RETURN Outcome(CRename(from, to), "rename", from, err)
END Rename;

(* Removes the name path, not a directory's (unlink). *)
PROCEDURE Remove*(path: ARRAY OF CHAR; VAR err: UnixErrors.Error): BOOLEAN;
BEGIN
  CheckString(path);
  RETURN Outcome(CRemove(path), "unlink", path, err)
END Remove;

(* The kind of file open on fd, by fstat: regular, directory, or other
   (a FIFO, a device, a socket). *)
PROCEDURE KindOf*(fd: LONGINT; VAR kind: INTEGER; VAR err: UnixErrors.Error): BOOLEAN;
  VAR r, k: SYSTEM.INT32;
BEGIN
  ASSERT(fd >= 0, AssertArgument);
  k := 0; r := CKind(fd, k); kind := k;
  RETURN Outcome(r, "fstat", "", err)
END KindOf;

(* Reads up to len bytes from fd into buf[pos..]: n, how many, 0 at the
   end. A non-blocking descriptor with nothing to give fails with
   EAGAIN. Halts for a negative fd, or pos and len outside buf. *)
PROCEDURE Read*(fd: LONGINT; VAR buf: ARRAY OF CHAR; pos, len: LONGINT;
    VAR n: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
  VAR r: SYSTEM.INT32; got: SYSTEM.INT64;
BEGIN
  ASSERT(fd >= 0, AssertArgument); CheckRange(buf, pos, len);
  got := 0; r := CRead(fd, buf, pos, len, got);
  n := SYSTEM.VAL(LONGINT, got);
  RETURN Outcome(r, "read", "", err)
END Read;

(* Writes up to len bytes from buf[pos..] to fd: n, how many, which may
   be fewer, as for a pipe whose reader is slow. Writing to a pipe no
   one reads raises SIGPIPE, which ends the program unless it is
   ignored (posockets' Sockets.IgnoreBrokenPipe); then it fails with
   EPIPE. Halts for a negative fd, or pos and len outside buf. *)
PROCEDURE Write*(fd: LONGINT; VAR buf: ARRAY OF CHAR; pos, len: LONGINT;
    VAR n: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
  VAR r: SYSTEM.INT32; put: SYSTEM.INT64;
BEGIN
  ASSERT(fd >= 0, AssertArgument); CheckRange(buf, pos, len);
  put := 0; r := CWrite(fd, buf, pos, len, put);
  n := SYSTEM.VAL(LONGINT, put);
  RETURN Outcome(r, "write", "", err)
END Write;

(* Waits up to ms milliseconds for fd to have something to read: ready
   TRUE if it has, or is at its end, or has an error, any of which the
   next Read gives without waiting; FALSE if ms passed first. A signal
   doesn't cut the wait short. It waits in the kernel, so it stops
   every task too: a program running Tasks waits through
   Tasks.AwaitReadableFor instead. EBADF if fd isn't open. Halts for a
   negative fd or ms, or ms over 2^31 - 1. *)
PROCEDURE WaitReadable*(fd, ms: LONGINT; VAR ready: BOOLEAN;
    VAR err: UnixErrors.Error): BOOLEAN;
  VAR r, rd: SYSTEM.INT32;
BEGIN
  ASSERT(fd >= 0, AssertArgument);
  ASSERT((ms >= 0) & (ms <= 7FFFFFFFH), AssertArgument);
  rd := 0; r := CWaitReadable(fd, SYSTEM.VAL(SYSTEM.INT32, ms), rd);
  ready := rd # 0;
  RETURN Outcome(r, "poll", "", err)
END WaitReadable;

(* Closes fd. Its result is ignored: a file written is synced first
   (Sync), which reports what close could. Halts for a negative fd. *)
PROCEDURE Close*(fd: LONGINT);
BEGIN
  ASSERT(fd >= 0, AssertArgument);
  CClose(fd)
END Close;

(* Opens the directory path for reading its names, with options, of
   which only noFollow counts: d, or FALSE, with err (ENOTDIR for
   anything not a directory), and d NIL. Its descriptor is
   close-on-exec. Close it with CloseDirectory. *)
PROCEDURE OpenDirectory*(path: ARRAY OF CHAR; options: SET; VAR d: Directory;
    VAR err: UnixErrors.Error): BOOLEAN;
  VAR r, o: SYSTEM.INT32; h: SYSTEM.ADDRESS;
BEGIN
  CheckString(path);
  o := 0; IF noFollow IN options THEN o := 2 END;
  h := 0; r := COpenDirectory(path, o, h);
  IF r = 0 THEN NEW(d); d.handle := h ELSE d := NIL END;
  RETURN Outcome(r, "opendir", path, err)
END OpenDirectory;

(* The next name in d, in the order the system keeps them, never "."
   or "..": "" at the end, and again after it. A name that doesn't fit
   in name fails with ENAMETOOLONG and is passed over; one of NameLen
   holds any. Any name, hidden ones too: what to show is the caller's
   to decide. Halts for d NIL or closed. *)
PROCEDURE NextName*(d: Directory; VAR name: ARRAY OF CHAR; VAR err: UnixErrors.Error): BOOLEAN;
BEGIN
  ASSERT((d # NIL) & (d.handle # 0), AssertDirectory);
  RETURN Outcome(CNextName(d.handle, name, LEN(name)), "readdir", "", err)
END NextName;

(* Closes d and its descriptor; nothing if it is already closed. Halts
   for d NIL. *)
PROCEDURE CloseDirectory*(d: Directory);
BEGIN
  ASSERT(d # NIL, AssertDirectory);
  IF d.handle # 0 THEN CCloseDirectory(d.handle); d.handle := 0 END
END CloseDirectory;

END UnixFiles.
