# AGENTS.md

pounix is an Oberon-2 library of Unix services that poc's runtime
doesn't give, for poc, the Peaseblossom Oberon Compiler: running as
another user, a path resolved and a file opened as a descriptor, and
programs run as child processes. It began on 2026-11-16 from pogemini's
C parts (`GemUser.c`, the general part of `GemFiles.c`) and what
pogemini does through `Platform.System`, so that pogemini, and any
later program, takes them from one shared library (Peaseblossom's
PLAN.md, "Ongoing library enhancements" 7, step 4, and "pounix's first
contents"). PLAN.md is the design and roadmap; this file is
operational notes for an agent working in this repo, not a design doc.

Its siblings are its model; read their `AGENTS.md` before redesigning
anything, since most of their text is confirmed behaviour of poc that
applies here unchanged:

- **posockets** (`~/Repos/Oberon/posockets`): the `GNUmakefile`,
  tests, halt tests, valgrind setup and conventions are copied from it,
  and descriptors are `LONGINT`s as there.
- **polibtls** (`~/Repos/Oberon/polibtls`): `doc/mkref.py` and its
  notes on testing on the BSD hosts.
- **pogemini** (`~/Repos/Oberon/pogemini`): the first user, whose
  `GemUser`, `GemFiles` and `GemCert` this library replaces.

## Status

As of 2026-11-17, Phases 1 to 8 of PLAN.md are done: on Linux, each
tested and valgrind-clean, and on FreeBSD, NetBSD and OpenBSD, amd64
and i386, `gmake test` and `RootUsers` passing (Phase 5): `UnixErrors` (`Error`, the errno values a
caller acts on), `UnixUsers` (`Root`, `Become`), `UnixFiles`
(`Resolve`, `OpenRead`, `KindOf`, `Read`, `Write`, `WaitReadable`,
`Close`, `OpenDirectory`, `NextName`, `CloseDirectory`) and `UnixProcesses` (`Command`, `Start`, `Wait`, `Signal`, pipes), with
`RootUsers` passing as root (`make test-root`, which the user runs
here, since sudo asks for a password). Phase 6: README's example
built from an installed copy, and uninstall clean; pounix is installed
in `~/.local/lib/poc`, and pogemini uses it (its PLAN.md, "pounix").
Phase 7: `UnixFiles.WaitReadable`, so the tests of polibtls and
pogemini start their child processes through pounix. Phase 8: a
directory's names (`OpenDirectory`, `NextName`, `CloseDirectory`), for
pogemini's directory listings. Phase 9 (2026-11-18): a file written,
renamed and removed (`OpenWrite`, `ModeOf`, `Sync`, `Rename`,
`Remove`), for pogeminilib's known-hosts file. Phase 10 (2026-11-18,
on Linux and the BSDs): `UnixTerminals` (`IsTerminal`,
`Echo`, `SetEcho`, `OpenPseudo`), so pogeminilib's browser reads a
secret without echoing it.

**poc 0.14.0** (`/usr/bin/poc`). pounix needs nothing beyond poc's
runtime and libc.

## Reference material

| What | Where |
|---|---|
| poc | `/usr/bin/poc`, its runtime under `/usr/lib/poc`; `poc(1)`, `/usr/share/doc/peaseblossom/` |
| poc source | `~/Repos/Oberon/Peaseblossom` (`doc/users-guide.md`, `doc/reference-guide.md`; the runtime in `rtl/llvm/`: `Platform.Mod` (`System`, `getEnv`), `Files.Mod`) |
| What pounix replaces | pogemini's `src/GemUser.c`, `src/GemFiles.c`, and `GemCert.Mod`'s `Platform.System` calls |
| Oberon-2 report | `~/Reference/Computer/Languages/Oberon/Oberon2.pdf` |
| POSIX | the Linux man pages: `fork(2)`, `execvp(3)`, `pipe2(2)`, `waitpid(2)`, `signal-safety(7)`, `realpath(3)`, `open(2)` (`O_NOFOLLOW`), `getpwnam(3)`, `initgroups(3)` |

## Build

