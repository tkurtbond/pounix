MODULE HaltTerminalsFd; (* a negative descriptor halts *)

IMPORT UnixErrors, UnixTerminals;

VAR err: UnixErrors.Error; ok: BOOLEAN;

BEGIN
  ok := UnixTerminals.SetEcho(-1, FALSE, err)
END HaltTerminalsFd.
