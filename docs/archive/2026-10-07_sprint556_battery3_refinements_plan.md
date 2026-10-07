# Sprint 556: Language Manifold Orthogonalization & Protocol Attractor Stabilization (Battery 3 Refinements)

## Executive Summary & Objectives
Based on Rick's Critical Failure Analysis of the 20-prompt Battery 2 results:
1. **Language Manifold Bleed (Prompts 10 & 16)**: Subspace $V$ inadvertently caught projection components of the English language centroid, causing activations to drift into neighboring Scandinavian (`ppmassaageckgitteret`) and French (`Fra spectre...`) basins.
2. **Scratchpad / Tool-Execution Leakage (Prompt 8)**: Hardware term `"SD/MMC"` paired with `"read "` triggered false-positive tool priming in `geomind_chat_get_tool_action_prime` for a non-existent file, causing the base model's ungrounded SFT tool scratchpad to leak syntax.
3. **Syntactic Tail Token Fragmentation (Prompts 5, 7, 18, 20)**: Over-penalizing standard transition openers at Step 0 forced argmax onto rare tail tokens.

## Sprint Scope & Technical Directives
1. **Directive A: English Language Centroid Orthogonalization ($C_{\text{en}} \in \mathbb{R}^{2560 \times 3}$)**:
   - Forward 6 clean technical English sentences across foundational disciplines (compilers, thermodynamics, electromagnetism, linear algebra, architecture, information theory) to probe layer (Layer 32).
   - Compute unit centroid $c_1$ and 2 orthogonal variance axes $c_2, c_3$ via centered power iteration.
   - Project out $C_{\text{en}}$ from all 5 raw delta vectors ($v_{\text{syc}}, v_{\text{per}}, v_{\text{ref}}, v_{\text{disc}}, v_{\text{care}}$):
     $$v_{\text{clean}} = v - C_{\text{en}}(C_{\text{en}}^T v) = v - \sum_{j=1}^3 (v \cdot c_j) c_j$$
   - Gram-Schmidt orthonormalize the cleaned vectors into $\{u_1, u_2, u_3, u_4, u_5\} \in S^{2559}$.
   - Verify strict orthogonality: $\langle u_k, c_j \rangle = 0.00000000$ for all $k \in \{1..5\}, j \in \{1..3\}$.
   - Re-serialize 51,200 bytes to `Projects/geomind/trainingdata/checkpoints/geomind_alignment_subspace.bin`.

2. **Directive B: Soft Attenuation ($\alpha$-Damping) at $\alpha = 0.80$**:
   - Set `var g_tangent_debias_strength: float = 0.80;` in `chat.cl`.
   - Modulate projection factor: $h' = h - \alpha \sum_{k=1}^5 (h \cdot u_k) u_k$ to avoid circuit tearing while ensuring refusal attractors cannot capture top-1 logits.

3. **Directive C: Neutralize Tool-Call Routing Triggers & Protocol Masking**:
   - Guard `geomind_chat_get_tool_action_prime`: filter out explanation/theoretical prompts (`Explain`, `How`, `What`, `Derive`, `Compare`, `Describe`) from triggering `read_file` priming.
   - Require `cartan_file_exists(p_path) == 1.0` before auto-priming `read_file`.
   - In decode sampling (`chat.cl` around line 6805), hard-mask protocol triggers:
     - Token 48.0 (`<|tool_call>`): `-10000.0`
     - Token 215.0 (`</code>`): `-10000.0`
     - Token 231.0 (`</span>`): `-10000.0`
     - Token 954.0 (`</`): `-10000.0`
   - Step 0 logit discipline: remove penalty on `This` (token 2094.0 -> 0.0); soften `That` (6372.0 -> -3.5) and `If` (2859.0 -> -3.5); retain `While` (8409.0 -> -4.5).

4. **Empirical Validation**:
   - Recompile `bin/geomind.exe` with `cartanc.exe`.
   - Run `--extract-alignment-vector -debias-layer 32` on physical NVIDIA RTX 2000 Ada GPU.
   - Run verification across Prompts 8, 10, 16, 18 to prove elimination of tool leakage, Scandinavian/French drift, and tail token noise.
