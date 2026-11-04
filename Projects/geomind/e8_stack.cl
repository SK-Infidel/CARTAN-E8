// Projects/geomind/e8_stack.cl
// GeoMind v2 Deep Multi-Layer E8 Gauge-Spinor Manifold Stack (Stage 1)
// Implements an L-Layer (default L=16, configurable up to 42) Non-Euclidean E8 Stack on S^{247}:
//   - Per-layer learned so(16) Gauge matrices: W_gauge^{(l)} in R^{120 x 120} (14,400 params/layer)
//   - Per-layer learned S_16^+ Spinor matrices: W_spinor^{(l)} in R^{128 x 128} (16,384 params/layer)
//   - Per-layer learned Finsler-Randers causal drift 1-forms: beta^{(l)} in R^{248}
//   - Per-layer learned Lie Q/K/V attention projections: W_attn^{(l)} in R^{3 x 248}
//   - Per-layer learned 4x4 Freudenthal-Tits Magic Square operators: U_moe^{(l)} in R^{256}
//   - Inter-layer Geodesic Kinetic Energy T_geo^{(l)} and Layer-Skipping Geodesic Coasting

include "geometry.cl";
include "moe.cl";
include "e8_attention_engine.cl";

var g_e8_stack_num_layers: float = 0.0;
var g_e8_stack_w_gauge: ptr = 0.0;     // L * 14,400 floats (120 x 120 per layer)
var g_e8_stack_w_spinor: ptr = 0.0;    // L * 16,384 floats (128 x 128 per layer)
var g_e8_stack_w_attn: ptr = 0.0;      // L * 744 floats   (3 x 248 per layer: Q, K, V Lie scales)
var g_e8_stack_u_moe: ptr = 0.0;       // L * 256 floats   (16 experts x 16 division algebra params)
var g_e8_stack_randers_b: ptr = 0.0;   // L * 248 floats   (Finsler-Randers causal 1-form per layer)

// Forward activation cache for multi-layer analytical backpropagation (single-step / last-step)
var g_e8_stack_act_in: ptr = 0.0;      // (L + 1) * 248 floats: layer input states h^{(l)} on S^{247}
var g_e8_stack_act_attn: ptr = 0.0;    // L * 248 floats: post-Finsler-Randers attention states
var g_e8_stack_act_lin: ptr = 0.0;     // L * 248 floats: post-(W_gauge, W_spinor) linear Lie states
var g_e8_stack_act_gated: ptr = 0.0;   // L * 248 floats: post-Octonion Fano Cross-Gate states
var g_e8_stack_act_vel: ptr = 0.0;     // L * 248 floats: inter-layer Sasaki tangent velocity

var g_e8_stack_last_kinetic_energy: float = 0.0;
var g_e8_stack_layer_coasts: float = 0.0;

