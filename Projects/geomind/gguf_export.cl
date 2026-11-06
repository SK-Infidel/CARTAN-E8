// Projects/geomind/gguf_export.cl
// Spec-Compliant GGUF v3 Open-Weights Exporter & HTML/SVG Manifold Relaxation Visualizer

include "src/std/geom.cl";
include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/fs.cl";
include "Projects/geomind/geometry.cl";

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

