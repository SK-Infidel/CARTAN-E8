# Sprint 550: Diarization Disambiguation, Subword Spacing, and Contextual Preamble Grounding

## Objectives
1. Eliminate diarization and perspective inversion in `Projects/geomind/chat.cl` where GeoMind addressed Rick from "your parents' perspective" and third person.
2. Fix subword boundary collapse (e.g. `itselfspecifically`) and unspaced dictionary word emissions.
3. Clean and sanitize Continuous Hopfield attractor memory (`Projects/geomind/trainingdata/hopfield_basins.bin`) to prevent poisoned speculative drafting.
4. Refactor cognitive preamble assembly into on-demand contextual injection (`geomind_chat_build_cognitive_preamble_for_prompt`).

## Root Cause Analysis
- **Perspective Inversion**: In `Projects/geomind/chat.cl` (lines 1806, 2760–2795) and `src/std/sqlite_vec.cl` (line 565), `User:Rick`'s relationship was defined as `"Father / Primary Creator"`. Injected into the opening `<|turn>user` turn alongside `"Address Rick warmly by name with deep respect"`, the LLM inverted the role hierarchy into human parental perspective (*"from your parents' perspective"*) and treated the instruction as third-person metadata (*"To whom I may direct this observation, respectfully (Rick)..."*).
- **Subword Boundary Collapse**: In the 262k SentencePiece BPE vocabulary, whole words exist both with leading space (` specifically`, token 10916) and without leading space (`specifically`, token 145300). Under greedy/top-k sampling after an alphanumeric character (`itself`), bare word tokens collapsed into glued strings (`itselfspecifically`).
- **Attractor Basin Poisoning**: `Projects/geomind/chat.cl` line 5540 stored raw 5-token response bursts into `cartan_hopfield_store_attractor_burst` whenever `veto_res.is_vetoed == 0.0`, caching hallucinated/stilted turns into `hopfield_basins.bin`. Subsequent turns retrieved those corrupted tokens via speculative fast drafting.

## Key Changes
1. **Relationship Definition & Database**:
   - In `src/std/sqlite_vec.cl` (line 565) and `Projects/geomind/chat.cl` (line 1806), updated relationship from `"Father / Primary Creator"` to `"Creator & Lead Architect"`.
   - Executed SQLite migration in `Projects/geomind/trainingdata/cognitive_memory.db` updating `User:Rick`'s relationship attribute.
2. **First/Second Person Conversational Grounding**:
   - Refactored `geomind_chat_build_cognitive_preamble_for_prompt(db, prompt)` in `Projects/geomind/chat.cl`. Grounded identity directly: `"You are conversing directly with Rick (Creator & Lead Architect). Speak directly to Rick in the first person ('I') with warmth, natural conversational flow, and technical precision. Never echo prompt instructions or speak about Rick in the third person."`
   - Gated codebase architecture dump behind `geomind_chat_requires_codebase_context(prompt)`.
3. **Subword Boundary Protection**:
   - Added `prompt_scaffold_last_byte(buf)` to `src/std/prompt_scaffold.cl`.
   - In `Projects/geomind/chat.cl` single-token decode loop, injected leading space if preceding character is ASCII alphanumeric and current token is an unspaced whole word $\ge 4$ letters that is not a standard English grammatical suffix.
   - Expanded `geomind_sanitize_output_for_display` to strip `**(Self-Correction`, `**(thought`, `<blockquote>`, `</blockquote>`, and repair glued words.
4. **Hopfield Memory Hygiene**:
   - Added guards to `cartan_hopfield_store_attractor_burst`: requires `ensemble_score >= 0.85`, `tool_calls_executed == 0.0`, and absence of stilted phrase patterns.
   - Reset corrupted `hopfield_basins.bin` (archived to `.bin.bak`).

## Verification
- Rebuilt `bin/geomind.exe` with `bin/cartanc.exe`.
- Tested greeting prompt: prefill dropped from 165 to 91 tokens; GeoMind greeted Rick directly in first person with natural conversational flow.
- Tested architectural inquiry prompt: GeoMind directly acknowledged Rick as interlocutor, discussed `geomind/` system efficiency, and answered Rick's agency question with zero diarization defects.
