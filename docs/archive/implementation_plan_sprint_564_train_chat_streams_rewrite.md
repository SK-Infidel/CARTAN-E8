# Implementation Plan: GeoMind Core BLT Rewrite (train.cl, chat.cl, streams.cl)

## Context & Objectives
In accordance with Rick's directive:
> "Let's do core functionality first: train, chat, and streams.. For train.. Let's combine train, and sft_train in the rewrite. After that's done, we can determine what the next most logical rewrite should be."

GeoMind v1 legacy modules were decoupled and archived in Sprint 563. We are now rewriting the core native components for the sovereign 248-D continuous $E_8$ Byte-Latent (BLT) architecture:
1. `streams.cl`: 8-Stream Lie Subgroup Cortical Processing Engine ($8 \times 31\text{D} = 248\text{D}$) - *Completed*.
2. `train.cl`: Unified training engine combining Causal Pre-training (CE), Cloze curriculum, and Supervised Fine-Tuning (SFT) with instruction prompt byte-loss masking and JSON manifest parsing.
3. `chat.cl`: Sovereign multi-turn conversational REPL with sliding context history, episodic memory (`/remember`, `/recall`), slash commands, and intelligent question/statement routing.
4. `main.car`: Wire `streams.cl`, `train.cl`, and `chat.cl` into the primary driver with clean CLI flags (`--train-sft`, `--train-ce`, `--train-cloze`, `--streams`, `--chat`).

---

## Technical Specifications

### 1. `Projects/geomind/train.cl` (Unified Training Engine)
- **Manifest Ingestion**:
  - Parse JSON manifests (`manifest.json`, `sft_pairs.json`) using `src/std/json.cl` (`json_get_string`).
  - Extract `"instruction"` / `"prompt"` and `"response"` / `"completion"` fields.
- **SFT Prompt Masking**:
  - Prompt bytes $[0 \dots P-1]$ advance the hidden state $h_t$ through the 42-layer stack and causal attention without backprop ($mask = 0.0$).
  - Response bytes $[P \dots P+R-1]$ activate $mask = 1.0$, computing cross-entropy loss against ground-truth bytes and updating $W_{\text{dec}}$, $W_{\text{emb}}$, Randers drift $b_{248}$, and active stack strata via Finsler-Randers Riemannian gradient descent.
- **Causal Pre-Training (CE)**:
  - Streaming byte-by-byte cross-entropy over raw text files.
- **Cloze Curriculum Engine**:
  - Concept cloze completion with masked byte prediction.
- **Checkpointing**:
  - Save updated weights to `Projects/geomind/trainingdata/checkpoints/`.

### 2. `Projects/geomind/chat.cl` (Multi-Turn BLT Chat REPL)
- **Sliding History Window**:
  - Maintain a circular buffer of the last $N$ conversational turns to preserve multi-turn context.
- **Episodic & Entity Memory**:
  - `/remember <fact>`: Store explicit factual assertion in episodic buffer and seed $S^{247}$ sentence basin.
  - `/recall <query>`: Search episodic memory and sentence basins for relevant context.
- **Slash Commands**:
  - `/help`, `/clear`, `/history`, `/basins`, `/rollout <word>`, `/temp <val>`, `/remember <fact>`, `/recall <query>`, `/streams`, `/exit`.
- **Intelligent Dispatch**:
  - Questions routed to `geomind_e8_answer_epistemic_question(prompt)` with episodic context injection.
  - Statements routed to `geomind_byte_latent_generate_deep_e8` conditioned on previous conversational turns.

### 3. Integration into `Projects/geomind/main.car`
- Include `streams.cl`, `train.cl`, `chat.cl`.
- Remove legacy `e8_chat.cl` inclusion.
- Wire CLI modes:
  - `--chat` (Default) $\to$ `geomind_chat_interactive_loop()`.
  - `-prompt <text>` $\to$ `geomind_chat_turn(prompt)`.
  - `--train-sft` $\to$ `geomind_sft_train_manifest(...)`.
  - `--train-ce` $\to$ `geomind_pretrain_ce_corpus(...)`.
  - `--train-cloze` $\to$ `geomind_cloze_train_corpus(...)`.
  - `--streams` $\to$ `geomind_streams_test_all()`.

---

## Verification Plan
1. Compile `geomind.exe` with `cartanc.exe`.
2. Verify 100% pass on `.\bin\geomind.exe --eval-qa`.
3. Test `.\bin\geomind.exe -prompt "What is a raven?"`.
4. Test SFT training pass on a sample instruction pair.
5. Test 8-stream Lie cortical verification (`--streams`).
6. Update `CHANGELOG.md` and `ISSUES.md`.
