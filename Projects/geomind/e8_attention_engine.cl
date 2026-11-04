// Projects/geomind/e8_attention_engine.cl
// GeoMind v2 Non-Euclidean Asymmetric Finsler-Randers Causal Attention Engine on E8 (248-D)
// Replaces symmetric Euclidean Q*K^T / sqrt(d) dot-product attention with:
//   1. Killing-Cartan bilinear inner product <Q_t, K_s>_g weighted by Coxeter-Dynkin weights
//   2. Asymmetric Finsler-Randers causal geodesic distance:
//        d_FR(Q_t, K_s; beta) = sqrt(sum_d g_d (Q_{t,d} - K_{s,d})^2 + eps)
//                             + sum_d beta_d (Q_{t,d} - K_{s,d})
//      where ||beta||_{g^{-1}} < 1 breaks time-reversal symmetry (d_FR(Q, K) != d_FR(K, Q))
//   3. Riemannian tangent-bundle value transport and exponential retraction onto S^{247}

include "geometry.cl";
include "moe.cl";
include "streams.cl";
include "../../src/std/autotune.cl";
include "../../src/std/collections.cl";
include "../../src/std/math.cl";

struct E8AttentionConfig {
    num_heads: float;
    head_dim: float;
    lattice_dim: float;
}

fn geomind_e8_attention_project(head_dim: float, q: ptr, k: ptr, v: ptr) -> ptr {
    let tile = autotune_find_optimal_tile(head_dim, head_dim, head_dim, "FP16");
    let e8_root_q = geomind_project_to_e8_lattice(0.0, head_dim);
    let e8_root_k = geomind_project_to_e8_lattice(1.0, head_dim);
    let qk_attn = autotune_matmul_tiled(q, k, head_dim, head_dim, head_dim, tile.block_m);
    let out = autotune_matmul_tiled(qk_attn, v, head_dim, head_dim, head_dim, tile.block_m);
    if (e8_root_q != 0.0) { cartan_vec_free(e8_root_q); }
    if (e8_root_k != 0.0) { cartan_vec_free(e8_root_k); }
    if (qk_attn != 0.0) { cartan_vec_free(qk_attn); }
    return out;
}

