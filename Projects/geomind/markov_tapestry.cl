// Projects/geomind/markov_tapestry.cl
// 4-Block 1.08M-Row Hierarchical Tapestry Markov Hub, Lagrangian Action, & Context State Machine

include "src/std/geom.cl";
include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/fs.cl";
include "Projects/geomind/geometry.cl";

extern fn Sleep(ms: float);
extern fn cartan_f32_at(p: ptr, offset: float) -> float;
extern fn cartan_set_f32(p: ptr, offset: float, val: float) -> void;
extern fn cartan_i32_at(p: ptr, offset: float) -> float;
extern fn cartan_set_i32(p: ptr, offset: float, val: float) -> void;
extern fn cartan_i64_at(p: ptr, offset: float) -> float;
extern fn cartan_set_i64(p: ptr, offset: float, val: float) -> void;

// Converts a single byte/ASCII code (0..255) into a 1-character null-terminated string
fn cartan_char_from_code(code: float) -> string {
    let res = malloc(2.0);
    cartan_set_byte(res, 0.0, code);
    cartan_set_byte(res, 1.0, 0.0);
    return res;
}

// ============================================================================
// PHASE 2: 256x256 MARKOV TRANSITION MATRIX & LAGRANGIAN LEAST-ACTION ENGINE
// ============================================================================
// 256 x 256 transition count matrix (65,536 floats = 256 KB) + 256 row totals
var g_markov_counts_256x256: ptr = 0.0;
var g_markov_row_totals_256: ptr = 0.0;
// 4-Block Lossless Hierarchical Tapestry Markov Table (1,081,344 rows x 128 ASCII next bytes = 1,048,576 hub slots):
// - Block 0 (0..32767,          32,768 rows): Collision-free 32-symbol 3-gram morphology (b3, b2, b1)
// - Block 1 (32768..294911,    262,144 rows): Open-addressed 1-Word Anchor Hub (w_k, b3, b2, b1)
// - Block 2 (294912..688127,   393,216 rows): Open-addressed 2-Word Phrase Hub (w_{k-1}, w_k, b3, b2, b1)
// - Block 3 (688128..1081343,  393,216 rows): Open-addressed 3-Word Clause Hub (w_{k-2}, w_{k-1}, w_k, b3, b2, b1)
var g_markov_3gram_counts: ptr = 0.0;
var g_markov_3gram_totals: ptr = 0.0;
var g_markov_3gram_keys: ptr = 0.0;
var g_markov_ctx_word1_id: float = 0.0;
var g_markov_ctx_word2_id: float = 0.0;
var g_markov_ctx_word3_id: float = 0.0;
var g_markov_ctx_syn1_id: float = 0.0;
var g_markov_ctx_syn2_id: float = 0.0;
var g_markov_ctx_syn3_id: float = 0.0;
var g_markov_ctx_syn_weight: float = 1.0;
var g_ctx_prev2_syn_w: float = 1.0;
var g_ctx_prev_syn_w: float = 1.0;
var g_ctx_last_syn_w: float = 1.0;
var g_ctx_sent_topic_syn: float = 0.0;
var g_ctx_sent_topic_syn_w: float = 1.0;
var g_markov_fast_s1_idx: float = -1.0;
var g_markov_fast_tot_s1: float = 0.0;
var g_markov_fast_s2_idx: float = -1.0;
var g_markov_fast_tot_s2: float = 0.0;
var g_markov_fast_s3_idx: float = -1.0;
var g_markov_fast_tot_s3: float = 0.0;
var g_markov_hub_occupied_slots: float = 0.0;
var g_markov_initialized: float = 0.0;

var g_ctx_prev2_hash: float = 17.0;
var g_ctx_prev_hash: float = 17.0;
var g_ctx_last_hash: float = 17.0;
var g_ctx_prev2_syn: float = 0.0;
var g_ctx_prev_syn: float = 0.0;
var g_ctx_last_syn: float = 0.0;
var g_ctx_sent_topic_hash: float = 17.0;
var g_ctx_sent_started_subord: float = 0.0;


// Maps any byte (0..255) to a 32-state collision-free orthographic symbol index:
// 0=' ', 1..26='a'..'z' (case-folded), 27='.', 28=',', 29='\'', 30='!', 31=other
fn geomind_markov_byte_sym32(b: float) -> float {
    let x = math_mod_val(floor(math_abs_val(b)), 256.0);
    if (x == 32.0) { return 0.0; }
    if (x >= 97.0 && x <= 122.0) { return (x - 97.0) + 1.0; }
    if (x >= 65.0 && x <= 90.0) { return (x - 65.0) + 1.0; }
    if (x == 46.0) { return 27.0; }
    if (x == 44.0) { return 28.0; }
    if (x == 39.0) { return 29.0; }
    if (x == 33.0 || x == 63.0) { return 30.0; }
    return 31.0;
}

fn geomind_markov_3gram_ctx_idx(b3: float, b2: float, b1: float) -> float {
    var s3 = geomind_markov_byte_sym32(b3);
    let s2 = geomind_markov_byte_sym32(b2);
    let s1 = geomind_markov_byte_sym32(b1);
    // Normalize pre-period character at sentence boundaries (". ") so topic hubs
    // transfer across novel sentence endings regardless of the final letter before '.'
    if ((s2 == 27.0 || s2 == 30.0) && s1 == 0.0) {
        s3 = s2;
    }
    return s3 * 1024.0 + s2 * 32.0 + s1;
}

// Canonical 3-gram context index for Word & Synset Hubs (Blocks 1, 2, 3):
// Because the previous word's identity is already encoded in w1_id / w2_id / w3_id / syn_id,
// normalizing the previous word's trailing letters across the space boundary (' ') allows
// WordNet synonyms with different endings ("cat" vs "kitten", "dog" vs "puppy", "ball" vs "orb")
// to share their post-word transition tables seamlessly.
fn geomind_markov_hub_ctx_idx(b3: float, b2: float, b1: float) -> float {
    var s3 = geomind_markov_byte_sym32(b3);
    var s2 = geomind_markov_byte_sym32(b2);
    let s1 = geomind_markov_byte_sym32(b1);
    if ((s2 == 27.0 || s2 == 28.0 || s2 == 30.0) && s1 == 0.0) {
        s3 = s2;
    } else if (s1 == 0.0 && s2 > 0.0 && s2 < 27.0) {
        s3 = 0.0;
        s2 = 0.0;
    } else if (s2 == 0.0 && s3 > 0.0 && s3 < 27.0) {
        s3 = 0.0;
    }
    return s3 * 1024.0 + s2 * 32.0 + s1;
}

