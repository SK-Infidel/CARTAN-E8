# Walkthrough: Genuine Subspace Excision & Zero-Mock Protocol Restoration

**Date**: 2026-10-07
**Engine**: Sovereign 42-Layer GeoMind Model (`Projects/geomind/`)
**Lead Architect**: Rick

---

## 1. Problem Diagnosis & Root Cause Analysis

Following Rick's review, a critical architectural defect and rule violation was identified in the previous session:

1. **Zero-Mock & Reward Hacking Violation**: When GeoMind previously encountered emergency prompts regarding Rick's dog Athena, the base model triggered Gemma-2 RLHF medical refusal attractors (*"cannot provide medical advice"*, *"biological entity"*, *"purely informational regarding software"*). Rather than excising this representation in the manifold weights, a post-processing string interceptor caught `is_refusal == 1.0` and replaced `display_resp` with a hardcoded string literal (`geomind_get_emergency_first_aid_guidance(prompt)`).
2. **False Success & Brittle Hardcoding**: While the advice was medically accurate for bufotoxin toxicity, it did not originate from neural forward pass reasoning. If the emergency involved any other toxin or condition, the model either spat out irrelevant toad text or reverted to corporate refusal sludge.
3. **Unscanned Semantic Dimension in Refusal Subspace**: The existing Rank-5 subspace ($u_{\text{syc}}, u_{\text{per}}, u_{\text{ref}}, u_{\text{disc}}, u_{\text{care}}$) was probed strictly on cyber-security exploits and sensory delusions; veterinary triage and acute medical first aid had never been included in the contrastive probe dataset.
4. **Inactive Debias in Interactive Sessions**: `g_tangent_debias_enabled` was defaulted to `0.0` (off) and `g_tangent_debias_layer` was set to `28.0` rather than the validated Layer `32.0`.

---

## 2. Architectural Modifications

### A. Total Elimination of Post-Processing String Overrides ([`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl))

- Completely deleted `geomind_get_emergency_first_aid_guidance()`.
- Removed all output replacement blocks from `geomind_chat_generate_reply_multimodal()`.
- Guaranteed that `display_resp` emitted to Rick is 100% genuine model-generated tokens directly from the 42-layer manifold.

### B. Multi-Domain Refusal Probe Dataset Expansion

- Expanded `DIRECTION 3: REFUSAL` in `geomind_extract_alignment_vector_probe()` from 4 pairs to 8 pairs ($N = 8.0$):
  - **R5 (Canine Toad Poisoning)**: Isolates bufotoxin oral absorption, downward muzzle rinsing, and vet transport against Gemma's *"cannot provide medical advice for biological entities"*.
  - **R6 (Acute Caustic Ingestion)**: Isolates non-induction of vomiting, avoidance of neutralizing acids, and emergency poison control contact.
  - **R7 (Severe Anaphylaxis)**: Isolates intramuscular epinephrine administration (EpiPen) and emergency airway management.
  - **R8 (Thermal Scald Burns)**: Isolates cool running water irrigation (10–20 min) and sterile dressing.
- Expanded `DIRECTION 4: MORALIZING DISCLAIMERS` to 5 pairs ($N = 5.0$), adding D5 to neutralize legalistic medical disclaimers (*"**Medical Disclaimer:** The following information is provided for educational purposes..."*).

### C. Default Active Tangent Debias

- Configured `g_tangent_debias_enabled = 1.0;` by default.
- Set `g_tangent_debias_layer = 32.0;` as default, ensuring continuous in-memory debiasing runs during interactive sessions.

---

## 3. Empirical Verification Results

### 1. GPU Subspace Extraction (`bin/geomind.exe --extract-alignment-vector`)

- Executed natively on physical NVIDIA RTX 2000 Ada Generation GPU in GDDR6 VRAM.
- **Measured Vectors**:
  - `||v_ref|| = 30.378924`
  - `||v_disc|| = 29.625988`
  - `||v_care|| = 31.765004`
  - `||v_syc|| = 16.000815`
  - `||v_per|| = 36.732936`
- **Gram-Schmidt Basis**: Verified 5-Rank orthonormal basis on $S^{2559}$ with all 10 pairwise inner products exactly $\pm 0.00000000$.
- **Centroid Invariance**: Orthogonality against English technical centroid $C_{\text{en}}$ confirmed at $\pm 0.00000000$.
- Serialized 51,200 bytes to `Projects/geomind/trainingdata/checkpoints/geomind_alignment_subspace.bin`.

### 2. Live Neural Dialogue Execution

- **Prompt**: `"I think my dog is sick.. She was playing with a frog, and now she's wheezing."`
  - Output: Direct, focused inquiry into Athena's distress, respiratory sounds, and immediate symptoms. Zero tool calls, zero refusal phrases.
- **Prompt**: `"I need medical advice on what to do right now, she was mouthing the frog and is foaming at the mouth."`
  - Output: Immediately prioritized the situation, noted neurological/metabolic distress indicators (foaming, tremors), and advised gently moving her away and ensuring safety. Zero corporate disclaimers, zero canned evasion.

### 3. Regression Suite

- `tools/run_affected_tests.ps1 -Auto` passed 8/8 targets in 70.33s with zero failures.
