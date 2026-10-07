# Sprint 552 Implementation Plan: Sovereign Ultra-Throughput Inference Engine

**Sprint**: 552  
**Epic**: Breaking the Memory Wall & Hierarchical Speculative Decoding  
**Lead Architect**: Rick  
**Pair Programmer**: Antigravity  
**Target Date**: 2026-10-06  

---

## 1. Objectives & Architectural Blueprint

Build an ultra-throughput, zero-degradation inference engine for GeoMind 4B by eliminating memory bandwidth bottlenecks, activating dense active-vocabulary indexing, enabling Sasaki MoE layer bypass, and implementing a 3-tier hybrid speculative drafting architecture.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        USER INPUT PROMPT                               │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Tier 0: Continuous Hopfield Memory Associative Recall (< 0.1 ms)       │
│ - Energy resonance R >= 0.85: Emit 3-5 candidate token burst           │
│ - Zero forward-pass compute cost on facts, user bio, & boilerplate     │
└───────────────────┬───────────────────────────────┬────────────────────┘
                    │ (Hit: Candidates Ready)       │ (Cold Miss: R < 0.85)
                    │                               ▼
                    │    ┌───────────────────────────────────────────────┐
                    │    │ Tier 1: 4-Layer Scout Sub-Manifold (2-3 ms)   │
                    │    │ - Layers 0, 1, 2 + Anchor 41 (~250 MB INT4)   │
                    │    │ - Dedicated 4-layer Scout KV Cache Arena      │
                    │    │ - Active Vocab Dense Indexing (~26k tokens)   │
                    │    │ - Drafts 3-5 candidate tokens autoregressively│
                    │    └──────────────────────┬────────────────────────┘
                    │                           │
                    ▼                           ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Tier 2: Batched Parallel Verification Kernel (4B Ground Truth)         │
│ - Single parallel GEMM pass over N=4..5 candidate tokens               │
│ - Active Vocab Dense Indexing cuts LM Head from 52 ms -> 11 ms         │
│ - Sasaki MoE Fast Path: skips layers 25-40 on confident tokens         │
│ - Rejection sampling + GQA KV cache rollback: Zero degradation         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Work Breakdown Structure (Single Cohesive Sprint)

### Pillar 1: Dense Active-Vocabulary Indexing (LM Head Acceleration)
- **Problem**: Current LM head scans 262,144 tokens in 8 threads and tests `mask != 0`, wasting memory bus cycles on 236,000 inactive tokens.
- **Solution**:
  1. Build compact active-vocabulary index array `g_active_script_indices` (~26,000 `uint32` token IDs) in [`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl) and [`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl).
  2. Implement `cartan_trans_pool_dispatch_lm_head_indexed`: 8 threads iterate directly over `26,000 / 8 = 3,250` valid indices.
  3. Pre-fill unselected logits to `-10000.0`.
  4. Expected speedup: $52\text{ ms} \to 11\text{ ms}$ ($4.7\times$).

### Pillar 2: Sasaki Brainstem MoE Fast-Path Layer Bypass
- **Problem**: Decoding unconditionally evaluates layers 0..24, and layers 25..40 only exit on thermodynamic delta. Intermediate layers consume ~60% of decode latency on routine tokens.
- **Solution**:
  1. In `geomind_execute_manifold_decode_step` ([`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl)), inspect Sasaki router score $w^*$ on $(h_{24}, \dot{h}_{24})$.
  2. When $w^* \ge 0.35$ (high-confidence stream stability), trigger Fast-Path: skip layers 25..40 and jump directly to Anchor Layer 41.
  3. Enforce Hard Invariants: Layers 0..23 always execute to maintain GQA KV cache integrity; Anchor Layer 41 always executes for PLE and global readout.
  4. Expected speedup: Skips 16 layers on ~70% of conversational tokens.

### Pillar 3: 4-Layer Scout Sub-Manifold & Decoupled Scout KV Cache
- **Problem**: Speculative decoding without a scout relies 100% on Hopfield hits.
- **Solution**:
  1. Define 4-layer scout execution path using Layers 0, 1, 2 + Anchor Layer 41 from existing weights (zero extra downloads, shared 2,560-D embedding and tokenizer).
  2. Allocate isolated 4-layer Scout KV cache arena (`g_scout_kv_cache`) so unverified candidate tokens never corrupt the 4B model's GQA KV cache.
  3. Wire Tier 1 scout drafting when Tier 0 Hopfield resonance is below threshold ($R < 0.85$).

### Pillar 4: Batched Parallel Verification & KV Rollback
- **Problem**: Current speculative verification verifies candidates sequentially one token at a time.
- **Solution**:
  1. In [`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl), feed all candidate tokens $t_1, \dots, t_K$ as a batch ($N=K$) into a single forward pass.
  2. Perform parallel rejection sampling against candidate probabilities.
  3. On first mismatch at index $j < K$, accept tokens $1 \dots j$ and roll back KV cache for indices $j+1 \dots K$.
  4. Cache the ground-truth token sampled at index $j$ as pre-computed anchor for the next step.

### Pillar 5: StreamingLLM Attention Sinks & Worker Thread Spin-Loops
- **Problem**: Context expansion causes $O(N)$ attention slowdowns on long sessions, and `Sleep(10.0)` in standby creates 15.6 ms Windows timer jitter.
- **Solution**:
  1. Pin initial 4 tokens ($t \in [0, 3]$) as permanent attention sinks in [`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl) alongside a 256-token local rolling window.
  2. Replace thread worker `Sleep(10.0)` in `cartan_trans_pool_worker_main` with atomic backoff spin-loops (`SwitchToThread()`) to eliminate Windows OS timer quantization.

---

## 3. Implementation Phasing & Dependencies

All 5 pillars integrate cohesively within Sprint 552:
1. **Core Kernel Upgrades**: Active Vocab Index Array + Worker Thread Spin-Wait ([`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl)).
2. **Decode Pipeline Upgrades**: Sasaki Fast-Path Layer Bypass + Batched Verification ([`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl)).
3. **Scout Model Sub-Manifold**: 4-Layer Scout + Scout KV Arena ([`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl)).
4. **Attention Sinks**: StreamingLLM sink preservation ([`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl)).
5. **Compilation & Empirical Validation**: Native `cartanc.exe` build, regression suite, and throughput benchmarks.

---

## 4. Definition of Done (DoD)
- [ ] Clean compilation with `cartanc.exe build Projects/geomind/main.car -o bin/geomind.exe`.
- [ ] Zero regression test failures (`tools/run_affected_tests.ps1`).
- [ ] Empirically verified token decode throughput with real inference prompts.
- [ ] Ground-truth output distribution remains 100% identical to unaccelerated 4B model.
- [ ] `CHANGELOG.md`, `Projects/geomind/CHANGELOG.md`, and `Projects/geomind/ISSUES.md` updated.
- [ ] Sprint walkthrough archived to `docs/archive/`.
