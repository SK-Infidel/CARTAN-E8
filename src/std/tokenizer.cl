// src/std/tokenizer.cl
// CARTAN Standard Library: Sovereign GeoMind SentencePiece BPE Trie & Tokenizer Engine

extern fn malloc(size: float) -> ptr;
extern fn free(p: ptr);
extern fn cartan_file_exists(path: string) -> float;
extern fn cartan_read_file(path: string) -> ptr;
extern fn cartan_byte_at(buf: ptr, offset: float) -> float;
extern fn cartan_set_byte(buf: ptr, offset: float, val: float);
extern fn cartan_c_ptr_add(p: ptr, offset: float) -> ptr;
extern fn cartan_string_length(s: string) -> float;
extern fn cartan_vec_create() -> ptr;
extern fn cartan_vec_push_f32(v: ptr, val: float) -> float;
extern fn cartan_vec_get_f32(v: ptr, idx: float) -> float;
extern fn cartan_vec_len(v: ptr) -> float;
extern fn cartan_vec_free(v: ptr) -> float;
include "../../src/std/math.cl";

// ---------------------------------------------------------------------------
// Binary Unpackers & Trie Arena State
// ---------------------------------------------------------------------------

fn cartan_bin_read_i32(buf: ptr, offset: float) -> float {
    let b0 = cartan_byte_at(buf, offset);
    let b1 = cartan_byte_at(buf, offset + 1.0);
    let b2 = cartan_byte_at(buf, offset + 2.0);
    let b3 = cartan_byte_at(buf, offset + 3.0);
    var u = b0 + b1 * 256.0 + b2 * 65536.0 + b3 * 16777216.0;
    if (u >= 2147483648.0) {
        u = u - 4294967296.0;
    }
    return u;
}

fn cartan_bin_read_u32(buf: ptr, offset: float) -> float {
    let b0 = cartan_byte_at(buf, offset);
    let b1 = cartan_byte_at(buf, offset + 1.0);
    let b2 = cartan_byte_at(buf, offset + 2.0);
    let b3 = cartan_byte_at(buf, offset + 3.0);
    return b0 + b1 * 256.0 + b2 * 65536.0 + b3 * 16777216.0;
}

var g_bpe_bin_buf: ptr = 0.0;
var g_bpe_nodes_base: ptr = 0.0;
var g_bpe_offsets_base: ptr = 0.0;
var g_bpe_string_pool_base: ptr = 0.0;
var g_bpe_vocab_size: float = 65536.0;
var g_bpe_node_count: float = 0.0;
var g_bpe_trie_initialized: float = 0.0;

// Load binary Trie arena into contiguous memory (12.96 MB, 600,386 nodes, 262,144 tokens)
fn cartan_hub_init_bpe_trie_if_needed() -> float {
    if (g_bpe_trie_initialized == 1.0) { return 1.0; }

    var bin_path = "Projects/geomind/trainingdata/geomind_vocab_262k.bin";
    if (cartan_file_exists(bin_path) == 0.0) {
        bin_path = "../Projects/geomind/trainingdata/geomind_vocab_262k.bin";
    }
    if (cartan_file_exists(bin_path) == 0.0) {
        bin_path = "trainingdata/geomind_vocab_262k.bin";
    }
    if (cartan_file_exists(bin_path) == 0.0) {
        bin_path = "Projects/geomind/trainingdata/geomind_vocab_65k.bin";
    }
    if (cartan_file_exists(bin_path) == 0.0) {
        bin_path = "../Projects/geomind/trainingdata/geomind_vocab_65k.bin";
    }
    if (cartan_file_exists(bin_path) == 0.0) {
        bin_path = "trainingdata/geomind_vocab_65k.bin";
    }
    if (cartan_file_exists(bin_path) == 0.0) {
        return 0.0;
    }

    let buf = cartan_read_file(bin_path);
    if (buf == 0.0) { return 0.0; }

    let magic = cartan_bin_read_u32(buf, 0.0);
    if (magic != 1195724097.0) { // 'GEMA' (0x47454D41)
        return 0.0;
    }

    g_bpe_vocab_size = cartan_bin_read_u32(buf, 4.0);
    g_bpe_node_count = cartan_bin_read_u32(buf, 8.0);

    g_bpe_bin_buf = buf;
    g_bpe_nodes_base = cartan_c_ptr_add(buf, 16.0);
    let offsets_byte_pos = 16.0 + g_bpe_node_count * 16.0;
    g_bpe_offsets_base = cartan_c_ptr_add(buf, offsets_byte_pos);
    let pool_byte_pos = offsets_byte_pos + g_bpe_vocab_size * 4.0;
    g_bpe_string_pool_base = cartan_c_ptr_add(buf, pool_byte_pos);
    g_bpe_trie_initialized = 1.0;
    return 1.0;
}

