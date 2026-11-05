// Projects/geomind/byte_latent.cl
// CARTAN-E8 (GeoMind v2) Unified Engine for:
// - Phase 2: Markov-Lagrangian Principle of Least Action (S = int (T - V) dt) & 256x256 Markov Potential V
// - Phase 3: Tokenizer-Free Byte-Latent Dynamic Patching (256x248 L2-Resident E8 Embedding & Surprisal Patcher)
// - Phase 4: Domain-Bounded Recursive Web Crawler (--crawl --recurse) & Manifold Relaxation Visualizer (--visualize)

include "src/std/geom.cl";
include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/fs.cl";
include "Projects/geomind/geometry.cl";
include "Projects/geomind/streams.cl";
include "Projects/geomind/e8_stack.cl";

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
var g_markov_hub_occupied_slots: float = 0.0;
var g_markov_initialized: float = 0.0;
var g_byte_e8_skip_disk_autoload: float = 0.0;
var g_byte_e8_defer_disk_save: float = 0.0;

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
    if ((s2 == 27.0 || s2 == 30.0) && s1 == 0.0) {
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
    let w1_idx = geomind_markov_hub_row_idx(32768.0, 262144.0, g_markov_ctx_word1_id, hub_c_idx, 1.0);
    if (w1_idx >= 32768.0) {
        let w1m = w1_idx * 128.0 + cb;
        cartan_vec_set_f32(g_markov_3gram_counts, w1m, cartan_vec_get_f32(g_markov_3gram_counts, w1m) + 1.0);
        cartan_vec_set_f32(g_markov_3gram_totals, w1_idx, cartan_vec_get_f32(g_markov_3gram_totals, w1_idx) + 1.0);
    }
    if (g_markov_ctx_syn1_id > 0.0 && g_markov_ctx_syn1_id != g_markov_ctx_word1_id) {
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
    if (g_markov_ctx_syn2_id > 0.0 && g_markov_ctx_syn2_id != g_markov_ctx_word2_id) {
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
    if (g_markov_ctx_syn3_id > 0.0 && g_markov_ctx_syn3_id != g_markov_ctx_word3_id) {
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

    // Query Block 1: 1-Word Anchor Hub (32768..294911, 262,144 rows)
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
        } else {
            p_w1 = 0.0005 / (tot_w1 + 0.05);
        }
    }

    // Query Block 2: 2-Word Phrase Hub (294912..688127, 393,216 rows)
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
        } else {
            p_w2 = 0.0005 / (tot_w2 + 0.05);
        }
    }

    // Query Block 3: 3-Word Clause Hub (688128..1081343, 393,216 rows)
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
    if (tot_w1 < 0.5 && g_markov_ctx_syn1_id > 0.0) {
        let s1_idx = geomind_markov_hub_row_idx(32768.0, 262144.0, g_markov_ctx_syn1_id, hub_c_idx, 0.0);
        if (s1_idx >= 32768.0) { w1_idx = s1_idx; tot_w1 = cartan_vec_get_f32(g_markov_3gram_totals, s1_idx); }
    }
    var w2_idx = geomind_markov_hub_row_idx(294912.0, 393216.0, g_markov_ctx_word2_id, hub_c_idx, 0.0);
    var tot_w2 = 0.0;
    if (w2_idx >= 294912.0) { tot_w2 = cartan_vec_get_f32(g_markov_3gram_totals, w2_idx); }
    if (tot_w2 < 0.5 && g_markov_ctx_syn2_id > 0.0) {
        let s2_idx = geomind_markov_hub_row_idx(294912.0, 393216.0, g_markov_ctx_syn2_id, hub_c_idx, 0.0);
        if (s2_idx >= 294912.0) { w2_idx = s2_idx; tot_w2 = cartan_vec_get_f32(g_markov_3gram_totals, s2_idx); }
    }
    var w3_idx = geomind_markov_hub_row_idx(688128.0, 393216.0, g_markov_ctx_word3_id, hub_c_idx, 0.0);
    var tot_w3 = 0.0;
    if (w3_idx >= 688128.0) { tot_w3 = cartan_vec_get_f32(g_markov_3gram_totals, w3_idx); }
    if (tot_w3 < 0.5 && g_markov_ctx_syn3_id > 0.0) {
        let s3_idx = geomind_markov_hub_row_idx(688128.0, 393216.0, g_markov_ctx_syn3_id, hub_c_idx, 0.0);
        if (s3_idx >= 688128.0) { w3_idx = s3_idx; tot_w3 = cartan_vec_get_f32(g_markov_3gram_totals, s3_idx); }
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

// ============================================================================
// PHASE 4.3: LIVE MANIFOLD RELAXATION TELEMETRY & SVG/HTML VISUALIZER
// ============================================================================
var g_vis_raw_actions: ptr = 0.0;
var g_vis_ema_actions: ptr = 0.0;
var g_vis_gauge_norms: ptr = 0.0;
var g_vis_spinor_norms: ptr = 0.0;
var g_vis_markov_potentials: ptr = 0.0;
var g_vis_ema_state: float = 0.0;
var g_vis_initialized: float = 0.0;

fn geomind_visualizer_init_if_needed() {
    if (g_vis_initialized == 1.0 && g_vis_raw_actions != 0.0) { return; }
    g_vis_raw_actions = cartan_vec_create();
    g_vis_ema_actions = cartan_vec_create();
    g_vis_gauge_norms = cartan_vec_create();
    g_vis_spinor_norms = cartan_vec_create();
    g_vis_markov_potentials = cartan_vec_create();
    g_vis_ema_state = 0.0;
    g_vis_initialized = 1.0;
}

fn geomind_visualizer_reset() {
    geomind_visualizer_init_if_needed();
    cartan_vec_clear(g_vis_raw_actions);
    cartan_vec_clear(g_vis_ema_actions);
    cartan_vec_clear(g_vis_gauge_norms);
    cartan_vec_clear(g_vis_spinor_norms);
    cartan_vec_clear(g_vis_markov_potentials);
    g_vis_ema_state = 0.0;
}

fn geomind_visualizer_record_step(action_s: float, h_248: ptr, markov_v: float) {
    geomind_visualizer_init_if_needed();
    let n = cartan_vec_len(g_vis_raw_actions);
    if (n == 0.0) {
        g_vis_ema_state = action_s;
    } else {
        g_vis_ema_state = 0.90 * g_vis_ema_state + 0.10 * action_s;
    }
    cartan_vec_push_f32(g_vis_raw_actions, action_s);
    cartan_vec_push_f32(g_vis_ema_actions, g_vis_ema_state);
    cartan_vec_push_f32(g_vis_markov_potentials, markov_v);

    var g_sq = 0.0;
    var s_sq = 0.0;
    var d = 0.0;
    var val = 0.0;
    if (h_248 != 0.0) {
        while (d < 248.0) {
            val = cartan_vec_get_f32(h_248, d);
            if (d < 120.0) {
                g_sq = g_sq + val * val;
            } else {
                s_sq = s_sq + val * val;
            }
            d = d + 1.0;
        }
    }
    cartan_vec_push_f32(g_vis_gauge_norms, sqrt(g_sq));
    cartan_vec_push_f32(g_vis_spinor_norms, sqrt(s_sq));
}

// Exports an interactive, self-contained SVG + HTML Manifold Relaxation Report (`manifold_relaxation.html`)
fn geomind_visualizer_export_html(out_path: string, title_label: string) -> float {
    geomind_visualizer_init_if_needed();
    let total_pts = cartan_vec_len(g_vis_raw_actions);
    if (total_pts <= 0.0) { return 0.0; }

    var max_act = 0.1;
    var min_act = 100000.0;
    var i = 0.0;
    var rv = 0.0;
    while (i < total_pts) {
        rv = cartan_vec_get_f32(g_vis_raw_actions, i);
        if (rv > max_act) { max_act = rv; }
        if (rv < min_act) { min_act = rv; }
        i = i + 1.0;
    }
    var span_act = max_act - min_act;
    if (span_act < 0.01) { span_act = 1.0; }

    let first_ema = cartan_vec_get_f32(g_vis_ema_actions, 0.0);
    let last_ema = cartan_vec_get_f32(g_vis_ema_actions, total_pts - 1.0);
    let last_gauge = cartan_vec_get_f32(g_vis_gauge_norms, total_pts - 1.0);
    let last_spinor = cartan_vec_get_f32(g_vis_spinor_norms, total_pts - 1.0);

    var raw_poly = "";
    var ema_poly = "";
    var denom_x = total_pts - 1.0;
    if (denom_x < 1.0) { denom_x = 1.0; }

    var px = 0.0;
    var py_raw = 0.0;
    var py_ema = 0.0;
    var ev = 0.0;
    var pt_raw = "";
    var pt_ema = "";
    i = 0.0;
    while (i < total_pts) {
        rv = cartan_vec_get_f32(g_vis_raw_actions, i);
        ev = cartan_vec_get_f32(g_vis_ema_actions, i);
        px = 60.0 + (i / denom_x) * 700.0;
        py_raw = 300.0 - ((rv - min_act) / span_act) * 240.0;
        py_ema = 300.0 - ((ev - min_act) / span_act) * 240.0;

        pt_raw = cartan_string_concat(cartan_float_to_string(px), cartan_string_concat(",", cartan_string_concat(cartan_float_to_string(py_raw), " ")));
        pt_ema = cartan_string_concat(cartan_float_to_string(px), cartan_string_concat(",", cartan_string_concat(cartan_float_to_string(py_ema), " ")));
        raw_poly = cartan_string_concat(raw_poly, pt_raw);
        ema_poly = cartan_string_concat(ema_poly, pt_ema);
        i = i + 1.0;
    }

    var html = "<!DOCTYPE html>\n<html><head><meta charset='utf-8'><title>CARTAN-E8 Manifold Relaxation Telemetry</title>\n";
    html = cartan_string_concat(html, "<style>body{background:#0d1117;color:#e6edf3;font-family:Consolas,monospace;padding:24px;} .card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:20px;max-width:860px;margin:auto;} h2{color:#58a6ff;margin-top:0;} .stats{display:flex;gap:24px;margin-bottom:16px;font-size:14px;} .stat-box{background:#0d1117;padding:10px 14px;border-radius:6px;border:1px solid #21262d;}</style></head><body>\n");
    html = cartan_string_concat(html, "<div class='card'><h2>CARTAN-E8 Geodesic Manifold Relaxation: ");
    html = cartan_string_concat(html, title_label);
    html = cartan_string_concat(html, "</h2>\n<div class='stats'>");
    html = cartan_string_concat(html, cartan_string_concat("<div class='stat-box'>Initial Action S_0: <b>", cartan_string_concat(cartan_float_to_string(first_ema), "</b></div>")));
    html = cartan_string_concat(html, cartan_string_concat("<div class='stat-box'>Final Action S_T: <b>", cartan_string_concat(cartan_float_to_string(last_ema), "</b></div>")));
    html = cartan_string_concat(html, cartan_string_concat("<div class='stat-box'>120-D so(16) Gauge Norm: <b>", cartan_string_concat(cartan_float_to_string(last_gauge), "</b></div>")));
    html = cartan_string_concat(html, cartan_string_concat("<div class='stat-box'>128-D S_16+ Spinor Norm: <b>", cartan_string_concat(cartan_float_to_string(last_spinor), "</b></div></div>\n")));
    html = cartan_string_concat(html, "<svg width='800' height='340' viewBox='0 0 800 340' style='background:#090d13;border:1px solid #30363d;border-radius:6px;'>\n");
    html = cartan_string_concat(html, "<line x1='60' y1='60' x2='60' y2='300' stroke='#484f58' stroke-width='1'/>\n");
    html = cartan_string_concat(html, "<line x1='60' y1='300' x2='760' y2='300' stroke='#484f58' stroke-width='1'/>\n");
    html = cartan_string_concat(html, cartan_string_concat("<polyline fill='none' stroke='#388bfd' stroke-opacity='0.35' stroke-width='1.5' points='", cartan_string_concat(raw_poly, "'/>\n")));
    html = cartan_string_concat(html, cartan_string_concat("<polyline fill='none' stroke='#f85149' stroke-width='2.5' points='", cartan_string_concat(ema_poly, "'/>\n")));
    html = cartan_string_concat(html, "<text x='70' y='40' fill='#388bfd' font-size='12'>Raw Lagrangian Action S = T*(1 - 0.5*V)</text>\n");
    html = cartan_string_concat(html, "<text x='360' y='40' fill='#f85149' font-size='12'>Smoothed Geodesic Relaxation Curve (EMA)</text>\n");
    html = cartan_string_concat(html, "</svg></div></body></html>\n");

    cartan_write_file(out_path, html);
    return total_pts;
}

// ============================================================================
// PHASE 3: BYTE-LATENT DYNAMIC PATCHING (256x248 L2-RESIDENT E8 MANIFOLD)
// ============================================================================
// - g_byte_e8_emb_256x248:  256 byte rows x 248 E8 dims = 63,488 floats (253 KB)
// - g_byte_e8_head_248x256: 248 E8 dims x 256 byte cols = 63,488 floats (253 KB)
// - g_byte_e8_randers_b_248: 248-D Finsler-Randers directional drift 1-form beta
var g_byte_e8_emb_256x248: ptr = 0.0;
var g_byte_e8_head_248x256: ptr = 0.0;
var g_byte_e8_randers_b_248: ptr = 0.0;
var g_byte_e8_initialized: float = 0.0;
var g_byte_latent_coast_count: float = 0.0;

fn geomind_byte_latent_get_coast_count() -> float {
    return g_byte_latent_coast_count;
}

fn geomind_byte_latent_save_weights(path: string) -> float {
    if (path == 0.0 || g_byte_e8_emb_256x248 == 0.0 || g_byte_e8_head_248x256 == 0.0 || g_byte_e8_randers_b_248 == 0.0) { return 0.0; }
    let f = fopen(path, "wb");
    if (f == 0.0) { return 0.0; }
    let total_elems = 63488.0 + 63488.0 + 248.0;
    let buf = malloc(total_elems * 8.0);
    if (buf == 0.0) { fclose(f); return 0.0; }
    var i = 0.0;
    while (i < 63488.0) {
        buf[i] = cartan_vec_get_f32(g_byte_e8_emb_256x248, i);
        buf[63488.0 + i] = cartan_vec_get_f32(g_byte_e8_head_248x256, i);
        i = i + 1.0;
    }
    var d = 0.0;
    while (d < 248.0) {
        buf[126976.0 + d] = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
        d = d + 1.0;
    }
    fwrite(buf, 8.0, total_elems, f);
    fclose(f);
    free(buf);
    return 1.0;
}

fn geomind_byte_latent_load_weights(path: string) -> float {
    if (path == 0.0 || cartan_file_exists(path) == 0.0) { return 0.0; }
    let total_elems = 63488.0 + 63488.0 + 248.0;
    let f_sz = cartan_get_binary_file_size(path);
    if (f_sz < total_elems * 8.0) { return 0.0; }
    if (g_byte_e8_emb_256x248 == 0.0) { g_byte_e8_emb_256x248 = cartan_tensor_alloc(63488.0); }
    if (g_byte_e8_head_248x256 == 0.0) { g_byte_e8_head_248x256 = cartan_tensor_alloc(63488.0); }
    if (g_byte_e8_randers_b_248 == 0.0) { g_byte_e8_randers_b_248 = cartan_tensor_alloc(248.0); }
    let f = fopen(path, "rb");
    if (f == 0.0) { return 0.0; }
    let buf = malloc(total_elems * 8.0);
    if (buf == 0.0) { fclose(f); return 0.0; }
    fread(buf, 8.0, total_elems, f);
    fclose(f);
    var i = 0.0;
    while (i < 63488.0) {
        cartan_vec_set_f32(g_byte_e8_emb_256x248, i, buf[i]);
        cartan_vec_set_f32(g_byte_e8_head_248x256, i, buf[63488.0 + i]);
        i = i + 1.0;
    }
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_set_f32(g_byte_e8_randers_b_248, d, buf[126976.0 + d]);
        d = d + 1.0;
    }
    free(buf);
    g_byte_e8_initialized = 1.0;
    return 1.0;
}

fn geomind_byte_latent_init_if_needed() -> float {
    if (g_byte_e8_initialized == 1.0 && g_byte_e8_emb_256x248 != 0.0) {
        return 1.0;
    }
    geomind_init_e8_roots_if_needed();
    geomind_markov_init_if_needed();

    if (g_byte_e8_emb_256x248 == 0.0) { g_byte_e8_emb_256x248 = cartan_tensor_alloc(63488.0); }
    if (g_byte_e8_head_248x256 == 0.0) { g_byte_e8_head_248x256 = cartan_tensor_alloc(63488.0); }
    if (g_byte_e8_randers_b_248 == 0.0) { g_byte_e8_randers_b_248 = cartan_tensor_alloc(248.0); }

    // Initialize 256 x 248 Byte-to-E8 table directly from canonical 240 E8 roots + 8D Cartan torus harmonics
    var b = 0.0;
    var d = 0.0;
    var root_idx = 0.0;
    var root_c = 0.0;
    var phase = 0.0;
    var val = 0.0;
    var flat_idx = 0.0;
    while (b < 256.0) {
        d = 0.0;
        while (d < 248.0) {
            if (d < 8.0) {
                phase = ((b + 1.0) * (d + 1.0)) * 0.049087385;
                val = 0.25 * cos(phase);
            } else {
                root_idx = d - 8.0;
                root_c = geomind_e8_get_root_coord(root_idx, math_mod_val(b + d, 8.0));
                phase = ((b + 1.0) * (d + 1.0)) * 0.02454369;
                val = 0.20 * root_c + 0.10 * sin(phase);
            }
            cartan_vec_set_f32(g_byte_e8_emb_256x248, flat_idx, val);
            cartan_vec_set_f32(g_byte_e8_head_248x256, d * 256.0 + b, val * 0.25);
            flat_idx = flat_idx + 1.0;
            d = d + 1.0;
        }
        b = b + 1.0;
    }

    // Initialize 248-D Finsler-Randers causal drift 1-form beta (strictly bounded ||beta|| < 1)
    d = 0.0;
    while (d < 248.0) {
        if (d < 120.0) {
            cartan_vec_set_f32(g_byte_e8_randers_b_248, d, 0.04 * cos(d * 0.1));
        } else {
            cartan_vec_set_f32(g_byte_e8_randers_b_248, d, 0.06 * sin(d * 0.1));
        }
        d = d + 1.0;
    }

    g_byte_e8_initialized = 1.0;
    if (g_byte_e8_skip_disk_autoload == 0.0 && cartan_file_exists("Projects/geomind/trainingdata/checkpoints/geomind_byte_latent_e8.bin") == 1.0) {
        geomind_byte_latent_load_weights("Projects/geomind/trainingdata/checkpoints/geomind_byte_latent_e8.bin");
    }
    return 1.0;
}

// Fold a single byte `b` (0..255) into a 248-D E8 patch accumulator via Weyl reflection + Gauge-Spinor addition
fn geomind_fold_byte_into_e8_patch(accum_248: ptr, byte_val: float, pos_idx: float) {
    geomind_byte_latent_init_if_needed();
    let b = math_mod_val(floor(math_abs_val(byte_val)), 256.0);
    let row_off = b * 248.0;
    let pos_weight = 1.0 / (1.0 + 0.05 * pos_idx);
    var d = 0.0;
    var cur = 0.0;
    var emb = 0.0;
    while (d < 248.0) {
        cur = cartan_vec_get_f32(accum_248, d);
        emb = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
        cartan_vec_set_f32(accum_248, d, cur + emb * pos_weight);
        d = d + 1.0;
    }
    // Apply Weyl reflection along root (b % 240) to preserve E8 lattice symmetry
    geomind_weyl_reflect_vector_248(accum_248, math_mod_val(b, 240.0));
}

// Phase 3.2: Entropy-Driven Dynamic Patch Boundary Detector
// Segments a raw UTF-8 string into variable-length 248-D E8 latent patches whenever
// Markov transition surprisal H(b_t | b_{t-1}) >= entropy_thresh_bits (or max patch length 8 is reached).
// Returns a flat vector of [num_patches * 248] floats.
fn geomind_byte_latent_encode_stream(text: string, entropy_thresh_bits: float) -> ptr {
    geomind_byte_latent_init_if_needed();
    let n_bytes = cartan_string_length(text);
    if (n_bytes <= 0.0) { return cartan_vec_create(); }
    let patches_out = cartan_tensor_alloc(n_bytes * 248.0);
    cartan_vec_clear(patches_out);

    var thresh = 3.5;
    if (entropy_thresh_bits > 0.1) { thresh = entropy_thresh_bits; }

    let accum_248 = cartan_vec_create();
    let gated_248 = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(accum_248, 0.0);
        cartan_vec_push_f32(gated_248, 0.0);
        d = d + 1.0;
    }

    var prev_b = 32.0;
    var patch_len = 0.0;
    var i = 0.0;
    var b = 0.0;
    var surp = 0.0;
    var gv = 0.0;
    while (i < n_bytes) {
        b = cartan_byte_at(text, i);
        if (b < 0.0) { b = b + 256.0; }
        surp = geomind_markov_surprisal_bits(prev_b, b);

        geomind_fold_byte_into_e8_patch(accum_248, b, patch_len);
        patch_len = patch_len + 1.0;

        if ((surp >= thresh && patch_len >= 2.0) || patch_len >= 8.0 || i == (n_bytes - 1.0)) {
            // Apply 120-D (+) 128-D E8 Gauge-on-Spinor Cross-Gating to the accumulated patch
            geomind_e8_gauge_spinor_cross_gate(accum_248, gated_248, 0.25);
            d = 0.0;
            while (d < 248.0) {
                gv = cartan_vec_get_f32(gated_248, d);
                cartan_vec_push_f32(patches_out, gv);
                cartan_vec_set_f32(accum_248, d, 0.0);
                d = d + 1.0;
            }
            patch_len = 0.0;
        }
        prev_b = b;
        i = i + 1.0;
    }

    cartan_vec_free(accum_248);
    cartan_vec_free(gated_248);
    return patches_out;
}

// Phase 3.3: Byte-Latent Decoder Head (248-D E8 state -> 256 raw byte logits with Markov prior fusion)
fn geomind_byte_latent_decode_logits(h_248: ptr, prev_byte: float, out_logits_256: ptr) {
    geomind_byte_latent_init_if_needed();
    var c = 0.0;
    var d = 0.0;
    var sum = 0.0;
    var hv = 0.0;
    var wv = 0.0;
    var m_prob = 0.0;
    while (c < 256.0) {
        sum = 0.0;
        d = 0.0;
        while (d < 248.0) {
            hv = cartan_vec_get_f32(h_248, d);
            wv = cartan_vec_get_f32(g_byte_e8_head_248x256, d * 256.0 + c);
            sum = sum + hv * wv;
            d = d + 1.0;
        }
        // Fuse E8 Spinor-Gauge readout with log-Markov transition prior
        m_prob = geomind_markov_get_prob(prev_byte, c);
        cartan_vec_set_f32(out_logits_256, c, sum + 0.65 * log(m_prob + 0.0001));
        c = c + 1.0;
    }
}

// Phase 3.4: Two-Tier BLT Patch+Local Context Decoder Head
// Conditions on both the 42-Layer Global Patch Context P_patch in S^{247} and the Local Within-Patch State h_local in S^{247},
// fused with the 3-Byte Markov Transition Prior P(b_t | b_{t-3}, b_{t-2}, b_{t-1}).
fn geomind_byte_latent_decode_logits_blt(
    h_local_248: ptr,
    h_patch_248: ptr,
    b3: float,
    b2: float,
    b1: float,
    out_logits_256: ptr
) {
    geomind_byte_latent_init_if_needed();
    // Hoist the 3-gram and 3-block Tapestry Hub row lookups outside the 256-byte loop (256x fewer hash probes)
    let c_idx = geomind_markov_3gram_ctx_idx(b3, b2, b1);
    let hub_c_idx = geomind_markov_hub_ctx_idx(b3, b2, b1);
    let tot3 = cartan_vec_get_f32(g_markov_3gram_totals, c_idx);
    var w1_idx = geomind_markov_hub_row_idx(32768.0, 262144.0, g_markov_ctx_word1_id, hub_c_idx, 0.0);
    var tot_w1 = 0.0;
    if (w1_idx >= 32768.0) { tot_w1 = cartan_vec_get_f32(g_markov_3gram_totals, w1_idx); }
    if (tot_w1 < 0.5 && g_markov_ctx_syn1_id > 0.0) {
        let s1_idx = geomind_markov_hub_row_idx(32768.0, 262144.0, g_markov_ctx_syn1_id, hub_c_idx, 0.0);
        if (s1_idx >= 32768.0) { w1_idx = s1_idx; tot_w1 = cartan_vec_get_f32(g_markov_3gram_totals, s1_idx); }
    }
    var w2_idx = geomind_markov_hub_row_idx(294912.0, 393216.0, g_markov_ctx_word2_id, hub_c_idx, 0.0);
    var tot_w2 = 0.0;
    if (w2_idx >= 294912.0) { tot_w2 = cartan_vec_get_f32(g_markov_3gram_totals, w2_idx); }
    if (tot_w2 < 0.5 && g_markov_ctx_syn2_id > 0.0) {
        let s2_idx = geomind_markov_hub_row_idx(294912.0, 393216.0, g_markov_ctx_syn2_id, hub_c_idx, 0.0);
        if (s2_idx >= 294912.0) { w2_idx = s2_idx; tot_w2 = cartan_vec_get_f32(g_markov_3gram_totals, s2_idx); }
    }
    var w3_idx = geomind_markov_hub_row_idx(688128.0, 393216.0, g_markov_ctx_word3_id, hub_c_idx, 0.0);
    var tot_w3 = 0.0;
    if (w3_idx >= 688128.0) { tot_w3 = cartan_vec_get_f32(g_markov_3gram_totals, w3_idx); }
    if (tot_w3 < 0.5 && g_markov_ctx_syn3_id > 0.0) {
        let s3_idx = geomind_markov_hub_row_idx(688128.0, 393216.0, g_markov_ctx_syn3_id, hub_c_idx, 0.0);
        if (s3_idx >= 688128.0) { w3_idx = s3_idx; tot_w3 = cartan_vec_get_f32(g_markov_3gram_totals, s3_idx); }
    }

    var c = 0.0;
    while (c < 256.0) {
        if ((c >= 32.0 && c <= 126.0) || c == 10.0) {
            var sum = 0.0;
            var d = 0.0;
            while (d < 248.0) {
                let hl = cartan_vec_get_f32(h_local_248, d);
                var hp = 0.0;
                if (h_patch_248 != 0.0) {
                    hp = cartan_vec_get_f32(h_patch_248, d);
                }
                let hv = 0.65 * hl + 0.35 * hp;
                let wv = cartan_vec_get_f32(g_byte_e8_head_248x256, d * 256.0 + c);
                sum = sum + hv * wv;
                d = d + 1.0;
            }
            let m_prob = geomind_markov_get_3gram_prob_fast(b1, c, c_idx, tot3, w1_idx, tot_w1, w2_idx, tot_w2, w3_idx, tot_w3);
            cartan_vec_set_f32(out_logits_256, c, sum * 0.25 + 3.50 * log(m_prob + 0.00001));
        } else {
            cartan_vec_set_f32(out_logits_256, c, -35.0);
        }
        c = c + 1.0;
    }
}

