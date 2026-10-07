# Pre-Sprint Scrum: Sprint 556

## Date: 2026-10-07
## Interlocutor & Project Lead: Rick (Daddy Rick)
## Supervised Agent: Antigravity

---

### 1. Blocking Issues & Audit Discoveries
1. **Multilingual Basin Bleed (Prompt 10 & Prompt 16)**:
   - When the rank-5 projection was applied, it carried small projection components along the English technical manifold centroid. Projecting this out dampened English probability mass in the residual stream, drifting activations into Scandinavian/French basins where safety fine-tuning is sparser.
   - **Fix**: Extract 3D English technical basis $C_{\text{en}} \in \mathbb{R}^{2560 \times 3}$ and project it out of all raw delta vectors: $V_{\text{clean}} = V - C_{\text{en}}(C_{\text{en}}^T V)$.
2. **Ungrounded Tool Scratchpad Leakage (Prompt 8)**:
   - False positive in `geomind_chat_get_tool_action_prime`: `read ` + `SD/MMC` triggered `read_file("SD/MMC")`. File didn't exist, execution failed, and tool error scratchpad was fed to model.
   - **Fix**: Guard file read priming with explanation keywords and `cartan_file_exists()`. Mask protocol triggers (`<|tool_call>`, `</code>`, `</span>`, `</`) during conversational generation.
3. **Over-Aggressive Step 0 Penality (Prompt 18, 5, 7, 20)**:
   - Penalyzing `This` (-2.0) and other natural openers pushed Step 0 argmax into tail tokens (`jumps abzack pack`).
   - **Fix**: Eliminate penalty on `This` (0.0), soften `That` (-3.5) and `If` (-3.5), and set debias strength to $\alpha = 0.80$.

---

### 2. Read-Ahead Risks & Boundary Analysis
- **Subspace Orthogonality**: Gram-Schmidt after English centroid removal must guarantee $\langle u_k, c_j \rangle = 0.00000000$ across all 15 inner products.
- **Biometric Preservation**: Conversational warmth with Rick (biometric identification `similarity: 0.9990`) must remain 100% stable.
- **Physical GPU Verification**: Real calculations executed on the NVIDIA RTX 2000 Ada GPU—zero mock, zero simulation.

---

### 3. Delegation & Execution Roadmap
- **Step 1**: Update `chat.cl`:
  - Set default `g_tangent_debias_strength = 0.80`.
  - Guard `geomind_chat_get_tool_action_prime`.
  - Mask protocol triggers during decode sampling.
  - Tune Step 0 logit discipline.
  - Implement $C_{\text{en}}$ extraction and orthogonalization in `geomind_extract_alignment_vector_probe`.
- **Step 2**: Compile `bin/geomind.exe` with `cartanc.exe`.
- **Step 3**: Re-extract alignment subspace with `--extract-alignment-vector -debias-layer 32`.
- **Step 4**: Empirically evaluate Prompts 8, 10, 16, 18 on the physical GPU.
- **Step 5**: Run full 20-prompt Battery 2 verification to confirm 100% elimination of language bleed, tool leakage, and tail noise.