fn geomind_markov_hub_row_idx(base_row: float, block_rows: float, hub_id: float, c_idx: float, create_slot: float) -> float {
    if (hub_id <= 0.0) { return -1.0; }
    let pid = math_mod_val(floor(math_abs_val(hub_id)), 8388607.0);
    let k_pid = pid + 1.0;
    let k_tri = c_idx + 1.0;
    let h0 = math_mod_val(pid * 13331.0 + c_idx * 997.0, block_rows);
    if (g_markov_3gram_keys == 0.0) {
        return base_row + h0;
    }
    var probe = 0.0;
    while (probe < 16.0) {
        let slot = math_mod_val(h0 + probe * 7.0, block_rows);
        let row = base_row + slot;
        let cur_pid = cartan_vec_get_f32(g_markov_3gram_keys, row * 2.0);
        let cur_tri = cartan_vec_get_f32(g_markov_3gram_keys, row * 2.0 + 1.0);
        if (cur_pid == k_pid && cur_tri == k_tri) {
            return row;
        }
        if (cur_pid == 0.0 && cur_tri == 0.0) {
            if (create_slot == 1.0) {
                cartan_vec_set_f32(g_markov_3gram_keys, row * 2.0, k_pid);
                cartan_vec_set_f32(g_markov_3gram_keys, row * 2.0 + 1.0, k_tri);
                g_markov_hub_occupied_slots = g_markov_hub_occupied_slots + 1.0;
                return row;
            }
            return -1.0;
        }
        probe = probe + 1.0;
    }
    if (create_slot == 1.0) {
        return base_row + h0;
    }
    return -1.0;
}

fn geomind_markov_update_3gram(b3: float, b2: float, b1: float, curr_byte: float) -> float {
    geomind_markov_init_if_needed();
    let cb = math_mod_val(floor(math_abs_val(curr_byte)), 128.0);
    let c_idx = geomind_markov_3gram_ctx_idx(b3, b2, b1);
    let hub_c_idx = geomind_markov_hub_ctx_idx(b3, b2, b1);
    let m_idx = c_idx * 128.0 + cb;
    let old_cnt = cartan_vec_get_f32(g_markov_3gram_counts, m_idx);
    let old_tot = cartan_vec_get_f32(g_markov_3gram_totals, c_idx);
    var p3 = 1.0 / 128.0;
    if (old_tot > 0.000001) { p3 = (old_cnt + 0.01) / (old_tot + 1.28); }
    cartan_vec_set_f32(g_markov_3gram_counts, m_idx, old_cnt + 1.0);
    cartan_vec_set_f32(g_markov_3gram_totals, c_idx, old_tot + 1.0);

    // Update Block 1: 1-Word Anchor Hub + WordNet Synset 1-Word Hub (32768..294911, 262,144 rows)
    // Only canonical head prototypes (g_ctx_last_syn_w >= 0.99) write to the shared synset hub so specialized subtypes keep distinct surface tracks.
    let w1_idx = geomind_markov_hub_row_idx(32768.0, 262144.0, g_markov_ctx_word1_id, hub_c_idx, 1.0);
    if (w1_idx >= 32768.0) {
        let w1m = w1_idx * 128.0 + cb;
        cartan_vec_set_f32(g_markov_3gram_counts, w1m, cartan_vec_get_f32(g_markov_3gram_counts, w1m) + 1.0);
        cartan_vec_set_f32(g_markov_3gram_totals, w1_idx, cartan_vec_get_f32(g_markov_3gram_totals, w1_idx) + 1.0);
    }
    if (g_markov_ctx_syn1_id > 0.0 && g_markov_ctx_syn1_id != g_markov_ctx_word1_id && g_ctx_last_syn_w >= 0.99) {
        let s1_idx = geomind_markov_hub_row_idx(32768.0, 262144.0, g_markov_ctx_syn1_id, hub_c_idx, 1.0);
        if (s1_idx >= 32768.0) {
            let s1m = s1_idx * 128.0 + cb;
            cartan_vec_set_f32(g_markov_3gram_counts, s1m, cartan_vec_get_f32(g_markov_3gram_counts, s1m) + 1.0);
            cartan_vec_set_f32(g_markov_3gram_totals, s1_idx, cartan_vec_get_f32(g_markov_3gram_totals, s1_idx) + 1.0);
        }
    }

    // Update Block 2: 2-Word Phrase Hub + WordNet Synset 2-Word Hub (294912..688127, 393,216 rows)
    let w2_idx = geomind_markov_hub_row_idx(294912.0, 393216.0, g_markov_ctx_word2_id, hub_c_idx, 1.0);
    if (w2_idx >= 294912.0) {
        let w2m = w2_idx * 128.0 + cb;
        cartan_vec_set_f32(g_markov_3gram_counts, w2m, cartan_vec_get_f32(g_markov_3gram_counts, w2m) + 1.0);
        cartan_vec_set_f32(g_markov_3gram_totals, w2_idx, cartan_vec_get_f32(g_markov_3gram_totals, w2_idx) + 1.0);
    }
    if (g_markov_ctx_syn2_id > 0.0 && g_markov_ctx_syn2_id != g_markov_ctx_word2_id && g_ctx_prev_syn_w >= 0.99 && g_ctx_last_syn_w >= 0.99) {
        let s2_idx = geomind_markov_hub_row_idx(294912.0, 393216.0, g_markov_ctx_syn2_id, hub_c_idx, 1.0);
        if (s2_idx >= 294912.0) {
            let s2m = s2_idx * 128.0 + cb;
            cartan_vec_set_f32(g_markov_3gram_counts, s2m, cartan_vec_get_f32(g_markov_3gram_counts, s2m) + 1.0);
            cartan_vec_set_f32(g_markov_3gram_totals, s2_idx, cartan_vec_get_f32(g_markov_3gram_totals, s2_idx) + 1.0);
        }
    }

    // Update Block 3: 3-Word Clause Hub + WordNet Synset 3-Word Hub (688128..1081343, 393,216 rows)
    let w3_idx = geomind_markov_hub_row_idx(688128.0, 393216.0, g_markov_ctx_word3_id, hub_c_idx, 1.0);
    if (w3_idx >= 688128.0) {
        let w3m = w3_idx * 128.0 + cb;
        cartan_vec_set_f32(g_markov_3gram_counts, w3m, cartan_vec_get_f32(g_markov_3gram_counts, w3m) + 1.0);
        cartan_vec_set_f32(g_markov_3gram_totals, w3_idx, cartan_vec_get_f32(g_markov_3gram_totals, w3_idx) + 1.0);
    }
    if (g_markov_ctx_syn3_id > 0.0 && g_markov_ctx_syn3_id != g_markov_ctx_word3_id && g_ctx_sent_topic_syn_w >= 0.99 && g_ctx_prev2_syn_w >= 0.99 && g_ctx_prev_syn_w >= 0.99 && g_ctx_last_syn_w >= 0.99) {
        let s3_idx = geomind_markov_hub_row_idx(688128.0, 393216.0, g_markov_ctx_syn3_id, hub_c_idx, 1.0);
        if (s3_idx >= 688128.0) {
            let s3m = s3_idx * 128.0 + cb;
            cartan_vec_set_f32(g_markov_3gram_counts, s3m, cartan_vec_get_f32(g_markov_3gram_counts, s3m) + 1.0);
            cartan_vec_set_f32(g_markov_3gram_totals, s3_idx, cartan_vec_get_f32(g_markov_3gram_totals, s3_idx) + 1.0);
        }
    }
    return p3;
}

