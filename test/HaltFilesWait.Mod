MODULE HaltFilesWait; (* a negative time to wait halts *)

IMPORT UnixErrors, UnixFiles;

VAR err: UnixErrors.Error; ready, ok: BOOLEAN;

BEGIN
  ok := UnixFiles.WaitReadable(0, -1, ready, err)
END HaltFilesWait.