// Initialize the L-layer Deep E8 Gauge-Spinor Manifold Stack
fn geomind_e8_stack_init(num_layers: float) {
    var L = floor(num_layers);
    if (L < 1.0) { L = 16.0; }
    if (L > 42.0) { L = 42.0; }
    if (g_e8_stack_num_layers == L && g_e8_stack_w_gauge != 0.0) {
        return;
    }

    g_e8_stack_num_layers = L;
    let gauge_total = L * 14400.0;
    let spinor_total = L * 16384.0;
    let attn_total = L * 744.0;
    let moe_total = L * 256.0;
    let randers_total = L * 248.0;

    g_e8_stack_w_gauge = cartan_tensor_alloc(gauge_total);
    g_e8_stack_w_spinor = cartan_tensor_alloc(spinor_total);
    g_e8_stack_w_attn = cartan_tensor_alloc(attn_total);
    g_e8_stack_u_moe = cartan_tensor_alloc(moe_total);
    g_e8_stack_randers_b = cartan_tensor_alloc(randers_total);

    g_e8_stack_act_in = cartan_tensor_alloc((L + 1.0) * 248.0);
    g_e8_stack_act_attn = cartan_tensor_alloc(L * 248.0);
    g_e8_stack_act_lin = cartan_tensor_alloc(L * 248.0);
    g_e8_stack_act_gated = cartan_tensor_alloc(L * 248.0);
    g_e8_stack_act_vel = cartan_tensor_alloc(L * 248.0);

    var l = 0.0;
    while (l < L) {
        let layer_phase = (l + 1.0) * 0.371;
        // 1. Initialize W_gauge^{(l)} in R^{120 x 120} near SO(120): I_120 + eps * SkewSymmetric
        let g_base = l * 14400.0;
        var r = 0.0;
        while (r < 120.0) {
            var c = 0.0;
            while (c < 120.0) {
                var w_val = 0.0;
                if (r == c) {
                    w_val = 1.0;
                } else {
                    if (c == r + 1.0) {
                        w_val = 0.045 * sin(layer_phase + r * 0.13);
                    } else {
                        if (r == c + 1.0) {
                            w_val = -0.045 * sin(layer_phase + c * 0.13);
                        } else {
                            w_val = 0.004 * sin(layer_phase + (r - c) * 0.29);
                        }
                    }
                }
                cartan_vec_set_f32(g_e8_stack_w_gauge, g_base + r * 120.0 + c, w_val);
                c = c + 1.0;
            }
            r = r + 1.0;
        }

        // 2. Initialize W_spinor^{(l)} in R^{128 x 128} near Spin(16): I_128 + eps * SkewSymmetric
        let s_base = l * 16384.0;
        var sr = 0.0;
        while (sr < 128.0) {
            var sc = 0.0;
            while (sc < 128.0) {
                var sw_val = 0.0;
                if (sr == sc) {
                    sw_val = 1.0;
                } else {
                    if (sc == sr + 1.0) {
                        sw_val = 0.045 * cos(layer_phase + sr * 0.11);
                    } else {
                        if (sr == sc + 1.0) {
                            sw_val = -0.045 * cos(layer_phase + sc * 0.11);
                        } else {
                            sw_val = 0.004 * cos(layer_phase + (sr - sc) * 0.23);
                        }
                    }
                }
                cartan_vec_set_f32(g_e8_stack_w_spinor, s_base + sr * 128.0 + sc, sw_val);
                sc = sc + 1.0;
            }
            sr = sr + 1.0;
        }

        // 3. Initialize W_attn^{(l)} (Q, K, V Lie scaling) and Finsler-Randers beta^{(l)}
        let a_base = l * 744.0;
        let b_base = l * 248.0;
        var d = 0.0;
        while (d < 248.0) {
            let sub_idx = floor(d / 31.0);
            let kw = geom_killing_form_dynkin_weight(sub_idx);
            cartan_vec_set_f32(g_e8_stack_w_attn, a_base + d, 1.0 + 0.05 * sin(layer_phase + d * 0.07) * kw);
            cartan_vec_set_f32(g_e8_stack_w_attn, a_base + 248.0 + d, 1.0 + 0.05 * cos(layer_phase + d * 0.07) * kw);
            cartan_vec_set_f32(g_e8_stack_w_attn, a_base + 496.0 + d, 1.0 + 0.03 * sin(layer_phase + d * 0.13));
            // Bounded causal drift 1-form beta^{(l)}_d
            cartan_vec_set_f32(g_e8_stack_randers_b, b_base + d, 0.025 * sin(layer_phase + d * 0.19));
            d = d + 1.0;
        }

        // 4. Initialize 4x4 Freudenthal-Tits Magic Square U_moe^{(l)} (16 experts x 16 params)
        let m_base = l * 256.0;
        var e_idx = 0.0;
        while (e_idx < 16.0) {
            let e_off = m_base + e_idx * 16.0;
            // Identity-aligned unit division algebra elements (u0=1, v0=1) + small Lie phase
            cartan_vec_set_f32(g_e8_stack_u_moe, e_off + 0.0, 1.0);
            cartan_vec_set_f32(g_e8_stack_u_moe, e_off + 8.0, 1.0);
            var k = 1.0;
            while (k < 8.0) {
                let u_k = 0.06 * sin(layer_phase + e_idx * 0.53 + k * 0.31);
                let v_k = 0.06 * cos(layer_phase + e_idx * 0.47 + k * 0.29);
                cartan_vec_set_f32(g_e8_stack_u_moe, e_off + k, u_k);
                cartan_vec_set_f32(g_e8_stack_u_moe, e_off + 8.0 + k, v_k);
                k = k + 1.0;
            }
            e_idx = e_idx + 1.0;
        }

        l = l + 1.0;
    }
}

// Project a 248-D state onto Q, K, V Lie fibers for layer l
fn geomind_e8_stack_project_qkv_248(h_248: ptr, h_off: float, l: float, q_out: ptr, k_out: ptr, v_out: ptr, out_off: float) {
    let a_base = l * 744.0;
    var d = 0.0;
    while (d < 248.0) {
        let h_d = cartan_vec_get_f32(h_248, h_off + d);
        var h_pair = h_d;
        if (d + 1.0 < 248.0) {
            h_pair = cartan_vec_get_f32(h_248, h_off + d + 1.0);
        } else {
            h_pair = cartan_vec_get_f32(h_248, h_off);
        }
        let wq = cartan_vec_get_f32(g_e8_stack_w_attn, a_base + d);
        let wk = cartan_vec_get_f32(g_e8_stack_w_attn, a_base + 248.0 + d);
        let wv = cartan_vec_get_f32(g_e8_stack_w_attn, a_base + 496.0 + d);

        cartan_vec_set_f32(q_out, out_off + d, h_d * wq + 0.08 * h_pair);
        cartan_vec_set_f32(k_out, out_off + d, h_d * wk - 0.08 * h_pair);
        cartan_vec_set_f32(v_out, out_off + d, h_d * wv);
        d = d + 1.0;
    }
}

// Apply layer l's learned 120x120 so(16) Gauge matrix and 128x128 S_16^+ Spinor matrix to a 248-D state
fn geomind_e8_stack_apply_gauge_spinor_linear_248(h_in: ptr, in_off: float, l: float, h_out: ptr, out_off: float) {
    let g_base = l * 14400.0;
    var r = 0.0;
    while (r < 120.0) {
        let row_off = g_base + r * 120.0;
        var acc = 0.0;
        var c = 0.0;
        while (c < 120.0) {
            acc = acc + cartan_vec_get_f32(g_e8_stack_w_gauge, row_off + c) * cartan_vec_get_f32(h_in, in_off + c);
            c = c + 1.0;
        }
        cartan_vec_set_f32(h_out, out_off + r, acc);
        r = r + 1.0;
    }

    let s_base = l * 16384.0;
    var sr = 0.0;
    while (sr < 128.0) {
        let srow_off = s_base + sr * 128.0;
        var sacc = 0.0;
        var sc = 0.0;
        while (sc < 128.0) {
            sacc = sacc + cartan_vec_get_f32(g_e8_stack_w_spinor, srow_off + sc) * cartan_vec_get_f32(h_in, in_off + 120.0 + sc);
            sc = sc + 1.0;
        }
        cartan_vec_set_f32(h_out, out_off + 120.0 + sr, sacc);
        sr = sr + 1.0;
    }
}

