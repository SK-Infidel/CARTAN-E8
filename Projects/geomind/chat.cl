// Projects/geomind/chat.cl
// GeoMind Sovereign 248-D Continuous E8 Byte-Latent Interactive Chat Engine
// Multi-turn Conversational REPL with Sliding Context History, Episodic Entity Memory,
// Dynamic Lie Stream Cortical Filtering, and Epistemic Question-Answering Dispatch.

include "geometry.cl";
include "markov_tapestry.cl";
include "byte_latent.cl";
include "e8_relational.cl";
include "wordnet_taxonomy.cl";
include "e8_anchors.cl";
include "streams.cl";

extern fn printf(format: string) -> i32;
extern fn cartan_flush(v: float) -> float;
extern fn cartan_read_line() -> string;
extern fn cartan_string_length(s: string) -> float;
extern fn cartan_string_starts_with(s: string, pfx: string) -> float;
extern fn cartan_string_ends_with(s: string, sfx: string) -> float;
extern fn cartan_string_to_lower(s: string) -> string;
extern fn cartan_string_eq(s1: string, s2: string) -> float;
extern fn cartan_string_concat(s1: string, s2: string) -> string;
extern fn cartan_string_substring(s: string, start: float, end_idx: float) -> string;
extern fn cartan_float_to_string(v: float) -> string;
extern fn cartan_tree_create() -> ptr;
extern fn cartan_tree_push(t: ptr, item: ptr) -> void;
extern fn cartan_tree_get(t: ptr, idx: float) -> string;
extern fn cartan_vec_create() -> ptr;
extern fn cartan_vec_push_f32(v: ptr, val: float) -> void;
extern fn cartan_vec_get_f32(v: ptr, idx: float) -> float;
extern fn cartan_vec_set_f32(v: ptr, idx: float, val: float) -> void;
extern fn cartan_vec_len(v: ptr) -> float;
extern fn cartan_vec_free(v: ptr) -> void;
extern fn free(p: ptr) -> void;
extern fn atof(s: string) -> float;

// Conversational Sliding Window Context Buffer (Stores up to 8 turns)
var g_chat_history_prompts: ptr = 0.0;
var g_chat_history_replies: ptr = 0.0;
var g_chat_history_count: float = 0.0;
var g_chat_temp: float = 0.70;

// Episodic Entity Memory (Stores up to 64 explicit facts remembered during the session)
var g_chat_memory_facts: ptr = 0.0;
var g_chat_memory_count: float = 0.0;

fn geomind_chat_init_if_needed() {
    if (g_chat_history_prompts == 0.0) {
        g_chat_history_prompts = cartan_tree_create();
        g_chat_history_replies = cartan_tree_create();
    }
    if (g_chat_memory_facts == 0.0) {
        g_chat_memory_facts = cartan_tree_create();
    }
}

// Stores an explicit fact into active episodic memory and indexes it into S^{247} sentence basins
fn geomind_chat_remember_fact(fact: string) -> float {
    let f_len = cartan_string_length(fact);
    if (f_len == 0.0) { return 0.0; }
    geomind_chat_init_if_needed();

    // Push fact into memory tree
    cartan_tree_push(g_chat_memory_facts, fact);
    g_chat_memory_count = g_chat_memory_count + 1.0;

    // Index fact into S^{247} sentence basins
    geomind_e8_index_corpus_sentence_basins(fact, 0.0);

    printf("  [Episodic Memory] Stored (Fact #%.0f): \"%s\"\n", g_chat_memory_count, fact);
    printf("  [Manifold] Projected and crystallized into S^{247} sentence basins\n");
    cartan_flush(0.0);
    return 1.0;
}

// Recalls facts from episodic memory matching the query
fn geomind_chat_recall_facts(query: string) -> float {
    let q_len = cartan_string_length(query);
    if (q_len == 0.0) { return 0.0; }
    geomind_chat_init_if_needed();

    printf("  [Episodic Recall Query] Searching for: \"%s\"\n", query);
    var matches = 0.0;
    var i = 0.0;
    let low_q = cartan_string_to_lower(query);

    while (i < g_chat_memory_count) {
        let stored_fact = cartan_tree_get(g_chat_memory_facts, i);
        let low_f = cartan_string_to_lower(stored_fact);
        if (string_contains(low_f, low_q) == 1.0 || string_contains(low_q, low_f) == 1.0) {
            printf("    * Fact #%.0f: %s\n", i + 1.0, stored_fact);
            matches = matches + 1.0;
        }
        i = i + 1.0;
    }

    if (matches == 0.0) {
        printf("    No direct episodic memory match. Querying S^{247} sentence basins:\n");
        let ans = geomind_e8_answer_epistemic_question(query);
        printf("    * Manifold Epistemic Association: %s\n", ans);
    }
    cartan_flush(0.0);
    return matches;
}

