# Implementation Plan: Sprint 566 — Tri-Pillar Cognitive Modernization (`ode_solver.cl`, `azr_engine.cl`, `webgpu_causal_engine.cl`)

## Context & Objectives
Per Daddy Rick's directive ("All of them?"), modernize the remaining three core subsystems natively for the sovereign 248-D continuous $E_8$ non-Euclidean manifold architecture:
1. **`Projects/geomind/ode_solver.cl` (Symplectic Geodesic Flow Integrator)**:
   - Implement continuous 4th-order Runge-Kutta (RK4) and symplectic Verlet integration on the Sasaki tangent bundle $TS^{247}$:
     $$\dot{h} = v, \quad \dot{v} = -\|v\|^2 h + F_{\text{Randers}}(v, \beta) + F_{\text{potential}}(h)$$
   - Riemannian retraction to maintain exact canonical radius $\|h\|_2 = \sqrt{248}$ on $S^{247}$.
2. **`Projects/geomind/azr_engine.cl` (Continuous $E_8$ Active Zero-Shot Reasoner & Self-Play)**:
   - Proposer-Verifier self-play across the 6 relational strata ($R_{\text{isa}}, R_{\text{super}}, R_{\text{cap}}, R_{\text{val}}, R_{\text{cause}}, R_{\text{effect}}$).
   - Generates multi-hop reasoning branches, evaluates geodesic trajectory action $\mathcal{S}$ and curvature via `ode_solver.cl`.
   - Adjoint $R^\top$ counterfactual verification: detects branch anomalies, rejects false premises, and backpropagates restorative updates.
3. **`Projects/geomind/webgpu_causal_engine.cl` (WebGPU Compute Shader Acceleration Engine)**:
   - Provide complete, verified WGSL compute shaders for:
     1. 248-D Asymmetric Finsler-Randers causal attention on $S^{247}$.
     2. $\mathfrak{so}(16)_{120} \oplus S_{16}^+ (128)$ learned linear + Octonion Fano non-associative cross-gate.
     3. 8-stream Lie cortical subgroup filter.
   - Hardware buffer allocation, WGSL pipeline creation, and graceful CPU fallback.
4. **Integration & Verification**:
   - Wire all three modules into `Projects/geomind/main.car`.
   - Add CLI test commands: `--ode-test`, `--azr`, `--webgpu-test`.
   - Compile natively with `cartanc.exe` into `bin/geomind.exe`.
   - Empirically verify all three subsystems.
   - Update `CHANGELOG.md` (`[2.20.0]`) and `ISSUES.md` (`[ISSUE-E8-020]`).
