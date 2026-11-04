# Sprint 549 Walkthrough: GeoMind Multi-Turn Chat Stability, UTF-8 Console Initialization & Sampling Fixes

## Root Causes Addressed
1. **Windows Console UTF-8 Mojibake (`[ISSUE-409]`)**:
   - Declared `SetConsoleOutputCP` and `SetConsoleCP` (`dllimport i32 (i32)`) and invoked `SetConsoleOutputCP(65001)` and `SetConsoleCP(65001)` inside `@cartan_crt_init` in [`src/cartanc/llvm_codegen.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/llvm_codegen.car#L1172-L1177).
2. **Telegraphic Grammar & Function-Word Suppression (`[ISSUE-409]`, `[ISSUE-424]`)**:
   - Removed the `- 0.35 * (6.0 - ic)` Zipfian Information Content (IC) penalty on common English function words (`ic < 6.0`) in [`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L1983) and [`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L216), and neutralized `geomind_apply_stream_gated_logit_bias`.
   - Updated [`geomind_ensure_subword_spacing`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L246-L261) so `"ly"`, `"s"`, and `"ed"` suffixes attach cleanly to `-ing` words (`"fascinatingly"` instead of `"fascinating ly"`).
3. **Out-of-Context Veterinary/Biology Priming (`[ISSUE-424]`)**:
   - Removed `"biology, veterinary care"` from [`geomind_chat_build_cognitive_preamble_for_prompt`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L3267-L3280) so the 96-token attention sink stays domain-neutral.
4. **Multi-Turn Token-Salad Collapse (`[ISSUE-409]`, `[ISSUE-424]`)**:
   - Expanded `g_attention_window_size` from `256.0` to `2048.0` in [`src/std/transformer.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/transformer.cl#L121).
   - Replaced the cumulative additive repetition penalty (`-5.75` to `-12.0` + `-0.75 * occ_count`) in [`cartan_apply_repetition_penalty`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L384-L454) with a deduplicated 64-token generated-window multiplicative penalty (`1.18`) + bounded frequency penalty (`0.20 * (occ_count - 1)`, max `1.20`), exempting `<turn|>` (`106.0`), newlines (`108.0`), and sentence punctuation.
   - Added descending logit sort, `top_p = 0.85` nucleus truncation, and `min_p = 0.08` relative probability cutoff in [`cartan_tokenizer_sample_topp_topk`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/tokenizer.cl#L334-L398).
   - Added progressive sentence-boundary `<turn|>` (`106.0`) wrap-up boost after 220 tokens and `geomind_is_degenerate_symbol_token` loop guard in [`Projects/geomind/chat.cl`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L7930-L7970).

## Empirical Verification (`task-553`)
- Rebuilt `bin/cartanc.exe` and `Projects/geomind/geomind.exe` (`bin/geomind.exe`).
- Executed a live two-turn test on Rick's exact prompts:
  - **Turn 1** (`"I'm curious about the state of modern AI. It seems things are progressing very rapidly."`): Generated `204.0` tokens (`4.0 tok/s`, Context Horizon: `339`), clean UTF-8 em-dashes (`—`), natural English prose, and clean `<turn|>` termination.
  - **Turn 2** (`"I'm curious about what characteristics of a new modern LLM would be considered an industry disrupter."`): Generated `516.0` tokens (`2.6 tok/s`, Context Horizon: `886`), clean 4-part architectural analysis (Continuous Context and State Retention, Verifiable Reasoning and Epistemic Grounding, Adaptive Compute and Efficiency, Native Tool and System Integration), zero veterinary/animal hallucinations, zero spliced subwords, and zero token-salad collapse.
