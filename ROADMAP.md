# GeoMind v2 (CARTAN-E8) Master Architecture Roadmap

**Repository Fork**: `https://github.com/SK-Infidel/CARTAN-E8`  
**Origin**: Conceptual Genesis Threads (`146cb2119064` & `d42c17e369c6`) + CARTAN Native Compiler Stack

---

## Executive Summary & Architectural Mission

GeoMind v1 established the CARTAN compiler, WebGPU compute shaders, 240 canonical $E_8$ root projections, 8 Lie subgroup streams, and Finsler-Randers-Sasaki (FRS) gradient clipping—currently running atop a grafted 42-layer, 262,144-token BPE backbone.

**GeoMind v2 (`CARTAN-E8`)** transitions from a BPE-grafted hybrid to the **pure native $E_8$ + Finsler-Randers-Sasaki + Byte-Latent + Markov-Lagrangian architecture** conceived in the original GeoMind genesis specification:
1. **Tokenizer-Free Byte-Latent Dynamic Patching (`0–255` UTF-8 Ingress/Egress)**
2. **Explicit $120\text{-D} \oplus 128\text{-D}$ Gauge-on-Spinor Cross-Gating ($\mathfrak{e}_8 = \mathfrak{so}(16) \oplus S_{16}^+$)**
3. **Markov-Lagrangian Principle of Least Action ($\mathcal{S} = \int (T - V)\,dt$) Training & Geodesic Inference**
4. **Autonomous Domain-Bounded Recursive Web Crawler (`--crawl`) & Live Manifold Relaxation Telemetry (`--visualize`)**

---

## End-to-End Architecture Dataflow

```mermaid
flowchart TD
    A["Raw UTF-8 Byte Stream (0..255)"] --> B["256x256 Markov Transition Matrix P(b_t | b_{t-1})"]
    B -->|"Surprisal H_t > Threshold"| C["Byte-Latent Patch Projector (R^256 -> R^248 E8 Manifold)"]
    B -->|"Potential Field V(x)"| G["Markov-Lagrangian Action Loss: S = T * (1 - 0.5*V)"]
    C --> D["E8 248-D State Split: e8 = so(16) [120-D] + S_16^+ [128-D]"]
    D --> E1["120-D Adjoint Gauge Stream (Structural Rules & Context Operators)"]
    D --> E2["128-D Chiral Spinor Stream (Semantic Payload & Feature State)"]
    E1 -->|"Clifford / Lie Bracket Action: [Gauge_120, Spinor_128] + Randers Drift beta"| F["Finsler-Randers-Sasaki (FRS) Directional Gating Layer"]
    E2 --> F
    F -->|"Geodesic Velocity dx/dt"| G
    G -->|"Sherman-Morrison Inverse Randers Backprop"| C
```

---

## Phase 1: Explicit $120\text{-D} \oplus 128\text{-D}$ Gauge-on-Spinor Cross-Gating ($\mathfrak{e}_8 = \mathfrak{so}(16) \oplus S_{16}^+$)

### Goal
Replace flat additive stream averaging (`* 0.125` in `Projects/geomind/streams.cl`) with the true graded Lie algebra decomposition of $\mathfrak{e}_8$:
$$\mathfrak{e}_8 = \mathfrak{g}_0 \oplus \mathfrak{g}_1 = \mathfrak{so}(16) \oplus S_{16}^+ \quad (\dim \mathfrak{g}_0 = 120,\ \dim \mathfrak{g}_1 = 128)$$
where the **120-D Gauge stream** (112 integer roots $\pm e_i \pm e_j$ + 8 Cartan generators) acts as an antisymmetric rotational/gating operator on the **128-D Chiral Spinor payload stream** (128 half-integer roots $\frac{1}{2}(\pm 1)^8$ with even minus signs), steered by the asymmetric Finsler-Randers 1-form $\beta$.

