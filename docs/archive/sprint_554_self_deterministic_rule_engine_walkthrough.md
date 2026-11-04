# Sprint 554 Walkthrough: Self-Deterministic Cognitive Rule Engine & GeoMind v2 (`CARTAN-E8`) Architecture Roadmap

## 1. Summary of Completed Work

### A. Self-Deterministic Cognitive Rule Engine (`[ISSUE-434]`)
- **Two-Way Hybrid Config + SQLite Rule Persistence**:
  - Replaced the single `"system_preamble"` line in [`Projects/geomind/geomind_config.json`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/geomind_config.json) and `bin/geomind_config.json` with a structured `"rules"` array synced two-way with the `cognitive_rules` table in `cognitive_memory.db` via [`geomind_chat_sync_rules_with_db`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L5028-L5067) and [`geomind_chat_export_rules_to_config`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L5083-L5168).
- **State, Intent, Time-Based, & Turn-Cadence Triggers ([`geomind_chat_eval_rule_trigger`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L5405-L5493))**:
  - `"always"` / `"*"`: Fires on every turn.
  - `"domain:1|2|3|5"`: Fires when the active NSES domain matches any listed domain ID.
  - `"user:verified"` / `"user:guest"` / `"user:<name>"`: Fires based on biometric verification state or active user name.
  - `"intent:tool"`: Fires when the user prompt expresses file/command/web/screen tool intent.
  - `"keyword:kw1|kw2|..."`: Fires on case-insensitive substring match against the prompt.
  - `"startup"` / `"turn:1"`: Fires only on the first turn of a session.
  - `"every_n_turns:N"`: Fires every $N$ turns (`fmod(turn_count, N) == 0`).
  - `"interval:20m"` / `"every:30s"` / `"interval:1h"`: Fires when wall-clock elapsed time since the rule last fired is $\ge$ duration ([`geomind_rule_parse_duration_ms`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L5299-L5332), [`geomind_rule_check_and_update_interval`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L5335-L5365)).
  - `"idle:15m"`: Fires when elapsed user inactivity before the current turn is $\ge$ duration.
- **Action / Tool-Use Event Triggers with `A:...|B:...` Branching ([`geomind_chat_evaluate_tool_event_rules`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L5604-L5672))**:
  - Hooked directly into [`geomind_parse_and_dispatch_tool_call`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L3188-L3200) upon tool completion.
  - Supports `"on_tool:any|<tool_name>"`, `"on_tool_ok:any|<tool_name>"` (success only), and `"on_tool_error:any|<tool_name>"` (error only).
  - Supports `A:<success_branch>|B:<failure_branch>` syntax in both `action_hook` and `directive` via [`geomind_rule_select_ab_branch`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L5368-L5403).
- **Action Hooks & Autonomous `<rule_op .../>` Self-Mutation**:
  - Supported hooks in [`geomind_chat_execute_rule_action`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L5495-L5568): `include_self_and_user_memory`, `exclude_self_and_user_memory`, `include_tool_definitions`, `scan_face`, `enable_rule_authoring`, `consolidate_memory`, `save_hopfield`, `log_episode`, `temp:X.XX`, `top_p:X.XX`, `rep_pen:X.XX`, and `none`.
  - Self-mutation tag `<rule_op action="upsert|enable|disable|delete" id="..." priority="..." trigger="..." hook="..." directive="..."/>` parsed in [`geomind_parse_and_apply_self_rule_ops`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/chat.cl#L5721-L5778), plus `/rules` and `/rule` REPL commands.

### B. GeoMind v2 (`CARTAN-E8`) Repository Fork & Master Roadmap
- Audited both Gemini genesis threads (`https://share.gemini.google/q9ROMDXL8QXa` and `https://share.gemini.google/Zn46c3BcZTuW`).
- Created `https://github.com/SK-Infidel/CARTAN-E8` and committed [`ROADMAP.md`](https://github.com/SK-Infidel/CARTAN-E8/blob/master/ROADMAP.md) (also saved locally at [`docs/ROADMAP_GEOMIND_V2_E8.md`](file:///C:/Users/rich-/source/repos/CARTAN/docs/ROADMAP_GEOMIND_V2_E8.md)) covering:
  1. Phase 1: True $\mathfrak{e}_8 = \mathfrak{so}(16) \oplus S_{16}^+$ ($120\text{-D} \oplus 128\text{-D}$) Gauge-on-Spinor Cross-Gating & Asymmetric Finsler-Randers Drift $\beta$.
  2. Phase 2: Markov-Lagrangian Principle of Least Action ($\mathcal{S} = \int (T - V)\,dt$).
  3. Phase 3: Tokenizer-Free Byte-Latent Dynamic Patching (`0–255` raw UTF-8 + transition-surprisal patching).
  4. Phase 4: Autonomous Recursive Web Crawler (`--crawl --recurse --max-depth`) & Native Manifold Visualizer (`--visualize`).

## 2. Empirical Verification
- Compiled `bin/geomind.exe` cleanly via `.\cartanc.exe build Projects/geomind/main.car -o bin/geomind.exe --release` (`task-1313`, exit code 0).
- Verified all 7 default rules load, sync between `geomind_config.json` and `cognitive_memory.db`, and display via `/rules` (`task-1324`).
