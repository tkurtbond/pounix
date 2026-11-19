MODULE TestErrors; (* UnixErrors: errno values and an error's text *)

IMPORT Strings, UnixErrors, Check;

VAR
  err: UnixErrors.Error;
  long: ARRAY 1000 OF CHAR;
  i: INTEGER;

(* Whether every errno value is positive and differs from the rest. *)
PROCEDURE Distinct(): BOOLEAN;
  VAR v: ARRAY 11 OF INTEGER; i, j: INTEGER;
BEGIN
  v[0] := UnixErrors.ENOENT; v[1] := UnixErrors.ENOTDIR;
  v[2] := UnixErrors.ENAMETOOLONG; v[3] := UnixErrors.EACCES;
  v[4] := UnixErrors.ELOOP; v[5] := UnixErrors.EPERM;
  v[6] := UnixErrors.EAGAIN; v[7] := UnixErrors.EMFILE;
  v[8] := UnixErrors.ENFILE; v[9] := UnixErrors.EINVAL;
  v[10] := UnixErrors.EEXIST;
  FOR i := 0 TO LEN(v) - 1 DO
    IF v[i] <= 0 THEN RETURN FALSE END;
    FOR j := 0 TO i - 1 DO IF v[i] = v[j] THEN RETURN FALSE END END
  END;
  RETURN TRUE
END Distinct;

BEGIN
  Check.Check(Distinct(), "errno values are positive and distinct");

  UnixErrors.SetSystem(err, UnixErrors.ENOENT, "open /x");
  Check.Check((err.code = UnixErrors.ENOENT)
    & (err.text = "open /x: No such file or directory"),
    "SetSystem: code, and the system's message after what");

  UnixErrors.SetOther(err, "become x", "no such user");
  Check.Check((err.code = 0) & (err.text = "become x: no such user"),
    "SetOther: code 0, and the message given");

  UnixErrors.Clear(err);
  Check.Check((err.code = 0) & (err.text = ""), "Clear");

  FOR i := 0 TO LEN(long) - 2 DO long[i] := "a" END; long[LEN(long) - 1] := 0X;
  UnixErrors.SetSystem(err, UnixErrors.EACCES, long);
  Check.Check(Strings.Length(err.text) = UnixErrors.TextLen - 1,
    "a long text is truncated to fit");

  Check.Summary
END TestErrors.
