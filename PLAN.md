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
- **`UnixTerminals`** (`src/UnixTerminals.Mod`, `.c`): `IsTerminal`,
  a terminal's `Echo` and `SetEcho`, and `OpenPseudo`, a
  pseudo-terminal for tests (Phase 10).

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
  and `noFollow`.
- `OpenWrite(path, options, mode, VAR fd, VAR err): BOOLEAN` (Phase
  9): opens for writing, close-on-exec, `options` adding `create`,
  `truncate`, `exclusive` and `append`, a file created having `mode`
  less the umask. `ModeOf(fd, VAR mode, VAR err)`: `fstat`'s
  permission bits. `Sync(fd, VAR err)`: `fsync`. `Rename(from, to,
  VAR err)`, `Remove(path, VAR err)`: `rename`, `unlink`.
- `KindOf(fd, VAR kind, VAR err): BOOLEAN`: `fstat`'s file type as
  `regular`, `directory` or `other`.
- `Read(fd, VAR buf, pos, len, VAR n, VAR err): BOOLEAN`: up to `len`
  bytes into `buf[pos..]`; `n` 0 at the end. `Write(fd, buf, pos, len,
  VAR n, VAR err)`: up to `len` bytes, for a pipe to a child. A
  non-blocking descriptor with nothing to give fails with `EAGAIN`. A
  FIFO no writer has yet opened gives the end (0) on Linux, NetBSD and
  OpenBSD, but `EAGAIN` on FreeBSD (Phase 5).
- `OpenDirectory(path, options, VAR d, VAR err)`, `NextName(d, VAR
  name, VAR err)`, `CloseDirectory(d)` (Phase 8): a directory's names,
  in the system's order, never `.` or `..`, hidden ones included;
  `name` `""` at the end. A `Directory` hides its `DIR`; whoever opens
  one closes it, as with a descriptor, and closing twice does nothing.
- `Close(fd)`: closes, ignoring the result, since a file written is
  synced first (`Sync`), which reports a write that failed; `EINTR` isn't retried
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
| 114 | `AssertDirectory` | a `Directory` that is `NIL`, or closed for `NextName` |

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

### Phase 6: documentation and install [done]

README.md, the reference (`make doc`), `make install`; then pogemini
moves to pounix (in pogemini, its own plan), and `GemAccess`'s
`Platform.GetTimeOfDay` to poDateTime's `Clocks` with it.

The install is checked (2026-11-16, poc 0.14.0): `make install
POCLIBDIR=<dir>` put the `OC` and `OC-g` variants under
`<dir>/<triple>/`; README's example, cut out of README.md, built
outside the repo with only `poc -OC -library-path <dir>`, linked pounix
statically, gave the same hash as `sha256sum`, resolved a symbolic
link, and reported a missing path ("No such file or directory"); `make
uninstall` removed every file it had put there. pounix is installed in
`~/.local/lib/poc`.