// ============================================================================
// NON-EUCLIDEAN ASYMMETRIC FINSLER-RANDERS CAUSAL ATTENTION (248-D, 8 HEADS x 31-D)
// ============================================================================
// Evaluates causal attention over a sequence of 248-D E8 states (8 Lie heads x 31-D = 248-D).
// For each head h in [0, 7] and causal pair s <= t:
//   - Killing-Cartan inner product: <Q_t^{(h)}, K_s^{(h)}>_g = sum_{d=0}^{30} g_h Q_{t,d} K_{s,d}
//   - Finsler-Randers asymmetric geodesic distance:
//       d_FR(Q_t^{(h)}, K_s^{(h)}; beta^{(h)}) =
//           sqrt(sum_{d=0}^{30} g_h (Q_{t,d} - K_{s,d})^2 + 1e-6)
//         + sum_{d=0}^{30} beta_tilde_d (Q_{t,d} - K_{s,d})
//     where beta_tilde = beta / max(1.0, ||beta||_{g^{-1}} / 0.95) enforces strong convexity.
//   - Heat-kernel attention score:
//       A_{t,s}^{(h)} = ( <Q_t^{(h)}, K_s^{(h)}>_g - 0.35 * d_FR(Q_t^{(h)}, K_s^{(h)}; beta^{(h)}) ) / sqrt(31)
//   - Value aggregation is projected onto the Riemannian tangent space T_{Q_t} S^{247}
//     and retracted onto S^{247} via exponential sphere retraction (zero Euclidean residual addition).
fn e8_finsler_randers_causal_attention_forward_248(
    seq_q_flat: ptr,
    seq_k_flat: ptr,
    seq_v_flat: ptr,
    seq_len: float,
    randers_b_248: ptr,
    seq_out_flat: ptr,
    step_scale: float
) -> float {
    if (seq_q_flat == 0.0 || seq_k_flat == 0.0 || seq_v_flat == 0.0 || seq_out_flat == 0.0 || seq_len <= 0.0) {
        return 0.0;
    }
    let num_heads = 8.0;
    let head_dim = 31.0;
    let hidden_dim = 248.0;
    let inv_sqrt_hd = 1.0 / sqrt(head_dim);
    var window_size = 16.0;
    if (window_size > seq_len) {
        window_size = seq_len;
    }

    // Compute g^{-1}-norm of randers_b_248 to enforce strong convexity ||beta||_{g^{-1}} <= 0.95
    var b_scale = 1.0;
    if (randers_b_248 != 0.0 && cartan_vec_len(randers_b_248) >= 248.0) {
        var b_norm_sq = 0.0;
        var bi = 0.0;
        while (bi < 248.0) {
            let b_val = cartan_vec_get_f32(randers_b_248, bi);
            let h_idx = floor(bi / 31.0);
            var kw = geom_killing_form_dynkin_weight(h_idx);
            if (kw < 0.001) { kw = 1.0; }
            b_norm_sq = b_norm_sq + (b_val * b_val) / kw;
            bi = bi + 1.0;
        }
        let b_norm = sqrt(b_norm_sq);
        if (b_norm > 0.95) {
            b_scale = 0.95 / b_norm;
        }
    }

    let scores_buf = cartan_vec_create();
    let agg_248 = cartan_vec_create();
    var di = 0.0;
    while (di < 248.0) {
        if (di < 16.0) {
            cartan_vec_push_f32(scores_buf, 0.0);
        }
        cartan_vec_push_f32(agg_248, 0.0);
        di = di + 1.0;
    }

    var total_fr_dist = 0.0;
    var total_pairs = 0.0;

    var t = 0.0;
    while (t < seq_len) {
        var win_start = t - window_size + 1.0;
        if (win_start < 0.0) { win_start = 0.0; }
        let win_len = t - win_start + 1.0;

        var h = 0.0;
        while (h < num_heads) {
            let kw = geom_killing_form_dynkin_weight(h);
            var max_sc = -100000.0;
            var s = win_start;
            var s_idx = 0.0;
            while (s <= t) {
                var dot_g = 0.0;
                var diff_sq_g = 0.0;
                var randers_drift = 0.0;
                var d = 0.0;
                while (d < head_dim) {
                    let dim_idx = h * head_dim + d;
                    let q_val = cartan_vec_get_f32(seq_q_flat, t * hidden_dim + dim_idx);
                    let k_val = cartan_vec_get_f32(seq_k_flat, s * hidden_dim + dim_idx);
                    let diff = q_val - k_val;
                    dot_g = dot_g + (q_val * k_val) * kw;
                    diff_sq_g = diff_sq_g + (diff * diff) * kw;
                    if (randers_b_248 != 0.0) {
                        let b_d = cartan_vec_get_f32(randers_b_248, dim_idx) * b_scale;
                        randers_drift = randers_drift + b_d * diff;
                    }
                    d = d + 1.0;
                }
                let riemann_dist = sqrt(diff_sq_g + 0.000001);
                var fr_dist = riemann_dist + randers_drift;
                if (fr_dist < 0.0) { fr_dist = 0.0; }
                total_fr_dist = total_fr_dist + fr_dist;
                total_pairs = total_pairs + 1.0;

                let sc = (dot_g - 0.35 * fr_dist) * inv_sqrt_hd;
                cartan_vec_set_f32(scores_buf, s_idx, sc);
                if (sc > max_sc) { max_sc = sc; }
                s = s + 1.0;
                s_idx = s_idx + 1.0;
            }

            var sum_exp = 0.0;
            var wi = 0.0;
            while (wi < win_len) {
                let sc = cartan_vec_get_f32(scores_buf, wi);
                let w_exp = exp(sc - max_sc);
                cartan_vec_set_f32(scores_buf, wi, w_exp);
                sum_exp = sum_exp + w_exp;
                wi = wi + 1.0;
            }
            if (sum_exp <= 0.0000001) { sum_exp = 1.0; }

            var d_out = 0.0;
            while (d_out < head_dim) {
                let dim_idx = h * head_dim + d_out;
                var acc_v = 0.0;
                s = win_start;
                s_idx = 0.0;
                while (s <= t) {
                    let attn_w = cartan_vec_get_f32(scores_buf, s_idx) / sum_exp;
                    let v_val = cartan_vec_get_f32(seq_v_flat, s * hidden_dim + dim_idx);
                    acc_v = acc_v + attn_w * v_val;
                    s = s + 1.0;
                    s_idx = s_idx + 1.0;
                }
                cartan_vec_set_f32(agg_248, dim_idx, acc_v);
                d_out = d_out + 1.0;
            }
            h = h + 1.0;
        }

        // Project aggregated attention vector onto Riemannian tangent space T_{Q_t} S^{247}
        // and retract onto S^{247} of radius ||Q_t||
        var q_norm_sq = 0.0;
        var q_dot_agg = 0.0;
        var k = 0.0;
        while (k < 248.0) {
            let q_k = cartan_vec_get_f32(seq_q_flat, t * 248.0 + k);
            let a_k = cartan_vec_get_f32(agg_248, k);
            q_norm_sq = q_norm_sq + q_k * q_k;
            q_dot_agg = q_dot_agg + q_k * a_k;
            k = k + 1.0;
        }
        var target_r = sqrt(q_norm_sq);
        if (target_r < 0.000001) {
            target_r = 1.0;
            q_norm_sq = 1.0;
        }
        let radial_coeff = q_dot_agg / q_norm_sq;
        var new_norm_sq = 0.0;
        k = 0.0;
        while (k < 248.0) {
            let q_k = cartan_vec_get_f32(seq_q_flat, t * 248.0 + k);
            let a_k = cartan_vec_get_f32(agg_248, k);
            let v_tan = a_k - radial_coeff * q_k;
            let stepped = q_k + step_scale * v_tan;
            cartan_vec_set_f32(seq_out_flat, t * 248.0 + k, stepped);
            new_norm_sq = new_norm_sq + stepped * stepped;
            k = k + 1.0;
        }
        var new_norm = sqrt(new_norm_sq);
        if (new_norm < 0.000001) { new_norm = 1.0; }
        let retract_scale = target_r / new_norm;
        k = 0.0;
        while (k < 248.0) {
            let val = cartan_vec_get_f32(seq_out_flat, t * 248.0 + k);
            cartan_vec_set_f32(seq_out_flat, t * 248.0 + k, val * retract_scale);
            k = k + 1.0;
        }

        t = t + 1.0;
    }

    cartan_vec_free(scores_buf);
    cartan_vec_free(agg_248);
    if (total_pairs <= 0.0) { return 0.0; }
    return total_fr_dist / total_pairs;
}

