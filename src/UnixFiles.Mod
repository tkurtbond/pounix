MODULE UnixFiles; (* Paths resolved, and files by descriptor *)

(* What rtl's Files doesn't give: a path with its symbolic links
   resolved, and a file opened with the options a server needs, as a
   descriptor its caller reads, can wait on through Tasks, or hands to
   another library. A descriptor is a LONGINT, as in posockets and
   polibtls; whoever opened it closes it.

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

  (* KindOf's kinds *)
  regular* = 1; directory* = 2; other* = 3;

  AssertArgument = 110;  (* PLAN.md, "Halt codes" *)

PROCEDURE ["C", "UnixFiles.-resolve"] CResolve(path: ARRAY OF CHAR;
  VAR out: ARRAY OF CHAR; max: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-open-read"] COpenRead(path: ARRAY OF CHAR;
  options: SYSTEM.INT32; VAR fd: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-kind"] CKind(fd: SYSTEM.INT64;
  VAR kind: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-read"] CRead(fd: SYSTEM.INT64; VAR buf: ARRAY OF CHAR;
  pos, len: SYSTEM.INT64; VAR n: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-write"] CWrite(fd: SYSTEM.INT64; VAR buf: ARRAY OF CHAR;
  pos, len: SYSTEM.INT64; VAR n: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixFiles.-close"] CClose(fd: SYSTEM.INT64);

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

(* Closes fd. Its result is ignored: nothing UnixFiles opens for writing
   (a pipe) can lose data in close. Halts for a negative fd. *)
PROCEDURE Close*(fd: LONGINT);
BEGIN
  ASSERT(fd >= 0, AssertArgument);
  CClose(fd)
END Close;

END UnixFiles.