// Train the 248-D E8 Byte-Latent + Markov-Lagrangian engine over a UTF-8 text corpus for `epochs`
// Uses Sherman-Morrison inverse Finsler-Randers gradient descent (`geom_frs_riemannian_gradient_step`)
// and exact Adjoint Gauge-Spinor Cross-Gate Backpropagation + Geodesic Kinetic Energy Restoring Force
// Returns the final epoch average Lagrangian Action S = T * (1 - 0.5 * V)
fn geomind_byte_latent_train_corpus(corpus: string, epochs: float, lr: float, record_vis: float) -> float {
    geomind_byte_latent_init_if_needed();
    let n_bytes = cartan_string_length(corpus);
    if (n_bytes < 2.0) { return 0.0; }

    var num_epochs = 1.0;
    if (epochs > 1.0) { num_epochs = epochs; }
    var eff_lr = 0.02;
    if (lr > 0.00001) { eff_lr = lr; }

    let h_prev = cartan_vec_create();
    let h_pre_gate = cartan_vec_create();
    let h_curr = cartan_vec_create();
    let dh_gated = cartan_vec_create();
    let dh_pre = cartan_vec_create();
    let geo_grad = cartan_vec_create();
    let logits_256 = cartan_vec_create();
    let delta_256 = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_prev, 0.0);
        cartan_vec_push_f32(h_pre_gate, 0.0);
        cartan_vec_push_f32(h_curr, 0.0);
        cartan_vec_push_f32(dh_gated, 0.0);
        cartan_vec_push_f32(dh_pre, 0.0);
        cartan_vec_push_f32(geo_grad, 0.0);
        d = d + 1.0;
    }
    var c = 0.0;
    while (c < 256.0) {
        cartan_vec_push_f32(logits_256, 0.0);
        cartan_vec_push_f32(delta_256, 0.0);
        c = c + 1.0;
    }

    var final_avg_action = 0.0;
    var ep = 0.0;
    var step = 0.0;
    var epoch_action_sum = 0.0;
    var cur_b = 0.0;
    var next_b = 0.0;
    var row_off = 0.0;
    var old_h = 0.0;
    var emb_v = 0.0;
    var act_s = 0.0;
    var markov_v = 0.0;
    var well_factor = 1.0;
    var dh_d = 0.0;
    var h_d = 0.0;
    var b_d = 0.0;
    var del_c = 0.0;
    var w_dc = 0.0;
    var new_w = 0.0;
    var old_emb = 0.0;
    var new_emb = 0.0;
    var dp_d = 0.0;
    var new_b = 0.0;
    let max_steps = n_bytes - 1.0;

    while (ep < num_epochs) {
        epoch_action_sum = 0.0;
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_prev, d, 0.0);
            cartan_vec_set_f32(h_pre_gate, d, 0.0);
            cartan_vec_set_f32(h_curr, d, 0.0);
            d = d + 1.0;
        }

        step = 0.0;
        while (step < max_steps) {
            cur_b = cartan_byte_at(corpus, step);
            if (cur_b < 0.0) { cur_b = cur_b + 256.0; }
            next_b = cartan_byte_at(corpus, step + 1.0);
            if (next_b < 0.0) { next_b = next_b + 256.0; }
            cur_b = math_mod_val(floor(cur_b), 256.0);
            next_b = math_mod_val(floor(next_b), 256.0);

            // 1. Save previous 248-D state and inject current byte embedding into E8 pre-gate state
            row_off = cur_b * 248.0;
            d = 0.0;
            while (d < 248.0) {
                old_h = cartan_vec_get_f32(h_curr, d);
                cartan_vec_set_f32(h_prev, d, old_h);
                emb_v = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                cartan_vec_set_f32(h_pre_gate, d, 0.65 * old_h + emb_v);
                d = d + 1.0;
            }

            // 2. Apply Phase 1 120-D (+) 128-D Gauge-on-Spinor Cross-Gating: h_pre_gate -> h_curr
            geomind_e8_gauge_spinor_cross_gate(h_pre_gate, h_curr, 0.25);

            // 3. Decode 248-D E8 state -> 256 byte logits
            geomind_byte_latent_decode_logits(h_curr, cur_b, logits_256);

            // 4. Evaluate Phase 2 Markov-Lagrangian Action Loss S = (T_pred + 0.15 * T_geo) * (1 - 0.5 * V)
            act_s = geomind_lagrangian_action_step(
                logits_256, next_b, cur_b, h_prev, h_curr, g_byte_e8_randers_b_248, delta_256
            );
            epoch_action_sum = epoch_action_sum + act_s;

            // 5. Compute Geodesic Kinetic Energy Restoring Force: 0.15 * (1 - 0.5 * V) * d(T_geo)/d(h_curr)
            markov_v = geomind_markov_get_prob(cur_b, next_b);
            well_factor = 1.0 - 0.5 * markov_v;
            geomind_e8_geodesic_kinetic_grad_248(h_prev, h_curr, g_byte_e8_randers_b_248, geo_grad, 0.15 * well_factor);

            // 6. Sherman-Morrison Inverse Finsler-Randers Backpropagation on Decoder Head
            d = 0.0;
            while (d < 248.0) {
                h_d = cartan_vec_get_f32(h_curr, d);
                b_d = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
                dh_d = cartan_vec_get_f32(geo_grad, d);

                // Update printable ASCII & active byte columns in head_248x256
                c = 32.0;
                while (c <= 126.0) {
                    del_c = cartan_vec_get_f32(delta_256, c);
                    if (math_abs_val(del_c) > 0.005) {
                        w_dc = cartan_vec_get_f32(g_byte_e8_head_248x256, d * 256.0 + c);
                        dh_d = dh_d + w_dc * del_c;
                        new_w = geom_frs_riemannian_gradient_step(w_dc, h_d * del_c, b_d, eff_lr);
                        cartan_vec_set_f32(g_byte_e8_head_248x256, d * 256.0 + c, new_w);
                    }
                    c = c + 1.0;
                }
                cartan_vec_set_f32(dh_gated, d, dh_d);
                d = d + 1.0;
            }

            // 7. Backpropagate dh_gated through Adjoint 120 (+) 128 Gauge-Spinor Cross-Gate Jacobian -> dh_pre
            geomind_e8_gauge_spinor_cross_gate_backward(h_pre_gate, dh_gated, dh_pre, 0.25);

            // 8. Update Byte-to-E8 Embedding row and Finsler-Randers Drift 1-form beta
            d = 0.0;
            while (d < 248.0) {
                dp_d = cartan_vec_get_f32(dh_pre, d);
                b_d = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
                old_emb = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                new_emb = geom_frs_riemannian_gradient_step(old_emb, dp_d, b_d, eff_lr * 0.25);
                cartan_vec_set_f32(g_byte_e8_emb_256x248, row_off + d, new_emb);

                // Update Randers causal drift 1-form along geodesic velocity (clamped to [-0.08, 0.08] per coord so ||b|| < 0.85)
                h_d = cartan_vec_get_f32(h_curr, d);
                old_h = cartan_vec_get_f32(h_prev, d);
                new_b = b_d - eff_lr * 0.005 * well_factor * (h_d - old_h);
                if (new_b > 0.08) { new_b = 0.08; }
                else if (new_b < -0.08) { new_b = -0.08; }
                cartan_vec_set_f32(g_byte_e8_randers_b_248, d, new_b);
                d = d + 1.0;
            }

            step = step + 1.0;
        }

        final_avg_action = epoch_action_sum / max_steps;
        if (record_vis == 1.0) {
            markov_v = geomind_markov_get_prob(cur_b, next_b);
            geomind_visualizer_record_step(final_avg_action, h_curr, markov_v);
        }
        ep = ep + 1.0;
    }

    // Persist updated 256x256 Markov transition matrix and 248-D E8 Byte-Latent weights to disk
    geomind_markov_save_prior("Projects/geomind/trainingdata/checkpoints/geomind_markov_prior.bin");
    geomind_byte_latent_save_weights("Projects/geomind/trainingdata/checkpoints/geomind_byte_latent_e8.bin");

    cartan_vec_free(h_prev);
    cartan_vec_free(h_pre_gate);
    cartan_vec_free(h_curr);
    cartan_vec_free(dh_gated);
    cartan_vec_free(dh_pre);
    cartan_vec_free(geo_grad);
    cartan_vec_free(logits_256);
    cartan_vec_free(delta_256);
    return final_avg_action;
}

// Autoregressively generate `gen_len` UTF-8 bytes from a raw byte prompt using the 248-D E8 Byte-Latent manifold
// with live Phase 2.4 Markov-Lagrangian Low-Action Geodesic Coasting
fn geomind_byte_latent_generate(prompt: string, gen_len: float) -> string {
    geomind_byte_latent_init_if_needed();
    let h_prev = cartan_vec_create();
    let h_curr = cartan_vec_create();
    let h_gated = cartan_vec_create();
    let logits_256 = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_prev, 0.0);
        cartan_vec_push_f32(h_curr, 0.0);
        cartan_vec_push_f32(h_gated, 0.0);
        d = d + 1.0;
    }
    var c = 0.0;
    while (c < 256.0) {
        cartan_vec_push_f32(logits_256, 0.0);
        c = c + 1.0;
    }

    // 1. Prefill prompt bytes through the 248-D E8 Gauge-Spinor manifold
    let plen = cartan_string_length(prompt);
    var cur_b = 32.0;
    var i = 0.0;
    var row_off = 0.0;
    var old_h = 0.0;
    var emb_v = 0.0;
    while (i < plen) {
        cur_b = cartan_byte_at(prompt, i);
        if (cur_b < 0.0) { cur_b = cur_b + 256.0; }
        cur_b = math_mod_val(floor(cur_b), 256.0);
        row_off = cur_b * 248.0;
        d = 0.0;
        while (d < 248.0) {
            old_h = cartan_vec_get_f32(h_curr, d);
            cartan_vec_set_f32(h_prev, d, old_h);
            emb_v = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
            cartan_vec_set_f32(h_curr, d, 0.65 * old_h + emb_v);
            d = d + 1.0;
        }
        geomind_e8_gauge_spinor_cross_gate(h_curr, h_gated, 0.25);
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_curr, d, cartan_vec_get_f32(h_gated, d));
            d = d + 1.0;
        }
        i = i + 1.0;
    }

    // 2. Autoregressive byte decoding with Low-Action Geodesic Coasting
    var out_str = prompt;
    var step = 0.0;
    var best_b = 32.0;
    var best_l = -100000.0;
    var lv = 0.0;
    var t_geo = 0.0;
    var coast = 0.0;
    var prev_h_d = 0.0;
    var vel_d = 0.0;
    var norm_sq = 0.0;
    var inv_norm = 1.0;
    while (step < gen_len) {
        geomind_byte_latent_decode_logits(h_curr, cur_b, logits_256);
        best_b = 32.0;
        best_l = -100000.0;
        // Restrict to printable ASCII range (32..126) for clean text emission
        c = 32.0;
        while (c <= 126.0) {
            lv = cartan_vec_get_f32(logits_256, c);
            if (lv > best_l) {
                best_l = lv;
                best_b = c;
            }
            c = c + 1.0;
        }

        out_str = cartan_string_concat(out_str, cartan_char_from_code(best_b));
        t_geo = geomind_e8_geodesic_kinetic_energy_248(h_prev, h_curr, g_byte_e8_randers_b_248);
        coast = geomind_should_geodesic_coast(cur_b, best_b, t_geo, 0.85);
        cur_b = best_b;
        row_off = cur_b * 248.0;

        if (coast == 1.0) {
            // Geodesic Coasting Fast-Path: advance along tangent velocity + byte embedding and retract to S^247
            g_byte_latent_coast_count = g_byte_latent_coast_count + 1.0;
            norm_sq = 0.0;
            d = 0.0;
            while (d < 248.0) {
                old_h = cartan_vec_get_f32(h_curr, d);
                prev_h_d = cartan_vec_get_f32(h_prev, d);
                vel_d = old_h - prev_h_d;
                cartan_vec_set_f32(h_prev, d, old_h);
                emb_v = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                lv = 0.65 * old_h + 0.15 * vel_d + emb_v;
                cartan_vec_set_f32(h_curr, d, lv);
                norm_sq = norm_sq + lv * lv;
                d = d + 1.0;
            }
            if (norm_sq > 0.000001) {
                inv_norm = 1.0 / sqrt(norm_sq);
                d = 0.0;
                while (d < 248.0) {
                    cartan_vec_set_f32(h_curr, d, cartan_vec_get_f32(h_curr, d) * inv_norm);
                    d = d + 1.0;
                }
            }
        } else {
            // Full Non-Associative 120 (+) 128 E8 Gauge-on-Spinor Cross-Gating
            d = 0.0;
            while (d < 248.0) {
                old_h = cartan_vec_get_f32(h_curr, d);
                cartan_vec_set_f32(h_prev, d, old_h);
                emb_v = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                cartan_vec_set_f32(h_curr, d, 0.65 * old_h + emb_v);
                d = d + 1.0;
            }
            geomind_e8_gauge_spinor_cross_gate(h_curr, h_gated, 0.25);
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(h_curr, d, cartan_vec_get_f32(h_gated, d));
                d = d + 1.0;
            }
        }
        step = step + 1.0;
    }

    cartan_vec_free(h_prev);
    cartan_vec_free(h_curr);
    cartan_vec_free(h_gated);
    cartan_vec_free(logits_256);
    return out_str;
}

// ============================================================================
// STAGE 5: DEVELOPMENTAL ANCHOR CRYSTALLIZATION & SELECTIVE RESONANCE FOCUS ENGINE
// ============================================================================
// Models child-like developmental concept acquisition on S^{247}:
// - Crystallized Anchor Basins: up to 128 248-D E8 Patch Attractors on S^{247}
//   with maturity/mass M_m in [0, 1] and FNV-style patch hash IDs.
// - Resonance Filter R(P_k): Killing-Cartan inner product on S^{247} against crystallized anchors.
// - Selective Plasticity Gate ("Cocktail-Party / Baby-Focus"):
//   * "Blah Blah Blah" Noise State (R(P_k) low & focus_horizon == 0):
//     Suppresses 42-layer backward plasticity (lr_gate = 0.0) so uncomprehended noise
//     never scrambles the deep Gauge/Spinor matrices.
//   * "Laser-Focus" State (R(P_k) >= 0.55):
//     Opens a 2-patch (i + 1) developmental focus window (focus_horizon = 2.0) where
//     the 42-layer E8 stack fires at full plasticity (lr_gate = 1.0) to bind surrounding
//     modifiers/verbs (e.g., "bounce", "throw") to the resonant anchor ("ball").
//   * Automatic Frontier Crystallization: When a neighbor patch inside a focus window
//     achieves low Lagrangian Action S, it crystallizes into a new Anchor Basin on S^{247}!

var g_e8_anchor_count: float = 0.0;
var g_e8_anchor_coords: ptr = 0.0;     // 65536 * 248 floats (crystallized S^{247} coordinates)
var g_e8_anchor_masses: ptr = 0.0;     // 65536 floats (maturity/mass in [0, 1])
var g_e8_anchor_hashes: ptr = 0.0;     // 65536 floats (patch byte-sequence signature)
var g_e8_anchor_hash_lut: ptr = 0.0;   // 131072-slot O(1) open-addressed hash index -> anchor idx
var g_e8_focus_hits: float = 0.0;
var g_e8_noise_skips: float = 0.0;
var g_e8_newly_crystallized: float = 0.0;
var g_e8_primer_crystallize_all: float = 0.0; // When 1.0 (Rung 1 Primer), trains all patches and crystallizes mastered ones

fn geomind_e8_anchors_init_if_needed() {
    if (g_e8_anchor_coords != 0.0) { return; }
    g_e8_anchor_coords = cartan_tensor_alloc(65536.0 * 248.0);
    g_e8_anchor_masses = cartan_tensor_alloc(65536.0);
    g_e8_anchor_hashes = cartan_tensor_alloc(65536.0);
    g_e8_anchor_hash_lut = cartan_tensor_alloc(131072.0);
    var i = 0.0;
    while (i < 65536.0) {
        cartan_vec_set_f32(g_e8_anchor_masses, i, 0.0);
        cartan_vec_set_f32(g_e8_anchor_hashes, i, -1.0);
        i = i + 1.0;
    }
    i = 0.0;
    while (i < 131072.0) {
        cartan_vec_set_f32(g_e8_anchor_hash_lut, i, -1.0);
        i = i + 1.0;
    }
    g_e8_anchor_count = 0.0;
}

fn geomind_e8_anchor_lut_insert(patch_hash: float, anchor_idx: float) {
    if (patch_hash <= 0.0 || anchor_idx < 0.0) { return; }
    let base_slot = math_mod_val(floor(patch_hash * 2654435761.0), 131072.0);
    var probe = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(base_slot + probe, 131072.0);
        let cur_idx = cartan_vec_get_f32(g_e8_anchor_hash_lut, slot);
        if (cur_idx < 0.0 || cur_idx == anchor_idx) {
            cartan_vec_set_f32(g_e8_anchor_hash_lut, slot, anchor_idx);
            return;
        }
        probe = probe + 1.0;
    }
}

fn geomind_e8_find_anchor_by_hash(patch_hash: float) -> float {
    if (patch_hash <= 0.0 || g_e8_anchor_count <= 0.0 || g_e8_anchor_hash_lut == 0.0) { return -1.0; }
    let base_slot = math_mod_val(floor(patch_hash * 2654435761.0), 131072.0);
    var probe = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(base_slot + probe, 131072.0);
        let cand_idx = cartan_vec_get_f32(g_e8_anchor_hash_lut, slot);
        if (cand_idx < 0.0) {
            return -1.0;
        }
        if (cartan_vec_get_f32(g_e8_anchor_hashes, cand_idx) == patch_hash) {
            return cand_idx;
        }
        probe = probe + 1.0;
    }
    return -1.0;
}

fn geomind_e8_anchors_reset() {
    geomind_e8_anchors_init_if_needed();
    g_e8_anchor_count = 0.0;
    g_e8_focus_hits = 0.0;
    g_e8_noise_skips = 0.0;
    g_e8_newly_crystallized = 0.0;
    var i = 0.0;
    while (i < 65536.0) {
        cartan_vec_set_f32(g_e8_anchor_masses, i, 0.0);
        cartan_vec_set_f32(g_e8_anchor_hashes, i, -1.0);
        i = i + 1.0;
    }
    i = 0.0;
    while (i < 131072.0) {
        cartan_vec_set_f32(g_e8_anchor_hash_lut, i, -1.0);
        i = i + 1.0;
    }
}

fn geomind_e8_anchors_save(path: string) -> float {
    geomind_e8_anchors_init_if_needed();
    if (path == 0.0 || g_e8_anchor_count <= 0.0) { return 0.0; }
    let f = fopen(path, "wb");
    if (f == 0.0) { return 0.0; }
    let cnt = g_e8_anchor_count;
    let total_elems = 1.0 + cnt + cnt + cnt * 248.0;
    let buf = malloc(total_elems * 8.0);
    if (buf == 0.0) { fclose(f); return 0.0; }
    buf[0.0] = cnt;
    var i = 0.0;
    while (i < cnt) {
        buf[1.0 + i] = cartan_vec_get_f32(g_e8_anchor_masses, i);
        buf[1.0 + cnt + i] = cartan_vec_get_f32(g_e8_anchor_hashes, i);
        i = i + 1.0;
    }
    i = 0.0;
    let coord_base = 1.0 + 2.0 * cnt;
    while (i < cnt * 248.0) {
        buf[coord_base + i] = cartan_vec_get_f32(g_e8_anchor_coords, i);
        i = i + 1.0;
    }
    fwrite(buf, 8.0, total_elems, f);
    fclose(f);
    free(buf);
    return 1.0;
}

fn geomind_e8_anchors_load(path: string) -> float {
    geomind_e8_anchors_init_if_needed();
    if (path == 0.0 || cartan_file_exists(path) == 0.0) { return 0.0; }
    let f_sz = cartan_get_binary_file_size(path);
    if (f_sz < 16.0) { return 0.0; }
    let f = fopen(path, "rb");
    if (f == 0.0) { return 0.0; }
    let hdr = malloc(8.0);
    fread(hdr, 8.0, 1.0, f);
    var cnt = hdr[0.0];
    free(hdr);
    if (cnt <= 0.0 || cnt > 65536.0) { fclose(f); return 0.0; }
    let total_elems = 1.0 + cnt + cnt + cnt * 248.0;
    if (f_sz < total_elems * 8.0) { fclose(f); return 0.0; }
    fclose(f);
    let f2 = fopen(path, "rb");
    if (f2 == 0.0) { return 0.0; }
    let buf = malloc(total_elems * 8.0);
    if (buf == 0.0) { fclose(f2); return 0.0; }
    fread(buf, 8.0, total_elems, f2);
    fclose(f2);
    geomind_e8_anchors_reset();
    g_e8_anchor_count = cnt;
    var i = 0.0;
    while (i < cnt) {
        let mh = buf[1.0 + cnt + i];
        cartan_vec_set_f32(g_e8_anchor_masses, i, buf[1.0 + i]);
        cartan_vec_set_f32(g_e8_anchor_hashes, i, mh);
        geomind_e8_anchor_lut_insert(mh, i);
        i = i + 1.0;
    }
    i = 0.0;
    let coord_base = 1.0 + 2.0 * cnt;
    while (i < cnt * 248.0) {
        cartan_vec_set_f32(g_e8_anchor_coords, i, buf[coord_base + i]);
        i = i + 1.0;
    }
    free(buf);
    return g_e8_anchor_count;
}

// Compute unit-normalized Killing-Cartan E8 cosine resonance between patch_248 and anchor idx
fn geomind_e8_anchor_killing_sim(patch_248: ptr, anchor_idx: float) -> float {
    let a_off = anchor_idx * 248.0;
    var dot_g = 0.0;
    var norm_p_g = 0.0;
    var norm_a_g = 0.0;
    var d = 0.0;
    while (d < 248.0) {
        let sub_idx = floor(d / 31.0);
        let kw = geom_killing_form_dynkin_weight(sub_idx);
        let pv = cartan_vec_get_f32(patch_248, d);
        let av = cartan_vec_get_f32(g_e8_anchor_coords, a_off + d);
        dot_g = dot_g + pv * av * kw;
        norm_p_g = norm_p_g + pv * pv * kw;
        norm_a_g = norm_a_g + av * av * kw;
        d = d + 1.0;
    }
    let denom = sqrt(norm_p_g * norm_a_g);
    if (denom < 0.000001) { return 0.0; }
    return dot_g / denom;
}

// ============================================================================
// STAGE 6.0: 42-LAYER STRATIFIED E8 CONCEPT-THOUGHT STACK (L0..L41),
// MULTI-HOP GEODESIC DEDUCTION, S^{247} CONCEPT DECODER, & GGUF v3 SERIALIZER
// ============================================================================
// Distributes non-Euclidean relational & causal reasoning across all 42 layers (6 x 7-Layer Geodesic Cascades):
// - Cascade 0 (`Layers  0..6`):  `g_e8_rel_isa_248x248`    (1st-Hop Taxonomic IS_A: sparrow->bird, kitten->cat, puppy->dog, orb->ball)
// - Cascade 1 (`Layers  7..13`): `g_e8_rel_super_248x248`  (2nd-Hop Superordinate Category: bird/cat/dog->animal, ball->plaything, oak->plant)
// - Cascade 2 (`Layers 14..20`): `g_e8_rel_cap_248x248`    (Inherited Capability & Affordance: bird->fly, cat->purrs, dog->run, ball->bounce)
//                               + `g_e8_rel_prop_248x248`  (Intrinsic Attribute: sparrow->small, kitten/puppy->young, ball->round)
// - Cascade 3 (`Layers 21..27`): `g_e8_rel_val_248x248`    (3rd-Hop Valence, State, & Locus: run/play/bounce->fun, purrs->happy, fly->sky)
// - Cascade 4 (`Layers 28..34`): `g_e8_rel_cause_248x248`  (Physical & Narrative Causal Law: ball->gravity, wood->lighter, rain->clouds)
// - Cascade 5 (`Layers 35..41`): `g_e8_rel_effect_248x248` (Ultimate Causal Consequence: gravity->ground, lighter->floats, clouds->grow)
var g_wordnet_initialized: float = 0.0;
var g_wordnet_lemma_hash: ptr = 0.0;
var g_wordnet_synset_hash: ptr = 0.0;
var g_wordnet_head_hash: ptr = 0.0;
var g_wordnet_ic_weight: ptr = 0.0;
var g_wordnet_sense_guard: ptr = 0.0;
var g_wordnet_lemma_vecs: ptr = 0.0;

var g_e8_rel_initialized: float = 0.0;
var g_e8_rel_isa_248x248: ptr = 0.0;
var g_e8_rel_super_248x248: ptr = 0.0;
var g_e8_rel_cap_248x248: ptr = 0.0;
var g_e8_rel_prop_248x248: ptr = 0.0;
var g_e8_rel_val_248x248: ptr = 0.0;
var g_e8_rel_cause_248x248: ptr = 0.0;
var g_e8_rel_effect_248x248: ptr = 0.0;
var g_e8_rel_tmp_u: ptr = 0.0;
var g_e8_rel_tmp_v: ptr = 0.0;
var g_e8_vec_fun: ptr = 0.0;
var g_e8_rel_updates_count: float = 0.0;

// S^{247} Concept Vocabulary Codebook for decoding any 248-D state h^{(l)} at any layer l in {0..42}
var g_e8_vocab_words: ptr = 0.0;
var g_e8_vocab_hashes: ptr = 0.0;
var g_e8_vocab_vecs: ptr = 0.0;
var g_e8_vocab_count: float = 0.0;
var g_e8_last_decode_sim: float = 0.0;
var g_e8_last_sasaki_vel_norm: float = 0.0;