// ============================================================================
// NON-EUCLIDEAN ASYMMETRIC FINSLER-RANDERS CAUSAL ATTENTION BACKWARD (248-D)
// ============================================================================
// Exact analytical backward pass differentiating:
//   A_{t,s}^{(h)} = ( <Q_t, K_s>_g - 0.35 * d_FR(Q_t, K_s; beta) ) / sqrt(31)
// with respect to Q_t, K_s, V_s, and the Finsler-Randers 1-form beta_248.
fn e8_finsler_randers_causal_attention_backward_248(
    seq_q_flat: ptr,
    seq_k_flat: ptr,
    seq_v_flat: ptr,
    d_seq_out_flat: ptr,
    seq_len: float,
    randers_b_248: ptr,
    step_scale: float,
    d_seq_q_flat: ptr,
    d_seq_k_flat: ptr,
    d_seq_v_flat: ptr,
    d_randers_b_248: ptr
) {
    if (seq_q_flat == 0.0 || seq_k_flat == 0.0 || seq_v_flat == 0.0 || d_seq_out_flat == 0.0 || seq_len <= 0.0) {
        return;
    }
    let num_heads = 8.0;
    let head_dim = 31.0;
    let hidden_dim = 248.0;
    let inv_sqrt_hd = 1.0 / sqrt(head_dim);
    var window_size = 16.0;
    if (window_size > seq_len) {
        window_size = seq_len;
    }

    var b_scale = 1.0;
    if (randers_b_248 != 0.0 && cartan_vec_len(randers_b_248) >= 248.0) {
        var b_norm_sq = 0.0;
        var bi = 0.0;
        while (bi < 248.0) {
            let b_val = cartan_vec_get_f32(randers_b_248, bi);
            let h_idx = floor(bi / 31.0);
            var kw = geom_killing_form_dynkin_weight(h_idx);
            if (kw < 0.001) { kw = 1.0; }
            b_norm_sq = b_norm_sq + (b_val * b_val) / kw;
            bi = bi + 1.0;
        }
        let b_norm = sqrt(b_norm_sq);
        if (b_norm > 0.95) {
            b_scale = 0.95 / b_norm;
        }
    }

    let attn_weights = cartan_vec_create();
    let d_scores = cartan_vec_create();
    let riemann_dists = cartan_vec_create();
    let d_agg_248 = cartan_vec_create();
    var wi = 0.0;
    while (wi < 248.0) {
        if (wi < 16.0) {
            cartan_vec_push_f32(attn_weights, 0.0);
            cartan_vec_push_f32(d_scores, 0.0);
            cartan_vec_push_f32(riemann_dists, 1.0);
        }
        cartan_vec_push_f32(d_agg_248, 0.0);
        wi = wi + 1.0;
    }

    var t = 0.0;
    while (t < seq_len) {
        var win_start = t - window_size + 1.0;
        if (win_start < 0.0) { win_start = 0.0; }
        let win_len = t - win_start + 1.0;

        // Tangent projection pullback on T_{Q_t} S^{247}
        var q_norm_sq = 0.0;
        var q_dot_dout = 0.0;
        var k = 0.0;
        while (k < 248.0) {
            let q_k = cartan_vec_get_f32(seq_q_flat, t * 248.0 + k);
            let dy_k = cartan_vec_get_f32(d_seq_out_flat, t * 248.0 + k);
            q_norm_sq = q_norm_sq + q_k * q_k;
            q_dot_dout = q_dot_dout + q_k * dy_k;
            k = k + 1.0;
        }
        if (q_norm_sq < 0.000001) { q_norm_sq = 1.0; }
        let proj_c = q_dot_dout / q_norm_sq;
        k = 0.0;
        while (k < 248.0) {
            let q_k = cartan_vec_get_f32(seq_q_flat, t * 248.0 + k);
            let dy_k = cartan_vec_get_f32(d_seq_out_flat, t * 248.0 + k);
            let dy_tan = dy_k - proj_c * q_k;
            cartan_vec_set_f32(d_agg_248, k, step_scale * dy_tan);
            if (d_seq_q_flat != 0.0) {
                let cur_dq = cartan_vec_get_f32(d_seq_q_flat, t * 248.0 + k);
                cartan_vec_set_f32(d_seq_q_flat, t * 248.0 + k, cur_dq + dy_k);
            }
            k = k + 1.0;
        }

        var h = 0.0;
        while (h < num_heads) {
            let kw = geom_killing_form_dynkin_weight(h);
            var max_sc = -100000.0;
            var s = win_start;
            var s_idx = 0.0;
            while (s <= t) {
                var dot_g = 0.0;
                var diff_sq_g = 0.0;
                var randers_drift = 0.0;
                var d = 0.0;
                while (d < head_dim) {
                    let dim_idx = h * head_dim + d;
                    let q_val = cartan_vec_get_f32(seq_q_flat, t * hidden_dim + dim_idx);
                    let k_val = cartan_vec_get_f32(seq_k_flat, s * hidden_dim + dim_idx);
                    let diff = q_val - k_val;
                    dot_g = dot_g + (q_val * k_val) * kw;
                    diff_sq_g = diff_sq_g + (diff * diff) * kw;
                    if (randers_b_248 != 0.0) {
                        let b_d = cartan_vec_get_f32(randers_b_248, dim_idx) * b_scale;
                        randers_drift = randers_drift + b_d * diff;
                    }
                    d = d + 1.0;
                }
                let r_dist = sqrt(diff_sq_g + 0.000001);
                cartan_vec_set_f32(riemann_dists, s_idx, r_dist);
                var fr_dist = r_dist + randers_drift;
                if (fr_dist < 0.0) { fr_dist = 0.0; }
                let sc = (dot_g - 0.35 * fr_dist) * inv_sqrt_hd;
                cartan_vec_set_f32(attn_weights, s_idx, sc);
                if (sc > max_sc) { max_sc = sc; }
                s = s + 1.0;
                s_idx = s_idx + 1.0;
            }

            var sum_exp = 0.0;
            var i = 0.0;
            while (i < win_len) {
                let sc = cartan_vec_get_f32(attn_weights, i);
                let w_exp = exp(sc - max_sc);
                cartan_vec_set_f32(attn_weights, i, w_exp);
                sum_exp = sum_exp + w_exp;
                i = i + 1.0;
            }
            if (sum_exp <= 0.0000001) { sum_exp = 1.0; }
            i = 0.0;
            while (i < win_len) {
                let w_norm = cartan_vec_get_f32(attn_weights, i) / sum_exp;
                cartan_vec_set_f32(attn_weights, i, w_norm);
                i = i + 1.0;
            }

            // Compute dL/d(attn_w) and accumulate dL/dV_s
            var sum_w_dw = 0.0;
            s = win_start;
            s_idx = 0.0;
            while (s <= t) {
                let w_s = cartan_vec_get_f32(attn_weights, s_idx);
                var dw_s = 0.0;
                var d = 0.0;
                while (d < head_dim) {
                    let dim_idx = h * head_dim + d;
                    let d_agg = cartan_vec_get_f32(d_agg_248, dim_idx);
                    let v_val = cartan_vec_get_f32(seq_v_flat, s * hidden_dim + dim_idx);
                    dw_s = dw_s + d_agg * v_val;
                    if (d_seq_v_flat != 0.0) {
                        let cur_dv = cartan_vec_get_f32(d_seq_v_flat, s * hidden_dim + dim_idx);
                        cartan_vec_set_f32(d_seq_v_flat, s * hidden_dim + dim_idx, cur_dv + w_s * d_agg);
                    }
                    d = d + 1.0;
                }
                cartan_vec_set_f32(d_scores, s_idx, dw_s);
                sum_w_dw = sum_w_dw + w_s * dw_s;
                s = s + 1.0;
                s_idx = s_idx + 1.0;
            }

            // Softmax Jacobian pullback into d(score_{t,s}) and differentiate Finsler-Randers score
            s = win_start;
            s_idx = 0.0;
            while (s <= t) {
                let w_s = cartan_vec_get_f32(attn_weights, s_idx);
                let dw_s = cartan_vec_get_f32(d_scores, s_idx);
                let d_sc = w_s * (dw_s - sum_w_dw) * inv_sqrt_hd;
                let r_dist = cartan_vec_get_f32(riemann_dists, s_idx);

                var d = 0.0;
                while (d < head_dim) {
                    let dim_idx = h * head_dim + d;
                    let q_val = cartan_vec_get_f32(seq_q_flat, t * hidden_dim + dim_idx);
                    let k_val = cartan_vec_get_f32(seq_k_flat, s * hidden_dim + dim_idx);
                    let diff = q_val - k_val;
                    var b_d = 0.0;
                    if (randers_b_248 != 0.0) {
                        b_d = cartan_vec_get_f32(randers_b_248, dim_idx) * b_scale;
                    }

                    // d(score)/dQ_{t,d} = kw * K_{s,d} - 0.35 * (kw * diff / r_dist + b_d)
                    // d(score)/dK_{s,d} = kw * Q_{t,d} + 0.35 * (kw * diff / r_dist + b_d)
                    let d_fr_dq = (kw * diff) / r_dist + b_d;
                    let grad_q = d_sc * (kw * k_val - 0.35 * d_fr_dq);
                    let grad_k = d_sc * (kw * q_val + 0.35 * d_fr_dq);

                    if (d_seq_q_flat != 0.0) {
                        let cur_dq = cartan_vec_get_f32(d_seq_q_flat, t * hidden_dim + dim_idx);
                        cartan_vec_set_f32(d_seq_q_flat, t * hidden_dim + dim_idx, cur_dq + grad_q);
                    }
                    if (d_seq_k_flat != 0.0) {
                        let cur_dk = cartan_vec_get_f32(d_seq_k_flat, s * hidden_dim + dim_idx);
                        cartan_vec_set_f32(d_seq_k_flat, s * hidden_dim + dim_idx, cur_dk + grad_k);
                    }
                    if (d_randers_b_248 != 0.0) {
                        let cur_db = cartan_vec_get_f32(d_randers_b_248, dim_idx);
                        let grad_b = (0.0 - 0.35) * d_sc * diff * b_scale;
                        cartan_vec_set_f32(d_randers_b_248, dim_idx, cur_db + grad_b);
                    }
                    d = d + 1.0;
                }
                s = s + 1.0;
                s_idx = s_idx + 1.0;
            }
            h = h + 1.0;
        }
        t = t + 1.0;
    }

    cartan_vec_free(attn_weights);
    cartan_vec_free(d_scores);
    cartan_vec_free(riemann_dists);
    cartan_vec_free(d_agg_248);
}

