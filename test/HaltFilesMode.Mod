MODULE HaltFilesMode; (* OpenWrite with a mode outside 0..7777 octal halts *)

IMPORT UnixErrors, UnixFiles;

VAR err: UnixErrors.Error; fd: LONGINT; ok: BOOLEAN;

BEGIN
  ok := UnixFiles.OpenWrite("../build/test/files/never", {UnixFiles.create}, 1000H, fd, err)
END HaltFilesMode.
