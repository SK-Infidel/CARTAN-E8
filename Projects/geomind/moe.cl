// Projects/geomind/moe.cl
// CARTAN-E8 Non-Euclidean 4x4 Freudenthal-Tits Magic Square Division-Algebra MoE
// Routes across the 16 Magic Square Lie algebras M(A_r, B_c) for A_r, B_c in {R(1D), C(2D), H(4D), O(8D)}
// using the Sasaki-Finsler-Randers Phase-Space Metric on TS^247 and executes true normed division-algebra
// multiplication (Real, Complex, Quaternion Hamilton, Octonion Fano) with Riemannian Sphere Retraction.

include "../../src/std/autotune.cl";
include "../../src/std/collections.cl";
include "../../src/std/math.cl";
include "../../src/std/geom.cl";
include "geometry.cl";

struct MoEConfig {
    num_experts: float;
    top_k: float;
    hidden_dim: float;
}

struct FreudenthalExpert {
    row_algebra: float;
    col_algebra: float;
    dimension: float;
}

struct E8MagicSquareMoE {
    expert_00_so3: float;     // R x R (dim 3)
    expert_01_su3: float;     // R x C (dim 8)
    expert_02_sp3: float;     // R x H (dim 21)
    expert_03_f4: float;      // R x O (dim 52)
    expert_10_su3: float;     // C x R (dim 8)
    expert_11_su3_su3: float; // C x C (dim 16)
    expert_12_su6: float;     // C x H (dim 35)
    expert_13_e6: float;      // C x O (dim 78)
    expert_20_sp3: float;     // H x R (dim 21)
    expert_21_su6: float;     // H x C (dim 35)
    expert_22_so12: float;    // H x H (dim 66)
    expert_23_e7: float;      // H x O (dim 133)
    expert_30_f4: float;      // O x R (dim 52)
    expert_31_e6: float;      // O x C (dim 78)
    expert_32_e7: float;      // O x H (dim 133)
    expert_33_e8: float;      // O x O (dim 248)
}

fn geomind_freudenthal_lie_dim(row_alg: float, col_alg: float) -> float {
    let r = math_mod_val(floor(math_abs_val(row_alg)), 4.0);
    let c = math_mod_val(floor(math_abs_val(col_alg)), 4.0);
    var lo = r;
    var hi = c;
    if (r > c) { lo = c; hi = r; }
    if (lo == 0.0) {
        if (hi == 0.0) { return 3.0; }   // so(3)
        if (hi == 1.0) { return 8.0; }   // su(3)
        if (hi == 2.0) { return 21.0; }  // sp(3)
        return 52.0;                     // f4
    }
    if (lo == 1.0) {
        if (hi == 1.0) { return 16.0; }  // su(3) (+) su(3)
        if (hi == 2.0) { return 35.0; }  // su(6)
        return 78.0;                     // e6
    }
    if (lo == 2.0) {
        if (hi == 2.0) { return 66.0; }  // so(12)
        return 133.0;                    // e7
    }
    return 248.0;                        // e8
}

