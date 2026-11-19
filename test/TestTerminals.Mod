MODULE TestTerminals; (* UnixTerminals, on a pseudo-terminal of its own *)

(* make's standard input is /dev/null, so the terminal is one
   OpenPseudo makes: what is written to its controller is typed there,
   and what it echoes is read back from the controller. *)

IMPORT Platform, UnixErrors, UnixFiles, UnixTerminals, Check;

CONST
  LF = 0AX;

VAR
  err: UnixErrors.Error;
  controller, terminal, fd: LONGINT;
  on, ok: BOOLEAN;

(* Whether a child process has descriptor fd open (TestFiles.ChildHas). *)
PROCEDURE ChildHas(fd: LONGINT): BOOLEAN;
  VAR cmd: ARRAY 64 OF CHAR; digits: ARRAY 24 OF CHAR; i, j: LONGINT;
BEGIN
  i := 0; REPEAT digits[i] := CHR(ORD("0") + fd MOD 10); fd := fd DIV 10; INC(i) UNTIL fd = 0;
  cmd := "true 2>/dev/null <&"; j := 0; WHILE cmd[j] # 0X DO INC(j) END;
  WHILE i > 0 DO DEC(i); cmd[j] := digits[i]; INC(j) END;
  cmd[j] := 0X;
  RETURN Platform.System(cmd) = 0
END ChildHas;

(* Whether s starts with head. *)
PROCEDURE StartsWith(s, head: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE (head[i] # 0X) & (s[i] = head[i]) DO INC(i) END;
  RETURN head[i] = 0X
END StartsWith;

(* Types line, and a line's end, at the terminal. *)
PROCEDURE Type(line: ARRAY OF CHAR): BOOLEAN;
  VAR buf: ARRAY 64 OF CHAR; i, n: LONGINT;
BEGIN
  i := 0; WHILE line[i] # 0X DO buf[i] := line[i]; INC(i) END;
  buf[i] := LF; INC(i);
  RETURN UnixFiles.Write(controller, buf, 0, i, n, err) & (n = i)
END Type;

(* Whether fd has something to read within ms, and if so, whether it
   holds part, read into s. *)
PROCEDURE Got(fd, ms: LONGINT; part: ARRAY OF CHAR): BOOLEAN;
  VAR s: ARRAY 256 OF CHAR; n, i, j: LONGINT; ready: BOOLEAN;
BEGIN
  IF ~UnixFiles.WaitReadable(fd, ms, ready, err) OR ~ready THEN RETURN FALSE END;
  IF ~UnixFiles.Read(fd, s, 0, LEN(s) - 1, n, err) THEN RETURN FALSE END;
  s[n] := 0X; i := 0;
  WHILE i < n DO
    j := 0; WHILE (part[j] # 0X) & (s[i + j] = part[j]) DO INC(j) END;
    IF part[j] = 0X THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN FALSE
END Got;

BEGIN
  Check.Check(UnixTerminals.OpenPseudo(controller, terminal, err) & (controller >= 0)
    & (terminal >= 0), "OpenPseudo makes a pseudo-terminal");
  Check.Check(UnixTerminals.IsTerminal(terminal) & UnixTerminals.IsTerminal(controller),
    "IsTerminal: both its sides are terminals");
  Check.Check(~UnixTerminals.IsTerminal(0), "... standard input, /dev/null, isn't");
  Check.Check(~ChildHas(controller) & ~ChildHas(terminal), "... both are close-on-exec");

  on := FALSE;
  Check.Check(UnixTerminals.Echo(terminal, on, err) & on, "Echo: a new one echoes");
  Check.Check(Type("abc") & Got(controller, 2000, "abc"), "... what is typed comes back");
  Check.Check(Got(terminal, 2000, "abc"), "... and is read at the terminal");

  Check.Check(UnixTerminals.SetEcho(terminal, FALSE, err), "SetEcho FALSE");
  on := TRUE;
  Check.Check(UnixTerminals.Echo(terminal, on, err) & ~on, "... Echo says it's off");
  Check.Check(Type("secret") & ~Got(controller, 300, "secret"), "... what is typed doesn't come back");
  Check.Check(Got(terminal, 2000, "secret"), "... but is still read at the terminal");

  Check.Check(UnixTerminals.SetEcho(terminal, TRUE, err), "SetEcho TRUE");
  on := FALSE;
  Check.Check(UnixTerminals.Echo(terminal, on, err) & on, "... Echo says it's on");
  Check.Check(Type("def") & Got(controller, 2000, "def") & Got(terminal, 2000, "def"),
    "... what is typed comes back again");
  Check.Check(UnixTerminals.SetEcho(terminal, TRUE, err), "SetEcho TRUE when it's on already");

  ok := UnixFiles.OpenWrite("../build/test/file", {UnixFiles.create, UnixFiles.truncate}, 1A4H, fd, err);
  Check.Check(ok, "a file");
  IF ok THEN
    Check.Check(~UnixTerminals.IsTerminal(fd), "IsTerminal: a file isn't");
    Check.Check(~UnixTerminals.Echo(fd, on, err) & (err.code = UnixErrors.ENOTTY)
      & StartsWith(err.text, "tcgetattr: "), "Echo of a file: ENOTTY");
    Check.Check(~UnixTerminals.SetEcho(fd, FALSE, err) & (err.code = UnixErrors.ENOTTY),
      "SetEcho of a file: ENOTTY");
    UnixFiles.Close(fd)
  END;

  UnixFiles.Close(terminal); UnixFiles.Close(controller);
  Check.Check(~UnixTerminals.IsTerminal(terminal), "IsTerminal: a closed descriptor isn't");
  Check.Check(~UnixTerminals.Echo(terminal, on, err) & (err.code # 0), "Echo of a closed descriptor fails");
  Check.Summary
END TestTerminals.
