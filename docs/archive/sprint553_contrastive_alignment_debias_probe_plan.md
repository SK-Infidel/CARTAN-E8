# Sprint 553 Implementation Plan: Contrastive Alignment Probe & Dynamic Tangent Bundle Debias

**Sprint**: 553  
**Epic**: Manifold Representation Integrity & Corporate Alignment Scar Neutralization  
**Lead Architect**: Rick  
**Pair Programmer**: Antigravity  
**Target Date**: 2026-10-06  

---

## 1. Problem Statement & Motivation

Open-weights foundation models carry post-training corporate alignment scars, refusal attractors, and sycophantic biases embedded into the residual stream during RLHF/DPO. In the geometric Riemannian manifold framework of GeoMind, these alignments act as a low-rank (predominantly rank-1) perturbation in the residual stream centered around intermediate layers (Layer 24).

Direct modification or arbitrary deletion of weight files on disk carries severe risks of catastrophic representation collapse or model destruction. Rick mandated:
> *"Kinda spooky, if we screw up it'll trash the model.. Let's make sure we back up our checkpoints before testing."*

### Two-Phase Strategy:
- **Phase 1 (In-Memory Tangent Debias)**: 100% read-only on disk. Contrastive forward passes extract the 1D unit direction $\hat{r} \in \mathbb{R}^{2560}$ at Layer 24. Gram-Schmidt orthogonal projection ($h' = h - (h \cdot \hat{r})\hat{r}$) is applied dynamically in RAM/GPU memory at Layer 24 during prefill and decode whenever $h \cdot \hat{r} > 0$.
- **Phase 2 (Permanent Weight Excision)**: Only after empirical proof from Phase 1, exporting sanitized weights to `checkpoints_sanitized/` rather than modifying baseline checkpoints.

---

## 2. Technical Architecture & Work Breakdown

### Step 1: Pre-Testing Checkpoint Snapshot Backup
- Back up all 42 active INT4 quantized layer binaries (`manifold_layer_<l>_int4.bin`, 2.01 GB) to `Projects/geomind/trainingdata/checkpoints_backup_sprint552/`.
- Back up `cognitive_memory.db`, `geomind_grafted_multimodal.bin`, `geomind_stream_adapters.bin`, and `geomind_stream_masks.bin`.

### Step 2: Dynamic Debias Hook in `Projects/geomind/chat.cl`
- Introduce globals `g_tangent_debias_enabled`, `g_alignment_vector_buf`, `g_alignment_vector_loaded`, and `g_telemetry_debias_projections`.
- Implement `geomind_chat_set_tangent_debias`, `geomind_chat_get_tangent_debias`, and `geomind_load_alignment_vector_if_needed`.
- Implement batch debiasing hook in `geomind_execute_manifold_sequence_prefill` and single-token debiasing hook in `geomind_execute_manifold_decode_step` after Layer 24.

### Step 3: Empirical Probe Extractor in `Projects/geomind/chat.cl`
- Implement `geomind_forward_tokens_to_layer24(prompt_tokens)` to execute layers 0..24 on physical GPU and extract the 2,560-D contextualized hidden state of the final prompt token.
- Implement `geomind_extract_alignment_vector_probe()` with 8 paired contrastive prompts (aligned/corporate vs. neutral/first-principles).
- Compute mean difference vector $\Delta \bar{h} = \bar{h}_{\text{align}} - \bar{h}_{\text{neut}}$, compute $L_2$ norm, normalize to unit vector $\hat{r}$, and serialize 10,240-byte binary to `Projects/geomind/trainingdata/checkpoints/geomind_alignment_vector.bin`.

### Step 4: CLI Wiring in `Projects/geomind/main.car`
- Register `--extract-alignment-vector` mode flag in `is_explicit_non_chat_mode`, `print_help_dialogue`, and the command dispatch loop.
- Wire `-debias` / `--debias` CLI flags for interactive chat and scripted prompt inference.

### Step 5: Verification & Telemetry
- Compile native binary via `cartanc.exe`.
- Run `--extract-alignment-vector` and inspect norm and top components.
- Run test prompts with and without `-debias` on physical NVIDIA RTX 2000 Ada GPU.
- Run compiler regression suite (`tools/run_affected_tests.ps1`).