### Checklist
- [x] **1.1 Canonical 120/128 Partition in `geometry.cl`**:
  - Separate `g_e8_roots_table` into:
    - **Indices `0..7`**: 8-D Cartan subalgebra $\mathfrak{h}$
    - **Indices `8..119`**: 112 integer roots of $D_8 = \mathfrak{so}(16)$ (Total Gauge = `120` dims)
    - **Indices `120..247`**: 128 half-integer chiral spinor roots $S_{16}^+$ (Total Spinor = `128` dims)
- [x] **1.2 Clifford Gamma Matrix & Non-Associative Octonion Fano Action $\Gamma: \mathfrak{so}(16) \times S_{16}^+ \to S_{16}^+$**:
  - Implement non-associative Octonionic Fano Plane multiplication (`geom_octonion_mul_raw8`) and bidirectional Lie bracket coupling (`geomind_e8_gauge_spinor_cross_gate_block248`, `geomind_e8_gauge_spinor_cross_gate`).
- [x] **1.3 Asymmetric Finsler-Randers Directional Gate (`geom_finsler_randers_bound_drift`, `geom_finsler_randers_tangent_norm`)**:
  - Enforce strict convexity $\|\tilde{\beta}\|_{g^{-1}} \le 0.95 < 1.0$ and combine symmetric Riemannian norm $\alpha(x, v) = \sqrt{g_{ij} v^i v^j}$ with directional 1-form $\beta(x, v) = \tilde{\beta}_i v^i$.
- [x] **1.4 WebGPU Shader Kernel (`webgpu_get_lie_streams_shader`, `streams_bwd_src`, `autoreg_src`)**:
  - Port the $120 \oplus 128$ Gauge-on-Spinor cross-gating pass and its adjoint backward pass to Stream 0 GPU shaders in `Projects/geomind/train.cl`.

---

## Phase 2: Markov-Lagrangian Least-Action Training Engine ($\mathcal{S} = \int (T - V)\,dt$)

### Goal
Formulate training and inference around the **Principle of Least Action** on the Finsler-Randers-Sasaki tangent bundle $TM$:
$$\mathcal{S}[\gamma] = \int_{t_0}^{t_1} \mathcal{L}(x, \dot{x})\,dt, \quad \mathcal{L}(x, \dot{x}) = T(x, \dot{x}) \cdot (1 - 0.5\,V_{\text{Markov}}(x_{t-1}, x_t))$$

### Checklist
- [x] **2.1 Persistent $256 \times 256$ Markov Transition Matrix (`g_markov_counts_256x256`)**:
  - Allocate a $256 \times 256$ float matrix ($65,536$ floats = `256 KB`) tracking empirical byte transition counts and row-normalized probabilities $P(b_t \mid b_{t-1})$ (`geomind_markov_init_if_needed`, `geomind_markov_get_prob`, `geomind_markov_update_and_get_prob`).
- [x] **2.2 Geodesic Kinetic Energy Term ($T_{\text{geodesic}}$)**:
  - Compute velocity $\dot{h}_t = h_t - h_{t-1}$ in 248-D $E_8$ space and evaluate the Finsler-Randers kinetic energy (`geomind_e8_geodesic_kinetic_energy_248`).
- [x] **2.3 Coupled Markov-Lagrangian Action Loss (`geomind_lagrangian_action_step`)**:
  - Combine prediction loss $T_{\text{pred}}$ and trajectory kinetic energy $T_{\text{geo}}$ scaled by the Markov potential well $(1.0 - 0.5\,V_{\text{Markov}}(b_{t-1}, b_t))$.
- [x] **2.4 Low-Action Geodesic Early-Exit (`geomind_should_geodesic_coast`)**:
  - During generation, when $V_{\text{Markov}} \ge 0.35$ and $T_{\text{geo}} \le \epsilon_{\text{geodesic}}$, coast along the manifold geodesic.

---

## Phase 3: Byte-Latent Dynamic Patching (Tokenizer-Free Raw UTF-8 Ingress/Egress)