pogemini moved to it the same day (pogemini's PLAN.md, "pounix"): its
`GemUser` and `GemFiles.c` are gone, `GemCert` runs `/bin/sh` through
`UnixProcesses` with its arguments as `$1` to `$3`, and `GemAccess`
takes poDateTime's `Clocks`; its tests pass on Linux and all five BSD
hosts.

### Phase 7: `UnixFiles.WaitReadable`, and the test helpers [done]

polibtls's `test/TestPeers.c` and pogemini's `test/Child.c` start a
command as a child process in C of their own, the same code copied:
`/bin/sh -c`, a pipe for its input and one for its output and error,
its output read a line at a time while it runs, with a time limit, and
to its end before it is waited for. `UnixProcesses` does all of it but
the time limit, which needs `poll`.

`UnixFiles.WaitReadable(fd, ms, VAR ready, VAR err)`: `poll` on one
descriptor, `ready` for `POLLIN`, `POLLHUP` (some systems give it, not
`POLLIN`, at the end of a pipe) or `POLLERR`, since each makes the next
`Read` return at once; `EBADF` for `POLLNVAL`. `EINTR` is retried with
the time left by `CLOCK_MONOTONIC`. It blocks the whole program, so a
program running `Tasks` uses `Tasks.AwaitReadableFor` instead. No
`WaitWritable` until a user needs one. Halt test `HaltFilesWait` (a
negative time).

[done on Linux 2026-11-16, valgrind-clean.] `TestProcesses` checks it
on `cat`'s output: not ready after 300 ms with nothing written, ready
at once after a line, ready at the end (which reads 0), and failing
for a descriptor just closed. With `poll`'s time set to 0, the first
fails. A C probe, with `SIGALRM` caught without `SA_RESTART` 200 ms
into a 1000 ms wait, returned after 1000 ms; with the full time
restarted after `EINTR`, after 1201 ms. Polling a closed descriptor is
deliberate, so `poc-gc.supp` suppresses `--track-fds`'s report of it,
for `poll` from `UnixFiles.-wait-readable` only.

The test helpers: pogemini's `test/Child.c` and the child-process part
of polibtls's `test/TestPeers.c` are gone, each replaced by a
`test/Child.Mod` over `UnixProcesses` and `WaitReadable` (their
PLAN.md's). Linux: pogemini's `make test` (299 checks) and polibtls's
`make test` (460) and `make valgrind` pass. The BSDs: `gmake test`
passes for pounix (59 checks), polibtls and pogemini on alerik,
artos, yishana, jherek and cymoril, with poDateTime 5ae9a47 and
posockets 08b6e48 from a `git archive`, no failure, no stray
`assertion failed`, no core file, and only the usual skips (clients a
host lacks, OpenSSL's openssl on OpenBSD, root).

### Phase 8: a directory's names [done]

pogemini lists a directory without `index.gmi`, when a capsule asks
for it (its PLAN.md, "Directory listings"), and nothing in pounix or
poc's runtime reads a directory: `Directories.NextFile` gives back its
pattern on Unix, where the shell expands it.

`OpenDirectory(path, options, VAR d, VAR err)` opens it `O_RDONLY |
O_DIRECTORY | O_CLOEXEC`, with `O_NOFOLLOW` for `noFollow`, and hands
the descriptor to `fdopendir`, so anything not a directory is `ENOTDIR`
before it is opened for reading (a FIFO never waits for a writer).
`NextName(d, VAR name, VAR err)`: `readdir`'s next name less `.` and
`..`, `""` at the end (no real name is empty), told from an error by
`errno` set to 0 before; a name too long for `name` is `ENAMETOOLONG`
and passed over. `NameLen`, 512, holds any (NetBSD's `MAXNAMLEN` is
511, the others' 255). `CloseDirectory(d)`: `closedir`, idempotent. No
`d_type`: it may be `DT_UNKNOWN`, and a caller deciding what to show
opens or resolves each name anyway. Halt code 114, `AssertDirectory`;
halt test `HaltFilesDirectory`.

[done on Linux 2026-11-17, valgrind-clean.] `TestFiles` checks every
name, hidden too, and the end twice; `ENAMETOOLONG` passing names
over; through a link, and `noFollow` refusing it; `ENOTDIR` for a file
and a FIFO; `ENOENT`; an empty directory; close-on-exec, with the
directory's descriptor the lowest free one; and that `CloseDirectory`
frees it. glibc's `fdopendir` sets `FD_CLOEXEC` itself (a C probe), so
taking `O_CLOEXEC` out changed nothing on Linux; clearing the flag
after `fdopendir` made the check fail.

[done on the BSD hosts 2026-11-17.] `gmake test` passed on FreeBSD,
NetBSD and OpenBSD, amd64 and i386. OpenBSD's linker warned that
`strcpy` "is almost always misused, please use strlcpy()", for
`resolve` and `next_name`, each of which checked the length first.
Both now use `strlcpy`, its result telling a name too long, which
leaves the buffer empty as before: in POSIX since 2024, in glibc
since 2.38 (declared without `-std=c99`; 2.43 here), and long in the
BSDs. `make test` and `make valgrind` passed on Linux and `gmake test`
on the five BSD hosts, with no warning (2026-11-17).

### Phase 9: a file written, renamed and removed [done]

pogeminilib keeps a known-hosts file (its PLAN.md, "Trust"), written
under a temporary name and renamed over the old one, and outside data
must never halt it. poc's `Files` halts (99) when it can't create the
temporary file or rename it (`Files.Fail`, read 2026-11-18), as for a
directory the program can't write in, so pounix gains what the plan
above held back until a user needed it: `OpenWrite` with `create`,
`truncate`, `exclusive` and `append` (`O_CREAT`, `O_TRUNC`, `O_EXCL`,
`O_APPEND`) and a mode, `ModeOf`, `Sync`, `Rename` and `Remove`, and
`UnixErrors.EEXIST`. A mode outside 0..7777 octal halts (110, halt
test `HaltFilesMode`).

`TestFiles` checks a file made `exclusive` with mode 600 octal, written,
synced and read back; `EEXIST` for an existing file and for a symbolic
link, which isn't followed; `ENOENT` without `create`; `append`;
`truncate` keeping the mode; 700 octal; close-on-exec; `Rename` over
another file and of a missing one; `Remove`, of a link not what it
names, and of a missing name. [done on Linux 2026-11-18,
valgrind-clean.]

### Phase 10: a terminal's echo [done]

pogeminilib's example browser asks for a secret when a server gives
status 11, and must not echo it. rtl has no way to turn a terminal's
echo off, and the browser ran `stty -echo` and `stty echo` through
`UnixProcesses` (its PLAN.md, Phase 6), a process each time, so pounix
gains `UnixTerminals` (the user, 2026-11-18): `IsTerminal` (`isatty`),
`Echo` and `SetEcho` (`tcgetattr`, `tcsetattr` with `TCSANOW`, ECHO
alone changed; the setting read back, since POSIX lets `tcsetattr`
succeed having made only some changes), and `UnixErrors.ENOTTY` for a
descriptor that isn't a terminal. A negative descriptor halts (110,
halt test `HaltTerminalsFd`).

`TCSANOW`, not `TCSAFLUSH` as `getpass` uses: what was typed before
echo went off was echoed as it came, so discarding it hides nothing.

A program killed while echo is off leaves the terminal so; that is
the caller's to handle, as with `stty`.

make's standard input is /dev/null, so a test needs a terminal of its
own: `OpenPseudo` (`posix_openpt`, `grantpt`, `unlockpt`, `ptsname`,
all POSIX; both sides close-on-exec, `O_NOCTTY`). `TestTerminals`
checks that a new one echoes, what is typed reaches the terminal with
echo off but doesn't come back, and with it on again does; `ENOTTY`
for a file; a closed descriptor. [done on Linux 2026-11-18,
valgrind-clean; FreeBSD, NetBSD and OpenBSD, amd64 and i386, `gmake test` passing.]

### Phase 11: a file's mode changed [done]

pogemini's `GemCert` makes its certificate directory with the
runtime's `Directories.MakeDirectory`, mode 777 octal less the umask,
where `umask 077` in the shell it ran before made it 700 (its PLAN.md,
"Certificates through TlsMake"), so pounix gains `UnixFiles.ChangeMode`
(the user, 2026-11-18): `chmod` on a path, retried on `EINTR`, the mode
as `OpenWrite` and `ModeOf` take it, set whole, whatever the umask. It
follows a symbolic link, as `chmod` does. A mode outside 0..7777 octal
halts (110, halt test `HaltFilesChangeMode`).

`TestFiles` checks a file set to 666 octal and a directory to 700 and
then 777, more than a usual umask allows, each read back by `ModeOf`,
and `ENOENT` for a missing name, with its text. [done on Linux
2026-11-18, valgrind-clean; FreeBSD, NetBSD and OpenBSD, amd64 and
i386, `gmake test` passing.]

## Open questions

- Whether `UnixProcesses` should close every descriptor above 2 in the
  child (`close_range` on Linux and FreeBSD, `closefrom` on the BSDs),
  for descriptors something else opened without close-on-exec. Not
  until a user finds one.
- Whether a program running tasks wants a `Wait` that doesn't block
  (`WNOHANG`, or `SIGCHLD` posting a `Tasks.Event`). When a user asks:
  the test helpers of Phase 7 don't, since each reads a child's output
  to its end before waiting for it.
- ~~The tests' `ReadLine` with a time limit (`TestPeers.ReadLine`)~~:
  decided 2026-11-16, `UnixFiles.WaitReadable` (Phase 7).
