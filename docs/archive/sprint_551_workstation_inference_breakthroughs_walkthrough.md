# Sprint 551 Walkthrough: Workstation Inference Breakthroughs (`[ISSUE-427]`, `[ISSUE-428]`)

## 1. Architectural Root Causes Identified ("AH-HA!" Bottlenecks)
1. **1.71 GB/token FP32 LM Head Memory Bandwidth Wall**: Even with Latin/English active vocabulary pruning (`167,243` rows), scanning `167,243 x 2560` in FP32 streamed `1.71 GB` of DDR5 RAM per generated token (`~38 ms/tok`).
2. **Single-Threaded PLE Projection (`10752 x 2560`) & 1-Token Cache**: [`cartan_update_pli_cache_if_needed`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L316-L405) and [`cartan_precompute_prompt_pli`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L407-L500) computed the 110 MB `10752 x 2560` PLE projection GEMV sequentially on Thread 0 and only cached a single token ID (`s_cached_tok_id`), recomputing the 110 MB GEMV whenever a common English token repeated two steps later.
3. **Dead `q_heads == 8.0` Guard on Parallel GQA Attention (`op == 19.0`)**: GeoMind's 42-layer sovereign manifold uses `q_heads == 10.0` (`kv_heads == 2.0`, `head_dim == 256.0`) on its 35 sliding layers and `q_heads == 5.0` (`kv_heads == 1.0`, `head_dim == 512.0`) on its 7 global layers. The `if (q_heads == 8.0 && max_seq >= 4.0)` guard never triggered, forcing all GQA attention onto Thread 0.
4. **Premature `SwitchToThread()` Worker Yielding & Redundant Early-Exit Allocations**: Worker threads yielded via `SwitchToThread()` after `4096` spin iterations (`~15 µs`), sleeping during the ~180 µs WebGPU FFN dispatch and suffering kernel context-switch wake latency on the next CPU dispatch. Additionally, `g_early_exit_enabled` defaulted to `1.0` despite `0.0%` early-exit rate, allocating 11 redundant 2,560-float vectors per token on Layers 30..40.

## 2. Structural Optimizations Implemented
- **Two-Stage INT8 Full-Scan + Exact FP32 Top-Candidate Refinement (`op == 20.0`, `op == 21.0`)**:
  - Implemented [`cartan_trans_pool_quantize_emb_int8`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L4387-L4430) (`op == 21.0`) and cached `geomind_embeddings_full_262k_int8.bin` (`671 MB`) + `geomind_embeddings_full_262k_scales.bin` (`1 MB`) in [`geomind_load_e8_assets_if_needed`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L774-L796).
  - Implemented [`cartan_trans_pool_dispatch_lm_head_int8_indexed`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L4304-L4385) (`op == 20.0`), scanning all 167,243 active vocabulary rows in 8-thread AVX2 INT8 (`428 MB` streamed, 4x less bandwidth) and refining all top candidates (`dot >= local_max_dot - 6.0`) using exact FP32 rows (`cartan_simd_dot_f32`).
- **512-Slot Session PLE Token Cache & 8-Thread PLE Projection GEMV**:
  - Added a 512-slot Session PLE Token Cache (`s_pli_cache_tokens`, `s_pli_cache_data`, `22 MB`) and dispatched cache-miss PLE projections (`10752 x 2560`) across all 8 threads via `cartan_trans_pool_dispatch(2.0, 10752.0, 2560.0, ...)`.
- **8-Thread GQA Attention (`q_heads == 10.0` / `5.0`) & Active Spin-Wait Barrier**:
  - Generalized `op == 19.0` to `q_heads >= 4.0 && max_seq >= 4.0` with strided head assignment (`qh = start_row; while (qh < q_heads) { ... qh = qh + 8.0; }`) and `16 * max_seq` score scratch capacity.
  - Raised active worker spin threshold to `2000000.0` iterations and defaulted `g_early_exit_enabled = 0.0`.

## 3. Empirical Benchmark Results (NVIDIA RTX 2000 Ada Laptop GPU + 8-Core AVX2 CPU)

| Benchmark | Sprint 549 Baseline | Sprint 550 | Sprint 551 (Current) | Total Speedup vs Baseline | Output Fidelity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Short-Context (20 tokens)** | `5.3–5.8 tok/s` | `6.7–7.3 tok/s` | **`9.1–9.2 tok/s`** (`task-1173`) | **+58.6%** | **100% Bit-Identical** |
| **Multi-Turn Turn 1 (163 tokens)** | `4.0 tok/s` | `5.0–7.1 tok/s` | **`7.8–9.7 tok/s`** (`task-1179`) | **+95.0% sustained** | **100% Bit-Identical** |
| **Multi-Turn Turn 2 (435 tokens)** | `2.6 tok/s` | `4.9–5.6 tok/s` | **`7.1–7.5 tok/s`** (`task-1179`) | **+188.5% (`2.88x`)** | **100% Bit-Identical** |