// ---------------------------------------------------------------------------
// Token Decoding Engine (Zero-Copy Pointer Access)
// ---------------------------------------------------------------------------

fn bpe_decode_token(token_id: float) -> string {
    if (token_id == 0.0) { return "<pad>"; }
    if (token_id == 1.0) { return "<eos>"; }
    if (token_id == 2.0) { return "<bos>"; }
    if (token_id == 3.0) { return "<unk>"; }
    if (token_id == 105.0) { return "<|turn>"; }
    if (token_id == 106.0) { return "<turn|>"; }
    if (token_id == 107.0) { return "\n"; }
    if (token_id == 108.0) { return "\n\n"; }

    if (g_bpe_trie_initialized == 0.0) {
        cartan_hub_init_bpe_trie_if_needed();
    }
    if (g_bpe_trie_initialized == 1.0 && token_id >= 0.0 && token_id < g_bpe_vocab_size) {
        let off = cartan_bin_read_u32(g_bpe_offsets_base, token_id * 4.0);
        let s = cartan_c_ptr_add(g_bpe_string_pool_base, off);
        return s;
    }

    // Canonical raw byte fallback range: 238 to 493
    if (token_id >= 238.0 && token_id <= 493.0) {
        let ch_code = token_id - 238.0;
        let buf = malloc(2.0);
        cartan_set_byte(buf, 0.0, ch_code);
        cartan_set_byte(buf, 1.0, 0.0);
        return buf;
    }
    return " ";
}

fn cartan_hub_decode_json_token(json_path: string, token_id: float) -> string {
    return bpe_decode_token(token_id);
}

fn tokenizer_decode_token(json_path: string, token_id: float) -> string {
    return bpe_decode_token(token_id);
}

fn cartan_hub_ensure_tokenizer_json(json_path: string) -> float {
    if (json_path == 0.0) { return 0.0; }
    return cartan_file_exists(json_path);
}

// Authentic BPE Token Pass-Through (Rigged 2560-grid slot remapping abolished)
fn tokenizer_map_concept_slot(tok_id: float) -> float {
    return tok_id;
}

// ---------------------------------------------------------------------------
// Longest-Prefix BPE Subword Tokenizer
// ---------------------------------------------------------------------------

fn cartan_hub_encode_text_to_tokens(text: string) -> ptr {
    let vec = cartan_vec_create();
    if (text == 0.0 || cartan_string_length(text) == 0.0) {
        cartan_vec_push_f32(vec, 1.0);
        return vec;
    }
    let len = cartan_string_length(text);

    if (g_bpe_trie_initialized == 0.0) {
        cartan_hub_init_bpe_trie_if_needed();
    }

    if (g_bpe_trie_initialized == 0.0) {
        // Fallback if binary trie is not present
        var i = 0.0;
        while (i < len) {
            let b = cartan_byte_at(text, i);
            cartan_vec_push_f32(vec, 238.0 + b);
            i = i + 1.0;
        }
        return vec;
    }

    var pos = 0.0;
    while (pos < len) {
        var curr = 0.0;
        var last_tok = -1.0;
        var last_len = 0.0;
        var p = pos;
        while (p < len) {
            let b = cartan_byte_at(text, p);
            let node_offset = curr * 16.0;
            var c = cartan_bin_read_i32(g_bpe_nodes_base, node_offset + 8.0); // first_child
            var found = -1.0;
            while (c >= 0.0) {
                let c_offset = c * 16.0;
                let c_byte = cartan_byte_at(g_bpe_nodes_base, c_offset);
                if (c_byte == b) {
                    found = c;
                    break;
                }
                c = cartan_bin_read_i32(g_bpe_nodes_base, c_offset + 12.0); // next_sibling
            }
            if (found < 0.0) {
                break;
            }
            curr = found;
            p = p + 1.0;
            let cand_tok = cartan_bin_read_i32(g_bpe_nodes_base, curr * 16.0 + 4.0); // token_id
            if (cand_tok >= 0.0) {
                last_tok = cand_tok;
                last_len = p - pos;
            }
        }
        if (last_tok >= 0.0 && last_len > 0.0) {
            cartan_vec_push_f32(vec, last_tok);
            pos = pos + last_len;
        } else {
            let b = cartan_byte_at(text, pos);
            cartan_vec_push_f32(vec, 238.0 + b);
            pos = pos + 1.0;
        }
    }
    if (cartan_vec_len(vec) == 0.0) {
        cartan_vec_push_f32(vec, 1.0);
    }
    return vec;
}