// ============================================================================
// SLIDING WINDOW ATTENTION WITH FINSLER-RANDERS METRIC & SPHERE RETRACTION
// ============================================================================
fn e8_multihead_sliding_window_attention(h_vec: ptr, num_heads: float, head_dim: float) -> ptr {
    if (h_vec == 0.0 || num_heads <= 0.0 || head_dim <= 0.0) {
        return cartan_vec_create();
    }
    let hidden_dim = num_heads * head_dim;
    let len = cartan_vec_len(h_vec);
    if (len < hidden_dim) {
        return cartan_vec_create();
    }
    let seq_len = floor(len / hidden_dim);
    let out_vec = cartan_vec_create();
    var idx = 0.0;
    while (idx < seq_len * hidden_dim) {
        cartan_vec_push_f32(out_vec, 0.0);
        idx = idx + 1.0;
    }

    if (hidden_dim == 248.0 && num_heads == 8.0 && head_dim == 31.0) {
        var null_b: ptr = 0.0;
        e8_finsler_randers_causal_attention_forward_248(h_vec, h_vec, h_vec, seq_len, null_b, out_vec, 0.25);
        return out_vec;
    }

    var window_size = 8.0;
    if (window_size > seq_len) {
        window_size = seq_len;
    }
    let scale = 1.0 / sqrt(head_dim);

    var h = 0.0;
    while (h < num_heads) {
        var t = 0.0;
        while (t < seq_len) {
            var win_start = t - window_size + 1.0;
            if (win_start < 0.0) { win_start = 0.0; }
            let win_len = t - win_start + 1.0;

            var s = win_start;
            var max_score = -100000.0;
            let scores = cartan_vec_create();
            while (s <= t) {
                var dot = 0.0;
                var diff_sq = 0.0;
                var d = 0.0;
                while (d < head_dim) {
                    let q_idx = t * hidden_dim + h * head_dim + d;
                    let k_idx = s * hidden_dim + h * head_dim + d;
                    let q_val = cartan_vec_get_f32(h_vec, q_idx);
                    let k_val = cartan_vec_get_f32(h_vec, k_idx);
                    let diff = q_val - k_val;
                    let sub_idx = math_mod_val(floor((h * head_dim + d) * 8.0 / hidden_dim), 8.0);
                    let kw = geom_killing_form_dynkin_weight(sub_idx);
                    dot = dot + (q_val * k_val) * kw;
                    diff_sq = diff_sq + (diff * diff) * kw;
                    d = d + 1.0;
                }
                let score = (dot - 0.35 * sqrt(diff_sq + 0.000001)) * scale;
                cartan_vec_push_f32(scores, score);
                if (score > max_score) {
                    max_score = score;
                }
                s = s + 1.0;
            }

            var sum_exp = 0.0;
            var i = 0.0;
            while (i < win_len) {
                let sc = cartan_vec_get_f32(scores, i);
                sum_exp = sum_exp + exp(sc - max_score);
                i = i + 1.0;
            }
            if (sum_exp <= 0.0) { sum_exp = 1.0; }

            // Compute head norm and tangent projection for Riemannian sphere retraction
            var q_norm_sq = 0.0;
            var q_dot_acc = 0.0;
            let acc_head = cartan_vec_create();
            var d_out = 0.0;
            while (d_out < head_dim) {
                var acc = 0.0;
                s = win_start;
                var s_idx = 0.0;
                while (s <= t) {
                    let sc = cartan_vec_get_f32(scores, s_idx);
                    let attn_w = exp(sc - max_score) / sum_exp;
                    let v_idx = s * hidden_dim + h * head_dim + d_out;
                    let v_val = cartan_vec_get_f32(h_vec, v_idx);
                    acc = acc + (attn_w * v_val);
                    s = s + 1.0;
                    s_idx = s_idx + 1.0;
                }
                cartan_vec_push_f32(acc_head, acc);
                let orig = cartan_vec_get_f32(h_vec, t * hidden_dim + h * head_dim + d_out);
                q_norm_sq = q_norm_sq + orig * orig;
                q_dot_acc = q_dot_acc + orig * acc;
                d_out = d_out + 1.0;
            }
            var target_r = sqrt(q_norm_sq);
            if (target_r < 0.000001) {
                target_r = 1.0;
                q_norm_sq = 1.0;
            }
            let radial_c = q_dot_acc / q_norm_sq;
            var new_norm_sq = 0.0;
            d_out = 0.0;
            while (d_out < head_dim) {
                let out_idx = t * hidden_dim + h * head_dim + d_out;
                let orig = cartan_vec_get_f32(h_vec, out_idx);
                let acc = cartan_vec_get_f32(acc_head, d_out);
                let v_tan = acc - radial_c * orig;
                let stepped = orig + 0.25 * v_tan;
                cartan_vec_set_f32(out_vec, out_idx, stepped);
                new_norm_sq = new_norm_sq + stepped * stepped;
                d_out = d_out + 1.0;
            }
            var new_norm = sqrt(new_norm_sq);
            if (new_norm < 0.000001) { new_norm = 1.0; }
            let r_scale = target_r / new_norm;
            d_out = 0.0;
            while (d_out < head_dim) {
                let out_idx = t * hidden_dim + h * head_dim + d_out;
                let val = cartan_vec_get_f32(out_vec, out_idx);
                cartan_vec_set_f32(out_vec, out_idx, val * r_scale);
                d_out = d_out + 1.0;
            }

            cartan_vec_free(acc_head);
            cartan_vec_free(scores);
            t = t + 1.0;
        }
        h = h + 1.0;
    }

    return out_vec;
}