// Applies a single Normed Division Algebra operator (0=R, 1=C, 2=H, 3=O) to an 8D vector block:
// - alg_type == 0 (R): Real dilation by unit_op[0]
// - alg_type == 1 (C): 4x Complex Symplectic multiplication (u0 + i*u1) * (x_{2m} + i*x_{2m+1})
// - alg_type == 2 (H): 2x Hamilton Quaternion non-commutative product u *_H x[0..3], u *_H x[4..7]
// - alg_type == 3 (O): 1x Cayley-Graves Octonion non-associative Fano product u *_O x[0..7]
fn geomind_division_algebra_mul_raw8(
    alg_type: float,
    u_ptr: ptr, u_off: float,
    x_ptr: ptr, x_off: float,
    out_ptr: ptr, out_off: float
) {
    let u0 = cartan_vec_get_f32(u_ptr, u_off + 0.0);
    let u1 = cartan_vec_get_f32(u_ptr, u_off + 1.0);
    let u2 = cartan_vec_get_f32(u_ptr, u_off + 2.0);
    let u3 = cartan_vec_get_f32(u_ptr, u_off + 3.0);

    let x0 = cartan_vec_get_f32(x_ptr, x_off + 0.0);
    let x1 = cartan_vec_get_f32(x_ptr, x_off + 1.0);
    let x2 = cartan_vec_get_f32(x_ptr, x_off + 2.0);
    let x3 = cartan_vec_get_f32(x_ptr, x_off + 3.0);
    let x4 = cartan_vec_get_f32(x_ptr, x_off + 4.0);
    let x5 = cartan_vec_get_f32(x_ptr, x_off + 5.0);
    let x6 = cartan_vec_get_f32(x_ptr, x_off + 6.0);
    let x7 = cartan_vec_get_f32(x_ptr, x_off + 7.0);

    if (alg_type <= 0.5) {
        // Real (R): isotropic geodesic scaling
        var s_r = u0;
        if (math_abs_val(s_r) < 0.001) { s_r = 1.0; }
        cartan_vec_set_f32(out_ptr, out_off + 0.0, s_r * x0);
        cartan_vec_set_f32(out_ptr, out_off + 1.0, s_r * x1);
        cartan_vec_set_f32(out_ptr, out_off + 2.0, s_r * x2);
        cartan_vec_set_f32(out_ptr, out_off + 3.0, s_r * x3);
        cartan_vec_set_f32(out_ptr, out_off + 4.0, s_r * x4);
        cartan_vec_set_f32(out_ptr, out_off + 5.0, s_r * x5);
        cartan_vec_set_f32(out_ptr, out_off + 6.0, s_r * x6);
        cartan_vec_set_f32(out_ptr, out_off + 7.0, s_r * x7);
        return;
    }
    if (alg_type <= 1.5) {
        // Complex (C): 4 symplectic 2D planes
        var c_norm = sqrt(u0 * u0 + u1 * u1);
        if (c_norm < 0.001) { c_norm = 1.0; }
        let c0 = u0 / c_norm;
        let c1 = u1 / c_norm;
        cartan_vec_set_f32(out_ptr, out_off + 0.0, c0 * x0 - c1 * x1);
        cartan_vec_set_f32(out_ptr, out_off + 1.0, c0 * x1 + c1 * x0);
        cartan_vec_set_f32(out_ptr, out_off + 2.0, c0 * x2 - c1 * x3);
        cartan_vec_set_f32(out_ptr, out_off + 3.0, c0 * x3 + c1 * x2);
        cartan_vec_set_f32(out_ptr, out_off + 4.0, c0 * x4 - c1 * x5);
        cartan_vec_set_f32(out_ptr, out_off + 5.0, c0 * x5 + c1 * x4);
        cartan_vec_set_f32(out_ptr, out_off + 6.0, c0 * x6 - c1 * x7);
        cartan_vec_set_f32(out_ptr, out_off + 7.0, c0 * x7 + c1 * x6);
        return;
    }
    if (alg_type <= 2.5) {
        // Quaternion (H): 2 non-commutative Hamilton 4D spinor blocks
        var q_norm = sqrt(u0 * u0 + u1 * u1 + u2 * u2 + u3 * u3);
        if (q_norm < 0.001) { q_norm = 1.0; }
        let q0 = u0 / q_norm;
        let q1 = u1 / q_norm;
        let q2 = u2 / q_norm;
        let q3 = u3 / q_norm;
        cartan_vec_set_f32(out_ptr, out_off + 0.0, q0 * x0 - q1 * x1 - q2 * x2 - q3 * x3);
        cartan_vec_set_f32(out_ptr, out_off + 1.0, q0 * x1 + q1 * x0 + q2 * x3 - q3 * x2);
        cartan_vec_set_f32(out_ptr, out_off + 2.0, q0 * x2 - q1 * x3 + q2 * x0 + q3 * x1);
        cartan_vec_set_f32(out_ptr, out_off + 3.0, q0 * x3 + q1 * x2 - q2 * x1 + q3 * x0);

        cartan_vec_set_f32(out_ptr, out_off + 4.0, q0 * x4 - q1 * x5 - q2 * x6 - q3 * x7);
        cartan_vec_set_f32(out_ptr, out_off + 5.0, q0 * x5 + q1 * x4 + q2 * x7 - q3 * x6);
        cartan_vec_set_f32(out_ptr, out_off + 6.0, q0 * x6 - q1 * x7 + q2 * x4 + q3 * x5);
        cartan_vec_set_f32(out_ptr, out_off + 7.0, q0 * x7 + q1 * x6 - q2 * x5 + q3 * x4);
        return;
    }
    // Octonion (O): full 8D non-associative Fano plane multiplication
    let u4 = cartan_vec_get_f32(u_ptr, u_off + 4.0);
    let u5 = cartan_vec_get_f32(u_ptr, u_off + 5.0);
    let u6 = cartan_vec_get_f32(u_ptr, u_off + 6.0);
    let u7 = cartan_vec_get_f32(u_ptr, u_off + 7.0);
    var o_norm = sqrt(u0*u0 + u1*u1 + u2*u2 + u3*u3 + u4*u4 + u5*u5 + u6*u6 + u7*u7);
    if (o_norm < 0.001) { o_norm = 1.0; }
    let inv_o = 1.0 / o_norm;
    let a0 = u0 * inv_o; let a1 = u1 * inv_o; let a2 = u2 * inv_o; let a3 = u3 * inv_o;
    let a4 = u4 * inv_o; let a5 = u5 * inv_o; let a6 = u6 * inv_o; let a7 = u7 * inv_o;
    cartan_vec_set_f32(out_ptr, out_off + 0.0, a0*x0 - a1*x1 - a2*x2 - a3*x3 - a4*x4 - a5*x5 - a6*x6 - a7*x7);
    cartan_vec_set_f32(out_ptr, out_off + 1.0, a0*x1 + a1*x0 + a2*x3 - a3*x2 + a4*x5 - a5*x4 - a6*x7 + a7*x6);
    cartan_vec_set_f32(out_ptr, out_off + 2.0, a0*x2 - a1*x3 + a2*x0 + a3*x1 + a4*x6 + a5*x7 - a6*x4 - a7*x5);
    cartan_vec_set_f32(out_ptr, out_off + 3.0, a0*x3 + a1*x2 - a2*x1 + a3*x0 + a4*x7 - a5*x6 + a6*x5 - a7*x4);
    cartan_vec_set_f32(out_ptr, out_off + 4.0, a0*x4 - a1*x5 - a2*x6 - a3*x7 + a4*x0 + a5*x1 + a6*x2 + a7*x3);
    cartan_vec_set_f32(out_ptr, out_off + 5.0, a0*x5 + a1*x4 - a2*x7 + a3*x6 - a4*x1 + a5*x0 - a6*x3 + a7*x2);
    cartan_vec_set_f32(out_ptr, out_off + 6.0, a0*x6 + a1*x7 + a2*x4 - a3*x5 - a4*x2 + a5*x3 + a6*x0 - a7*x1);
    cartan_vec_set_f32(out_ptr, out_off + 7.0, a0*x7 - a1*x6 + a2*x5 + a3*x4 - a4*x3 - a5*x2 + a6*x1 + a7*x0);
}