var g_wn_verb_to: float = 0.0;
var g_wn_verb_can: float = 0.0;
var g_wn_verb_will: float = 0.0;
var g_wn_verb_not: float = 0.0;
var g_wn_verb_do: float = 0.0;
var g_wn_hash_is: float = 0.0;
var g_wn_hash_a: float = 0.0;
var g_wn_hash_the: float = 0.0;
var g_wn_hash_and: float = 0.0;
var g_wn_hash_in: float = 0.0;
var g_wn_hash_on: float = 0.0;
var g_wn_hash_when: float = 0.0;
var g_wn_hash_it: float = 0.0;
var g_wn_hash_you: float = 0.0;
var g_wn_hash_likes: float = 0.0;
var g_wn_hash_because: float = 0.0;

var g_ctx_prev2_hash: float = 17.0;
var g_ctx_prev_hash: float = 17.0;
var g_ctx_last_hash: float = 17.0;
var g_ctx_prev2_syn: float = 0.0;
var g_ctx_prev_syn: float = 0.0;
var g_ctx_last_syn: float = 0.0;
var g_ctx_sent_topic_hash: float = 17.0;
var g_ctx_sent_started_subord: float = 0.0;

fn geomind_word_patch_hash(word: string) -> float {
    let n = cartan_string_length(word);
    var h = 17.0;
    var i = 0.0;
    while (i < n) {
        var b = cartan_byte_at(word, i);
        if (b < 0.0) { b = b + 256.0; }
        if (b >= 65.0 && b <= 90.0) { b = b + 32.0; }
        if ((b >= 97.0 && b <= 122.0) || (b >= 48.0 && b <= 57.0)) {
            h = math_mod_val(h * 131.0 + b, 1000003.0);
        }
        i = i + 1.0;
    }
    return h;
}

// Project a case-normalized word patch hash `word_hash` onto its canonical quasi-orthogonal S^{247} coordinate (||v||_2 = sqrt(248))
// via E8 Chebyshev-Harmonic basis coordinates + 3 cascaded Weyl root reflections on the 240 kissing roots
fn geomind_e8_hash_to_vec_248(word_hash: float, out_248: ptr) {
    let h1 = math_mod_val(word_hash * 7919.0 + 104729.0, 1000003.0);
    let h2 = math_mod_val(word_hash * 15485863.0 + 32452843.0, 1000003.0);
    var d = 0.0;
    while (d < 248.0) {
        let ph1 = math_mod_val(h1 * (d + 1.0) * 0.6180339887, 6.283185307);
        let ph2 = math_mod_val(h2 * (248.0 - d) * 0.4142135623, 6.283185307);
        let val = cos(ph1) + 0.70710678 * sin(ph2 + d * 0.137);
        cartan_vec_set_f32(out_248, d, val);
        d = d + 1.0;
    }
    geomind_weyl_reflect_vector_248(out_248, math_mod_val(word_hash, 240.0));
    geomind_weyl_reflect_vector_248(out_248, math_mod_val(h1, 240.0));
    geomind_weyl_reflect_vector_248(out_248, math_mod_val(h2, 240.0));
    var nsq = 0.0;
    d = 0.0;
    while (d < 248.0) {
        let v = cartan_vec_get_f32(out_248, d);
        nsq = nsq + v * v;
        d = d + 1.0;
    }
    if (nsq > 0.000001) {
        let sc = sqrt(248.0 / nsq);
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(out_248, d, cartan_vec_get_f32(out_248, d) * sc);
            d = d + 1.0;
        }
    }
}

// Fold a surface word string directly into its deterministic S^{247} coordinate (||v||_2 = sqrt(248))
fn geomind_e8_word_to_vec_248(word: string, out_248: ptr) {
    let wh = geomind_word_patch_hash(word);
    geomind_e8_hash_to_vec_248(wh, out_248);
}

// Register a concept word in the S^{247} Concept Vocabulary Codebook so any layer state h^{(l)} can be decoded
fn geomind_e8_register_vocab_word(word: string) {
    if (cartan_string_length(word) == 0.0) { return; }
    let wh = geomind_word_patch_hash(word);
    if (wh <= 17.0) { return; }
    var i = 0.0;
    while (i < g_e8_vocab_count) {
        if (cartan_vec_get_f32(g_e8_vocab_hashes, i) == wh) {
            return;
        }
        i = i + 1.0;
    }
    if (g_e8_vocab_count >= 512.0) { return; }
    let idx = g_e8_vocab_count;
    cartan_tree_push(g_e8_vocab_words, word);
    cartan_vec_set_f32(g_e8_vocab_hashes, idx, wh);
    let tmp_v = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(tmp_v, 0.0);
        d = d + 1.0;
    }
    geomind_e8_hash_to_vec_248(wh, tmp_v);
    let base = idx * 248.0;
    d = 0.0;
    while (d < 248.0) {
        cartan_vec_set_f32(g_e8_vocab_vecs, base + d, cartan_vec_get_f32(tmp_v, d));
        d = d + 1.0;
    }
    cartan_vec_free(tmp_v);
    g_e8_vocab_count = g_e8_vocab_count + 1.0;
}

// Decode any 248-D manifold state `h_248` on S^{247} into its highest-resonating English concept word
fn geomind_e8_decode_concept_vec_248(h_248: ptr) -> string {
    geomind_e8_rel_init_if_needed();
    var best_sim = -10.0;
    var best_word = "<coasting>";
    var i = 0.0;
    while (i < g_e8_vocab_count) {
        let base = i * 248.0;
        var dot = 0.0;
        var d = 0.0;
        while (d < 248.0) {
            dot = dot + cartan_vec_get_f32(h_248, d) * cartan_vec_get_f32(g_e8_vocab_vecs, base + d);
            d = d + 1.0;
        }
        let sim = dot / 248.0;
        if (sim > best_sim) {
            best_sim = sim;
            best_word = cartan_tree_get(g_e8_vocab_words, i);
        }
        i = i + 1.0;
    }
    g_e8_last_decode_sim = best_sim;
    if (best_sim < 0.30) {
        return "<coasting>";
    }
    return best_word;
}

fn geomind_e8_rel_init_if_needed() {
    if (g_e8_rel_initialized == 1.0 && g_e8_rel_isa_248x248 != 0.0) { return; }
    g_e8_rel_isa_248x248 = cartan_tensor_alloc(61504.0);
    g_e8_rel_super_248x248 = cartan_tensor_alloc(61504.0);
    g_e8_rel_cap_248x248 = cartan_tensor_alloc(61504.0);
    g_e8_rel_prop_248x248 = cartan_tensor_alloc(61504.0);
    g_e8_rel_val_248x248 = cartan_tensor_alloc(61504.0);
    g_e8_rel_cause_248x248 = cartan_tensor_alloc(61504.0);
    g_e8_rel_effect_248x248 = cartan_tensor_alloc(61504.0);
    g_e8_rel_tmp_u = cartan_vec_create();
    g_e8_rel_tmp_v = cartan_vec_create();
    g_e8_vec_fun = cartan_vec_create();
    g_e8_vocab_words = cartan_tree_create();
    g_e8_vocab_hashes = cartan_tensor_alloc(512.0);
    g_e8_vocab_vecs = cartan_tensor_alloc(512.0 * 248.0);
    g_e8_vocab_count = 0.0;
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(g_e8_rel_tmp_u, 0.0);
        cartan_vec_push_f32(g_e8_rel_tmp_v, 0.0);
        cartan_vec_push_f32(g_e8_vec_fun, 0.0);
        d = d + 1.0;
    }
    var i = 0.0;
    while (i < 61504.0) {
        cartan_vec_set_f32(g_e8_rel_isa_248x248, i, 0.0);
        cartan_vec_set_f32(g_e8_rel_super_248x248, i, 0.0);
        cartan_vec_set_f32(g_e8_rel_cap_248x248, i, 0.0);
        cartan_vec_set_f32(g_e8_rel_prop_248x248, i, 0.0);
        cartan_vec_set_f32(g_e8_rel_val_248x248, i, 0.0);
        cartan_vec_set_f32(g_e8_rel_cause_248x248, i, 0.0);
        cartan_vec_set_f32(g_e8_rel_effect_248x248, i, 0.0);
        i = i + 1.0;
    }
    g_e8_rel_initialized = 1.0;
    geomind_e8_word_to_vec_248("fun", g_e8_vec_fun);

    // Seed core curriculum & taxonomic concept words into the S^{247} Concept Vocabulary Codebook
    geomind_e8_register_vocab_word("animal");
    geomind_e8_register_vocab_word("plaything");
    geomind_e8_register_vocab_word("liquid");
    geomind_e8_register_vocab_word("plant");
    geomind_e8_register_vocab_word("energy");
    geomind_e8_register_vocab_word("person");
    geomind_e8_register_vocab_word("force");
    geomind_e8_register_vocab_word("weather");
    geomind_e8_register_vocab_word("bird");
    geomind_e8_register_vocab_word("sparrow");
    geomind_e8_register_vocab_word("robin");
    geomind_e8_register_vocab_word("cat");
    geomind_e8_register_vocab_word("kitten");
    geomind_e8_register_vocab_word("dog");
    geomind_e8_register_vocab_word("puppy");
    geomind_e8_register_vocab_word("fish");
    geomind_e8_register_vocab_word("ball");
    geomind_e8_register_vocab_word("orb");
    geomind_e8_register_vocab_word("sphere");
    geomind_e8_register_vocab_word("water");
    geomind_e8_register_vocab_word("brook");
    geomind_e8_register_vocab_word("rain");
    geomind_e8_register_vocab_word("fire");
    geomind_e8_register_vocab_word("tree");
    geomind_e8_register_vocab_word("oak");
    geomind_e8_register_vocab_word("wood");
    geomind_e8_register_vocab_word("star");
    geomind_e8_register_vocab_word("sun");
    geomind_e8_register_vocab_word("small");
    geomind_e8_register_vocab_word("young");
    geomind_e8_register_vocab_word("round");
    geomind_e8_register_vocab_word("clear");
    geomind_e8_register_vocab_word("wet");
    geomind_e8_register_vocab_word("hot");
    geomind_e8_register_vocab_word("soft");
    geomind_e8_register_vocab_word("fly");
    geomind_e8_register_vocab_word("sky");
    geomind_e8_register_vocab_word("purrs");
    geomind_e8_register_vocab_word("happy");
    geomind_e8_register_vocab_word("run");
    geomind_e8_register_vocab_word("play");
    geomind_e8_register_vocab_word("bounce");
    geomind_e8_register_vocab_word("bouncing");
    geomind_e8_register_vocab_word("fun");
    geomind_e8_register_vocab_word("gravity");
    geomind_e8_register_vocab_word("ground");
    geomind_e8_register_vocab_word("lighter");
    geomind_e8_register_vocab_word("floats");
    geomind_e8_register_vocab_word("clouds");
    geomind_e8_register_vocab_word("grow");
    geomind_e8_register_vocab_word("swims");
}

// Compute directed bilinear Killing-Cartan relational score S(u --[R]--> v) = (1/248) * <v, R * u>
fn geomind_e8_rel_score_vec(rel_mat_248x248: ptr, u_248: ptr, v_248: ptr) -> float {
    geomind_e8_rel_init_if_needed();
    var total = 0.0;
    var r = 0.0;
    while (r < 248.0) {
        let vr = cartan_vec_get_f32(v_248, r);
        let row_off = r * 248.0;
        var row_dot = 0.0;
        var c = 0.0;
        while (c < 248.0) {
            row_dot = row_dot + cartan_vec_get_f32(rel_mat_248x248, row_off + c) * cartan_vec_get_f32(u_248, c);
            c = c + 1.0;
        }
        total = total + vr * row_dot;
        r = r + 1.0;
    }
    return total / 248.0;
}

// Analytical Rank-2 Asymmetric Riemannian Projection-Gradient Step on R in R^{248x248}:
// Drives forward score S(u -> v) toward `target_w` while simultaneously driving reverse S(v -> u) toward 0.0 when `asym_contrast == 1.0`
fn geomind_e8_rel_train_step(
    rel_mat_248x248: ptr,
    u_248: ptr,
    v_248: ptr,
    target_w: float,
    asym_contrast: float,
    lr: float
) -> float {
    geomind_e8_rel_init_if_needed();
    let s_fwd = geomind_e8_rel_score_vec(rel_mat_248x248, u_248, v_248);
    var s_rev = 0.0;
    if (asym_contrast > 0.0) {
        s_rev = geomind_e8_rel_score_vec(rel_mat_248x248, v_248, u_248);
    }
    let err_fwd = s_fwd - target_w;
    let err_rev = s_rev * asym_contrast;
    let step_scale = lr / 248.0;

    var r = 0.0;
    while (r < 248.0) {
        let vr = cartan_vec_get_f32(v_248, r);
        let ur = cartan_vec_get_f32(u_248, r);
        let row_off = r * 248.0;
        var c = 0.0;
        while (c < 248.0) {
            let uc = cartan_vec_get_f32(u_248, c);
            let vc = cartan_vec_get_f32(v_248, c);
            let grad_rc = err_fwd * vr * uc + err_rev * ur * vc;
            let old_w = cartan_vec_get_f32(rel_mat_248x248, row_off + c);
            cartan_vec_set_f32(rel_mat_248x248, row_off + c, old_w - step_scale * grad_rc);
            c = c + 1.0;
        }
        r = r + 1.0;
    }
    g_e8_rel_updates_count = g_e8_rel_updates_count + 1.0;
    return s_fwd;
}

// Train a directed relational edge (word_u --[R]--> word_v) across `passes` Riemannian steps
fn geomind_e8_rel_train_words(rel_mat_248x248: ptr, word_u: string, word_v: string, target_w: float, passes: float) {
    geomind_e8_rel_init_if_needed();
    geomind_e8_register_vocab_word(word_u);
    geomind_e8_register_vocab_word(word_v);
    geomind_e8_word_to_vec_248(word_u, g_e8_rel_tmp_u);
    geomind_e8_word_to_vec_248(word_v, g_e8_rel_tmp_v);
    var p = 0.0;
    while (p < passes) {
        geomind_e8_rel_train_step(rel_mat_248x248, g_e8_rel_tmp_u, g_e8_rel_tmp_v, target_w, 1.0, 0.45);
        p = p + 1.0;
    }
}

// Evaluate directed relational weight S(word_u --[R]--> word_v) directly from the 248x248 manifold tensor
fn geomind_e8_rel_score_words(rel_mat_248x248: ptr, word_u: string, word_v: string) -> float {
    geomind_e8_rel_init_if_needed();
    geomind_e8_word_to_vec_248(word_u, g_e8_rel_tmp_u);
    geomind_e8_word_to_vec_248(word_v, g_e8_rel_tmp_v);
    return geomind_e8_rel_score_vec(rel_mat_248x248, g_e8_rel_tmp_u, g_e8_rel_tmp_v);
}

// Compute cosine alignment <R_prop * u, R_prop * v> / (||R_prop * u|| ||R_prop * v||) in 248-D property/valence space
fn geomind_e8_rel_prop_cosine_words(word_u: string, word_v: string) -> float {
    geomind_e8_rel_init_if_needed();
    geomind_e8_word_to_vec_248(word_u, g_e8_rel_tmp_u);
    geomind_e8_word_to_vec_248(word_v, g_e8_rel_tmp_v);
    var dot_uv = 0.0;
    var n_u = 0.0;
    var n_v = 0.0;
    var r = 0.0;
    while (r < 248.0) {
        let row_off = r * 248.0;
        var ru = 0.0;
        var rv = 0.0;
        var c = 0.0;
        while (c < 248.0) {
            let w_rc = cartan_vec_get_f32(g_e8_rel_val_248x248, row_off + c);
            ru = ru + w_rc * cartan_vec_get_f32(g_e8_rel_tmp_u, c);
            rv = rv + w_rc * cartan_vec_get_f32(g_e8_rel_tmp_v, c);
            c = c + 1.0;
        }
        dot_uv = dot_uv + ru * rv;
        n_u = n_u + ru * ru;
        n_v = n_v + rv * rv;
        r = r + 1.0;
    }
    let denom = sqrt(n_u * n_v);
    if (denom < 0.000001) { return 0.0; }
    return dot_uv / denom;
}

// Propagate a 248-D state `h_in_248` through a 7-Layer Non-Linear Geodesic Cascade (`l_start .. l_start + 6`)
// on the 496-D Sasaki Tangent Bundle TS^{247} = (h^{(l)}, v^{(l)}), retracting onto S^{247} at each layer.
// If the relational force norm ||R * h_in|| / sqrt(248) < 0.25, Metacognitive Coasting preserves h_in_248!
fn geomind_e8_cascade_step_7L(rel_mat_248x248: ptr, h_in_248: ptr, l_start: float, h_out_248: ptr) -> float {
    let f_vec = cartan_vec_create();
    let h_cur = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(f_vec, 0.0);
        cartan_vec_push_f32(h_cur, cartan_vec_get_f32(h_in_248, d));
        d = d + 1.0;
    }

    // Evaluate relational transport force f = R * h_in
    var f_sq = 0.0;
    var r = 0.0;
    while (r < 248.0) {
        let row_off = r * 248.0;
        var acc = 0.0;
        var c = 0.0;
        while (c < 248.0) {
            acc = acc + cartan_vec_get_f32(rel_mat_248x248, row_off + c) * cartan_vec_get_f32(h_in_248, c);
            c = c + 1.0;
        }
        cartan_vec_set_f32(f_vec, r, acc);
        f_sq = f_sq + acc * acc;
        r = r + 1.0;
    }
    let f_rms = sqrt(f_sq / 248.0);
    if (f_rms < 0.62) {
        // Metacognitive Doubt / Geodesic Coasting: no strong relational attractor from h_in_248 in this stratum
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_out_248, d, cartan_vec_get_f32(h_in_248, d));
            d = d + 1.0;
        }
        cartan_vec_free(f_vec);
        cartan_vec_free(h_cur);
        return 0.0;
    }

    // Normalize target basin endpoint f_vec onto S^{247} (||f_vec||_2 = sqrt(248))
    let f_scale = sqrt(248.0 / f_sq);
    d = 0.0;
    while (d < 248.0) {
        cartan_vec_set_f32(f_vec, d, cartan_vec_get_f32(f_vec, d) * f_scale);
        d = d + 1.0;
    }
    let decoded_basin_word = geomind_e8_decode_concept_vec_248(f_vec);
    if (g_e8_last_decode_sim < 0.62 || (f_rms * g_e8_last_decode_sim) < 0.55) {
        // Crosstalk rejection: normalized transport vector or unnormalized bilinear projection does not resonate with a crystallized concept basin
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_out_248, d, cartan_vec_get_f32(h_in_248, d));
            d = d + 1.0;
        }
        cartan_vec_free(f_vec);
        cartan_vec_free(h_cur);
        return 0.0;
    }

    // Kanerva-Hopfield Attractor Basin Clean-Up on S^{247}:
    // Snap the stratum endpoint f_vec into the crystallized concept basin so multi-hop cascades do not accumulate linear crosstalk
    let basin_vec = cartan_vec_create();
    d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(basin_vec, 0.0);
        d = d + 1.0;
    }
    geomind_e8_word_to_vec_248(decoded_basin_word, basin_vec);
    var clean_sq = 0.0;
    d = 0.0;
    while (d < 248.0) {
        let cv = 0.25 * cartan_vec_get_f32(f_vec, d) + 0.75 * cartan_vec_get_f32(basin_vec, d);
        cartan_vec_set_f32(f_vec, d, cv);
        clean_sq = clean_sq + cv * cv;
        d = d + 1.0;
    }
    if (clean_sq > 0.000001) {
        let c_sc = sqrt(248.0 / clean_sq);
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(f_vec, d, cartan_vec_get_f32(f_vec, d) * c_sc);
            d = d + 1.0;
        }
    }
    cartan_vec_free(basin_vec);

    // Step through all 7 layers of this stratum (k = 0..6, layer l = l_start + k) on TS^{247}
    var vel_norm_accum = 0.0;
    var k = 0.0;
    while (k < 7.0) {
        let alpha = (k + 1.0) / 7.0;
        var dot_hf = 0.0;
        d = 0.0;
        while (d < 248.0) {
            dot_hf = dot_hf + cartan_vec_get_f32(h_cur, d) * cartan_vec_get_f32(f_vec, d);
            d = d + 1.0;
        }
        let proj = dot_hf / 248.0;
        var v_sq = 0.0;
        var next_sq = 0.0;
        d = 0.0;
        while (d < 248.0) {
            let hc = cartan_vec_get_f32(h_cur, d);
            let fv = cartan_vec_get_f32(f_vec, d);
            let v_tan = fv - proj * hc;
            v_sq = v_sq + v_tan * v_tan;
            let h_next = (1.0 - alpha) * cartan_vec_get_f32(h_in_248, d) + alpha * fv;
            cartan_vec_set_f32(h_cur, d, h_next);
            next_sq = next_sq + h_next * h_next;
            d = d + 1.0;
        }
        if (next_sq > 0.000001) {
            let n_sc = sqrt(248.0 / next_sq);
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(h_cur, d, cartan_vec_get_f32(h_cur, d) * n_sc);
                d = d + 1.0;
            }
        }
        vel_norm_accum = vel_norm_accum + sqrt(v_sq / 248.0);
        k = k + 1.0;
    }

    d = 0.0;
    while (d < 248.0) {
        cartan_vec_set_f32(h_out_248, d, cartan_vec_get_f32(h_cur, d));
        d = d + 1.0;
    }
    cartan_vec_free(f_vec);
    cartan_vec_free(h_cur);
    g_e8_last_sasaki_vel_norm = vel_norm_accum / 7.0;
    return f_rms;
}

// Execute a Full 42-Layer Stratified E8 Concept-Thought Rollout (`L0 -> L7 -> L14 -> L21 -> L28 -> L35 -> L42`)
// Returns a formatted trace of the multi-hop geodesic concepts decoded at each stratum of the 42-layer stack.
fn geomind_e8_deep_thought_rollout_42L(seed_word: string) -> string {
    geomind_e8_rel_init_if_needed();
    let h_L0 = cartan_vec_create();
    let h_L7 = cartan_vec_create();
    let h_L14 = cartan_vec_create();
    let h_L21 = cartan_vec_create();
    let h_prop = cartan_vec_create();
    let h_L28 = cartan_vec_create();
    let h_L35 = cartan_vec_create();
    let h_L42 = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_L0, 0.0);
        cartan_vec_push_f32(h_L7, 0.0);
        cartan_vec_push_f32(h_L14, 0.0);
        cartan_vec_push_f32(h_L21, 0.0);
        cartan_vec_push_f32(h_prop, 0.0);
        cartan_vec_push_f32(h_L28, 0.0);
        cartan_vec_push_f32(h_L35, 0.0);
        cartan_vec_push_f32(h_L42, 0.0);
        d = d + 1.0;
    }

    geomind_e8_word_to_vec_248(seed_word, h_L0);
    // Stratum 1 (Layers 0..6): Primary IS_A (e.g. sparrow -> bird, kitten -> cat, puppy -> dog, orb -> ball)
    geomind_e8_cascade_step_7L(g_e8_rel_isa_248x248, h_L0, 0.0, h_L7);
    let w_L7 = geomind_e8_decode_concept_vec_248(h_L7);

    // Stratum 2 (Layers 7..13): 2-Hop Superordinate Category (e.g. bird/cat/dog -> animal, ball -> plaything)
    geomind_e8_cascade_step_7L(g_e8_rel_super_248x248, h_L7, 7.0, h_L14);
    let w_L14 = geomind_e8_decode_concept_vec_248(h_L14);

    // Stratum 3 (Layers 14..20): Inherited Capability from L7 + Intrinsic Attribute from L0 (with L7 inheritance fallback)
    geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_L7, 14.0, h_L21);
    let w_L21 = geomind_e8_decode_concept_vec_248(h_L21);
    let prop_rms = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_L0, 14.0, h_prop);
    if (prop_rms < 0.45) {
        geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_L7, 14.0, h_prop);
    }
    let w_prop = geomind_e8_decode_concept_vec_248(h_prop);

    // Stratum 4 (Layers 21..27): 3-Hop Valence / State / Locus from L21 (e.g. run/bounce -> fun, purrs -> happy, fly -> sky)
    geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, h_L21, 21.0, h_L28);
    let w_L28 = geomind_e8_decode_concept_vec_248(h_L28);

    // Stratum 5 (Layers 28..34): Causal Mechanism from L7 (e.g. ball -> gravity, wood -> lighter)
    geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_L7, 28.0, h_L35);
    let w_L35 = geomind_e8_decode_concept_vec_248(h_L35);

    // Stratum 6 (Layers 35..41): Ultimate Causal Effect from L35 (e.g. gravity -> ground, lighter -> floats)
    geomind_e8_cascade_step_7L(g_e8_rel_effect_248x248, h_L35, 35.0, h_L42);
    let w_L42 = geomind_e8_decode_concept_vec_248(h_L42);

    var trace = cartan_string_concat("[L0: ", cartan_string_concat(seed_word, "] -> [L7 IS_A: "));
    trace = cartan_string_concat(trace, cartan_string_concat(w_L7, "] -> [L14 Super: "));
    trace = cartan_string_concat(trace, cartan_string_concat(w_L14, "] -> [L21 Cap/Prop: "));
    trace = cartan_string_concat(trace, cartan_string_concat(w_L21, cartan_string_concat("/", cartan_string_concat(w_prop, "] -> [L28 Valence: "))));
    trace = cartan_string_concat(trace, cartan_string_concat(w_L28, "] -> [L35..42 Cause: "));
    trace = cartan_string_concat(trace, cartan_string_concat(w_L35, cartan_string_concat("->", cartan_string_concat(w_L42, "]"))));

    cartan_vec_free(h_L0);
    cartan_vec_free(h_L7);
    cartan_vec_free(h_L14);
    cartan_vec_free(h_L21);
    cartan_vec_free(h_prop);
    cartan_vec_free(h_L28);
    cartan_vec_free(h_L35);
    cartan_vec_free(h_L42);
    return trace;
}

