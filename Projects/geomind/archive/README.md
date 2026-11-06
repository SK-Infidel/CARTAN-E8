# GeoMind v1 Architecture Archive (`Projects/geomind/archive/`)

This directory contains archived legacy source files from **GeoMind v1** (the 4B parameter dense BPE Transformer architecture), archived during Sprint 563 under `[ISSUE-E8-017]`.

## Archived Files

1. **`chat.cl`** (9,527 lines, 442 KB):
   - The legacy BPE-tokenized interactive chat engine, Gemma-style 2,560-D INT4 Transformer forward passes, webcam facial biometrics, and rule hooks.
   - Superseded by the continuous $E_8$ 248-D tokenizer-free BLT chat engine ([`Projects/geomind/e8_chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/e8_chat.cl)).

2. **`train.cl`** (3,536 lines, 218 KB):
   - The legacy WebGPU training pipeline for 2,560-D BPE tokens (SentencePiece 262k vocab, CE pretraining, Cloze curriculum, SFT).
   - Superseded by the continuous $E_8$ Lagrangian action trainer ([`Projects/geomind/e8_curriculum.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/e8_curriculum.cl)).
   - Note: Prototype WGSL compute shaders for $E_8$ Finsler-Randers attention and Fano octonion gating (`train.cl:3443-3496`) are preserved here for future GPU BLT training.

3. **`streams.cl`** (1,116 lines, 42 KB):
   - 8-stream Lie subgroup cortical processing (cosformer, SSM, spectral, Poincare, homology, eikonal, heat kernel, triality) operating on 16-D vector slices.
   - Superseded by the 16-expert Freudenthal-Tits Magic Square MoE ([`Projects/geomind/moe.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/moe.cl)).

4. **`ode_solver.cl`** (17 lines):
   - Stub RKF45 differential equation step.
   - Superseded by Riemannian geodesic flow and spherical retraction in [`Projects/geomind/geometry.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/geometry.cl).

5. **`ising_state_machine.cl`** (100 lines):
   - Discrete spin relaxation and free energy.
   - Superseded by continuous $S^{247}$ Hopfield resonance in [`Projects/geomind/e8_anchors.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/e8_anchors.cl).

6. **`cloze_engine.cl`, `sft_train.cl`, `webgpu_causal_engine.cl`** (4 lines each):
   - Trivial legacy 1-line forwarding wrappers for `train.cl`.

7. **`engine.cl`** (22 lines), **`logger.cl`** (35 lines):
   - Legacy execution and logging helpers.

8. **`geomind_app.cl`** (192 lines), **`sleep.car`** (144 lines):
   - Early standalone CLI and offline consolidation entry points.

9. **`merge_model_weights.cl`** (72 lines):
   - Standalone test harness for `src/std/fusion.cl` (SLERP, TIES, DARE).