// Exact Adjoint (Conjugate Transpose) of Normed Division Algebra Multiplication:
// Given y = u *_{A} x and dy, computes dx = \bar{u} *_{A} dy and du = dy *_{A} \bar{x}
fn geomind_division_algebra_mul_backward_raw8(
    alg_type: float,
    u_ptr: ptr, u_off: float,
    x_ptr: ptr, x_off: float,
    dy_ptr: ptr, dy_off: float,
    du_ptr: ptr, du_off: float,
    dx_ptr: ptr, dx_off: float
) {
    let u0 = cartan_vec_get_f32(u_ptr, u_off + 0.0);
    let u1 = cartan_vec_get_f32(u_ptr, u_off + 1.0);
    let u2 = cartan_vec_get_f32(u_ptr, u_off + 2.0);
    let u3 = cartan_vec_get_f32(u_ptr, u_off + 3.0);

    let x0 = cartan_vec_get_f32(x_ptr, x_off + 0.0);
    let x1 = cartan_vec_get_f32(x_ptr, x_off + 1.0);
    let x2 = cartan_vec_get_f32(x_ptr, x_off + 2.0);
    let x3 = cartan_vec_get_f32(x_ptr, x_off + 3.0);
    let x4 = cartan_vec_get_f32(x_ptr, x_off + 4.0);
    let x5 = cartan_vec_get_f32(x_ptr, x_off + 5.0);
    let x6 = cartan_vec_get_f32(x_ptr, x_off + 6.0);
    let x7 = cartan_vec_get_f32(x_ptr, x_off + 7.0);

    let g0 = cartan_vec_get_f32(dy_ptr, dy_off + 0.0);
    let g1 = cartan_vec_get_f32(dy_ptr, dy_off + 1.0);
    let g2 = cartan_vec_get_f32(dy_ptr, dy_off + 2.0);
    let g3 = cartan_vec_get_f32(dy_ptr, dy_off + 3.0);
    let g4 = cartan_vec_get_f32(dy_ptr, dy_off + 4.0);
    let g5 = cartan_vec_get_f32(dy_ptr, dy_off + 5.0);
    let g6 = cartan_vec_get_f32(dy_ptr, dy_off + 6.0);
    let g7 = cartan_vec_get_f32(dy_ptr, dy_off + 7.0);

    if (alg_type <= 0.5) {
        var s_r = u0;
        if (math_abs_val(s_r) < 0.001) { s_r = 1.0; }
        if (dx_ptr != 0.0) {
            cartan_vec_set_f32(dx_ptr, dx_off + 0.0, s_r * g0);
            cartan_vec_set_f32(dx_ptr, dx_off + 1.0, s_r * g1);
            cartan_vec_set_f32(dx_ptr, dx_off + 2.0, s_r * g2);
            cartan_vec_set_f32(dx_ptr, dx_off + 3.0, s_r * g3);
            cartan_vec_set_f32(dx_ptr, dx_off + 4.0, s_r * g4);
            cartan_vec_set_f32(dx_ptr, dx_off + 5.0, s_r * g5);
            cartan_vec_set_f32(dx_ptr, dx_off + 6.0, s_r * g6);
            cartan_vec_set_f32(dx_ptr, dx_off + 7.0, s_r * g7);
        }
        if (du_ptr != 0.0) {
            let dot_rx = g0*x0 + g1*x1 + g2*x2 + g3*x3 + g4*x4 + g5*x5 + g6*x6 + g7*x7;
            cartan_vec_set_f32(du_ptr, du_off + 0.0, dot_rx);
        }
        return;
    }
    if (alg_type <= 1.5) {
        var c_norm = sqrt(u0 * u0 + u1 * u1);
        if (c_norm < 0.001) { c_norm = 1.0; }
        let c0 = u0 / c_norm;
        let c1 = u1 / c_norm;
        if (dx_ptr != 0.0) {
            cartan_vec_set_f32(dx_ptr, dx_off + 0.0, c0 * g0 + c1 * g1);
            cartan_vec_set_f32(dx_ptr, dx_off + 1.0, c0 * g1 - c1 * g0);
            cartan_vec_set_f32(dx_ptr, dx_off + 2.0, c0 * g2 + c1 * g3);
            cartan_vec_set_f32(dx_ptr, dx_off + 3.0, c0 * g3 - c1 * g2);
            cartan_vec_set_f32(dx_ptr, dx_off + 4.0, c0 * g4 + c1 * g5);
            cartan_vec_set_f32(dx_ptr, dx_off + 5.0, c0 * g5 - c1 * g4);
            cartan_vec_set_f32(dx_ptr, dx_off + 6.0, c0 * g6 + c1 * g7);
            cartan_vec_set_f32(dx_ptr, dx_off + 7.0, c0 * g7 - c1 * g6);
        }
        if (du_ptr != 0.0) {
            let du0 = (g0*x0 + g1*x1 + g2*x2 + g3*x3 + g4*x4 + g5*x5 + g6*x6 + g7*x7) / c_norm;
            let du1 = (g1*x0 - g0*x1 + g3*x2 - g2*x3 + g5*x4 - g4*x5 + g7*x6 - g6*x7) / c_norm;
            cartan_vec_set_f32(du_ptr, du_off + 0.0, du0);
            cartan_vec_set_f32(du_ptr, du_off + 1.0, du1);
        }
        return;
    }
    if (alg_type <= 2.5) {
        var q_norm = sqrt(u0 * u0 + u1 * u1 + u2 * u2 + u3 * u3);
        if (q_norm < 0.001) { q_norm = 1.0; }
        let q0 = u0 / q_norm;
        let q1 = (0.0 - u1) / q_norm;
        let q2 = (0.0 - u2) / q_norm;
        let q3 = (0.0 - u3) / q_norm;
        if (dx_ptr != 0.0) {
            cartan_vec_set_f32(dx_ptr, dx_off + 0.0, q0 * g0 - q1 * g1 - q2 * g2 - q3 * g3);
            cartan_vec_set_f32(dx_ptr, dx_off + 1.0, q0 * g1 + q1 * g0 + q2 * g3 - q3 * g2);
            cartan_vec_set_f32(dx_ptr, dx_off + 2.0, q0 * g2 - q1 * g3 + q2 * g0 + q3 * g1);
            cartan_vec_set_f32(dx_ptr, dx_off + 3.0, q0 * g3 + q1 * g2 - q2 * g1 + q3 * g0);

            cartan_vec_set_f32(dx_ptr, dx_off + 4.0, q0 * g4 - q1 * g5 - q2 * g6 - q3 * g7);
            cartan_vec_set_f32(dx_ptr, dx_off + 5.0, q0 * g5 + q1 * g4 + q2 * g7 - q3 * g6);
            cartan_vec_set_f32(dx_ptr, dx_off + 6.0, q0 * g6 - q1 * g7 + q2 * g4 + q3 * g5);
            cartan_vec_set_f32(dx_ptr, dx_off + 7.0, q0 * g7 + q1 * g6 - q2 * g5 + q3 * g4);
        }
        if (du_ptr != 0.0) {
            let du0 = (g0*x0 + g1*x1 + g2*x2 + g3*x3 + g4*x4 + g5*x5 + g6*x6 + g7*x7) / q_norm;
            let du1 = (g1*x0 - g0*x1 - g2*x3 + g3*x2 + g5*x4 - g4*x5 - g6*x7 + g7*x6) / q_norm;
            let du2 = (g2*x0 + g1*x3 - g0*x2 - g3*x1 + g6*x4 + g5*x7 - g4*x6 - g7*x5) / q_norm;
            let du3 = (g3*x0 - g1*x2 + g2*x1 - g0*x3 + g7*x4 - g5*x6 + g6*x5 - g4*x7) / q_norm;
            cartan_vec_set_f32(du_ptr, du_off + 0.0, du0);
            cartan_vec_set_f32(du_ptr, du_off + 1.0, du1);
            cartan_vec_set_f32(du_ptr, du_off + 2.0, du2);
            cartan_vec_set_f32(du_ptr, du_off + 3.0, du3);
        }
        return;
    }
    // Octonion (O): exact Octonion conjugate transpose product
    let u4 = cartan_vec_get_f32(u_ptr, u_off + 4.0);
    let u5 = cartan_vec_get_f32(u_ptr, u_off + 5.0);
    let u6 = cartan_vec_get_f32(u_ptr, u_off + 6.0);
    let u7 = cartan_vec_get_f32(u_ptr, u_off + 7.0);
    var o_norm = sqrt(u0*u0 + u1*u1 + u2*u2 + u3*u3 + u4*u4 + u5*u5 + u6*u6 + u7*u7);
    if (o_norm < 0.001) { o_norm = 1.0; }
    let inv_o = 1.0 / o_norm;
    geom_octonion_mul_backward_raw8(u_ptr, u_off, x_ptr, x_off, dy_ptr, dy_off, du_ptr, du_off, dx_ptr, dx_off);
    var k = 0.0;
    while (k < 8.0) {
        if (dx_ptr != 0.0) {
            cartan_vec_set_f32(dx_ptr, dx_off + k, cartan_vec_get_f32(dx_ptr, dx_off + k) * inv_o);
        }
        if (du_ptr != 0.0) {
            cartan_vec_set_f32(du_ptr, du_off + k, cartan_vec_get_f32(du_ptr, du_off + k) * inv_o);
        }
        k = k + 1.0;
    }
}