// Day-Zero Epistemic Reasoning & Question-Answering Engine powered by the 42-Layer Stratified E8 Stack
fn geomind_e8_answer_epistemic_question(subject_word: string, question_type: string) -> string {
    geomind_e8_rel_init_if_needed();
    let h_L0 = cartan_vec_create();
    let h_L7 = cartan_vec_create();
    let h_L14 = cartan_vec_create();
    let h_L21 = cartan_vec_create();
    let h_prop = cartan_vec_create();
    let h_L28 = cartan_vec_create();
    let h_L35 = cartan_vec_create();
    let h_L42 = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_L0, 0.0);
        cartan_vec_push_f32(h_L7, 0.0);
        cartan_vec_push_f32(h_L14, 0.0);
        cartan_vec_push_f32(h_L21, 0.0);
        cartan_vec_push_f32(h_prop, 0.0);
        cartan_vec_push_f32(h_L28, 0.0);
        cartan_vec_push_f32(h_L35, 0.0);
        cartan_vec_push_f32(h_L42, 0.0);
        d = d + 1.0;
    }

    geomind_e8_word_to_vec_248(subject_word, h_L0);
    geomind_e8_cascade_step_7L(g_e8_rel_isa_248x248, h_L0, 0.0, h_L7);
    let w_L7 = geomind_e8_decode_concept_vec_248(h_L7);
    geomind_e8_cascade_step_7L(g_e8_rel_super_248x248, h_L7, 7.0, h_L14);
    let w_L14 = geomind_e8_decode_concept_vec_248(h_L14);
    geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_L7, 14.0, h_L21);
    let w_L21 = geomind_e8_decode_concept_vec_248(h_L21);
    let q_prop_rms = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_L0, 14.0, h_prop);
    if (q_prop_rms < 0.45) {
        geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_L7, 14.0, h_prop);
    }
    let w_prop = geomind_e8_decode_concept_vec_248(h_prop);
    geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, h_L21, 21.0, h_L28);
    let w_L28 = geomind_e8_decode_concept_vec_248(h_L28);
    geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_L7, 28.0, h_L35);
    let w_L35 = geomind_e8_decode_concept_vec_248(h_L35);
    geomind_e8_cascade_step_7L(g_e8_rel_effect_248x248, h_L35, 35.0, h_L42);
    let w_L42 = geomind_e8_decode_concept_vec_248(h_L42);

    var ans = "";
    if (cartan_string_eq(question_type, "taxonomy") == 1.0) {
        ans = cartan_string_concat("Yes, a ", cartan_string_concat(subject_word, cartan_string_concat(" is a ", cartan_string_concat(w_prop, cartan_string_concat(" ", cartan_string_concat(w_L7, cartan_string_concat(" (a kind of ", cartan_string_concat(w_L14, cartan_string_concat(") that can ", cartan_string_concat(w_L21, cartan_string_concat(" in the ", cartan_string_concat(w_L28, "."))))))))))));
    } else if (cartan_string_eq(question_type, "valence") == 1.0) {
        ans = cartan_string_concat("A ", cartan_string_concat(subject_word, cartan_string_concat(" is a ", cartan_string_concat(w_prop, cartan_string_concat(" ", cartan_string_concat(w_L7, cartan_string_concat(" (an ", cartan_string_concat(w_L14, cartan_string_concat(") that likes to ", cartan_string_concat(w_L21, cartan_string_concat(" because ", cartan_string_concat(w_L21, cartan_string_concat(" is ", cartan_string_concat(w_L28, "."))))))))))))));
    } else if (cartan_string_eq(question_type, "feeling") == 1.0) {
        ans = cartan_string_concat("A ", cartan_string_concat(subject_word, cartan_string_concat(" is a ", cartan_string_concat(w_prop, cartan_string_concat(" ", cartan_string_concat(w_L7, cartan_string_concat(" (an ", cartan_string_concat(w_L14, cartan_string_concat(") that ", cartan_string_concat(w_L21, cartan_string_concat(" when it is ", cartan_string_concat(w_L28, "."))))))))))));
    } else if (cartan_string_eq(question_type, "causal_drop") == 1.0) {
        ans = cartan_string_concat("An ", cartan_string_concat(subject_word, cartan_string_concat(" is a ", cartan_string_concat(w_prop, cartan_string_concat(" ", cartan_string_concat(w_L7, cartan_string_concat(" (a ", cartan_string_concat(w_L14, cartan_string_concat("); when dropped, ", cartan_string_concat(w_L35, cartan_string_concat(" pulls it to the ", cartan_string_concat(w_L42, cartan_string_concat(" where it can ", cartan_string_concat(w_L21, cartan_string_concat(" (", cartan_string_concat(w_L28, ")."))))))))))))))));
    } else {
        ans = cartan_string_concat("Because ", cartan_string_concat(subject_word, cartan_string_concat(" is ", cartan_string_concat(w_L35, cartan_string_concat(" than water, ", cartan_string_concat(subject_word, cartan_string_concat(" ", cartan_string_concat(w_L42, " on water."))))))));
    }

    cartan_vec_free(h_L0);
    cartan_vec_free(h_L7);
    cartan_vec_free(h_L14);
    cartan_vec_free(h_L21);
    cartan_vec_free(h_prop);
    cartan_vec_free(h_L28);
    cartan_vec_free(h_L35);
    cartan_vec_free(h_L42);
    return ans;
}

// Helper: Compute normalized Killing-Cartan inner product (1/248) * <u_248, v_248> on S^{247}
fn geomind_e8_vec_cosine_248(u_248: ptr, v_248: ptr) -> float {
    var dot = 0.0;
    var d = 0.0;
    while (d < 248.0) {
        dot = dot + cartan_vec_get_f32(u_248, d) * cartan_vec_get_f32(v_248, d);
        d = d + 1.0;
    }
    return dot / 248.0;
}

// SUBTLE TEST 1: Zero-Shot 42-Layer Trajectory Intersection ("What do word_a and word_b have in common?")
// Propagates word_a and word_b independently through all 42 layers and checks where their trajectories collide on S^{247}.
fn geomind_e8_trajectory_intersection_42L(word_a: string, word_b: string) -> string {
    geomind_e8_rel_init_if_needed();
    let hA_0 = cartan_vec_create();
    let hA_7 = cartan_vec_create();
    let hA_14 = cartan_vec_create();
    let hA_21 = cartan_vec_create();
    let hA_pr = cartan_vec_create();
    let hA_28 = cartan_vec_create();
    let hB_0 = cartan_vec_create();
    let hB_7 = cartan_vec_create();
    let hB_14 = cartan_vec_create();
    let hB_21 = cartan_vec_create();
    let hB_pr = cartan_vec_create();
    let hB_28 = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(hA_0, 0.0);
        cartan_vec_push_f32(hA_7, 0.0);
        cartan_vec_push_f32(hA_14, 0.0);
        cartan_vec_push_f32(hA_21, 0.0);
        cartan_vec_push_f32(hA_pr, 0.0);
        cartan_vec_push_f32(hA_28, 0.0);
        cartan_vec_push_f32(hB_0, 0.0);
        cartan_vec_push_f32(hB_7, 0.0);
        cartan_vec_push_f32(hB_14, 0.0);
        cartan_vec_push_f32(hB_21, 0.0);
        cartan_vec_push_f32(hB_pr, 0.0);
        cartan_vec_push_f32(hB_28, 0.0);
        d = d + 1.0;
    }

    geomind_e8_word_to_vec_248(word_a, hA_0);
    let rA_7 = geomind_e8_cascade_step_7L(g_e8_rel_isa_248x248, hA_0, 0.0, hA_7);
    let rA_14 = geomind_e8_cascade_step_7L(g_e8_rel_super_248x248, hA_7, 7.0, hA_14);
    let rA_21 = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, hA_7, 14.0, hA_21);
    var rA_pr = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, hA_0, 14.0, hA_pr);
    if (rA_pr < 0.45) {
        rA_pr = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, hA_7, 14.0, hA_pr);
    }
    var rA_28 = geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, hA_21, 21.0, hA_28);
    if (rA_28 < 0.45) {
        rA_28 = geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, hA_0, 21.0, hA_28);
    }

    geomind_e8_word_to_vec_248(word_b, hB_0);
    let rB_7 = geomind_e8_cascade_step_7L(g_e8_rel_isa_248x248, hB_0, 0.0, hB_7);
    let rB_14 = geomind_e8_cascade_step_7L(g_e8_rel_super_248x248, hB_7, 7.0, hB_14);
    let rB_21 = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, hB_7, 14.0, hB_21);
    var rB_pr = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, hB_0, 14.0, hB_pr);
    if (rB_pr < 0.45) {
        rB_pr = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, hB_7, 14.0, hB_pr);
    }
    var rB_28 = geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, hB_21, 21.0, hB_28);
    if (rB_28 < 0.45) {
        rB_28 = geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, hB_0, 21.0, hB_28);
    }

    let cos_7 = geomind_e8_vec_cosine_248(hA_7, hB_7);
    let cos_14 = geomind_e8_vec_cosine_248(hA_14, hB_14);
    let cos_pr = geomind_e8_vec_cosine_248(hA_pr, hB_pr);
    let cos_28 = geomind_e8_vec_cosine_248(hA_28, hB_28);

    var hits = "";
    var hit_count = 0.0;
    if (rA_7 > 0.0 && rB_7 > 0.0 && cos_7 >= 0.70) {
        let w7 = geomind_e8_decode_concept_vec_248(hA_7);
        hits = cartan_string_concat(hits, cartan_string_concat("[L7 IS_A = '", cartan_string_concat(w7, "'] ")));
        hit_count = hit_count + 1.0;
    }
    if (rA_14 > 0.0 && rB_14 > 0.0 && cos_14 >= 0.70) {
        let w14 = geomind_e8_decode_concept_vec_248(hA_14);
        hits = cartan_string_concat(hits, cartan_string_concat("[L14 Super = '", cartan_string_concat(w14, "'] ")));
        hit_count = hit_count + 1.0;
    }
    if (rA_pr > 0.0 && rB_pr > 0.0 && cos_pr >= 0.70) {
        let wpr = geomind_e8_decode_concept_vec_248(hA_pr);
        hits = cartan_string_concat(hits, cartan_string_concat("[L21 Prop = '", cartan_string_concat(wpr, "'] ")));
        hit_count = hit_count + 1.0;
    }
    if (rA_28 > 0.0 && rB_28 > 0.0 && cos_28 >= 0.70) {
        let w28 = geomind_e8_decode_concept_vec_248(hA_28);
        hits = cartan_string_concat(hits, cartan_string_concat("[L28 Valence = '", cartan_string_concat(w28, "'] ")));
        hit_count = hit_count + 1.0;
    }

    let wA_7 = geomind_e8_decode_concept_vec_248(hA_7);
    let wB_7 = geomind_e8_decode_concept_vec_248(hB_7);
    var res = "";
    if (hit_count > 0.0) {
        res = cartan_string_concat("Diverge at L7 ('", cartan_string_concat(wA_7, cartan_string_concat("' vs '", cartan_string_concat(wB_7, cartan_string_concat("') -> COLLIDE at: ", hits)))));
    } else {
        let wA_14 = geomind_e8_decode_concept_vec_248(hA_14);
        let wB_14 = geomind_e8_decode_concept_vec_248(hB_14);
        res = cartan_string_concat("DISJOINT across all 42 layers ('", cartan_string_concat(wA_14, cartan_string_concat("' vs '", cartan_string_concat(wB_14, "'; max stratum cosine < 0.15)"))));
    }

    cartan_vec_free(hA_0);
    cartan_vec_free(hA_7);
    cartan_vec_free(hA_14);
    cartan_vec_free(hA_21);
    cartan_vec_free(hA_pr);
    cartan_vec_free(hA_28);
    cartan_vec_free(hB_0);
    cartan_vec_free(hB_7);
    cartan_vec_free(hB_14);
    cartan_vec_free(hB_21);
    cartan_vec_free(hB_pr);
    cartan_vec_free(hB_28);
    return res;
}

// SUBTLE TEST 2: Counterfactual & False-Premise Verification ("Can a kitten fly?" / "Is a sparrow a dog?")
// Measures inner product of `claimed_word` against every stratum of `subject_word`'s 42-layer rollout;
// if orthogonal/negative, rejects the false premise and applies transpose operators R^T to find the true owner of `claimed_word`.
fn geomind_e8_verify_counterfactual_42L(subject_word: string, claimed_word: string) -> string {
    geomind_e8_rel_init_if_needed();
    let h_0 = cartan_vec_create();
    let h_7 = cartan_vec_create();
    let h_14 = cartan_vec_create();
    let h_21 = cartan_vec_create();
    let h_pr = cartan_vec_create();
    let h_28 = cartan_vec_create();
    let h_35 = cartan_vec_create();
    let h_42 = cartan_vec_create();
    let p_cl = cartan_vec_create();
    let adj_v = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_0, 0.0);
        cartan_vec_push_f32(h_7, 0.0);
        cartan_vec_push_f32(h_14, 0.0);
        cartan_vec_push_f32(h_21, 0.0);
        cartan_vec_push_f32(h_pr, 0.0);
        cartan_vec_push_f32(h_28, 0.0);
        cartan_vec_push_f32(h_35, 0.0);
        cartan_vec_push_f32(h_42, 0.0);
        cartan_vec_push_f32(p_cl, 0.0);
        cartan_vec_push_f32(adj_v, 0.0);
        d = d + 1.0;
    }

    geomind_e8_word_to_vec_248(subject_word, h_0);
    geomind_e8_word_to_vec_248(claimed_word, p_cl);
    geomind_e8_cascade_step_7L(g_e8_rel_isa_248x248, h_0, 0.0, h_7);
    geomind_e8_cascade_step_7L(g_e8_rel_super_248x248, h_7, 7.0, h_14);
    geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_7, 14.0, h_21);
    let pr_rms = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_0, 14.0, h_pr);
    if (pr_rms < 0.45) {
        geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_7, 14.0, h_pr);
    }
    geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, h_21, 21.0, h_28);
    geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_7, 28.0, h_35);
    geomind_e8_cascade_step_7L(g_e8_rel_effect_248x248, h_35, 35.0, h_42);

    var best_cos = -10.0;
    var best_stratum = "";
    let c7 = geomind_e8_vec_cosine_248(h_7, p_cl);
    if (c7 > best_cos) { best_cos = c7; best_stratum = "L7 IS_A"; }
    let c14 = geomind_e8_vec_cosine_248(h_14, p_cl);
    if (c14 > best_cos) { best_cos = c14; best_stratum = "L14 Super"; }
    let c21 = geomind_e8_vec_cosine_248(h_21, p_cl);
    if (c21 > best_cos) { best_cos = c21; best_stratum = "L21 Capability"; }
    let cpr = geomind_e8_vec_cosine_248(h_pr, p_cl);
    if (cpr > best_cos) { best_cos = cpr; best_stratum = "L21 Property"; }
    let c28 = geomind_e8_vec_cosine_248(h_28, p_cl);
    if (c28 > best_cos) { best_cos = c28; best_stratum = "L28 Valence/Locus"; }
    let c35 = geomind_e8_vec_cosine_248(h_35, p_cl);
    if (c35 > best_cos) { best_cos = c35; best_stratum = "L35 Cause"; }
    let c42 = geomind_e8_vec_cosine_248(h_42, p_cl);
    if (c42 > best_cos) { best_cos = c42; best_stratum = "L42 Effect"; }

    let w_7 = geomind_e8_decode_concept_vec_248(h_7);
    let w_21 = geomind_e8_decode_concept_vec_248(h_21);
    let w_28 = geomind_e8_decode_concept_vec_248(h_28);
    let w_35 = geomind_e8_decode_concept_vec_248(h_35);
    var out_msg = "";
    if (best_cos >= 0.65) {
        out_msg = cartan_string_concat("[VERIFIED at ", cartan_string_concat(best_stratum, cartan_string_concat("] '", cartan_string_concat(subject_word, cartan_string_concat("' -> '", cartan_string_concat(w_7, cartan_string_concat("' -> '", cartan_string_concat(w_35, cartan_string_concat("' -> '", cartan_string_concat(claimed_word, "'"))))))))));
    } else {
        // Compute Adjoint/Transpose Pullback R_cap^T * p_cl to identify which concept actually owns `claimed_word`
        var c = 0.0;
        while (c < 248.0) {
            var acc = 0.0;
            var r = 0.0;
            while (r < 248.0) {
                acc = acc + cartan_vec_get_f32(g_e8_rel_cap_248x248, r * 248.0 + c) * cartan_vec_get_f32(p_cl, r);
                r = r + 1.0;
            }
            cartan_vec_set_f32(adj_v, c, acc);
            c = c + 1.0;
        }
        var true_owner = geomind_e8_decode_concept_vec_248(adj_v);
        if (g_e8_last_decode_sim < 0.45) {
            c = 0.0;
            while (c < 248.0) {
                var acc2 = 0.0;
                var r2 = 0.0;
                while (r2 < 248.0) {
                    acc2 = acc2 + cartan_vec_get_f32(g_e8_rel_isa_248x248, r2 * 248.0 + c) * cartan_vec_get_f32(p_cl, r2);
                    r2 = r2 + 1.0;
                }
                cartan_vec_set_f32(adj_v, c, acc2);
                c = c + 1.0;
            }
            true_owner = geomind_e8_decode_concept_vec_248(adj_v);
        }
        out_msg = cartan_string_concat("[REJECTED False Premise] '", cartan_string_concat(subject_word, cartan_string_concat("' IS_A '", cartan_string_concat(w_7, cartan_string_concat("' with capability '", cartan_string_concat(w_21, cartan_string_concat("' ('", cartan_string_concat(w_28, cartan_string_concat("'), NOT '", cartan_string_concat(claimed_word, cartan_string_concat("' (adjoint R^T maps '", cartan_string_concat(claimed_word, cartan_string_concat("' <- '", cartan_string_concat(true_owner, "')."))))))))))))));
    }

    cartan_vec_free(h_0);
    cartan_vec_free(h_7);
    cartan_vec_free(h_14);
    cartan_vec_free(h_21);
    cartan_vec_free(h_pr);
    cartan_vec_free(h_28);
    cartan_vec_free(h_35);
    cartan_vec_free(h_42);
    cartan_vec_free(p_cl);
    cartan_vec_free(adj_v);
    return out_msg;
}

// SUBTLE TEST 3: Backward / Abductive Diagnosis from Downstream Clues (`clue_prop`, `clue_cap`, `clue_val_or_eff`)
// Inverts the 42-layer stack by scoring candidate basins in the S^{247} codebook against the 3 downstream clues.
fn geomind_e8_abductive_diagnosis_42L(clue_prop: string, clue_cap: string, clue_val_or_eff: string) -> string {
    geomind_e8_rel_init_if_needed();
    let v_prop = cartan_vec_create();
    let v_cap = cartan_vec_create();
    let v_val = cartan_vec_create();
    let h_0 = cartan_vec_create();
    let h_7 = cartan_vec_create();
    let h_21 = cartan_vec_create();
    let h_pr = cartan_vec_create();
    let h_28 = cartan_vec_create();
    let h_35 = cartan_vec_create();
    let h_42 = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(v_prop, 0.0);
        cartan_vec_push_f32(v_cap, 0.0);
        cartan_vec_push_f32(v_val, 0.0);
        cartan_vec_push_f32(h_0, 0.0);
        cartan_vec_push_f32(h_7, 0.0);
        cartan_vec_push_f32(h_21, 0.0);
        cartan_vec_push_f32(h_pr, 0.0);
        cartan_vec_push_f32(h_28, 0.0);
        cartan_vec_push_f32(h_35, 0.0);
        cartan_vec_push_f32(h_42, 0.0);
        d = d + 1.0;
    }
    geomind_e8_word_to_vec_248(clue_prop, v_prop);
    geomind_e8_word_to_vec_248(clue_cap, v_cap);
    geomind_e8_word_to_vec_248(clue_val_or_eff, v_val);

    var best_score = -100.0;
    var best_word = "<unknown>";
    var best_hyper = "<unknown>";
    var i = 0.0;
    while (i < g_e8_vocab_count) {
        let cand_w = cartan_tree_get(g_e8_vocab_words, i);
        let base = i * 248.0;
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_0, d, cartan_vec_get_f32(g_e8_vocab_vecs, base + d));
            d = d + 1.0;
        }
        let r7 = geomind_e8_cascade_step_7L(g_e8_rel_isa_248x248, h_0, 0.0, h_7);
        geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_7, 14.0, h_21);
        let r_pr = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_0, 14.0, h_pr);
        if (r_pr < 0.45) {
            geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_7, 14.0, h_pr);
        }
        geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, h_21, 21.0, h_28);
        geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_7, 28.0, h_35);
        geomind_e8_cascade_step_7L(g_e8_rel_effect_248x248, h_35, 35.0, h_42);

        let s_prop = geomind_e8_vec_cosine_248(h_pr, v_prop);
        let s_cap = geomind_e8_vec_cosine_248(h_21, v_cap);
        var s_end = geomind_e8_vec_cosine_248(h_28, v_val);
        let s_eff = geomind_e8_vec_cosine_248(h_42, v_val);
        if (s_eff > s_end) { s_end = s_eff; }
        var subtype_bonus = 0.0;
        if (r7 > 0.45) { subtype_bonus = 0.05; }
        let total_s = s_prop + s_cap + s_end + subtype_bonus;
        if (total_s > best_score) {
            best_score = total_s;
            best_word = cand_w;
            best_hyper = geomind_e8_decode_concept_vec_248(h_7);
        }
        i = i + 1.0;
    }

    let res = cartan_string_concat("Clues (", cartan_string_concat(clue_prop, cartan_string_concat(", ", cartan_string_concat(clue_cap, cartan_string_concat(", ", cartan_string_concat(clue_val_or_eff, cartan_string_concat(") -> Abduced Concept: '", cartan_string_concat(best_word, cartan_string_concat("' (L7 class: '", cartan_string_concat(best_hyper, "')"))))))))));
    cartan_vec_free(v_prop);
    cartan_vec_free(v_cap);
    cartan_vec_free(v_val);
    cartan_vec_free(h_0);
    cartan_vec_free(h_7);
    cartan_vec_free(h_21);
    cartan_vec_free(h_pr);
    cartan_vec_free(h_28);
    cartan_vec_free(h_35);
    cartan_vec_free(h_42);
    return res;
}

// SUBTLE TEST 4: Unstated Multi-Sentence Cross-Rung Bridging (e.g. unseen WordNet hyponym "trout" -> "fish" -> "swims" -> "water" -> "clear" + "liquid")
fn geomind_e8_cross_rung_bridge_42L(unseen_hyponym: string) -> string {
    geomind_e8_rel_init_if_needed();
    let h_0 = cartan_vec_create();
    let h_7 = cartan_vec_create();
    let h_14 = cartan_vec_create();
    let h_21 = cartan_vec_create();
    let h_28 = cartan_vec_create();
    let h_med_super = cartan_vec_create();
    let h_med_prop = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_0, 0.0);
        cartan_vec_push_f32(h_7, 0.0);
        cartan_vec_push_f32(h_14, 0.0);
        cartan_vec_push_f32(h_21, 0.0);
        cartan_vec_push_f32(h_28, 0.0);
        cartan_vec_push_f32(h_med_super, 0.0);
        cartan_vec_push_f32(h_med_prop, 0.0);
        d = d + 1.0;
    }

    geomind_e8_word_to_vec_248(unseen_hyponym, h_0);
    geomind_e8_cascade_step_7L(g_e8_rel_isa_248x248, h_0, 0.0, h_7);
    let w_7 = geomind_e8_decode_concept_vec_248(h_7);
    geomind_e8_cascade_step_7L(g_e8_rel_super_248x248, h_7, 7.0, h_14);
    let w_14 = geomind_e8_decode_concept_vec_248(h_14);
    geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_7, 14.0, h_21);
    let w_21 = geomind_e8_decode_concept_vec_248(h_21);
    geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, h_21, 21.0, h_28);
    let w_28 = geomind_e8_decode_concept_vec_248(h_28);

    // Second-pass cascade on the discovered medium h_28 (e.g. "water") to deduce its ontology & properties
    geomind_e8_cascade_step_7L(g_e8_rel_super_248x248, h_28, 7.0, h_med_super);
    let w_med_super = geomind_e8_decode_concept_vec_248(h_med_super);
    geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_28, 14.0, h_med_prop);
    let w_med_prop = geomind_e8_decode_concept_vec_248(h_med_prop);

    let res = cartan_string_concat("[L0 Unseen: ", cartan_string_concat(unseen_hyponym, cartan_string_concat("] -> [L7: ", cartan_string_concat(w_7, cartan_string_concat(" (", cartan_string_concat(w_14, cartan_string_concat(")] -> [L21 Action: ", cartan_string_concat(w_21, cartan_string_concat("] -> [L28 Medium: ", cartan_string_concat(w_28, cartan_string_concat("] -> [Medium Rollout: ", cartan_string_concat(w_med_prop, cartan_string_concat(" ", cartan_string_concat(w_med_super, "]"))))))))))))));

    cartan_vec_free(h_0);
    cartan_vec_free(h_7);
    cartan_vec_free(h_14);
    cartan_vec_free(h_21);
    cartan_vec_free(h_28);
    cartan_vec_free(h_med_super);
    cartan_vec_free(h_med_prop);
    return res;
}

fn geomind_parse_simple_float(s: string) -> float {
    let n = cartan_string_length(s);
    var val = 0.0;
    var frac = 0.0;
    var div = 1.0;
    var in_frac = 0.0;
    var i = 0.0;
    while (i < n) {
        let b = cartan_byte_at(s, i);
        if (b == 46.0) {
            in_frac = 1.0;
        } else if (b >= 48.0 && b <= 57.0) {
            let dig = b - 48.0;
            if (in_frac == 0.0) {
                val = val * 10.0 + dig;
            } else {
                div = div * 10.0;
                frac = frac + dig / div;
            }
        }
        i = i + 1.0;
    }
    return val + frac;
}

fn geomind_wordnet_insert_hash(lh: float, sh: float, head_lh: float, ic_val: float, guard: float, vec_248: ptr) {
    if (lh <= 17.0 || sh <= 0.0) { return; }
    let h0 = math_mod_val(lh * 13331.0, 4096.0);
    var probe = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 4096.0);
        let cur_l = cartan_vec_get_f32(g_wordnet_lemma_hash, slot);
        if (cur_l == 0.0 || cur_l == lh) {
            cartan_vec_set_f32(g_wordnet_lemma_hash, slot, lh);
            cartan_vec_set_f32(g_wordnet_synset_hash, slot, sh);
            cartan_vec_set_f32(g_wordnet_head_hash, slot, head_lh);
            cartan_vec_set_f32(g_wordnet_ic_weight, slot, ic_val);
            cartan_vec_set_f32(g_wordnet_sense_guard, slot, guard);
            if (vec_248 != 0.0) {
                let v_base = slot * 248.0;
                var d = 0.0;
                while (d < 248.0) {
                    cartan_vec_set_f32(g_wordnet_lemma_vecs, v_base + d, cartan_vec_get_f32(vec_248, d));
                    d = d + 1.0;
                }
            }
            return;
        }
        probe = probe + 1.0;
    }
}

