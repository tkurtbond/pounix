MODULE UnixTerminals; (* A terminal's echo, and a pseudo-terminal *)

(* A program asking for a password or another secret turns the
   terminal's echo off while it is typed, and back on after; rtl has no
   way to (pogeminilib's browser, for a Gemini server's status 11).
   The secret is read as anything else is, from the descriptor; only
   the echo changes.

   A program killed while echo is off leaves the terminal so: the
   shell doesn't restore it, and "stty echo" (or "stty sane") does.

   OpenPseudo gives a pseudo-terminal, so a test can drive a program,
   or these procedures, as if from a terminal, where make's standard
   input is /dev/null. *)

IMPORT SYSTEM, UnixErrors;

CONST
  AssertArgument = 110;  (* PLAN.md, "Halt codes" *)

PROCEDURE ["C", "UnixTerminals.-is-terminal"] CIsTerminal(fd: SYSTEM.INT64): SYSTEM.INT32;
PROCEDURE ["C", "UnixTerminals.-echo"] CEcho(fd: SYSTEM.INT64;
  VAR on: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "UnixTerminals.-set-echo"] CSetEcho(fd: SYSTEM.INT64;
  on: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "UnixTerminals.-open-pseudo"] COpenPseudo(VAR controller,
  terminal: SYSTEM.INT64): SYSTEM.INT32;

(* Sets err from the C part's result r, for what; TRUE if r is 0. *)
PROCEDURE Outcome(r: SYSTEM.INT32; what: ARRAY OF CHAR;
    VAR err: UnixErrors.Error): BOOLEAN;
BEGIN
  IF r = 0 THEN UnixErrors.Clear(err); RETURN TRUE END;
  UnixErrors.SetSystem(err, r, what);
  RETURN FALSE
END Outcome;

(* Whether descriptor fd is a terminal; FALSE, too, if it isn't open.
   A negative fd halts (110). *)
PROCEDURE IsTerminal*(fd: LONGINT): BOOLEAN;
BEGIN
  ASSERT(fd >= 0, AssertArgument);
  RETURN CIsTerminal(fd) = 1
END IsTerminal;

(* Whether fd's terminal echoes what is typed, in on: FALSE, with err,
   if it can't be told, ENOTTY if fd isn't a terminal. A negative fd
   halts (110). *)
PROCEDURE Echo*(fd: LONGINT; VAR on: BOOLEAN; VAR err: UnixErrors.Error): BOOLEAN;
  VAR v: SYSTEM.INT32;
BEGIN
  ASSERT(fd >= 0, AssertArgument);
  v := 0;
  IF ~Outcome(CEcho(fd, v), "tcgetattr", err) THEN RETURN FALSE END;
  on := v # 0;
  RETURN TRUE
END Echo;

(* Turns fd's terminal's echo on or off, at once, changing nothing
   else: FALSE, with err, if it can't be, ENOTTY if fd isn't a
   terminal. A negative fd halts (110). *)
PROCEDURE SetEcho*(fd: LONGINT; on: BOOLEAN; VAR err: UnixErrors.Error): BOOLEAN;
  VAR v: SYSTEM.INT32;
BEGIN
  ASSERT(fd >= 0, AssertArgument);
  IF on THEN v := 1 ELSE v := 0 END;
  RETURN Outcome(CSetEcho(fd, v), "tcsetattr", err)
END SetEcho;

(* A new pseudo-terminal: what is written to controller is typed at
   terminal, and what is written to terminal, and echoed there, is read
   from controller. Both are read-write and close-on-exec, and neither
   becomes the process's controlling terminal; whoever opened them
   closes them (UnixFiles.Close). FALSE, with err, if it can't be
   made, and both -1. *)
PROCEDURE OpenPseudo*(VAR controller, terminal: LONGINT; VAR err: UnixErrors.Error): BOOLEAN;
  VAR c, t: SYSTEM.INT64;
BEGIN
  c := -1; t := -1;
  IF Outcome(COpenPseudo(c, t), "pseudo-terminal", err) THEN
    controller := SYSTEM.VAL(LONGINT, c); terminal := SYSTEM.VAL(LONGINT, t);
    RETURN TRUE
  END;
  controller := -1; terminal := -1;
  RETURN FALSE
END OpenPseudo;

END UnixTerminals.