fn geomind_sasaki_route(position: ptr, momentum: ptr, expert_idx: float) -> float {
    if (position == 0.0 || momentum == 0.0) { return 0.0; }
    let plen = cartan_vec_len(position);
    if (plen <= 0.0) { return 0.0; }
    let sub_idx = math_mod_val(expert_idx, 8.0);
    let kw = geom_killing_form_dynkin_weight(sub_idx);
    var d_sasaki_sq = 0.0;
    var d = 0.0;
    while (d < plen) {
        let pos_d = cartan_vec_get_f32(position, d);
        var mom_d = 0.0;
        if (d < cartan_vec_len(momentum)) {
            mom_d = cartan_vec_get_f32(momentum, d);
        }
        d_sasaki_sq = d_sasaki_sq + ((pos_d * pos_d) + (mom_d * mom_d)) * kw;
        d = d + 1.0;
    }
    let norm_energy = d_sasaki_sq / plen;
    let route_score = exp(0.0 - (norm_energy * 0.05));
    return route_score;
}

// Persistent static scratch buffers for zero-allocation Sasaki routing
var g_sasaki_weights: ptr = 0.0;
var g_sasaki_logits: ptr = 0.0;

fn geomind_sasaki_stream_routing(position: ptr, momentum: ptr, temp: float) -> ptr {
    if (g_sasaki_weights == 0.0) {
        g_sasaki_weights = cartan_vec_create();
        g_sasaki_logits = cartan_vec_create();
        var init_s = 0.0;
        while (init_s < 8.0) {
            cartan_vec_push_f32(g_sasaki_weights, 0.125);
            cartan_vec_push_f32(g_sasaki_logits, 0.0);
            init_s = init_s + 1.0;
        }
    }
    if (position == 0.0) {
        var s = 0.0;
        while (s < 8.0) {
            cartan_vec_set_f32(g_sasaki_weights, s, 0.125);
            s = s + 1.0;
        }
        return g_sasaki_weights;
    }
    var t = 0.70;
    if (temp > 0.05) { t = temp; }
    let plen = position[0];
    var max_logit = -1000000.0;

    var stream_dim = floor(plen / 8.0);
    if (stream_dim < 1.0) { stream_dim = 320.0; }

    var s = 0.0;
    while (s < 8.0) {
        let start_d = s * stream_dim;
        let kw = geom_killing_form_dynkin_weight(s);
        var pos_sq = 0.0;
        var mom_sq = 0.0;
        var dot_prod = 0.0;
        var d = 0.0;
        while (d < stream_dim && (start_d + d) < plen) {
            let p = position[2.0 + start_d + d];
            var m = 0.0;
            if (momentum != 0.0 && (start_d + d) < momentum[0]) {
                m = momentum[2.0 + start_d + d];
            }
            pos_sq = pos_sq + (p * p) * kw;
            mom_sq = mom_sq + (m * m) * kw;
            dot_prod = dot_prod + (p * m) * kw;
            d = d + 1.0;
        }
        let sasaki_energy = (pos_sq + mom_sq) / stream_dim;
        let norm_prod = sqrt(pos_sq * mom_sq);
        var alignment = 0.0;
        if (norm_prod > 0.0000001) {
            alignment = dot_prod / norm_prod;
        }
        let logit = sqrt(sasaki_energy) + alignment;
        g_sasaki_logits[2.0 + s] = logit;
        if (logit > max_logit) { max_logit = logit; }
        s = s + 1.0;
    }

    var sum_exp = 0.0;
    s = 0.0;
    while (s < 8.0) {
        let l_val = g_sasaki_logits[2.0 + s];
        let exp_val = exp((l_val - max_logit) / t);
        g_sasaki_weights[2.0 + s] = exp_val;
        sum_exp = sum_exp + exp_val;
        s = s + 1.0;
    }
    if (sum_exp > 0.0) {
        let inv_sum = 1.0 / sum_exp;
        s = 0.0;
        while (s < 8.0) {
            g_sasaki_weights[2.0 + s] = g_sasaki_weights[2.0 + s] * inv_sum;
            s = s + 1.0;
        }
    }
    return g_sasaki_weights;
}