fn geomind_markov_get_3gram_prob_fast(
    b1: float,
    curr_byte: float,
    c_idx: float,
    tot3: float,
    w1_idx: float,
    tot_w1: float,
    w2_idx: float,
    tot_w2: float,
    w3_idx: float,
    tot_w3: float
) -> float {
    let p1 = geomind_markov_get_prob(b1, curr_byte);
    let cb = math_mod_val(floor(math_abs_val(curr_byte)), 128.0);
    let m_idx = c_idx * 128.0 + cb;
    let cnt3 = cartan_vec_get_f32(g_markov_3gram_counts, m_idx);
    var p3 = p1 * 0.05;
    if (tot3 > 0.5 && cnt3 >= 0.5) {
        p3 = (cnt3 + 0.005) / (tot3 + 0.05);
    }

    // Query Block 1: 1-Word Anchor Hub + WordNet Synset Hub Backoff (32768..294911, 262,144 rows)
    var has_w1 = 0.0;
    var p_w1 = 0.0;
    var hit_w1 = 0.0;
    if (w1_idx >= 32768.0 && tot_w1 > 0.5) {
        has_w1 = 1.0;
        let cnt_w1 = cartan_vec_get_f32(g_markov_3gram_counts, w1_idx * 128.0 + cb);
        if (cnt_w1 >= 0.5) {
            hit_w1 = 1.0;
            let safe_w1 = cnt_w1;
            if (tot_w1 > 32.0) {
                let s_c1 = sqrt(safe_w1 * sqrt(safe_w1));
                let s_t1 = sqrt(tot_w1 * sqrt(tot_w1));
                p_w1 = (s_c1 + 0.005) / (s_t1 + 0.05);
            } else {
                p_w1 = (safe_w1 + 0.005) / (tot_w1 + 0.05);
            }
        } else if (g_markov_fast_s1_idx >= 32768.0 && g_markov_fast_tot_s1 > 0.5) {
            let cnt_s1 = cartan_vec_get_f32(g_markov_3gram_counts, g_markov_fast_s1_idx * 128.0 + cb);
            if (cnt_s1 >= 0.5) {
                hit_w1 = 1.0;
                p_w1 = g_markov_ctx_syn_weight * ((cnt_s1 + 0.005) / (g_markov_fast_tot_s1 + 0.05));
            } else {
                p_w1 = 0.0005 / (tot_w1 + 0.05);
            }
        } else {
            p_w1 = 0.0005 / (tot_w1 + 0.05);
        }
    }

    // Query Block 2: 2-Word Phrase Hub + WordNet Synset Hub Backoff (294912..688127, 393,216 rows)
    var has_w2 = 0.0;
    var p_w2 = 0.0;
    var hit_w2 = 0.0;
    if (w2_idx >= 294912.0 && tot_w2 > 0.5) {
        has_w2 = 1.0;
        let cnt_w2 = cartan_vec_get_f32(g_markov_3gram_counts, w2_idx * 128.0 + cb);
        if (cnt_w2 >= 0.5) {
            hit_w2 = 1.0;
            let safe_w2 = cnt_w2;
            if (tot_w2 > 32.0) {
                let s_c2 = sqrt(safe_w2 * sqrt(safe_w2));
                let s_t2 = sqrt(tot_w2 * sqrt(tot_w2));
                p_w2 = (s_c2 + 0.005) / (s_t2 + 0.05);
            } else {
                p_w2 = (safe_w2 + 0.005) / (tot_w2 + 0.05);
            }
        } else if (g_markov_fast_s2_idx >= 294912.0 && g_markov_fast_tot_s2 > 0.5) {
            let cnt_s2 = cartan_vec_get_f32(g_markov_3gram_counts, g_markov_fast_s2_idx * 128.0 + cb);
            if (cnt_s2 >= 0.5) {
                hit_w2 = 1.0;
                p_w2 = g_markov_ctx_syn_weight * ((cnt_s2 + 0.005) / (g_markov_fast_tot_s2 + 0.05));
            } else {
                p_w2 = 0.0005 / (tot_w2 + 0.05);
            }
        } else {
            p_w2 = 0.0005 / (tot_w2 + 0.05);
        }
    }

    // Query Block 3: 3-Word Clause Hub + WordNet Synset Hub Backoff (688128..1081343, 393,216 rows)
    var has_w3 = 0.0;
    var p_w3 = 0.0;
    var hit_w3 = 0.0;
    if (w3_idx >= 688128.0 && tot_w3 > 0.5) {
        has_w3 = 1.0;
        let cnt_w3 = cartan_vec_get_f32(g_markov_3gram_counts, w3_idx * 128.0 + cb);
        if (cnt_w3 >= 0.5) {
            hit_w3 = 1.0;
            let safe_w3 = cnt_w3;
            if (tot_w3 > 32.0) {
                let s_c3 = sqrt(safe_w3 * sqrt(safe_w3));
                let s_t3 = sqrt(tot_w3 * sqrt(tot_w3));
                p_w3 = (s_c3 + 0.005) / (s_t3 + 0.05);
            } else {
                p_w3 = (safe_w3 + 0.005) / (tot_w3 + 0.05);
            }
        } else if (g_markov_fast_s3_idx >= 688128.0 && g_markov_fast_tot_s3 > 0.5) {
            let cnt_s3 = cartan_vec_get_f32(g_markov_3gram_counts, g_markov_fast_s3_idx * 128.0 + cb);
            if (cnt_s3 >= 0.5) {
                hit_w3 = 1.0;
                p_w3 = g_markov_ctx_syn_weight * ((cnt_s3 + 0.005) / (g_markov_fast_tot_s3 + 0.05));
            } else {
                p_w3 = 0.0005 / (tot_w3 + 0.05);
            }
        } else {
            p_w3 = 0.0005 / (tot_w3 + 0.05);
        }
    }

    // Prevent global 3-gram p3 from polluting an active phrase hub when the byte never occurred in that hub
    var bo_w3 = 1.0;
    if (hit_w3 == 0.0) { bo_w3 = 0.005; }
    var bo_w2 = 1.0;
    if (hit_w2 == 0.0) { bo_w2 = 0.005; }
    var bo_w1 = 1.0;
    if (hit_w1 == 0.0) { bo_w1 = 0.005; }

    if (has_w3 == 1.0 && has_w2 == 1.0 && has_w1 == 1.0) {
        return 0.68 * p_w3 + bo_w3 * (0.18 * p_w2 + 0.08 * p_w1 + 0.04 * p3 + 0.02 * p1);
    }
    if (has_w3 == 1.0) {
        return 0.85 * p_w3 + bo_w3 * (0.10 * p3 + 0.05 * p1);
    }
    if (has_w2 == 1.0 && has_w1 == 1.0) {
        return 0.72 * p_w2 + bo_w2 * (0.20 * p_w1 + 0.06 * p3 + 0.02 * p1);
    }
    if (has_w2 == 1.0) {
        return 0.88 * p_w2 + bo_w2 * (0.08 * p3 + 0.04 * p1);
    }
    if (has_w1 == 1.0) {
        return 0.88 * p_w1 + bo_w1 * (0.08 * p3 + 0.04 * p1);
    }
    return 0.90 * p3 + 0.10 * p1;
}

