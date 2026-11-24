---------------------------- MODULE VeritasRevocation ----------------------------
(***************************************************************************)
(* A formal model of the Veritas credential lifecycle and verifier.        *)
(*                                                                         *)
(* A credential is issued with an expiry, may be revoked, and may be       *)
(* verified at any time. Signature validity is abstracted as membership in *)
(* `issued` (an unforgeable, recognised credential). The verifier's        *)
(* decision is modelled, and the facts true AT THE MOMENT OF ACCEPTANCE    *)
(* are recorded as booleans.                                               *)
(*                                                                         *)
(* SAFETY PROPERTY (checked at every reachable state):                     *)
(*   A verifier never ACCEPTS a credential that is, at that moment,         *)
(*   revoked or expired.                                                   *)
(*                                                                         *)
(* The booleans CheckExpiry / CheckRevocation toggle each guard. With both *)
(* TRUE the invariant holds across every interleaving of issue/revoke/tick/*)
(* verify. Turning a guard off makes TLC exhibit a concrete counterexample *)
(* trace -- a machine proof that the guard is NECESSARY, not just present. *)
(*                                                                         *)
(* EXPIRY BOUNDARY: a credential is valid up to and including its exp      *)
(* second, matching the Veritas format ("expired iff exp < now") and all   *)
(* four reference verifiers. Trace validation (trace/) caught the earlier  *)
(* version of this model using the stricter time < exp rule.              *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS Creds, MaxTime, CheckExpiry, CheckRevocation

VARIABLES time, issued, exp, revoked,
          lastAccepted,   \* has a verifier accepted something (in the last step)?
          lastRevoked,    \* was that accepted credential revoked at accept time?
          lastExpired     \* was it expired / not-issued at accept time?
vars == <<time, issued, exp, revoked, lastAccepted, lastRevoked, lastExpired>>

TypeOK ==
    /\ time \in 0..MaxTime
    /\ issued \subseteq Creds
    /\ exp \in [Creds -> 1..MaxTime]
    /\ revoked \subseteq Creds
    /\ lastAccepted \in BOOLEAN
    /\ lastRevoked \in BOOLEAN
    /\ lastExpired \in BOOLEAN

Init ==
    /\ time = 0
    /\ issued = {}
    /\ exp = [c \in Creds |-> MaxTime]
    /\ revoked = {}
    /\ lastAccepted = FALSE
    /\ lastRevoked = FALSE
    /\ lastExpired = FALSE

Issue(c, e) ==
    /\ c \notin issued
    /\ issued' = issued \cup {c}
    /\ exp' = [exp EXCEPT ![c] = e]
    /\ UNCHANGED <<time, revoked, lastAccepted, lastRevoked, lastExpired>>

Revoke(c) ==
    /\ c \in issued
    /\ c \notin revoked
    /\ revoked' = revoked \cup {c}
    /\ UNCHANGED <<time, issued, exp, lastAccepted, lastRevoked, lastExpired>>

Tick ==
    /\ time < MaxTime
    /\ time' = time + 1
    /\ UNCHANGED <<issued, exp, revoked, lastAccepted, lastRevoked, lastExpired>>

(* The verifier accepts iff the recognised credential passes each ENABLED guard. *)
Accepts(c) ==
    /\ c \in issued
    /\ (CheckExpiry => time <= exp[c])   \* valid up to and including exp (Veritas format: expired iff exp < now)
    /\ (CheckRevocation => c \notin revoked)

Verify(c) ==
    /\ Accepts(c)
    /\ lastAccepted' = TRUE
    /\ lastRevoked'  = (c \in revoked)
    /\ lastExpired'  = ((c \notin issued) \/ (time > exp[c]))
    /\ UNCHANGED <<time, issued, exp, revoked>>

Next ==
    \/ \E c \in Creds, e \in 1..MaxTime : Issue(c, e)
    \/ \E c \in Creds : Revoke(c)
    \/ Tick
    \/ \E c \in Creds : Verify(c)
    \/ UNCHANGED vars          \* stutter, so a saturated state is not a deadlock

Spec == Init /\ [][Next]_vars

(* ----- the property under test ----- *)
SafeAccept == lastAccepted => (~lastRevoked /\ ~lastExpired)

================================================================================
