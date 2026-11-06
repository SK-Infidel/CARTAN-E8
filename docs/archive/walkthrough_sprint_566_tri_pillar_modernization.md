# Walkthrough: Sprint 566 — Tri-Pillar Cognitive Modernization (`ode_solver.cl`, `azr_engine.cl`, `webgpu_causal_engine.cl`)

## Objectives
Per Daddy Rick's directive ("All of them?"), modernize all three remaining candidates from legacy v1 into sovereign continuous 248-D $E_8$ non-Euclidean subsystems:
1. **[`Projects/geomind/ode_solver.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/ode_solver.cl)**: 4th-order Runge-Kutta (RK4) and symplectic flow integrator on the Sasaki tangent bundle $TS^{247}$ with zero allocation and exact canonical radius preservation ($\|h\|_2 = \sqrt{248} = 15.748016$).
2. **[`Projects/geomind/azr_engine.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/azr_engine.cl)**: Active Zero-Shot Reasoner with autonomous Proposer-Verifier self-play across the 6 relational strata, evaluating forward-backward adjoint consistency and applying Riemannian natural gradient self-correction.
3. **[`Projects/geomind/webgpu_causal_engine.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/webgpu_causal_engine.cl)**: WebGPU compute shader pipeline generating WGSL kernels for Finsler-Randers causal attention (2,896 bytes), $\mathfrak{so}(16)_{120} \oplus S_{16}^+ (128)$ gauge-spinor Fano cross-gate (2,579 bytes), and 8-stream Lie cortical filters (1,110 bytes), with VRAM write-lock sandboxing and graceful CPU fallback.

---

## Changes Implemented

### 1. [`Projects/geomind/ode_solver.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/ode_solver.cl)
- Implemented `geomind_ode_geodesic_accel_248(h, v, h_star, beta, accel_out)`:
  Computes continuous geodesic acceleration:
  $$\frac{d^2 h}{dt^2} = -\frac{\|v\|^2}{\|h\|^2} h + F_{\text{drift}}(v, \beta) + F_{\text{potential}}(h, h^*)$$
- Implemented zero-allocation `geomind_ode_geodesic_step_rk4_248(h, v, h_star, beta, dt, out_h, out_v)`:
  Uses persistent scratch buffers (`g_ode_k1_h`..`g_ode_k4_v`, `g_ode_zero_beta`), retracts onto $S^{247}$ maintaining exact canonical radius, and projects velocity into the tangent space $T_h S^{247}$ ($\langle v, h \rangle = 0.00000000$).
- Implemented `geomind_ode_symplectic_flow_248(h_init, h_target, steps, dt)`:
  Integrates continuous trajectory from $h_{\text{init}}$ to $h_{\text{target}}$ and returns total geodesic action $\mathcal{S}_{\text{flow}}$.
- Built verification suite `geomind_ode_test_all()`.

### 2. [`Projects/geomind/azr_engine.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/azr_engine.cl)
- Implemented `geomind_azr_matrix_vec_mul` and `geomind_azr_matrix_transpose_vec_mul` for $248 \times 248$ bilinear operators.
- Implemented `geomind_azr_verify_adjoint_consistency(u, v, R)`:
  Evaluates forward prediction $v_{\text{proj}} = R u$ and backward adjoint reconstruction $u_{\text{recon}} = R^\top v$, computing harmonic consistency:
  $$\text{Consistency} = \frac{2 \langle v, R u \rangle \langle u, R^\top v \rangle}{248 (\langle v, R u \rangle + \langle u, R^\top v \rangle)}$$
- Implemented `geomind_azr_propose_and_verify_chain(concept_word, target_stratum)`:
  Proposes multi-hop trajectories across Stratum 1 (Hypernym), Stratum 2 (Superordinate), and Stratum 3 (Capability).
- Implemented `geomind_azr_run_self_play(episodes, lr)`:
  Runs autonomous Proposer-Verifier episodes, scores verification rewards across all cognitive tiers, and triggers Riemannian natural gradient self-correction when consistency dips below threshold.

### 3. [`Projects/geomind/webgpu_causal_engine.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/webgpu_causal_engine.cl)
- Implemented complete, valid WGSL compute shader generators:
  - `webgpu_get_e8_finsler_randers_attn_shader()` (2,896 bytes)
  - `webgpu_get_e8_gauge_spinor_fano_shader()` (2,579 bytes)
  - `webgpu_get_e8_lie_streams_shader()` (1,110 bytes)
- Implemented `webgpu_engine_init()` checking VRAM write-lock sandboxing status via `cartan_rt_check_vram_access()` and mounting pipelines.
- Built verification suite `geomind_webgpu_test_all()`.

### 4. Integration & Driver ([`Projects/geomind/main.car`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/main.car))
- Added includes for all three modules.
- Wired CLI flags `--ode-test`, `--azr`, and `--webgpu-test` into help dialogue, non-chat mode check, and CLI dispatcher.

---

## Empirical Verification
1. **Compilation**:
   `cartanc.exe build Projects/geomind/main.car -o bin/geomind.exe` completed with Exit Code 0 (MSVC Clang -O2).
2. **ODE Integrator**:
   `.\bin\geomind.exe --ode-test`:
   - Initial Radius: `15.748016`
   - Post-RK4 Radius: `15.748016` (Exact match)
   - Tangent Orthogonality $\langle v, h \rangle$: `0.00000000`
   - 10-Step Symplectic Geodesic Flow Action: `S = 18.066790`
3. **Active Zero-Shot Reasoner**:
   `.\bin\geomind.exe --azr -episodes 1`:
   - 6 concept episodes evaluated (`sparrow`, `robin`, `kitten`, `puppy`, `orb`, `sphere`).
   - Mean Consistency Reward: `1.0237` across Tier 1, 2, and 3 reasoning chains.
4. **WebGPU Causal Engine**:
   `.\bin\geomind.exe --webgpu-test`:
   - All 3 WGSL kernels structurally validated and mounted.
   - VRAM Write-Lock Sandboxing ACTIVE.
5. **Full Regression Check**:
   `.\bin\geomind.exe --eval-qa` passing with zero regressions.