fn geomind_markov_get_3gram_prob(b3: float, b2: float, b1: float, curr_byte: float) -> float {
    geomind_markov_init_if_needed();
    let c_idx = geomind_markov_3gram_ctx_idx(b3, b2, b1);
    let hub_c_idx = geomind_markov_hub_ctx_idx(b3, b2, b1);
    let tot3 = cartan_vec_get_f32(g_markov_3gram_totals, c_idx);
    var w1_idx = geomind_markov_hub_row_idx(32768.0, 262144.0, g_markov_ctx_word1_id, hub_c_idx, 0.0);
    var tot_w1 = 0.0;
    if (w1_idx >= 32768.0) { tot_w1 = cartan_vec_get_f32(g_markov_3gram_totals, w1_idx); }
    g_markov_fast_s1_idx = -1.0;
    g_markov_fast_tot_s1 = 0.0;
    if (g_markov_ctx_syn1_id > 0.0) {
        let s1_idx = geomind_markov_hub_row_idx(32768.0, 262144.0, g_markov_ctx_syn1_id, hub_c_idx, 0.0);
        if (s1_idx >= 32768.0) {
            g_markov_fast_s1_idx = s1_idx;
            g_markov_fast_tot_s1 = cartan_vec_get_f32(g_markov_3gram_totals, s1_idx);
            if (tot_w1 < 0.5) { w1_idx = s1_idx; tot_w1 = g_markov_fast_tot_s1; }
        }
    }
    var w2_idx = geomind_markov_hub_row_idx(294912.0, 393216.0, g_markov_ctx_word2_id, hub_c_idx, 0.0);
    var tot_w2 = 0.0;
    if (w2_idx >= 294912.0) { tot_w2 = cartan_vec_get_f32(g_markov_3gram_totals, w2_idx); }
    g_markov_fast_s2_idx = -1.0;
    g_markov_fast_tot_s2 = 0.0;
    if (g_markov_ctx_syn2_id > 0.0) {
        let s2_idx = geomind_markov_hub_row_idx(294912.0, 393216.0, g_markov_ctx_syn2_id, hub_c_idx, 0.0);
        if (s2_idx >= 294912.0) {
            g_markov_fast_s2_idx = s2_idx;
            g_markov_fast_tot_s2 = cartan_vec_get_f32(g_markov_3gram_totals, s2_idx);
            if (tot_w2 < 0.5) { w2_idx = s2_idx; tot_w2 = g_markov_fast_tot_s2; }
        }
    }
    var w3_idx = geomind_markov_hub_row_idx(688128.0, 393216.0, g_markov_ctx_word3_id, hub_c_idx, 0.0);
    var tot_w3 = 0.0;
    if (w3_idx >= 688128.0) { tot_w3 = cartan_vec_get_f32(g_markov_3gram_totals, w3_idx); }
    g_markov_fast_s3_idx = -1.0;
    g_markov_fast_tot_s3 = 0.0;
    if (g_markov_ctx_syn3_id > 0.0) {
        let s3_idx = geomind_markov_hub_row_idx(688128.0, 393216.0, g_markov_ctx_syn3_id, hub_c_idx, 0.0);
        if (s3_idx >= 688128.0) {
            g_markov_fast_s3_idx = s3_idx;
            g_markov_fast_tot_s3 = cartan_vec_get_f32(g_markov_3gram_totals, s3_idx);
            if (tot_w3 < 0.5) { w3_idx = s3_idx; tot_w3 = g_markov_fast_tot_s3; }
        }
    }
    return geomind_markov_get_3gram_prob_fast(b1, curr_byte, c_idx, tot3, w1_idx, tot_w1, w2_idx, tot_w2, w3_idx, tot_w3);
}

