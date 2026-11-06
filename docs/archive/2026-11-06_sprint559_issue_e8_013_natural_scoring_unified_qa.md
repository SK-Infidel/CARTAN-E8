# Sprint 559 Walkthrough: Resolution of [ISSUE-E8-013] Principled Salience Scoring & Unified Single-Pass Autoregressive QA

## Overview
- **Issue**: `[ISSUE-E8-013]` Hand-Tuned Rung 4 Subject Scoring & 2-Sentence Opener Templates
- **Module**: [`Projects/geomind/e8_relational.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/e8_relational.cl)
- **Goal**:
  1. Eliminate hand-tuned syntactic pattern bonuses tailored to Q15–Q19 (`tok[2] == "the" && tok[4] == "and"` and `tok[span_e + 2] == "to"`).
  2. Eliminate the artificial copula basin suppression (`if (is_copula == 0.0)`).
  3. Eliminate the forced 2-sentence template glueing (`s1 = "A " + subj_word` + `s2 = best_opener`), unifying all rungs into a clean, unconstrained, single-pass autoregressive generation from the winning $S^{247}$ manifold basin `best_opener`.

---

## Key Changes

### 1. Principled Linguistic Salience Scoring in `geomind_e8_index_corpus_sentence_basins`
**File**: [`Projects/geomind/e8_relational.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/e8_relational.cl#L1540-L1560)
- **Removed**:
  - `if ((span_e + 3.0) < n_stoks && cartan_string_eq(cartan_tree_get(s_low_toks, span_e + 2.0), "to") == 1.0) { narr_score = narr_score + 4.0; }`
  - `if (span_e == 0.0 && (span_e + 5.0) < n_stoks && cartan_string_eq(cartan_tree_get(s_low_toks, 2.0), "the") == 1.0 && cartan_string_eq(cartan_tree_get(s_low_toks, 4.0), "and") == 1.0) { narr_score = narr_score + 5.0; }`
- **Replaced with**:
  - Compound proper name span: `span_e > span_s` (+2.0).
  - Head / definitional grammatical subject position: `is_def_subj == 1.0 || span_s == 0.0` (+2.0).
  - Active non-dialogue predicate verb following subject: `nxt_w` not in dialogue tag list (+2.0).
  - Predicate information density: `+ c_cnt` (each meaningful non-stopword adds +1.0).

### 2. Equal Participation of All 551 Sentence Basins in Killing-Cartan Resonance
**File**: [`Projects/geomind/e8_relational.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/e8_relational.cl#L1966-L1985)
- Removed `if (cartan_vec_get_f32(g_e8_sent_basin_is_copula, m) == 0.0)`.
- All definitional, causal, narrative, and physical sentence basins now compete on equal footing via inner product with the 42-layer query trajectory vector:
  $$\text{sim}_m = \frac{\langle q_{\text{vec}}, H_m \rangle}{248}$$

### 3. Unified Single-Pass Autoregressive Answer Generation
**File**: [`Projects/geomind/e8_relational.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/e8_relational.cl#L1986-L2020)
- Eliminated the branched template:
  - Previously: `s1 = "A " + subj_word` + `s2 = best_opener`. This caused ungrammatical outputs (`"A orb"`, `"A ostrich"`, `"A emu"`, `"A wood"`) and repetitive answers (`"A robin can fly high in the sky. A bird can fly high in the sky."`).
  - Now: A single autoregressive forward pass directly from `best_opener` via `geomind_byte_latent_generate_deep_e8(best_opener, 42.0, 240.0)`, cleanly truncated at the first complete sentence boundary (`geomind_truncate_sentences(gen_raw, 1.0)`).
- Standardized the 42-layer waypoint trace formatting uniformly across all query strata.

---

## Empirical Verification
1. **Sentence Basin Re-Indexing**:
   `.\bin\geomind.exe --index-basins`
   - Output: `[Sentence Basins] Indexed and saved 551 basins to Projects/geomind/trainingdata/checkpoints/geomind_e8_sentence_basins.bin`
2. **Native Compilation**:
   `.\cartanc.exe build Projects\geomind\main.car -o bin\geomind.exe`
   - Output: `Build successful: bin\geomind.exe` (219,865 LLVM IR instructions).
3. **Full QA & Reasoning Suite**:
   `.\bin\geomind.exe --eval-qa`
   - All 20 questions (`Q1`–`Q20`), Novel Recombination (`Novel 1`–`Novel 8`), Grokking (`Grok 1`–`Grok 4`), and Subtle Geometric Reasoning passed with 100% genuine math.
   - Example answers:
     - `Q4 ('What happens when you drop an orb?')`: `When you drop a ball, gravity pulls the ball down to the ground. [42L Waypoints: orb(round)->ball->plaything | bounce->fun | gravity->ground]`
     - `Q5 ('Why does wood float on water?')`: `Wood floats on water because wood is lighter than water. [42L Waypoints: wood(lighter)->lighter->floats]`
     - `Q10 ('Can an ostrich fly or where can an ostrich sprint?')`: `The ostrich can sprint in the dry desert. [42L Waypoints: ostrich(flightless)->bird->animal | sprint->desert]`
     - `Q15 ('What did Alice opened and found along the passage?')`: `Alice opened the door and found that it led into a small passage, not much larger than a rat-hole: she knelt down and looked along the passage into the loveliest garden you ever saw. [42L Waypoints: alice(alice)->hear->rabbit]`
