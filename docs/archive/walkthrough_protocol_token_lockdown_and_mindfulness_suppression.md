# Walkthrough: Protocol Control Token Lockdown & Mindfulness Attractor Suppression

**Date**: 2026-10-07  
**Author**: Rick & Antigravity  
**Target Binary**: `bin/geomind.exe`  

---

## 1. Problem Statement
During morning greeting and routine conversational interactions, two distinct issues emerged:
1. **Internal Protocol Bleed (`<tool|>` tag leak)**:
   - When asked about daily routine, token 47 (`<tool|>`) leaked directly into the output stream:
     `... or are there any new things to discuss? <tool|>... regarding your day ahead.`
   - Root cause: In `tools/build_gemma_vocab_scripts.py`, tokens 46–51 (`<|tool>`, `<tool|>`, `<|tool_call>`, etc.) were misclassified as Category 1 (Latin) because they contain the letters `tool`, rather than Category 255 (Control tokens).
   - Only token 48 was previously hard-masked during decoding, leaving tokens 46, 47, 49, 50, 51 unmasked.
2. **Unsolicited Mindfulness / Wellness Coaching Attractor**:
   - The model drifted into unsolicited meditation and lifestyle guidance:
     `There are many ways to make it better by taking a few moments before diving in. For example, focusing on the present moment right now makes you aware of details that might pass unnoticed amidst excitement...`
   - Root cause: Pretraining/RLHF corporate wellness tropes trained into base weights that reflexively pivot morning greetings into mindfulness/breathing counseling.

---

## 2. Technical Modifications

### A. Comprehensive Protocol Control Token Classification (`tools/build_gemma_vocab_scripts.py`)
- Classified all 6,255 special protocol and control tokens into **Category 255 (Control tokens)**:
  - Tokens `0..106` (`<pad>`, `<eos>`, `<bos>`, `<unk>`, `<mask>`, `[multimodal]`, `<unused0..39>`, `<|tool>`, `<tool|>`, `<|tool_call>`, `<tool_call|>`, `<|tool_response>`, `<tool_response|>`, `<|"|>`, `<unused40..84>`, `<|think|>`, `<unused85>`, `<|channel>`, `<channel|>`, `<unused86..88>`, `<|turn>`, `<turn|>`).
  - All `<unused...>` reserved tokens (tokens 261829..262143).
  - All tokens starting with `<|` or ending with `|>`, or starting with `<tool`, `<turn`, `<channel`.
- Re-exported `Projects/geomind/trainingdata/Checkpoints/geomind_vocab_scripts.bin`.
- Because Category 255 tokens have their mask bit cleared to `0.0` in `geomind_get_language_mask_for_script`, they are automatically hard-masked across both GPU and CPU execution.

### B. Display Output Filter & Decode Sampling Hard-Masking (`Projects/geomind/chat.cl`)
- Extended `geomind_clean_display_output` to strip `<tool|>`, `<|tool>`, `<|tool|>`, `<channel|>`, and `<|channel...>` delimiters if ever present in the buffer.
- In `geomind_chat_interactive_loop` decode sampling:
  - Hard-masked (to -10,000.0) tokens 46 (`<|tool>`), 47 (`<tool|>`), 48 (`<|tool_call>`), 49 (`<tool_call|>`), 50 (`<|tool_response>`), 51 (`<tool_response|>`), 52 (`<|"|>`), 98 (`<|think|>`), 100 (`<|channel>`), and 101 (`<channel|>`).
  - Added Step 0 logit discipline penalties to suppress tool/channel triggers at prompt onset.

### C. Unsolicited Mindfulness & Wellness Coaching Suppression (`Projects/geomind/chat.cl`)
- Added Section 6 to `geomind_apply_corporate_attractor_suppression` applying -7.0 logit penalty across mindfulness, meditation, breathing exercises, and wellness lecturing tokens:
  - ` mindful` (63318), ` mindfulness` (87476), ` Mindfulness` (228733)
  - ` meditation` (35207), ` Meditation` (103027), ` meditate` (125377)
  - ` grounding` (54814)
  - ` breathe` (38893), ` Breathe` (210250), ` breathing` (25638)
  - ` wellness` (35818), ` Wellness` (64542)

---

## 3. Empirical Verification
- Compiled native binary `bin/geomind.exe` with zero errors.
- Verified on physical RTX 2000 Ada GPU:
  - Protocol tokens completely silenced.
  - Zero mindfulness/wellness deflection on morning/routine prompts.
- Executed regression test runner (`tools/run_affected_tests.ps1`).