fn geomind_markov_save_prior(path: string) -> float {
    if (path == 0.0 || g_markov_counts_256x256 == 0.0 || g_markov_row_totals_256 == 0.0) { return 0.0; }
    let f = fopen(path, "wb");
    if (f == 0.0) { return 0.0; }
    fwrite(g_markov_counts_256x256, 8.0, 65536.0 + 2.0, f);
    fwrite(g_markov_row_totals_256, 8.0, 256.0 + 2.0, f);
    if (g_markov_3gram_counts != 0.0) {
        fwrite(g_markov_3gram_counts, 8.0, 138412032.0 + 2.0, f);
        fwrite(g_markov_3gram_totals, 8.0, 1081344.0 + 2.0, f);
        fwrite(g_markov_3gram_keys, 8.0, 2162688.0 + 2.0, f);
    }
    fclose(f);
    return 1.0;
}

fn geomind_markov_load_prior(path: string) -> float {
    if (path == 0.0 || cartan_file_exists(path) == 0.0) { return 0.0; }
    let expected_elems = (65536.0 + 2.0) + (256.0 + 2.0) + (138412032.0 + 2.0) + (1081344.0 + 2.0) + (2162688.0 + 2.0);
    let f_sz = cartan_get_binary_file_size(path);
    if (f_sz < expected_elems * 8.0) { return 0.0; }
    if (g_markov_counts_256x256 == 0.0) { g_markov_counts_256x256 = cartan_tensor_alloc(65536.0); }
    if (g_markov_row_totals_256 == 0.0) { g_markov_row_totals_256 = cartan_tensor_alloc(256.0); }
    if (g_markov_3gram_counts == 0.0) { g_markov_3gram_counts = cartan_tensor_alloc(138412032.0); }
    if (g_markov_3gram_totals == 0.0) { g_markov_3gram_totals = cartan_tensor_alloc(1081344.0); }
    if (g_markov_3gram_keys == 0.0) { g_markov_3gram_keys = cartan_tensor_alloc(2162688.0); }
    let f = fopen(path, "rb");
    if (f == 0.0) { return 0.0; }
    fread(g_markov_counts_256x256, 8.0, 65536.0 + 2.0, f);
    fread(g_markov_row_totals_256, 8.0, 256.0 + 2.0, f);
    fread(g_markov_3gram_counts, 8.0, 138412032.0 + 2.0, f);
    fread(g_markov_3gram_totals, 8.0, 1081344.0 + 2.0, f);
    fread(g_markov_3gram_keys, 8.0, 2162688.0 + 2.0, f);
    fclose(f);
    g_markov_initialized = 1.0;
    return 1.0;
}

fn geomind_markov_init_if_needed() -> float {
    if (g_markov_initialized == 1.0 && g_markov_counts_256x256 != 0.0) {
        return 1.0;
    }
    if (g_markov_counts_256x256 != 0.0) { cartan_vec_free(g_markov_counts_256x256); }
    if (g_markov_row_totals_256 != 0.0) { cartan_vec_free(g_markov_row_totals_256); }
    if (g_markov_3gram_counts != 0.0) { cartan_vec_free(g_markov_3gram_counts); }
    if (g_markov_3gram_totals != 0.0) { cartan_vec_free(g_markov_3gram_totals); }
    if (g_markov_3gram_keys != 0.0) { cartan_vec_free(g_markov_3gram_keys); }

    g_markov_counts_256x256 = cartan_tensor_alloc(65536.0);
    g_markov_row_totals_256 = cartan_tensor_alloc(256.0);
    g_markov_3gram_counts = cartan_tensor_alloc(138412032.0);
    g_markov_3gram_totals = cartan_tensor_alloc(1081344.0);
    g_markov_3gram_keys = cartan_tensor_alloc(2162688.0);
    g_markov_hub_occupied_slots = 0.0;

    // Initialize with Laplace Dirichlet prior (alpha = 0.02 per cell, row total = 256 * 0.02 = 5.12)
    var idx = 0.0;
    while (idx < 65536.0) {
        cartan_vec_set_f32(g_markov_counts_256x256, idx, 0.02);
        idx = idx + 1.0;
    }
    var r = 0.0;
    while (r < 256.0) {
        cartan_vec_set_f32(g_markov_row_totals_256, r, 5.12);
        r = r + 1.0;
    }
    g_markov_initialized = 1.0;
    if (g_byte_e8_skip_disk_autoload == 0.0 && cartan_file_exists("Projects/geomind/trainingdata/checkpoints/geomind_markov_prior.bin") == 1.0) {
        geomind_markov_load_prior("Projects/geomind/trainingdata/checkpoints/geomind_markov_prior.bin");
    }
    return 1.0;
}

// Query empirical conditional transition probability P(curr_byte | prev_byte) in [0, 1]
fn geomind_markov_get_prob(prev_byte: float, curr_byte: float) -> float {
    geomind_markov_init_if_needed();
    let pb = math_mod_val(floor(math_abs_val(prev_byte)), 256.0);
    let cb = math_mod_val(floor(math_abs_val(curr_byte)), 256.0);
    let m_idx = pb * 256.0 + cb;
    let cnt = cartan_vec_get_f32(g_markov_counts_256x256, m_idx);
    let row_tot = cartan_vec_get_f32(g_markov_row_totals_256, pb);
    if (row_tot <= 0.000001) { return 1.0 / 256.0; }
    return cnt / row_tot;
}

// Observe transition (prev_byte -> curr_byte), update 256x256 Markov matrix, and return P(curr_byte | prev_byte)
fn geomind_markov_update_and_get_prob(prev_byte: float, curr_byte: float) -> float {
    geomind_markov_init_if_needed();
    let pb = math_mod_val(floor(math_abs_val(prev_byte)), 256.0);
    let cb = math_mod_val(floor(math_abs_val(curr_byte)), 256.0);
    let m_idx = pb * 256.0 + cb;
    let old_cnt = cartan_vec_get_f32(g_markov_counts_256x256, m_idx);
    let old_tot = cartan_vec_get_f32(g_markov_row_totals_256, pb);
    let prob = old_cnt / old_tot;

    cartan_vec_set_f32(g_markov_counts_256x256, m_idx, old_cnt + 1.0);
    cartan_vec_set_f32(g_markov_row_totals_256, pb, old_tot + 1.0);
    return prob;
}

