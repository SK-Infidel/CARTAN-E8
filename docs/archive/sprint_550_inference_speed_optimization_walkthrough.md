# Sprint 550 Walkthrough: Autoregressive Inference Speed Optimization (`[ISSUE-425]` & `[ISSUE-426]`)

## Summary of Optimizations
1. **`@cartan_simd_axpy_f32` AVX2 FMA Compiler Intrinsic ([`src/cartanc/core_runtime.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/core_runtime.car#L22), [`src/cartanc/llvm_codegen.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/llvm_codegen.car#L1202))**:
   - Added `alwaysinline` `<8 x float>` AVX2 vector fused multiply-add loop (`dst[i..i+7] += scale * src[i..i+7]`) for Value-cache attention accumulation.
2. **8-Thread GQA Causal Attention & 8-Thread PLE Gating ([`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl))**:
   - Parallelized Step 6 GQA Causal Attention (`op == 19.0`, `lines 2656-2753`, `4752-4916`) across all 8 worker threads (`1 head/thread`) with per-head score scratch buffers (`8 * g_kv_cache_max_seq`) and `@cartan_simd_axpy_f32` V-accumulation.
   - Parallelized Step 10 Per-Layer Embedding (PLE) Gating (`lines 4948-4998`, 55M MACs/token across 42 layers) across the 8-thread pool.
   - Partitioned the parallel clear range in [`cartan_trans_pool_dispatch_lm_head_indexed`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L4242-L4295) by `[active_indices[ti * chunk], active_indices[end_r])` so each thread clears and populates a strictly disjoint slice of `out_logits`.
3. **Inlined 64-Bit Vector Slot Indexing & Zero-Churn Decode Loop ([`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl), [`src/std/tokenizer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/tokenizer.cl), [`src/std/reasoning.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/reasoning.cl), [`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl))**:
   - Replaced out-of-line `cartan_vec_get_f32` / `cartan_vec_set_f32` calls in hot loops with direct `v_ptr[2.0 + idx]` indexing (~3.5M calls/token eliminated).
   - Updated [`geomind_execute_manifold_decode_step`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L5216-L5236) to run `cartan_manifold_layer_forward_native(cur_h, cur_h, ...)` in-place across all 42 layers, restricted the post-prefill reflective doubt scan to `step == 2.0`, and hoisted `geomind_is_tool_action_intent(prompt)` out of the token loop.

## Empirical Benchmark Results

| Benchmark Scenario | Pre-Sprint 550 | Post-Sprint 550 | Speedup |
| :--- | :--- | :--- | :--- |
| **Short Context (20 tokens, WebGPU Hybrid)** | `5.3 – 5.8 tok/s` (`task-665`) | **`6.7 – 7.3 tok/s`** (`task-805`/`task-851`) | **+26%** |
| **Short Context (20 tokens, CPU-Only)** | `4.9 – 5.0 tok/s` (`task-670`) | **`5.7 – 5.8 tok/s`** (`task-809`) | **+16%** |
| **2-Turn Interactive — Turn 1 (163–204 tokens)** | `4.0 – 5.4 tok/s` (`task-553`) | **`5.0 – 7.1 tok/s`** (`task-897`) | **+25% sustained** |
| **2-Turn Interactive — Turn 2 (212+ tokens, ~530 ctx)** | `2.6 – 2.9 tok/s` (`task-553`) | **`4.9 – 5.6 tok/s`** (`task-897`) | **+88% sustained (~1.9x)** |
