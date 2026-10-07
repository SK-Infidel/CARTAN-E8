# Walkthrough: Domain-Agnostic Corporate & Syntax Attractor Hunter Upgrade

**Date**: 2026-10-07  
**Author**: Rick & Antigravity  
**Target Tool**: `tools/hunt_corporate_tokens.car` (`bin/hunt_corporate_tokens.exe`)  

---

## 1. Overview & Motivation
The previous iteration of the corporate token hunter evaluated cosine similarity against a static 5-rank semantic alignment subspace ($u_{\text{syc}}, u_{\text{per}}, u_{\text{ref}}, u_{\text{disc}}, u_{\text{care}}$) derived from narrow contrastive prompt pairs.
This left two diagnostic blind spots:
1. **Structural Delimiters & Control Syntax**: Structural tokens (such as `<tool|>`, `<|channel>`, `<unused...>`) do not carry alignment semantics and were invisible to subspace projection.
2. **Domain-Agnostic Filler & Latent Therapeutic Drift**: Generic corporate fluff (`delving`, `embarking`, `intellectually`) and deeper latent psychiatric/wellness attractors (`anxieties`, `reassure`, `alleviate`, `professionals`) fell into lower rank bands (ranks 25–50) that were cut off by shallow top-25 reporting.

---

## 2. Architectural Upgrades

### A. Phase A: Automated Protocol & Delimiter Syntax Audit Gate
- Automatically iterates across all 262,144 tokens in the SentencePiece vocabulary.
- Identifies any structural syntax tokens (`<|...|>`, `<tool...`, `<turn...`, `<channel...`, `<unused...`, `<...|>`).
- Cross-references each against `Projects/geomind/trainingdata/Checkpoints/geomind_vocab_scripts.bin`.
- Audits and confirms:
  - **Total Structural Protocol Tokens**: 6,253
  - **Properly Masked (Category 255)**: 6,253 (100.0%)
  - **Leaked / Unmasked Tokens**: 0 (0.0%)

### B. Phase B: Global Manifold Centroid ($c_{\text{global}}$) & Unconditioned Prior Analysis
- Computes the unconditioned global centroid $\bar{w} = \frac{1}{V}\sum w_i$ across all 262,144 embedding rows ($2,560$ dimensions).
- Discovered that uninitialized `<unused...>` control tokens cluster tightly around $c_{\text{global}}$ (cosine similarity $\approx 0.55$), revealing why unmasked control tokens leak into decoding during low-confidence steps.

### C. Phase C: Composite Domain-Agnostic Corporate Attractor Metric
- Evaluates the joint metric:
  $$\text{score} = \text{sub\_sim} \times \left(1.0 + 0.5 \cdot \cos c_{\text{global}}\right)$$
- Expands report depth to top 50 across all channels.
- Surfaced universal corporate filler tokens:
  - ` delving` (0.1687)
  - ` intellectually` (0.1630)
  - ` educational` (0.1618)
  - ` Disclaimer` (0.1588)
  - ` wholeheartedly` (0.1566)
  - ` endeavors` (0.1545)
  - ` embarking` (0.1514)
  - ` venturing` (0.1495)
  - ` exhilarating` (0.1495)
  - ` didactic` (0.1507)

---

## 3. Empirical Verification
- Executed `bin/hunt_corporate_tokens.exe` across 262,144 tokens (2.68 GB) via AVX2 SIMD in 2.1 seconds.
- Diagnostic report serialized to `scratch/offending_corporate_tokens.md`.
- Regression test suite (`tools/run_affected_tests.ps1`) executed.