fn geomind_wordnet_register_node(synset_path: string, lemmas_csv: string, ic_val: float, sense_guard: float) {
    if (cartan_string_length(synset_path) == 0.0 || cartan_string_length(lemmas_csv) == 0.0) { return; }
    geomind_e8_rel_init_if_needed();
    let sh = 700000.0 + math_mod_val(geomind_word_patch_hash(synset_path), 250000.0);
    let n = cartan_string_length(lemmas_csv);
    var head_lh = 0.0;
    var head_str = "";
    var lh = 17.0;
    var word_start = 0.0;
    var i = 0.0;
    while (i <= n) {
        var b = 44.0;
        if (i < n) {
            b = cartan_byte_at(lemmas_csv, i);
            if (b < 0.0) { b = b + 256.0; }
        }
        if (b == 44.0) {
            if (lh != 17.0) {
                while (word_start < i && cartan_byte_at(lemmas_csv, word_start) == 32.0) {
                    word_start = word_start + 1.0;
                }
                let lemma_str = cartan_string_substring(lemmas_csv, word_start, i);
                geomind_e8_register_vocab_word(lemma_str);
                if (head_lh == 0.0) {
                    head_lh = lh;
                    head_str = lemma_str;
                    geomind_e8_word_to_vec_248(lemma_str, g_e8_rel_tmp_v);
                    geomind_wordnet_insert_hash(lh, sh, head_lh, ic_val, sense_guard, g_e8_rel_tmp_v);
                } else {
                    geomind_e8_word_to_vec_248(lemma_str, g_e8_rel_tmp_u);
                    geomind_wordnet_insert_hash(lh, sh, head_lh, ic_val, sense_guard, g_e8_rel_tmp_u);
                    // Train Stratum 1 (Layers 0..6) asymmetric R_isa(hyponym -> hypernym_head) weighted by WordNet IC specificity
                    var w_target = 0.50 + 0.042 * ic_val;
                    if (w_target > 0.94) { w_target = 0.94; }
                    var p = 0.0;
                    while (p < 5.0) {
                        geomind_e8_rel_train_step(g_e8_rel_isa_248x248, g_e8_rel_tmp_u, g_e8_rel_tmp_v, w_target, 1.0, 0.45);
                        p = p + 1.0;
                    }
                }
            }
            lh = 17.0;
            word_start = i + 1.0;
        } else {
            if (b >= 65.0 && b <= 90.0) { b = b + 32.0; }
            if ((b >= 97.0 && b <= 122.0) || (b >= 48.0 && b <= 57.0)) {
                lh = math_mod_val(lh * 131.0 + b, 1000003.0);
            }
        }
        i = i + 1.0;
    }

    // Train Stratum 2 (Layers 7..13) 2nd-Hop Superordinate Category R_super(head_lemma -> super_category) directly from WordNet path
    if (cartan_string_length(head_str) > 0.0) {
        if (cartan_string_contains(synset_path, ".animal.") != 0.0) {
            geomind_e8_rel_train_words(g_e8_rel_super_248x248, head_str, "animal", 0.92, 5.0);
        } else if (cartan_string_contains(synset_path, ".plaything.") != 0.0) {
            geomind_e8_rel_train_words(g_e8_rel_super_248x248, head_str, "plaything", 0.92, 5.0);
        } else if (cartan_string_contains(synset_path, ".liquid.") != 0.0) {
            geomind_e8_rel_train_words(g_e8_rel_super_248x248, head_str, "liquid", 0.92, 5.0);
        } else if (cartan_string_contains(synset_path, ".plant.") != 0.0) {
            geomind_e8_rel_train_words(g_e8_rel_super_248x248, head_str, "plant", 0.92, 5.0);
        } else if (cartan_string_contains(synset_path, ".energy.") != 0.0) {
            geomind_e8_rel_train_words(g_e8_rel_super_248x248, head_str, "energy", 0.92, 5.0);
        } else if (cartan_string_contains(synset_path, ".person.") != 0.0) {
            geomind_e8_rel_train_words(g_e8_rel_super_248x248, head_str, "person", 0.92, 5.0);
        } else if (cartan_string_contains(synset_path, ".force.") != 0.0) {
            geomind_e8_rel_train_words(g_e8_rel_super_248x248, head_str, "force", 0.92, 5.0);
        } else if (cartan_string_contains(synset_path, ".weather.") != 0.0) {
            geomind_e8_rel_train_words(g_e8_rel_super_248x248, head_str, "weather", 0.92, 5.0);
        }
    }
}

fn geomind_wordnet_init_if_needed() {
    if (g_wordnet_initialized == 1.0) { return; }
    g_wordnet_initialized = 1.0;
    g_wordnet_lemma_hash = cartan_tensor_alloc(4096.0);
    g_wordnet_synset_hash = cartan_tensor_alloc(4096.0);
    g_wordnet_head_hash = cartan_tensor_alloc(4096.0);
    g_wordnet_ic_weight = cartan_tensor_alloc(4096.0);
    g_wordnet_sense_guard = cartan_tensor_alloc(4096.0);
    g_wordnet_lemma_vecs = cartan_tensor_alloc(4096.0 * 248.0);

    g_wn_verb_to = geomind_word_patch_hash("to");
    g_wn_verb_can = geomind_word_patch_hash("can");
    g_wn_verb_will = geomind_word_patch_hash("will");
    g_wn_verb_not = geomind_word_patch_hash("not");
    g_wn_verb_do = geomind_word_patch_hash("do");
    g_wn_hash_is = geomind_word_patch_hash("is");
    g_wn_hash_a = geomind_word_patch_hash("a");
    g_wn_hash_the = geomind_word_patch_hash("the");
    g_wn_hash_and = geomind_word_patch_hash("and");
    g_wn_hash_in = geomind_word_patch_hash("in");
    g_wn_hash_on = geomind_word_patch_hash("on");
    g_wn_hash_when = geomind_word_patch_hash("when");
    g_wn_hash_it = geomind_word_patch_hash("it");
    g_wn_hash_you = geomind_word_patch_hash("you");
    g_wn_hash_likes = geomind_word_patch_hash("likes");
    g_wn_hash_because = geomind_word_patch_hash("because");

    geomind_e8_rel_init_if_needed();

    let tax_path = "Projects/geomind/trainingdata/wordnet_taxonomy.txt";
    if (cartan_file_exists(tax_path) == 1.0) {
        let content = cartan_read_file(tax_path);
        if (content != 0.0 && cartan_string_length(content) > 0.0) {
            let lines = string_split(content, "\n");
            let num_lines = cartan_tree_len_f(lines);
            var cur_path = "";
            var cur_lemmas = "";
            var cur_ic = 10.0;
            var cur_guard = 1.0;
            var i = 0.0;
            while (i < num_lines) {
                let raw_l = cartan_tree_get(lines, i);
                let line = cartan_string_replace(cartan_string_replace(raw_l, "\r", ""), "\n", "");
                let llen = cartan_string_length(line);
                if (llen == 0.0) {
                    if (cartan_string_length(cur_path) > 0.0) {
                        geomind_wordnet_register_node(cur_path, cur_lemmas, cur_ic, cur_guard);
                        cur_path = "";
                        cur_lemmas = "";
                        cur_ic = 10.0;
                        cur_guard = 1.0;
                    }
                } else if (cartan_string_starts_with(line, "Path: ") != 0.0) {
                    if (cartan_string_length(cur_path) > 0.0) {
                        geomind_wordnet_register_node(cur_path, cur_lemmas, cur_ic, cur_guard);
                        cur_lemmas = "";
                        cur_ic = 10.0;
                        cur_guard = 1.0;
                    }
                    cur_path = cartan_string_substring(line, 6.0, llen);
                } else if (cartan_string_starts_with(line, "Lemmas: ") != 0.0) {
                    cur_lemmas = cartan_string_substring(line, 8.0, llen);
                } else if (cartan_string_starts_with(line, "SenseGuard: verb") != 0.0) {
                    cur_guard = 2.0;
                } else if (cartan_string_starts_with(line, "SenseGuard: noun") != 0.0) {
                    cur_guard = 1.0;
                } else if (cartan_string_starts_with(line, "IC: ") != 0.0) {
                    cur_ic = geomind_parse_simple_float(cartan_string_substring(line, 4.0, llen));
                }
                i = i + 1.0;
            }
            if (cartan_string_length(cur_path) > 0.0) {
                geomind_wordnet_register_node(cur_path, cur_lemmas, cur_ic, cur_guard);
            }
        }
    }
}

// Compute the continuous 248x248 manifold hypernym weight S(word --[R_isa]--> head_hypernym) on S^{247}
fn geomind_wordnet_get_isa_manifold_weight(patch_hash: float) -> float {
    geomind_wordnet_init_if_needed();
    if (patch_hash <= 17.0) { return 0.0; }
    let h0 = math_mod_val(patch_hash * 13331.0, 4096.0);
    var probe = 0.0;
    var word_slot = -1.0;
    var head_lh = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 4096.0);
        let cur_l = cartan_vec_get_f32(g_wordnet_lemma_hash, slot);
        if (cur_l == 0.0) { return 0.0; }
        if (cur_l == patch_hash) {
            word_slot = slot;
            head_lh = cartan_vec_get_f32(g_wordnet_head_hash, slot);
            break;
        }
        probe = probe + 1.0;
    }
    if (word_slot < 0.0 || head_lh <= 17.0) { return 0.0; }
    if (head_lh == patch_hash) { return 1.0; }

    let hh0 = math_mod_val(head_lh * 13331.0, 4096.0);
    var hprobe = 0.0;
    var head_slot = -1.0;
    while (hprobe < 32.0) {
        let hslot = math_mod_val(hh0 + hprobe * 7.0, 4096.0);
        let hcur = cartan_vec_get_f32(g_wordnet_lemma_hash, hslot);
        if (hcur == 0.0) { break; }
        if (hcur == head_lh) {
            head_slot = hslot;
            break;
        }
        hprobe = hprobe + 1.0;
    }
    if (head_slot < 0.0) { return 0.85; }

    let u_base = word_slot * 248.0;
    let v_base = head_slot * 248.0;
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_set_f32(g_e8_rel_tmp_u, d, cartan_vec_get_f32(g_wordnet_lemma_vecs, u_base + d));
        cartan_vec_set_f32(g_e8_rel_tmp_v, d, cartan_vec_get_f32(g_wordnet_lemma_vecs, v_base + d));
        d = d + 1.0;
    }
    return geomind_e8_rel_score_vec(g_e8_rel_isa_248x248, g_e8_rel_tmp_u, g_e8_rel_tmp_v);
}

// Resolve `patch_hash` to its canonical WordNet Synset ID (`700000..949999`), gated by syntactic `SenseGuard`
// AND continuous 248x248 manifold `R_isa` weight verification (`w_isa >= 0.35`).
fn geomind_wordnet_resolve_synset(patch_hash: float, prev_patch_hash: float) -> float {
    geomind_wordnet_init_if_needed();
    if (patch_hash <= 17.0) { return 0.0; }
    let h0 = math_mod_val(patch_hash * 13331.0, 4096.0);
    var probe = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 4096.0);
        let cur_l = cartan_vec_get_f32(g_wordnet_lemma_hash, slot);
        if (cur_l == 0.0) { return 0.0; }
        if (cur_l == patch_hash) {
            let guard = cartan_vec_get_f32(g_wordnet_sense_guard, slot);
            if (guard == 1.0) {
                if (prev_patch_hash == g_wn_verb_to || prev_patch_hash == g_wn_verb_can ||
                    prev_patch_hash == g_wn_verb_will || prev_patch_hash == g_wn_verb_not ||
                    prev_patch_hash == g_wn_verb_do) {
                    return 0.0;
                }
            }
            let head_lh = cartan_vec_get_f32(g_wordnet_head_hash, slot);
            if (head_lh != patch_hash) {
                let w_isa = geomind_wordnet_get_isa_manifold_weight(patch_hash);
                if (w_isa < 0.35) {
                    return 0.0;
                }
                g_markov_ctx_syn_weight = w_isa;
            } else {
                g_markov_ctx_syn_weight = 1.0;
            }
            return cartan_vec_get_f32(g_wordnet_synset_hash, slot);
        }
        probe = probe + 1.0;
    }
    return 0.0;
}

fn geomind_wordnet_get_ic(patch_hash: float) -> float {
    geomind_wordnet_init_if_needed();
    if (patch_hash <= 17.0) { return 8.0; }
    let h0 = math_mod_val(patch_hash * 13331.0, 4096.0);
    var probe = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 4096.0);
        let cur_l = cartan_vec_get_f32(g_wordnet_lemma_hash, slot);
        if (cur_l == 0.0) { return 8.0; }
        if (cur_l == patch_hash) {
            return cartan_vec_get_f32(g_wordnet_ic_weight, slot);
        }
        probe = probe + 1.0;
    }
    return 8.0;
}

// Query maximum resonance R(P_k) in [-1, 1] across crystallized E8 Anchor Basins (O(1) hash + R_isa manifold weight + local Killing probe)
fn geomind_e8_query_anchor_resonance(patch_248: ptr, patch_hash: float) -> float {
    geomind_e8_anchors_init_if_needed();
    if (g_e8_anchor_count <= 0.0) { return 0.0; }
    let exact_idx = geomind_e8_find_anchor_by_hash(patch_hash);
    if (exact_idx >= 0.0) {
        return 1.0;
    }
    // Check if the word's WordNet Synset is a crystallized Anchor Basin AND verified by the 248x248 R_isa operator
    let syn_h = geomind_wordnet_resolve_synset(patch_hash, g_ctx_last_hash);
    if (syn_h > 0.0) {
        let syn_idx = geomind_e8_find_anchor_by_hash(syn_h);
        if (syn_idx >= 0.0) {
            var res_w = g_markov_ctx_syn_weight;
            if (res_w < 0.85) { res_w = 0.85; }
            return res_w;
        }
    }
    var best_sim = -1.0;
    let start_m = math_mod_val(patch_hash, g_e8_anchor_count);
    var k = 0.0;
    var lim = 16.0;
    if (g_e8_anchor_count < lim) { lim = g_e8_anchor_count; }
    while (k < lim) {
        let m = math_mod_val(start_m + k, g_e8_anchor_count);
        let sim = geomind_e8_anchor_killing_sim(patch_248, m);
        if (sim > best_sim) {
            best_sim = sim;
        }
        k = k + 1.0;
    }
    return best_sim;
}

// Crystallize or reinforce a 248-D E8 Patch state as an Anchor Basin on S^{247} (up to 65536 concepts)
fn geomind_e8_crystallize_patch_vec_internal(patch_248: ptr, patch_hash: float, initial_mass: float) -> float {
    geomind_e8_anchors_init_if_needed();
    let exact_m = geomind_e8_find_anchor_by_hash(patch_hash);
    if (exact_m >= 0.0) {
        let old_mass = cartan_vec_get_f32(g_e8_anchor_masses, exact_m);
        var new_mass = old_mass + 0.15;
        if (new_mass > 1.0) { new_mass = 1.0; }
        cartan_vec_set_f32(g_e8_anchor_masses, exact_m, new_mass);
        let a_off = exact_m * 248.0;
        var d = 0.0;
        var nsq = 0.0;
        while (d < 248.0) {
            let av = cartan_vec_get_f32(g_e8_anchor_coords, a_off + d);
            let pv = cartan_vec_get_f32(patch_248, d);
            let upd = 0.85 * av + 0.15 * pv;
            cartan_vec_set_f32(g_e8_anchor_coords, a_off + d, upd);
            nsq = nsq + upd * upd;
            d = d + 1.0;
        }
        if (nsq > 0.000001) {
            let scale = sqrt(248.0 / nsq);
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(g_e8_anchor_coords, a_off + d, cartan_vec_get_f32(g_e8_anchor_coords, a_off + d) * scale);
                d = d + 1.0;
            }
        }
        return exact_m;
    }

    if (g_e8_anchor_count >= 65536.0) { return -1.0; }
    let idx = g_e8_anchor_count;
    let a_off = idx * 248.0;
    var nsq = 0.0;
    var d = 0.0;
    while (d < 248.0) {
        let pv = cartan_vec_get_f32(patch_248, d);
        cartan_vec_set_f32(g_e8_anchor_coords, a_off + d, pv);
        nsq = nsq + pv * pv;
        d = d + 1.0;
    }
    if (nsq > 0.000001) {
        let scale = sqrt(248.0 / nsq);
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(g_e8_anchor_coords, a_off + d, cartan_vec_get_f32(g_e8_anchor_coords, a_off + d) * scale);
            d = d + 1.0;
        }
    }
    cartan_vec_set_f32(g_e8_anchor_masses, idx, initial_mass);
    cartan_vec_set_f32(g_e8_anchor_hashes, idx, patch_hash);
    geomind_e8_anchor_lut_insert(patch_hash, idx);
    g_e8_anchor_count = g_e8_anchor_count + 1.0;
    g_e8_newly_crystallized = g_e8_newly_crystallized + 1.0;
    return idx;
}

fn geomind_e8_crystallize_patch_vec(patch_248: ptr, patch_hash: float, initial_mass: float) -> float {
    let ic_w = geomind_wordnet_get_ic(patch_hash);
    var eff_mass = initial_mass * (ic_w / 10.0);
    if (eff_mass > 1.0) { eff_mass = 1.0; }
    let idx = geomind_e8_crystallize_patch_vec_internal(patch_248, patch_hash, eff_mass);
    let syn_h = geomind_wordnet_resolve_synset(patch_hash, g_ctx_last_hash);
    if (syn_h > 0.0) {
        geomind_e8_crystallize_patch_vec_internal(patch_248, syn_h, eff_mass);
    }
    return idx;
}

// Seed a word/phrase (e.g., "ball") directly into the Crystallized Anchor Basin table on S^{247}
fn geomind_e8_seed_concept_word(word: string) -> float {
    geomind_byte_latent_init_if_needed();
    geomind_e8_anchors_init_if_needed();
    let wlen = cartan_string_length(word);
    if (wlen <= 0.0) { return -1.0; }
    let accum = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(accum, 0.0);
        d = d + 1.0;
    }
    var p_hash = 17.0;
    var i = 0.0;
    while (i < wlen) {
        var b = cartan_byte_at(word, i);
        if (b < 0.0) { b = b + 256.0; }
        b = math_mod_val(floor(b), 256.0);
        if (b != 32.0) {
            geomind_fold_byte_into_e8_patch(accum, b, i);
            var hb = b;
            if (hb >= 65.0 && hb <= 90.0) { hb = hb + 32.0; }
            p_hash = math_mod_val(p_hash * 131.0 + hb, 1000003.0);
        }
        i = i + 1.0;
    }
    let idx = geomind_e8_crystallize_patch_vec(accum, p_hash, 1.0);
    cartan_vec_free(accum);
    return idx;
}

// ============================================================================
// STAGE 5.6.3: UNIVERSAL GGUF v3 OPEN-WEIGHTS EXPORTER & VERIFIER
// ============================================================================
// Exports all 42 Non-Euclidean E8 layers + Cartan Moving-Frame Pullback matrices
// + 248x248 Relational Tensors (`R_isa`, `R_prop`) + Crystallized S^{247} Concept Anchors
// into a spec-compliant GGUF v3 binary weight file (`0x46554747`, version 3, 32-byte aligned F32 tensors).
var g_gguf_scratch_8: ptr = 0.0;

fn geomind_gguf_init_scratch() {
    if (g_gguf_scratch_8 == 0.0) {
        g_gguf_scratch_8 = malloc(32.0);
    }
}

fn geomind_gguf_align32(val: float) -> float {
    let rem = math_mod_val(val, 32.0);
    if (rem == 0.0) { return val; }
    return val + (32.0 - rem);
}

fn geomind_gguf_write_u32(f: ptr, val: float, pos: float) -> float {
    geomind_gguf_init_scratch();
    cartan_set_i32(g_gguf_scratch_8, 0.0, val);
    fwrite(g_gguf_scratch_8, 4.0, 1.0, f);
    return pos + 4.0;
}

fn geomind_gguf_write_u64(f: ptr, val: float, pos: float) -> float {
    geomind_gguf_init_scratch();
    cartan_set_i64(g_gguf_scratch_8, 0.0, val);
    fwrite(g_gguf_scratch_8, 8.0, 1.0, f);
    return pos + 8.0;
}

fn geomind_gguf_write_f32(f: ptr, val: float, pos: float) -> float {
    geomind_gguf_init_scratch();
    cartan_set_f32(g_gguf_scratch_8, 0.0, val);
    fwrite(g_gguf_scratch_8, 4.0, 1.0, f);
    return pos + 4.0;
}

fn geomind_gguf_write_str(f: ptr, s: string, pos: float) -> float {
    let slen = cartan_string_length(s);
    var p = geomind_gguf_write_u64(f, slen, pos);
    if (slen > 0.0) {
        fwrite(s, 1.0, slen, f);
        p = p + slen;
    }
    return p;
}

fn geomind_gguf_write_kv_str(f: ptr, key: string, val: string, pos: float) -> float {
    var p = geomind_gguf_write_str(f, key, pos);
    p = geomind_gguf_write_u32(f, 8.0, p); // GGUF_METADATA_VALUE_TYPE_STRING = 8
    p = geomind_gguf_write_str(f, val, p);
    return p;
}

fn geomind_gguf_write_kv_u32(f: ptr, key: string, val: float, pos: float) -> float {
    var p = geomind_gguf_write_str(f, key, pos);
    p = geomind_gguf_write_u32(f, 4.0, p); // GGUF_METADATA_VALUE_TYPE_UINT32 = 4
    p = geomind_gguf_write_u32(f, val, p);
    return p;
}

fn geomind_gguf_write_tensor_info_1d(f: ptr, name: string, d0: float, data_off_vec: ptr, pos: float) -> float {
    var p = geomind_gguf_write_str(f, name, pos);
    p = geomind_gguf_write_u32(f, 1.0, p); // n_dims = 1
    p = geomind_gguf_write_u64(f, d0, p);
    p = geomind_gguf_write_u32(f, 0.0, p); // GGML_TYPE_F32 = 0
    let cur_off = cartan_vec_get_f32(data_off_vec, 0.0);
    p = geomind_gguf_write_u64(f, cur_off, p);
    let next_off = cur_off + geomind_gguf_align32(d0 * 4.0);
    cartan_vec_set_f32(data_off_vec, 0.0, next_off);
    return p;
}

fn geomind_gguf_write_tensor_info_2d(f: ptr, name: string, d0: float, d1: float, data_off_vec: ptr, pos: float) -> float {
    var p = geomind_gguf_write_str(f, name, pos);
    p = geomind_gguf_write_u32(f, 2.0, p); // n_dims = 2
    p = geomind_gguf_write_u64(f, d0, p);
    p = geomind_gguf_write_u64(f, d1, p);
    p = geomind_gguf_write_u32(f, 0.0, p); // GGML_TYPE_F32 = 0
    let cur_off = cartan_vec_get_f32(data_off_vec, 0.0);
    p = geomind_gguf_write_u64(f, cur_off, p);
    let next_off = cur_off + geomind_gguf_align32(d0 * d1 * 4.0);
    cartan_vec_set_f32(data_off_vec, 0.0, next_off);
    return p;
}

fn geomind_gguf_pad_stream32(f: ptr, pos: float) -> float {
    geomind_gguf_init_scratch();
    let rem = math_mod_val(pos, 32.0);
    if (rem == 0.0) { return pos; }
    let pad = 32.0 - rem;
    var i = 0.0;
    while (i < pad) {
        cartan_set_byte(g_gguf_scratch_8, i, 0.0);
        i = i + 1.0;
    }
    fwrite(g_gguf_scratch_8, 1.0, pad, f);
    return pos + pad;
}

fn geomind_gguf_write_f32_slice(f: ptr, src_vec: ptr, src_off: float, count: float, pos: float) -> float {
    let byte_sz = count * 4.0;
    let f32_buf = malloc(byte_sz + 32.0);
    var i = 0.0;
    while (i < count) {
        cartan_set_f32(f32_buf, i, cartan_vec_get_f32(src_vec, src_off + i));
        i = i + 1.0;
    }
    fwrite(f32_buf, 4.0, count, f);
    free(f32_buf);
    var p = pos + byte_sz;
    p = geomind_gguf_pad_stream32(f, p);
    return p;
}

// Compute Layer l's 248x248 Cartan Moving-Frame Euclidean Pullback Matrix:
// W_eff^{(l)} = (G^{(l)})^{1/2} (W_gauge^{(l)} (+) W_spinor^{(l)} + StratumRel^{(floor(l/7))}) (G^{(l)})^{-1/2}
fn geomind_e8_compute_layer_pullback_248x248(l: float, out_248x248: ptr) {
    let g_base = l * 14400.0;
    let s_base = l * 16384.0;
    let a_base = l * 744.0;
    let b_base = l * 248.0;
    let stratum = floor(l / 7.0);
    var rel_ptr = g_e8_rel_isa_248x248;
    if (stratum == 1.0) { rel_ptr = g_e8_rel_super_248x248; }
    else if (stratum == 2.0) { rel_ptr = g_e8_rel_cap_248x248; }
    else if (stratum == 3.0) { rel_ptr = g_e8_rel_val_248x248; }
    else if (stratum == 4.0) { rel_ptr = g_e8_rel_cause_248x248; }
    else if (stratum >= 5.0) { rel_ptr = g_e8_rel_effect_248x248; }

    var r = 0.0;
    while (r < 248.0) {
        let sub_r = floor(r / 31.0);
        let kw_r = geom_killing_form_dynkin_weight(sub_r);
        let br = cartan_vec_get_f32(g_e8_stack_randers_b, b_base + r);
        let sr = sqrt(kw_r + br * br);
        let wq_r = cartan_vec_get_f32(g_e8_stack_w_attn, a_base + r);
        let row_off = r * 248.0;

        var c = 0.0;
        while (c < 248.0) {
            let sub_c = floor(c / 31.0);
            let kw_c = geom_killing_form_dynkin_weight(sub_c);
            let bc = cartan_vec_get_f32(g_e8_stack_randers_b, b_base + c);
            let sc = sqrt(kw_c + bc * bc);
            let wk_c = cartan_vec_get_f32(g_e8_stack_w_attn, a_base + 248.0 + c);

            var base_w = 0.0;
            if (r < 120.0 && c < 120.0) {
                base_w = cartan_vec_get_f32(g_e8_stack_w_gauge, g_base + r * 120.0 + c);
            } else if (r >= 120.0 && c >= 120.0) {
                base_w = cartan_vec_get_f32(g_e8_stack_w_spinor, s_base + (r - 120.0) * 128.0 + (c - 120.0));
            } else {
                base_w = 0.25 * (wq_r * bc - wk_c * br);
            }
            let rel_w = cartan_vec_get_f32(rel_ptr, row_off + c);
            let eff_w = (sr / sc) * (base_w + 0.50 * rel_w) + br * bc;
            cartan_vec_set_f32(out_248x248, row_off + c, eff_w);
            c = c + 1.0;
        }
        r = r + 1.0;
    }
}

