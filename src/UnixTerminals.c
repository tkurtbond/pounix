/* UnixTerminals.c -- the C part of module UnixTerminals (pounix):
   whether a descriptor is a terminal, its echo turned off and on, and
   a pseudo-terminal for tests. POSIX only (isatty, tcgetattr,
   tcsetattr, posix_openpt, grantpt, unlockpt, ptsname, open, fcntl),
   the same on Linux and the BSDs.

   Each function returns 0 or the errno value, never leaving it in
   errno for Oberon to fetch, and retries EINTR itself. Labelled
   UnixTerminals.-<name>. */

#define _XOPEN_SOURCE 700  /* posix_openpt, grantpt, unlockpt, ptsname, in glibc */

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <termios.h>
#include <unistd.h>

#define NAME(n) __asm__("UnixTerminals.-" n)

int32_t unixterminals_is_terminal(int64_t fd) NAME("is-terminal");
int32_t unixterminals_echo(int64_t fd, int32_t *on) NAME("echo");
int32_t unixterminals_set_echo(int64_t fd, int32_t on) NAME("set-echo");
int32_t unixterminals_open_pseudo(int64_t *controller, int64_t *terminal) NAME("open-pseudo");

/* 1 if fd is a terminal, 0 if not. */
int32_t unixterminals_is_terminal(int64_t fd)
{
	return isatty((int)fd) == 1;
}

/* Whether fd's terminal echoes what is typed, in *on: 0, or the errno
   value, ENOTTY if fd isn't a terminal. */
int32_t unixterminals_echo(int64_t fd, int32_t *on)
{
	struct termios t;

	if (tcgetattr((int)fd, &t) != 0)
		return errno;
	*on = (t.c_lflag & ECHO) != 0;
	return 0;
}

/* Turns fd's echo on or off, and nothing else, at once (TCSANOW):
   what was typed before was echoed as it came, so nothing waiting is
   discarded. POSIX lets tcsetattr succeed having made only some of
   the changes, so the result is read back. */
int32_t unixterminals_set_echo(int64_t fd, int32_t on)
{
	struct termios t;
	int r;

	if (tcgetattr((int)fd, &t) != 0)
		return errno;
	if (on)
		t.c_lflag |= ECHO;
	else
		t.c_lflag &= ~(tcflag_t)ECHO;
	do
		r = tcsetattr((int)fd, TCSANOW, &t);
	while (r != 0 && errno == EINTR);
	if (r != 0)
		return errno;
	if (tcgetattr((int)fd, &t) != 0)
		return errno;
	if (((t.c_lflag & ECHO) != 0) != (on != 0))
		return EINVAL;
	return 0;
}

/* A new pseudo-terminal: its controller in *controller, the terminal
   side in *terminal, both read-write, close-on-exec, and neither made
   the process's controlling terminal. ptsname isn't thread-safe, but
   nothing in poc runs C in threads. */
int32_t unixterminals_open_pseudo(int64_t *controller, int64_t *terminal)
{
	int c, t, e;
	char *name;

	c = posix_openpt(O_RDWR | O_NOCTTY);
	if (c < 0)
		return errno;
	if (fcntl(c, F_SETFD, FD_CLOEXEC) != 0 || grantpt(c) != 0
	    || unlockpt(c) != 0 || (name = ptsname(c)) == NULL)
		goto fail;
	do
		t = open(name, O_RDWR | O_NOCTTY | O_CLOEXEC);
	while (t < 0 && errno == EINTR);
	if (t < 0)
		goto fail;
	*controller = c;
	*terminal = t;
	return 0;
fail:
	e = errno;
	close(c);
	return e;
}
