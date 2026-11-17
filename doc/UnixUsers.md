# UnixUsers: Running as another user

<!-- Made by doc/mkref.py from UnixUsers.Mod; edit the source, then make doc. -->

A server started as root, to bind a low port or read keys only root may, should then run as a user of its own who can do no more than it needs. Become makes it that user for good: root can't be had back. From pogemini's GemUser.

## Procedures

#### Root

```oberon
PROCEDURE Root*(): BOOLEAN;
```

Whether the process runs as root: its effective user ID is 0.

#### Become

```oberon
PROCEDURE Become*(user: ARRAY OF CHAR; VAR err: UnixErrors.Error): BOOLEAN;
```

Becomes user, with its groups, then its user ID, for good, and checks that root can't be had back. As root, any user; otherwise only the one it already is, which changes nothing. FALSE, with err, if it can't: code 0 for a user that doesn't exist, one not root asking for another user, or root regained, and the errno value for anything else. After a failure as root, the process may have taken the user's groups but not its ID, so it should stop.
