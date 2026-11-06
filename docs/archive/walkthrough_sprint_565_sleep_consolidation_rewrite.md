# Walkthrough: Sprint 565 — Sovereign Continuous E8 Sleep Consolidation Engine (`sleep.cl`, `sleep.car`)

## Objectives
Implement the continuous non-Euclidean metacognitive sleep consolidation subsystem for GeoMind v2, replacing legacy v1 code with native 248-D continuous $E_8$ operations:
1. **Hippocampal-Neocortical Manifold Rehearsal**: Rehearse $S^{247}$ sentence basins through the 8-stream Lie cortical filter and relax decoder head $W_{\text{dec}}$ without mutating canonical corpus coordinates.
2. **Topological Void Detection & Geodesic SLERP Discovery Bridging**: Detect semantic voids on $S^{247}$ ($0.15 \le \cos_{ij} \le 0.45$) and crystallize discovery bridges into $S^{247}$ anchor attractors (`g_e8_anchor_*`).
3. **Synaptic Homeostasis & Randers Drift Damping**: Apply mild weight decay to $W_{\text{dec}}$, damp Finsler-Randers causal drift $\|b\|$, and clear synaptic refractory buffers.
4. **Standalone Daemon CLI (`sleep.car`) & Driver Integration (`main.car`)**: Support scheduled background execution (`bin/sleep.exe`) and direct invocation via `geomind.exe --sleep`.

---

## Changes Implemented

### 1. [`Projects/geomind/sleep.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/sleep.cl)
- Implemented `geomind_e8_slerp_248(u_248, v_248, t, out_248)`:
  $$\text{slerp}(u, v, t) = \frac{\sin((1-t)\Omega)}{\sin \Omega} u + \frac{\sin(t\Omega)}{\sin \Omega} v, \quad \Omega = \arccos\left(\frac{\langle u, v \rangle}{248}\right)$$
  Unit-sphere normalized onto $S^{247}$ ($\|h\|_2 = \sqrt{248}$).
- Implemented `geomind_sleep_rehearse_basins(cycles, lr)`:
  - Passes sentence basins through `geomind_streams_forward_248(basin_in, basin_out, 0.25)`.
  - Differentiates and relaxes decoder head $W_{\text{dec}}$ on resonant bytes along the Lie gradient.
  - Zero coordinate drift on canonical corpus basins (`g_e8_sent_basin_vecs`), preserving exact literature retrieval coordinates.
- Implemented `geomind_sleep_detect_voids_and_bridge(max_bridges)`:
  - Measures pairwise spherical cosines $\cos_{ij} = \langle u_i, u_j \rangle / 248$.
  - Detects semantic voids ($0.15 \le \cos_{ij} \le 0.45$).
  - Synthesizes SLERP midpoint vectors, relaxes via 8-stream Lie filter, and registers into $S^{247}$ anchor basins (`g_e8_anchor_*`) via `geomind_e8_crystallize_patch_vec_internal`.
  - Zero pollution of `g_e8_sent_basin_openers`.
- Implemented `geomind_sleep_synaptic_homeostasis()`:
  - Decays $W_{\text{dec}}$ weights by factor $0.998$ to prevent runaway saturation.
  - Damps Finsler-Randers drift $\|b\|$ by factor $0.95$.
  - Resets cross-turn episodic refractory buffers via `geomind_e8_episodic_refractory_reset()`.
- Implemented `geomind_sleep_run_full_cycle(cycles)`:
  - Runs Phases 1–3 and serializes checkpoints (`geomind_e8_anchors.bin` and `geomind_train_save_checkpoint`).

### 2. Standalone Daemon CLI ([`Projects/geomind/sleep.car`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/sleep.car))
- Created autonomous daemon CLI parsing `-cycles <N>` and `-lr <float>`, invoking `geomind_sleep_run_full_cycle`.

### 3. Engine Integration & Driver ([`Projects/geomind/main.car`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/main.car))
- Included `sleep.cl`.
- Added `--sleep` flag to help dialog, non-chat mode check, and CLI dispatcher.

### 4. Helper API ([`Projects/geomind/byte_latent.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/byte_latent.cl))
- Added `geomind_byte_latent_readout_dot(state_248, byte_c)` computing genuine inner products between 248-D state vectors and $W_{\text{dec}}$ columns.

---

## Empirical Verification
1. **Compilation**:
   - `cartanc build Projects/geomind/sleep.car -o bin/sleep.exe`: Exit 0 (clean LLVM IR & MSVC Clang link).
   - `cartanc build Projects/geomind/main.car -o bin/geomind.exe`: Exit 0 (clean link).
2. **Offline Sleep Execution**:
   - `.\bin\sleep.exe -cycles 1`:
     - Rehearsed 551 sentence basins.
     - Synthesized 6 geodesic anchor discovery bridges on $S^{247}$.
     - Applied synaptic homeostasis (Randers drift $\|b\|$ relaxed from 0.545 to 0.518).
     - Saved checkpoints; sentence basins remained exactly at 551.
3. **Epistemic QA Regression Suite**:
   - `.\bin\geomind.exe --eval-qa` passing with zero degradation.
