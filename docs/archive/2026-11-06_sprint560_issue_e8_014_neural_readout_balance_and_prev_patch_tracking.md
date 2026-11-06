# Sprint 560 Walkthrough: Resolution of [ISSUE-E8-014] Thermodynamic Readout Balancing & Continuous Causal Patch Tracking

## Overview
- **Issue**: `[ISSUE-E8-014]` Neural Readout $W_{\text{dec}}$ Dwarfed by $\log(m\_prob)$ & Missing `h_prev_patch` in Generation
- **Modules**: [`Projects/geomind/byte_latent.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/byte_latent.cl), [`Projects/geomind/e8_curriculum.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/e8_curriculum.cl)
- **Goals**:
  1. Restore natural thermodynamic balance between the 42-layer $E_8$ neural manifold readout ($W_{\text{dec}}$) and the Markov Tapestry prior ($m\_prob$).
  2. Eliminate the $-10.0$ artificial logit cliff on low-probability/unseen n-grams.
  3. Track `h_prev_patch` continuously across patch boundaries and generation invocations via persistent tensors, matching training dynamics.

---

## Key Changes

### 1. Thermodynamic Readout Balancing in `geomind_byte_latent_decode_logits_blt`
**File**: [`Projects/geomind/byte_latent.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/byte_latent.cl#L388-L425)
- **Problem**:
  - The neural readout dot product was artificially squashed by $0.15 \times 0.25 = 0.0375$ on $W_{\text{dec}}$, producing neural logit ranges of only $\approx [-0.3, +0.3]$.
  - The Markov prior logit $\log(m\_prob + 0.00001)$ spanned $[-11.51, 0.0]$, plus an artificial $-10.0$ cliff on $mp < 0.035$.
  - Consequently, generation was ~95%+ driven by the Markov table, rendering the 42-layer manifold almost powerless.
- **Solution**:
  - Replaced $hv$ normalization with an uncompressed fusion of local and contextual patch latents:
    $$hv = 0.5 \cdot hl + 0.5 \cdot hp \quad (\|hv\| \approx 15.75)$$
  - Scaled the neural readout dot product by $4.0 \times \langle hv, W_{\text{dec}}[:, b] \rangle$, expanding neural logits to $[-8.0, +12.0]$ with $\sigma \approx 2.5 - 3.5$.
  - Tempered the Markov logit to $0.65 \times \log(m\_prob + 0.0005)$ and clamped it at a $-5.0$ floor, eliminating the $-10.0$ cliff.
  - Synchronized the training backward pass in `geomind_byte_latent_train_deep_e8_corpus` ([`Projects/geomind/e8_curriculum.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/e8_curriculum.cl#L753-L772)) with identical $0.5 \cdot hl + 0.5 \cdot hp$ fusion and $4.0 \times$ gradient multiplier.

### 2. Continuous Causal Patch Tracking in `geomind_byte_latent_generate_deep_e8`
**File**: [`Projects/geomind/byte_latent.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/byte_latent.cl#L42-L44, #L462-L470, #L555-L568, #L730-L744)
- **Problem**:
  - Generation previously passed `prev_patch_ptr = 0.0` to `geomind_e8_stack_forward_step` on initial step or whenever `patch_steps == 0`, losing causal attention across prompt and generation segments.
- **Solution**:
  - Introduced persistent module globals:
    - `g_e8_gen_prev_patch`: $248\text{D}$ tensor storing previous patch latent.
    - `g_e8_gen_top_patch`: $248\text{D}$ tensor storing top-layer patch latent.
    - `g_e8_gen_has_prev`: scalar flag tracking causal history validity.
  - In `geomind_byte_latent_generate_deep_e8`:
    - Loaded initial `h_prev_patch` and `h_top_patch` from persistent storage.
    - Passed valid `h_prev_patch` to `geomind_e8_stack_forward_step` whenever `patch_steps > 0 || g_e8_gen_has_prev == 1.0`.
    - Persisted newly completed patch latents at every patch boundary, ensuring continuous causal attention across generation calls.

---

## Empirical Verification
1. **Compilation**:
   `.\cartanc.exe build Projects\geomind\main.car -o bin\geomind.exe`
   - Output: Clean build, 0 errors, 219,865 LLVM IR instructions.
2. **Regression & QA Suite**:
   `.\bin\geomind.exe --eval-qa`
   - All 20 core questions (`Q1`–`Q20`): 100% pass rate.
   - Novel Concept Recombination (`Novel 1`–`Novel 8`): 100% pass rate.
   - WordNet Grokking (`Grok 1`–`Grok 4`): 100% pass rate.
   - Stratified 42L Rollouts (`Rollout 1`–`Rollout 10`): 100% pass rate.
   - Subtle Geometric Reasoning (`Subtle 1`–`Subtle 4`): 100% pass rate.
