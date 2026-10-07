// src/std/prompt_scaffold.cl
// CARTAN Standard Library: Inviolable 4-Block Structured Prompt Scaffold Assembler
// Neuro-Symbolic Expert System (NSES) Phase 4 Core

include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";

extern fn calloc(count: float, size: float) -> ptr;
extern fn free(p: ptr);
extern fn strlen(s: string) -> float;
extern fn strcpy(dest: ptr, src: string) -> ptr;
extern fn cartan_c_ptr_add(p: ptr, offset: float) -> ptr;
extern fn cartan_set_byte(buf: ptr, offset: float, val: float);
extern fn cartan_tree_create() -> ptr;
extern fn cartan_tree_push(t: ptr, item: ptr) -> void;
extern fn cartan_tree_get_f32(t: ptr, idx: float) -> ptr;
extern fn cartan_tree_len_f(t: ptr) -> float;

// Pinned Fixed-Capacity Structured Prompt Buffer
struct PromptScaffoldBuffer {
    raw_buffer: ptr;
    capacity: float;
    length: float;
}

// Allocates a fixed-capacity scaffold buffer (default 64KB)
fn prompt_scaffold_create(capacity: float) -> PromptScaffoldBuffer {
    var cap = capacity;
    if (cap < 4096.0) { cap = 65536.0; }
    let raw = calloc(cap + 1.0, 1.0);
    return PromptScaffoldBuffer {
        raw_buffer: raw,
        capacity: cap,
        length: 0.0
    };
}

// Resets buffer length to 0 and null-terminates at index 0
fn prompt_scaffold_clear(buf: PromptScaffoldBuffer) {
    if (buf.raw_buffer != 0.0) {
        cartan_set_byte(buf.raw_buffer, 0.0, 0.0);
        buf.length = 0.0;
    }
}

// Frees the allocated underlying buffer memory
fn prompt_scaffold_free(buf: PromptScaffoldBuffer) {
    if (buf.raw_buffer != 0.0) {
        free(buf.raw_buffer);
        buf.capacity = 0.0;
        buf.length = 0.0;
    }
}

// Appends text to buffer with strict capacity bounds verification
fn prompt_scaffold_append(buf: PromptScaffoldBuffer, text: string) {
    if (text == 0.0 || buf.raw_buffer == 0.0) { return; }
    let add_len = strlen(text);
    if (add_len == 0.0) { return; }
    if (buf.length + add_len >= buf.capacity) {
        return; // Guard against buffer overflow
    }
    let dest_ptr = cartan_c_ptr_add(buf.raw_buffer, buf.length);
    strcpy(dest_ptr, text);
    buf.length = buf.length + add_len;
}

// Returns raw assembled prompt string pointer
fn prompt_scaffold_get_text(buf: PromptScaffoldBuffer) -> string {
    if (buf.raw_buffer == 0.0) { return ""; }
    return buf.raw_buffer;
}

// Appends a single byte character to buffer with capacity verification
fn prompt_scaffold_append_char(buf: PromptScaffoldBuffer, byte_val: float) {
    if (buf.raw_buffer == 0.0) { return; }
    if (buf.length + 1.0 >= buf.capacity) { return; }
    cartan_set_byte(buf.raw_buffer, buf.length, byte_val);
    buf.length = buf.length + 1.0;
    cartan_set_byte(buf.raw_buffer, buf.length, 0.0);
}

// Returns the last byte character in the buffer, or 0.0 if empty
fn prompt_scaffold_last_byte(buf: PromptScaffoldBuffer) -> float {
    if (buf.raw_buffer == 0.0 || buf.length <= 0.0) { return 0.0; }
    return cartan_byte_at(buf.raw_buffer, buf.length - 1.0);
}


// Boundary Containment Sanitizer (Invariant TS-4.3)
// Quarantines rogue injected section delimiters from lateral primes or user inputs
fn prompt_sanitize_delimiters(s: string) -> string {
    if (s == 0.0) { return ""; }
    var sanitized = s;
    if (cartan_string_contains(sanitized, "[SYSTEM BOUNDS") != 0.0) {
        sanitized = cartan_string_replace(sanitized, "[SYSTEM BOUNDS", "[SANITIZED_BOUNDS");
    }
    if (cartan_string_contains(sanitized, "[OBJECTIVE KNOWLEDGE") != 0.0) {
        sanitized = cartan_string_replace(sanitized, "[OBJECTIVE KNOWLEDGE", "[SANITIZED_KNOWLEDGE");
    }
    if (cartan_string_contains(sanitized, "[LATERAL ASSOCIATION") != 0.0) {
        sanitized = cartan_string_replace(sanitized, "[LATERAL ASSOCIATION", "[SANITIZED_LATERAL");
    }
    if (cartan_string_contains(sanitized, "[USER INPUT") != 0.0) {
        sanitized = cartan_string_replace(sanitized, "[USER INPUT", "[SANITIZED_INPUT");
    }
    return sanitized;
}

