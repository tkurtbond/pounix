# UnixErrors: What went wrong in a pounix call

<!-- Made by doc/mkref.py from UnixErrors.Mod; edit the source, then make doc. -->

Every pounix call that the system can fail returns a BOOLEAN, FALSE for a failure, and fills in an Error. Its code is the errno value the system gave, 0 for a failure it gave none for (a user that doesn't exist); its text says what was being done and what went wrong, as "open /srv/x.gmi: No such file or directory". A caller acts on code, compared with the variables below, never on text.

Programmer errors (a negative descriptor, a buffer too small for what was asked) halt instead; PLAN.md, "Halt codes".

## Constants

```oberon
TextLen* = 512;  (* an Error's text, terminator included *)
```

## Types

```oberon
Error* = RECORD
  code-: INTEGER;
  text-: ARRAY TextLen OF CHAR
END;
```

What went wrong: code, the errno value or 0, and text.

## Variables

```oberon
ENOENT-, ENOTDIR-, ENAMETOOLONG-, EACCES-, ELOOP-, EPERM-,
EAGAIN-, EMFILE-, ENFILE-, EINVAL-, EEXIST-, ENOTTY-: INTEGER;
```

errno values a caller may act on, as Error.code. Their numbers differ between systems, so they come from the C part.

## Procedures

#### Clear

```oberon
PROCEDURE Clear*(VAR err: Error);
```

Makes err say there was no error: code 0, text "".

#### SetSystem

```oberon
PROCEDURE SetSystem*(VAR err: Error; code: INTEGER; what: ARRAY OF CHAR);
```

Sets err to the system error code, with the text "<what>: <the system's message for code>". For pounix's modules, and for a program's own calls of the system.

#### SetOther

```oberon
PROCEDURE SetOther*(VAR err: Error; what, message: ARRAY OF CHAR);
```

Sets err to an error the system gave no code for: code 0, with the text "<what>: <message>".
