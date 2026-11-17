# PLAN.md

pounix: an Oberon-2 library of Unix services for poc, the Peaseblossom
Oberon Compiler, that poc's runtime doesn't give and a program would
otherwise get from C of its own. AGENTS.md has the operational notes;
this file is the design, the decisions and the roadmap. Append to the
relevant section as work goes; mark a finished phase `[done]`, and
strike through an open question once it is decided, saying what was
decided and when.

## Origin

Peaseblossom's PLAN.md, "Ongoing library enhancements" 7, decided
(2026-11-16) where the services poc's runtime lacks should go:
portable ones into small `rtl` modules (so far `StopRequests`), clocks
into poDateTime, and **services that only make sense on Unix into a
library outside poc, pounix** (the name the user chose), a sibling of
posockets. Its "pounix's first contents" lists what pogemini's C
becomes, and the user decided on 2026-11-16 to start pounix then,
since child processes already had more than one user. That list is
this plan's starting point.

## Users

**pogemini** (`~/Repos/Oberon/pogemini`), the Gemini server, whose C
pounix replaces, so that it keeps none of its own:

- `src/GemUser.c`: whether it runs as root, and becoming the user it
  serves as, for good.
- `src/GemFiles.c`: `realpath`; opening a file for reading with
  `O_NONBLOCK` (a FIFO mustn't stop the server in `open`),
  `O_NOFOLLOW` and `O_CLOEXEC`; its kind by `fstat`; reading with
  `EINTR` retried; closing; and which `errno` values mean the file
  isn't there to serve.
- `src/GemCert.Mod`: runs `openssl` through `Platform.System`, so
  through the shell, quoting every name, to make a self-signed
  certificate. With child processes it runs `openssl` twice from lists
  of arguments, and does the rest (`umask`, `mkdir`, the config file,
  the renames) itself.

What stays pogemini's, rewritten in Oberon over pounix: a file must lie
under the capsule's root once resolved, a hidden name is never served,
which failures count as "not found" for Gemini, and the order
`GemFiles` relies on (resolve, check, then open without following a
final link).

**Tests that run a child process**: polibtls's `test/TestPeers.c`
(`Spawn`, `Wait`, `ReadLine`, `Kill`) and pogemini's `test/Child.c`,
copied from it, run a command through `/bin/sh -c` with its input and
output on pipes. Both could take `UnixProcesses` as a test-only
dependency, as polibtls's TCP tests take posockets; whether they do is
theirs to decide, once it exists.

**The next program** that needs one of these services takes it from
pounix, rather than copying pogemini's C.

## Goal and scope

Small, Unix-only, portable across Linux and the three BSDs that poc
supports; VAX/VMS is out of scope (its equivalents, where there are
any, belong to whatever needs them there). Every service here is one
a user named; nothing is bound in case. Not in scope at first:
anything posockets has (sockets, `SIGPIPE`), anything `rtl` has
(`Platform`'s descriptors, environment, `System`; `Files`;
`Directories`; `StopRequests`), clocks (poDateTime), and anything no
user needs yet (writing files by descriptor beyond a pipe, a user's
lookup by itself, process groups, sessions, daemonizing).

## Design

### Modules

One per concern, each named `Unix<Concern>`, so that none can clash
with an `rtl` module (`Files`) and a reader sees where it comes from
(the user, 2026-11-16):

- **`UnixErrors`** (`src/UnixErrors.Mod`, `.c`): the `Error` the
  others return, its text from `strerror_r`, and the `errno` values a
  caller may act on. Every other module imports it.
- **`UnixUsers`** (`src/UnixUsers.Mod`, `.c`): `Root`, `Become`.
- **`UnixFiles`** (`src/UnixFiles.Mod`, `.c`): `Resolve` (`realpath`),
  and files by descriptor: `OpenRead`, `KindOf`, `Read`, `Write`,
  `Close`.
- **`UnixProcesses`** (`src/UnixProcesses.Mod`, `.c`): a `Command` (a
  program and its arguments, as a list, and what its standard streams
  are), `Start`, a `Process`, `Wait`, `Signal`, and the pipes to it.

None imports `Tasks`: a call that waits (`Read` on a blocking
descriptor, `Wait`) stops every task, as `rtl`'s own blocking calls
do. A program that runs tasks gives `OpenRead` the `nonBlocking`
option, or asks for non-blocking pipes, and waits through
`Tasks.AwaitReadable` itself. A `UnixTasks`-like module, if one is
ever wanted, comes when a user needs it.

### Integer model

`-OC`, as in polibfyaml, posockets and polibtls: `INTEGER` 32 bits,
`LONGINT` 64. Descriptors and process IDs are `LONGINT`, as
posockets' and polibtls's descriptors are; lengths and positions are
`LONGINT`. The C part takes and returns only `int32_t`, `int64_t` and
`intptr_t`, so it means the same under either model, and on i386,
where `ssize_t` is 32 bits (polibtls's Phase 10).

### Errors

```
Error* = RECORD
  code-: INTEGER;              (* the errno value; 0 if there was none *)
  text-: ARRAY TextLen OF CHAR (* "<what was being done>: <message>" *)
END
```

A failure is a `BOOLEAN` result `FALSE` with an `Error`. `code` is the
`errno` value for a system error, and 0 for one the system gave no
code for ("become nobody2: no such user"); `text` says what was being
done and what went wrong, truncated, never overflowed. A caller acts on
`code`, compared with the read-only variables `UnixErrors.ENOENT`,
`EACCES` and the rest, which come from the C part, since their numbers
differ between systems. Only the values some user acts on are given.

The C part returns the `errno` value as its result (0 for success),
never leaving it in `errno`: anything Oberon runs between (the
collector, `Out`) may change it. It retries `EINTR` itself.

### Users

- `Root(): BOOLEAN`: whether the effective user ID is 0.
- `Become(user, VAR err): BOOLEAN`: takes `user`'s groups
  (`initgroups`, `setgid`) and then its user ID (`setuid`), for good,
  and checks that root can't be had back (`setuid(0)` and `seteuid(0)`
  must fail). As root, any user; otherwise only the user it already is
  (real and effective), which succeeds and changes nothing, so that a
  server run by its own user can name that user. pogemini's
  `GemUser.c`, unchanged in substance.

`getpwnam` reports a missing user as `NULL` with `errno` unchanged on
some systems and set to `ENOENT` or `ESRCH` on others (POSIX allows
both), so `Become` clears `errno` before and treats `NULL` with 0, or
one of those, as "no such user" (to confirm on each system, Phase 2).

### Files

- `Resolve(path, VAR real, VAR err): BOOLEAN`: `realpath`; `real` too
  short is `ENAMETOOLONG`.
- `OpenRead(path, options, VAR fd, VAR err): BOOLEAN`: opens for
  reading, always close-on-exec; `options` a `SET` of `nonBlocking`
  and `noFollow`. A mode for writing, with `create`, `truncate`,
  `append`, `exclusive`, comes with a user that needs it, as
  `OpenWrite`.
- `KindOf(fd, VAR kind, VAR err): BOOLEAN`: `fstat`'s file type as
  `regular`, `directory` or `other`.
- `Read(fd, VAR buf, pos, len, VAR n, VAR err): BOOLEAN`: up to `len`
  bytes into `buf[pos..]`; `n` 0 at the end. `Write(fd, buf, pos, len,
  VAR n, VAR err)`: up to `len` bytes, for a pipe to a child. A
  non-blocking descriptor with nothing to give fails with `EAGAIN`. A
  FIFO no writer has yet opened gives the end (0) on Linux, NetBSD and
  OpenBSD, but `EAGAIN` on FreeBSD (Phase 5).
- `Close(fd)`: closes, ignoring the result, since nothing pounix opens
  for writing can lose data in `close` (a pipe); `EINTR` isn't retried
  (the descriptor is gone on Linux and the BSDs either way).

Descriptors are `LONGINT`; a negative one, or `pos` and `len` outside
`buf`, halts (programmer errors).

### Processes

```
cmd := UnixProcesses.NewCommand("openssl");      (* argv[0], on PATH *)
UnixProcesses.Add(cmd, "req"); UnixProcesses.Add(cmd, "-new"); ...
UnixProcesses.SetOutput(cmd, UnixProcesses.null);
IF UnixProcesses.Start(cmd, p, err) & UnixProcesses.Wait(p, err) & p.exited & (p.status = 0) THEN ...
```

- **A `Command`** is the program, its arguments as a list (no shell,
  so no quoting), and what each standard stream of the child is:
  `inherit` (the default), `null` (`/dev/null`), `pipe` (a pipe whose
  other end the caller gets), or, for standard error only, `toOutput`.
  A program without "/" is searched for on `PATH` (`execvp`).
- **`Start(cmd, VAR p, VAR err): BOOLEAN`** forks and execs. A program
  that can't be run (not found, not executable) fails `Start` with
  its `errno` (`ENOENT`, `EACCES`), not a child exiting 127: the child
  writes `exec`'s `errno` to a close-on-exec pipe, which the parent
  reads to its end; nothing read means `exec` succeeded. So pogemini
  can say "openssl isn't on PATH" without guessing from 127.
- **In the child**, between `fork` and `exec`, only async-signal-safe
  calls: `dup2`, `open` of `/dev/null`, `signal`, `sigprocmask`,
  `write`, `_exit` (and `execvp`, safe in a program of one thread).
  `SIGPIPE` is set back to its default, since an ignored signal stays
  ignored across `exec` and posockets' `IgnoreBrokenPipe` ignores it
  (a pipeline in the child might otherwise never end), and the signal
  mask is cleared. Signals poc's runtime catches (`StopRequests`)
  return to their defaults through `exec` by themselves.
- **A `Process`** has its `pid`, the caller's ends of its pipes (`in`,
  `out`, `err`, -1 for none), and, once waited for, `exited` and
  `status` (the exit status, or the signal that ended it). The pipes
  are the process's; `CloseInput(p)` closes `in` (the child sees the
  end of its input), and `Close(p)` closes whatever is still open.
  Pipe ends are close-on-exec, so a later child never inherits them,
  and blocking unless `SetNonBlockingPipes(cmd, TRUE)`.
