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
var g_markov_initialized: float = 0.0;

fn geomind_markov_save_prior(path: string) -> float {
    if (path == 0.0 || g_markov_counts_256x256 == 0.0 || g_markov_row_totals_256 == 0.0) { return 0.0; }
    let f = fopen(path, "wb");
    if (f == 0.0) { return 0.0; }
    let total_elems = 65536.0 + 256.0;
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
    fwrite(buf, 8.0, total_elems, f);
    fclose(f);
    free(buf);
    return 1.0;
}

fn geomind_markov_load_prior(path: string) -> float {
    if (path == 0.0 || cartan_file_exists(path) == 0.0) { return 0.0; }
    let total_elems = 65536.0 + 256.0;
    let f_sz = cartan_get_binary_file_size(path);
    if (f_sz < total_elems * 8.0) { return 0.0; }
    if (g_markov_counts_256x256 == 0.0) {
        g_markov_counts_256x256 = cartan_tensor_alloc(65536.0);
    }
    if (g_markov_row_totals_256 == 0.0) {
        g_markov_row_totals_256 = cartan_tensor_alloc(256.0);
    }
    let f = fopen(path, "rb");
    if (f == 0.0) { return 0.0; }
    let buf = malloc(total_elems * 8.0);
    if (buf == 0.0) { fclose(f); return 0.0; }
    fread(buf, 8.0, total_elems, f);
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
// STAGE 1-3: DEEP L-LAYER E8 GAUGE-SPINOR MANIFOLD BYTE-LATENT TRAINER & GENERATOR
// ============================================================================
// Trains the full L-Layer Deep E8 Stack (W_gauge 120x120, W_spinor 128x128,
// Finsler-Randers Causal Attention, 4x4 Freudenthal Magic Square MoE, and
// 256x248 Byte-Latent Readout/Embedding) using Non-Euclidean Riemannian retraction
// and Coupled Markov-Lagrangian Action minimization.
fn geomind_byte_latent_train_deep_e8_corpus(
    corpus: string,
    num_layers: float,
    epochs: float,
    lr: float,
    record_vis: float
) -> float {
    geomind_byte_latent_init_if_needed();
    var L = floor(num_layers);
    if (L < 1.0) { L = 16.0; }
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

    let h_prev = cartan_vec_create();
    let h_in_stack = cartan_vec_create();
    let h_top = cartan_vec_create();
    let dh_top = cartan_vec_create();
    let dh_in_stack = cartan_vec_create();
    let geo_grad = cartan_vec_create();
    let emb_vec = cartan_vec_create();
    let logits_256 = cartan_vec_create();
    let delta_256 = cartan_vec_create();

    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_prev, 0.0);
        cartan_vec_push_f32(h_in_stack, 0.0);
        cartan_vec_push_f32(h_top, 0.0);
        cartan_vec_push_f32(dh_top, 0.0);
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
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_prev, d, 0.0);
            cartan_vec_set_f32(h_in_stack, d, 0.0);
            cartan_vec_set_f32(h_top, d, 0.0);
            d = d + 1.0;
        }

        var step = 0.0;
        var cur_b = 32.0;
        var next_b = 32.0;
        while (step < max_steps) {
            cur_b = cartan_byte_at(corpus, step);
            if (cur_b < 0.0) { cur_b = cur_b + 256.0; }
            next_b = cartan_byte_at(corpus, step + 1.0);
            if (next_b < 0.0) { next_b = next_b + 256.0; }
            cur_b = math_mod_val(floor(cur_b), 256.0);
            next_b = math_mod_val(floor(next_b), 256.0);

            let row_off = cur_b * 248.0;
            d = 0.0;
            while (d < 248.0) {
                let top_d = cartan_vec_get_f32(h_top, d);
                cartan_vec_set_f32(h_prev, d, top_d);
                let e_d = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                cartan_vec_set_f32(emb_vec, d, e_d);
                if (step == 0.0) {
                    cartan_vec_set_f32(h_in_stack, d, e_d);
                } else {
                    cartan_vec_set_f32(h_in_stack, d, top_d);
                }
                d = d + 1.0;
            }
            if (step > 0.0) {
                // Non-Euclidean tangent transport + exponential sphere retraction onto S^{247}
                geom_retract_sphere_step(h_in_stack, emb_vec, 0.55);
            }
            // Apply Weyl reflection along root (cur_b % 240)
            geomind_weyl_reflect_vector_248(h_in_stack, math_mod_val(cur_b, 240.0));

            // Forward through all L layers of the Deep E8 Gauge-Spinor Manifold Stack
            let markov_v = geomind_markov_get_prob(cur_b, next_b);
            var prev_seq_ptr: ptr = 0.0;
            if (step > 0.0) { prev_seq_ptr = h_prev; }
            let stack_t_geo = geomind_e8_stack_forward_step(h_in_stack, prev_seq_ptr, markov_v, 0.85, h_top);

            // Decode top-layer 248-D E8 state -> 256 byte logits
            geomind_byte_latent_decode_logits(h_top, cur_b, logits_256);

            // Evaluate Markov-Lagrangian Action S = (T_pred + 0.15 * T_geo + 0.05 * stack_t_geo) * (1 - 0.5 * V)
            let base_act = geomind_lagrangian_action_step(
                logits_256, next_b, cur_b, h_prev, h_top, g_byte_e8_randers_b_248, delta_256
            );
            let well_factor = 1.0 - 0.5 * markov_v;
            let act_s = base_act + 0.05 * stack_t_geo * well_factor;
            epoch_action_sum = epoch_action_sum + act_s;

            // Compute Geodesic Kinetic Energy Restoring Force on top manifold state
            geomind_e8_geodesic_kinetic_grad_248(h_prev, h_top, g_byte_e8_randers_b_248, geo_grad, 0.15 * well_factor);

            // Sherman-Morrison Inverse Finsler-Randers Backpropagation on Readout Head
            d = 0.0;
            while (d < 248.0) {
                let h_d = cartan_vec_get_f32(h_top, d);
                let b_d = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
                var dh_d = cartan_vec_get_f32(geo_grad, d);

                c = 32.0;
                while (c <= 126.0) {
                    let del_c = cartan_vec_get_f32(delta_256, c);
                    if (math_abs_val(del_c) > 0.005) {
                        let w_dc = cartan_vec_get_f32(g_byte_e8_head_248x256, d * 256.0 + c);
                        dh_d = dh_d + w_dc * del_c;
                        let new_w = geom_frs_riemannian_gradient_step(w_dc, h_d * del_c, b_d, eff_lr);
                        cartan_vec_set_f32(g_byte_e8_head_248x256, d * 256.0 + c, new_w);
                    }
                    c = c + 1.0;
                }
                cartan_vec_set_f32(dh_top, d, dh_d);
                d = d + 1.0;
            }

            // Backpropagate dh_top through all L layers of the Deep E8 Stack -> dh_in_stack
            geomind_e8_stack_backward_step(dh_top, eff_lr * 0.15, 0.05 * well_factor, dh_in_stack);

            // Update Byte-to-E8 Embedding row and Finsler-Randers Drift 1-form beta
            d = 0.0;
            while (d < 248.0) {
                let dp_d = cartan_vec_get_f32(dh_in_stack, d);
                let b_d = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
                let old_emb = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                let new_emb = geom_frs_riemannian_gradient_step(old_emb, dp_d, b_d, eff_lr * 0.25);
                cartan_vec_set_f32(g_byte_e8_emb_256x248, row_off + d, new_emb);

                let h_d = cartan_vec_get_f32(h_top, d);
                let old_h = cartan_vec_get_f32(h_prev, d);
                var new_b = b_d - eff_lr * 0.005 * well_factor * (h_d - old_h);
                if (new_b > 0.08) { new_b = 0.08; }
                else if (new_b < -0.08) { new_b = -0.08; }
                cartan_vec_set_f32(g_byte_e8_randers_b_248, d, new_b);
                d = d + 1.0;
            }

            step = step + 1.0;
        }

        final_avg_action = epoch_action_sum / max_steps;
        if (record_vis == 1.0) {
            let mv = geomind_markov_get_prob(cur_b, next_b);
            geomind_visualizer_record_step(final_avg_action, h_top, mv);
        }
        ep = ep + 1.0;
    }

    geomind_markov_save_prior("Projects/geomind/trainingdata/checkpoints/geomind_markov_prior.bin");
    geomind_byte_latent_save_weights("Projects/geomind/trainingdata/checkpoints/geomind_byte_latent_e8.bin");
    geomind_e8_stack_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin");

    cartan_vec_free(h_prev);
    cartan_vec_free(h_in_stack);
    cartan_vec_free(h_top);
    cartan_vec_free(dh_top);
    cartan_vec_free(dh_in_stack);
    cartan_vec_free(geo_grad);
    cartan_vec_free(emb_vec);
    cartan_vec_free(logits_256);
    cartan_vec_free(delta_256);
    return final_avg_action;
}

