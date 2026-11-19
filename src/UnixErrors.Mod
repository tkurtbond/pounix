MODULE UnixErrors; (* What went wrong in a pounix call *)

(* Every pounix call that the system can fail returns a BOOLEAN, FALSE
   for a failure, and fills in an Error. Its code is the errno value
   the system gave, 0 for a failure it gave none for (a user that
   doesn't exist); its text says what was being done and what went
   wrong, as "open /srv/x.gmi: No such file or directory". A caller acts
   on code, compared with the variables below, never on text.

   Programmer errors (a negative descriptor, a buffer too small for
   what was asked) halt instead; PLAN.md, "Halt codes". *)

IMPORT SYSTEM;

CONST
  TextLen* = 512;  (* an Error's text, terminator included *)

TYPE
  (* What went wrong: code, the errno value or 0, and text. *)
  Error* = RECORD
    code-: INTEGER;
    text-: ARRAY TextLen OF CHAR
  END;

VAR
  (* errno values a caller may act on, as Error.code. Their numbers
     differ between systems, so they come from the C part. *)
  ENOENT-, ENOTDIR-, ENAMETOOLONG-, EACCES-, ELOOP-, EPERM-,
  EAGAIN-, EMFILE-, ENFILE-, EINVAL-, EEXIST-: INTEGER;

PROCEDURE ["C", "UnixErrors.-errno-value"] CErrnoValue(which: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "UnixErrors.-error-text"] CErrorText(code: SYSTEM.INT32;
  what: ARRAY OF CHAR; whatLen: SYSTEM.INT64;
  message: ARRAY OF CHAR; messageLen: SYSTEM.INT64;
  VAR text: ARRAY OF CHAR; textLen: SYSTEM.INT64);

(* Makes err say there was no error: code 0, text "". *)
PROCEDURE Clear*(VAR err: Error);
BEGIN
  err.code := 0; err.text[0] := 0X
END Clear;

(* Sets err to the system error code, with the text "<what>: <the
   system's message for code>". For pounix's modules, and for a
   program's own calls of the system. *)
PROCEDURE SetSystem*(VAR err: Error; code: INTEGER; what: ARRAY OF CHAR);
BEGIN
  err.code := code;
  CErrorText(code, what, LEN(what), "", 1, err.text, LEN(err.text))
END SetSystem;

(* Sets err to an error the system gave no code for: code 0, with the
   text "<what>: <message>". *)
PROCEDURE SetOther*(VAR err: Error; what, message: ARRAY OF CHAR);
BEGIN
  err.code := 0;
  CErrorText(0, what, LEN(what), message, LEN(message), err.text, LEN(err.text))
END SetOther;

(* The value of the errno named by which, in the order of the C part. *)
PROCEDURE Value(which: INTEGER): INTEGER;
  VAR v: SYSTEM.INT32;
BEGIN
  v := CErrnoValue(which);
  RETURN v
END Value;

BEGIN
  ENOENT := Value(0); ENOTDIR := Value(1); ENAMETOOLONG := Value(2);
  EACCES := Value(3); ELOOP := Value(4); EPERM := Value(5);
  EAGAIN := Value(6); EMFILE := Value(7); ENFILE := Value(8);
  EINVAL := Value(9); EEXIST := Value(10)
END UnixErrors.
