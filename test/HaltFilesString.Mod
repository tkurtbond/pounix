MODULE HaltFilesString; (* a path with no 0X halts, so C reads no further *)

IMPORT UnixErrors, UnixFiles;

VAR err: UnixErrors.Error; path: ARRAY 4 OF CHAR; fd: LONGINT; ok: BOOLEAN;

BEGIN
  path[0] := "a"; path[1] := "b"; path[2] := "c"; path[3] := "d";
  ok := UnixFiles.OpenRead(path, {}, fd, err)
END HaltFilesString.