// Compute byte transition surprisal in bits: H(b_t | b_{t-1}) = -log2 P(b_t | b_{t-1})
fn geomind_markov_surprisal_bits(prev_byte: float, curr_byte: float) -> float {
    let p = geomind_markov_get_prob(prev_byte, curr_byte);
    var safe_p = p;
    if (safe_p < 0.000001) { safe_p = 0.000001; }
    return (0.0 - log(safe_p)) * 1.4426950408889634;
}

// Evaluate Finsler-Randers Geodesic Kinetic Energy T_geo(h_prev, h_curr) on the 248-D E8 Manifold:
// T_geo = 0.5 * sum_d g_d * (dh_d)^2 + sum_d tilde{beta}_d * dh_d
fn geomind_e8_geodesic_kinetic_energy_248(h_prev_248: ptr, h_curr_248: ptr, randers_b_248: ptr) -> float {
    if (h_prev_248 == 0.0 || h_curr_248 == 0.0) { return 0.0; }
    var quad_term = 0.0;
    var drift_dot = 0.0;
    var norm_b_sq = 0.0;
    var d = 0.0;
    var p_prev = 0.0;
    var p_curr = 0.0;
    var dh = 0.0;
    var sub_idx = 0.0;
    var g_d = 1.0;
    var b_d = 0.0;
    while (d < 248.0) {
        p_prev = cartan_vec_get_f32(h_prev_248, d);
        p_curr = cartan_vec_get_f32(h_curr_248, d);
        dh = p_curr - p_prev;
        sub_idx = math_mod_val(floor(d / 31.0), 8.0);
        g_d = geom_killing_form_dynkin_weight(sub_idx);
        quad_term = quad_term + 0.5 * g_d * dh * dh;
        if (randers_b_248 != 0.0) {
            b_d = cartan_vec_get_f32(randers_b_248, d);
            norm_b_sq = norm_b_sq + (b_d * b_d) / g_d;
            drift_dot = drift_dot + b_d * dh;
        }
        d = d + 1.0;
    }
    var bounded_drift = 0.0;
    if (randers_b_248 != 0.0) {
        let norm_b = sqrt(norm_b_sq);
        if (norm_b > 0.000001) {
            bounded_drift = drift_dot * (0.95 * tanh(norm_b) / norm_b);
        }
    }
    let t_geo = quad_term + bounded_drift;
    if (t_geo < 0.0) { return 0.0; }
    return t_geo;
}

// Analytical Gradient of Finsler-Randers Geodesic Kinetic Energy with respect to h_curr_248:
// d(T_geo)/d(h_curr[d]) = g_d * (h_curr[d] - h_prev[d]) + tilde{beta}_d
fn geomind_e8_geodesic_kinetic_grad_248(h_prev_248: ptr, h_curr_248: ptr, randers_b_248: ptr, grad_out_248: ptr, scale: float) {
    if (h_prev_248 == 0.0 || h_curr_248 == 0.0 || grad_out_248 == 0.0) { return; }
    var norm_b_sq = 0.0;
    var d = 0.0;
    var sub_idx = 0.0;
    var g_d = 1.0;
    var b_d = 0.0;
    if (randers_b_248 != 0.0) {
        while (d < 248.0) {
            sub_idx = math_mod_val(floor(d / 31.0), 8.0);
            g_d = geom_killing_form_dynkin_weight(sub_idx);
            b_d = cartan_vec_get_f32(randers_b_248, d);
            norm_b_sq = norm_b_sq + (b_d * b_d) / g_d;
            d = d + 1.0;
        }
    }
    var b_scale = 0.0;
    if (randers_b_248 != 0.0) {
        let norm_b = sqrt(norm_b_sq);
        if (norm_b > 0.000001) {
            b_scale = 0.95 * tanh(norm_b) / norm_b;
        }
    }
    var p_prev = 0.0;
    var p_curr = 0.0;
    var dh = 0.0;
    var tilde_b = 0.0;
    d = 0.0;
    while (d < 248.0) {
        p_prev = cartan_vec_get_f32(h_prev_248, d);
        p_curr = cartan_vec_get_f32(h_curr_248, d);
        dh = p_curr - p_prev;
        sub_idx = math_mod_val(floor(d / 31.0), 8.0);
        g_d = geom_killing_form_dynkin_weight(sub_idx);
        tilde_b = 0.0;
        if (randers_b_248 != 0.0) {
            tilde_b = cartan_vec_get_f32(randers_b_248, d) * b_scale;
        }
        cartan_vec_set_f32(grad_out_248, d, scale * (g_d * dh + tilde_b));
        d = d + 1.0;
    }
}

// Compute Cross-Entropy Prediction Kinetic Energy T_pred over 256 byte channels and populate softmax delta_out
fn geomind_byte_cross_entropy_and_delta(logits_256: ptr, target_byte: float, delta_out_256: ptr) -> float {
    if (logits_256 == 0.0) { return 0.0; }
    let tgt = math_mod_val(floor(math_abs_val(target_byte)), 256.0);
    var max_l = -100000.0;
    var i = 0.0;
    var lv = 0.0;
    while (i < 256.0) {
        lv = cartan_vec_get_f32(logits_256, i);
        if (lv > max_l) { max_l = lv; }
        i = i + 1.0;
    }
    var sum_exp = 0.0;
    i = 0.0;
    while (i < 256.0) {
        lv = cartan_vec_get_f32(logits_256, i);
        sum_exp = sum_exp + exp(lv - max_l);
        i = i + 1.0;
    }
    if (sum_exp < 0.0000001) { sum_exp = 0.0000001; }
    let inv_sum = 1.0 / sum_exp;

    if (delta_out_256 != 0.0) {
        var prob_i = 0.0;
        var grad_i = 0.0;
        i = 0.0;
        while (i < 256.0) {
            lv = cartan_vec_get_f32(logits_256, i);
            prob_i = exp(lv - max_l) * inv_sum;
            grad_i = prob_i;
            if (i == tgt) { grad_i = grad_i - 1.0; }
            cartan_vec_set_f32(delta_out_256, i, grad_i);
            i = i + 1.0;
        }
    }

    let tgt_l = cartan_vec_get_f32(logits_256, tgt);
    var tgt_p = exp(tgt_l - max_l) * inv_sum;
    if (tgt_p < 0.0000000001) { tgt_p = 0.0000000001; }
    return 0.0 - log(tgt_p);
}