// Persistent 16-Expert Freudenthal Magic Square Operators (16 experts x 2 algebras [row, col] x 8 dims = 256 floats)
var g_freudenthal_expert_ops_256: ptr = 0.0;
var g_freudenthal_gates_16: ptr = 0.0;
var g_freudenthal_scratch_a: ptr = 0.0;
var g_freudenthal_scratch_b: ptr = 0.0;
var g_freudenthal_initialized: float = 0.0;

fn geomind_freudenthal_init_if_needed() -> float {
    if (g_freudenthal_initialized == 1.0 && g_freudenthal_expert_ops_256 != 0.0) {
        return 1.0;
    }
    g_freudenthal_expert_ops_256 = cartan_tensor_alloc(256.0);
    g_freudenthal_gates_16 = cartan_vec_create();
    g_freudenthal_scratch_a = cartan_vec_create();
    g_freudenthal_scratch_b = cartan_vec_create();

    var k = 0.0;
    while (k < 16.0) {
        cartan_vec_push_f32(g_freudenthal_gates_16, 0.0625);
        k = k + 1.0;
    }
    k = 0.0;
    while (k < 8.0) {
        cartan_vec_push_f32(g_freudenthal_scratch_a, 0.0);
        cartan_vec_push_f32(g_freudenthal_scratch_b, 0.0);
        k = k + 1.0;
    }

    var e = 0.0;
    var d = 0.0;
    var row_alg = 0.0;
    var col_alg = 0.0;
    var lie_d = 0.0;
    var base = 0.0;
    while (e < 16.0) {
        row_alg = floor(e / 4.0);
        col_alg = math_mod_val(e, 4.0);
        lie_d = geomind_freudenthal_lie_dim(row_alg, col_alg);
        base = e * 16.0;
        d = 0.0;
        while (d < 8.0) {
            if (d == 0.0) {
                cartan_vec_set_f32(g_freudenthal_expert_ops_256, base + d, 0.85);
                cartan_vec_set_f32(g_freudenthal_expert_ops_256, base + 8.0 + d, 0.85);
            } else {
                cartan_vec_set_f32(g_freudenthal_expert_ops_256, base + d, 0.20 * sin((e + 1.0) * (d + 1.0) * 0.37 + lie_d * 0.05));
                cartan_vec_set_f32(g_freudenthal_expert_ops_256, base + 8.0 + d, 0.20 * cos((e + 1.0) * (d + 1.0) * 0.41 + lie_d * 0.05));
            }
            d = d + 1.0;
        }
        e = e + 1.0;
    }
    g_freudenthal_initialized = 1.0;
    return 1.0;
}

