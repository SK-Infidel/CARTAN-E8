# Sprint 552 Walkthrough: Sustained Multi-Turn Inference Speed, Zero-`tanh` Stage-1 LM Head, Fused QKV Dispatch, & KV-Group GQA Attention

## Summary of Root Causes & Fixes (`[ISSUE-429]`, `[ISSUE-430]`)

1. **2,048-Slot 2-Way Set-Associative Session PLE Cache ([`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L289-L515))**:
   - Upgraded `cartan_init_pli_session_cache`, `cartan_update_pli_cache_if_needed`, and `cartan_precompute_prompt_pli` from 512 direct-mapped slots to 2,048 2-way set-associative slots (`88 MB`, 1,024 sets $\times$ 2 ways).
   - Way 0 pins the first/core vocabulary token mapped to each set, while Way 1 caches newer dynamic tokens, preventing multi-turn conversations from evicting common English tokens and re-triggering the 110 MB `10752 x 2560` PLE projection GEMV.

2. **Zero-`tanh()` Stage 1 + Bounded 96-Candidate Stage 2 LM Head (`op == 20.0`) ([`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L2835-L2889))**:
   - Because $30 \tanh(x / 30)$ is strictly monotonic, Stage 1 now stores raw `dot_i8` directly in `out_logits[2.0 + r]`, eliminating **167,243 transcendental C runtime `tanh()` calls** per token.
   - Stage 2 refines at most `96` top candidates per thread (`raw_val >= local_max_dot - 1.50`) using exact FP32 dot products (`cartan_simd_dot_f32`) + exact `30.0 * tanh(...)`, and converts remaining tail tokens in-place via a 3-op rational Padé softcap (`30.0 * (u * (27.0 + u2) / (27.0 + 9.0 * u2))`).

3. **Fused Single-Barrier `W_q + W_k + W_v` INT4 GEMV (`op == 22.0`) ([`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L3539-L3680))**:
   - Added `cartan_trans_pool_dispatch_int4_qkv_gemv` (`op == 22.0`, storing `out_k` and `out_v` at disjoint pointer slots `16.0` and `17.0`) across all 24 KV-producing layers (`lines 4916-5018`), replacing 3 separate thread-pool barriers per layer with a single barrier (`48` fewer thread-pool barriers per token) while keeping `h_norm1` hot in L1 cache.

4. **KV-Group-Fused 2-Head GQA Causal Attention (`op == 19.0`) & Vectorized Prefill V-Accumulation ([`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L2608-L2762))**:
   - Fused pairs of Query heads sharing the same KV head (`(0,1)`, `(2,3)`, `(4)`, `(5,6)`, `(7,8)`, `(9)` for `q_heads == 10.0`; `(0,1)`, `(2,3)`, `(4)` for `q_heads == 5.0`) so each worker thread loads `k_ht` and `v_ht` from RAM once for both Query heads in a single loop over `t`.
   - Replaced scalar 4-way batched prefill V-accumulation loops with `cartan_simd_axpy_f32` (`lines 6181-6204`, `6722-6745`, `7268-7291`), and replaced `cartan_tensor_compute_lm_head_logits_full` in [`Projects/geomind/chat.cl:7918`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L7918) with the fast `cartan_tensor_compute_lm_head_logits`.

## Empirical Benchmark Results (`task-1381`)

| Benchmark Metric | Sprint 549 Baseline | Sprint 550 | Sprint 551 | **Sprint 552 (Current)** | Total Gain vs. Sprint 549 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Turn 1 Peak (`tok/s`)** | `4.0 tok/s` | `7.1 tok/s` | `9.7 tok/s` | **`11.9 tok/s`** | **+197.5% (`2.98x`)** |
| **Turn 1 Sustained (174 tokens)** | `4.0 tok/s` | `6.0 tok/s` | `7.8 tok/s` | **`10.2 tok/s`** | **+155.0% (`2.55x`)** |
| **Turn 2 Sustained (363+ tokens, 670+ ctx)** | `2.6 tok/s` | `4.9 tok/s` | `7.1–7.5 tok/s` | **`9.5–11.5 tok/s`** | **+265.4% (`3.65x`)** |