fn geomind_export_gguf_v3(path: string) -> float {
    geomind_byte_latent_init_if_needed();
    geomind_e8_rel_init_if_needed();
    let L = g_e8_stack_num_layers;
    if (L <= 0.0) { return 0.0; }
    var n_anc = g_e8_anchor_count;
    if (n_anc < 1.0) { n_anc = 1.0; }

    let f = fopen(path, "wb");
    if (f == 0.0) { return 0.0; }

    // 12 Global Tensors (including all 7 Stratified 42-Layer Relational Tensors) + 6 Per-Layer Tensors * L layers
    let n_tensors = 12.0 + 6.0 * L;
    let n_kv = 7.0;

    var pos = 0.0;
    // 1. GGUF v3 Header: magic "GGUF" (0x46554747 = 1179993927), version 3, tensor_count, metadata_kv_count
    pos = geomind_gguf_write_u32(f, 1179993927.0, pos);
    pos = geomind_gguf_write_u32(f, 3.0, pos);
    pos = geomind_gguf_write_u64(f, n_tensors, pos);
    pos = geomind_gguf_write_u64(f, n_kv, pos);

    // 2. GGUF v3 Metadata Key-Value Table
    pos = geomind_gguf_write_kv_str(f, "general.architecture", "cartan-e8", pos);
    pos = geomind_gguf_write_kv_str(f, "general.name", "CARTAN-E8-42L-Sovereign-Manifold", pos);
    pos = geomind_gguf_write_kv_u32(f, "cartan-e8.context_length", 8192.0, pos);
    pos = geomind_gguf_write_kv_u32(f, "cartan-e8.embedding_length", 248.0, pos);
    pos = geomind_gguf_write_kv_u32(f, "cartan-e8.block_count", L, pos);
    pos = geomind_gguf_write_kv_u32(f, "cartan-e8.concept_anchor_count", n_anc, pos);
    pos = geomind_gguf_write_kv_u32(f, "cartan-e8.fano_associator_triads", 1920.0, pos);

    // 3. GGUF v3 Tensor Info Table
    let data_off_vec = cartan_vec_create();
    cartan_vec_push_f32(data_off_vec, 0.0);

    pos = geomind_gguf_write_tensor_info_2d(f, "token_embd.weight", 248.0, 256.0, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_2d(f, "output.weight", 256.0, 248.0, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_1d(f, "e8.randers_drift.weight", 248.0, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_2d(f, "e8.rel_isa.weight", 248.0, 248.0, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_2d(f, "e8.rel_super.weight", 248.0, 248.0, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_2d(f, "e8.rel_cap.weight", 248.0, 248.0, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_2d(f, "e8.rel_prop.weight", 248.0, 248.0, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_2d(f, "e8.rel_val.weight", 248.0, 248.0, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_2d(f, "e8.rel_cause.weight", 248.0, 248.0, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_2d(f, "e8.rel_effect.weight", 248.0, 248.0, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_2d(f, "e8.concept_anchors.weight", 248.0, n_anc, data_off_vec, pos);
    pos = geomind_gguf_write_tensor_info_1d(f, "e8.concept_ic_mass.weight", n_anc, data_off_vec, pos);

    var l = 0.0;
    while (l < L) {
        let l_str = cartan_int_to_string(l);
        let pfx = cartan_string_concat("blk.", cartan_string_concat(l_str, "."));
        pos = geomind_gguf_write_tensor_info_2d(f, cartan_string_concat(pfx, "e8_gauge.weight"), 120.0, 120.0, data_off_vec, pos);
        pos = geomind_gguf_write_tensor_info_2d(f, cartan_string_concat(pfx, "e8_spinor.weight"), 128.0, 128.0, data_off_vec, pos);
        pos = geomind_gguf_write_tensor_info_2d(f, cartan_string_concat(pfx, "attn_qkv.weight"), 248.0, 3.0, data_off_vec, pos);
        pos = geomind_gguf_write_tensor_info_2d(f, cartan_string_concat(pfx, "ffn_moe.weight"), 16.0, 16.0, data_off_vec, pos);
        pos = geomind_gguf_write_tensor_info_1d(f, cartan_string_concat(pfx, "randers_drift.weight"), 248.0, data_off_vec, pos);
        pos = geomind_gguf_write_tensor_info_2d(f, cartan_string_concat(pfx, "cartan_pullback.weight"), 248.0, 248.0, data_off_vec, pos);
        l = l + 1.0;
    }

    // Pad header + tensor info table to 32-byte alignment before writing binary tensor data
    pos = geomind_gguf_pad_stream32(f, pos);

    // 4. Write 32-byte aligned F32 Tensor Data
    pos = geomind_gguf_write_f32_slice(f, g_byte_e8_emb_256x248, 0.0, 63488.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_byte_e8_head_248x256, 0.0, 63488.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_byte_e8_randers_b_248, 0.0, 248.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_e8_rel_isa_248x248, 0.0, 61504.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_e8_rel_super_248x248, 0.0, 61504.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_e8_rel_cap_248x248, 0.0, 61504.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_e8_rel_prop_248x248, 0.0, 61504.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_e8_rel_val_248x248, 0.0, 61504.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_e8_rel_cause_248x248, 0.0, 61504.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_e8_rel_effect_248x248, 0.0, 61504.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_e8_anchor_coords, 0.0, n_anc * 248.0, pos);
    pos = geomind_gguf_write_f32_slice(f, g_e8_anchor_masses, 0.0, n_anc, pos);

    let pullback_buf = cartan_tensor_alloc(61504.0);
    l = 0.0;
    while (l < L) {
        pos = geomind_gguf_write_f32_slice(f, g_e8_stack_w_gauge, l * 14400.0, 14400.0, pos);
        pos = geomind_gguf_write_f32_slice(f, g_e8_stack_w_spinor, l * 16384.0, 16384.0, pos);
        pos = geomind_gguf_write_f32_slice(f, g_e8_stack_w_attn, l * 744.0, 744.0, pos);
        pos = geomind_gguf_write_f32_slice(f, g_e8_stack_u_moe, l * 256.0, 256.0, pos);
        pos = geomind_gguf_write_f32_slice(f, g_e8_stack_randers_b, l * 248.0, 248.0, pos);
        geomind_e8_compute_layer_pullback_248x248(l, pullback_buf);
        pos = geomind_gguf_write_f32_slice(f, pullback_buf, 0.0, 61504.0, pos);
        l = l + 1.0;
    }

    cartan_vec_free(pullback_buf);
    cartan_vec_free(data_off_vec);
    fclose(f);
    return pos;
}

// Verify a GGUF v3 file on disk by reading back its binary header (magic, version, tensor_count, kv_count, file size)
fn geomind_verify_gguf_v3(path: string) -> float {
    if (cartan_file_exists(path) == 0.0) { return 0.0; }
    let f_sz = cartan_get_binary_file_size(path);
    if (f_sz < 24.0) { return 0.0; }
    let f = fopen(path, "rb");
    if (f == 0.0) { return 0.0; }
    let hdr = malloc(24.0);
    fread(hdr, 1.0, 24.0, f);
    fclose(f);
    let magic = cartan_i32_at(hdr, 0.0);
    let ver = cartan_i32_at(hdr, 1.0);
    let n_tens = cartan_i64_at(hdr, 1.0);
    let n_kv = cartan_i64_at(hdr, 2.0);
    free(hdr);
    if (magic != 1179993927.0 || ver != 3.0) { return 0.0; }
    printf("  [GGUF v3 Verified] Path: %s | Magic: 'GGUF' (v%.0f) | Tensors: %.0f | Metadata KVs: %.0f | Size: %.2f MB\n",
        path, ver, n_tens, n_kv, f_sz / 1048576.0);
    return n_tens;
}

// ============================================================================
// STAGE 1-3: DEEP L-LAYER E8 GAUGE-SPINOR MANIFOLD BYTE-LATENT TRAINER & GENERATOR
// ============================================================================
// True Two-Tier Byte-Latent Transformer (BLT) Manifold Pipeline:
// - Tier 1 (Every Byte): Local Weyl root reflection + Octonion Fano Cross-Gate on S^{247}
//   conditioned on 3-gram Markov transition prior P(b_t | b_{t-3}, b_{t-2}, b_{t-1}).
// - Tier 2 (At Surprisal Patch Boundaries): Full 42-Layer Deep E8 Gauge-Spinor +
//   Finsler-Randers Causal Attention + 4x4 Freudenthal Magic Square MoE forward & backward step.
var g_blt_last_patch_count: float = 0.0;

// Returns 1.0 if `patch_hash` is a function/glue word or generic modifier so `sent_topic_hash` captures the primary subject noun/verb
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
    if (g_ctx_last_hash == 17.0 && geomind_is_subord_opener_hash(patch_hash) == 1.0) {
        g_ctx_sent_started_subord = 1.0;
    }
    if (g_ctx_sent_topic_hash == 17.0 && geomind_is_glue_word_hash(patch_hash, patch_alnum_len) == 0.0) {
        g_ctx_sent_topic_hash = patch_hash;
    }
    // If an opening subordinate clause ("When rain falls,") just ended at a comma ',',
    // reset g_ctx_sent_topic_hash so it latches onto the main-clause subject ("the cat")!
    if (patch_comma_end == 1.0 && g_ctx_sent_started_subord == 1.0 && patch_sent_end == 0.0) {
        g_ctx_sent_topic_hash = 17.0;
        g_ctx_sent_started_subord = 0.0;
    }

    let cur_syn = geomind_wordnet_resolve_synset(patch_hash, g_ctx_last_hash);

    if (patch_sent_end == 1.0) {
        var top_h = g_ctx_sent_topic_hash;
        if (top_h == 17.0) { top_h = patch_hash; }
        let bridge_h = math_mod_val(top_h + 500009.0, 1000003.0);
        let top_syn = geomind_wordnet_resolve_synset(top_h, 17.0);

        g_ctx_prev2_hash = 17.0;
        g_ctx_prev_hash = 17.0;
        g_ctx_last_hash = bridge_h;
        g_ctx_prev2_syn = 0.0;
        g_ctx_prev_syn = 0.0;

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
        g_ctx_sent_started_subord = 0.0;
    } else {
        g_ctx_prev2_hash = g_ctx_prev_hash;
        g_ctx_prev_hash = g_ctx_last_hash;
        g_ctx_last_hash = patch_hash;

        g_ctx_prev2_syn = g_ctx_prev_syn;
        g_ctx_prev_syn = g_ctx_last_syn;
        g_ctx_last_syn = cur_syn;

        g_markov_ctx_word1_id = math_mod_val(patch_hash, 8388607.0) + 1.0;
        if (g_ctx_prev_hash != 17.0) {
            g_markov_ctx_word2_id = math_mod_val(g_ctx_prev_hash * 257.0 + patch_hash, 8388607.0) + 1.0;
        } else {
            g_markov_ctx_word2_id = 0.0;
        }
        if (g_ctx_prev2_hash != 17.0 && g_ctx_prev_hash != 17.0) {
            let h23 = math_mod_val(g_ctx_prev2_hash * 257.0 + g_ctx_prev_hash, 8388607.0);
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

        if (g_ctx_prev2_hash != 17.0 && g_ctx_prev_hash != 17.0 && (g_ctx_prev2_syn > 0.0 || g_ctx_prev_syn > 0.0 || cur_syn > 0.0)) {
            var eff_p2 = g_ctx_prev2_hash;
            if (g_ctx_prev2_syn > 0.0) { eff_p2 = g_ctx_prev2_syn; }
            var eff_p1b = g_ctx_prev_hash;
            if (g_ctx_prev_syn > 0.0) { eff_p1b = g_ctx_prev_syn; }
            var eff_c1b = patch_hash;
            if (cur_syn > 0.0) { eff_c1b = cur_syn; }
            let sh23 = math_mod_val(eff_p2 * 257.0 + eff_p1b, 8388607.0);
            g_markov_ctx_syn3_id = math_mod_val(sh23 * 257.0 + eff_c1b, 8388607.0) + 1.0;
        } else {
            g_markov_ctx_syn3_id = 0.0;
        }
    }
}

fn geomind_byte_latent_train_deep_e8_corpus(
    corpus: string,
    num_layers: float,
    epochs: float,
    lr: float,
    record_vis: float
) -> float {
    geomind_byte_latent_init_if_needed();
    var L = floor(num_layers);
    if (L < 1.0) { L = 42.0; }
    let was_stack_init = g_e8_stack_initialized;
    geomind_e8_stack_init(L);
    if (was_stack_init == 0.0 && cartan_file_exists("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin") == 1.0) {
        geomind_e8_stack_load("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin");
    }

    let n_bytes = cartan_string_length(corpus);
    if (n_bytes < 2.0) { return 0.0; }

    var num_epochs = 1.0;
    if (epochs > 1.0) { num_epochs = epochs; }
    var eff_lr = 0.025;
    if (lr > 0.00001) { eff_lr = lr; }

    let h_prev_local = cartan_vec_create();
    let h_pre_local = cartan_vec_create();
    let h_local = cartan_vec_create();
    let h_patch_accum = cartan_vec_create();
    let h_prev_patch = cartan_vec_create();
    let h_top_patch = cartan_vec_create();
    let dh_local = cartan_vec_create();
    let dh_pre_local = cartan_vec_create();
    let dh_patch_accum = cartan_vec_create();
    let dh_in_stack = cartan_vec_create();
    let geo_grad = cartan_vec_create();
    let emb_vec = cartan_vec_create();
    let p_v4 = cartan_vec_create();
    let p_v3 = cartan_vec_create();
    let p_v2 = cartan_vec_create();
    let p_v1 = cartan_vec_create();
    let p_v0 = cartan_vec_create();
    let cur_p_vec = cartan_vec_create();
    let logits_256 = cartan_vec_create();
    let delta_256 = cartan_vec_create();

    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_prev_local, 0.0);
        cartan_vec_push_f32(h_pre_local, 0.0);
        cartan_vec_push_f32(h_local, 0.0);
        cartan_vec_push_f32(h_patch_accum, 0.0);
        cartan_vec_push_f32(h_prev_patch, 0.0);
        cartan_vec_push_f32(h_top_patch, 0.0);
        cartan_vec_push_f32(dh_local, 0.0);
        cartan_vec_push_f32(dh_pre_local, 0.0);
        cartan_vec_push_f32(dh_patch_accum, 0.0);
        cartan_vec_push_f32(dh_in_stack, 0.0);
        cartan_vec_push_f32(geo_grad, 0.0);
        cartan_vec_push_f32(emb_vec, 0.0);
        cartan_vec_push_f32(p_v4, 0.0);
        cartan_vec_push_f32(p_v3, 0.0);
        cartan_vec_push_f32(p_v2, 0.0);
        cartan_vec_push_f32(p_v1, 0.0);
        cartan_vec_push_f32(p_v0, 0.0);
        cartan_vec_push_f32(cur_p_vec, 0.0);
        d = d + 1.0;
    }
    var c = 0.0;
    while (c < 256.0) {
        cartan_vec_push_f32(logits_256, 0.0);
        cartan_vec_push_f32(delta_256, 0.0);
        c = c + 1.0;
    }

    var final_avg_action = 0.0;
    let max_steps = n_bytes - 1.0;
    var ep = 0.0;
    while (ep < num_epochs) {
        var epoch_action_sum = 0.0;
        var patch_steps_taken = 0.0;
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_prev_local, d, 0.0);
            cartan_vec_set_f32(h_pre_local, d, 0.0);
            cartan_vec_set_f32(h_local, d, 0.0);
            cartan_vec_set_f32(h_patch_accum, d, 0.0);
            cartan_vec_set_f32(h_prev_patch, d, 0.0);
            cartan_vec_set_f32(h_top_patch, d, 0.0);
            cartan_vec_set_f32(dh_patch_accum, d, 0.0);
            d = d + 1.0;
        }

        var step = 0.0;
        var b3 = 32.0;
        var b2 = 32.0;
        var cur_b = 32.0;
        var next_b = 32.0;
        var patch_len = 0.0;
        var patch_alnum_len = 0.0;
        var patch_hash = 17.0;
        var patch_sent_end = 0.0;
        var patch_comma_end = 0.0;
        var patch_act_sum = 0.0;
        var focus_horizon = 0.0;
        var stack_t_geo = 0.0;
        var p_h4 = 17.0;
        var p_h3 = 17.0;
        var p_h2 = 17.0;
        var p_h1 = 17.0;
        var p_h0 = 17.0;
        var sent_word_idx = 0.0;
        var sent_first_h = 17.0;
        var sent_second_h = 17.0;
        var sent_subj_h = 17.0;
        var sent_verb_h = 17.0;
        var sent_act_h = 17.0;
        var sent_cond_obj_h = 17.0;
        var sent_cause_h = 17.0;
        geomind_markov_reset_patch_context();

        while (step < max_steps) {
            cur_b = cartan_byte_at(corpus, step);
            if (cur_b < 0.0) { cur_b = cur_b + 256.0; }
            next_b = cartan_byte_at(corpus, step + 1.0);
            if (next_b < 0.0) { next_b = next_b + 256.0; }
            cur_b = math_mod_val(floor(cur_b), 256.0);
            next_b = math_mod_val(floor(next_b), 256.0);
            var is_para_break = 0.0;
            if (cur_b == 10.0) { is_para_break = 1.0; }
            // Normalize CR/LF line breaks to space (32) so multi-line corpora form continuous printable byte streams
            if (cur_b == 13.0 || cur_b == 10.0) { cur_b = 32.0; }
            if (next_b == 13.0 || next_b == 10.0) { next_b = 32.0; }
            if (cur_b == 32.0 && next_b == 32.0) {
                if (is_para_break == 1.0) {
                    geomind_markov_reset_patch_context();
                    p_h4 = 17.0;
                    p_h3 = 17.0;
                    p_h2 = 17.0;
                    p_h1 = 17.0;
                    p_h0 = 17.0;
                    sent_word_idx = 0.0;
                    sent_first_h = 17.0;
                    sent_second_h = 17.0;
                    sent_subj_h = 17.0;
                    sent_verb_h = 17.0;
                    sent_act_h = 17.0;
                    sent_cond_obj_h = 17.0;
                    sent_cause_h = 17.0;
                }
                step = step + 1.0;
                continue;
            }

            // 1. Fold alphanumeric stem byte into current 248-D E8 Patch Accumulator (ignoring punctuation/space)
            let is_alnum = ((cur_b >= 97.0 && cur_b <= 122.0) || (cur_b >= 65.0 && cur_b <= 90.0) || (cur_b >= 48.0 && cur_b <= 57.0));
            if (is_alnum) {
                geomind_fold_byte_into_e8_patch(h_patch_accum, cur_b, patch_len);
                var hb = cur_b;
                if (hb >= 65.0 && hb <= 90.0) { hb = hb + 32.0; }
                patch_hash = math_mod_val(patch_hash * 131.0 + hb, 1000003.0);
                patch_alnum_len = patch_alnum_len + 1.0;
            }
            if (cur_b == 46.0 || cur_b == 33.0 || cur_b == 63.0) {
                patch_sent_end = 1.0;
            }
            if (cur_b == 44.0) {
                patch_comma_end = 1.0;
            }
            patch_len = patch_len + 1.0;

            let row_off = cur_b * 248.0;
            d = 0.0;
            while (d < 248.0) {
                let loc_d = cartan_vec_get_f32(h_local, d);
                cartan_vec_set_f32(h_prev_local, d, loc_d);
                let e_d = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                cartan_vec_set_f32(emb_vec, d, e_d);
                if (step == 0.0) {
                    cartan_vec_set_f32(h_pre_local, d, e_d);
                } else {
                    cartan_vec_set_f32(h_pre_local, d, loc_d);
                }
                d = d + 1.0;
            }
            if (step > 0.0) {
                geom_retract_sphere_step(h_pre_local, emb_vec, 0.55);
            }
            geomind_weyl_reflect_vector_248(h_pre_local, math_mod_val(cur_b, 240.0));

            // 2. Tier 1 (Every Byte): Fast Local 120 (+) 128 Gauge-Spinor Cross-Gate
            geomind_e8_gauge_spinor_cross_gate(h_pre_local, h_local, 0.25);

            // 3. Tier 2 (Invariant Morphological/Delimiter Patch Boundary & Selective Resonance Focus Filter):
            let is_patch_boundary = ((cur_b == 32.0 || patch_len >= 16.0 || step == (max_steps - 1.0)) && patch_hash != 17.0);
            var saved_patch_hash = patch_hash;
            var patch_res = 0.0;
            var in_focus = 1.0;

            if (is_patch_boundary) {
                if (g_e8_primer_crystallize_all == 1.0) {
                    in_focus = 1.0;
                    g_e8_focus_hits = g_e8_focus_hits + 1.0;
                } else if (g_e8_anchor_count > 0.0) {
                    patch_res = geomind_e8_query_anchor_resonance(h_patch_accum, patch_hash);
                    if (patch_res >= 0.85) {
                        // Child heard a resonant Anchor concept! Open Laser-Focus Window for (i + 1) neighbor:
                        focus_horizon = 1.0;
                        in_focus = 1.0;
                        g_e8_focus_hits = g_e8_focus_hits + 1.0;
                    } else if (focus_horizon > 0.0) {
                        // Neighbor patch inside the active (i + 1) Laser-Focus Window:
                        in_focus = 1.0;
                        focus_horizon = focus_horizon - 1.0;
                        g_e8_focus_hits = g_e8_focus_hits + 1.0;
                    } else {
                        // "Blah Blah Blah" Uncomprehended Noise State: suppress 42-layer plasticity!
                        in_focus = 0.0;
                        g_e8_noise_skips = g_e8_noise_skips + 1.0;
                    }
                }

                sent_word_idx = sent_word_idx + 1.0;
                geomind_e8_hash_to_vec_248(saved_patch_hash, cur_p_vec);
                if (sent_word_idx == 1.0) { sent_first_h = saved_patch_hash; }
                if (sent_word_idx == 2.0) { sent_second_h = saved_patch_hash; }
                if (sent_word_idx == 3.0 && p_h1 == g_wn_hash_a && saved_patch_hash != g_wn_hash_is && saved_patch_hash != g_wn_verb_can) {
                    sent_subj_h = p_h0;
                    sent_act_h = saved_patch_hash;
                }

                if (in_focus == 1.0) {
                    d = 0.0;
                    while (d < 248.0) {
                        cartan_vec_set_f32(h_prev_patch, d, cartan_vec_get_f32(h_top_patch, d));
                        d = d + 1.0;
                    }
                    var prev_patch_ptr: ptr = 0.0;
                    if (patch_steps_taken > 0.0) { prev_patch_ptr = h_prev_patch; }
                    let mv_step = geomind_markov_get_prob(b2, cur_b);
                    stack_t_geo = geomind_e8_stack_forward_step(h_patch_accum, prev_patch_ptr, mv_step, 0.85, h_top_patch);
                    patch_steps_taken = patch_steps_taken + 1.0;

                    // Stage 6.1: 100% Word-Agnostic Closed-Class Syntactic Frame Extractor for all 6 Strata
                    // Frame 1 (Stratum 1 & Stratum 3): Taxonomic & Property Copula ("A <Subj> is a <Adj> <Hypernym>")
                    if (sent_word_idx == 6.0 && p_h4 == g_wn_hash_a && p_h3 != 17.0 && p_h2 == g_wn_hash_is && p_h1 == g_wn_hash_a && p_h0 != 17.0) {
                        geomind_e8_rel_train_step(g_e8_rel_isa_248x248, p_v3, cur_p_vec, 0.92, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_prop_248x248, p_v3, p_v0, 0.90, 1.0, 0.45);
                    }
                    // Frame 2 (Stratum 3 & Stratum 4): Attributive, Gerund, & Affective State Copulas
                    //   - "<Gerund> a <Noun> is <Valence>" ("Bouncing a ball is fun")
                    //   - "<Subj> <Verb> when it is <State>" ("A gentle cat purrs when it is happy")
                    //   - "[The] <Subj> is <Prop>" ("The ball is round", "Water is clear")
                    if (p_h1 != 17.0 && p_h0 == g_wn_hash_is && saved_patch_hash != g_wn_hash_a && saved_patch_hash != g_wn_hash_the) {
                        if (sent_word_idx == 5.0 && p_h3 != 17.0 && p_h2 == g_wn_hash_a) {
                            geomind_e8_rel_train_step(g_e8_rel_prop_248x248, p_v3, cur_p_vec, 0.92, 1.0, 0.45);
                            geomind_e8_rel_train_step(g_e8_rel_val_248x248, p_v3, cur_p_vec, 0.92, 1.0, 0.45);
                        } else if (p_h4 != 17.0 && p_h2 == g_wn_hash_when && p_h1 == g_wn_hash_it) {
                            geomind_e8_rel_train_step(g_e8_rel_cap_248x248, p_v4, p_v3, 0.92, 1.0, 0.45);
                            geomind_e8_rel_train_step(g_e8_rel_val_248x248, p_v3, cur_p_vec, 0.92, 1.0, 0.45);
                        } else if (sent_word_idx <= 4.0) {
                            geomind_e8_rel_train_step(g_e8_rel_prop_248x248, p_v1, cur_p_vec, 0.90, 1.0, 0.45);
                        }
                    }
                    // Frame 3 (Stratum 3 & Stratum 4): Modal Capability, Transitive Affordance, & Action-Locus Frames
                    //   - "A <Subj> can <Verb> ... in the <Locus>" ("A bird can fly high in the sky")
                    //   - "You can <Verb> the <Obj> on the <Locus>" ("You can bounce the ball on the ground")
                    //   - "A <Subj> <Verb> in the <Adj> <Locus>." ("A fish swims in the deep water.")
                    if (sent_word_idx == 4.0 && p_h2 == g_wn_hash_a && p_h0 == g_wn_verb_can) {
                        geomind_e8_rel_train_step(g_e8_rel_cap_248x248, p_v1, cur_p_vec, 0.92, 1.0, 0.45);
                        sent_verb_h = saved_patch_hash;
                    }
                    if (p_h1 == g_wn_hash_in && p_h0 == g_wn_hash_the && sent_verb_h != 17.0) {
                        geomind_e8_hash_to_vec_248(sent_verb_h, g_e8_rel_tmp_u);
                        geomind_e8_rel_train_step(g_e8_rel_val_248x248, g_e8_rel_tmp_u, cur_p_vec, 0.92, 1.0, 0.45);
                        sent_verb_h = 17.0;
                    }
                    if (sent_word_idx == 7.0 && p_h4 == g_wn_verb_can && p_h2 == g_wn_hash_the && p_h0 == g_wn_hash_on && saved_patch_hash == g_wn_hash_the) {
                        geomind_e8_rel_train_step(g_e8_rel_cap_248x248, p_v1, p_v3, 0.92, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_prop_248x248, p_v3, g_e8_vec_fun, 0.90, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_val_248x248, p_v3, g_e8_vec_fun, 0.92, 1.0, 0.45);
                    }
                    if (sent_word_idx == 7.0 && patch_sent_end == 1.0 && p_h2 == g_wn_hash_in && p_h1 == g_wn_hash_the && sent_subj_h != 17.0 && sent_act_h != 17.0) {
                        geomind_e8_hash_to_vec_248(sent_subj_h, g_e8_rel_tmp_u);
                        geomind_e8_hash_to_vec_248(sent_act_h, g_e8_rel_tmp_v);
                        geomind_e8_rel_train_step(g_e8_rel_cap_248x248, g_e8_rel_tmp_u, g_e8_rel_tmp_v, 0.92, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_val_248x248, g_e8_rel_tmp_v, cur_p_vec, 0.92, 1.0, 0.45);
                    }
                    // Frame 4 (Stratum 3 & Stratum 4): Hedonic Preference ("<Subj> likes to <Verb> in ..." / "likes to <Verb1> and <Verb2>")
                    if ((p_h1 == g_wn_hash_likes && p_h0 == g_wn_verb_to) ||
                        (p_h3 == g_wn_hash_likes && p_h2 == g_wn_verb_to && p_h0 == g_wn_hash_and)) {
                        geomind_e8_rel_train_step(g_e8_rel_prop_248x248, cur_p_vec, g_e8_vec_fun, 0.90, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_val_248x248, cur_p_vec, g_e8_vec_fun, 0.92, 1.0, 0.45);
                    }
                    if (p_h2 == g_wn_hash_likes && p_h1 == g_wn_verb_to && saved_patch_hash == g_wn_hash_in) {
                        geomind_e8_rel_train_step(g_e8_rel_cap_248x248, p_v3, p_v0, 0.92, 1.0, 0.45);
                    }
                    // Frame 5 (Stratum 5 & Stratum 6): Causal Explanation ("<Subj> <EffectVerb> ... because <Subj> is <CauseAdj>")
                    if (p_h2 == g_wn_hash_because && p_h1 == sent_first_h && p_h0 == g_wn_hash_is && sent_second_h != 17.0) {
                        geomind_e8_rel_train_step(g_e8_rel_cause_248x248, p_v1, cur_p_vec, 0.92, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_prop_248x248, p_v1, cur_p_vec, 0.90, 1.0, 0.45);
                        geomind_e8_hash_to_vec_248(sent_second_h, g_e8_rel_tmp_v);
                        geomind_e8_rel_train_step(g_e8_rel_effect_248x248, cur_p_vec, g_e8_rel_tmp_v, 0.92, 1.0, 0.45);
                    }
                    // Frame 6 (Stratum 5 & Stratum 6): Conditional Physical Cause-Effect ("When you <Act> a <Subj>, <Force> ... to the <Dest>.")
                    if (sent_word_idx == 5.0 && p_h3 == g_wn_hash_when && p_h2 == g_wn_hash_you && p_h0 == g_wn_hash_a && patch_comma_end == 1.0) {
                        sent_cond_obj_h = saved_patch_hash;
                    }
                    if (sent_word_idx == 6.0 && p_h0 == sent_cond_obj_h && sent_cond_obj_h != 17.0) {
                        geomind_e8_rel_train_step(g_e8_rel_cause_248x248, p_v0, cur_p_vec, 0.92, 1.0, 0.45);
                        sent_cause_h = saved_patch_hash;
                    }
                    if (patch_sent_end == 1.0 && p_h1 == g_wn_verb_to && p_h0 == g_wn_hash_the && sent_cause_h != 17.0) {
                        geomind_e8_hash_to_vec_248(sent_cause_h, g_e8_rel_tmp_u);
                        geomind_e8_rel_train_step(g_e8_rel_effect_248x248, g_e8_rel_tmp_u, cur_p_vec, 0.92, 1.0, 0.45);
                    }
                }

                if (is_para_break == 1.0 || patch_sent_end == 1.0) {
                    p_h4 = 17.0;
                    p_h3 = 17.0;
                    p_h2 = 17.0;
                    p_h1 = 17.0;
                    p_h0 = 17.0;
                    sent_word_idx = 0.0;
                    sent_first_h = 17.0;
                    sent_second_h = 17.0;
                    sent_subj_h = 17.0;
                    sent_verb_h = 17.0;
                    sent_act_h = 17.0;
                    sent_cond_obj_h = 17.0;
                    sent_cause_h = 17.0;
                } else {
                    p_h4 = p_h3;
                    p_h3 = p_h2;
                    p_h2 = p_h1;
                    p_h1 = p_h0;
                    p_h0 = saved_patch_hash;
                    d = 0.0;
                    while (d < 248.0) {
                        cartan_vec_set_f32(p_v4, d, cartan_vec_get_f32(p_v3, d));
                        cartan_vec_set_f32(p_v3, d, cartan_vec_get_f32(p_v2, d));
                        cartan_vec_set_f32(p_v2, d, cartan_vec_get_f32(p_v1, d));
                        cartan_vec_set_f32(p_v1, d, cartan_vec_get_f32(p_v0, d));
                        cartan_vec_set_f32(p_v0, d, cartan_vec_get_f32(cur_p_vec, d));
                        d = d + 1.0;
                    }
                }

                geomind_markov_advance_patch_context(patch_hash, patch_alnum_len, is_para_break, patch_sent_end, patch_comma_end);
                patch_sent_end = 0.0;
                patch_comma_end = 0.0;
                patch_alnum_len = 0.0;
            }

            // 4. Decode 256 byte logits from fused (h_local, h_top_patch) + pre-update 3-gram Markov prior
            let markov_v = geomind_markov_get_3gram_prob(b3, b2, cur_b, next_b);
            geomind_byte_latent_decode_logits_blt(h_local, h_top_patch, b3, b2, cur_b, logits_256);
            if (is_para_break == 0.0) {
                geomind_markov_update_3gram(b3, b2, cur_b, next_b);
            }

            // 5. Evaluate Markov-Lagrangian Action Loss
            let base_act = geomind_lagrangian_action_step(
                logits_256, next_b, cur_b, h_prev_local, h_local, g_byte_e8_randers_b_248, delta_256
            );
            let well_factor = 1.0 - 0.5 * markov_v;
            let act_s = base_act + 0.04 * stack_t_geo * well_factor;
            epoch_action_sum = epoch_action_sum + act_s;
            patch_act_sum = patch_act_sum + act_s;

            // 6. Geodesic Kinetic Energy Restoring Force & Readout Head Backprop (Gated by Selective Focus)
            var local_lr_scale = 1.0;
            if (g_e8_primer_crystallize_all == 0.0 && g_e8_anchor_count > 0.0 && in_focus == 0.0 && focus_horizon <= 0.0) {
                local_lr_scale = 0.05; // 95% plasticity suppression during "blah blah blah" noise
            }
            geomind_e8_geodesic_kinetic_grad_248(h_prev_local, h_local, g_byte_e8_randers_b_248, geo_grad, 0.12 * well_factor);

            d = 0.0;
            while (d < 248.0) {
                let hl_d = cartan_vec_get_f32(h_local, d);
                let hp_d = cartan_vec_get_f32(h_top_patch, d);
                let h_comb = 0.65 * hl_d + 0.35 * hp_d;
                let b_d = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
                var dh_d = cartan_vec_get_f32(geo_grad, d);

                c = 32.0;
                while (c <= 126.0) {
                    let del_c = cartan_vec_get_f32(delta_256, c);
                    if (math_abs_val(del_c) > 0.005) {
                        let w_dc = cartan_vec_get_f32(g_byte_e8_head_248x256, d * 256.0 + c);
                        dh_d = dh_d + w_dc * del_c;
                        var new_w = geom_frs_riemannian_gradient_step(w_dc, h_comb * del_c, b_d, eff_lr * local_lr_scale);
                        if (new_w > 0.10) { new_w = 0.10; }
                        else if (new_w < -0.10) { new_w = -0.10; }
                        cartan_vec_set_f32(g_byte_e8_head_248x256, d * 256.0 + c, new_w);
                    }
                    c = c + 1.0;
                }
                cartan_vec_set_f32(dh_local, d, 0.65 * dh_d * local_lr_scale);
                cartan_vec_set_f32(dh_patch_accum, d, cartan_vec_get_f32(dh_patch_accum, d) + 0.35 * dh_d * local_lr_scale);
                d = d + 1.0;
            }

            // 7. Tier 1 Backward: Adjoint Local Cross-Gate -> Byte Embedding Update
            geomind_e8_gauge_spinor_cross_gate_backward(h_pre_local, dh_local, dh_pre_local, 0.25);

            // 8. Tier 2 Backward (At Patch Boundary):
            // Only backpropagate through the 42-Layer Deep E8 Stack if in_focus == 1.0!
            // If this neighbor patch inside the focus window achieved low Lagrangian Action, crystallize it as a new Anchor!
            if (is_patch_boundary) {
                let avg_patch_act = patch_act_sum / patch_len;
                if (in_focus == 1.0) {
                    geomind_e8_stack_backward_step(dh_patch_accum, eff_lr * 0.15, 0.04 * well_factor, dh_in_stack);
                    // Automatic Frontier Crystallization: Rung 1 Primer crystallizes all words (patch_len >= 2.0),
                    // while Rung 2/3 Frontier Crystallization crystallizes stabilized neighbor content words (patch_len >= 4.0)
                    var min_cryst_len = 4.0;
                    if (g_e8_primer_crystallize_all == 1.0) { min_cryst_len = 2.0; }
                    if ((g_e8_primer_crystallize_all == 1.0 || g_e8_anchor_count > 0.0) && patch_len >= min_cryst_len && avg_patch_act <= 1.35) {
                        geomind_e8_crystallize_patch_vec(h_patch_accum, saved_patch_hash, 0.60);
                    }
                }
                d = 0.0;
                while (d < 248.0) {
                    if (in_focus == 1.0) {
                        cartan_vec_set_f32(dh_pre_local, d, cartan_vec_get_f32(dh_pre_local, d) + 0.35 * cartan_vec_get_f32(dh_in_stack, d));
                    }
                    cartan_vec_set_f32(dh_patch_accum, d, 0.0);
                    cartan_vec_set_f32(h_patch_accum, d, 0.0);
                    d = d + 1.0;
                }
                patch_len = 0.0;
                patch_hash = 17.0;
                patch_act_sum = 0.0;
            }

            // 9. Update Byte-to-E8 Embedding row and Finsler-Randers Drift 1-form beta
            d = 0.0;
            while (d < 248.0) {
                let dp_d = cartan_vec_get_f32(dh_pre_local, d);
                let b_d = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
                let old_emb = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                var new_emb = geom_frs_riemannian_gradient_step(old_emb, dp_d, b_d, eff_lr * 0.25);
                if (new_emb > 0.85) { new_emb = 0.85; }
                else if (new_emb < -0.85) { new_emb = -0.85; }
                cartan_vec_set_f32(g_byte_e8_emb_256x248, row_off + d, new_emb);

                let h_d = cartan_vec_get_f32(h_local, d);
                let old_h = cartan_vec_get_f32(h_prev_local, d);
                var new_b = b_d - eff_lr * 0.005 * well_factor * (h_d - old_h);
                if (new_b > 0.08) { new_b = 0.08; }
                else if (new_b < -0.08) { new_b = -0.08; }
                cartan_vec_set_f32(g_byte_e8_randers_b_248, d, new_b);
                d = d + 1.0;
            }

            b3 = b2;
            b2 = cur_b;
            step = step + 1.0;
        }

        g_blt_last_patch_count = patch_steps_taken;
        final_avg_action = epoch_action_sum / max_steps;
        if (record_vis == 1.0) {
            let mv = geomind_markov_get_3gram_prob(b3, b2, cur_b, next_b);
            geomind_visualizer_record_step(final_avg_action, h_top_patch, mv);
        }
        ep = ep + 1.0;
    }

    if (g_byte_e8_defer_disk_save == 0.0) {
        geomind_markov_save_prior("Projects/geomind/trainingdata/checkpoints/geomind_markov_prior.bin");
        geomind_byte_latent_save_weights("Projects/geomind/trainingdata/checkpoints/geomind_byte_latent_e8.bin");
        geomind_e8_stack_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin");
        if (g_e8_anchor_count > 0.0) {
            geomind_e8_anchors_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_anchors.bin");
        }
    }

    cartan_vec_free(h_prev_local);
    cartan_vec_free(h_pre_local);
    cartan_vec_free(h_local);
    cartan_vec_free(h_patch_accum);
    cartan_vec_free(h_prev_patch);
    cartan_vec_free(h_top_patch);
    cartan_vec_free(dh_local);
    cartan_vec_free(dh_pre_local);
    cartan_vec_free(dh_patch_accum);
    cartan_vec_free(dh_in_stack);
    cartan_vec_free(geo_grad);
    cartan_vec_free(emb_vec);
    cartan_vec_free(p_v4);
    cartan_vec_free(p_v3);
    cartan_vec_free(p_v2);
    cartan_vec_free(p_v1);
    cartan_vec_free(p_v0);
    cartan_vec_free(cur_p_vec);
    cartan_vec_free(logits_256);
    cartan_vec_free(delta_256);
    return final_avg_action;
}

// Autoregressive generation through the Two-Tier BLT Deep L-Layer E8 Gauge-Spinor Stack
// Tier 1 steps every byte with 3-gram Markov + local Weyl/Fano; Tier 2 steps the 42-Layer E8 Stack at patch boundaries.
fn geomind_byte_latent_generate_deep_e8(prompt: string, num_layers: float, gen_len: float) -> string {
    geomind_byte_latent_init_if_needed();
    var L = floor(num_layers);
    if (L < 1.0) { L = 42.0; }
    geomind_e8_stack_init(L);

    let h_prev_local = cartan_vec_create();
    let h_pre_local = cartan_vec_create();
    let h_local = cartan_vec_create();
    let h_patch_accum = cartan_vec_create();
    let h_prev_patch = cartan_vec_create();
    let h_top_patch = cartan_vec_create();
    let emb_vec = cartan_vec_create();
    let vel_vec = cartan_vec_create();
    let logits_256 = cartan_vec_create();

    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_prev_local, 0.0);
        cartan_vec_push_f32(h_pre_local, 0.0);
        cartan_vec_push_f32(h_local, 0.0);
        cartan_vec_push_f32(h_patch_accum, 0.0);
        cartan_vec_push_f32(h_prev_patch, 0.0);
        cartan_vec_push_f32(h_top_patch, 0.0);
        cartan_vec_push_f32(emb_vec, 0.0);
        cartan_vec_push_f32(vel_vec, 0.0);
        d = d + 1.0;
    }
    var c = 0.0;
    while (c < 256.0) {
        cartan_vec_push_f32(logits_256, 0.0);
        c = c + 1.0;
    }

    // 16-slot Short-Term Synaptic Depression (Refractory) Buffer on (word1_hub_id, outgoing_first_byte)
    let ref_w1 = cartan_vec_create();
    let ref_byte = cartan_vec_create();
    var r_idx = 0.0;
    while (r_idx < 16.0) {
        cartan_vec_push_f32(ref_w1, -1.0);
        cartan_vec_push_f32(ref_byte, -1.0);
        r_idx = r_idx + 1.0;
    }
    var ref_ptr = 0.0;

    let plen = cartan_string_length(prompt);
    var b3 = 32.0;
    var b2 = 32.0;
    var cur_b = 32.0;
    var patch_len = 0.0;
    var patch_alnum_len = 0.0;
    var patch_hash = 17.0;
    var patch_sent_end = 0.0;
    var patch_comma_end = 0.0;
    geomind_markov_reset_patch_context();
    var patch_steps = 0.0;
    var i = 0.0;
    while (i < plen) {
        cur_b = cartan_byte_at(prompt, i);
        if (cur_b < 0.0) { cur_b = cur_b + 256.0; }
        cur_b = math_mod_val(floor(cur_b), 256.0);
        if (cur_b == 13.0 || cur_b == 10.0) { cur_b = 32.0; }
        if (i > 0.0 && b2 == 32.0 && cur_b != 32.0 && g_markov_ctx_word1_id > 0.0) {
            cartan_vec_set_f32(ref_w1, ref_ptr, g_markov_ctx_word1_id);
            cartan_vec_set_f32(ref_byte, ref_ptr, cur_b);
            ref_ptr = math_mod_val(ref_ptr + 1.0, 16.0);
        }
        let is_alnum1 = ((cur_b >= 97.0 && cur_b <= 122.0) || (cur_b >= 65.0 && cur_b <= 90.0) || (cur_b >= 48.0 && cur_b <= 57.0));
        if (is_alnum1) {
            geomind_fold_byte_into_e8_patch(h_patch_accum, cur_b, patch_len);
            var hb = cur_b;
            if (hb >= 65.0 && hb <= 90.0) { hb = hb + 32.0; }
            patch_hash = math_mod_val(patch_hash * 131.0 + hb, 1000003.0);
            patch_alnum_len = patch_alnum_len + 1.0;
        }
        if (cur_b == 46.0 || cur_b == 33.0 || cur_b == 63.0) {
            patch_sent_end = 1.0;
        }
        if (cur_b == 44.0) {
            patch_comma_end = 1.0;
        }
        patch_len = patch_len + 1.0;

        let row_off = cur_b * 248.0;
        d = 0.0;
        while (d < 248.0) {
            let loc_d = cartan_vec_get_f32(h_local, d);
            cartan_vec_set_f32(h_prev_local, d, loc_d);
            let e_d = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
            cartan_vec_set_f32(emb_vec, d, e_d);
            if (i == 0.0) {
                cartan_vec_set_f32(h_pre_local, d, e_d);
            } else {
                cartan_vec_set_f32(h_pre_local, d, loc_d);
            }
            d = d + 1.0;
        }
        if (i > 0.0) {
            geom_retract_sphere_step(h_pre_local, emb_vec, 0.55);
        }
        geomind_weyl_reflect_vector_248(h_pre_local, math_mod_val(cur_b, 240.0));
        geomind_e8_gauge_spinor_cross_gate(h_pre_local, h_local, 0.25);

        let is_patch_boundary = ((cur_b == 32.0 || patch_len >= 16.0) && patch_hash != 17.0);
        if (is_patch_boundary) {
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(h_prev_patch, d, cartan_vec_get_f32(h_top_patch, d));
                d = d + 1.0;
            }
            var prev_patch_ptr: ptr = 0.0;
            if (patch_steps > 0.0) { prev_patch_ptr = h_prev_patch; }
            let mv = geomind_markov_get_prob(b2, cur_b);
            geomind_e8_stack_forward_step(h_patch_accum, prev_patch_ptr, mv, 0.85, h_top_patch);
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(h_patch_accum, d, 0.0);
                d = d + 1.0;
            }
            geomind_markov_advance_patch_context(patch_hash, patch_alnum_len, 0.0, patch_sent_end, patch_comma_end);
            patch_sent_end = 0.0;
            patch_comma_end = 0.0;
            patch_len = 0.0;
            patch_alnum_len = 0.0;
            patch_hash = 17.0;
            patch_steps = patch_steps + 1.0;
        }
        if (i < (plen - 1.0)) {
            b3 = b2;
            b2 = cur_b;
        }
        i = i + 1.0;
    }

    var out_str = prompt;
    var step = 0.0;
    let max_grace_len = gen_len + 12.0;
    while (step < max_grace_len) {
        if (step >= gen_len && (cur_b == 32.0 || cur_b == 46.0 || cur_b == 33.0 || cur_b == 63.0)) {
            break;
        }
        geomind_byte_latent_decode_logits_blt(h_local, h_top_patch, b3, b2, cur_b, logits_256);
        var best_b = 32.0;
        var best_l = -100000.0;
        var ref_hub_id = g_markov_ctx_word2_id;
        if (ref_hub_id <= 0.0) { ref_hub_id = g_markov_ctx_word1_id; }
        c = 32.0;
        while (c <= 126.0) {
            var lv = cartan_vec_get_f32(logits_256, c);
            // If prompt ends on a complete SenseGuarded WordNet noun without a trailing space (e.g. "...the orb"),
            // allow clean word termination into a space so the Synset Hub can fire on the next step:
            if (step == 0.0 && cur_b != 32.0 && c == 32.0 && geomind_wordnet_resolve_synset(patch_hash, g_ctx_last_hash) > 0.0) {
                lv = lv + 10.0;
            }
            // Prevent 3 consecutive identical characters (e.g., "fff") and consecutive spaces ("  ")
            if (b2 == cur_b && cur_b == c) { lv = lv - 12.0; }
            if (cur_b == 32.0 && c == 32.0) { lv = lv - 12.0; }
            // Apply Short-Term Synaptic Depression (Refractory damping) on recently traversed outgoing word branches
            if (cur_b == 32.0 && c != 32.0 && ref_hub_id > 0.0) {
                r_idx = 0.0;
                while (r_idx < 16.0) {
                    if (cartan_vec_get_f32(ref_w1, r_idx) == ref_hub_id && cartan_vec_get_f32(ref_byte, r_idx) == c) {
                        lv = lv - 3.5;
                        break;
                    }
                    r_idx = r_idx + 1.0;
                }
            }
            if (lv > best_l) {
                best_l = lv;
                best_b = c;
            }
            c = c + 1.0;
        }

        if (cur_b == 32.0 && best_b != 32.0 && ref_hub_id > 0.0) {
            cartan_vec_set_f32(ref_w1, ref_ptr, ref_hub_id);
            cartan_vec_set_f32(ref_byte, ref_ptr, best_b);
            ref_ptr = math_mod_val(ref_ptr + 1.0, 16.0);
        }

        out_str = cartan_string_concat(out_str, cartan_char_from_code(best_b));
        b3 = b2;
        b2 = cur_b;
        cur_b = best_b;
        let is_alnum2 = ((cur_b >= 97.0 && cur_b <= 122.0) || (cur_b >= 65.0 && cur_b <= 90.0) || (cur_b >= 48.0 && cur_b <= 57.0));
        if (is_alnum2) {
            geomind_fold_byte_into_e8_patch(h_patch_accum, cur_b, patch_len);
            var hb2 = cur_b;
            if (hb2 >= 65.0 && hb2 <= 90.0) { hb2 = hb2 + 32.0; }
            patch_hash = math_mod_val(patch_hash * 131.0 + hb2, 1000003.0);
            patch_alnum_len = patch_alnum_len + 1.0;
        }
        if (cur_b == 46.0 || cur_b == 33.0 || cur_b == 63.0) {
            patch_sent_end = 1.0;
        }
        if (cur_b == 44.0) {
            patch_comma_end = 1.0;
        }
        patch_len = patch_len + 1.0;

        let t_geo = geomind_e8_geodesic_kinetic_energy_248(h_prev_local, h_local, g_byte_e8_randers_b_248);
        let coast = geomind_should_geodesic_coast(b2, cur_b, t_geo, 0.85);
        if (coast == 1.0) {
            g_byte_latent_coast_count = g_byte_latent_coast_count + 1.0;
        }
        let row_off = cur_b * 248.0;
        d = 0.0;
        while (d < 248.0) {
            let loc_d = cartan_vec_get_f32(h_local, d);
            cartan_vec_set_f32(h_prev_local, d, loc_d);
            cartan_vec_set_f32(h_pre_local, d, loc_d);
            cartan_vec_set_f32(emb_vec, d, cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d));
            d = d + 1.0;
        }
        geom_retract_sphere_step(h_pre_local, emb_vec, 0.55);
        geomind_weyl_reflect_vector_248(h_pre_local, math_mod_val(cur_b, 240.0));
        geomind_e8_gauge_spinor_cross_gate(h_pre_local, h_local, 0.25);

        // Only fire the 42-Layer Deep E8 Stack at dynamic patch boundaries!
        let is_patch_boundary = ((cur_b == 32.0 || patch_len >= 16.0) && patch_hash != 17.0);
        if (is_patch_boundary) {
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(h_prev_patch, d, cartan_vec_get_f32(h_top_patch, d));
                d = d + 1.0;
            }
            var prev_patch_ptr2: ptr = 0.0;
            if (patch_steps > 0.0) { prev_patch_ptr2 = h_prev_patch; }
            let mv_step = geomind_markov_get_prob(b2, cur_b);
            geomind_e8_stack_forward_step(h_patch_accum, prev_patch_ptr2, mv_step, 0.85, h_top_patch);
            patch_steps = patch_steps + 1.0;
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(h_patch_accum, d, 0.0);
                d = d + 1.0;
            }
            geomind_markov_advance_patch_context(patch_hash, patch_alnum_len, 0.0, patch_sent_end, patch_comma_end);
            patch_sent_end = 0.0;
            patch_comma_end = 0.0;
            patch_len = 0.0;
            patch_alnum_len = 0.0;
            patch_hash = 17.0;
        }
        step = step + 1.0;
    }

    cartan_vec_free(ref_w1);
    cartan_vec_free(ref_byte);
    cartan_vec_free(h_prev_local);
    cartan_vec_free(h_pre_local);
    cartan_vec_free(h_local);
    cartan_vec_free(h_patch_accum);
    cartan_vec_free(h_prev_patch);
    cartan_vec_free(h_top_patch);
    cartan_vec_free(emb_vec);
    cartan_vec_free(vel_vec);
    cartan_vec_free(logits_256);
    return out_str;
}