`GNUmakefile`, from posockets' without poDateTime: `make`, `make
test`, `make test-root` (`RootUsers` through `$(SUDO)`, default
`sudo`), `make valgrind`, `make doc`, `make clean`,
`make install`/`uninstall` into `POCLIBDIR` (`~/.local/lib/poc` by
default), with `POC` from `PATH`, output under `build/`,
`.NOTPARALLEL`, and `POC_LIBRARY_PATH` unexported. Add a module to
`LIBMODS`, in import order; a `src/<Module>.c` beside it is compiled
into the library. The library links nothing beyond libc, so a program
using it passes no flags.

The integer model is `-OC`. The C parts take and return only
`int32_t`, `int64_t` and `intptr_t`, so the boundary means the same
under either model; lengths and descriptors cross as `int64_t`
(polibtls's i386 finding: `ssize_t` is 32 bits there).

## Test

One main module per concern in `test/` through `test/Check.Mod`,
listed in `TESTS`; halt tests `test/Halt*.Mod` in `HALTTESTS` as
`name:code` (poc's `ASSERT(x, n)` exits 10, printing `assertion failed
(n)`; `make test` requires both). Tests run from `test/` with standard
input `/dev/null` and make their files under `build/test/`, emptied
first; `Platform.System` makes what Oberon can't (a symbolic link, a
FIFO). There is no string concatenation in poc: build texts with an
`Append`. `RootUsers` is in `ROOTTESTS`: built by `make`, run only by
`make test-root`.

A check that something is close-on-exec runs a child shell that
redirects from it (`true 2>/dev/null <&N`, which fails if N isn't
open), with descriptor 0 as the control: FreeBSD and OpenBSD have no
`/proc/self/fd`. A check worth having is checked
against a mutation once: the `SIGPIPE` check fails with the child's
`signal(SIGPIPE, SIG_DFL)` taken out.

`make valgrind` runs each test under memcheck with `test/poc-gc.supp`,
`test/vg-reachable.sh` and `test/vg-fds.sh` (posockets'), and
`--child-silent-after-fork=yes`: a child whose `exec` fails ends in
`_exit` holding the parent's `argv` and pipes, which valgrind would
otherwise report as its leaks. `poc-gc.supp` also suppresses SSSD's
NSS module calling `fstat(-1)` inside `getpwnam`, and `TestProcesses`
polling a closed descriptor on purpose (`WaitReadable`'s failure).

## Layout

- `src/UnixErrors.Mod`/`.c`: `Error` (`code-`, the errno value or 0;
  `text-`), `Clear`, `SetSystem`, `SetOther`, and the errno values as
  read-only variables, since their numbers differ between systems.
- `src/UnixUsers.Mod`/`.c`: `Root`, `Become` (groups, then user ID,
  then a check that root can't be had back).
- `src/UnixFiles.Mod`/`.c`: `Resolve` (`realpath`), `OpenRead`
  (`nonBlocking`, `noFollow`; always `O_CLOEXEC`), `KindOf`, `Read`,
  `Write`, `WaitReadable` (`poll`, one descriptor), `Close`;
  `OpenDirectory` (`O_DIRECTORY`, then `fdopendir`), `NextName`
  (`readdir`, less `.` and `..`), `CloseDirectory`.
- `src/UnixProcesses.Mod`/`.c`: `Command` (program and arguments as a
  list, streams `inherit`/`null`/`pipe`/`toOutput`), `Start` (fork and
  `execvp`, exec's errno back through a close-on-exec pipe), `Process`,
  `Wait`, `Signal`, `CloseInput`, `Close`.
- `test/`: the tests, halt tests, `RootUsers`, and the valgrind files.
- `doc/`: the reference made by `doc/mkref.py` (`make doc`),
  committed. Edit the comments in `src/`, never the `.md`.
- `PLAN.md`: design, decisions, findings, open questions.

## Confirmed facts

Each was confirmed by a program that ran, with poc 0.14.0 on Fedora 44
(x86-64), on 2026-11-16.

- **`getpwnam` through SSSD calls `fstat(-1)`**, which valgrind's
  `--track-fds` reports as `FdBadUse`; suppressed in `poc-gc.supp`.
- **A FIFO opened `O_RDONLY | O_NONBLOCK` with no writer** opens at
  once, and `read` gives 0, the end, not `EAGAIN`, on Linux, NetBSD and
  OpenBSD; FreeBSD gives `EAGAIN` until a writer has opened it (Phase
  5, all five BSD hosts).
- **A non-blocking pipe with nothing in it** fails `read` with
  `EAGAIN`.
- **sh can't change a signal ignored on entry**: `sh -c 'kill -PIPE
  $$'` survives if `SIGPIPE` was ignored when it started, and ends by
  it otherwise, which is how `TestProcesses` sees the child's
  disposition.
- **glibc's `fdopendir` sets close-on-exec itself** (2026-11-17), so on
  Linux `OpenDirectory`'s close-on-exec check passes without
  `O_CLOEXEC`; it fails once the flag is cleared after `fdopendir`.
- **valgrind follows a forked child until it execs**, writing its leak
  report to the same log; `--child-silent-after-fork=yes` stops that.

## Testing on the BSD hosts

As polibtls's AGENTS.md says ("Testing on the BSD hosts"): FreeBSD
(alerik), NetBSD (artos, yishana), OpenBSD (jherek, cymoril); rackhir
only after asking. Copy the working tree (`tar` less `build/` and
`.git`) under `~/tmp`, run `gmake test`, judge by make's exit status
and count `assertion failed` lines as well as `FAIL`, and remove it all
when done. alerik has passwordless doas: `gmake test-root SUDO=doas`.
On the others, where doas or sudo asks for a password, run
`build/RootUsers` from `test/` in the user's root shells (tmux windows
4 to 6), once `gmake test` has built it, so make never runs as root in
the tree.

## Conventions

- **Claim only what has been verified**, here under "Confirmed facts"
  and in PLAN.md. Throwaway programs go in a session directory under
  `/usr/local/sw/tmp` (`/tmp` is a RAM disk here), removed when done.
- **POSIX, and what all four systems have** (`pipe2`, `O_CLOEXEC`,
  `initgroups`); anything else behind an `#ifdef` naming the system,
  noted in PLAN.md, "Portability".
- **The C parts** return 0 or the errno value, never leaving it in
  `errno` for Oberon to fetch, and retry `EINTR` themselves (but not in
  `close`). Text crosses as an address and a length. Functions are
  named `<Module>.-<name>` with `__asm__` labels.
- **Every descriptor pounix opens is close-on-exec**, so no child gets
  it.
- **Programmer errors halt** with the codes in PLAN.md, "Halt codes"
  (110..119). What the system does never halts; it comes back as a
  `BOOLEAN` and an `Error`.
- **Comments explain why.**
- **Record decisions and findings in PLAN.md as they happen.**
- **Commit only when asked.** Commit messages are short and say why.