- **`Wait(p, VAR err)`** blocks in `waitpid`, retrying `EINTR`; a
  process already waited for halts. **`Signal(p, sig, VAR err)`**
  sends `interrupt`, `terminate` or `kill` (read-only variables from
  the C part) to a process not yet waited for.
- No finalizer: a `Process` dropped unwaited leaves a zombie and open
  pipes, as a descriptor dropped unclosed does in posockets (its
  "Sockets and closing"). Whoever started it waits for it.

### Portability

POSIX only, and what all four systems have: `pipe2` with `O_CLOEXEC`
(Linux, FreeBSD 10, NetBSD 6, OpenBSD 5.7), `initgroups`, `realpath`
with a `NULL`-free `PATH_MAX` buffer. Anything else goes behind an
`#ifdef` naming the system, noted here for the port.

### Halt codes

110..119, after pogemini's 100..109 (no other po* project uses them):

| Code | Name | Meaning |
|---|---|---|
| 110 | `AssertArgument` | an argument out of range: a negative descriptor, `pos` and `len` outside the buffer |
| 111 | `AssertCommand` | a `Command` that is `NIL` or has no program |
| 112 | `AssertWaited` | `Wait` or `Signal` on a process already waited for |
| 113 | `AssertProcess` | a `Process` that is `NIL` |

