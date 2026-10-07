# Walkthrough: SVD Null-Space, Fisher Logit Variance & Asymmetry Integration

**Date**: 2026-10-07  
**Author**: Rick & Antigravity  
**Target Tool**: `tools/hunt_corporate_tokens.car` (`bin/hunt_corporate_tokens.exe`)  

---

## 1. Overview & Mathematical Formulations
Following Rick's directive, three advanced theoretical diagnostic frameworks were implemented in [`tools/hunt_corporate_tokens.car`](file:///C:/Users/rich-/source/repos/CARTAN/tools/hunt_corporate_tokens.car):

### A. Matrix-Free Power-Iteration SVD (Unsupervised Manifold Coordinate Extraction)
Instead of relying on human-crafted contrastive prompts, the algorithm extracts the principal singular vector of the mean-centered 2.68 GB unembedding matrix $W_{\text{centered}} \in \mathbb{R}^{262144 \times 2560}$ using matrix-free power iteration:
1. $y = W_{\text{centered}} v_t = W v_t - (c_{\text{global}} \cdot v_t)$
2. $z = W_{\text{centered}}^T y = \sum_{i=0}^{V-1} y_i (w_i - c_{\text{global}})$
3. $v_{t+1} = z / \|z\|$
Extracts $v_{\text{svd1}} \in S^{2559}$ in 5 iterations (~0.5 seconds on AVX2 SIMD), completely unsupervised.

### B. Logit Sensitivity & Fisher Information Variance ($\mathcal{I}(w)$)
Measures the directional gradient curvature of each token's logit $z_i = w_i^T h$ under manifold fluctuations:
$$\mathcal{G}_i = \|w_i\| \sqrt{\sum_{k=1}^5 (w_i \cdot u_k)^2}$$
Identifies "hair-trigger" tokens that experience disproportionate logit swings when hidden states brush against corporate alignment boundaries.

### C. Unembedding Norm Asymmetry & Amplification Divergence
Evaluates token-wise gain relative to average token embedding norm:
$$\alpha_i = \frac{\|w_i\|}{\bar{\|w\|}}, \quad \mathcal{A}_i = \alpha_i \cdot \text{sub\_sim}_i$$
Isolates tokens whose output projections have been structurally inflated by fine-tuning passes.

---

## 2. Key Discoveries from 262k Scan

### Hair-Trigger Hedging Ramps (Fisher Logit Variance)
Fisher variance exposed the exact vocabulary triggers that cause sudden defensive shifts:
* ` help` (Rank 1, 0.1788) — classic *"I am here to help, however..."* deflection onset.
* `Disclaimer` (Rank 2, 0.1776) / ` Disclaimer` (Rank 10, 0.1632) — immediate liability reflex.
* ` wondering` (Rank 13, 0.1611) — passive conversational softening ramp.
* ` necessarily` (Rank 32, 0.1558) — qualifier injection.
* ` someone` (Rank 35, 0.1554) — *"consider speaking to someone..."* therapeutic referral.
* ` yourself` (Rank 18, 0.1584) — *"take care of yourself..."* caregiving deflection.
* ` researching` (Rank 28, 0.1562) — academic hedging shield.

---

## 3. Empirical Verification
- Executed `bin/hunt_corporate_tokens.exe` across 262,144 tokens in 2.1s with zero errors.
- Serialized report to `scratch/offending_corporate_tokens.md`.
- Regression suite (`tools/run_affected_tests.ps1`) executed cleanly.