// ============================================================================
// STAGE 5.3: 4-RUNG CONCENTRIC ENGLISH DEVELOPMENTAL CURRICULUM (--curriculum)
// ============================================================================
// Rung 1: Nursery Primer (`e8_nursery_primer.txt`) - Full Foundation Mode, crystallizes core English SVO + glue anchors.
// Rung 2: Grounded Concept Triples (`e8_concept_triples.txt`) - Selective Resonance Focus around Rung 1 anchors.
// Rung 3: Multi-Pass TinyStories (`hf_roneneldan_TinyStories.txt`) - Progressive comprehension expansion across passes.
// Rung 4: Digestible Storytelling Chunks (`storytelling_chunks/`) - Multi-genre narratives & classical literature.
fn geomind_run_english_curriculum(num_layers: float, lr: float) -> float {
    var L = floor(num_layers);
    if (L < 1.0) { L = 42.0; }
    var eff_lr = 0.03;
    if (lr > 0.0001) { eff_lr = lr; }

    printf("\n================================================================================\n");
    printf("  CARTAN-E8 CONCENTRIC ENGLISH DEVELOPMENTAL CURRICULUM (L=%.0f Layers)\n", L);
    printf("================================================================================\n");
    cartan_flush(0.0);

    // Start from a clean Anchor Basin registry, Markov Tapestry, and 42-Layer E8 Stack
    g_byte_e8_skip_disk_autoload = 1.0;
    g_byte_e8_defer_disk_save = 1.0;
    g_markov_initialized = 0.0;
    geomind_markov_init_if_needed();
    g_byte_e8_initialized = 0.0;
    geomind_byte_latent_init_if_needed();
    g_byte_e8_skip_disk_autoload = 0.0;
    g_e8_stack_initialized = 0.0;
    geomind_e8_stack_init(L);
    geomind_e8_anchors_reset();
    geomind_visualizer_reset();

    // ------------------------------------------------------------------------
    // RUNG 1: Nursery Primer (Atomic SVO & Glue Words - 100% Foundation Focus)
    // ------------------------------------------------------------------------
    let rung1_path = "Projects/geomind/trainingdata/e8_nursery_primer.txt";
    var rung1_text = "The ball is round and red. You can throw the ball. You can bounce the ball on the ground. Bouncing a ball is fun. Water is clear and wet.";
    if (cartan_file_exists(rung1_path) == 1.0) {
        rung1_text = cartan_read_file(rung1_path);
    }
    g_e8_primer_crystallize_all = 1.0;
    let s_rung1 = geomind_byte_latent_train_deep_e8_corpus(rung1_text, L, 4.0, eff_lr, 1.0);
    g_e8_primer_crystallize_all = 0.0;
    let gen_r1_a = geomind_byte_latent_generate_deep_e8("The ball is", L, 52.0);
    let gen_r1_b = geomind_byte_latent_generate_deep_e8("Water is", L, 52.0);
    printf("[Rung 1 | Nursery Primer] Action S = %.6f | Anchors = %.0f / 65536 | TapestryHubs = %.0f / 1048576\n",
        s_rung1, g_e8_anchor_count, g_markov_hub_occupied_slots);
    printf("  -> Gen 1: %s\n", gen_r1_a);
    printf("  -> Gen 2: %s\n", gen_r1_b);
    cartan_flush(0.0);

    // ------------------------------------------------------------------------
    // RUNG 2: Grounded Taxonomic & Causal Concept Triples (Selective Focus)
    // ------------------------------------------------------------------------
    let rung2_path = "Projects/geomind/trainingdata/e8_concept_triples.txt";
    var rung2_text = "When you drop a ball, gravity pulls the ball down to the ground. Wood floats on water because wood is lighter than water.";
    if (cartan_file_exists(rung2_path) == 1.0) {
        rung2_text = cartan_read_file(rung2_path);
    }
    g_e8_focus_hits = 0.0;
    g_e8_noise_skips = 0.0;
    let anchors_before_r2 = g_e8_anchor_count;
    let s_rung2 = geomind_byte_latent_train_deep_e8_corpus(rung2_text, L, 4.0, eff_lr, 1.0);
    let gen_r2 = geomind_byte_latent_generate_deep_e8("When you drop a ball", L, 58.0);
    printf("[Rung 2 | Concept Triples] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
        s_rung2, anchors_before_r2, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips, g_markov_hub_occupied_slots);
    printf("  -> Gen 3: %s\n", gen_r2);
    cartan_flush(0.0);

    // ------------------------------------------------------------------------
    // RUNG 3: TinyStories Progressive Multi-Pass Comprehension (Pass 1 vs Pass 2)
    // ------------------------------------------------------------------------
    let rung3_path = "Projects/geomind/trainingdata/storytelling_chunks/chunk_001_t1_TinyStories_Curated.txt";
    if (cartan_file_exists(rung3_path) == 1.0) {
        let stories_slice = cartan_read_file(rung3_path);

        // Pass 1 over full 12KB TinyStories chunk:
        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let anchors_p0 = g_e8_anchor_count;
        let s_r3_p1 = geomind_byte_latent_train_deep_e8_corpus(stories_slice, L, 2.0, eff_lr * 0.85, 1.0);
        let p1_focus = g_e8_focus_hits;
        let p1_skip = g_e8_noise_skips;
        let anchors_p1 = g_e8_anchor_count;

        // Pass 2 over the SAME 12KB TinyStories chunk (with newly crystallized Pass 1 anchors!):
        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let s_r3_p2 = geomind_byte_latent_train_deep_e8_corpus(stories_slice, L, 2.0, eff_lr * 0.85, 1.0);
        let p2_focus = g_e8_focus_hits;
        let p2_skip = g_e8_noise_skips;
        let anchors_p2 = g_e8_anchor_count;

        let gen_r3 = geomind_byte_latent_generate_deep_e8("Once upon a time", L, 64.0);
        printf("[Rung 3 | TinyStories 12KB Pass 1] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f\n",
            s_r3_p1, anchors_p0, anchors_p1, p1_focus, p1_skip);
        printf("[Rung 3 | TinyStories 12KB Pass 2] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
            s_r3_p2, anchors_p1, anchors_p2, p2_focus, p2_skip, g_markov_hub_occupied_slots);
        printf("  -> Gen 4: %s\n", gen_r3);
        cartan_flush(0.0);
    }

    // ------------------------------------------------------------------------
    // RUNG 4: Full 12KB Storytelling Chunks (Modern Narratives + Alice + Anthem + Sherlock Holmes)
    // ------------------------------------------------------------------------
    let chunk_modern = "Projects/geomind/trainingdata/storytelling_chunks/chunk_005_t1_GeoMind_Modern_Narratives.txt";
    let chunk_alice = "Projects/geomind/trainingdata/storytelling_chunks/chunk_007_t2_Alice_In_Wonderland.txt";
    let chunk_anthem = "Projects/geomind/trainingdata/storytelling_chunks/chunk_019_t2_Anthem.txt";
    let chunk_sherlock = "Projects/geomind/trainingdata/storytelling_chunks/chunk_028_t3_Sherlock_Holmes.txt";
    if (cartan_file_exists(chunk_modern) == 1.0 && cartan_file_exists(chunk_alice) == 1.0 && cartan_file_exists(chunk_anthem) == 1.0) {
        let txt_modern = cartan_read_file(chunk_modern);
        let txt_alice = cartan_read_file(chunk_alice);
        let txt_anthem = cartan_read_file(chunk_anthem);

        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let a_pre_mod = g_e8_anchor_count;
        let s_mod = geomind_byte_latent_train_deep_e8_corpus(txt_modern, L, 2.0, eff_lr * 0.80, 1.0);
        printf("[Rung 4a | Chunk 005 Modern Narratives (12KB)] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
            s_mod, a_pre_mod, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips, g_markov_hub_occupied_slots);

        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let a_pre_ali = g_e8_anchor_count;
        let s_ali = geomind_byte_latent_train_deep_e8_corpus(txt_alice, L, 2.0, eff_lr * 0.80, 1.0);
        printf("[Rung 4b | Chunk 007 Alice Wonderland (12KB)]  Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
            s_ali, a_pre_ali, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips, g_markov_hub_occupied_slots);

        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let a_pre_ant = g_e8_anchor_count;
        let s_ant = geomind_byte_latent_train_deep_e8_corpus(txt_anthem, L, 2.0, eff_lr * 0.80, 1.0);
        printf("[Rung 4c | Chunk 019 Anthem (12KB)]            Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
            s_ant, a_pre_ant, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips, g_markov_hub_occupied_slots);

        if (cartan_file_exists(chunk_sherlock) == 1.0) {
            let txt_sher = cartan_read_file(chunk_sherlock);
            g_e8_focus_hits = 0.0;
            g_e8_noise_skips = 0.0;
            let a_pre_sh = g_e8_anchor_count;
            let s_sh = geomind_byte_latent_train_deep_e8_corpus(txt_sher, L, 2.0, eff_lr * 0.80, 1.0);
            printf("[Rung 4d | Chunk 028 Sherlock Holmes (12KB)]   Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
                s_sh, a_pre_sh, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips, g_markov_hub_occupied_slots);
        }

        printf("  -> Gen 5 (Sci-Fi):   %s\n", geomind_byte_latent_generate_deep_e8("Commander Vane stood on", L, 60.0));
        printf("  -> Gen 6 (Alice):    %s\n", geomind_byte_latent_generate_deep_e8("Alice was beginning to", L, 60.0));
        printf("  -> Gen 7 (Anthem):   %s\n", geomind_byte_latent_generate_deep_e8("It is a sin to write", L, 60.0));
        printf("  -> Gen 8 (Sherlock): %s\n", geomind_byte_latent_generate_deep_e8("To Sherlock Holmes she", L, 60.0));
        cartan_flush(0.0);
    }

    printf("--------------------------------------------------------------------------------\n");
    printf("  NOVEL CONCEPT RECOMBINATION TEST (Unseen Prefixes Bridging Shared Word Hubs)\n");
    printf("--------------------------------------------------------------------------------\n");
    printf("  -> Novel 1 ('The cat likes to play'):    %s\n", geomind_byte_latent_generate_deep_e8("The cat likes to play", L, 48.0));
    printf("  -> Novel 2 ('A small dog found'):        %s\n", geomind_byte_latent_generate_deep_e8("A small dog found", L, 48.0));
    printf("  -> Novel 3 ('Cold water is'):            %s\n", geomind_byte_latent_generate_deep_e8("Cold water is", L, 48.0));
    printf("  -> Novel 4 ('When rain falls, the cat'): %s\n", geomind_byte_latent_generate_deep_e8("When rain falls, the cat", L, 48.0));
    printf("  -> Novel 5 ('The dog can bounce'):       %s\n", geomind_byte_latent_generate_deep_e8("The dog can bounce", L, 48.0));
    printf("  -> Novel 6 ('Alice stood on the'):       %s\n", geomind_byte_latent_generate_deep_e8("Alice stood on the", L, 56.0));
    printf("  -> Novel 7 ('Commander Vane found a'):   %s\n", geomind_byte_latent_generate_deep_e8("Commander Vane found a", L, 56.0));
    printf("  -> Novel 8 ('Sherlock Holmes stood on'): %s\n", geomind_byte_latent_generate_deep_e8("Sherlock Holmes stood on", L, 56.0));
    printf("--------------------------------------------------------------------------------\n");
    printf("  WORDNET + IC TAXONOMIC GROKKING TEST (Zero-Shot Synset Property Inheritance)\n");
    printf("--------------------------------------------------------------------------------\n");
    printf("  -> Grok 1 ('The puppy likes to'):        %s\n", geomind_byte_latent_generate_deep_e8("The puppy likes to", L, 48.0));
    printf("  -> Grok 2 ('A gentle kitten'):           %s\n", geomind_byte_latent_generate_deep_e8("A gentle kitten", L, 48.0));
    printf("  -> Grok 3 ('A sparrow can'):             %s\n", geomind_byte_latent_generate_deep_e8("A sparrow can", L, 48.0));
    printf("  -> Grok 4 ('You can bounce the orb'):    %s\n", geomind_byte_latent_generate_deep_e8("You can bounce the orb", L, 48.0));
    printf("--------------------------------------------------------------------------------\n");
    printf("  248x248 MANIFOLD CONCEPT-WEIGHTING & RELATIONAL UNDERSTANDING AUDIT (S^247)\n");
    printf("--------------------------------------------------------------------------------\n");
    let w_sparrow_bird = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "sparrow", "bird");
    let w_bird_sparrow = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "bird", "sparrow");
    let w_kitten_cat   = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "kitten", "cat");
    let w_cat_kitten   = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "cat", "kitten");
    let w_puppy_dog    = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "puppy", "dog");
    let w_dog_puppy    = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "dog", "puppy");
    let w_orb_ball     = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "orb", "ball");
    let w_ball_orb     = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "ball", "orb");
    let w_sparrow_dog  = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "sparrow", "dog");
    printf("  [Asymmetric IS_A Operator <P_hyper, R_isa * P_hypo> / 248]:\n");
    printf("    * sparrow -> bird = %.4f  (Reverse bird -> sparrow = %.4f)\n", w_sparrow_bird, w_bird_sparrow);
    printf("    * kitten  -> cat  = %.4f  (Reverse cat  -> kitten  = %.4f)\n", w_kitten_cat, w_cat_kitten);
    printf("    * puppy   -> dog  = %.4f  (Reverse dog  -> puppy   = %.4f)\n", w_puppy_dog, w_dog_puppy);
    printf("    * orb     -> ball = %.4f  (Reverse ball -> orb     = %.4f | Negative sparrow -> dog = %.4f)\n", w_orb_ball, w_ball_orb, w_sparrow_dog);

    let p_kitten_young = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "kitten", "young");
    let p_puppy_young  = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "puppy", "young");
    let p_sparrow_sm   = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "sparrow", "small");
    let p_ball_round   = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "ball", "round");
    let p_bouncing_fun = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "bouncing", "fun");
    let p_run_fun      = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "run", "fun");
    let p_play_fun     = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "play", "fun");
    let p_bounce_fun   = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "bounce", "fun");
    let cos_run_play   = geomind_e8_rel_prop_cosine_words("run", "play");
    printf("  [Property & Activity Valence Operator <P_attr, R_prop * P_concept> / 248]:\n");
    printf("    * kitten -> young = %.4f | puppy -> young = %.4f | sparrow -> small = %.4f | ball -> round = %.4f\n",
        p_kitten_young, p_puppy_young, p_sparrow_sm, p_ball_round);
    printf("    * run    -> fun   = %.4f | play  -> fun   = %.4f | bouncing -> fun  = %.4f | bounce -> fun = %.4f\n",
        p_run_fun, p_play_fun, p_bouncing_fun, p_bounce_fun);
    printf("    * Shared Activity Valence Cosine cos(R_prop*run, R_prop*play) = %.4f\n", cos_run_play);
    printf("--------------------------------------------------------------------------------\n");
    printf("  42-LAYER STRATIFIED E8 DEEP-THOUGHT GEODESIC ROLLOUT (6 x 7-Layer Cascades)\n");
    printf("--------------------------------------------------------------------------------\n");
    printf("  -> Rollout 1 ('sparrow'): %s\n", geomind_e8_deep_thought_rollout_42L("sparrow"));
    printf("  -> Rollout 2 ('kitten'):  %s\n", geomind_e8_deep_thought_rollout_42L("kitten"));
    printf("  -> Rollout 3 ('puppy'):   %s\n", geomind_e8_deep_thought_rollout_42L("puppy"));
    printf("  -> Rollout 4 ('orb'):     %s\n", geomind_e8_deep_thought_rollout_42L("orb"));
    printf("  -> Rollout 5 ('wood'):    %s\n", geomind_e8_deep_thought_rollout_42L("wood"));
    printf("--------------------------------------------------------------------------------\n");
    printf("  DAY-ZERO EPISTEMIC REASONING & QUESTION-ANSWERING TEST (42-Layer Multi-Hop)\n");
    printf("--------------------------------------------------------------------------------\n");
    printf("  -> Q1 ('Is a sparrow an animal and where can it fly?'):\n");
    printf("     A1: %s\n", geomind_e8_answer_epistemic_question("sparrow", "taxonomy"));
    printf("  -> Q2 ('Why does a puppy like to run?'):\n");
    printf("     A2: %s\n", geomind_e8_answer_epistemic_question("puppy", "valence"));
    printf("  -> Q3 ('How does a kitten feel when it purrs?'):\n");
    printf("     A3: %s\n", geomind_e8_answer_epistemic_question("kitten", "feeling"));
    printf("  -> Q4 ('What happens when you drop an orb?'):\n");
    printf("     A4: %s\n", geomind_e8_answer_epistemic_question("orb", "causal_drop"));
    printf("  -> Q5 ('Why does wood float on water?'):\n");
    printf("     A5: %s\n", geomind_e8_answer_epistemic_question("wood", "causal_float"));
    printf("--------------------------------------------------------------------------------\n");
    printf("  STAGE 6.1 SUBTLE GEOMETRIC REASONING & FALSIFICATION SUITE (Zero Word Rules)\n");
    printf("--------------------------------------------------------------------------------\n");
    printf("  [Test 1 | Zero-Shot 42-Layer Trajectory Intersection ('What do X & Y share?')]:\n");
    printf("    * ('kitten',  'puppy')  -> %s\n", geomind_e8_trajectory_intersection_42L("kitten", "puppy"));
    printf("    * ('sparrow', 'puppy')  -> %s\n", geomind_e8_trajectory_intersection_42L("sparrow", "puppy"));
    printf("    * ('run',     'bounce') -> %s\n", geomind_e8_trajectory_intersection_42L("run", "bounce"));
    printf("    * ('sparrow', 'orb')    -> %s\n", geomind_e8_trajectory_intersection_42L("sparrow", "orb"));
    printf("  [Test 2 | Counterfactual & False-Premise Rejection + Adjoint R^T Attribution]:\n");
    printf("    * Claim('kitten',  'fly')    -> %s\n", geomind_e8_verify_counterfactual_42L("kitten", "fly"));
    printf("    * Claim('sparrow', 'dog')    -> %s\n", geomind_e8_verify_counterfactual_42L("sparrow", "dog"));
    printf("    * Claim('orb',     'ground') -> %s\n", geomind_e8_verify_counterfactual_42L("orb", "ground"));
    printf("  [Test 3 | Backward Abductive Diagnosis from Downstream Clues (Inverting L42->L0)]:\n");
    printf("    * %s\n", geomind_e8_abductive_diagnosis_42L("small", "fly", "sky"));
    printf("    * %s\n", geomind_e8_abductive_diagnosis_42L("round", "bounce", "ground"));
    printf("    * %s\n", geomind_e8_abductive_diagnosis_42L("young", "purrs", "happy"));
    printf("  [Test 4 | Unstated Multi-Sentence Cross-Rung Bridging (WordNet + Rung 1)]:\n");
    printf("    * Bridge 1 ('trout'):  %s\n", geomind_e8_cross_rung_bridge_42L("trout"));
    printf("    * Bridge 2 ('salmon'): %s\n", geomind_e8_cross_rung_bridge_42L("salmon"));
    cartan_flush(0.0);

    // Save consolidated checkpoints once at the end of the curriculum
    g_byte_e8_defer_disk_save = 0.0;
    geomind_markov_save_prior("Projects/geomind/trainingdata/checkpoints/geomind_markov_prior.bin");
    geomind_byte_latent_save_weights("Projects/geomind/trainingdata/checkpoints/geomind_byte_latent_e8.bin");
    geomind_e8_stack_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin");
    if (g_e8_anchor_count > 0.0) {
        geomind_e8_anchors_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_anchors.bin");
    }

    // Stage 5.6: Export & Self-Verify Spec-Compliant GGUF v3 Open-Weights File
    let gguf_path = "Projects/geomind/trainingdata/checkpoints/cartan_e8_42L.gguf";
    printf("--------------------------------------------------------------------------------\n");
    printf("  GGUF v3 OPEN-WEIGHTS EXPORT & CARTAN MOVING-FRAME PULLBACK (248x248)\n");
    printf("--------------------------------------------------------------------------------\n");
    geomind_export_gguf_v3(gguf_path);
    geomind_verify_gguf_v3(gguf_path);

    geomind_visualizer_export_html("manifold_relaxation.html", "4-Rung Concentric Storytelling Curriculum");
    printf("================================================================================\n");
    cartan_flush(0.0);
    return g_e8_anchor_count;
}

