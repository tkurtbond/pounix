MODULE HaltProcessesProcess; (* halts with 113 *)

IMPORT UnixErrors, UnixProcesses;

VAR err: UnixErrors.Error; p: UnixProcesses.Process; ok: BOOLEAN;

BEGIN
  ok := UnixProcesses.Start(UnixProcesses.NewCommand("true"), p, err);
  p := NIL; ok := UnixProcesses.Wait(p, err)
END HaltProcessesProcess.
