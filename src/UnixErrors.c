/* UnixErrors.c -- the C part of module UnixErrors (pounix): errno
   values, whose numbers differ between systems, and an error's text.

   Text crosses as an address and a length: an open array reaches C as
   its first element's address alone, so Oberon passes LEN(a) beside
   it, and C stops at a 0X or at the length, whichever comes first, and
   always terminates what it writes. Labelled UnixErrors.-<name>, so
   the functions can't collide with C names. */

/* glibc gives POSIX's strerror_r without _GNU_SOURCE; the BSDs always
   do. Nothing here needs more than POSIX. */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define NAME(n) __asm__("UnixErrors.-" n)

typedef intptr_t address;
/* A length from Oberon: LEN(a) is a LONGINT, 64 bits under -OC even on
   a 32-bit system, where an address is 32. */
typedef int64_t length;

int32_t errno_value(int32_t which) NAME("errno-value");
void error_text(int32_t code, address what, length whatlen,
		address message, length messagelen,
		address text, length textlen) NAME("error-text");

/* The errno values Oberon names, in UnixErrors.Mod's order. */
int32_t errno_value(int32_t which)
{
	static const int32_t values[] = {
		ENOENT, ENOTDIR, ENAMETOOLONG, EACCES, ELOOP, EPERM,
		EAGAIN, EMFILE, ENFILE, EINVAL
	};

	if (which < 0 || which >= (int32_t)(sizeof values / sizeof values[0]))
		return -1;
	return values[which];
}

static length bounded_length(const char *s, length max)
{
	length n = 0;

	while (n < max && s[n] != '\0')
		n++;
	return n;
}

/* Writes "<what>: <message>" into text (textlen bytes, terminator
   included), truncating, never overflowing: the message given, or, if
   it is empty, strerror_r's for code. */
void error_text(int32_t code, address what, length whatlen,
		address message, length messagelen,
		address text, length textlen)
{
	char buf[256];
	const char *msg = (const char *)message;
	length msglen = bounded_length(msg, messagelen);

	if (textlen <= 0)
		return;
	if (msglen == 0) {
		if (strerror_r(code, buf, sizeof buf) != 0)
			snprintf(buf, sizeof buf, "error %d", (int)code);
		msg = buf;
		msglen = (length)strlen(buf);
	}
	snprintf((char *)text, (size_t)textlen, "%.*s: %.*s",
		 (int)bounded_length((const char *)what, whatlen),
		 (const char *)what, (int)msglen, msg);
}