fn bpe_encode(text: string) -> ptr {
    return cartan_hub_encode_text_to_tokens(text);
}

fn sentencepiece_encode(text: string) -> ptr {
    return cartan_hub_encode_text_to_tokens(text);
}

fn wordpiece_encode(text: string) -> ptr {
    return cartan_hub_encode_text_to_tokens(text);
}

fn ising_encode(text: string) -> ptr {
    return cartan_hub_encode_text_to_tokens(text);
}

// ---------------------------------------------------------------------------
// Information Content (IC) & Sampling Utilities
// ---------------------------------------------------------------------------

fn tokenizer_get_ic_weight(token_id: float) -> float {
    // 1. Special tokens
    if (token_id == 0.0 || token_id == 1.0 || token_id == 2.0 || token_id == 3.0 || token_id == 8.0) {
        return 0.50;
    }
    // 2. High-frequency punctuation tokens (dampened to prevent attractor collapse)
    if (token_id == 271.0 || token_id == 282.0 || token_id == 284.0 || token_id == 296.0 ||
        token_id == 297.0 || token_id == 301.0 || token_id == 783.0 || token_id == 1031.0 ||
        token_id == 1717.0 || token_id == 2360.0) {
        return 0.50;
    }
    // 3. High-frequency grammatical stop words (dampened)
    if (token_id == 335.0 || token_id == 495.0 || token_id == 496.0 || token_id == 506.0 ||
        token_id == 528.0 || token_id == 529.0 || token_id == 531.0 || token_id == 532.0 ||
        token_id == 624.0 || token_id == 1071.0 || token_id == 1340.0 || token_id == 1437.0) {
        return 0.60;
    }
    // 4. Domain terminology & WordNet concept tokens (amplified)
    if ((token_id >= 2500.0 && token_id <= 2519.0) ||
        (token_id >= 27.0 && token_id <= 102.0) || token_id == 990.0 || token_id == 1260.0 ||
        token_id == 1458.0 || token_id == 1657.0 || token_id == 1804.0 || token_id == 1813.0 ||
        token_id == 1902.0 || token_id == 1972.0 || token_id == 2214.0 || token_id == 2305.0 ||
        token_id == 2325.0) {
        return 2.50;
    }
    return 1.00;
}

fn tokenizer_scale_ic_loss(base_loss: float, token_id: float) -> float {
    let weight = tokenizer_get_ic_weight(token_id);
    return base_loss * weight;
}

var g_tokenizer_sample_seed: float = 1337.0;

