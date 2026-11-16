# veritas-tla — a machine-checked proof for credential revocation

<!-- at-a-glance -->
> **A machine-checked proof that a revoked or expired credential never verifies.**  
> **Result:** TLC: 388 reachable states, no violation; 3 configs including counterexamples proving each guard necessary.  
> **Reproduce:** `bash run-checks.sh`  
> ![CI](https://github.com/fhionnghaile/veritas-tla/actions/workflows/ci.yml/badge.svg)
>
> **What this is worth:** Turns 'we check revocation' into 'removing the check is provably unsafe, here is the trace' — the strongest correctness signal there is.


**Claim.** The [Veritas](../Veritas) credential verifier never accepts a credential that
is revoked or expired — and it stays correct under *every* ordering of issue, revoke,
clock-tick and verify events, not just the happy path. This is proved by exhaustive model
checking in **TLA+ / TLC**, not asserted.

## The property

> In no reachable state does a verifier accept a credential that is, at that moment,
> **revoked or expired**.

TLC explores the entire reachable state space of the model and checks this invariant at
every state. For the correct verifier it finds **no violation across 388 reachable states**
(depth 9) — a proof for the bounded model.

## The model (`VeritasRevocation.tla`)

A credential is *issued* with an expiry, may be *revoked*, and may be *verified* at any
time; the clock *ticks* forward. Signature validity is abstracted as membership in
`issued` (an unforgeable, recognised credential). The verifier accepts iff the credential
is recognised and passes each **enabled** guard:

```
Accepts(c) == c \in issued
           /\ (CheckExpiry      => time < exp[c])
           /\ (CheckRevocation  => c \notin revoked)
```

`CheckExpiry` and `CheckRevocation` are constants, so the *same* model proves the property
holds **and** that each guard is load-bearing.

## The results — proof, and the necessity of each guard

| Config | `CheckExpiry` | `CheckRevocation` | TLC result |
|---|---|---|---|
| `correct` | TRUE | TRUE | ✅ **No violation** — invariant holds over all 388 states |
| `no_revocation` | TRUE | FALSE | ❌ **Counterexample**: `Issue → Revoke → Verify` accepts a **revoked** credential |
| `no_expiry` | FALSE | TRUE | ❌ **Counterexample**: `Issue(exp=1) → Tick → Verify` accepts an **expired** credential |

Turning a guard off doesn't just weaken the system in theory — TLC produces the **exact
shortest trace** that breaks it. That's the difference between "we check revocation" and
"removing the revocation check is provably unsafe, and here is how." Full transcripts are
in `results/`.

## Run it

```bash
bash run-checks.sh      # downloads tla2tools.jar if needed; needs only a JVM
```

The harness is self-asserting: it fails unless the correct verifier passes **and** both
reduced verifiers produce their counterexamples. CI runs it on every push.

## Scope & honesty

- This is a **bounded** model (2 credentials, time horizon 3). TLC proves the property
  over that finite space exhaustively; it is strong evidence, not a proof for unbounded
  parameters (that needs an inductive invariant / TLAPS, a natural next step).
- Cryptographic soundness is **abstracted**: `issued` stands in for "signature valid and
  recognised." The proof is about the **protocol logic** (expiry + revocation + ordering),
  which is where lifecycle bugs actually live; the signature layer is verified separately in
  Veritas by cross-implementation test vectors.

## Why this is a technical-depth proof

Formal verification is the strongest correctness signal in security engineering, and
almost no practitioner reaches for it. Modelling a real protocol, stating a safety
property, and having a model checker both confirm it and generate counterexamples for the
broken variants demonstrates a way of thinking about correctness — under adversarial
interleaving — that a 20-year researcher recognises immediately.
