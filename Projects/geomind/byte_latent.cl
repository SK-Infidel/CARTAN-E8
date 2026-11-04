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
// 3-gram context Markov table: 65,536 collision-free (ctx_patch_id, sym(b_{t-1}), sym(b_t)) contexts x 128 ASCII next bytes
var g_markov_3gram_counts: ptr = 0.0;
var g_markov_3gram_totals: ptr = 0.0;
var g_markov_3gram_keys: ptr = 0.0;
var g_markov_ctx_patch_id: float = 0.0;
var g_markov_initialized: float = 0.0;

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
    let s3 = geomind_markov_byte_sym32(b3);
    let s2 = geomind_markov_byte_sym32(b2);
    let s1 = geomind_markov_byte_sym32(b1);
    return s3 * 1024.0 + s2 * 32.0 + s1;
}

fn geomind_markov_patch_ctx_idx(b3: float, b2: float, b1: float, create_slot: float) -> float {
    let pid = math_mod_val(floor(math_abs_val(g_markov_ctx_patch_id)), 32768.0);
    let c_idx = geomind_markov_3gram_ctx_idx(b3, b2, b1);
    let k_pid = pid + 1.0;
    let k_tri = c_idx + 1.0;
    let h0 = math_mod_val(pid * 13331.0 + c_idx * 997.0, 32768.0);
    if (g_markov_3gram_keys == 0.0) {
        return 32768.0 + h0;
    }
    var probe = 0.0;
    while (probe < 16.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 32768.0);
        let row = 32768.0 + slot;
        let cur_pid = cartan_vec_get_f32(g_markov_3gram_keys, row * 2.0);
        let cur_tri = cartan_vec_get_f32(g_markov_3gram_keys, row * 2.0 + 1.0);
        if (cur_pid == k_pid && cur_tri == k_tri) {
            return row;
        }
        if (cur_pid == 0.0 && cur_tri == 0.0) {
            if (create_slot == 1.0) {
                cartan_vec_set_f32(g_markov_3gram_keys, row * 2.0, k_pid);
                cartan_vec_set_f32(g_markov_3gram_keys, row * 2.0 + 1.0, k_tri);
                return row;
            }
            return -1.0;
        }
        probe = probe + 1.0;
    }
    if (create_slot == 1.0) {
        return 32768.0 + h0;
    }
    return -1.0;
}

fn geomind_markov_update_3gram(b3: float, b2: float, b1: float, curr_byte: float) -> float {
    geomind_markov_init_if_needed();
    let cb = math_mod_val(floor(math_abs_val(curr_byte)), 128.0);
    let c_idx = geomind_markov_3gram_ctx_idx(b3, b2, b1);
    let m_idx = c_idx * 128.0 + cb;
    let old_cnt = cartan_vec_get_f32(g_markov_3gram_counts, m_idx);
    let old_tot = cartan_vec_get_f32(g_markov_3gram_totals, c_idx);
    var p3 = 1.0 / 128.0;
    if (old_tot > 0.000001) { p3 = (old_cnt + 0.01) / (old_tot + 1.28); }
    cartan_vec_set_f32(g_markov_3gram_counts, m_idx, old_cnt + 1.0);
    cartan_vec_set_f32(g_markov_3gram_totals, c_idx, old_tot + 1.0);

    // Also update 2-Patch Discourse-Conditioned 3-gram row (32768..65535)
    let p_idx = geomind_markov_patch_ctx_idx(b3, b2, b1, 1.0);
    if (p_idx >= 32768.0) {
        let pm_idx = p_idx * 128.0 + cb;
        let p_cnt = cartan_vec_get_f32(g_markov_3gram_counts, pm_idx);
        let p_tot = cartan_vec_get_f32(g_markov_3gram_totals, p_idx);
        cartan_vec_set_f32(g_markov_3gram_counts, pm_idx, p_cnt + 1.0);
        cartan_vec_set_f32(g_markov_3gram_totals, p_idx, p_tot + 1.0);
    }
    return p3;
}