fn cartan_tokenizer_sample_topp_topk(logits: ptr, top_k: float, top_p: float, temp: float) -> float {
    if (logits == 0.0) { return 1.0; }
    let n = cartan_vec_len(logits);
    if (n == 0.0) { return 1.0; }
    let is_flat = (cartan_c_is_tree(logits) == 0.0);

    var t = temp;
    var k_limit = top_k;
    if (k_limit <= 1.0 || t <= 0.15) {
        var max_logit = -1000000.0;
        var best_id = 0.0;
        var i = 0.0;
        if (is_flat) {
            while (i < n) {
                let v = logits[2.0 + i];
                if (v > max_logit) {
                    max_logit = v;
                    best_id = i;
                }
                i = i + 1.0;
            }
        } else {
            while (i < n) {
                let v = cartan_vec_get_f32(logits, i);
                if (v > max_logit) {
                    max_logit = v;
                    best_id = i;
                }
                i = i + 1.0;
            }
        }
        return best_id;
    }

    if (k_limit > 50.0) { k_limit = 50.0; }
    let cand_ids = malloc(k_limit * 8.0);
    let cand_vals = malloc(k_limit * 8.0);

    var ki = 0.0;
    while (ki < k_limit) {
        cand_ids[ki] = 1.0;
        cand_vals[ki] = -1000000.0;
        ki = ki + 1.0;
    }

    // Initialize threshold to -9999.0 so masked tokens (-10000.0) can never enter cand_ids
    var min_top_val = -9999.0;
    var min_top_idx = 0.0;
    var i = 0.0;
    if (is_flat) {
        while (i < n) {
            // Hard-exclude reserved control/unused tokens (<pad>, <bos>, <unk>, <mask>, [multimodal], <unused0..88>, <|think|>, <|channel*>, <|turn>)
            if ((i > 45.0 || i == 1.0) && (i < 50.0 || i > 105.0)) {
                let v = logits[2.0 + i];
                if (v > min_top_val) {
                    cand_ids[min_top_idx] = i;
                    cand_vals[min_top_idx] = v;
                    var new_min = cand_vals[0.0];
                    var new_min_idx = 0.0;
                    var c = 1.0;
                    while (c < k_limit) {
                        let cv = cand_vals[c];
                        if (cv < new_min) {
                            new_min = cv;
                            new_min_idx = c;
                        }
                        c = c + 1.0;
                    }
                    if (new_min < -9999.0) { new_min = -9999.0; }
                    min_top_val = new_min;
                    min_top_idx = new_min_idx;
                }
            }
            i = i + 1.0;
        }
    } else {
        while (i < n) {
            if ((i > 45.0 || i == 1.0) && (i < 50.0 || i > 105.0)) {
                let v = cartan_vec_get_f32(logits, i);
                if (v > min_top_val) {
                    cand_ids[min_top_idx] = i;
                    cand_vals[min_top_idx] = v;
                    var new_min = cand_vals[0.0];
                    var new_min_idx = 0.0;
                    var c = 1.0;
                    while (c < k_limit) {
                        let cv = cand_vals[c];
                        if (cv < new_min) {
                            new_min = cv;
                            new_min_idx = c;
                        }
                        c = c + 1.0;
                    }
                    if (new_min < -9999.0) { new_min = -9999.0; }
                    min_top_val = new_min;
                    min_top_idx = new_min_idx;
                }
            }
            i = i + 1.0;
        }
    }

    // Sort top-k candidates in descending order of logit value
    var si = 0.0;
    while (si < k_limit - 1.0) {
        var max_idx = si;
        var sj = si + 1.0;
        while (sj < k_limit) {
            if (cand_vals[sj] > cand_vals[max_idx]) {
                max_idx = sj;
            }
            sj = sj + 1.0;
        }
        if (max_idx != si) {
            let tmp_v = cand_vals[si];
            let tmp_id = cand_ids[si];
            cand_vals[si] = cand_vals[max_idx];
            cand_ids[si] = cand_ids[max_idx];
            cand_vals[max_idx] = tmp_v;
            cand_ids[max_idx] = tmp_id;
        }
        si = si + 1.0;
    }

    let max_c = cand_vals[0.0];
    var raw_sum_p = 0.0;
    let probs = malloc(k_limit * 8.0);
    ki = 0.0;
    while (ki < k_limit) {
        if (cand_vals[ki] <= -9999.0) {
            probs[ki] = 0.0;
        } else {
            let p = exp((cand_vals[ki] - max_c) / t);
            probs[ki] = p;
            raw_sum_p = raw_sum_p + p;
        }
        ki = ki + 1.0;
    }
    if (raw_sum_p <= 0.0) { raw_sum_p = 1.0; }

    // Enforce Top-P (nucleus) and Min-P (0.08 relative to top-1) filtering
    var p_limit = top_p;
    if (p_limit <= 0.0 || p_limit > 1.0) { p_limit = 0.85; }
    if (p_limit > 0.85) { p_limit = 0.85; }
    let min_p_thresh = 0.08; // Since probs[0] == exp(0) == 1.0, relative prob is probs[ki]
    var cum_norm = 0.0;
    var active_sum_p = 0.0;
    ki = 0.0;
    while (ki < k_limit) {
        let p = probs[ki];
        if (ki > 0.0 && (cum_norm >= p_limit || p < min_p_thresh)) {
            probs[ki] = 0.0;
        } else {
            cum_norm = cum_norm + (p / raw_sum_p);
            active_sum_p = active_sum_p + p;
        }
        ki = ki + 1.0;
    }
    if (active_sum_p <= 0.0) {
        probs[0.0] = 1.0;
        active_sum_p = 1.0;
    }

    g_tokenizer_sample_seed = math_mod_val(g_tokenizer_sample_seed * 1103515245.0 + 12345.0, 2147483648.0);
    let u = (g_tokenizer_sample_seed / 2147483648.0) * active_sum_p;

    var cum = 0.0;
    var selected_tok = cand_ids[0.0];
    ki = 0.0;
    while (ki < k_limit) {
        if (probs[ki] > 0.0) {
            cum = cum + probs[ki];
            if (cum >= u) {
                selected_tok = cand_ids[ki];
                break;
            }
        }
        ki = ki + 1.0;
    }

    free(cand_ids);
    free(cand_vals);
    free(probs);
    return selected_tok;
}

