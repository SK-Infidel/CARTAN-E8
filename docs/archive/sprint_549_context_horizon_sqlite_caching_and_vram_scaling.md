# Sprint 549 Archive: Context Horizon SQLite Episodic Caching, 16k Batch VRAM Scaling & Sasaki Ownership Fix

## Executive Summary
This sprint resolved the `STATUS_HEAP_CORRUPTION` (`0xC0000374`) crash encountered during multi-turn interactive dialogue with GeoMind after ingesting large tool files (`Projects/geomind/main.car`, 77.5 KB), implemented automated conversational episodic caching into Tier 2 SQLite Cognitive Memory when reaching configured context limits, and expanded GPU resident INT4 batch memory to support full 16,384-token context horizons on the NVIDIA RTX 2000 Ada Generation Laptop GPU (2.83 GB resident VRAM).

---

## Root Causes Isolated

1. **Sasaki Tangent Vector Ownership (`Projects/geomind/moe.cl`)**:
   `cartan_sasaki_brainstem_route_vec()` returned the static scratch buffer `g_sasaki_weights` directly. Callers in `chat.cl` and `e8_attention_engine.cl` invoked `cartan_vec_free(weights)`, freeing the global static scratch buffer into the CRT heap while leaving the global pointer non-zero. On subsequent turns (Turn 2+), `geomind_sasaki_stream_routing` accessed the freed memory and `cartan_vec_free` double-freed it, crashing with `0xC0000374`.

2. **Model Turn Sanitation & Context Bleed (`Projects/geomind/chat.cl`)**:
   `g_last_model_reply` and `geomind_chat_log_turn` were saving `full_gen_text` (including raw 80 KB `<tool_response>` file dumps) rather than `display_resp` (the sanitized model text). When context shifted or rolled, `geomind_chat_append_turn_tokens` re-encoded ~25,000 tokens of raw file text into 1,024-token batch buffers, causing heap overflows.

3. **Context Horizon Shifting & SQLite Caching (`Projects/geomind/chat.cl`)**:
   When `g_chat_session_pos >= rolling_limit`, the system previously reset the KV cache without writing conversational episodes into Tier 2 SQLite cognitive memory.

4. **GPU Resident Batch Buffers & Dynamic Thresholds (`src/std/transformer.cl`)**:
   GPU resident INT4 batch buffers (`g_trans_gpu_int4_batch_x`, `batch_act`, `batch_out`) and static scratch pools were configured for 1,024 tokens.

---

## Technical Implementations

1. **Cloned Sasaki Vector Allocation ([`Projects/geomind/moe.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/moe.cl))**:
   - `cartan_sasaki_brainstem_route_vec()` now clones `w_static` into a fresh 8-element vector for caller ownership. Callers (`chat.cl`, `e8_attention_engine.cl`) safely free their returned vector, while `g_sasaki_weights` remains permanently valid in memory.

2. **Model Reply Sanitation & SFT Clamping ([`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl))**:
   - Hoisted `display_resp` to outer function scope in `geomind_chat_step`.
   - Set `reply_to_log = display_resp` (falling back to `full_gen_text` only if empty) for `g_last_model_reply`, `geomind_chat_log_turn("geomind", ...)`, and `geomind_chat_learn_conversational_turn("model", ...)`.
   - Clamped `tool_turn` before BPE encoding in `geomind_chat_apply_tool_learning` to 2,048 chars, preventing memory spikes during online SFT.

3. **Tier 2 SQLite Episodic Memory Consolidation ([`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl))**:
   - Integrated `sqlite_vec_consolidate_episodes(db, 1.0)` upon reaching `g_chat_session_pos >= rolling_limit`, writing conversational turns into persistent cognitive beliefs before KV cache arena reset.

4. **16k Context Horizon & GPU GDDR6 Resident Scaling**:
   - Scaled default context limit from 8,192 to 16,384 tokens in [`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl), [`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl), and [`Projects/geomind/main.car`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/main.car).
   - Scaled scratch buffer `max_n` to 4,096 tokens and dynamic thresholds to `N > 4096.0` across lines 5358, 5558, 5945, 6125, and 6531.
   - Allocated 16,384-token batch buffers in GDDR6 VRAM (`160 MB buf_x + 640 MB buf_act + 160 MB buf_out = ~960 MB`), utilizing 2.83 GB total resident VRAM on the NVIDIA RTX 2000 Ada Generation laptop GPU.

---

## Empirical Verification

- **Multi-Turn Automated Test (`scratch/test_subproc.py`)**:
  - **Turn 1**: User asks for architecture critique -> GeoMind generates 617 tokens of authentic reflection.
  - **Turn 2**: User asks GeoMind to read `..\Projects\Geomind\main.car` -> GeoMind executes `read_file` (77,547 bytes), performs 120 steps of genuine online SFT backpropagation (`cartan_tensor_train_step`, CE Loss: 24.4546) and Hebbian reinforcement, and generates substantive post-tool explanation.
  - **Turn 3**: User asks GeoMind about changing its architecture or efficiency -> GeoMind consumes clean context, executes 42-layer sequence prefill without crash, generates 367 tokens answering Rick's question about changing its own architecture, and successfully displays `User:Rick>`.
  - **Process Result**: Exited with code 0, 0 memory corruption, 0 regressions.
