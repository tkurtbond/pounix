/* UnixUsers.c -- the C part of module UnixUsers (pounix): becoming
   another user. POSIX and BSD (getpwnam, initgroups, setgid, setuid),
   the same on Linux and the BSDs. From pogemini's GemUser.c. Labelled
   UnixUsers.-<name>. */

#define _DEFAULT_SOURCE  /* initgroups, in glibc */

#include <errno.h>
#include <grp.h>
#include <pwd.h>
#include <stdint.h>
#include <sys/types.h>
#include <unistd.h>

#define NAME(n) __asm__("UnixUsers.-" n)

/* What become failed at, as UnixUsers.Mod numbers it. */
enum { NO_USER = 1, NOT_ROOT = 2, LOOKUP = 3, GROUPS = 4, USER_ID = 5,
       REGAINED = 6 };

int32_t unixusers_root(void) NAME("root");
int32_t unixusers_become(const char *user, int32_t *step) NAME("become");

/* 1 if the process runs as root (its effective user ID is 0), 0 if
   not. */
int32_t unixusers_root(void)
{
	return geteuid() == 0;
}

/* Becomes user, its groups and its user ID, for good: 0, or an errno
   value (0 if the system gave none) with *step what failed. One not
   root can only "become" itself. */
int32_t unixusers_become(const char *user, int32_t *step)
{
	struct passwd *pw;

	/* POSIX lets getpwnam leave errno alone for a user that isn't
	   there, or set it to ENOENT, ESRCH, EBADF or EPERM, and
	   systems do each */
	errno = 0;
	pw = getpwnam(user);
	if (pw == NULL) {
		int e = errno;

		if (e == 0 || e == ENOENT || e == ESRCH || e == EBADF
		    || e == EPERM) {
			*step = NO_USER;
			return 0;
		}
		*step = LOOKUP;
		return e;
	}
	if (geteuid() != 0) {
		if (pw->pw_uid == getuid() && pw->pw_uid == geteuid())
			return 0;
		*step = NOT_ROOT;
		return 0;
	}
	/* groups first: once the user ID is no longer root, they can't
	   be changed */
	if (initgroups(user, pw->pw_gid) != 0 || setgid(pw->pw_gid) != 0) {
		*step = GROUPS;
		return errno;
	}
	if (setuid(pw->pw_uid) != 0) {
		*step = USER_ID;
		return errno;
	}
	/* for good: root again must be impossible */
	if (pw->pw_uid != 0 && (setuid(0) == 0 || seteuid(0) == 0)) {
		*step = REGAINED;
		return 0;
	}
	*step = 0;
	return 0;
}
