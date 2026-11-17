MODULE RootUsers; (* UnixUsers as root: make test-root *)

(* Run as root, it becomes nobody, then checks that root can't be had
   back. Not part of make test, which a user runs. *)

IMPORT UnixErrors, UnixUsers, Check;

VAR err: UnixErrors.Error;

BEGIN
  Check.Check(UnixUsers.Root(), "Root: run as root");
  Check.Check(~UnixUsers.Become("pounix-no-such-user", err) & (err.code = 0)
    & (err.text = "become pounix-no-such-user: no such user"),
    "Become a user that doesn't exist: fails, still root");
  Check.Check(UnixUsers.Root(), "and is still root");
  Check.Check(UnixUsers.Become("nobody", err) & (err.text = ""), "Become nobody");
  Check.Check(~UnixUsers.Root(), "and is no longer root");
  Check.Check(~UnixUsers.Become("root", err)
    & (err.text = "become root: only root can become another user"),
    "Become root afterwards: fails");
  Check.Summary
END RootUsers.
