MODULE HaltFilesDirectory; (* NextName on a closed directory halts *)

IMPORT UnixErrors, UnixFiles;

VAR err: UnixErrors.Error; d: UnixFiles.Directory; name: ARRAY UnixFiles.NameLen OF CHAR; ok: BOOLEAN;

BEGIN
  ok := UnixFiles.OpenDirectory("..", {}, d, err);
  UnixFiles.CloseDirectory(d);
  ok := UnixFiles.NextName(d, name, err)
END HaltFilesDirectory.
