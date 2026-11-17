/* UnixProcesses.c -- the C part of module UnixProcesses (pounix):
   starting a program as a child process, waiting for it, signalling it.
   POSIX (fork, execvp, waitpid, kill) and pipe2, which Linux and the
   BSDs all have (PLAN.md, "Portability").

   Each function returns 0 or the errno value. Labelled
   UnixProcesses.-<name>. */

#define _GNU_SOURCE  /* pipe2, in glibc */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define NAME(n) __asm__("UnixProcesses.-" n)

/* UnixProcesses.Mod's modes for a stream, and what start failed at */
enum { INHERIT = 0, NUL = 1, PIPE = 2, TO_OUTPUT = 3 };
enum { STEP_PIPE = 1, STEP_FORK = 2, STEP_EXEC = 3 };

int32_t unixprocesses_signal_value(int32_t which) NAME("signal-value");
int32_t unixprocesses_start(const char *args, int64_t len, int32_t count,
    int32_t in, int32_t out, int32_t err, int32_t nonblocking,
    int64_t *pid, int64_t *fds, int32_t *step) NAME("start");
int32_t unixprocesses_wait(int64_t pid, int32_t *exited, int32_t *status) NAME("wait");
int32_t unixprocesses_kill(int64_t pid, int32_t sig) NAME("kill");

/* The signal named by which: interrupt, terminate, kill. */
int32_t unixprocesses_signal_value(int32_t which)
{
	static const int values[] = { SIGINT, SIGTERM, SIGKILL };

	return which >= 0 && which < 3 ? values[which] : 0;
}

static void close_all(int *fds, int n)
{
	int i;

	for (i = 0; i < n; i++)
		if (fds[i] >= 0) {
			close(fds[i]);
			fds[i] = -1;
		}
}

/* In the child: reports e to the parent through report, and ends.
   Only async-signal-safe calls from here to exec. */
static void child_fail(int report, int e)
{
	ssize_t r;

	do
		r = write(report, &e, sizeof e);
	while (r < 0 && errno == EINTR);
	_exit(127);
}

/* In the child: what stream target (0, 1, 2) becomes, from source, a
   descriptor at 3 or above (so no dup2 overwrites another's source). */
static void child_stream(int source, int target, int report)
{
	if (dup2(source, target) < 0)
		child_fail(report, errno);
}

/* In the child: d moved to 3 or above, close-on-exec, if it is a
   standard stream's number, so setting up 0 to 2 can't overwrite it. */
static int child_lift(int d, int report)
{
	if (d >= 0 && d < 3) {
		d = fcntl(d, F_DUPFD_CLOEXEC, 3);
		if (d < 0)
			child_fail(report, errno);
	}
	return d;
}

/* Starts the program args[0] with the count arguments in args, each
   ended by a 0 byte, len bytes in all, its standard streams as in, out
   and err say. *pid is the child's, fds[0..2] the parent's ends of its
   pipes (-1 for none). Fails with the errno value and *step: a pipe,
   fork, or the child's setup or exec, whose errno comes back through a
   close-on-exec pipe. */
