# pounix - Unix services for poc

This software is developed with the aid of AI.

An Oberon-2 library of the Unix services that the runtime of poc, the
[Peaseblossom](https://github.com/tkurtbond/peaseblossom) Oberon
compiler, doesn't give:

- `UnixUsers`: a server started as root becomes a user of its own, for
  good;
- `UnixFiles`: a path with its symbolic links resolved, and a file
  opened as a descriptor, non-blocking or refusing a link, for a
  program that waits on it through `Tasks` or hands it to another
  library, and, for a program without tasks, a wait with a time limit
  for a descriptor to have something to read; a file written,
  synced, renamed and removed with every failure reported (poc's
  `Files` halts when it can't create or rename one); and the names in
  a directory;
- `UnixProcesses`: a program run as a child process with its
  arguments as a list (no shell, so no quoting), its standard streams
  inherited, `/dev/null` or pipes, and a program that can't be run
  reported by its `errno`, not by an exit status of 127;
- `UnixErrors`: what went wrong, as the `errno` value and a text.

It began with the C parts of pogemini, a Gemini server, so that later
programs share them.

**Status: early.** Phases 1 to 7 of [PLAN.md](PLAN.md) are done: all
four modules, tested on Linux, FreeBSD, NetBSD and OpenBSD, and checked
under valgrind on Linux, and `make install` checked by building the
example below outside the repo; pogemini uses it, and polibtls's
tests. PLAN.md has the design and the
roadmap; [AGENTS.md](AGENTS.md) has the working notes.

## Requirements

- poc 0.14.0.
- Linux, FreeBSD, NetBSD or OpenBSD (amd64 and i386 tested on the
  BSDs); GNU make, as `gmake` on the BSDs.
- valgrind, for `make valgrind` (Linux).

The library links nothing beyond the C library, so a program using it
needs no extra flags.

## Building

    make            # the library and the tests, under build/
    make test       # run the tests
    make valgrind   # the tests under valgrind
    make test-root  # Become as root, through sudo (SUDO=doas to change)
    make install    # into ~/.local/lib/poc (POCLIBDIR=<dir> to change)

A program then builds with `poc -OC -library-path ~/.local/lib/poc
Program.Mod`. A library works only with the poc that built it: after
upgrading poc, install pounix again.

## An example

This prints the SHA-256 of each file named, resolving links first,
through `openssl`:

```oberon
MODULE Hash; (* prints the SHA-256 of each file named, by openssl *)

IMPORT Modules, Out, UnixErrors, UnixFiles, UnixProcesses;

VAR
  i: INTEGER; name, real: ARRAY 1024 OF CHAR; out: ARRAY 256 OF CHAR;
  cmd: UnixProcesses.Command; p: UnixProcesses.Process;
  err: UnixErrors.Error; n: LONGINT;

PROCEDURE Fail(err: UnixErrors.Error);
BEGIN Out.String(err.text); Out.Ln
END Fail;

BEGIN
  FOR i := 1 TO Modules.ArgCount - 1 DO
    Modules.GetArg(i, name);
    IF ~UnixFiles.Resolve(name, real, err) THEN Fail(err)
    ELSE
      cmd := UnixProcesses.NewCommand("openssl");
      UnixProcesses.Add(cmd, "dgst"); UnixProcesses.Add(cmd, "-sha256");
      UnixProcesses.Add(cmd, "-r"); UnixProcesses.Add(cmd, real);
      UnixProcesses.SetOutput(cmd, UnixProcesses.pipe);
      UnixProcesses.SetError(cmd, UnixProcesses.null);
      IF ~UnixProcesses.Start(cmd, p, err) THEN Fail(err)
      ELSE
        IF UnixFiles.Read(p.out, out, 0, LEN(out) - 1, n, err) THEN
          out[n] := 0X; Out.String(out)
        ELSE Fail(err)
        END;
        UnixProcesses.Close(p);
        IF UnixProcesses.Wait(p, err) & ~(p.exited & (p.status = 0)) THEN
          Out.String("openssl failed for "); Out.String(real); Out.Ln
        END
      END
    END
  END
END Hash.
```

## Errors and halts

Every call the system can fail returns a `BOOLEAN`, `FALSE` for a
failure, and fills in a `UnixErrors.Error`: `code`, the `errno` value
(0 when the system gave none, as for a user that doesn't exist), to
compare with `UnixErrors.ENOENT` and the rest, and `text`, such as
`open /srv/x.gmi: No such file or directory`, for people. A
programmer's error (a negative descriptor, a range outside a buffer, a
process waited for twice) halts instead, with the codes in PLAN.md,
"Halt codes".

Every descriptor pounix opens is close-on-exec, so no child process
inherits it. Whoever opens a descriptor, or starts a process, closes
it, or waits for it: nothing is finalized.

## License

BSD 3-clause; see [LICENSE](LICENSE).
