MODULE UnixUsers; (* Running as another user *)

(* A server started as root, to bind a low port or read keys only root
   may, should then run as a user of its own who can do no more than
   it needs. Become makes it that user for good: root can't be had
   back. From pogemini's GemUser. *)

IMPORT SYSTEM, UnixErrors;

CONST
  (* what the C part's become failed at *)
  NoUser = 1; NotRoot = 2; Lookup = 3; Groups = 4; UserId = 5; Regained = 6;

PROCEDURE ["C", "UnixUsers.-root"] CRoot(): SYSTEM.INT32;
PROCEDURE ["C", "UnixUsers.-become"] CBecome(user: ARRAY OF CHAR;
  VAR step: SYSTEM.INT32): SYSTEM.INT32;

(* Appends s to what, as much of it as fits. *)
PROCEDURE Append(s: ARRAY OF CHAR; VAR what: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE what[i] # 0X DO INC(i) END;
  j := 0;
  WHILE (j < LEN(s)) & (s[j] # 0X) & (i < LEN(what) - 1) DO
    what[i] := s[j]; INC(i); INC(j)
  END;
  what[i] := 0X
END Append;

(* Whether the process runs as root: its effective user ID is 0. *)
PROCEDURE Root*(): BOOLEAN;
BEGIN RETURN CRoot() # 0
END Root;

(* Becomes user, with its groups, then its user ID, for good, and
   checks that root can't be had back. As root, any user; otherwise
   only the one it already is, which changes nothing. FALSE, with err,
   if it can't: code 0 for a user that doesn't exist, one not root
   asking for another user, or root regained, and the errno value for
   anything else. After a failure as root, the process may have taken
   the user's groups but not its ID, so it should stop. *)
PROCEDURE Become*(user: ARRAY OF CHAR; VAR err: UnixErrors.Error): BOOLEAN;
  VAR code, step: SYSTEM.INT32; what: ARRAY 300 OF CHAR;
BEGIN
  UnixErrors.Clear(err); step := 0;
  code := CBecome(user, step);
  IF (code = 0) & (step = 0) THEN RETURN TRUE END;
  what := "become "; Append(user, what);
  IF step = NoUser THEN UnixErrors.SetOther(err, what, "no such user")
  ELSIF step = NotRoot THEN UnixErrors.SetOther(err, what, "only root can become another user")
  ELSIF step = Regained THEN UnixErrors.SetOther(err, what, "could become root again")
  ELSIF step = Lookup THEN UnixErrors.SetSystem(err, code, what)
  ELSIF step = Groups THEN Append(" (its groups)", what); UnixErrors.SetSystem(err, code, what)
  ELSE ASSERT(step = UserId); Append(" (its user ID)", what); UnixErrors.SetSystem(err, code, what)
  END;
  RETURN FALSE
END Become;

END UnixUsers.
