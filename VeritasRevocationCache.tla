------------------------- MODULE VeritasRevocationCache -------------------------
(***************************************************************************)
(* The production shape of Veritas verification: verifiers work OFFLINE    *)
(* from a cached copy of the signed revocation list, refreshed from time   *)
(* to time. This model asks what a cache does to revocation.               *)
(*                                                                         *)
(* Result 1 (StrictRevocation): with ANY cache, a just-revoked credential  *)
(* can still be accepted until the next refresh. The window is inherent to *)
(* offline verification, so TLC produces a counterexample even when the    *)
(* freshness guard is on.                                                  *)
(*                                                                         *)
(* Result 2 (BoundedStaleness): with the freshness guard on (refuse to     *)
(* verify from a cache older than MaxStale), a credential revoked more     *)
(* than MaxStale ticks ago is NEVER accepted. With the guard off, TLC      *)
(* exhibits the stale-cache acceptance trace.                              *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS Creds, MaxTime, MaxStale, CheckFreshness

VARIABLES time, issued, exp, revoked, revokedAt, cache, cacheAt,
          lastAccepted,       \* did a verifier accept something in the last step?
          lastRevoked,        \* was that credential revoked (at the issuer) when accepted?
          lastStaleRevoked    \* ... revoked MORE than MaxStale ticks before it was accepted?
vars == <<time, issued, exp, revoked, revokedAt, cache, cacheAt,
          lastAccepted, lastRevoked, lastStaleRevoked>>

TypeOK ==
    /\ time \in 0..MaxTime
    /\ issued \subseteq Creds
    /\ exp \in [Creds -> 1..MaxTime]
    /\ revoked \subseteq Creds
    /\ revokedAt \in [Creds -> 0..MaxTime]
    /\ cache \subseteq Creds
    /\ cacheAt \in 0..MaxTime
    /\ lastAccepted \in BOOLEAN
    /\ lastRevoked \in BOOLEAN
    /\ lastStaleRevoked \in BOOLEAN

Init ==
    /\ time = 0
    /\ issued = {}
    /\ exp = [c \in Creds |-> MaxTime]
    /\ revoked = {}
    /\ revokedAt = [c \in Creds |-> 0]
    /\ cache = {}
    /\ cacheAt = 0
    /\ lastAccepted = FALSE
    /\ lastRevoked = FALSE
    /\ lastStaleRevoked = FALSE

Issue(c, e) ==
    /\ c \notin issued
    /\ issued' = issued \cup {c}
    /\ exp' = [exp EXCEPT ![c] = e]
    /\ UNCHANGED <<time, revoked, revokedAt, cache, cacheAt, lastAccepted, lastRevoked, lastStaleRevoked>>

Revoke(c) ==                       \* the issuer revokes; verifiers have not heard yet
    /\ c \in issued
    /\ c \notin revoked
    /\ revoked' = revoked \cup {c}
    /\ revokedAt' = [revokedAt EXCEPT ![c] = time]
    /\ UNCHANGED <<time, issued, exp, cache, cacheAt, lastAccepted, lastRevoked, lastStaleRevoked>>

Refresh ==                         \* the verifier fetches the current signed list
    /\ cache' = revoked
    /\ cacheAt' = time
    /\ UNCHANGED <<time, issued, exp, revoked, revokedAt, lastAccepted, lastRevoked, lastStaleRevoked>>

Tick ==
    /\ time < MaxTime
    /\ time' = time + 1
    /\ UNCHANGED <<issued, exp, revoked, revokedAt, cache, cacheAt, lastAccepted, lastRevoked, lastStaleRevoked>>

(* The verifier only sees its cache. With the freshness guard it refuses to  *)
(* verify (fails closed) once the cache is older than MaxStale.              *)
Accepts(c) ==
    /\ c \in issued
    /\ time <= exp[c]
    /\ c \notin cache
    /\ (CheckFreshness => time - cacheAt <= MaxStale)

Verify(c) ==
    /\ Accepts(c)
    /\ lastAccepted' = TRUE
    /\ lastRevoked' = (c \in revoked)
    /\ lastStaleRevoked' = ((c \in revoked) /\ (time - revokedAt[c] > MaxStale))
    /\ UNCHANGED <<time, issued, exp, revoked, revokedAt, cache, cacheAt>>

Next ==
    \/ \E c \in Creds, e \in 1..MaxTime : Issue(c, e)
    \/ \E c \in Creds : Revoke(c)
    \/ Refresh
    \/ Tick
    \/ \E c \in Creds : Verify(c)
    \/ UNCHANGED vars

Spec == Init /\ [][Next]_vars

StrictRevocation == lastAccepted => ~lastRevoked        \* impossible offline: expect a counterexample
BoundedStaleness == lastAccepted => ~lastStaleRevoked   \* holds iff the freshness guard is on
================================================================================
