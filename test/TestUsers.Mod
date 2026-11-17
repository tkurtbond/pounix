MODULE TestUsers; (* UnixUsers, as a user: root is tested by RootUsers *)

IMPORT Out, Platform, UnixErrors, UnixUsers, Check;

VAR
  err: UnixErrors.Error;
  me: ARRAY 256 OF CHAR;

BEGIN
  IF UnixUsers.Root() THEN
    Out.String("skip - run as root: make test-root tests that"); Out.Ln
  ELSE
    Check.Check(~UnixUsers.Root(), "Root: not root");

    IF Platform.getEnv("USER", me) & (me # "") OR Platform.getEnv("LOGNAME", me) & (me # "") THEN
      Check.Check(UnixUsers.Become(me, err) & (err.code = 0) & (err.text = ""),
        "Become the user it is already");
      Check.Check(~UnixUsers.Root(), "and is still not root")
    ELSE
      Out.String("skip - neither USER nor LOGNAME is set"); Out.Ln
    END;

    Check.Check(~UnixUsers.Become("nobody", err) & (err.code = 0)
      & (err.text = "become nobody: only root can become another user"),
      "Become another user: fails, not root");

    Check.Check(~UnixUsers.Become("pounix-no-such-user", err) & (err.code = 0)
      & (err.text = "become pounix-no-such-user: no such user"),
      "Become a user that doesn't exist: fails");

    Check.Check(~UnixUsers.Become("", err) & (err.text = "become : no such user"),
      "Become the empty name: no such user")
  END;
  Check.Summary
END TestUsers.
