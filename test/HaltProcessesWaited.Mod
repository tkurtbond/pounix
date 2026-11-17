MODULE HaltProcessesWaited; (* halts with 112 *)

IMPORT UnixErrors, UnixProcesses;

VAR err: UnixErrors.Error; p: UnixProcesses.Process; ok: BOOLEAN;

BEGIN
  ok := UnixProcesses.Start(UnixProcesses.NewCommand("true"), p, err);
  ok := UnixProcesses.Wait(p, err) & UnixProcesses.Wait(p, err)
END HaltProcessesWaited.