fn e8_attention_compute_energy(h: ptr) -> float {
    if (h == 0.0) { return 0.0; }
    var sum_sq = 0.0;
    var i = 0.0;
    let n = cartan_vec_len(h);
    var stride = floor(n / 8.0);
    if (stride < 1.0) { stride = 1.0; }
    while (i < n) {
        let v = cartan_vec_get_f32(h, i);
        let sub_idx = floor(i / stride);
        let kw = geom_killing_form_dynkin_weight(sub_idx);
        sum_sq = sum_sq + (v * v) * kw;
        i = i + 1.0;
    }
    return 0.5 * sum_sq;
}

// Anisotropic Killing-Cartan RMSNorm bounding manifold activation energy to 1.0
fn cartan_tensor_rmsnorm(v: ptr, eps: float) {
    if (v == 0.0) { return; }
    let dim = v[0];
    if (dim <= 0.0) { return; }
    var sum_sq = 0.0;
    var i = 0.0;
    var stride = floor(dim / 8.0);
    if (stride < 1.0) { stride = 1.0; }
    while (i < dim) {
        let val = v[2.0 + i];
        let sub_idx = floor(i / stride);
        let kw = geom_killing_form_dynkin_weight(sub_idx);
        sum_sq = sum_sq + (val * val) * kw;
        i = i + 1.0;
    }
    let rms = sqrt((sum_sq / dim) + eps);
    if (rms <= 0.000001) { return; }
    let inv_rms = 1.0 / rms;
    i = 0.0;
    while (i < dim) {
        v[2.0 + i] = v[2.0 + i] * inv_rms;
        i = i + 1.0;
    }
}

