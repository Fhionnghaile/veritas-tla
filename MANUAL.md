# veritas-tla — a machine-checked proof for credential revocation — manual

*One page, eight blocks. Every figure here comes from this repository's own tests and README.*

## 1. Claim
TLC finds no state where a revoked or expired credential verifies (388 states, and 15,966 at a larger bound), removing either guard produces a counterexample, and every model state is replayed against the real Veritas verifier with 47,898 of 47,898 decisions agreeing.

## 2. What it is
A formal model of the Veritas verifier, checked exhaustively by a model checker. It proves the revocation and expiry checks are correct under every ordering of events, that each check is necessary, and that the model matches the shipped code. A second model covers offline verification with a cached revocation list.

## 3. Demo
The TLC and trace-validation transcripts in `results/`.

![Real test run, captured 24 Nov 2026](docs/test-run.svg)
*Real output from this repository's checks (`results/`), captured 24 Nov 2026.*

## 4. Run it yourself
**Prerequisites:** A JVM (plus PHP with sodium and the Veritas source for trace validation), or just Docker.

```bash
bash run-checks.sh       # model checks (+ trace validation if php and ../veritas/src are present)
bash run-all-docker.sh   # everything, in throwaway containers
```

## 5. What you will see
Seven model checks and two trace validations, each with its expected outcome: no error at 388 states (depth 9) and 15,966 states (depth 13); a counterexample for each removed guard; for the cached list, bounded staleness holds across 24,600 states, fails without the freshness guard, and strict revocation is shown impossible offline; 776/776 and 47,898/47,898 model-vs-code agreement. The scripts fail unless every outcome is as stated.

## 6. 30-second talking point
> "We check revocation" is a claim. "Removing the revocation check is provably unsafe, and here is the trace" is evidence. Lifecycle bugs live in the ordering of events, and a model checker tries every ordering.

## 7. Scope and limits
- Bounded models (up to 3 credentials, horizon 5). Exhaustive for those spaces, not a proof for unbounded parameters.
- Trace validation covered one boundary mismatch: the model now follows the documented rule (valid up to and including `exp`).
- Cryptographic soundness is abstracted. The signature layer is verified separately in Veritas.

## 8. Links
[Repository](https://github.com/fhionnghaile/veritas-tla) · [Write-up](https://padraigfhionnghaile.com/work/veritas-tla/) · [README](README.md)
