# Implementation Plan: Sprint 567 — Sovereign E8 Weight Merging (`merge_model_weights.cl`), Thermodynamic Ising State Machine (`ising_state_machine.cl`), & Non-Euclidean Telemetry Logger (`logger.cl`)

## Context & Objectives
Per Daddy Rick's approval of the modernization assessments:
1. **`Projects/geomind/merge_model_weights.cl`**:
   - Rewrite as sovereign $E_8$ & BLT Model Merging Engine.
   - Implement Riemannian SLERP on $S^{247}$, TIES sign-elect consensus, DARE drop-and-rescale, and Task Arithmetic on the Lie algebra $\mathfrak{e}_8$.
   - Enable blending of Meta BLT byte representations and multi-checkpoint model consolidation.
2. **`Projects/geomind/ising_state_machine.cl`**:
   - Rewrite as a continuous 248-spin Ising decision glass on $S^{247}$.
   - Coupled Glauber spin dynamics, variational free energy $F = E - T S$, and simulated annealing for crisp basin snapping.
3. **`Projects/geomind/logger.cl`**:
   - Rewrite as structured continuous non-Euclidean telemetry logger.
   - Formats and persists Lagrangian action $\mathcal{S}$, geodesic kinetic energy $T_{\text{geo}}$, Markov potential $V_{\text{Markov}}$, Finsler-Randers drift $\|b\|$, and $S^{247}$ radius stability to JSONL and terminal streams.
4. **`Projects/geomind/archive/engine.cl`**:
   - Remains cleanly archived per Option A (modular execution is natively handled by `byte_latent.cl`, `e8_stack.cl`, and `main.car`).
5. **Integration & Verification**:
   - Wire all three modules into `Projects/geomind/main.car`.
   - Add CLI test commands: `--merge-test`, `--ising-test`, `--log-test`.
   - Build natively with `cartanc.exe` into `bin/geomind.exe`.
   - Empirically verify all three subsystems.
   - Update `CHANGELOG.md` (`[2.21.0]`) and `ISSUES.md` (`[ISSUE-E8-021]`).