// Determines if an incoming prompt represents an epistemic reasoning question
fn geomind_e8_is_question_prompt(prompt: string) -> float {
    let p_len = cartan_string_length(prompt);
    if (p_len == 0.0) { return 0.0; }
    if (cartan_string_ends_with(prompt, "?") == 1.0) { return 1.0; }
    let low = cartan_string_to_lower(prompt);
    if (cartan_string_starts_with(low, "what ") == 1.0 ||
        cartan_string_starts_with(low, "who ") == 1.0 ||
        cartan_string_starts_with(low, "where ") == 1.0 ||
        cartan_string_starts_with(low, "why ") == 1.0 ||
        cartan_string_starts_with(low, "how ") == 1.0 ||
        cartan_string_starts_with(low, "is ") == 1.0 ||
        cartan_string_starts_with(low, "can ") == 1.0 ||
        cartan_string_starts_with(low, "does ") == 1.0 ||
        cartan_string_starts_with(low, "do ") == 1.0 ||
        cartan_string_starts_with(low, "did ") == 1.0 ||
        cartan_string_starts_with(low, "which ") == 1.0) {
        return 1.0;
    }
    return 0.0;
}

// Adds a conversational turn to the sliding context window
fn geomind_chat_record_turn(prompt: string, reply: string) {
    geomind_chat_init_if_needed();
    cartan_tree_push(g_chat_history_prompts, prompt);
    cartan_tree_push(g_chat_history_replies, reply);
    g_chat_history_count = g_chat_history_count + 1.0;
}

// Displays the active conversation history
fn geomind_chat_show_history() {
    printf("================================================================================\n");
    printf("  CONVERSATION HISTORY (Active Turns: %.0f)\n", g_chat_history_count);
    printf("================================================================================\n");
    var i = 0.0;
    while (i < g_chat_history_count) {
        let p = cartan_tree_get(g_chat_history_prompts, i);
        let r = cartan_tree_get(g_chat_history_replies, i);
        printf("[Turn %.0f]\n", i + 1.0);
        printf("  User:    %s\n", p);
        printf("  GeoMind: %s\n\n", r);
        i = i + 1.0;
    }
    cartan_flush(0.0);
}

// Resets conversational history and episodic buffers
fn geomind_chat_clear_session() {
    geomind_chat_init_if_needed();
    g_chat_history_prompts = cartan_tree_create();
    g_chat_history_replies = cartan_tree_create();
    g_chat_history_count = 0.0;
    geomind_e8_episodic_refractory_reset();
    printf("[GeoMind] Session context and refractory memory reset.\n");
    cartan_flush(0.0);
}

// Executes a single conversational inference turn on the 248-D E8 manifold
fn geomind_chat_turn(prompt: string) -> string {
    if (cartan_string_length(prompt) == 0.0) { return ""; }
    geomind_chat_init_if_needed();

    // Check episodic memory first if prompt is a question
    if (geomind_e8_is_question_prompt(prompt) == 1.0) {
        let low_q = cartan_string_to_lower(prompt);
        var i = 0.0;
        while (i < g_chat_memory_count) {
            let fact = cartan_tree_get(g_chat_memory_facts, i);
            let low_f = cartan_string_to_lower(fact);
            if (string_contains(low_q, low_f) == 1.0 || string_contains(low_f, low_q) == 1.0) {
                geomind_chat_record_turn(prompt, fact);
                return fact;
            }
            i = i + 1.0;
        }

        // Dispatch to Epistemic Q&A engine
        let reply = geomind_e8_answer_epistemic_question(prompt);
        geomind_chat_record_turn(prompt, reply);
        return reply;
    }

    // Declarative or creative prompt: Autoregressive byte generation through 42-layer stack
    let gen_reply = geomind_byte_latent_generate_deep_e8(prompt, 42.0, 128.0);
    geomind_chat_record_turn(prompt, gen_reply);
    return gen_reply;
}