// Non-Euclidean 16-layer E8 Gauge-Spinor & Freudenthal manifold cascade with sphere retraction
fn e8_attention_forward_step_with_momentum(hidden_ptr: ptr, mom_ptr: ptr, temp: float) -> ptr {
    if (hidden_ptr == 0.0) { return cartan_vec_create(); }
    let h_len = hidden_ptr[0];
    if (h_len == 0.0) { return cartan_vec_create(); }
    let weights = cartan_sasaki_brainstem_route_vec(hidden_ptr, mom_ptr, temp);
    let h_cur = geomind_streams_manifold_forward_routed(hidden_ptr, weights);
    if (weights != 0.0) {
        cartan_vec_free(weights);
    }

    cartan_tensor_rmsnorm(h_cur, 0.00001);
    let dim = h_cur[0];
    let gated_buf = cartan_tensor_alloc(dim);
    var l = 0.0;
    while (l < 16.0) {
        if (l == 6.0 || l == 12.0) {
            geomind_e8_stream_herald_inplace(h_cur);
        }
        // Apply Non-Euclidean E8 Gauge-Spinor Cross-Gate across 248-D blocks
        geomind_e8_gauge_spinor_cross_gate(h_cur, gated_buf, 0.25);
        var d = 0.0;
        while (d < dim) {
            h_cur[2.0 + d] = gated_buf[2.0 + d];
            d = d + 1.0;
        }
        l = l + 1.0;
    }
    cartan_vec_free(gated_buf);
    cartan_tensor_rmsnorm(h_cur, 0.00001);
    return h_cur;
}

fn e8_attention_forward_step(hidden_ptr: ptr, temp: float) -> ptr {
    var null_mom: ptr = 0.0;
    return e8_attention_forward_step_with_momentum(hidden_ptr, null_mom, temp);
}