Each module declares the ones it uses, with the same value.

## Testing

As posockets': one main module per concern in `test/`, through
`test/Check.Mod`; halt tests `test/Halt*.Mod` in `HALTTESTS` as
`name:code`; `make valgrind` with `poc-gc.supp`, `vg-reachable.sh`
(which also allows the memory glibc keeps for NSS modules that
`getpwnam` loads with `dlopen`) and `vg-fds.sh`. Tests make their files
under `build/test/`.

`Become` as root can't run in `make test` (it is run by a user). A
separate program, `test/RootUsers.Mod`, built by `make tests` and run
by `make test-root` under `sudo`, or as root on a BSD host, becomes
`nobody` and checks that root can't be had back.

## Roadmap

### Phase 1: project skeleton and `UnixErrors` [done]

The `GNUmakefile` (from posockets', without poDateTime), `test/`,
`doc/mkref.py` (polibtls's), and `UnixErrors` with `TestErrors`:
`make`, `make test`, `make valgrind`, `make doc`.

### Phase 2: `UnixUsers` [done]

`Root` and `Become` from pogemini's `GemUser.c`; `TestUsers` as a user
(itself; another user and a missing one fail with the right text),
`RootUsers` as root.

[done 2026-11-16 on Linux; `RootUsers` passed as root by `make
test-root`, run by the user, since sudo here asks for a password.] Under
valgrind, `getpwnam` through SSSD's NSS module calls `fstat(-1)`
(`sss_cli_check_socket`), which `--track-fds` reports as a bad use of a
descriptor; `test/poc-gc.supp` suppresses it.

### Phase 3: `UnixFiles` [done]

From `GemFiles.c`'s general part; `TestFiles` (resolve through links,
a missing file's `ENOENT`, `noFollow` on a link, a FIFO opened
`nonBlocking`, kinds, reading to the end, a short `real`), halt tests.

[done 2026-11-16 on Linux, valgrind-clean.] `TestFiles` makes its
files with the shell (`Platform.System`: a link and a FIFO need it),
and checks close-on-exec where `/proc/self/fd` shows a child's
descriptors. A FIFO opened `nonBlocking` with no writer reads 0, the
end, not `EAGAIN` (Linux; to confirm on the BSDs). Halt tests:
`HaltFilesRange`, `HaltFilesFd`, `HaltFilesString` (a path with no
`0X`).

### Phase 4: `UnixProcesses` [done]

`TestProcesses` (arguments with spaces and quotes reach the child
unchanged, `ENOENT` for a missing program, exit status, a signal,
pipes in both directions, `/dev/null`, `toOutput`, `SIGPIPE` default in
the child even when ignored here, no descriptor leaked to the child),
halt tests.

[done 2026-11-16 on Linux, valgrind-clean.] `TestProcesses` ignores
`SIGPIPE` itself, through libc's `signal` (13 and `SIG_IGN` 1 on Linux
and the BSDs), and runs `sh -c 'kill -PIPE $$'`: sh can't undo a
signal ignored on entry, so it ends by `SIGPIPE` only if the child has
it at its default; with the child's `signal(SIGPIPE, SIG_DFL)` taken
out, the check fails. Arguments with spaces, quotes, `$`, `*` and the
empty one arrive unchanged; a later child has none of an earlier one's
pipes (by a shell's redirection from the descriptor, since Phase 5). In the child, a pipe end or
`/dev/null` on 0 to 2 (the caller's own closed) is first moved to 3 or
above, so setting up the standard streams can't overwrite it. Under
valgrind a child whose `exec` fails reports the parent's `argv` and
pipes as its own at `_exit`; `make valgrind` passes
`--child-silent-after-fork=yes`. Halt tests: `HaltProcessesCommand`,
`HaltProcessesWaited`, `HaltProcessesProcess`.

### Phase 5: the BSD port [done]

`gmake test` on alerik, artos, yishana, jherek and cymoril, and
`RootUsers` as root where there is a root shell.

[done 2026-11-16, poc 0.14.0: FreeBSD 15.1 amd64 (alerik), NetBSD 11.0
amd64 (artos) and i386 (yishana), OpenBSD 7.9 amd64 (jherek) and i386
(cymoril), each 53 checks and the six halt tests passing, and
`RootUsers` as root on each (alerik by `gmake test-root SUDO=doas`, the
others by `build/RootUsers` in a root shell).] The C parts needed no
change. Two things in the tests did:

- **A FIFO no writer has yet opened**, opened `O_NONBLOCK`, gives
  `read` 0 on Linux, NetBSD and OpenBSD, but `EAGAIN` on FreeBSD; once
  a writer has come and gone, 0 everywhere (C probe on all five).
  `TestFiles` accepts either, and `UnixFiles.OpenRead`'s comment says
  so.
- **FreeBSD and OpenBSD have no `/proc/self/fd`**, so the close-on-exec
  checks skipped there. They now ask a child shell to redirect from the
  descriptor (`true 2>/dev/null <&N`), which fails if it isn't open, on
  all six systems; with `O_CLOEXEC` taken out of `OpenRead` and
  `pipe2`, both checks fail (Linux).

### Phase 6: documentation and install

README.md, the reference (`make doc`), `make install`; then pogemini
moves to pounix (in pogemini, its own plan), and `GemAccess`'s
`Platform.GetTimeOfDay` to poDateTime's `Clocks` with it.

## Open questions

- Whether `UnixProcesses` should close every descriptor above 2 in the
  child (`close_range` on Linux and FreeBSD, `closefrom` on the BSDs),
  for descriptors something else opened without close-on-exec. Not
  until a user finds one.
- Whether a program running tasks wants a `Wait` that doesn't block
  (`WNOHANG`, or `SIGCHLD` posting a `Tasks.Event`), and the tests a
  `ReadLine` with a time limit (`TestPeers.ReadLine`). When a user asks.
