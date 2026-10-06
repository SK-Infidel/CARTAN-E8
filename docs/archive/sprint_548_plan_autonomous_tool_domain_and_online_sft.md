# Sprint 548 Plan: Autonomous Tool Domain (Domain 11) & Continuous Online SFT

## Mission & Purpose
Empower GeoMind to autonomously recognize when host tools are required, execute them without manual slash commands, synthesize responses from genuine tool output, and immediately backpropagate successful tool interactions into the manifold weights via online teacher forcing and Hebbian plasticity.

---

## Architecture & Dependency Tree

```
┌────────────────────────────────────────────────────────────┐
│ User Prompt: "Would you like to take a look at your code?" │
└─────────────────────────────┬──────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────┐
│ Comprehensive Tool Intent Classifier                       │
│ (geomind_chat_requires_tool_definitions: Files, Code, Git,  │
│  Terminal, Web, Screen, Extensions, Paths)                 │
└─────────────────────────────┬──────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────┐
│ Neuro-Symbolic Expert System (NSES) Routing: Domain 11     │
│ - Domain 11: TOOLS_AND_ACTIONS                             │
│ - Veto Firewall: Penalty on refusal tokens ('[]', '[')     │
└─────────────────────────────┬──────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────┐
│ Step 0 Generation Scaffolding (Teacher Forcing)            │
│ - Prime KV Cache & Buffer with "<tool_call:"               │
│ - Autoregressive Decode completes tool name & arguments    │
└─────────────────────────────┬──────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────┐
│ Reactive Tool Interceptor & Genuine Host Execution        │
│ (geomind_parse_and_dispatch_tool_call -> read_file, etc.)  │
│ - Ingest genuine <tool_response> into KV cache             │
│ - Model synthesizes natural response from tool output      │
└─────────────────────────────┬──────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────┐
│ Online SFT & Hebbian Backward Pass                         │
│ (geomind_chat_apply_correction -> cartan_tensor_train_step)│
│ - Gradient update on (Prompt -> Tool -> Output)            │
│ - Weights progressively learn native tool emission         │
└────────────────────────────────────────────────────────────┘
```

---

## Concrete Deliverables
1. **Comprehensive Keyword Taxonomy**:
   Expand `geomind_chat_requires_tool_definitions(prompt)` to cover all categories:
   - File read/inspect/view/open/contents
   - File write/save/modify/create/edit
   - File existence/search/find/locate
   - Directory/folder listing/contents/structure
   - Code inspection/review/codebase
   - Git operations (status, diff, log, branch, commit, repo, etc.)
   - Compiler/build/cargo/cartanc/tests
   - File extensions (.car, .cl, .c, .rs, .h, etc.)
   - Common project paths (main.car, chat.cl, src/, Projects/, etc.)
   - Terminal/shell/command execution
   - Web browsing & screen OCR reading
   - Direct tool requests
2. **Domain 11 in NSES**:
   - Route tool-active turns to Domain 11 (`TOOLS_AND_ACTIONS`).
   - Suppress refusal token `3805.0` (`'[]'`) and bracket `236840.0` (`'['`) via symbolic logit shaping.
3. **Teacher-Forced Generation Scaffolding**:
   - In `Projects/geomind/chat.cl`: If tool intent is detected at step 0, prime the scaffold with `<tool_call:`.
   - The model autoregressively completes the tool call.
   - The tool call executes and injects `<tool_response>` into the context.
4. **Autonomous Online SFT & Hebbian Plasticity**:
   - On successful tool execution, automatically invoke `geomind_chat_apply_correction(prompt, full_gen_text)`.
   - Executes real backpropagation via `cartan_tensor_train_step` and synaptic reinforcement via `cartan_hebbian_step_token`.
5. **Empirical Verification**:
   - Test `test_jit_context_and_minimal_prefill.car` (all gates passing).
   - Test interactive prompt `"Would you like to take a look at your code now ?"` and verify autonomous dispatch and answer synthesis.