int32_t unixprocesses_start(const char *args, int64_t len, int32_t count,
    int32_t in, int32_t out, int32_t err, int32_t nonblocking,
    int64_t *pid, int64_t *fds, int32_t *step)
{
	/* ends[i][0] read, [1] write; report: exec's errno */
	int ends[3][2] = { { -1, -1 }, { -1, -1 }, { -1, -1 } };
	int report[2] = { -1, -1 }, modes[3], i, e, got;
	char **argv;
	const char *a;
	pid_t child;
	ssize_t r;

	modes[0] = in; modes[1] = out; modes[2] = err;
	fds[0] = fds[1] = fds[2] = -1;
	argv = malloc(((size_t)count + 1) * sizeof *argv);
	if (argv == NULL) {
		*step = STEP_FORK;
		return ENOMEM;
	}
	for (i = 0, a = args; i < count && a < args + len; i++) {
		argv[i] = (char *)a;
		a += strlen(a) + 1;
	}
	argv[i] = NULL;

	for (i = 0; i < 3; i++)
		if (modes[i] == PIPE && pipe2(ends[i], O_CLOEXEC) != 0)
			goto pipe_failed;
	if (pipe2(report, O_CLOEXEC) != 0)
		goto pipe_failed;

	child = fork();
	if (child < 0) {
		e = errno;
		free(argv);
		close_all(&ends[0][0], 6);
		close_all(report, 2);
		*step = STEP_FORK;
		return e;
	}
	if (child == 0) {
		/* the child's end of each pipe: the read end of its input,
		   the write end of its output and error */
		int mine[3], j, nul = -1;
		sigset_t none;

		for (j = 0; j < 3; j++)
			mine[j] = ends[j][j == 0 ? 0 : 1];
		report[1] = child_lift(report[1], report[1]);
		for (j = 0; j < 3; j++)
			mine[j] = child_lift(mine[j], report[1]);
		if (modes[0] == NUL || modes[1] == NUL || modes[2] == NUL) {
			nul = open("/dev/null", O_RDWR | O_CLOEXEC);
			if (nul < 0)
				child_fail(report[1], errno);
			nul = child_lift(nul, report[1]);
		}
		for (j = 0; j < 3; j++)
			if (modes[j] == PIPE)
				child_stream(mine[j], j, report[1]);
			else if (modes[j] == NUL)
				child_stream(nul, j, report[1]);
			else if (modes[j] == TO_OUTPUT)
				child_stream(1, 2, report[1]);
		/* an ignored signal stays ignored across exec */
		signal(SIGPIPE, SIG_DFL);
		sigemptyset(&none);
		sigprocmask(SIG_SETMASK, &none, NULL);
		execvp(argv[0], argv);
		child_fail(report[1], errno);
	}

	free(argv);
	close(report[1]);
	for (i = 0; i < 3; i++)
		if (modes[i] == PIPE) {
			/* the parent keeps the write end of the input, the
			   read end of output and error */
			int keep = ends[i][i == 0 ? 1 : 0];

			close(ends[i][i == 0 ? 0 : 1]);
			if (nonblocking)
				fcntl(keep, F_SETFL, fcntl(keep, F_GETFL) | O_NONBLOCK);
			fds[i] = keep;
		}
	got = 0;
	do
		r = read(report[0], (char *)&e + got, sizeof e - (size_t)got);
	while ((r < 0 && errno == EINTR) || (r > 0 && (got += (int)r) < (int)sizeof e));
	close(report[0]);
	if (got == (int)sizeof e) {
		/* the child ended without exec: reap it */
		while (waitpid(child, NULL, 0) < 0 && errno == EINTR)
			;
		for (i = 0; i < 3; i++)
			if (fds[i] >= 0) {
				close((int)fds[i]);
				fds[i] = -1;
			}
		*step = STEP_EXEC;
		return e;
	}
	*pid = child;
	*step = 0;
	return 0;

pipe_failed:
	e = errno;
	free(argv);
	close_all(&ends[0][0], 6);
	close_all(report, 2);
	*step = STEP_PIPE;
	return e;
}

/* Waits for pid to end: *exited 1 and its exit status, or 0 and the
   signal that ended it. */
int32_t unixprocesses_wait(int64_t pid, int32_t *exited, int32_t *status)
{
	int st;
	pid_t r;

	do
		r = waitpid((pid_t)pid, &st, 0);
	while (r < 0 && errno == EINTR);
	if (r < 0)
		return errno;
	if (WIFEXITED(st)) {
		*exited = 1;
		*status = WEXITSTATUS(st);
	} else {
		*exited = 0;
		*status = WIFSIGNALED(st) ? WTERMSIG(st) : 0;
	}
	return 0;
}

/* Sends sig to pid. */
int32_t unixprocesses_kill(int64_t pid, int32_t sig)
{
	return kill((pid_t)pid, sig) == 0 ? 0 : errno;
}
