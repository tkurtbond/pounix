MODULE UnixProcesses; (* Programs run as child processes *)

(* Runs a program with its arguments as a list, with no shell between,
   so nothing in them needs quoting; each of its standard streams
   inherited, /dev/null, or a pipe to the caller. A program that can't
   be run fails Start with its errno, not a child exiting 127.

   For example:
     cmd := UnixProcesses.NewCommand("openssl");
     UnixProcesses.Add(cmd, "req"); UnixProcesses.Add(cmd, "-new");
     UnixProcesses.SetOutput(cmd, UnixProcesses.null);
     IF UnixProcesses.Start(cmd, p, err) & UnixProcesses.Wait(p, err)
       & p.exited & (p.status = 0) THEN ...

   The child gets SIGPIPE back at its default, though the caller may
   ignore it (posockets' Sockets.IgnoreBrokenPipe), and an empty signal
   mask. No descriptor UnixProcesses opens reaches a later child.

   A Process has no finalizer: one dropped unwaited for stays a zombie,
   and its pipes stay open, as a descriptor dropped unclosed does.
   Whoever starts a process waits for it, and closes its pipes. *)

IMPORT SYSTEM, UnixErrors, UnixFiles;

CONST
  (* What a standard stream of the child is: SetInput, SetOutput,
     SetError *)
  inherit* = 0;   (* the caller's own (the default) *)
  null* = 1;      (* /dev/null: no input, output thrown away *)
  pipe* = 2;      (* a pipe, whose other end is the Process's in, out
                     or err *)
  toOutput* = 3;  (* SetError only: wherever standard output goes *)

  (* PLAN.md, "Halt codes" *)
  AssertArgument = 110; AssertCommand = 111; AssertWaited = 112;
  AssertProcess = 113;

  StepPipe = 1; StepFork = 2;  (* what the C part's start failed at *)
  NameLen = 256;

TYPE
  Arguments = POINTER TO ARRAY OF CHAR;

  (* A program, its arguments, and its standard streams. *)
  Command* = POINTER TO CommandDesc;
  CommandDesc* = RECORD
    args: Arguments;      (* the program, then each argument, each
                             ended by 0X *)
    len, count: LONGINT;  (* bytes used in args, and strings *)
    in, out, err: INTEGER;
    nonBlocking: BOOLEAN
  END;

  (* A started program. in is the write end of its standard input's
     pipe, out and err the read ends of its output's and error's, -1
     for none. Once waited for, exited is TRUE if it exited, with its
     exit status in status, and FALSE if a signal ended it, with the
     signal in status. *)
  Process* = POINTER TO ProcessDesc;
  ProcessDesc* = RECORD
    pid-, in-, out-, err-: LONGINT;
    waited-, exited-: BOOLEAN;
    status-: INTEGER;
    name: ARRAY NameLen OF CHAR  (* the program, for err's text *)
  END;

VAR
  (* Signals for Signal: SIGINT, SIGTERM, SIGKILL *)
  interrupt-, terminate-, kill-: INTEGER;

PROCEDURE ["C", "UnixProcesses.-signal-value"] CSignalValue(which: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "UnixProcesses.-start"] CStart(VAR args: ARRAY OF CHAR;
  len: SYSTEM.INT64; count, in, out, err, nonBlocking: SYSTEM.INT32;
  VAR pid: SYSTEM.INT64; VAR fds: ARRAY OF SYSTEM.INT64;
  VAR step: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "UnixProcesses.-wait"] CWait(pid: SYSTEM.INT64;
  VAR exited, status: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "UnixProcesses.-kill"] CKill(pid: SYSTEM.INT64;
  sig: SYSTEM.INT32): SYSTEM.INT32;

(* Appends s to what, as much of it as fits. *)
PROCEDURE Append(s: ARRAY OF CHAR; VAR what: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE what[i] # 0X DO INC(i) END;
  j := 0;
  WHILE (j < LEN(s)) & (s[j] # 0X) & (i < LEN(what) - 1) DO
    what[i] := s[j]; INC(i); INC(j)
  END;
  what[i] := 0X
END Append;

(* Adds s, and its 0X, to cmd's strings. *)
PROCEDURE AddString(cmd: Command; VAR s: ARRAY OF CHAR);
  VAR n, i: LONGINT; bigger: Arguments;
BEGIN
  n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
  IF cmd.len + n + 1 > LEN(cmd.args^) THEN
    i := 2 * LEN(cmd.args^);
    WHILE cmd.len + n + 1 > i DO i := 2 * i END;
    NEW(bigger, i);
    FOR i := 0 TO cmd.len - 1 DO bigger[i] := cmd.args[i] END;
    cmd.args := bigger
  END;
  FOR i := 0 TO n - 1 DO cmd.args[cmd.len + i] := s[i] END;
  cmd.args[cmd.len + n] := 0X;
  INC(cmd.len, n + 1); INC(cmd.count)
END AddString;

(* A command to run program, with no arguments yet and every stream
   inherited. A program with no "/" is looked for on PATH. Halts for
   the empty name. *)
PROCEDURE NewCommand*(program: ARRAY OF CHAR): Command;
  VAR cmd: Command;
BEGIN
  ASSERT(program[0] # 0X, AssertCommand);
  NEW(cmd); NEW(cmd.args, 256); cmd.len := 0; cmd.count := 0;
  cmd.in := inherit; cmd.out := inherit; cmd.err := inherit;
  cmd.nonBlocking := FALSE;
  AddString(cmd, program);
  RETURN cmd
END NewCommand;

PROCEDURE CheckCommand(cmd: Command);
BEGIN ASSERT((cmd # NIL) & (cmd.count > 0), AssertCommand)
END CheckCommand;

(* Adds arg to cmd's arguments, as it is: no shell sees it. *)
PROCEDURE Add*(cmd: Command; arg: ARRAY OF CHAR);
BEGIN CheckCommand(cmd); AddString(cmd, arg)
END Add;

(* What the child's standard input is: inherit, null or pipe. *)
PROCEDURE SetInput*(cmd: Command; mode: INTEGER);
BEGIN
  CheckCommand(cmd); ASSERT((mode >= inherit) & (mode <= pipe), AssertArgument);
  cmd.in := mode
END SetInput;

(* What the child's standard output is: inherit, null or pipe. *)
PROCEDURE SetOutput*(cmd: Command; mode: INTEGER);
BEGIN
  CheckCommand(cmd); ASSERT((mode >= inherit) & (mode <= pipe), AssertArgument);
  cmd.out := mode
END SetOutput;

(* What the child's standard error is: inherit, null, pipe or
   toOutput. *)
PROCEDURE SetError*(cmd: Command; mode: INTEGER);
BEGIN
  CheckCommand(cmd); ASSERT((mode >= inherit) & (mode <= toOutput), AssertArgument);
  cmd.err := mode
END SetError;

(* Whether the caller's ends of the pipes are non-blocking, for a
   program that waits on them through Tasks; blocking by default. *)
PROCEDURE SetNonBlockingPipes*(cmd: Command; on: BOOLEAN);
BEGIN CheckCommand(cmd); cmd.nonBlocking := on
END SetNonBlockingPipes;

(* Starts cmd's program, as p: FALSE, with err and p NIL, if it can't,
   such as for a program not found (ENOENT) or not executable
   (EACCES). *)
PROCEDURE Start*(cmd: Command; VAR p: Process; VAR err: UnixErrors.Error): BOOLEAN;
  VAR r, step, nb: SYSTEM.INT32; pid: SYSTEM.INT64; fds: ARRAY 3 OF SYSTEM.INT64;
    what: ARRAY NameLen + 16 OF CHAR;
BEGIN
  CheckCommand(cmd);
  IF cmd.nonBlocking THEN nb := 1 ELSE nb := 0 END;
  pid := 0; step := 0;
  r := CStart(cmd.args^, cmd.len, SYSTEM.VAL(SYSTEM.INT32, cmd.count),
    cmd.in, cmd.out, cmd.err, nb, pid, fds, step);
  IF r # 0 THEN
    p := NIL;
    what := "start ";
    Append(cmd.args^, what);
    IF step = StepPipe THEN Append(" (a pipe)", what)
    ELSIF step = StepFork THEN Append(" (fork)", what)
    END;
    UnixErrors.SetSystem(err, r, what);
    RETURN FALSE
  END;
  NEW(p);
  p.pid := SYSTEM.VAL(LONGINT, pid);
  p.in := SYSTEM.VAL(LONGINT, fds[0]); p.out := SYSTEM.VAL(LONGINT, fds[1]);
  p.err := SYSTEM.VAL(LONGINT, fds[2]);
  p.waited := FALSE; p.exited := FALSE; p.status := 0;
  COPY(cmd.args^, p.name);
  UnixErrors.Clear(err);
  RETURN TRUE
END Start;

(* Waits for p to end, then sets exited and status. Halts if p was
   already waited for. *)
PROCEDURE Wait*(p: Process; VAR err: UnixErrors.Error): BOOLEAN;
  VAR r, exited, status: SYSTEM.INT32; what: ARRAY NameLen + 16 OF CHAR;
BEGIN
  ASSERT(p # NIL, AssertProcess); ASSERT(~p.waited, AssertWaited);
  exited := 0; status := 0;
  r := CWait(p.pid, exited, status);
  IF r # 0 THEN
    what := "wait for "; Append(p.name, what);
    UnixErrors.SetSystem(err, r, what);
    RETURN FALSE
  END;
  p.waited := TRUE; p.exited := exited # 0; p.status := status;
  UnixErrors.Clear(err);
  RETURN TRUE
END Wait;

(* Sends p the signal sig: interrupt, terminate or kill. Halts if p was
   already waited for, since its pid may now be another process's. *)
PROCEDURE Signal*(p: Process; sig: INTEGER; VAR err: UnixErrors.Error): BOOLEAN;
  VAR r: SYSTEM.INT32; what: ARRAY NameLen + 16 OF CHAR;
BEGIN
  ASSERT(p # NIL, AssertProcess); ASSERT(~p.waited, AssertWaited);
  ASSERT((sig = interrupt) OR (sig = terminate) OR (sig = kill), AssertArgument);
  r := CKill(p.pid, sig);
  IF r # 0 THEN
    what := "signal "; Append(p.name, what);
    UnixErrors.SetSystem(err, r, what);
    RETURN FALSE
  END;
  UnixErrors.Clear(err);
  RETURN TRUE
END Signal;

(* Closes p's in, if open, so the child reads the end of its input. *)
PROCEDURE CloseInput*(p: Process);
BEGIN
  ASSERT(p # NIL, AssertProcess);
  IF p.in >= 0 THEN UnixFiles.Close(p.in); p.in := -1 END
END CloseInput;

(* Closes whichever of p's pipes are still open. It neither waits for
   p nor ends it. *)
PROCEDURE Close*(p: Process);
BEGIN
  ASSERT(p # NIL, AssertProcess);
  CloseInput(p);
  IF p.out >= 0 THEN UnixFiles.Close(p.out); p.out := -1 END;
  IF p.err >= 0 THEN UnixFiles.Close(p.err); p.err := -1 END
END Close;

BEGIN
  interrupt := CSignalValue(0); terminate := CSignalValue(1); kill := CSignalValue(2)
END UnixProcesses.