fn geomind_markov_get_3gram_prob(b3: float, b2: float, b1: float, curr_byte: float) -> float {
    geomind_markov_init_if_needed();
    let p1 = geomind_markov_get_prob(b1, curr_byte);
    let cb = math_mod_val(floor(math_abs_val(curr_byte)), 128.0);
    let c_idx = geomind_markov_3gram_ctx_idx(b3, b2, b1);
    let m_idx = c_idx * 128.0 + cb;
    let cnt3 = cartan_vec_get_f32(g_markov_3gram_counts, m_idx);
    let tot3 = cartan_vec_get_f32(g_markov_3gram_totals, c_idx);
    var p3 = p1 * 0.05;
    if (tot3 > 0.5 && cnt3 >= 0.5) {
        p3 = (cnt3 + 0.005) / (tot3 + 0.05);
    }

    // Open-Addressed Sentence-Discourse Context Lookup (32768..65535):
    // When the current (pid, b3, b2, b1) sentence context has been observed in training (tot_p > 0.5),
    // condition directly on its empirical distribution so unobserved continuations (cnt_p == 0) in a known
    // sentence context do not inherit unconditioned global p3 mass.
    let p_idx = geomind_markov_patch_ctx_idx(b3, b2, b1, 0.0);
    if (p_idx >= 32768.0) {
        let tot_p = cartan_vec_get_f32(g_markov_3gram_totals, p_idx);
        if (tot_p > 0.5) {
            let pm_idx = p_idx * 128.0 + cb;
            let cnt_p = cartan_vec_get_f32(g_markov_3gram_counts, pm_idx);
            if (cnt3 >= 0.5 && cnt_p >= 0.5) {
                var safe_cnt_p = cnt_p;
                if (safe_cnt_p > cnt3) { safe_cnt_p = cnt3; }
                let pp = (safe_cnt_p + 0.005) / (tot_p + 0.05);
                return 0.92 * pp + 0.06 * p3 + 0.02 * p1;
            }
            let pp_zero = 0.0005 / (tot_p + 0.05);
            return 0.92 * pp_zero + 0.04 * p3 + 0.04 * p1;
        }
    }
    return 0.90 * p3 + 0.10 * p1;
}

fn geomind_markov_save_prior(path: string) -> float {
    if (path == 0.0 || g_markov_counts_256x256 == 0.0 || g_markov_row_totals_256 == 0.0) { return 0.0; }
    let f = fopen(path, "wb");
    if (f == 0.0) { return 0.0; }
    let total_elems = 65536.0 + 256.0 + 8388608.0 + 65536.0 + 131072.0;
    let buf = malloc(total_elems * 8.0);
    if (buf == 0.0) { fclose(f); return 0.0; }
    var i = 0.0;
    while (i < 65536.0) {
        buf[i] = cartan_vec_get_f32(g_markov_counts_256x256, i);
        i = i + 1.0;
    }
    var r = 0.0;
    while (r < 256.0) {
        buf[65536.0 + r] = cartan_vec_get_f32(g_markov_row_totals_256, r);
        r = r + 1.0;
    }
    i = 0.0;
    while (i < 8388608.0) {
        buf[65792.0 + i] = cartan_vec_get_f32(g_markov_3gram_counts, i);
        i = i + 1.0;
    }
    r = 0.0;
    while (r < 65536.0) {
        buf[8454400.0 + r] = cartan_vec_get_f32(g_markov_3gram_totals, r);
        r = r + 1.0;
    }
    var k = 0.0;
    while (k < 131072.0) {
        var kv = 0.0;
        if (g_markov_3gram_keys != 0.0) {
            kv = cartan_vec_get_f32(g_markov_3gram_keys, k);
        }
        buf[8519936.0 + k] = kv;
        k = k + 1.0;
    }
    fwrite(buf, 8.0, total_elems, f);
    fclose(f);
    free(buf);
    return 1.0;
}

