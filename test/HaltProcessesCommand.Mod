MODULE HaltProcessesCommand; (* a command with no program halts *)

IMPORT UnixProcesses;

VAR cmd: UnixProcesses.Command;

BEGIN
  cmd := UnixProcesses.NewCommand("")
END HaltProcessesCommand.