// Launches the native interactive 248-D E8 Chat REPL
fn geomind_chat_interactive_loop() -> float {
    geomind_wordnet_init_if_needed();
    geomind_e8_sent_basins_load_if_needed();
    geomind_markov_init_if_needed();
    let default_m = "Projects/geomind/trainingdata/checkpoints/geomind_e8_markov_tapestry.bin";
    if (cartan_file_exists(default_m) == 1.0) {
        geomind_markov_load_prior(default_m);
    }
    geomind_chat_init_if_needed();

    printf("================================================================================\n");
    printf("  GEOMIND E8 INTERACTIVE COGNITIVE AGENT (248-D Sovereign BLT)\n");
    printf("  Continuous Lie Manifold S^247 | 42-Layer Octonionic Geodesic Stack\n");
    printf("  Sentence Basins: %.0f loaded | Vocab Codebook: %.0f concepts\n", g_e8_sent_basin_count, g_e8_vocab_count);
    printf("================================================================================\n\n");
    printf("Commands: /help, /remember <fact>, /recall <query>, /history, /basins, /streams, /clear, /exit\n\n");
    cartan_flush(0.0);

    var running = 1.0;
    while (running == 1.0) {
        printf("User> ");
        cartan_flush(0.0);
        let input_line = cartan_read_line();
        let in_len = cartan_string_length(input_line);
        if (in_len == 0.0) {
            continue;
        }

        // Handle slash commands
        if (cartan_string_eq(input_line, "/exit") == 1.0 || cartan_string_eq(input_line, "/quit") == 1.0) {
            printf("[GeoMind] Session ended. Goodbye!\n");
            cartan_flush(0.0);
            running = 0.0;
            break;
        }
        if (cartan_string_eq(input_line, "/help") == 1.0) {
            printf("  Available Commands:\n");
            printf("    /help            Display this command list\n");
            printf("    /remember <fact> Store explicit factual statement into episodic memory\n");
            printf("    /recall <query>  Search episodic memory and sentence basins for matches\n");
            printf("    /history         Display conversation turn history\n");
            printf("    /basins          Display count of active S^{247} sentence basins\n");
            printf("    /rollout <word>  Execute 42-layer stratified geodesic rollout for concept word\n");
            printf("    /streams         Run 8-stream Lie cortical pass on active state\n");
            printf("    /clear           Reset conversation history and refractory memory buffers\n");
            printf("    /exit, /quit     Exit interactive REPL\n\n");
            cartan_flush(0.0);
            continue;
        }
        if (cartan_string_starts_with(input_line, "/remember ") == 1.0) {
            let fact = cartan_string_substring(input_line, 10.0, in_len);
            geomind_chat_remember_fact(fact);
            continue;
        }
        if (cartan_string_starts_with(input_line, "/recall ") == 1.0) {
            let query = cartan_string_substring(input_line, 8.0, in_len);
            geomind_chat_recall_facts(query);
            continue;
        }
        if (cartan_string_eq(input_line, "/history") == 1.0) {
            geomind_chat_show_history();
            continue;
        }
        if (cartan_string_eq(input_line, "/basins") == 1.0) {
            printf("  Active Sentence Basins: %.0f loaded on S^{247}\n", g_e8_sent_basin_count);
            printf("  Vocabulary Concepts:    %.0f registered in Hinton codebook\n\n", g_e8_vocab_count);
            cartan_flush(0.0);
            continue;
        }
        if (cartan_string_starts_with(input_line, "/rollout ") == 1.0) {
            let word = cartan_string_substring(input_line, 9.0, in_len);
            let trace = geomind_e8_deep_thought_rollout_42L(word);
            printf("  [42-Layer Stratified Rollout]: %s\n\n", trace);
            cartan_flush(0.0);
            continue;
        }
        if (cartan_string_eq(input_line, "/streams") == 1.0) {
            printf("  Executing 8-Stream Lie Subgroup Cortical Processing Verification:\n");
            geomind_streams_test_all();
            continue;
        }
        if (cartan_string_eq(input_line, "/clear") == 1.0) {
            geomind_chat_clear_session();
            continue;
        }

        // Process user conversational input
        let reply = geomind_chat_turn(input_line);
        printf("\nGeoMind> %s\n\n", reply);
        cartan_flush(0.0);
    }
    return 0.0;
}
