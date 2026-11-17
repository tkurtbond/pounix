MODULE HaltFilesRange; (* Read past the end of its buffer halts *)

IMPORT UnixErrors, UnixFiles;

VAR err: UnixErrors.Error; buf: ARRAY 8 OF CHAR; n: LONGINT; ok: BOOLEAN;

BEGIN
  ok := UnixFiles.Read(0, buf, 4, 5, n, err)
END HaltFilesRange.