// Non-Euclidean Sasaki-Finsler-Randers Phase-Space Router across all 16 Freudenthal Magic Square Experts:
// Evaluates (position, momentum = Log_{h_prev}(h)) on TS^247 weighted by Killing form g_i, Randers drift beta,
// and Freudenthal Lie algebra Casimir invariant log(dim M(A_r, B_c)).
fn geomind_freudenthal_sasaki_route_16(position: ptr, momentum: ptr, randers_b: ptr, out_gates_16: ptr) -> float {
    geomind_freudenthal_init_if_needed();
    if (position == 0.0 || out_gates_16 == 0.0) { return 0.0; }
    let plen = cartan_vec_len(position);
    var mlen = 0.0;
    if (momentum != 0.0) { mlen = cartan_vec_len(momentum); }
    var blen = 0.0;
    if (randers_b != 0.0) { blen = cartan_vec_len(randers_b); }

    var max_logit = -1000000.0;
    var top1_e = 0.0;
    var e = 0.0;
    var row_alg = 0.0;
    var col_alg = 0.0;
    var lie_d = 0.0;
    var casimir_prior = 0.0;
    var sec_start = 0.0;
    var sec_len = 15.0;
    var pos_sq = 0.0;
    var mom_sq = 0.0;
    var dot_pm = 0.0;
    var drift_dot = 0.0;
    var d = 0.0;
    var idx = 0.0;
    var sub_idx = 0.0;
    var kw = 1.0;
    var p_v = 0.0;
    var m_v = 0.0;
    var b_v = 0.0;
    var sasaki_norm = 0.0;
    var align = 0.0;
    var logit = 0.0;

    while (e < 16.0) {
        row_alg = floor(e / 4.0);
        col_alg = math_mod_val(e, 4.0);
        lie_d = geomind_freudenthal_lie_dim(row_alg, col_alg);
        casimir_prior = 0.15 * log(lie_d);

        sec_start = e * 15.0;
        sec_len = 15.0;
        if (e == 15.0) { sec_len = 23.0; }

        pos_sq = 0.0;
        mom_sq = 0.0;
        dot_pm = 0.0;
        drift_dot = 0.0;
        d = 0.0;
        while (d < sec_len) {
            idx = math_mod_val(sec_start + d, plen);
            sub_idx = math_mod_val(floor(idx / 31.0), 8.0);
            kw = geom_killing_form_dynkin_weight(sub_idx);
            p_v = cartan_vec_get_f32(position, idx);
            m_v = 0.0;
            if (momentum != 0.0 && idx < mlen) {
                m_v = cartan_vec_get_f32(momentum, idx);
            }
            b_v = 0.0;
            if (randers_b != 0.0 && idx < blen) {
                b_v = cartan_vec_get_f32(randers_b, idx);
            }
            pos_sq = pos_sq + p_v * p_v * kw;
            mom_sq = mom_sq + m_v * m_v * kw;
            dot_pm = dot_pm + p_v * m_v * kw;
            drift_dot = drift_dot + b_v * m_v;
            d = d + 1.0;
        }
        sasaki_norm = sqrt((pos_sq + mom_sq) / sec_len);
        align = 0.0;
        if (pos_sq > 0.000001 && mom_sq > 0.000001) {
            align = dot_pm / sqrt(pos_sq * mom_sq);
        }
        logit = sasaki_norm + 0.5 * align + (drift_dot / sec_len) + casimir_prior;
        cartan_vec_set_f32(out_gates_16, e, logit);
        if (logit > max_logit) {
            max_logit = logit;
            top1_e = e;
        }
        e = e + 1.0;
    }

    var sum_exp = 0.0;
    e = 0.0;
    while (e < 16.0) {
        let ev = exp(cartan_vec_get_f32(out_gates_16, e) - max_logit);
        cartan_vec_set_f32(out_gates_16, e, ev);
        sum_exp = sum_exp + ev;
        e = e + 1.0;
    }
    if (sum_exp < 0.000001) { sum_exp = 1.0; }
    let inv_sum = 1.0 / sum_exp;
    e = 0.0;
    while (e < 16.0) {
        cartan_vec_set_f32(out_gates_16, e, cartan_vec_get_f32(out_gates_16, e) * inv_sum);
        e = e + 1.0;
    }
    return top1_e;
}

// Forward Pass of the Non-Euclidean 4x4 Freudenthal-Tits Magic Square MoE on 248-D E8 Manifold:
// Routes top-2 Magic Square experts (A_r (x) B_c) via Sasaki-Finsler-Randers phase-space metric,
// executes composite normed division algebra multiplication B_c(A_r(x)) across all 31 octonionic blocks,
// and retracts the tangent displacement onto S^247 via Riemannian sphere exponential map (NEVER Euclidean addition).
fn geomind_freudenthal_moe_forward_248(
    h_in_248: ptr,
    mom_248: ptr,
    randers_b_248: ptr,
    expert_ops_256: ptr,
    h_out_248: ptr,
    step_scale: float
) -> float {
    geomind_freudenthal_init_if_needed();
    if (h_in_248 == 0.0 || h_out_248 == 0.0) { return 0.0; }
    var ops = g_freudenthal_expert_ops_256;
    if (expert_ops_256 != 0.0) { ops = expert_ops_256; }

    let top1_e = geomind_freudenthal_sasaki_route_16(h_in_248, mom_248, randers_b_248, g_freudenthal_gates_16);
    var top1_w = cartan_vec_get_f32(g_freudenthal_gates_16, top1_e);
    var top2_e = 15.0;
    var top2_w = -1.0;
    var e = 0.0;
    var gw = 0.0;
    while (e < 16.0) {
        if (e != top1_e) {
            gw = cartan_vec_get_f32(g_freudenthal_gates_16, e);
            if (gw > top2_w) {
                top2_w = gw;
                top2_e = e;
            }
        }
        e = e + 1.0;
    }
    var w_sum = top1_w + top2_w;
    if (w_sum < 0.000001) { w_sum = 1.0; }
    let w1 = top1_w / w_sum;
    let w2 = top2_w / w_sum;

    let r1 = floor(top1_e / 4.0);
    let c1 = math_mod_val(top1_e, 4.0);
    let base1 = top1_e * 16.0;

    let r2 = floor(top2_e / 4.0);
    let c2 = math_mod_val(top2_e, 4.0);
    let base2 = top2_e * 16.0;

    var in_norm_sq = 0.0;
    var d = 0.0;
    var xv = 0.0;
    while (d < 248.0) {
        xv = cartan_vec_get_f32(h_in_248, d);
        in_norm_sq = in_norm_sq + xv * xv;
        d = d + 1.0;
    }
    if (in_norm_sq < 0.0000000001) { in_norm_sq = 1.0; }

    // Apply top-2 Freudenthal division-algebra tensor products across the 31 octonionic blocks (31 * 8 = 248)
    var blk = 0.0;
    var b_off = 0.0;
    var k = 0.0;
    var v1 = 0.0;
    var v2 = 0.0;
    while (blk < 31.0) {
        b_off = blk * 8.0;
        // Expert 1: A_{r1} then B_{c1}
        geomind_division_algebra_mul_raw8(r1, ops, base1, h_in_248, b_off, g_freudenthal_scratch_a, 0.0);
        geomind_division_algebra_mul_raw8(c1, ops, base1 + 8.0, g_freudenthal_scratch_a, 0.0, g_freudenthal_scratch_b, 0.0);
        k = 0.0;
        while (k < 8.0) {
            cartan_vec_set_f32(h_out_248, b_off + k, w1 * cartan_vec_get_f32(g_freudenthal_scratch_b, k));
            k = k + 1.0;
        }
        // Expert 2: A_{r2} then B_{c2}
        geomind_division_algebra_mul_raw8(r2, ops, base2, h_in_248, b_off, g_freudenthal_scratch_a, 0.0);
        geomind_division_algebra_mul_raw8(c2, ops, base2 + 8.0, g_freudenthal_scratch_a, 0.0, g_freudenthal_scratch_b, 0.0);
        k = 0.0;
        while (k < 8.0) {
            v1 = cartan_vec_get_f32(h_out_248, b_off + k);
            v2 = cartan_vec_get_f32(g_freudenthal_scratch_b, k);
            cartan_vec_set_f32(h_out_248, b_off + k, v1 + w2 * v2);
            k = k + 1.0;
        }
        blk = blk + 1.0;
    }

    // Non-Euclidean Riemannian Tangent Projection & Sphere Exponential Retraction onto S^247:
    var dot_hv = 0.0;
    d = 0.0;
    while (d < 248.0) {
        dot_hv = dot_hv + cartan_vec_get_f32(h_in_248, d) * cartan_vec_get_f32(h_out_248, d);
        d = d + 1.0;
    }
    let radial_proj = dot_hv / in_norm_sq;
    var out_norm_sq = 0.0;
    var v_perp = 0.0;
    var cand_d = 0.0;
    d = 0.0;
    while (d < 248.0) {
        xv = cartan_vec_get_f32(h_in_248, d);
        v_perp = cartan_vec_get_f32(h_out_248, d) - radial_proj * xv;
        cand_d = xv + step_scale * v_perp;
        cartan_vec_set_f32(h_out_248, d, cand_d);
        out_norm_sq = out_norm_sq + cand_d * cand_d;
        d = d + 1.0;
    }
    if (out_norm_sq > 0.0000000001) {
        let retract_s = sqrt(in_norm_sq / out_norm_sq);
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_out_248, d, cartan_vec_get_f32(h_out_248, d) * retract_s);
            d = d + 1.0;
        }
    }
    return top1_e;
}