// Evaluate Inter-Layer Killing-Cartan Geodesic Kinetic Energy on 248-D E8 Manifold
fn geomind_e8_stack_kinetic_energy_248(h_curr: ptr, h_prev: ptr) -> float {
    if (h_curr == 0.0 || h_prev == 0.0) { return 0.0; }
    var sum_k = 0.0;
    var d = 0.0;
    while (d < 248.0) {
        let dh = cartan_vec_get_f32(h_curr, d) - cartan_vec_get_f32(h_prev, d);
        let sub_idx = floor(d / 31.0);
        let kw = geom_killing_form_dynkin_weight(sub_idx);
        sum_k = sum_k + 0.5 * kw * dh * dh;
        d = d + 1.0;
    }
    return sum_k;
}

// Accumulate Inter-Layer Geodesic Kinetic Energy Restoring Force into dh_accum
fn geomind_e8_stack_kinetic_grad_248(h_curr: ptr, h_prev: ptr, scale: float, dh_accum: ptr) {
    if (h_curr == 0.0 || h_prev == 0.0 || dh_accum == 0.0) { return; }
    var d = 0.0;
    while (d < 248.0) {
        let dh = cartan_vec_get_f32(h_curr, d) - cartan_vec_get_f32(h_prev, d);
        let sub_idx = floor(d / 31.0);
        let kw = geom_killing_form_dynkin_weight(sub_idx);
        let cur_g = cartan_vec_get_f32(dh_accum, d);
        cartan_vec_set_f32(dh_accum, d, cur_g + scale * kw * dh);
        d = d + 1.0;
    }
}

