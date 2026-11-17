/* UnixFiles.c -- the C part of module UnixFiles (pounix): a path
   resolved, and files by descriptor. POSIX only (realpath, open, fstat,
   read, write, close, poll, clock_gettime), the same on Linux and the
   BSDs. From pogemini's
   GemFiles.c.

   Each function returns 0 or the errno value, never leaving it in
   errno for Oberon to fetch, and retries EINTR itself. Text crosses as
   an address and a length (UnixErrors.c). Labelled UnixFiles.-<name>. */

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define NAME(n) __asm__("UnixFiles.-" n)

typedef int64_t length;

/* UnixFiles.Mod's options, as bits, and kinds */
enum { OPT_NONBLOCKING = 1, OPT_NOFOLLOW = 2 };
enum { KIND_REGULAR = 1, KIND_DIRECTORY = 2, KIND_OTHER = 3 };

int32_t unixfiles_resolve(const char *path, char *out, length max) NAME("resolve");
int32_t unixfiles_open_read(const char *path, int32_t options, int64_t *fd) NAME("open-read");
int32_t unixfiles_kind(int64_t fd, int32_t *kind) NAME("kind");
int32_t unixfiles_read(int64_t fd, char *buf, length pos, length len, int64_t *n) NAME("read");
int32_t unixfiles_write(int64_t fd, const char *buf, length pos, length len, int64_t *n) NAME("write");
int32_t unixfiles_wait_readable(int64_t fd, int32_t ms, int32_t *ready) NAME("wait-readable");
void unixfiles_close(int64_t fd) NAME("close");

/* path with every symbolic link, "." and ".." resolved, into out, of
   max bytes: 0, or the errno value, ENAMETOOLONG if out is too short. */
int32_t unixfiles_resolve(const char *path, char *out, length max)
{
	char real[PATH_MAX];

	if (realpath(path, real) == NULL)
		return errno;
	if ((length)strlen(real) >= max)
		return ENAMETOOLONG;
	strcpy(out, real);
	return 0;
}

/* Opens path for reading, close-on-exec, its descriptor in *fd. */
int32_t unixfiles_open_read(const char *path, int32_t options, int64_t *fd)
{
	int flags = O_RDONLY | O_CLOEXEC, d;

	if (options & OPT_NONBLOCKING)
		flags |= O_NONBLOCK;
	if (options & OPT_NOFOLLOW)
		flags |= O_NOFOLLOW;
	do
		d = open(path, flags);
	while (d < 0 && errno == EINTR);
	if (d < 0)
		return errno;
	*fd = d;
	return 0;
}

/* The kind of file open on fd, by fstat. */
int32_t unixfiles_kind(int64_t fd, int32_t *kind)
{
	struct stat st;

	if (fstat((int)fd, &st) != 0)
		return errno;
	*kind = S_ISREG(st.st_mode) ? KIND_REGULAR
	    : S_ISDIR(st.st_mode) ? KIND_DIRECTORY : KIND_OTHER;
	return 0;
}

/* Reads up to len bytes into buf[pos..]: how many in *n, 0 at the
   end. */
int32_t unixfiles_read(int64_t fd, char *buf, length pos, length len, int64_t *n)
{
	ssize_t r;

	do
		r = read((int)fd, buf + pos, (size_t)len);
	while (r < 0 && errno == EINTR);
	if (r < 0)
		return errno;
	*n = r;
	return 0;
}

/* Writes up to len bytes from buf[pos..]: how many in *n. */
int32_t unixfiles_write(int64_t fd, const char *buf, length pos, length len, int64_t *n)
{
	ssize_t r;

	do
		r = write((int)fd, buf + pos, (size_t)len);
	while (r < 0 && errno == EINTR);
	if (r < 0)
		return errno;
	*n = r;
	return 0;
}

/* The milliseconds of the monotonic clock, for wait_readable's time
   left after EINTR. */
static int64_t now_ms(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

/* Waits up to ms milliseconds for fd to have something to read: *ready
   1 if it has, or is at its end (POLLHUP: some systems give it, not
   POLLIN, for a pipe whose writer has gone), or has an error that a
   read will report; 0 if ms passed first. A signal doesn't cut the
   wait short: poll is called again with the time left. EBADF if fd
   isn't open (POLLNVAL). */
int32_t unixfiles_wait_readable(int64_t fd, int32_t ms, int32_t *ready)
{
	struct pollfd p;
	int64_t end = now_ms() + ms, left = ms;
	int r;

	for (;;) {
		p.fd = (int)fd; p.events = POLLIN; p.revents = 0;
		r = poll(&p, 1, (int)left);
		if (r >= 0 || errno != EINTR)
			break;
		left = end - now_ms();
		if (left < 0)
			left = 0;
	}
	if (r < 0)
		return errno;
	if (r > 0 && (p.revents & POLLNVAL))
		return EBADF;
	*ready = r > 0 && (p.revents & (POLLIN | POLLHUP | POLLERR)) != 0;
	return 0;
}

/* Closes fd. EINTR isn't retried: on Linux and the BSDs the descriptor
   is gone either way, and another thread may have reused its number. */
void unixfiles_close(int64_t fd)
{
	close((int)fd);
}
