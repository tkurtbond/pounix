MODULE HaltFilesFd; (* a negative descriptor halts *)

IMPORT UnixErrors, UnixFiles;

VAR err: UnixErrors.Error; buf: ARRAY 8 OF CHAR; n: LONGINT; ok: BOOLEAN;

BEGIN
  ok := UnixFiles.Read(-1, buf, 0, 1, n, err)
END HaltFilesFd.