// ============================================================================
// SINGLE-STEP DEEP L-LAYER E8 STACK FORWARD PASS (WITH ACTIVATION CACHING)
// ============================================================================
// Propagates a single 248-D state h_in_248 through all L layers of:
//   1. Non-Euclidean Finsler-Randers Causal Self-Attention
//   2. Learned 120x120 so(16) Gauge + 128x128 S_16^+ Spinor Transform & Octonion Fano Cross-Gate
//   3. 4x4 Freudenthal-Tits Magic Square Division-Algebra MoE on Sasaki Tangent Bundle
//   4. Inter-Layer Geodesic Kinetic Energy & Layer-Skipping Geodesic Coasting (for l >= L/2)
fn geomind_e8_stack_forward_step(
    h_in_248: ptr,
    h_prev_seq_248: ptr,
    markov_entropy_v: float,
    coast_eps: float,
    h_out_248: ptr
) -> float {
    if (h_in_248 == 0.0 || h_out_248 == 0.0) { return 0.0; }
    if (g_e8_stack_num_layers <= 0.0 || g_e8_stack_w_gauge == 0.0) {
        geomind_e8_stack_init(16.0);
    }
    let L = g_e8_stack_num_layers;

    // Copy h_in_248 into layer 0 input slot of g_e8_stack_act_in
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_set_f32(g_e8_stack_act_in, d, cartan_vec_get_f32(h_in_248, d));
        d = d + 1.0;
    }

    let q_seq = cartan_vec_create();
    let k_seq = cartan_vec_create();
    let v_seq = cartan_vec_create();
    let attn_seq_out = cartan_vec_create();
    let randers_l = cartan_vec_create();
    let u_moe_l = cartan_vec_create();
    let h_cur = cartan_vec_create();
    let h_prev_layer = cartan_vec_create();
    let h_attn = cartan_vec_create();
    let h_lin = cartan_vec_create();
    let h_gated = cartan_vec_create();
    let h_vel = cartan_vec_create();
    let h_moe = cartan_vec_create();

    var idx = 0.0;
    while (idx < 496.0) {
        cartan_vec_push_f32(q_seq, 0.0);
        cartan_vec_push_f32(k_seq, 0.0);
        cartan_vec_push_f32(v_seq, 0.0);
        cartan_vec_push_f32(attn_seq_out, 0.0);
        if (idx < 256.0) {
            cartan_vec_push_f32(u_moe_l, 0.0);
        }
        if (idx < 248.0) {
            cartan_vec_push_f32(randers_l, 0.0);
            cartan_vec_push_f32(h_cur, cartan_vec_get_f32(h_in_248, idx));
            cartan_vec_push_f32(h_prev_layer, cartan_vec_get_f32(h_in_248, idx));
            cartan_vec_push_f32(h_attn, 0.0);
            cartan_vec_push_f32(h_lin, 0.0);
            cartan_vec_push_f32(h_gated, 0.0);
            cartan_vec_push_f32(h_vel, 0.0);
            cartan_vec_push_f32(h_moe, 0.0);
        }
        idx = idx + 1.0;
    }

    var total_kinetic = 0.0;
    var prev_layer_t_geo = 100.0;

    var l = 0.0;
    while (l < L) {
        let l_off = l * 248.0;
        // Check Layer-Skipping Geodesic Coasting condition on upper manifold layers (l >= L/2)
        let norm_prev_t = prev_layer_t_geo / 248.0;
        if (l >= floor(L * 0.5) && markov_entropy_v >= 0.25 && norm_prev_t <= coast_eps && coast_eps > 0.0) {
            // Geodesic coast along previous layer's Sasaki tangent velocity on S^{247}
            geom_retract_sphere_step(h_cur, h_vel, 0.15);
            g_e8_stack_layer_coasts = g_e8_stack_layer_coasts + 1.0;
            var cd = 0.0;
            while (cd < 248.0) {
                let c_val = cartan_vec_get_f32(h_cur, cd);
                cartan_vec_set_f32(g_e8_stack_act_attn, l_off + cd, c_val);
                cartan_vec_set_f32(g_e8_stack_act_lin, l_off + cd, c_val);
                cartan_vec_set_f32(g_e8_stack_act_gated, l_off + cd, c_val);
                cartan_vec_set_f32(g_e8_stack_act_vel, l_off + cd, cartan_vec_get_f32(h_vel, cd));
                cartan_vec_set_f32(g_e8_stack_act_in, (l + 1.0) * 248.0 + cd, c_val);
                cd = cd + 1.0;
            }
            let t_coast = geomind_e8_stack_kinetic_energy_248(h_cur, h_prev_layer);
            total_kinetic = total_kinetic + t_coast;
            prev_layer_t_geo = t_coast;
            cd = 0.0;
            while (cd < 248.0) {
                cartan_vec_set_f32(h_prev_layer, cd, cartan_vec_get_f32(h_cur, cd));
                cd = cd + 1.0;
            }
            l = l + 1.0;
        } else {
            // 1. Non-Euclidean Asymmetric Finsler-Randers Causal Attention (2-step causal context)
            var b_idx = 0.0;
            while (b_idx < 248.0) {
                cartan_vec_set_f32(randers_l, b_idx, cartan_vec_get_f32(g_e8_stack_randers_b, l_off + b_idx));
                b_idx = b_idx + 1.0;
            }
            if (h_prev_seq_248 != 0.0) {
                geomind_e8_stack_project_qkv_248(h_prev_seq_248, 0.0, l, q_seq, k_seq, v_seq, 0.0);
                geomind_e8_stack_project_qkv_248(h_cur, 0.0, l, q_seq, k_seq, v_seq, 248.0);
                e8_finsler_randers_causal_attention_forward_248(q_seq, k_seq, v_seq, 2.0, randers_l, attn_seq_out, 0.22);
                var ad = 0.0;
                while (ad < 248.0) {
                    let a_val = cartan_vec_get_f32(attn_seq_out, 248.0 + ad);
                    cartan_vec_set_f32(h_attn, ad, a_val);
                    cartan_vec_set_f32(g_e8_stack_act_attn, l_off + ad, a_val);
                    ad = ad + 1.0;
                }
            } else {
                geomind_e8_stack_project_qkv_248(h_cur, 0.0, l, q_seq, k_seq, v_seq, 0.0);
                e8_finsler_randers_causal_attention_forward_248(q_seq, k_seq, v_seq, 1.0, randers_l, attn_seq_out, 0.22);
                var ad = 0.0;
                while (ad < 248.0) {
                    let a_val = cartan_vec_get_f32(attn_seq_out, ad);
                    cartan_vec_set_f32(h_attn, ad, a_val);
                    cartan_vec_set_f32(g_e8_stack_act_attn, l_off + ad, a_val);
                    ad = ad + 1.0;
                }
            }

            // 2. Learned 120x120 so(16) Gauge & 128x128 S_16^+ Spinor Linear Lie Transform
            geomind_e8_stack_apply_gauge_spinor_linear_248(h_attn, 0.0, l, h_lin, 0.0);
            var ld = 0.0;
            while (ld < 248.0) {
                let lv = cartan_vec_get_f32(h_lin, ld);
                cartan_vec_set_f32(g_e8_stack_act_lin, l_off + ld, lv);
                ld = ld + 1.0;
            }

            // Apply Octonion Fano Cross-Gate on S^{247}
            geomind_e8_gauge_spinor_cross_gate_block248(h_lin, 0.0, h_gated, 0.0, 0.25);
            ld = 0.0;
            while (ld < 248.0) {
                cartan_vec_set_f32(g_e8_stack_act_gated, l_off + ld, cartan_vec_get_f32(h_gated, ld));
                ld = ld + 1.0;
            }

            // 3. Compute Riemannian Tangent Velocity in T_{h_prev} S^{247} and Route 4x4 Freudenthal MoE
            var prev_norm_sq = 0.0;
            var prev_dot_gated = 0.0;
            ld = 0.0;
            while (ld < 248.0) {
                let p_k = cartan_vec_get_f32(h_prev_layer, ld);
                let g_k = cartan_vec_get_f32(h_gated, ld);
                prev_norm_sq = prev_norm_sq + p_k * p_k;
                prev_dot_gated = prev_dot_gated + p_k * g_k;
                ld = ld + 1.0;
            }
            if (prev_norm_sq < 0.000001) { prev_norm_sq = 1.0; }
            let proj_coeff = prev_dot_gated / prev_norm_sq;
            ld = 0.0;
            while (ld < 248.0) {
                let p_k = cartan_vec_get_f32(h_prev_layer, ld);
                let g_k = cartan_vec_get_f32(h_gated, ld);
                let v_tan = g_k - proj_coeff * p_k;
                cartan_vec_set_f32(h_vel, ld, v_tan);
                cartan_vec_set_f32(g_e8_stack_act_vel, l_off + ld, v_tan);
                ld = ld + 1.0;
            }

            let m_base = l * 256.0;
            var mi = 0.0;
            while (mi < 256.0) {
                cartan_vec_set_f32(u_moe_l, mi, cartan_vec_get_f32(g_e8_stack_u_moe, m_base + mi));
                mi = mi + 1.0;
            }
            geomind_freudenthal_moe_forward_248(h_gated, h_vel, randers_l, u_moe_l, h_moe, 0.25);

            // 4. Accumulate Inter-Layer Geodesic Kinetic Energy T_geo^{(l)}
            let t_layer = geomind_e8_stack_kinetic_energy_248(h_moe, h_prev_layer);
            total_kinetic = total_kinetic + t_layer;
            prev_layer_t_geo = t_layer;

            ld = 0.0;
            while (ld < 248.0) {
                let m_val = cartan_vec_get_f32(h_moe, ld);
                cartan_vec_set_f32(h_cur, ld, m_val);
                cartan_vec_set_f32(h_prev_layer, ld, m_val);
                cartan_vec_set_f32(g_e8_stack_act_in, (l + 1.0) * 248.0 + ld, m_val);
                ld = ld + 1.0;
            }

            l = l + 1.0;
        }
    }

    d = 0.0;
    while (d < 248.0) {
        cartan_vec_set_f32(h_out_248, d, cartan_vec_get_f32(h_cur, d));
        d = d + 1.0;
    }

    cartan_vec_free(q_seq);
    cartan_vec_free(k_seq);
    cartan_vec_free(v_seq);
    cartan_vec_free(attn_seq_out);
    cartan_vec_free(randers_l);
    cartan_vec_free(u_moe_l);
    cartan_vec_free(h_cur);
    cartan_vec_free(h_prev_layer);
    cartan_vec_free(h_attn);
    cartan_vec_free(h_lin);
    cartan_vec_free(h_gated);
    cartan_vec_free(h_vel);
    cartan_vec_free(h_moe);

    g_e8_stack_last_kinetic_energy = total_kinetic / L;
    return g_e8_stack_last_kinetic_energy;
}