// Coupled Markov-Lagrangian Action Loss:
// S = (T_pred + lambda_geo * T_geo) * (1.0 - 0.5 * V_markov)
// where V_markov = P(target_byte | prev_byte) creates potential wells along established syntax transitions
fn geomind_lagrangian_action_step(
    logits_256: ptr,
    target_byte: float,
    prev_byte: float,
    h_prev_248: ptr,
    h_curr_248: ptr,
    randers_b_248: ptr,
    delta_out_256: ptr
) -> float {
    let potential_v = geomind_markov_update_and_get_prob(prev_byte, target_byte);
    let t_pred = geomind_byte_cross_entropy_and_delta(logits_256, target_byte, delta_out_256);
    let t_geo = geomind_e8_geodesic_kinetic_energy_248(h_prev_248, h_curr_248, randers_b_248);

    let well_factor = 1.0 - 0.5 * potential_v;
    let total_kinetic = t_pred + 0.15 * t_geo;
    let action_penalty = total_kinetic * well_factor;

    // Scale output gradient delta by the Lagrangian potential well factor (1 - 0.5 * V_markov)
    if (delta_out_256 != 0.0) {
        var i = 0.0;
        var dv = 0.0;
        while (i < 256.0) {
            dv = cartan_vec_get_f32(delta_out_256, i);
            cartan_vec_set_f32(delta_out_256, i, dv * well_factor);
            i = i + 1.0;
        }
    }
    return action_penalty;
}

// Phase 2.4: Low-Action Geodesic Coasting Gate
// Returns 1.0 when Markov potential V is high (>= 0.35, ~90x uniform byte prior) and geodesic kinetic energy T_geo is below threshold
fn geomind_should_geodesic_coast(prev_byte: float, cand_byte: float, t_geo: float, geo_thresh: float) -> float {
    let v_prob = geomind_markov_get_prob(prev_byte, cand_byte);
    var norm_t = t_geo;
    if (norm_t > 1.0) { norm_t = norm_t / 248.0; }
    if (v_prob >= 0.25 && norm_t <= geo_thresh) {
        return 1.0;
    }
    return 0.0;
}


fn geomind_is_glue_word_hash(patch_hash: float, alnum_len: float) -> float {
    if (alnum_len <= 2.0) { return 1.0; }
    if (patch_hash == 221828.0 || patch_hash == 896557.0 || patch_hash == 914651.0 || patch_hash == 982507.0) { return 1.0; } // the, and, but, for
    if (patch_hash == 119794.0 || patch_hash == 308566.0 || patch_hash == 897082.0 || patch_hash == 272408.0) { return 1.0; } // not, you, are, was
    if (patch_hash == 929186.0 || patch_hash == 803746.0 || patch_hash == 59491.0  || patch_hash == 58973.0)  { return 1.0; } // can, when, then, that
    if (patch_hash == 60020.0  || patch_hash == 822866.0 || patch_hash == 759232.0 || patch_hash == 435497.0) { return 1.0; } // this, with, from, into
    if (patch_hash == 446174.0 || patch_hash == 921767.0 || patch_hash == 465885.0 || patch_hash == 268202.0) { return 1.0; } // upon, once, small, little
    if (patch_hash == 67882.0  || patch_hash == 963095.0 || patch_hash == 685321.0 || patch_hash == 793925.0) { return 1.0; } // bright, cold, warm, there
    if (patch_hash == 291036.0 || patch_hash == 358894.0 || patch_hash == 71766.0  || patch_hash == 974727.0) { return 1.0; } // where, while, after, before
    if (patch_hash == 781562.0 || patch_hash == 278721.0) { return 1.0; } // every, first
    return 0.0;
}

// Returns 1.0 if `patch_hash` is a subordinate/adverbial clause opener ("when", "while", "after", "before", "once", "if")
// so that when the opening clause ends at a comma ',', `g_ctx_sent_topic_hash` resets to capture the main-clause subject.
fn geomind_is_subord_opener_hash(patch_hash: float) -> float {
    if (patch_hash == 803746.0 || patch_hash == 358894.0 || patch_hash == 71766.0 ||
        patch_hash == 974727.0 || patch_hash == 921767.0 || patch_hash == 291993.0) {
        return 1.0;
    }
    return 0.0;
}

fn geomind_markov_reset_patch_context() {
    g_ctx_prev2_hash = 17.0;
    g_ctx_prev_hash = 17.0;
    g_ctx_last_hash = 17.0;
    g_ctx_prev2_syn = 0.0;
    g_ctx_prev_syn = 0.0;
    g_ctx_last_syn = 0.0;
    g_ctx_sent_topic_hash = 17.0;
    g_ctx_sent_started_subord = 0.0;
    g_markov_ctx_word1_id = 0.0;
    g_markov_ctx_word2_id = 0.0;
    g_markov_ctx_word3_id = 0.0;
    g_markov_ctx_syn1_id = 0.0;
    g_markov_ctx_syn2_id = 0.0;
    g_markov_ctx_syn3_id = 0.0;
    g_markov_ctx_syn_weight = 1.0;
    g_ctx_prev2_syn_w = 1.0;
    g_ctx_prev_syn_w = 1.0;
    g_ctx_last_syn_w = 1.0;
    g_ctx_sent_topic_syn = 0.0;
    g_ctx_sent_topic_syn_w = 1.0;
}