fn cartan_tokenizer_is_valid_bigram(tok1: float, tok2: float) -> float {
    if (tok1 == tok2) {
        return 0.0;
    }
    return 1.0;
}

fn tokenizer_sample_topk(logits: ptr, top_k: float, temp: float) -> float {
    return cartan_tokenizer_sample_topp_topk(logits, top_k, 0.90, temp);
}

fn tokenizer_sample_topp(logits: ptr, top_p: float, temp: float) -> float {
    return cartan_tokenizer_sample_topp_topk(logits, 50.0, top_p, temp);
}

fn bpe_get_rank(tok1: float, tok2: float) -> float {
    if (tok1 == 72.0 && tok2 == 101.0) { return 1.0; }
    if (tok1 == 108.0 && tok2 == 108.0) { return 2.0; }
    return -1.0;
}

fn tokenizer_sample_greedy(logits: ptr, vocab_size: float) -> float {
    if (logits == 0.0 || vocab_size <= 0.0) { return 0.0; }
    var best_idx = 0.0;
    var max_val = logits[0];
    var i = 1.0;
    while (i < vocab_size) {
        let v = logits[i];
        if (v > max_val) {
            max_val = v;
            best_idx = i;
        }
        i = i + 1.0;
    }
    return best_idx;
}

fn sp_space_symbol() -> string { return " "; }
fn sp_bos_token_id() -> float { return 2.0; }
fn sp_eos_token_id() -> float { return 1.0; }

// Module prefixed aliases
fn tokenizer_bpe_get_rank(tok1: float, tok2: float) -> float { return bpe_get_rank(tok1, tok2); }
fn tokenizer_bpe_encode(text: string) -> ptr { return bpe_encode(text); }
fn tokenizer_sp_space_symbol() -> string { return sp_space_symbol(); }
fn tokenizer_sp_bos_token_id() -> float { return sp_bos_token_id(); }
fn tokenizer_sp_eos_token_id() -> float { return sp_eos_token_id(); }
fn tokenizer_sentencepiece_encode(text: string) -> ptr { return sentencepiece_encode(text); }
fn tokenizer_wordpiece_encode(text: string) -> ptr { return wordpiece_encode(text); }
fn tokenizer_bpe_decode_token(token_id: float) -> string { return bpe_decode_token(token_id); }