// ============================================================================
// MULTI-LAYER ANALYTICAL BACKWARD PASS THROUGH ALL L E8 MANIFOLD LAYERS
// ============================================================================
// Backpropagates dh_top_248 from layer L-1 down to layer 0:
//   - Pulls back through 4x4 Freudenthal-Tits Magic Square Division-Algebra MoE & updates U_moe^{(l)}
//   - Adds inter-layer Geodesic Kinetic Energy restoring force dT_geo^{(l)} / dh^{(l)}
//   - Pulls back through Octonion Fano Cross-Gate adjoint (geomind_e8_gauge_spinor_cross_gate_backward_block248)
//   - Pulls back through and updates W_gauge^{(l)} (120x120) and W_spinor^{(l)} (128x128)
//   - Pulls back through Finsler-Randers Causal Attention & updates beta^{(l)} and W_attn^{(l)}
//   - Writes input gradient into dh_in_248
fn geomind_e8_stack_backward_step(
    dh_top_248: ptr,
    lr: float,
    lambda_kin: float,
    dh_in_248: ptr
) {
    if (dh_top_248 == 0.0 || g_e8_stack_num_layers <= 0.0 || g_e8_stack_w_gauge == 0.0) {
        return;
    }
    let L = g_e8_stack_num_layers;

    let dh_cur = cartan_vec_create();
    let dh_gated = cartan_vec_create();
    let dh_lin = cartan_vec_create();
    let dh_attn = cartan_vec_create();
    let h_in_l = cartan_vec_create();
    let h_attn_l = cartan_vec_create();
    let h_lin_l = cartan_vec_create();
    let h_gated_l = cartan_vec_create();
    let h_vel_l = cartan_vec_create();
    let h_out_l = cartan_vec_create();
    let u_moe_l = cartan_vec_create();
    let du_moe_l = cartan_vec_create();
    let randers_l = cartan_vec_create();
    let dranders_l = cartan_vec_create();
    let q_l = cartan_vec_create();
    let k_l = cartan_vec_create();
    let v_l = cartan_vec_create();
    let dq_l = cartan_vec_create();
    let dk_l = cartan_vec_create();
    let dv_l = cartan_vec_create();

    var idx = 0.0;
    while (idx < 256.0) {
        cartan_vec_push_f32(u_moe_l, 0.0);
        cartan_vec_push_f32(du_moe_l, 0.0);
        if (idx < 248.0) {
            cartan_vec_push_f32(dh_cur, cartan_vec_get_f32(dh_top_248, idx));
            cartan_vec_push_f32(dh_gated, 0.0);
            cartan_vec_push_f32(dh_lin, 0.0);
            cartan_vec_push_f32(dh_attn, 0.0);
            cartan_vec_push_f32(h_in_l, 0.0);
            cartan_vec_push_f32(h_attn_l, 0.0);
            cartan_vec_push_f32(h_lin_l, 0.0);
            cartan_vec_push_f32(h_gated_l, 0.0);
            cartan_vec_push_f32(h_vel_l, 0.0);
            cartan_vec_push_f32(h_out_l, 0.0);
            cartan_vec_push_f32(randers_l, 0.0);
            cartan_vec_push_f32(dranders_l, 0.0);
            cartan_vec_push_f32(q_l, 0.0);
            cartan_vec_push_f32(k_l, 0.0);
            cartan_vec_push_f32(v_l, 0.0);
            cartan_vec_push_f32(dq_l, 0.0);
            cartan_vec_push_f32(dk_l, 0.0);
            cartan_vec_push_f32(dv_l, 0.0);
        }
        idx = idx + 1.0;
    }

    // Scale per-layer learning rate gently with depth to preserve SO(120)/Spin(16) manifold stability
    let layer_lr = lr / sqrt(L);

    var l = L - 1.0;
    while (l >= 0.0) {
        let l_off = l * 248.0;
        var d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_in_l, d, cartan_vec_get_f32(g_e8_stack_act_in, l_off + d));
            cartan_vec_set_f32(h_out_l, d, cartan_vec_get_f32(g_e8_stack_act_in, (l + 1.0) * 248.0 + d));
            cartan_vec_set_f32(h_attn_l, d, cartan_vec_get_f32(g_e8_stack_act_attn, l_off + d));
            cartan_vec_set_f32(h_lin_l, d, cartan_vec_get_f32(g_e8_stack_act_lin, l_off + d));
            cartan_vec_set_f32(h_gated_l, d, cartan_vec_get_f32(g_e8_stack_act_gated, l_off + d));
            cartan_vec_set_f32(h_vel_l, d, cartan_vec_get_f32(g_e8_stack_act_vel, l_off + d));
            cartan_vec_set_f32(randers_l, d, cartan_vec_get_f32(g_e8_stack_randers_b, l_off + d));
            cartan_vec_set_f32(dranders_l, d, 0.0);
            cartan_vec_set_f32(dq_l, d, 0.0);
            cartan_vec_set_f32(dk_l, d, 0.0);
            cartan_vec_set_f32(dv_l, d, 0.0);
            d = d + 1.0;
        }

        // 1. Add Inter-Layer Geodesic Kinetic Energy Restoring Force: dT_geo^{(l)} / dh^{(l)}
        if (lambda_kin > 0.0) {
            geomind_e8_stack_kinetic_grad_248(h_out_l, h_in_l, lambda_kin / L, dh_cur);
        }

        // 2. Backward through 4x4 Freudenthal-Tits Magic Square Division-Algebra MoE
        let m_base = l * 256.0;
        var mi = 0.0;
        while (mi < 256.0) {
            cartan_vec_set_f32(u_moe_l, mi, cartan_vec_get_f32(g_e8_stack_u_moe, m_base + mi));
            mi = mi + 1.0;
        }
        geomind_freudenthal_moe_backward_248(h_gated_l, h_vel_l, randers_l, u_moe_l, dh_cur, dh_gated, 0.25, layer_lr);
        mi = 0.0;
        while (mi < 256.0) {
            cartan_vec_set_f32(g_e8_stack_u_moe, m_base + mi, cartan_vec_get_f32(u_moe_l, mi));
            mi = mi + 1.0;
        }

        // 3. Backward through Octonion Fano Cross-Gate (120 gauge (x) 128 spinor)
        geomind_e8_gauge_spinor_cross_gate_backward_block248(h_lin_l, 0.0, dh_gated, 0.0, dh_lin, 0.0, 0.25);

        // 4. Backward through W_gauge^{(l)} (120x120) and W_spinor^{(l)} (128x128)
        let g_base = l * 14400.0;
        var c = 0.0;
        while (c < 120.0) {
            cartan_vec_set_f32(dh_attn, c, 0.0);
            c = c + 1.0;
        }
        var r = 0.0;
        while (r < 120.0) {
            let d_lin_r = cartan_vec_get_f32(dh_lin, r);
            let sub_idx = floor(r / 31.0);
            var kw_inv = 1.0 / geom_killing_form_dynkin_weight(sub_idx);
            let row_off = g_base + r * 120.0;
            c = 0.0;
            while (c < 120.0) {
                let w_rc = cartan_vec_get_f32(g_e8_stack_w_gauge, row_off + c);
                let h_attn_c = cartan_vec_get_f32(h_attn_l, c);
                // Pullback dh_attn_c += w_{r,c} * d_lin_r
                cartan_vec_set_f32(dh_attn, c, cartan_vec_get_f32(dh_attn, c) + w_rc * d_lin_r);
                // Riemannian Killing-preconditioned gradient update on W_gauge^{(l)}
                let w_new = w_rc - (layer_lr * kw_inv) * (d_lin_r * h_attn_c);
                cartan_vec_set_f32(g_e8_stack_w_gauge, row_off + c, w_new);
                c = c + 1.0;
            }
            r = r + 1.0;
        }

        let s_base = l * 16384.0;
        var sc = 0.0;
        while (sc < 128.0) {
            cartan_vec_set_f32(dh_attn, 120.0 + sc, 0.0);
            sc = sc + 1.0;
        }
        var sr = 0.0;
        while (sr < 128.0) {
            let d_lin_sr = cartan_vec_get_f32(dh_lin, 120.0 + sr);
            let s_sub_idx = floor((120.0 + sr) / 31.0);
            var skw_inv = 1.0 / geom_killing_form_dynkin_weight(s_sub_idx);
            let srow_off = s_base + sr * 128.0;
            sc = 0.0;
            while (sc < 128.0) {
                let sw_rc = cartan_vec_get_f32(g_e8_stack_w_spinor, srow_off + sc);
                let h_attn_sc = cartan_vec_get_f32(h_attn_l, 120.0 + sc);
                cartan_vec_set_f32(dh_attn, 120.0 + sc, cartan_vec_get_f32(dh_attn, 120.0 + sc) + sw_rc * d_lin_sr);
                let sw_new = sw_rc - (layer_lr * skw_inv) * (d_lin_sr * h_attn_sc);
                cartan_vec_set_f32(g_e8_stack_w_spinor, srow_off + sc, sw_new);
                sc = sc + 1.0;
            }
            sr = sr + 1.0;
        }

        // 5. Backward through Non-Euclidean Finsler-Randers Causal Attention & Q/K/V projections
        geomind_e8_stack_project_qkv_248(h_in_l, 0.0, l, q_l, k_l, v_l, 0.0);
        e8_finsler_randers_causal_attention_backward_248(
            q_l, k_l, v_l, dh_attn, 1.0, randers_l, 0.22,
            dq_l, dk_l, dv_l, dranders_l
        );

        let a_base = l * 744.0;
        d = 0.0;
        while (d < 248.0) {
            let h_d = cartan_vec_get_f32(h_in_l, d);
            let dq_d = cartan_vec_get_f32(dq_l, d);
            let dk_d = cartan_vec_get_f32(dk_l, d);
            let dv_d = cartan_vec_get_f32(dv_l, d);

            let wq = cartan_vec_get_f32(g_e8_stack_w_attn, a_base + d);
            let wk = cartan_vec_get_f32(g_e8_stack_w_attn, a_base + 248.0 + d);
            let wv = cartan_vec_get_f32(g_e8_stack_w_attn, a_base + 496.0 + d);

            cartan_vec_set_f32(g_e8_stack_w_attn, a_base + d, wq - layer_lr * dq_d * h_d);
            cartan_vec_set_f32(g_e8_stack_w_attn, a_base + 248.0 + d, wk - layer_lr * dk_d * h_d);
            cartan_vec_set_f32(g_e8_stack_w_attn, a_base + 496.0 + d, wv - layer_lr * dv_d * h_d);

            // Update Finsler-Randers causal drift 1-form beta^{(l)}
            let cur_b = cartan_vec_get_f32(g_e8_stack_randers_b, l_off + d);
            let db_d = cartan_vec_get_f32(dranders_l, d);
            var new_b = cur_b - layer_lr * db_d;
            if (new_b > 0.25) { new_b = 0.25; }
            if (new_b < -0.25) { new_b = -0.25; }
            cartan_vec_set_f32(g_e8_stack_randers_b, l_off + d, new_b);

            // Propagate gradient to layer input dh_cur for layer l-1
            let dh_in_d = dq_d * wq + dk_d * wk + dv_d * wv;
            cartan_vec_set_f32(dh_cur, d, dh_in_d);
            d = d + 1.0;
        }

        // Normalize layer gradient norm if needed to prevent deep cascade explosion
        var grad_norm_sq = 0.0;
        d = 0.0;
        while (d < 248.0) {
            let gv = cartan_vec_get_f32(dh_cur, d);
            grad_norm_sq = grad_norm_sq + gv * gv;
            d = d + 1.0;
        }
        let grad_norm = sqrt(grad_norm_sq);
        if (grad_norm > 5.0) {
            let g_scale = 5.0 / grad_norm;
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(dh_cur, d, cartan_vec_get_f32(dh_cur, d) * g_scale);
                d = d + 1.0;
            }
        }

        l = l - 1.0;
    }

    if (dh_in_248 != 0.0) {
        var d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(dh_in_248, d, cartan_vec_get_f32(dh_cur, d));
            d = d + 1.0;
        }
    }

    cartan_vec_free(dh_cur);
    cartan_vec_free(dh_gated);
    cartan_vec_free(dh_lin);
    cartan_vec_free(dh_attn);
    cartan_vec_free(h_in_l);
    cartan_vec_free(h_attn_l);
    cartan_vec_free(h_lin_l);
    cartan_vec_free(h_gated_l);
    cartan_vec_free(h_vel_l);
    cartan_vec_free(h_out_l);
    cartan_vec_free(u_moe_l);
    cartan_vec_free(du_moe_l);
    cartan_vec_free(randers_l);
    cartan_vec_free(dranders_l);
    cartan_vec_free(q_l);
    cartan_vec_free(k_l);
    cartan_vec_free(v_l);
    cartan_vec_free(dq_l);
    cartan_vec_free(dk_l);
    cartan_vec_free(dv_l);
}