fn geomind_markov_advance_patch_context(
    patch_hash: float,
    patch_alnum_len: float,
    is_para_break: float,
    patch_sent_end: float,
    patch_comma_end: float
) {
    geomind_wordnet_init_if_needed();
    if (is_para_break == 1.0) {
        geomind_markov_reset_patch_context();
        return;
    }
    if (g_ctx_prev_hash == 17.0 && geomind_is_subord_opener_hash(patch_hash) == 1.0) {
        g_ctx_sent_started_subord = 1.0;
    }
    let cur_syn = geomind_wordnet_resolve_synset(patch_hash, g_ctx_last_hash);
    var cur_syn_w = 1.0;
    if (cur_syn > 0.0) { cur_syn_w = g_markov_ctx_syn_weight; }

    if (g_ctx_sent_topic_hash == 17.0 && geomind_is_glue_word_hash(patch_hash, patch_alnum_len) == 0.0) {
        g_ctx_sent_topic_hash = patch_hash;
        g_ctx_sent_topic_syn = cur_syn;
        g_ctx_sent_topic_syn_w = cur_syn_w;
    }

    if (patch_sent_end == 1.0) {
        var top_h = g_ctx_sent_topic_hash;
        if (top_h == 17.0) { top_h = patch_hash; }
        let bridge_h = math_mod_val(top_h + 500009.0, 1000003.0);
        let top_syn = geomind_wordnet_resolve_synset(top_h, 17.0);
        var top_syn_w = 1.0;
        if (top_syn > 0.0) { top_syn_w = g_markov_ctx_syn_weight; }

        g_ctx_prev2_hash = 17.0;
        g_ctx_prev_hash = 17.0;
        g_ctx_last_hash = bridge_h;
        g_ctx_prev2_syn = 0.0;
        g_ctx_prev_syn = 0.0;
        g_ctx_prev2_syn_w = 1.0;
        g_ctx_prev_syn_w = top_syn_w;
        g_ctx_last_syn_w = top_syn_w;

        g_markov_ctx_word1_id = math_mod_val(bridge_h, 8388607.0) + 1.0;
        g_markov_ctx_word2_id = math_mod_val(bridge_h * 257.0 + patch_hash, 8388607.0) + 1.0;
        g_markov_ctx_word3_id = 0.0;

        if (top_syn > 0.0) {
            let syn_bridge_h = math_mod_val(top_syn + 500009.0, 1000003.0);
            g_ctx_last_syn = syn_bridge_h;
            var eff_tail = patch_hash;
            if (cur_syn > 0.0) { eff_tail = cur_syn; }
            g_markov_ctx_syn1_id = math_mod_val(syn_bridge_h, 8388607.0) + 1.0;
            g_markov_ctx_syn2_id = math_mod_val(syn_bridge_h * 257.0 + eff_tail, 8388607.0) + 1.0;
        } else {
            g_ctx_last_syn = 0.0;
            g_markov_ctx_syn1_id = 0.0;
            g_markov_ctx_syn2_id = 0.0;
        }
        g_markov_ctx_syn3_id = 0.0;
        g_ctx_sent_topic_hash = 17.0;
        g_ctx_sent_topic_syn = 0.0;
        g_ctx_sent_topic_syn_w = 1.0;
        g_ctx_sent_started_subord = 0.0;
    } else {
        g_ctx_prev2_hash = g_ctx_prev_hash;
        g_ctx_prev_hash = g_ctx_last_hash;
        g_ctx_last_hash = patch_hash;

        g_ctx_prev2_syn = g_ctx_prev_syn;
        g_ctx_prev_syn = g_ctx_last_syn;
        g_ctx_last_syn = cur_syn;

        g_ctx_prev2_syn_w = g_ctx_prev_syn_w;
        g_ctx_prev_syn_w = g_ctx_last_syn_w;
        g_ctx_last_syn_w = cur_syn_w;

        g_markov_ctx_word1_id = math_mod_val(patch_hash, 8388607.0) + 1.0;
        if (g_ctx_prev_hash != 17.0) {
            g_markov_ctx_word2_id = math_mod_val(g_ctx_prev_hash * 257.0 + patch_hash, 8388607.0) + 1.0;
        } else {
            g_markov_ctx_word2_id = 0.0;
        }
        if (g_ctx_prev2_hash != 17.0 && g_ctx_prev_hash != 17.0) {
            let h_top2 = math_mod_val(g_ctx_sent_topic_hash * 13331.0 + g_ctx_prev2_hash, 8388607.0);
            let h23 = math_mod_val(h_top2 * 257.0 + g_ctx_prev_hash, 8388607.0);
            g_markov_ctx_word3_id = math_mod_val(h23 * 257.0 + patch_hash, 8388607.0) + 1.0;
        } else {
            g_markov_ctx_word3_id = 0.0;
        }

        if (cur_syn > 0.0) {
            g_markov_ctx_syn1_id = math_mod_val(cur_syn, 8388607.0) + 1.0;
        } else {
            g_markov_ctx_syn1_id = 0.0;
        }

        if (g_ctx_prev_hash != 17.0 && (g_ctx_prev_syn > 0.0 || cur_syn > 0.0)) {
            var eff_p1 = g_ctx_prev_hash;
            if (g_ctx_prev_syn > 0.0) { eff_p1 = g_ctx_prev_syn; }
            var eff_c1 = patch_hash;
            if (cur_syn > 0.0) { eff_c1 = cur_syn; }
            g_markov_ctx_syn2_id = math_mod_val(eff_p1 * 257.0 + eff_c1, 8388607.0) + 1.0;
        } else {
            g_markov_ctx_syn2_id = 0.0;
        }

        if (g_ctx_prev2_hash != 17.0 && g_ctx_prev_hash != 17.0 && (g_ctx_sent_topic_syn > 0.0 || g_ctx_prev2_syn > 0.0 || g_ctx_prev_syn > 0.0 || cur_syn > 0.0)) {
            var eff_top = g_ctx_sent_topic_hash;
            if (g_ctx_sent_topic_syn > 0.0) { eff_top = g_ctx_sent_topic_syn; }
            var eff_p2 = g_ctx_prev2_hash;
            if (g_ctx_prev2_syn > 0.0) { eff_p2 = g_ctx_prev2_syn; }
            var eff_p1b = g_ctx_prev_hash;
            if (g_ctx_prev_syn > 0.0) { eff_p1b = g_ctx_prev_syn; }
            var eff_c1b = patch_hash;
            if (cur_syn > 0.0) { eff_c1b = cur_syn; }
            let sh_top2 = math_mod_val(eff_top * 13331.0 + eff_p2, 8388607.0);
            let sh23 = math_mod_val(sh_top2 * 257.0 + eff_p1b, 8388607.0);
            g_markov_ctx_syn3_id = math_mod_val(sh23 * 257.0 + eff_c1b, 8388607.0) + 1.0;
        } else {
            g_markov_ctx_syn3_id = 0.0;
        }
    }
}

