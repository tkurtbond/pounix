MODULE TestFiles; (* UnixFiles, on files made under ../build/test *)

IMPORT Platform, UnixErrors, UnixFiles, Check;

VAR
  err: UnixErrors.Error;
  real, short: ARRAY 4096 OF CHAR;
  tiny: ARRAY 4 OF CHAR;
  buf: ARRAY 16 OF CHAR;
  fd, n: LONGINT;
  kind: INTEGER;
  ok: BOOLEAN;
  d: UnixFiles.Directory;

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

(* Whether a child process has descriptor fd open: the shell's
   redirection from it fails if not, on Linux and the BSDs alike, which
   don't all have /proc/self/fd. *)
PROCEDURE ChildHas(fd: LONGINT): BOOLEAN;
  VAR cmd: ARRAY 64 OF CHAR; digits: ARRAY 24 OF CHAR; i, j: LONGINT;
BEGIN
  i := 0; REPEAT digits[i] := CHR(ORD("0") + fd MOD 10); fd := fd DIV 10; INC(i) UNTIL fd = 0;
  cmd := "true 2>/dev/null <&"; j := 0; WHILE cmd[j] # 0X DO INC(j) END;
  WHILE i > 0 DO DEC(i); cmd[j] := digits[i]; INC(j) END;
  cmd[j] := 0X;
  RETURN Shell(cmd)
END ChildHas;

(* Reads every name in the directory path into seen, a bit per expected
   name (a, b.txt, .hidden, sub), with name of size; others counts any
   other name, tooLong the ENAMETOOLONGs; FALSE on any other failure. *)
PROCEDURE ReadAll(path: ARRAY OF CHAR; size: INTEGER; VAR seen: SET;
    VAR others, tooLong: INTEGER): BOOLEAN;
  VAR name: ARRAY UnixFiles.NameLen OF CHAR; small: ARRAY 4 OF CHAR;
    dir: UnixFiles.Directory; e: UnixErrors.Error; got: BOOLEAN;
BEGIN
  seen := {}; others := 0; tooLong := 0;
  IF ~UnixFiles.OpenDirectory(path, {}, dir, e) THEN RETURN FALSE END;
  LOOP
    IF size = LEN(small) THEN got := UnixFiles.NextName(dir, small, e); COPY(small, name)
    ELSE got := UnixFiles.NextName(dir, name, e)
    END;
    IF ~got THEN
      IF e.code = UnixErrors.ENAMETOOLONG THEN INC(tooLong)
      ELSE UnixFiles.CloseDirectory(dir); RETURN FALSE
      END
    ELSIF name = "" THEN EXIT
    ELSIF name = "a" THEN INCL(seen, 0)
    ELSIF name = "b.txt" THEN INCL(seen, 1)
    ELSIF name = ".hidden" THEN INCL(seen, 2)
    ELSIF name = "sub" THEN INCL(seen, 3)
    ELSE INC(others)
    END
  END;
  (* the end again *)
  got := UnixFiles.NextName(dir, name, e) & (name = "");
  UnixFiles.CloseDirectory(dir); UnixFiles.CloseDirectory(dir);
  RETURN got
END ReadAll;

PROCEDURE Directories;
  VAR seen: SET; others, tooLong: INTEGER; f: LONGINT; name: ARRAY UnixFiles.NameLen OF CHAR;
BEGIN
  ok := Shell("mkdir -p ../build/test/files/listing/sub && touch ../build/test/files/listing/a ../build/test/files/listing/b.txt ../build/test/files/listing/.hidden && ln -s listing ../build/test/files/dirlink");
  Check.Check(ok, "make a directory to list");
  Check.Check(ReadAll("../build/test/files/listing", UnixFiles.NameLen, seen, others, tooLong)
    & (seen = {0..3}) & (others = 0) & (tooLong = 0),
    "OpenDirectory, NextName: every name, hidden too, not . or .., then the end, again");
  Check.Check(ReadAll("../build/test/files/listing", 4, seen, others, tooLong)
    & (seen = {0, 3}) & (others = 0) & (tooLong = 2),
    "NextName: a name too long for name, ENAMETOOLONG, passed over");
  Check.Check(ReadAll("../build/test/files/dirlink", UnixFiles.NameLen, seen, others, tooLong)
    & (seen = {0..3}),
    "OpenDirectory: through a link");
  Check.Check(~UnixFiles.OpenDirectory("../build/test/files/dirlink", {UnixFiles.noFollow}, d, err)
    & (err.code # 0) & (d = NIL),
    "OpenDirectory noFollow: a link fails");
  Check.Check(~UnixFiles.OpenDirectory("../build/test/files/hello.txt", {}, d, err)
    & (err.code = UnixErrors.ENOTDIR) & (d = NIL)
    & (err.text = "opendir ../build/test/files/hello.txt: Not a directory"),
    "OpenDirectory: a file, ENOTDIR");
  Check.Check(~UnixFiles.OpenDirectory("../build/test/files/fifo", {}, d, err)
    & (err.code = UnixErrors.ENOTDIR),
    "OpenDirectory: a FIFO, ENOTDIR, without waiting for a writer");
  Check.Check(~UnixFiles.OpenDirectory("../build/test/files/missing", {}, d, err)
    & (err.code = UnixErrors.ENOENT),
    "OpenDirectory: a directory that doesn't exist, ENOENT");
  (* the lowest descriptor free is the one open takes *)
  ok := UnixFiles.OpenRead("../build/test/files/hello.txt", {}, f, err);
  UnixFiles.Close(f);
  ok := ok & UnixFiles.OpenDirectory("../build/test/files/listing", {}, d, err)
    & UnixFiles.OpenRead("../build/test/files/hello.txt", {}, fd, err) & (fd # f);
  Check.Check(ok & ChildHas(0) & ~ChildHas(f), "OpenDirectory: close-on-exec, a child hasn't it");
  UnixFiles.Close(fd);
  UnixFiles.CloseDirectory(d);
  ok := UnixFiles.OpenRead("../build/test/files/hello.txt", {}, fd, err) & (fd = f);
  Check.Check(ok, "CloseDirectory: its descriptor closed");
  UnixFiles.Close(fd);
  Check.Check(UnixFiles.OpenDirectory("../build/test/files/listing/sub", {}, d, err)
    & UnixFiles.NextName(d, name, err) & (name = ""),
    "NextName: an empty directory, the end at once");
  UnixFiles.CloseDirectory(d)
END Directories;

(* Reads the file path whole into s (at most LEN(s) - 1 bytes): FALSE
   if it can't be read. *)
PROCEDURE Contents(path: ARRAY OF CHAR; VAR s: ARRAY OF CHAR): BOOLEAN;
  VAR f, k, m: LONGINT; e: UnixErrors.Error;
BEGIN
  s[0] := 0X;
  IF ~UnixFiles.OpenRead(path, {}, f, e) THEN RETURN FALSE END;
  k := 0;
  WHILE UnixFiles.Read(f, s, k, LEN(s) - 1 - k, m, e) & (m > 0) DO INC(k, m) END;
  s[k] := 0X; UnixFiles.Close(f);
  RETURN e.code = 0
END Contents;

(* OpenWrite, ModeOf, Sync, Rename, Remove *)
PROCEDURE Writing;
  VAR f, mode: LONGINT; text: ARRAY 64 OF CHAR;
BEGIN
  ok := Shell("mkdir -p ../build/test/files/w && ln -s ../hello.txt ../build/test/files/w/link");
  Check.Check(ok, "make a directory to write in");

  text := "one.";
  Check.Check(UnixFiles.OpenWrite("../build/test/files/w/a", {UnixFiles.create, UnixFiles.exclusive}, 180H, f, err)
    & (f >= 0) & UnixFiles.Write(f, text, 0, 4, n, err) & (n = 4)
    & UnixFiles.Sync(f, err),
    "OpenWrite create exclusive: a new file written and synced");
  Check.Check(UnixFiles.ModeOf(f, mode, err) & (mode = 180H), "ModeOf: 600 octal, as asked");
  Check.Check(ChildHas(0) & ~ChildHas(f), "OpenWrite: close-on-exec");
  UnixFiles.Close(f);
  Check.Check(Contents("../build/test/files/w/a", text) & (text = "one."), "OpenWrite: what was written is there");

  Check.Check(~UnixFiles.OpenWrite("../build/test/files/w/a", {UnixFiles.create, UnixFiles.exclusive}, 180H, f, err)
    & (f = -1) & (err.code = UnixErrors.EEXIST),
    "OpenWrite create exclusive: an existing file, EEXIST");
  Check.Check(~UnixFiles.OpenWrite("../build/test/files/w/link", {UnixFiles.create, UnixFiles.exclusive}, 180H, f, err)
    & (err.code = UnixErrors.EEXIST) & Contents("../build/test/files/hello.txt", text)
    & (text[0] = "h") & (text[5] = 0AX) & (text[6] = 0X),
    "OpenWrite create exclusive: a link isn't followed, EEXIST");
  Check.Check(~UnixFiles.OpenWrite("../build/test/files/w/b", {}, 180H, f, err) & (err.code = UnixErrors.ENOENT),
    "OpenWrite: no file, not create, ENOENT");

  text := "xy";
  Check.Check(UnixFiles.OpenWrite("../build/test/files/w/a", {UnixFiles.append}, 0, f, err)
    & UnixFiles.Write(f, text, 0, 2, n, err) & (n = 2),
    "OpenWrite append");
  UnixFiles.Close(f);
  Check.Check(Contents("../build/test/files/w/a", text) & (text = "one.xy"), "OpenWrite append: at the end");
  text := "z";
  Check.Check(UnixFiles.OpenWrite("../build/test/files/w/a", {UnixFiles.truncate}, 0, f, err)
    & UnixFiles.Write(f, text, 0, 1, n, err) & UnixFiles.ModeOf(f, mode, err) & (mode = 180H),
    "OpenWrite truncate: the mode unchanged");
  UnixFiles.Close(f);
  Check.Check(Contents("../build/test/files/w/a", text) & (text = "z"), "OpenWrite truncate: emptied first");

  (* 700 octal, which no usual umask takes from *)
  Check.Check(UnixFiles.OpenWrite("../build/test/files/w/c", {UnixFiles.create}, 1C0H, f, err)
    & UnixFiles.ModeOf(f, mode, err) & (mode = 1C0H),
    "OpenWrite create: 700 octal");
  UnixFiles.Close(f);

  Check.Check(UnixFiles.Rename("../build/test/files/w/a", "../build/test/files/w/c", err) & Contents("../build/test/files/w/c", text) & (text = "z")
    & ~UnixFiles.OpenRead("../build/test/files/w/a", {}, f, err),
    "Rename: over another file");
  Check.Check(~UnixFiles.Rename("../build/test/files/w/a", "../build/test/files/w/d", err) & (err.code = UnixErrors.ENOENT)
    & (err.text = "rename ../build/test/files/w/a: No such file or directory"),
    "Rename: no such file, ENOENT");
  Check.Check(UnixFiles.Remove("../build/test/files/w/c", err) & ~UnixFiles.OpenRead("../build/test/files/w/c", {}, f, err),
    "Remove");
  Check.Check(~UnixFiles.Remove("../build/test/files/w/c", err) & (err.code = UnixErrors.ENOENT)
    & (err.text = "unlink ../build/test/files/w/c: No such file or directory"),
    "Remove: no such file, ENOENT");
  Check.Check(UnixFiles.Remove("../build/test/files/w/link", err) & Contents("../build/test/files/hello.txt", text)
    & (text[0] = "h") & (text[5] = 0AX) & (text[6] = 0X),
    "Remove: a link, not what it names")
END Writing;

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
  Check.Check(ChildHas(0) & ~ChildHas(fd), "OpenRead: close-on-exec, a child has 0 but not it");
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
  (* the end at once, except on FreeBSD, which gives EAGAIN until a
     writer has opened it *)
  Check.Check(UnixFiles.Read(fd, buf, 0, LEN(buf), n, err) & (n = 0)
    OR (err.code = UnixErrors.EAGAIN),
    "Read: a FIFO no one has opened to write, 0 or EAGAIN");
  UnixFiles.Close(fd);

  Check.Check(UnixFiles.Write(1, buf, 0, 0, n, err) & (n = 0), "Write: nothing");

  Directories;
  Writing;

  Check.Summary
END TestFiles.