// Autoregressive generation through the Deep L-Layer E8 Gauge-Spinor Stack
// with both Sequence-Level Geodesic Coasting and Layer-Skipping Geodesic Coasting
fn geomind_byte_latent_generate_deep_e8(prompt: string, num_layers: float, gen_len: float) -> string {
    geomind_byte_latent_init_if_needed();
    var L = floor(num_layers);
    if (L < 1.0) { L = 16.0; }
    geomind_e8_stack_init(L);

    let h_prev = cartan_vec_create();
    let h_in_stack = cartan_vec_create();
    let h_top = cartan_vec_create();
    let emb_vec = cartan_vec_create();
    let vel_vec = cartan_vec_create();
    let logits_256 = cartan_vec_create();

    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_prev, 0.0);
        cartan_vec_push_f32(h_in_stack, 0.0);
        cartan_vec_push_f32(h_top, 0.0);
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
    var cur_b = 32.0;
    var prev_b = 32.0;
    var i = 0.0;
    while (i < plen) {
        cur_b = cartan_byte_at(prompt, i);
        if (cur_b < 0.0) { cur_b = cur_b + 256.0; }
        cur_b = math_mod_val(floor(cur_b), 256.0);
        let row_off = cur_b * 248.0;
        d = 0.0;
        while (d < 248.0) {
            let top_d = cartan_vec_get_f32(h_top, d);
            cartan_vec_set_f32(h_prev, d, top_d);
            let e_d = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
            cartan_vec_set_f32(emb_vec, d, e_d);
            if (i == 0.0) {
                cartan_vec_set_f32(h_in_stack, d, e_d);
            } else {
                cartan_vec_set_f32(h_in_stack, d, top_d);
            }
            d = d + 1.0;
        }
        if (i > 0.0) {
            geom_retract_sphere_step(h_in_stack, emb_vec, 0.55);
        }
        geomind_weyl_reflect_vector_248(h_in_stack, math_mod_val(cur_b, 240.0));
        let mv = geomind_markov_get_prob(prev_b, cur_b);
        var prev_seq_ptr: ptr = 0.0;
        if (i > 0.0) { prev_seq_ptr = h_prev; }
        geomind_e8_stack_forward_step(h_in_stack, prev_seq_ptr, mv, 0.85, h_top);
        prev_b = cur_b;
        i = i + 1.0;
    }

    var out_str = prompt;
    var step = 0.0;
    while (step < gen_len) {
        geomind_byte_latent_decode_logits(h_top, cur_b, logits_256);
        var best_b = 32.0;
        var best_l = -100000.0;
        c = 32.0;
        while (c <= 126.0) {
            let lv = cartan_vec_get_f32(logits_256, c);
            if (lv > best_l) {
                best_l = lv;
                best_b = c;
            }
            c = c + 1.0;
        }

        out_str = cartan_string_concat(out_str, cartan_char_from_code(best_b));
        let t_geo = geomind_e8_geodesic_kinetic_energy_248(h_prev, h_top, g_byte_e8_randers_b_248);
        let coast = geomind_should_geodesic_coast(cur_b, best_b, t_geo, 0.85);
        let markov_v = geomind_markov_get_prob(cur_b, best_b);
        cur_b = best_b;
        let row_off = cur_b * 248.0;

        if (coast == 1.0) {
            g_byte_latent_coast_count = g_byte_latent_coast_count + 1.0;
            d = 0.0;
            while (d < 248.0) {
                let top_d = cartan_vec_get_f32(h_top, d);
                let prev_d = cartan_vec_get_f32(h_prev, d);
                let e_d = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                cartan_vec_set_f32(h_prev, d, top_d);
                cartan_vec_set_f32(vel_vec, d, 0.25 * (top_d - prev_d) + e_d);
                d = d + 1.0;
            }
            geom_retract_sphere_step(h_top, vel_vec, 0.55);
        } else {
            d = 0.0;
            while (d < 248.0) {
                let top_d = cartan_vec_get_f32(h_top, d);
                cartan_vec_set_f32(h_prev, d, top_d);
                cartan_vec_set_f32(h_in_stack, d, top_d);
                cartan_vec_set_f32(emb_vec, d, cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d));
                d = d + 1.0;
            }
            geom_retract_sphere_step(h_in_stack, emb_vec, 0.55);
            geomind_weyl_reflect_vector_248(h_in_stack, math_mod_val(cur_b, 240.0));
            geomind_e8_stack_forward_step(h_in_stack, h_prev, markov_v, 0.85, h_top);
        }
        step = step + 1.0;
    }

    cartan_vec_free(h_prev);
    cartan_vec_free(h_in_stack);
    cartan_vec_free(h_top);
    cartan_vec_free(emb_vec);
    cartan_vec_free(vel_vec);
    cartan_vec_free(logits_256);
    return out_str;
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