// ============================================================================
// SEQUENCE-LEVEL DEEP L-LAYER E8 STACK FORWARD PASS
// ============================================================================
// Evaluates the full L-layer Deep E8 Stack across a sequence of `seq_len` 248-D patches.
fn geomind_e8_stack_forward_seq(
    seq_in_flat: ptr,
    seq_len: float,
    coast_eps: float,
    seq_out_flat: ptr
) -> float {
    if (seq_in_flat == 0.0 || seq_out_flat == 0.0 || seq_len <= 0.0) { return 0.0; }
    if (g_e8_stack_num_layers <= 0.0 || g_e8_stack_w_gauge == 0.0) {
        geomind_e8_stack_init(16.0);
    }
    let h_in = cartan_vec_create();
    let h_prev = cartan_vec_create();
    let h_out = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_in, 0.0);
        cartan_vec_push_f32(h_prev, 0.0);
        cartan_vec_push_f32(h_out, 0.0);
        d = d + 1.0;
    }

    var sum_kin = 0.0;
    var t = 0.0;
    while (t < seq_len) {
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_in, d, cartan_vec_get_f32(seq_in_flat, t * 248.0 + d));
            d = d + 1.0;
        }
        var prev_ptr: ptr = 0.0;
        if (t > 0.0) { prev_ptr = h_prev; }
        let kin_t = geomind_e8_stack_forward_step(h_in, prev_ptr, 0.35, coast_eps, h_out);
        sum_kin = sum_kin + kin_t;
        d = 0.0;
        while (d < 248.0) {
            let out_d = cartan_vec_get_f32(h_out, d);
            cartan_vec_set_f32(seq_out_flat, t * 248.0 + d, out_d);
            cartan_vec_set_f32(h_prev, d, out_d);
            d = d + 1.0;
        }
        t = t + 1.0;
    }

    cartan_vec_free(h_in);
    cartan_vec_free(h_prev);
    cartan_vec_free(h_out);
    return sum_kin / seq_len;
}

