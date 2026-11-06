# Implementation Plan: GeoMind Continuous E8 Sleep Consolidation Engine (`sleep.cl`, `sleep.car`)

## Context & Objectives
In GeoMind v2, offline sleep represents continuous non-Euclidean manifold consolidation:
1. **Hippocampal-Neocortical Manifold Rehearsal**:
   Replays $S^{247}$ sentence basins and episodic memories through the 42-layer $E_8$ stack and 8-stream Lie cortical engine, performing Riemannian geodesic relaxation on high-energy states.
2. **Topological Void Detection & Geodesic SLERP Bridges**:
   Identifies semantic voids on $S^{247}$ between isolated concept basins and synthesizes geodesic SLERP midpoint discovery bridges:
   $$\text{slerp}(u, v, t) = \frac{\sin((1-t)\Omega)}{\sin \Omega} u + \frac{\sin(t\Omega)}{\sin \Omega} v, \quad \Omega = \arccos\left(\frac{\langle u, v \rangle}{248}\right)$$
3. **Synaptic Homeostasis & Finsler-Randers Drift Relaxation**:
   Normalizes the 256x256 Markov transition matrix and decoder head $W_{\text{dec}}$, damping runaway weights and relaxing the causal drift 1-form $b_{248}$.
4. **Episodic Memory Distillation**:
   Flushes short-term synaptic refractory buffers and compacts session turn history into persistent sentence basins.

---

## Technical Specifications

### 1. `Projects/geomind/sleep.cl` (Consolidation Subsystem)
- `geomind_sleep_rehearse_basins(cycles: float, lr: float) -> float`:
  Loops through all loaded $S^{247}$ sentence basins, runs forward 42-layer rollout + 8-stream Lie pass, and applies Sherman-Morrison Finsler-Randers relaxation.
- `geomind_sleep_detect_voids_and_bridge(max_bridges: float) -> float`:
  Measures pairwise spherical cosines $\cos \Omega_{ij}$, finds isolated basins with $0.15 \le \cos \Omega_{ij} \le 0.45$, and synthesizes SLERP midpoint bridge attractors on $S^{247}$.
- `geomind_sleep_synaptic_homeostasis() -> float`:
  Normalizes Markov priors, clips drift 1-form $\|b\| \le 0.05$, and applies slight weight decay to decoder head $W_{\text{dec}}$.
- `geomind_sleep_run_full_cycle(cycles: float) -> float`:
  Executes Phases 1–4 and persists updated weights and basins.

### 2. `Projects/geomind/sleep.car` (Standalone Daemon CLI)
- Entry point for autonomous scheduled background sleep:
  `sleep.exe [-cycles <N>] [-lr <float>]`

### 3. `Projects/geomind/main.car`
- Wire `--sleep` flag to execute sleep consolidation directly from `geomind.exe`.

---

## Verification Plan
1. Compile `bin/sleep.exe` and `bin/geomind.exe` with `cartanc.exe`.
2. Run `.\bin\geomind.exe --sleep` for 1 cycle.
3. Verify:
   - Basin rehearsal passes without error and reports relaxation energy.
   - SLERP discovery bridges are synthesized and retracted onto $S^{247}$.
   - Homeostasis normalizes weights.
   - Checkpoints persist cleanly.
4. Verify zero regression on `.\bin\geomind.exe --eval-qa`.
5. Update `CHANGELOG.md` (`[2.19.0]`) and `ISSUES.md` (`[ISSUE-E8-019]`).
