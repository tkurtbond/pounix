MODULE TestProcesses; (* UnixProcesses, running sh, cat, sleep and true *)

IMPORT SYSTEM, Out, Platform, UnixErrors, UnixFiles, UnixProcesses, Check;

CONST
  (* SIGPIPE and SIG_IGN, the same on Linux and the BSDs: for this test
     only, to ignore SIGPIPE as a server does *)
  SIGPIPE = 13; SIGIGN = 1;

VAR
  err: UnixErrors.Error;
  cmd: UnixProcesses.Command;
  p, q: UnixProcesses.Process;
  text, expected: ARRAY 256 OF CHAR;
  quote, nl: ARRAY 2 OF CHAR;
  n: LONGINT;
  ok: BOOLEAN;

PROCEDURE ["C", "signal"] CSignal(sig: SYSTEM.INT32; handler: SYSTEM.ADDRESS): SYSTEM.ADDRESS;

(* Appends s to t. *)
PROCEDURE Append(s: ARRAY OF CHAR; VAR t: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE t[i] # 0X DO INC(i) END;
  j := 0; WHILE s[j] # 0X DO t[i] := s[j]; INC(i); INC(j) END;
  t[i] := 0X
END Append;

(* Everything fd gives until its end, as text. *)
PROCEDURE ReadAll(fd: LONGINT; VAR t: ARRAY OF CHAR): BOOLEAN;
  VAR pos, got: LONGINT; e: UnixErrors.Error;
BEGIN
  pos := 0;
  REPEAT
    IF ~UnixFiles.Read(fd, t, pos, LEN(t) - 1 - pos, got, e) THEN t[pos] := 0X; RETURN FALSE END;
    INC(pos, got)
  UNTIL (got = 0) OR (pos = LEN(t) - 1);
  t[pos] := 0X;
  RETURN TRUE
END ReadAll;

(* Runs cmd and waits for it: whether it ran. *)
PROCEDURE Run(cmd: UnixProcesses.Command; VAR p: UnixProcesses.Process): BOOLEAN;
  VAR e: UnixErrors.Error;
BEGIN RETURN UnixProcesses.Start(cmd, p, e) & UnixProcesses.Wait(p, e)
END Run;

(* A command running sh -c script. *)
PROCEDURE Sh(script: ARRAY OF CHAR): UnixProcesses.Command;
  VAR c: UnixProcesses.Command;
BEGIN
  c := UnixProcesses.NewCommand("sh"); UnixProcesses.Add(c, "-c"); UnixProcesses.Add(c, script);
  RETURN c
END Sh;

(* Whether a child process sees descriptor fd open, where /proc says. *)
PROCEDURE ChildHas(fd: LONGINT): BOOLEAN;
  VAR c: UnixProcesses.Command; r: UnixProcesses.Process; path: ARRAY 64 OF CHAR;
    digits: ARRAY 24 OF CHAR; i, j: LONGINT;
BEGIN
  i := 0; REPEAT digits[i] := CHR(ORD("0") + fd MOD 10); fd := fd DIV 10; INC(i) UNTIL fd = 0;
  path := "/proc/self/fd/"; j := 0; WHILE path[j] # 0X DO INC(j) END;
  WHILE i > 0 DO DEC(i); path[j] := digits[i]; INC(j) END;
  path[j] := 0X;
  c := UnixProcesses.NewCommand("test"); UnixProcesses.Add(c, "-e"); UnixProcesses.Add(c, path);
  RETURN Run(c, r) & r.exited & (r.status = 0)
END ChildHas;

BEGIN
  IF CSignal(SIGPIPE, SIGIGN) = 0 THEN END;

  (* exit status *)
  Check.Check(Run(UnixProcesses.NewCommand("true"), p) & p.waited & p.exited & (p.status = 0)
    & (p.in = -1) & (p.out = -1) & (p.err = -1),
    "true: exits 0, no pipes");
  Check.Check(Run(Sh("exit 7"), p) & p.exited & (p.status = 7), "sh -c 'exit 7': exits 7");

  (* a program that can't be run *)
  Check.Check(~UnixProcesses.Start(UnixProcesses.NewCommand("pounix-no-such-program"), p, err)
    & (p = NIL) & (err.code = UnixErrors.ENOENT)
    & (err.text = "start pounix-no-such-program: No such file or directory"),
    "Start: a program not on PATH, ENOENT");
  ok := Platform.System("mkdir -p ../build/test/processes && printf 'exit 0\n' > ../build/test/processes/not-executable && chmod 644 ../build/test/processes/not-executable") = 0;
  Check.Check(ok & ~UnixProcesses.Start(UnixProcesses.NewCommand("../build/test/processes/not-executable"), p, err)
    & (err.code = UnixErrors.EACCES),
    "Start: a file not executable, EACCES");

  (* arguments reach the child unchanged *)
  cmd := Sh('printf "%s|" "$@"');
  UnixProcesses.Add(cmd, "sh"); UnixProcesses.Add(cmd, "a b"); UnixProcesses.Add(cmd, "it's");
  quote[0] := 22X; quote[1] := 0X;
  expected := "x"; Append(quote, expected); Append("y", expected);
  UnixProcesses.Add(cmd, expected); UnixProcesses.Add(cmd, "$HOME"); UnixProcesses.Add(cmd, "");
  UnixProcesses.Add(cmd, "*");
  UnixProcesses.SetOutput(cmd, UnixProcesses.pipe);
  expected := "a b|it's|x"; Append(quote, expected); Append("y|$HOME||*|", expected);
  Check.Check(UnixProcesses.Start(cmd, p, err) & (p.out >= 0) & ReadAll(p.out, text)
    & UnixProcesses.Wait(p, err) & p.exited & (p.status = 0) & (text = expected),
    "arguments with spaces, quotes, $, *, and empty, unchanged");
  UnixProcesses.Close(p);
  Check.Check(p.out = -1, "Close: out closed");

  (* pipes both ways *)
  cmd := UnixProcesses.NewCommand("cat");
  UnixProcesses.SetInput(cmd, UnixProcesses.pipe); UnixProcesses.SetOutput(cmd, UnixProcesses.pipe);
  text := "hello, cat";
  Check.Check(UnixProcesses.Start(cmd, p, err) & (p.in >= 0) & (p.out >= 0) & (p.err = -1)
    & UnixFiles.Write(p.in, text, 0, 10, n, err) & (n = 10),
    "cat: write to its input");
  IF Platform.System("test -d /proc/self/fd") = 0 THEN
    Check.Check(ChildHas(0) & ~ChildHas(p.in) & ~ChildHas(p.out),
      "a later child has none of an earlier one's pipes")
  ELSE
    Out.String("skip - no /proc/self/fd, pipes in a later child unchecked"); Out.Ln
  END;
  UnixProcesses.CloseInput(p);
  Check.Check((p.in = -1) & ReadAll(p.out, text) & (text = "hello, cat")
    & UnixProcesses.Wait(p, err) & p.exited & (p.status = 0),
    "cat: after CloseInput, its output and exit 0");
  UnixProcesses.Close(p);

  (* /dev/null, and toOutput *)
  cmd := UnixProcesses.NewCommand("cat");
  UnixProcesses.SetInput(cmd, UnixProcesses.null); UnixProcesses.SetOutput(cmd, UnixProcesses.pipe);
  Check.Check(UnixProcesses.Start(cmd, p, err) & ReadAll(p.out, text) & (text = "")
    & UnixProcesses.Wait(p, err) & p.exited & (p.status = 0),
    "null input: cat reads nothing");
  UnixProcesses.Close(p);
  cmd := Sh("echo out; echo err >&2"); nl[0] := 0AX; nl[1] := 0X;
  expected := "out"; Append(nl, expected); Append("err", expected); Append(nl, expected);
  UnixProcesses.SetOutput(cmd, UnixProcesses.pipe); UnixProcesses.SetError(cmd, UnixProcesses.toOutput);
  Check.Check(UnixProcesses.Start(cmd, p, err) & (p.err = -1) & ReadAll(p.out, text)
    & (text = expected) & UnixProcesses.Wait(p, err),
    "toOutput: standard error to the output's pipe");
  UnixProcesses.Close(p);
  cmd := Sh("echo err >&2"); expected := "err"; Append(nl, expected);
  UnixProcesses.SetOutput(cmd, UnixProcesses.null); UnixProcesses.SetError(cmd, UnixProcesses.pipe);
  Check.Check(UnixProcesses.Start(cmd, p, err) & (p.out = -1) & (p.err >= 0) & ReadAll(p.err, text)
    & (text = expected) & UnixProcesses.Wait(p, err),
    "error to a pipe of its own");
  UnixProcesses.Close(p);

  (* non-blocking pipes *)
  cmd := UnixProcesses.NewCommand("cat");
  UnixProcesses.SetInput(cmd, UnixProcesses.pipe); UnixProcesses.SetOutput(cmd, UnixProcesses.pipe);
  UnixProcesses.SetNonBlockingPipes(cmd, TRUE);
  Check.Check(UnixProcesses.Start(cmd, p, err) & ~UnixFiles.Read(p.out, text, 0, 10, n, err)
    & (err.code = UnixErrors.EAGAIN),
    "SetNonBlockingPipes: nothing to read yet, EAGAIN");
  UnixProcesses.CloseInput(p);
  Check.Check(UnixProcesses.Wait(p, err) & p.exited & (p.status = 0), "and cat ends");
  UnixProcesses.Close(p);

  (* signals *)
  cmd := UnixProcesses.NewCommand("sleep"); UnixProcesses.Add(cmd, "30");
  Check.Check(UnixProcesses.Start(cmd, p, err) & UnixProcesses.Signal(p, UnixProcesses.terminate, err)
    & UnixProcesses.Wait(p, err) & ~p.exited & (p.status = UnixProcesses.terminate),
    "Signal terminate: sleep ends by SIGTERM");
  cmd := UnixProcesses.NewCommand("sleep"); UnixProcesses.Add(cmd, "30");
  Check.Check(UnixProcesses.Start(cmd, q, err) & UnixProcesses.Signal(q, UnixProcesses.kill, err)
    & UnixProcesses.Wait(q, err) & ~q.exited & (q.status = UnixProcesses.kill),
    "Signal kill: sleep ends by SIGKILL");

  (* SIGPIPE, ignored here, is the default in the child: sh can't
     change a signal ignored on entry, so it survives if not *)
  Check.Check(Run(Sh("kill -PIPE $$; exit 0"), p) & ~p.exited & (p.status = SIGPIPE),
    "the child has SIGPIPE at its default, though ignored here");

  Check.Summary
END TestProcesses.