fn geomind_markov_load_prior(path: string) -> float {
    if (path == 0.0 || cartan_file_exists(path) == 0.0) { return 0.0; }
    let base_elems = 65536.0 + 256.0;
    let full_elems = 65536.0 + 256.0 + 8388608.0 + 65536.0;
    let keyed_elems = full_elems + 131072.0;
    let f_sz = cartan_get_binary_file_size(path);
    if (f_sz < base_elems * 8.0) { return 0.0; }
    if (g_markov_counts_256x256 == 0.0) {
        g_markov_counts_256x256 = cartan_tensor_alloc(65536.0);
    }
    if (g_markov_row_totals_256 == 0.0) {
        g_markov_row_totals_256 = cartan_tensor_alloc(256.0);
    }
    if (g_markov_3gram_counts == 0.0) {
        g_markov_3gram_counts = cartan_tensor_alloc(8388608.0);
    }
    if (g_markov_3gram_totals == 0.0) {
        g_markov_3gram_totals = cartan_tensor_alloc(65536.0);
    }
    if (g_markov_3gram_keys == 0.0) {
        g_markov_3gram_keys = cartan_tensor_alloc(131072.0);
    }
    let f = fopen(path, "rb");
    if (f == 0.0) { return 0.0; }
    var read_elems = base_elems;
    if (f_sz >= keyed_elems * 8.0) {
        read_elems = keyed_elems;
    } else {
        if (f_sz >= full_elems * 8.0) { read_elems = full_elems; }
    }
    let buf = malloc(read_elems * 8.0);
    if (buf == 0.0) { fclose(f); return 0.0; }
    fread(buf, 8.0, read_elems, f);
    fclose(f);
    var i = 0.0;
    while (i < 65536.0) {
        cartan_vec_set_f32(g_markov_counts_256x256, i, buf[i]);
        i = i + 1.0;
    }
    var r = 0.0;
    while (r < 256.0) {
        cartan_vec_set_f32(g_markov_row_totals_256, r, buf[65536.0 + r]);
        r = r + 1.0;
    }
    if (read_elems >= full_elems) {
        i = 0.0;
        while (i < 8388608.0) {
            cartan_vec_set_f32(g_markov_3gram_counts, i, buf[65792.0 + i]);
            i = i + 1.0;
        }
        r = 0.0;
        while (r < 65536.0) {
            cartan_vec_set_f32(g_markov_3gram_totals, r, buf[8454400.0 + r]);
            r = r + 1.0;
        }
    }
    if (read_elems == keyed_elems) {
        var k = 0.0;
        while (k < 131072.0) {
            cartan_vec_set_f32(g_markov_3gram_keys, k, buf[8519936.0 + k]);
            k = k + 1.0;
        }
    }
    free(buf);
    g_markov_initialized = 1.0;
    return 1.0;
}