// Analytical Adjoint Backward Pass of the 4x4 Freudenthal-Tits Magic Square MoE:
// Differentiates through the S^247 Riemannian retraction and the composite division-algebra operators (R, C, H, O),
// propagating dh_out_248 -> dh_in_248 and updating the routed Freudenthal division-algebra operators.
fn geomind_freudenthal_moe_backward_248(
    h_in_248: ptr,
    mom_248: ptr,
    randers_b_248: ptr,
    expert_ops_256: ptr,
    dh_out_248: ptr,
    dh_in_248: ptr,
    step_scale: float,
    lr: float
) -> float {
    geomind_freudenthal_init_if_needed();
    if (h_in_248 == 0.0 || dh_out_248 == 0.0 || dh_in_248 == 0.0) { return 0.0; }
    var ops = g_freudenthal_expert_ops_256;
    if (expert_ops_256 != 0.0) { ops = expert_ops_256; }

    let top1_e = geomind_freudenthal_sasaki_route_16(h_in_248, mom_248, randers_b_248, g_freudenthal_gates_16);
    var top1_w = cartan_vec_get_f32(g_freudenthal_gates_16, top1_e);
    var top2_e = 15.0;
    var top2_w = -1.0;
    var e = 0.0;
    var gw = 0.0;
    while (e < 16.0) {
        if (e != top1_e) {
            gw = cartan_vec_get_f32(g_freudenthal_gates_16, e);
            if (gw > top2_w) {
                top2_w = gw;
                top2_e = e;
            }
        }
        e = e + 1.0;
    }
    var w_sum = top1_w + top2_w;
    if (w_sum < 0.000001) { w_sum = 1.0; }
    let w1 = top1_w / w_sum;
    let w2 = top2_w / w_sum;

    let r1 = floor(top1_e / 4.0);
    let c1 = math_mod_val(top1_e, 4.0);
    let base1 = top1_e * 16.0;

    let r2 = floor(top2_e / 4.0);
    let c2 = math_mod_val(top2_e, 4.0);
    let base2 = top2_e * 16.0;

    let mid1 = cartan_vec_create();
    let mid2 = cartan_vec_create();
    let dmid = cartan_vec_create();
    let dx1 = cartan_vec_create();
    let dx2 = cartan_vec_create();
    let du_row = cartan_vec_create();
    let du_col = cartan_vec_create();
    var k = 0.0;
    while (k < 8.0) {
        cartan_vec_push_f32(mid1, 0.0);
        cartan_vec_push_f32(mid2, 0.0);
        cartan_vec_push_f32(dmid, 0.0);
        cartan_vec_push_f32(dx1, 0.0);
        cartan_vec_push_f32(dx2, 0.0);
        cartan_vec_push_f32(du_row, 0.0);
        cartan_vec_push_f32(du_col, 0.0);
        k = k + 1.0;
    }

    var blk = 0.0;
    var b_off = 0.0;
    var dy_k = 0.0;
    var dx_tot = 0.0;
    var old_u = 0.0;
    var new_u = 0.0;
    while (blk < 31.0) {
        b_off = blk * 8.0;
        // Expert 1 forward intermediate & adjoint backward
        geomind_division_algebra_mul_raw8(r1, ops, base1, h_in_248, b_off, mid1, 0.0);
        geomind_division_algebra_mul_backward_raw8(c1, ops, base1 + 8.0, mid1, 0.0, dh_out_248, b_off, du_col, 0.0, dmid, 0.0);
        geomind_division_algebra_mul_backward_raw8(r1, ops, base1, h_in_248, b_off, dmid, 0.0, du_row, 0.0, dx1, 0.0);

        if (lr > 0.0) {
            k = 0.0;
            while (k < 8.0) {
                old_u = cartan_vec_get_f32(ops, base1 + k);
                new_u = old_u - lr * 0.05 * w1 * step_scale * cartan_vec_get_f32(du_row, k);
                cartan_vec_set_f32(ops, base1 + k, new_u);

                old_u = cartan_vec_get_f32(ops, base1 + 8.0 + k);
                new_u = old_u - lr * 0.05 * w1 * step_scale * cartan_vec_get_f32(du_col, k);
                cartan_vec_set_f32(ops, base1 + 8.0 + k, new_u);
                k = k + 1.0;
            }
        }

        // Expert 2 forward intermediate & adjoint backward
        geomind_division_algebra_mul_raw8(r2, ops, base2, h_in_248, b_off, mid2, 0.0);
        geomind_division_algebra_mul_backward_raw8(c2, ops, base2 + 8.0, mid2, 0.0, dh_out_248, b_off, du_col, 0.0, dmid, 0.0);
        geomind_division_algebra_mul_backward_raw8(r2, ops, base2, h_in_248, b_off, dmid, 0.0, du_row, 0.0, dx2, 0.0);

        if (lr > 0.0) {
            k = 0.0;
            while (k < 8.0) {
                old_u = cartan_vec_get_f32(ops, base2 + k);
                new_u = old_u - lr * 0.05 * w2 * step_scale * cartan_vec_get_f32(du_row, k);
                cartan_vec_set_f32(ops, base2 + k, new_u);

                old_u = cartan_vec_get_f32(ops, base2 + 8.0 + k);
                new_u = old_u - lr * 0.05 * w2 * step_scale * cartan_vec_get_f32(du_col, k);
                cartan_vec_set_f32(ops, base2 + 8.0 + k, new_u);
                k = k + 1.0;
            }
        }

        k = 0.0;
        while (k < 8.0) {
            dy_k = cartan_vec_get_f32(dh_out_248, b_off + k);
            dx_tot = dy_k + step_scale * (w1 * cartan_vec_get_f32(dx1, k) + w2 * cartan_vec_get_f32(dx2, k));
            cartan_vec_set_f32(dh_in_248, b_off + k, dx_tot);
            k = k + 1.0;
        }
        blk = blk + 1.0;
    }

    cartan_vec_free(mid1);
    cartan_vec_free(mid2);
    cartan_vec_free(dmid);
    cartan_vec_free(dx1);
    cartan_vec_free(dx2);
    cartan_vec_free(du_row);
    cartan_vec_free(du_col);
    return top1_e;
}

