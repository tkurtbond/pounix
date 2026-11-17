MODULE TestFiles; (* UnixFiles, on files made under ../build/test *)

IMPORT Out, Platform, UnixErrors, UnixFiles, Check;

VAR
  err: UnixErrors.Error;
  real, short: ARRAY 4096 OF CHAR;
  tiny: ARRAY 4 OF CHAR;
  buf: ARRAY 16 OF CHAR;
  fd, n: LONGINT;
  kind: INTEGER;
  ok: BOOLEAN;

(* Whether s ends with tail. *)
PROCEDURE EndsWith(s, tail: ARRAY OF CHAR): BOOLEAN;
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  j := 0; WHILE tail[j] # 0X DO INC(j) END;
  IF j > i THEN RETURN FALSE END;
  WHILE (j > 0) & (s[i - 1] = tail[j - 1]) DO DEC(i); DEC(j) END;
  RETURN j = 0
END EndsWith;

(* Whether the shell command cmd exits 0. *)
PROCEDURE Shell(cmd: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN Platform.System(cmd) = 0
END Shell;

(* Whether a child process sees descriptor fd open, where /proc says. *)
PROCEDURE ChildHas(fd: LONGINT): BOOLEAN;
  VAR cmd: ARRAY 64 OF CHAR; digits: ARRAY 24 OF CHAR; i, j: LONGINT;
BEGIN
  i := 0; REPEAT digits[i] := CHR(ORD("0") + fd MOD 10); fd := fd DIV 10; INC(i) UNTIL fd = 0;
  cmd := "test -e /proc/self/fd/"; j := 0; WHILE cmd[j] # 0X DO INC(j) END;
  WHILE i > 0 DO DEC(i); cmd[j] := digits[i]; INC(j) END;
  cmd[j] := 0X;
  RETURN Shell(cmd)
END ChildHas;

BEGIN
  ok := Shell("mkdir -p ../build/test/files/dir && printf 'hello\n' > ../build/test/files/hello.txt && ln -s hello.txt ../build/test/files/link && mkfifo ../build/test/files/fifo");
  Check.Check(ok, "make the files");

  (* Resolve *)
  Check.Check(UnixFiles.Resolve("../build/test/files/dir/../link", real, err) & (err.code = 0)
    & (real[0] = "/") & EndsWith(real, "/build/test/files/hello.txt"),
    "Resolve: a link and .. resolved, absolute");
  Check.Check(~UnixFiles.Resolve("../build/test/files/missing", real, err) & (err.code = UnixErrors.ENOENT)
    & (err.text = "resolve ../build/test/files/missing: No such file or directory")
    & (real = ""),
    "Resolve: a path that doesn't exist, ENOENT");
  Check.Check(~UnixFiles.Resolve("../build/test/files/hello.txt", tiny, err)
    & (err.code = UnixErrors.ENAMETOOLONG) & (tiny = ""),
    "Resolve: too long for real, ENAMETOOLONG");
  Check.Check(~UnixFiles.Resolve("../build/test/files/hello.txt/x", short, err)
    & (err.code = UnixErrors.ENOTDIR),
    "Resolve: through a file, ENOTDIR");

  (* OpenRead, KindOf, Read *)
  Check.Check(UnixFiles.OpenRead("../build/test/files/hello.txt", {}, fd, err) & (fd >= 0) & (err.code = 0),
    "OpenRead: a file");
  Check.Check(UnixFiles.KindOf(fd, kind, err) & (kind = UnixFiles.regular), "KindOf: regular");
  buf := "ab";
  Check.Check(UnixFiles.Read(fd, buf, 2, 10, n, err) & (n = 6)
    & (buf[0] = "a") & (buf[1] = "b") & (buf[2] = "h") & (buf[7] = 0AX),
    "Read: 6 bytes at pos 2");
  Check.Check(UnixFiles.Read(fd, buf, 0, LEN(buf), n, err) & (n = 0), "Read: 0 at the end");
  Check.Check(~UnixFiles.Write(fd, buf, 0, 1, n, err) & (err.code # 0)
    & EndsWith(err.text, "Bad file descriptor"),
    "Write: to a descriptor open for reading fails");
  IF Shell("test -d /proc/self/fd") THEN
    Check.Check(ChildHas(0) & ~ChildHas(fd), "OpenRead: close-on-exec, a child has 0 but not it")
  ELSE
    Out.String("skip - no /proc/self/fd, close-on-exec unchecked"); Out.Ln
  END;
  UnixFiles.Close(fd);

  Check.Check(~UnixFiles.OpenRead("../build/test/files/missing", {}, fd, err) & (fd = -1)
    & (err.code = UnixErrors.ENOENT)
    & (err.text = "open ../build/test/files/missing: No such file or directory"),
    "OpenRead: a file that doesn't exist, ENOENT, fd -1");

  Check.Check(UnixFiles.OpenRead("../build/test/files/dir", {}, fd, err)
    & UnixFiles.KindOf(fd, kind, err) & (kind = UnixFiles.directory),
    "OpenRead, KindOf: a directory");
  UnixFiles.Close(fd);

  Check.Check(UnixFiles.OpenRead("../build/test/files/link", {}, fd, err), "OpenRead: through a link");
  UnixFiles.Close(fd);
  Check.Check(~UnixFiles.OpenRead("../build/test/files/link", {UnixFiles.noFollow}, fd, err)
    & (err.code # 0) & (fd = -1),
    "OpenRead noFollow: a link fails");
  Check.Check(UnixFiles.OpenRead("../build/test/files/hello.txt", {UnixFiles.noFollow}, fd, err),
    "OpenRead noFollow: a file");
  UnixFiles.Close(fd);

  (* a FIFO with no writer: non-blocking, the open doesn't wait *)
  Check.Check(UnixFiles.OpenRead("../build/test/files/fifo", {UnixFiles.nonBlocking}, fd, err)
    & UnixFiles.KindOf(fd, kind, err) & (kind = UnixFiles.other),
    "OpenRead nonBlocking, KindOf: a FIFO, other");
  Check.Check(UnixFiles.Read(fd, buf, 0, LEN(buf), n, err) & (n = 0),
    "Read: a FIFO no one has opened to write, 0");
  UnixFiles.Close(fd);

  Check.Check(UnixFiles.Write(1, buf, 0, 0, n, err) & (n = 0), "Write: nothing");

  Check.Summary
END TestFiles.