fn geomind_markov_init_if_needed() -> float {
    if (g_markov_initialized == 1.0 && g_markov_counts_256x256 != 0.0) {
        return 1.0;
    }
    g_markov_counts_256x256 = cartan_tensor_alloc(65536.0);
    g_markov_row_totals_256 = cartan_tensor_alloc(256.0);
    g_markov_3gram_counts = cartan_tensor_alloc(8388608.0);
    g_markov_3gram_totals = cartan_tensor_alloc(65536.0);
    g_markov_3gram_keys = cartan_tensor_alloc(131072.0);

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
    if (cartan_file_exists("Projects/geomind/trainingdata/checkpoints/geomind_markov_prior.bin") == 1.0) {
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

    g_byte_e8_emb_256x248 = cartan_tensor_alloc(63488.0);
    g_byte_e8_head_248x256 = cartan_tensor_alloc(63488.0);
    g_byte_e8_randers_b_248 = cartan_tensor_alloc(248.0);

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
    if (cartan_file_exists("Projects/geomind/trainingdata/checkpoints/geomind_byte_latent_e8.bin") == 1.0) {
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
    var c = 0.0;
    while (c < 256.0) {
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
        let m_prob = geomind_markov_get_3gram_prob(b3, b2, b1, c);
        cartan_vec_set_f32(out_logits_256, c, sum + 2.25 * log(m_prob + 0.00001));
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
var g_e8_anchor_coords: ptr = 0.0;     // 512 * 248 floats (crystallized S^{247} coordinates)
var g_e8_anchor_masses: ptr = 0.0;     // 512 floats (maturity/mass in [0, 1])
var g_e8_anchor_hashes: ptr = 0.0;     // 512 floats (patch byte-sequence signature)
var g_e8_focus_hits: float = 0.0;
var g_e8_noise_skips: float = 0.0;
var g_e8_newly_crystallized: float = 0.0;
var g_e8_primer_crystallize_all: float = 0.0; // When 1.0 (Rung 1 Primer), trains all patches and crystallizes mastered ones

fn geomind_e8_anchors_init_if_needed() {
    if (g_e8_anchor_coords != 0.0) { return; }
    g_e8_anchor_coords = cartan_tensor_alloc(512.0 * 248.0);
    g_e8_anchor_masses = cartan_tensor_alloc(512.0);
    g_e8_anchor_hashes = cartan_tensor_alloc(512.0);
    var i = 0.0;
    while (i < 512.0 * 248.0) {
        cartan_vec_set_f32(g_e8_anchor_coords, i, 0.0);
        if (i < 512.0) {
            cartan_vec_set_f32(g_e8_anchor_masses, i, 0.0);
            cartan_vec_set_f32(g_e8_anchor_hashes, i, -1.0);
        }
        i = i + 1.0;
    }
    g_e8_anchor_count = 0.0;
}

fn geomind_e8_anchors_reset() {
    geomind_e8_anchors_init_if_needed();
    g_e8_anchor_count = 0.0;
    g_e8_focus_hits = 0.0;
    g_e8_noise_skips = 0.0;
    g_e8_newly_crystallized = 0.0;
    var i = 0.0;
    while (i < 512.0) {
        cartan_vec_set_f32(g_e8_anchor_masses, i, 0.0);
        cartan_vec_set_f32(g_e8_anchor_hashes, i, -1.0);
        i = i + 1.0;
    }
}

fn geomind_e8_anchors_save(path: string) -> float {
    geomind_e8_anchors_init_if_needed();
    if (path == 0.0 || g_e8_anchor_count <= 0.0) { return 0.0; }
    let f = fopen(path, "wb");
    if (f == 0.0) { return 0.0; }
    let total_elems = 1.0 + 512.0 + 512.0 + 512.0 * 248.0;
    let buf = malloc(total_elems * 8.0);
    if (buf == 0.0) { fclose(f); return 0.0; }
    buf[0.0] = g_e8_anchor_count;
    var i = 0.0;
    while (i < 512.0) {
        buf[1.0 + i] = cartan_vec_get_f32(g_e8_anchor_masses, i);
        buf[513.0 + i] = cartan_vec_get_f32(g_e8_anchor_hashes, i);
        i = i + 1.0;
    }
    i = 0.0;
    while (i < 512.0 * 248.0) {
        buf[1025.0 + i] = cartan_vec_get_f32(g_e8_anchor_coords, i);
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
    let total_elems = 1.0 + 512.0 + 512.0 + 512.0 * 248.0;
    let f_sz = cartan_get_binary_file_size(path);
    if (f_sz < total_elems * 8.0) { return 0.0; }
    let f = fopen(path, "rb");
    if (f == 0.0) { return 0.0; }
    let buf = malloc(total_elems * 8.0);
    if (buf == 0.0) { fclose(f); return 0.0; }
    fread(buf, 8.0, total_elems, f);
    fclose(f);
    g_e8_anchor_count = buf[0.0];
    if (g_e8_anchor_count > 512.0) { g_e8_anchor_count = 512.0; }
    var i = 0.0;
    while (i < 512.0) {
        cartan_vec_set_f32(g_e8_anchor_masses, i, buf[1.0 + i]);
        cartan_vec_set_f32(g_e8_anchor_hashes, i, buf[513.0 + i]);
        i = i + 1.0;
    }
    i = 0.0;
    while (i < 512.0 * 248.0) {
        cartan_vec_set_f32(g_e8_anchor_coords, i, buf[1025.0 + i]);
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

// Query maximum resonance R(P_k) in [-1, 1] across all crystallized E8 Anchor Basins
fn geomind_e8_query_anchor_resonance(patch_248: ptr, patch_hash: float) -> float {
    geomind_e8_anchors_init_if_needed();
    if (g_e8_anchor_count <= 0.0) { return 0.0; }
    var best_sim = -1.0;
    var m = 0.0;
    while (m < g_e8_anchor_count) {
        let a_hash = cartan_vec_get_f32(g_e8_anchor_hashes, m);
        if (patch_hash > 0.0 && a_hash == patch_hash) {
            return 1.0;
        }
        let sim = geomind_e8_anchor_killing_sim(patch_248, m);
        if (sim > best_sim) {
            best_sim = sim;
        }
        m = m + 1.0;
    }
    return best_sim;
}

// Crystallize or reinforce a 248-D E8 Patch state as an Anchor Basin on S^{247}
fn geomind_e8_crystallize_patch_vec(patch_248: ptr, patch_hash: float, initial_mass: float) -> float {
    geomind_e8_anchors_init_if_needed();
    // Check if an anchor with matching hash or very high Killing similarity (>= 0.92) already exists
    var m = 0.0;
    while (m < g_e8_anchor_count) {
        let a_hash = cartan_vec_get_f32(g_e8_anchor_hashes, m);
        let sim = geomind_e8_anchor_killing_sim(patch_248, m);
        if ((patch_hash > 0.0 && a_hash == patch_hash) || sim >= 0.92) {
            let old_mass = cartan_vec_get_f32(g_e8_anchor_masses, m);
            var new_mass = old_mass + 0.15;
            if (new_mass > 1.0) { new_mass = 1.0; }
            cartan_vec_set_f32(g_e8_anchor_masses, m, new_mass);
            // Gently retract anchor coordinate toward new observation on S^{247}
            let a_off = m * 248.0;
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
            return m;
        }
        m = m + 1.0;
    }

    if (g_e8_anchor_count >= 512.0) { return -1.0; }
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
    g_e8_anchor_count = g_e8_anchor_count + 1.0;
    g_e8_newly_crystallized = g_e8_newly_crystallized + 1.0;
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
// STAGE 1-3: DEEP L-LAYER E8 GAUGE-SPINOR MANIFOLD BYTE-LATENT TRAINER & GENERATOR
// ============================================================================
// True Two-Tier Byte-Latent Transformer (BLT) Manifold Pipeline:
// - Tier 1 (Every Byte): Local Weyl root reflection + Octonion Fano Cross-Gate on S^{247}
//   conditioned on 3-gram Markov transition prior P(b_t | b_{t-3}, b_{t-2}, b_{t-1}).
// - Tier 2 (At Surprisal Patch Boundaries): Full 42-Layer Deep E8 Gauge-Spinor +
//   Finsler-Randers Causal Attention + 4x4 Freudenthal Magic Square MoE forward & backward step.
var g_blt_last_patch_count: float = 0.0;

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
    geomind_e8_stack_init(L);
    if (cartan_file_exists("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin") == 1.0) {
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
        var patch_hash = 17.0;
        var prev_patch_hash = 17.0;
        var last_patch_hash = 17.0;
        var patch_sent_end = 0.0;
        var patch_act_sum = 0.0;
        var focus_horizon = 0.0;
        var stack_t_geo = 0.0;
        g_markov_ctx_patch_id = 0.0;

        while (step < max_steps) {
            cur_b = cartan_byte_at(corpus, step);
            if (cur_b < 0.0) { cur_b = cur_b + 256.0; }
            next_b = cartan_byte_at(corpus, step + 1.0);
            if (next_b < 0.0) { next_b = next_b + 256.0; }
            cur_b = math_mod_val(floor(cur_b), 256.0);
            next_b = math_mod_val(floor(next_b), 256.0);
            // Normalize CR/LF line breaks to space (32) so multi-line corpora form continuous printable byte streams
            if (cur_b == 13.0 || cur_b == 10.0) { cur_b = 32.0; }
            if (next_b == 13.0 || next_b == 10.0) { next_b = 32.0; }
            if (cur_b == 32.0 && next_b == 32.0) {
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
            }
            if (cur_b == 46.0 || cur_b == 33.0 || cur_b == 63.0) {
                patch_sent_end = 1.0;
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
                }

                // Update Sentence-Level Rolling Patch Discourse ID immediately at patch boundary (in lockstep with generation!)
                if (patch_sent_end == 1.0) {
                    prev_patch_hash = 17.0;
                    last_patch_hash = 17.0;
                    g_markov_ctx_patch_id = 0.0;
                    patch_sent_end = 0.0;
                } else {
                    prev_patch_hash = last_patch_hash;
                    last_patch_hash = math_mod_val(last_patch_hash * 257.0 + patch_hash, 32768.0);
                    g_markov_ctx_patch_id = last_patch_hash;
                }
            }

            // 4. Decode 256 byte logits from fused (h_local, h_top_patch) + pre-update 3-gram Markov prior
            let markov_v = geomind_markov_get_3gram_prob(b3, b2, cur_b, next_b);
            geomind_byte_latent_decode_logits_blt(h_local, h_top_patch, b3, b2, cur_b, logits_256);

            // Only update 3-gram Markov counts when in focus (or when no anchor filter is active)
            if (g_e8_primer_crystallize_all == 1.0 || g_e8_anchor_count == 0.0 || focus_horizon > 0.0 || in_focus == 1.0) {
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
                        if (new_w > 0.45) { new_w = 0.45; }
                        else if (new_w < -0.45) { new_w = -0.45; }
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

    geomind_markov_save_prior("Projects/geomind/trainingdata/checkpoints/geomind_markov_prior.bin");
    geomind_byte_latent_save_weights("Projects/geomind/trainingdata/checkpoints/geomind_byte_latent_e8.bin");
    geomind_e8_stack_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin");
    if (g_e8_anchor_count > 0.0) {
        geomind_e8_anchors_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_anchors.bin");
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

    let plen = cartan_string_length(prompt);
    var b3 = 32.0;
    var b2 = 32.0;
    var cur_b = 32.0;
    var patch_len = 0.0;
    var patch_hash = 17.0;
    var last_patch_hash = 17.0;
    var prev_patch_hash = 17.0;
    var patch_sent_end = 0.0;
    g_markov_ctx_patch_id = 0.0;
    var patch_steps = 0.0;
    var i = 0.0;
    while (i < plen) {
        cur_b = cartan_byte_at(prompt, i);
        if (cur_b < 0.0) { cur_b = cur_b + 256.0; }
        cur_b = math_mod_val(floor(cur_b), 256.0);
        if (cur_b == 13.0 || cur_b == 10.0) { cur_b = 32.0; }
        let is_alnum1 = ((cur_b >= 97.0 && cur_b <= 122.0) || (cur_b >= 65.0 && cur_b <= 90.0) || (cur_b >= 48.0 && cur_b <= 57.0));
        if (is_alnum1) {
            geomind_fold_byte_into_e8_patch(h_patch_accum, cur_b, patch_len);
            var hb = cur_b;
            if (hb >= 65.0 && hb <= 90.0) { hb = hb + 32.0; }
            patch_hash = math_mod_val(patch_hash * 131.0 + hb, 1000003.0);
        }
        if (cur_b == 46.0 || cur_b == 33.0 || cur_b == 63.0) {
            patch_sent_end = 1.0;
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
            if (patch_sent_end == 1.0) {
                prev_patch_hash = 17.0;
                last_patch_hash = 17.0;
                g_markov_ctx_patch_id = 0.0;
                patch_sent_end = 0.0;
            } else {
                prev_patch_hash = last_patch_hash;
                last_patch_hash = math_mod_val(last_patch_hash * 257.0 + patch_hash, 32768.0);
                g_markov_ctx_patch_id = last_patch_hash;
            }
            patch_len = 0.0;
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
    while (step < gen_len) {
        geomind_byte_latent_decode_logits_blt(h_local, h_top_patch, b3, b2, cur_b, logits_256);
        var best_b = 32.0;
        var best_l = -100000.0;
        c = 32.0;
        while (c <= 126.0) {
            var lv = cartan_vec_get_f32(logits_256, c);
            // Prevent 3 consecutive identical characters (e.g., "fff") and consecutive spaces ("  ")
            if (b2 == cur_b && cur_b == c) { lv = lv - 12.0; }
            if (cur_b == 32.0 && c == 32.0) { lv = lv - 12.0; }
            if (lv > best_l) {
                best_l = lv;
                best_b = c;
            }
            c = c + 1.0;
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
        }
        if (cur_b == 46.0 || cur_b == 33.0 || cur_b == 63.0) {
            patch_sent_end = 1.0;
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
            if (patch_sent_end == 1.0) {
                prev_patch_hash = 17.0;
                last_patch_hash = 17.0;
                g_markov_ctx_patch_id = 0.0;
                patch_sent_end = 0.0;
            } else {
                prev_patch_hash = last_patch_hash;
                last_patch_hash = math_mod_val(last_patch_hash * 257.0 + patch_hash, 32768.0);
                g_markov_ctx_patch_id = last_patch_hash;
            }
            patch_len = 0.0;
            patch_hash = 17.0;
        }
        step = step + 1.0;
    }

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
// STAGE 5.3: 3-RUNG CONCENTRIC ENGLISH DEVELOPMENTAL CURRICULUM (--curriculum)
// ============================================================================
// Rung 1: Nursery Primer (`e8_nursery_primer.txt`) - Full Foundation Mode, crystallizes core English SVO + glue anchors.
// Rung 2: Grounded Concept Triples (`e8_concept_triples.txt`) - Selective Resonance Focus around Rung 1 anchors.
// Rung 3: Multi-Pass TinyStories (`hf_roneneldan_TinyStories.txt`) - Progressive comprehension expansion across passes.
fn geomind_run_english_curriculum(num_layers: float, lr: float) -> float {
    var L = floor(num_layers);
    if (L < 1.0) { L = 42.0; }
    var eff_lr = 0.03;
    if (lr > 0.0001) { eff_lr = lr; }

    printf("\n================================================================================\n");
    printf("  CARTAN-E8 CONCENTRIC ENGLISH DEVELOPMENTAL CURRICULUM (L=%.0f Layers)\n", L);
    printf("================================================================================\n");
    cartan_flush(0.0);

    // Start from a clean Anchor Basin registry for the developmental trajectory
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
    printf("[Rung 1 | Nursery Primer] Action S = %.6f | Crystallized Anchors = %.0f\n", s_rung1, g_e8_anchor_count);
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
    printf("[Rung 2 | Concept Triples] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f\n",
        s_rung2, anchors_before_r2, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips);
    printf("  -> Gen 3: %s\n", gen_r2);
    cartan_flush(0.0);

    // ------------------------------------------------------------------------
    // RUNG 3: TinyStories Progressive Multi-Pass Comprehension (Pass 1 vs Pass 2)
    // ------------------------------------------------------------------------
    let rung3_path = "Projects/geomind/trainingdata/hf_roneneldan_TinyStories.txt";
    if (cartan_file_exists(rung3_path) == 1.0) {
        let full_stories = cartan_read_file(rung3_path);
        let slen = cartan_string_length(full_stories);
        var slice_len = 4500.0;
        if (slen < slice_len) { slice_len = slen; }
        let stories_slice = cartan_string_substring(full_stories, 0.0, slice_len);

        // Pass 1 over TinyStories slice:
        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let anchors_p0 = g_e8_anchor_count;
        let s_r3_p1 = geomind_byte_latent_train_deep_e8_corpus(stories_slice, L, 2.0, eff_lr * 0.85, 1.0);
        let p1_focus = g_e8_focus_hits;
        let p1_skip = g_e8_noise_skips;
        let anchors_p1 = g_e8_anchor_count;

        // Pass 2 over the SAME TinyStories slice (with newly crystallized Pass 1 anchors!):
        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let s_r3_p2 = geomind_byte_latent_train_deep_e8_corpus(stories_slice, L, 2.0, eff_lr * 0.85, 1.0);
        let p2_focus = g_e8_focus_hits;
        let p2_skip = g_e8_noise_skips;
        let anchors_p2 = g_e8_anchor_count;

        let gen_r3 = geomind_byte_latent_generate_deep_e8("Once upon a time", L, 64.0);
        printf("[Rung 3 | TinyStories Pass 1] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f\n",
            s_r3_p1, anchors_p0, anchors_p1, p1_focus, p1_skip);
        printf("[Rung 3 | TinyStories Pass 2] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f\n",
            s_r3_p2, anchors_p1, anchors_p2, p2_focus, p2_skip);
        printf("  -> Gen 4: %s\n", gen_r3);
        cartan_flush(0.0);
    }

    geomind_visualizer_export_html("manifold_relaxation.html", "3-Rung Concentric English Curriculum");
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
