# Sprint 548 Task List: Autonomous Tool Domain & Online SFT

- [x] **Task 1: Comprehensive Keyword Intent Classifier**
  - [x] Implement grouped semantic matcher in `Projects/geomind/chat.cl` (`geomind_chat_requires_tool_definitions`).
  - [x] Add all categories: files (read/write/exists), dirs (list/explore), code (inspect/repo/git), compiler/build (cargo/cartanc), extensions, paths, terminal (powershell/cmd/exec), web (browse/url), screen (ocr), and explicit tools.
  - [x] Verify conversational prompts ("Hello", "Who am I") do NOT trigger tool mode.

- [x] **Task 2: NSES Domain 11 (TOOLS_AND_ACTIONS) Integration**
  - [x] Define Domain 11 in NSES routing when tool intent is active.
  - [x] Apply symbolic firewall penalties (-10000.0) on refusal tokens `3805.0` ('[]') and `236840.0` ('[').

- [x] **Task 3: Step 0 Generation Scaffolding (Teacher Forcing)**
  - [x] When tool intent is active and `step == 0`, prime the decode buffer and KV cache with `<tool_call:`.
  - [x] Autoregressively complete the tool call tag and attributes.
  - [x] Verify `geomind_parse_and_dispatch_tool_call` catches the call, executes it, and injects `<tool_response>`.

- [x] **Task 4: Autonomous Online SFT & Hebbian Learning Loop**
  - [x] Hook `geomind_chat_apply_correction(prompt, full_gen_text)` at turn completion when `tool_calls_executed > 0`.
  - [x] Execute `cartan_tensor_train_step` (cross-entropy gradient update) and `cartan_hebbian_step_token`.
  - [x] Add clear telemetry logging showing the loss and synaptic reinforcement.

- [x] **Task 5: Empirical Verification & Regression Testing**
  - [x] Run `Projects/geomind/Testing-scratch/test_jit_context_and_minimal_prefill.car` to verify all 5 gates pass.
  - [x] Compile `bin/geomind.exe` and test prompt: `"Would you like to take a look at your code now ?"`.
  - [x] Verify autonomous tool execution, `<tool_response>` assimilation, and answer generation.
  - [x] Update `CHANGELOG.md` and save walkthrough to `docs/archive/`.