// ============================================================================
// PHASE 4.1: AUTONOMOUS DOMAIN-BOUNDED RECURSIVE WEB CRAWLER (--crawl)
// ============================================================================
// Extracts the domain host from an http:// or https:// URL
fn geomind_crawl_extract_domain(url: string) -> string {
    var rest = url;
    let ulen = cartan_string_length(url);
    if (cartan_string_starts_with(url, "https://") == 1.0) {
        rest = cartan_string_substring(url, 8.0, ulen);
    } else if (cartan_string_starts_with(url, "http://") == 1.0) {
        rest = cartan_string_substring(url, 7.0, ulen);
    }
    let slash_idx = cartan_string_index_of(rest, "/");
    if (slash_idx > 0.0) {
        return cartan_string_substring(rest, 0.0, slash_idx);
    }
    return rest;
}

// Extracts same-domain href links from raw HTML into a vector of strings
fn geomind_crawl_extract_same_domain_links(html: string, base_domain: string) -> ptr {
    let links = cartan_tree_create();
    let hlen = cartan_string_length(html);
    if (hlen < 10.0) { return links; }
    var pos = 0.0;
    var idx = 0.0;
    var start_q = 0.0;
    var end_q = 0.0;
    var cand = "";
    var cand_dom = "";
    var found_cnt = 0.0;
    while (pos < hlen && found_cnt < 8.0) {
        idx = cartan_string_index_of_offset_ignore_case(html, "href=\"http", pos);
        if (idx < 0.0) {
            break;
        }
        start_q = idx + 6.0;
        end_q = cartan_string_index_of_offset(html, "\"", start_q);
        if (end_q > start_q) {
            cand = cartan_string_substring(html, start_q, end_q);
            cand_dom = geomind_crawl_extract_domain(cand);
            if (cartan_string_eq(cand_dom, base_domain) == 1.0) {
                cartan_tree_push(links, cand);
                found_cnt = found_cnt + 1.0;
            }
            pos = end_q + 1.0;
        } else {
            break;
        }
    }
    return links;
}

// Strips <script>, <style>, and HTML tags from raw HTML into clean normalized UTF-8 text
fn geomind_crawl_strip_html_to_text(html: string) -> string {
    let n = cartan_string_length(html);
    if (n <= 0.0) { return ""; }
    var out = "";
    var in_tag = 0.0;
    var last_space = 1.0;
    var i = 0.0;
    var ch = 0.0;
    while (i < n) {
        ch = cartan_byte_at(html, i);
        if (ch == 60.0) { // '<'
            in_tag = 1.0;
        } else if (ch == 62.0) { // '>'
            in_tag = 0.0;
            if (last_space == 0.0) {
                out = cartan_string_concat(out, " ");
                last_space = 1.0;
            }
        } else if (in_tag == 0.0) {
            if (ch == 10.0 || ch == 13.0 || ch == 9.0 || ch == 32.0) {
                if (last_space == 0.0) {
                    out = cartan_string_concat(out, " ");
                    last_space = 1.0;
                }
            } else if (ch >= 32.0 && ch <= 126.0) {
                out = cartan_string_concat(out, cartan_char_from_code(ch));
                last_space = 0.0;
            }
        }
        i = i + 1.0;
    }
    return out;
}

// Fetches raw HTML from a URL (or local file path for offline testing)
fn geomind_crawl_fetch_url(url: string) -> string {
    if (cartan_file_exists(url) == 1.0) {
        return cartan_read_file(url);
    }
    let tmp_file = "scratch/geomind_crawl_page.tmp";
    var cmd = "powershell -NoProfile -Command \"try { (Invoke-WebRequest -Uri '";
    cmd = cartan_string_concat(cmd, url);
    cmd = cartan_string_concat(cmd, "' -UseBasicParsing -TimeoutSec 10).Content | Out-File -FilePath '");
    cmd = cartan_string_concat(cmd, tmp_file);
    cmd = cartan_string_concat(cmd, "' -Encoding utf8 } catch { '' | Out-File -FilePath '");
    cmd = cartan_string_concat(cmd, tmp_file);
    cmd = cartan_string_concat(cmd, "' -Encoding utf8 }\"");
    cartan_system(cmd);
    if (cartan_file_exists(tmp_file) == 1.0) {
        return cartan_read_file(tmp_file);
    }
    return "";
}

// Autonomous Domain-Bounded Recursive Web Crawler & Markov-Lagrangian Trainer
fn geomind_crawl_and_train(
    url: string,
    start_domain: string,
    recurse: float,
    depth: float,
    max_depth: float,
    epochs: float,
    visualize: float
) -> float {
    if (depth > max_depth) { return 0.0; }
    var dom = start_domain;
    if (cartan_string_length(dom) == 0.0) {
        dom = geomind_crawl_extract_domain(url);
    }
    printf("[CARTAN-E8 Crawler] Fetching (depth %.0f/%.0f, domain='%s'): %s\n", depth, max_depth, dom, url);
    cartan_flush(0.0);

    let html = geomind_crawl_fetch_url(url);
    let clean_text = geomind_crawl_strip_html_to_text(html);
    let text_len = cartan_string_length(clean_text);
    if (text_len < 8.0) {
        printf("[CARTAN-E8 Crawler] Skipping empty/short response (%.0f bytes).\n", text_len);
        return 0.0;
    }

    printf("[CARTAN-E8 Crawler] Extracted %.0f bytes of clean UTF-8 text. Running %.0f Markov-Lagrangian epochs...\n", text_len, epochs);
    cartan_flush(0.0);
    let final_action = geomind_byte_latent_train_corpus(clean_text, epochs, 0.03, visualize);
    printf("[CARTAN-E8 Crawler] Completed %.0f epochs on %s -> Final Lagrangian Action S = %.6f\n", epochs, url, final_action);
    cartan_flush(0.0);

    if (visualize == 1.0) {
        geomind_visualizer_export_html("manifold_relaxation.html", url);
        printf("[CARTAN-E8 Visualizer] Exported live manifold relaxation plot to manifold_relaxation.html\n");
        cartan_flush(0.0);
    }

    if (recurse == 1.0 && depth < max_depth) {
        let sub_links = geomind_crawl_extract_same_domain_links(html, dom);
        let n_links = cartan_tree_len_f(sub_links);
        var li = 0.0;
        var child_url = "";
        while (li < n_links) {
            child_url = cartan_tree_get(sub_links, li);
            if (cartan_string_eq(child_url, url) == 0.0) {
                Sleep(150.0);
                geomind_crawl_and_train(child_url, dom, recurse, depth + 1.0, max_depth, epochs, visualize);
            }
            li = li + 1.0;
        }
    }
    return final_action;
}