// ============================================================================
// DEEP E8 STACK CHECKPOINT PERSISTENCE (SAVE / LOAD)
// ============================================================================
// Binary layout:
//   [0]: Magic header 14824816.0 ("E8_248_16")
//   [1]: L (number of layers)
//   [2]: g_e8_stack_layer_coasts
//   [3 .. +L*14400]: g_e8_stack_w_gauge
//   [.. +L*16384]:   g_e8_stack_w_spinor
//   [.. +L*744]:     g_e8_stack_w_attn
//   [.. +L*256]:     g_e8_stack_u_moe
//   [.. +L*248]:     g_e8_stack_randers_b
fn geomind_e8_stack_save(path: string) -> float {
    if (path == 0.0 || g_e8_stack_num_layers <= 0.0 || g_e8_stack_w_gauge == 0.0) { return 0.0; }
    let L = g_e8_stack_num_layers;
    let gauge_len = L * 14400.0;
    let spinor_len = L * 16384.0;
    let attn_len = L * 744.0;
    let moe_len = L * 256.0;
    let randers_len = L * 248.0;
    let total_floats = 3.0 + gauge_len + spinor_len + attn_len + moe_len + randers_len;

    let f = fopen(path, "wb");
    if (f == 0.0) { return 0.0; }
    let buf = malloc(total_floats * 8.0);
    if (buf == 0.0) { fclose(f); return 0.0; }

    buf[0.0] = 14824816.0;
    buf[1.0] = L;
    buf[2.0] = g_e8_stack_layer_coasts;

    var off = 3.0;
    var i = 0.0;
    while (i < gauge_len) {
        buf[off + i] = cartan_vec_get_f32(g_e8_stack_w_gauge, i);
        i = i + 1.0;
    }
    off = off + gauge_len;
    i = 0.0;
    while (i < spinor_len) {
        buf[off + i] = cartan_vec_get_f32(g_e8_stack_w_spinor, i);
        i = i + 1.0;
    }
    off = off + spinor_len;
    i = 0.0;
    while (i < attn_len) {
        buf[off + i] = cartan_vec_get_f32(g_e8_stack_w_attn, i);
        i = i + 1.0;
    }
    off = off + attn_len;
    i = 0.0;
    while (i < moe_len) {
        buf[off + i] = cartan_vec_get_f32(g_e8_stack_u_moe, i);
        i = i + 1.0;
    }
    off = off + moe_len;
    i = 0.0;
    while (i < randers_len) {
        buf[off + i] = cartan_vec_get_f32(g_e8_stack_randers_b, i);
        i = i + 1.0;
    }

    fwrite(buf, 8.0, total_floats, f);
    fclose(f);
    free(buf);
    return 1.0;
}