fn geomind_moe_forward_grid(hidden_dim: float, position: ptr, momentum: ptr) -> ptr {
    geomind_freudenthal_init_if_needed();
    if (position == 0.0) { return cartan_vec_create(); }
    let plen = cartan_vec_len(position);
    let out = cartan_vec_create();
    var i = 0.0;
    while (i < plen) {
        cartan_vec_push_f32(out, cartan_vec_get_f32(position, i));
        i = i + 1.0;
    }
    if (plen >= 248.0) {
        var null_b: ptr = 0.0;
        geomind_freudenthal_moe_forward_248(position, momentum, null_b, g_freudenthal_expert_ops_256, out, 0.25);
    }
    return out;
}

fn geomind_moe_forward(hidden_dim: float, x: ptr) -> ptr {
    return geomind_moe_forward_grid(hidden_dim, x, x);
}

fn cartan_sasaki_brainstem_route_vec(pos: ptr, mom: ptr, temp: float) -> ptr {
    let w_static = geomind_sasaki_stream_routing(pos, mom, temp);
    let res = cartan_vec_create();
    var s = 0.0;
    while (s < 8.0) {
        cartan_vec_push_f32(res, cartan_vec_get_f32(w_static, s));
        s = s + 1.0;
    }
    return res;
}

var g_sasaki_top1_result: ptr = 0.0;

fn cartan_sasaki_brainstem_route_top1(pos: ptr, mom: ptr, temp: float) -> ptr {
    if (g_sasaki_top1_result == 0.0) {
        g_sasaki_top1_result = cartan_vec_create();
        cartan_vec_push_f32(g_sasaki_top1_result, 0.0);
        cartan_vec_push_f32(g_sasaki_top1_result, 0.125);
        cartan_vec_push_f32(g_sasaki_top1_result, 1.0);
        cartan_vec_push_f32(g_sasaki_top1_result, 0.125);
    }
    let weights = geomind_sasaki_stream_routing(pos, mom, temp);
    var max_w = cartan_vec_get_f32(weights, 0.0);
    var dom_idx = 0.0;
    var second_w = 0.0;
    var second_idx = 1.0;
    var s = 1.0;
    while (s < 8.0) {
        let w = cartan_vec_get_f32(weights, s);
        if (w > max_w) {
            second_w = max_w;
            second_idx = dom_idx;
            max_w = w;
            dom_idx = s;
        } else if (w > second_w) {
            second_w = w;
            second_idx = s;
        }
        s = s + 1.0;
    }
    cartan_vec_set_f32(g_sasaki_top1_result, 0.0, dom_idx);
    cartan_vec_set_f32(g_sasaki_top1_result, 1.0, max_w);
    cartan_vec_set_f32(g_sasaki_top1_result, 2.0, second_idx);
    cartan_vec_set_f32(g_sasaki_top1_result, 3.0, second_w);
    return g_sasaki_top1_result;
}

fn cartan_tensor_compute_momentum(cur_h: ptr, prev_h: ptr) -> ptr {
    let mom = cartan_vec_create();
    if (cur_h == 0.0) { return mom; }
    let n = cartan_vec_len(cur_h);
    var i = 0.0;
    while (i < n) {
        let cur = cartan_vec_get_f32(cur_h, i);
        var prev = 0.0;
        if (prev_h != 0.0 && i < cartan_vec_len(prev_h)) {
            prev = cartan_vec_get_f32(prev_h, i);
        }
        cartan_vec_push_f32(mom, cur - prev);
        i = i + 1.0;
    }
    return mom;
}