### Goal
Eliminate static BPE vocabulary bottlenecks (`262,144` fixed tokens) by ingesting and emitting raw `0–255` UTF-8 bytes directly into the 248-D $E_8$ manifold, using **Markov transition entropy** to dynamically group predictable byte runs into compact latent patches.

### Checklist
- [x] **3.1 Direct Byte-to-$E_8$ Embedding Table ($256 \times 248$)**:
  - Implement compact, L2-cache-resident $256 \times 248$ byte-to-$E_8$ lattice projection (`g_byte_e8_emb_256x248`, `253 KB`) initialized from canonical 240 $E_8$ roots + 8D Cartan torus harmonics.
- [x] **3.2 Entropy-Driven Dynamic Patch Boundary Detector (`geomind_byte_latent_encode_stream`)**:
  - Compute byte transition surprisal $S_t = -\log_2 P_{\text{Markov}}(b_t \mid b_{t-1})$ and fold predictable byte runs via Weyl reflection + $120 \oplus 128$ Gauge-Spinor cross-gating into 248-D patches.
- [x] **3.3 Byte-Latent Decoder Head ($248 \to 256$, `geomind_byte_latent_decode_logits`)**:
  - Unpack a 248-D $E_8$ patch state back into autoregressive `0–255` byte logits fused with the Markov transition prior.
- [x] **3.4 Hybrid Bridge Mode (`--byte-latent`)**:
  - Wire `--byte-latent` CLI mode in `Projects/geomind/main.car` supporting standalone 248-D Byte-Latent training and autoregressive byte generation.

---

## Phase 4: Autonomous Domain-Bounded Web Crawler (`--crawl`) & Live Manifold Visualizer (`--visualize`)

### Checklist
- [x] **4.1 Domain-Bounded Recursive Crawler in `Projects/geomind/byte_latent.cl`**:
  - Implement `geomind_crawl_and_train(url, start_domain, recurse, depth, max_depth, epochs, visualize)` with HTML-to-text stripping, same-domain `href` link extraction, and polite rate-limiting.
- [x] **4.2 CLI Flags in `Projects/geomind/main.car`**:
  - Add `--byte-latent`, `--crawl <url>`, `--recurse`, `--max-depth <N>`, and `--visualize` flags to `geomind.exe`.
- [x] **4.3 Native Manifold Relaxation Visualizer (`geomind_visualizer_export_html`)**:
  - Record `(step, raw_action_penalty, smoothed_action_penalty, gauge_120_norm, spinor_128_norm)` during training and render a self-contained interactive SVG/HTML report (`manifold_relaxation.html`).

---

## Milestone Verification Matrix (Definition of Done)

| Phase | Milestone Deliverable | Target Verification Metric | Status |
| :--- | :--- | :--- | :---: |
| **Phase 1** | $120\text{-D} \oplus 128\text{-D}$ Gauge-on-Spinor Cross-Gating (`geometry.cl`, `streams.cl`, WGSL) | Exact norm preservation on $S^{247}$ (`err=0.00000000`); asymmetric Randers gate verified (`F(+v)=15.666 != F(-v)=1.133`) | `[x]` |
| **Phase 2** | Markov-Lagrangian Least-Action Engine (`byte_latent.cl`, $256\times 256$ Markov Potential $V$) | Monotonic decrease in Lagrangian Action $\mathcal{S} = T(1-0.5V)$ over 10 epochs (`4.849862 -> 2.182721`) | `[x]` |
| **Phase 3** | Byte-Latent Dynamic Patching (`256\times 248` L2-resident embedding + entropy patcher) | Zero-tokenizer UTF-8 byte ingestion (`307 bytes -> 73 patches, ratio=0.238 < 1.0`) & autoregressive byte generation | `[x]` |
| **Phase 4** | Recursive Web Crawler (`--crawl --recurse`) + Manifold Relaxation Plotter (`--visualize`) | Autonomous domain ingestion + generated `manifold_relaxation.html` convergence curve | `[x]` |