fn geomind_e8_stack_load(path: string) -> float {
    if (path == 0.0 || cartan_file_exists(path) == 0.0) { return 0.0; }
    let f_sz = cartan_get_binary_file_size(path);
    if (f_sz < 32035.0 * 8.0) { return 0.0; }

    let f = fopen(path, "rb");
    if (f == 0.0) { return 0.0; }
    let header = malloc(3.0 * 8.0);
    if (header == 0.0) { fclose(f); return 0.0; }
    fread(header, 8.0, 3.0, f);
    let magic = header[0.0];
    let L = floor(header[1.0]);
    let saved_coasts = header[2.0];
    free(header);

    if (math_abs_val(magic - 14824816.0) > 1.0 || L < 1.0 || L > 42.0) {
        fclose(f);
        return 0.0;
    }

    let gauge_len = L * 14400.0;
    let spinor_len = L * 16384.0;
    let attn_len = L * 744.0;
    let moe_len = L * 256.0;
    let randers_len = L * 248.0;
    let payload_floats = gauge_len + spinor_len + attn_len + moe_len + randers_len;
    if (f_sz < (3.0 + payload_floats) * 8.0) {
        fclose(f);
        return 0.0;
    }

    let buf = malloc(payload_floats * 8.0);
    if (buf == 0.0) { fclose(f); return 0.0; }
    fread(buf, 8.0, payload_floats, f);
    fclose(f);

    geomind_e8_stack_init(L);
    g_e8_stack_layer_coasts = saved_coasts;

    var off = 0.0;
    var i = 0.0;
    while (i < gauge_len) {
        cartan_vec_set_f32(g_e8_stack_w_gauge, i, buf[off + i]);
        i = i + 1.0;
    }
    off = off + gauge_len;
    i = 0.0;
    while (i < spinor_len) {
        cartan_vec_set_f32(g_e8_stack_w_spinor, i, buf[off + i]);
        i = i + 1.0;
    }
    off = off + spinor_len;
    i = 0.0;
    while (i < attn_len) {
        cartan_vec_set_f32(g_e8_stack_w_attn, i, buf[off + i]);
        i = i + 1.0;
    }
    off = off + attn_len;
    i = 0.0;
    while (i < moe_len) {
        cartan_vec_set_f32(g_e8_stack_u_moe, i, buf[off + i]);
        i = i + 1.0;
    }
    off = off + moe_len;
    i = 0.0;
    while (i < randers_len) {
        cartan_vec_set_f32(g_e8_stack_randers_b, i, buf[off + i]);
        i = i + 1.0;
    }

    free(buf);
    return 1.0;
}
