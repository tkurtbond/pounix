MODULE HaltFilesChangeMode; (* ChangeMode with a mode outside 0..7777 octal halts *)

IMPORT UnixErrors, UnixFiles;

VAR err: UnixErrors.Error; ok: BOOLEAN;

BEGIN
  ok := UnixFiles.ChangeMode("../build/test/files/never", 1000H, err)
END HaltFilesChangeMode.