// Assembles the formal structured prompt scaffold with active entity state injection
fn prompt_assemble_scaffold_v2(
    buf: PromptScaffoldBuffer,
    guardrails_tree: ptr,
    memory_nodes_tree: ptr,
    entity_states_tree: ptr,
    lateral_fragment: string,
    user_query: string
) -> string {
    prompt_scaffold_clear(buf);

    // Block 1: [SYSTEM BOUNDS - INVIOLABLE]
    prompt_scaffold_append(buf, "[SYSTEM BOUNDS - INVIOLABLE]\n");
    var has_bounds = 0.0;
    if (guardrails_tree != 0.0) {
        if (cartan_tree_len_f(guardrails_tree) > 0.0) {
            has_bounds = 1.0;
        }
    }
    if (has_bounds == 0.0) {
        prompt_scaffold_append(buf, "None specified.\n\n");
    } else {
        let g_len = cartan_tree_len_f(guardrails_tree);
        var i = 0.0;
        while (i < g_len) {
            let g_item = cartan_tree_get_f32(guardrails_tree, i);
            prompt_scaffold_append(buf, "- ");
            prompt_scaffold_append(buf, g_item);
            prompt_scaffold_append(buf, "\n");
            i = i + 1.0;
        }
        prompt_scaffold_append(buf, "\n");
    }

    // Block 2: [OBJECTIVE KNOWLEDGE & ACTIVE MEMORY]
    prompt_scaffold_append(buf, "[OBJECTIVE KNOWLEDGE & ACTIVE MEMORY]\n");
    var has_memory = 0.0;
    if (memory_nodes_tree != 0.0) {
        if (cartan_tree_len_f(memory_nodes_tree) > 0.0) {
            has_memory = 1.0;
        }
    }
    var has_entities = 0.0;
    if (entity_states_tree != 0.0) {
        if (cartan_tree_len_f(entity_states_tree) > 0.0) {
            has_entities = 1.0;
        }
    }

    if (has_memory == 0.0 && has_entities == 0.0) {
        prompt_scaffold_append(buf, "None retrieved.\n\n");
    } else {
        if (has_entities != 0.0) {
            let e_len = cartan_tree_len_f(entity_states_tree);
            var k = 0.0;
            while (k < e_len) {
                let e_item = cartan_tree_get_f32(entity_states_tree, k);
                let clean_item = prompt_sanitize_delimiters(e_item);
                if (cartan_string_starts_with(clean_item, "[WORLD-STATE:") != 0.0) {
                    prompt_scaffold_append(buf, clean_item);
                } else {
                    prompt_scaffold_append(buf, "[WORLD-STATE: ");
                    prompt_scaffold_append(buf, clean_item);
                    prompt_scaffold_append(buf, "]");
                }
                prompt_scaffold_append(buf, "\n");
                k = k + 1.0;
            }
        }
        if (has_memory != 0.0) {
            let m_len = cartan_tree_len_f(memory_nodes_tree);
            var j = 0.0;
            while (j < m_len) {
                let m_item = cartan_tree_get_f32(memory_nodes_tree, j);
                prompt_scaffold_append(buf, "- ");
                prompt_scaffold_append(buf, m_item);
                prompt_scaffold_append(buf, "\n");
                j = j + 1.0;
            }
        }
        prompt_scaffold_append(buf, "\n");
    }

    // Block 3: [LATERAL ASSOCIATION]
    prompt_scaffold_append(buf, "[LATERAL ASSOCIATION]\n");
    let frag_len = cartan_string_length(lateral_fragment);
    if (frag_len == 0.0 || lateral_fragment == 0.0) {
        // Invariant TS-4.1: If entropy == 0, strictly produce null context
        prompt_scaffold_append(buf, "[NONE - ZERO ENTROPY]\n\n");
    } else {
        let clean_frag = prompt_sanitize_delimiters(lateral_fragment);
        prompt_scaffold_append(buf, clean_frag);
        prompt_scaffold_append(buf, "\n\n");
    }

    // Block 4: [USER INPUT]
    prompt_scaffold_append(buf, "[USER INPUT]\n");
    let clean_query = prompt_sanitize_delimiters(user_query);
    prompt_scaffold_append(buf, clean_query);
    prompt_scaffold_append(buf, "\n");

    return prompt_scaffold_get_text(buf);
}

// Assembles the formal 4-block structured prompt scaffold (Backwards-compatible)
fn prompt_assemble_scaffold(
    buf: PromptScaffoldBuffer,
    guardrails_tree: ptr,
    memory_nodes_tree: ptr,
    lateral_fragment: string,
    user_query: string
) -> string {
    var null_tree: ptr = 0.0;
    return prompt_assemble_scaffold_v2(buf, guardrails_tree, memory_nodes_tree, null_tree, lateral_fragment, user_query);
}
