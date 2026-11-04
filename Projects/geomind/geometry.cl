// test/geomind/geometry.cl
// GeoMind Production-Grade Lie Group E8 & Finsler-Randers-Sasaki (FRS) Geometry Engine

include "../../src/std/geom.cl";
include "../../src/std/math.cl";
include "../../src/std/collections.cl";

// Persistent global table of the 240 canonical E8 roots (240 vectors x 8 dimensions = 1920 floats)
var g_e8_roots_table: ptr = 0.0;
var g_e8_roots_initialized: float = 0.0;

// Initialize the 240 canonical E8 root vectors in R^8
// Length of every root vector is exactly sqrt(2), so ||alpha||^2 = 2.0
fn geomind_init_e8_roots_if_needed() -> float {
    if (g_e8_roots_initialized == 1.0 && g_e8_roots_table != 0.0) {
        return 240.0;
    }

    g_e8_roots_table = cartan_vec_create();
    var total_entries = 240.0 * 8.0;
    var idx = 0.0;
    while (idx < total_entries) {
        cartan_vec_push_f32(g_e8_roots_table, 0.0);
        idx = idx + 1.0;
    }

    var root_count = 0.0;

    // 1. Type A: 112 Integer Roots (+/- e_i +/- e_j for 0 <= i < j < 8)
    // 28 pairs x 4 sign permutations = 112 roots
    var i = 0.0;
    var j = 0.0;
    var base0 = 0.0;
    var base1 = 0.0;
    var base2 = 0.0;
    var base3 = 0.0;
    while (i < 8.0) {
        j = i + 1.0;
        while (j < 8.0) {
            // Sign combination 1: (+1, +1)
            base0 = root_count * 8.0;
            cartan_vec_set_f32(g_e8_roots_table, base0 + i, 1.0);
            cartan_vec_set_f32(g_e8_roots_table, base0 + j, 1.0);
            root_count = root_count + 1.0;

            // Sign combination 2: (+1, -1)
            base1 = root_count * 8.0;
            cartan_vec_set_f32(g_e8_roots_table, base1 + i, 1.0);
            cartan_vec_set_f32(g_e8_roots_table, base1 + j, -1.0);
            root_count = root_count + 1.0;

            // Sign combination 3: (-1, +1)
            base2 = root_count * 8.0;
            cartan_vec_set_f32(g_e8_roots_table, base2 + i, -1.0);
            cartan_vec_set_f32(g_e8_roots_table, base2 + j, 1.0);
            root_count = root_count + 1.0;

            // Sign combination 4: (-1, -1)
            base3 = root_count * 8.0;
            cartan_vec_set_f32(g_e8_roots_table, base3 + i, -1.0);
            cartan_vec_set_f32(g_e8_roots_table, base3 + j, -1.0);
            root_count = root_count + 1.0;

            j = j + 1.0;
        }
        i = i + 1.0;
    }

    // 2. Type B: 128 Half-Integer Roots ((+/- 1/2)^8 with even number of minus signs)
    // 2^8 / 2 = 128 roots
    var mask = 0.0;
    var minus_count = 0.0;
    var b = 0.0;
    var p2 = 0.0;
    var bit = 0.0;
    var base_b = 0.0;
    var val = 0.0;
    while (mask < 256.0) {
        minus_count = 0.0;
        b = 0.0;
        while (b < 8.0) {
            p2 = pow(2.0, b);
            bit = math_mod_val(floor(mask / p2), 2.0);
            if (bit == 1.0) {
                minus_count = minus_count + 1.0;
            }
            b = b + 1.0;
        }

        // Even number of minus signs condition (sum of coordinates is an even integer)
        if (math_mod_val(minus_count, 2.0) == 0.0) {
            base_b = root_count * 8.0;
            b = 0.0;
            while (b < 8.0) {
                p2 = pow(2.0, b);
                bit = math_mod_val(floor(mask / p2), 2.0);
                val = 0.5;
                if (bit == 1.0) { val = -0.5; }
                cartan_vec_set_f32(g_e8_roots_table, base_b + b, val);
                b = b + 1.0;
            }
            root_count = root_count + 1.0;
        }
        mask = mask + 1.0;
    }

    g_e8_roots_initialized = 1.0;
    return root_count;
}

// Get coordinate d of root index r (r in 0..239, d in 0..7)
fn geomind_e8_get_root_coord(root_idx: float, dim: float) -> float {
    geomind_init_e8_roots_if_needed();
    let r = math_mod_val(root_idx, 240.0);
    let d = math_mod_val(dim, 8.0);
    return cartan_vec_get_f32(g_e8_roots_table, r * 8.0 + d);
}

// Inner product between two E8 roots: <alpha, beta> in {-2, -1, 0, 1, 2}
fn geomind_e8_root_dot(root_a: float, root_b: float) -> float {
    geomind_init_e8_roots_if_needed();
    let r_a = math_mod_val(root_a, 240.0) * 8.0;
    let r_b = math_mod_val(root_b, 240.0) * 8.0;
    var dot = 0.0;
    var d = 0.0;
    while (d < 8.0) {
        let va = cartan_vec_get_f32(g_e8_roots_table, r_a + d);
        let vb = cartan_vec_get_f32(g_e8_roots_table, r_b + d);
        dot = dot + va * vb;
        d = d + 1.0;
    }
    return dot;
}

// Squared norm of E8 root: strictly 2.0
fn geomind_e8_root_norm_sq(root_idx: float) -> float {
    return geomind_e8_root_dot(root_idx, root_idx);
}

// Weyl Group Reflection Operator: s_alpha(v) = v - <v, alpha> * alpha
// Transforms vector v in R^8 by reflection across root hyperplane orthogonal to root_idx
fn geomind_weyl_reflect(v_in: ptr, root_idx: float, v_out: ptr) -> float {
    if (v_in == 0.0 || v_out == 0.0) { return 0.0; }
    geomind_init_e8_roots_if_needed();
    let r_base = math_mod_val(root_idx, 240.0) * 8.0;

    // Compute inner product <v, alpha>
    var dot_va = 0.0;
    var d = 0.0;
    while (d < 8.0) {
        let v_d = cartan_vec_get_f32(v_in, d);
        let alpha_d = cartan_vec_get_f32(g_e8_roots_table, r_base + d);
        dot_va = dot_va + v_d * alpha_d;
        d = d + 1.0;
    }

    // Apply reflection: s_alpha(v)_d = v_d - <v, alpha> * alpha_d
    d = 0.0;
    while (d < 8.0) {
        let v_d = cartan_vec_get_f32(v_in, d);
        let alpha_d = cartan_vec_get_f32(g_e8_roots_table, r_base + d);
        cartan_vec_set_f32(v_out, d, v_d - dot_va * alpha_d);
        d = d + 1.0;
    }
    return dot_va;
}

// Full 248D E8 Weyl Group Root Reflection Operator: s_alpha(v) = v - <v, alpha> * alpha
// Transforms vector v across all 31 Cartan octaves in-place; exactly norm-preserving on S^247
fn geomind_weyl_reflect_vector_248(v: ptr, root_idx: float) -> ptr {
    if (v == 0.0) { return v; }
    geomind_init_e8_roots_if_needed();
    let r_base = math_mod_val(root_idx, 240.0) * 8.0;
    let v_len = cartan_vec_len(v);
    let octaves = floor(v_len / 8.0);
    
    var oct = 0.0;
    while (oct < octaves) {
        let base = oct * 8.0;
        var dot = 0.0;
        var d = 0.0;
        while (d < 8.0) {
            let vd = cartan_vec_get_f32(v, base + d);
            let ad = cartan_vec_get_f32(g_e8_roots_table, r_base + d);
            dot = dot + vd * ad;
            d = d + 1.0;
        }
        d = 0.0;
        while (d < 8.0) {
            let vd = cartan_vec_get_f32(v, base + d);
            let ad = cartan_vec_get_f32(g_e8_roots_table, r_base + d);
            cartan_vec_set_f32(v, base + d, vd - dot * ad);
            d = d + 1.0;
        }
        oct = oct + 1.0;
    }
    return v;
}

// Project 8D Cartan subalgebra coordinate state into complete 248D E8 Lie algebra space:
// Dims 0..7: Cartan subalgebra coordinates h
// Dims 8..247: Adjoint root space projection amplitudes <h, alpha_r> for r in 0..239
fn geomind_project_cartan_to_e8_248(cartan_8d: ptr, out_248d: ptr) -> float {
    if (cartan_8d == 0.0 || out_248d == 0.0) { return 0.0; }
    geomind_init_e8_roots_if_needed();

    // 1. Copy 8 Cartan subalgebra coordinates
    var d = 0.0;
    while (d < 8.0) {
        let val = cartan_vec_get_f32(cartan_8d, d);
        cartan_vec_set_f32(out_248d, d, val);
        d = d + 1.0;
    }

    // 2. Compute 240 root space projection amplitudes
    var r = 0.0;
    while (r < 240.0) {
        let r_base = r * 8.0;
        var dot = 0.0;
        d = 0.0;
        while (d < 8.0) {
            let h_d = cartan_vec_get_f32(cartan_8d, d);
            let alpha_d = cartan_vec_get_f32(g_e8_roots_table, r_base + d);
            dot = dot + h_d * alpha_d;
            d = d + 1.0;
        }
        // Amplitude in root space g_alpha
        cartan_vec_set_f32(out_248d, 8.0 + r, dot);
        r = r + 1.0;
    }
    return 248.0;
}

// Backward compatibility bridge for lattice root coordinate projection
fn geomind_project_to_e8_lattice(idx: float, dim: float) -> float {
    return geomind_e8_get_root_coord(idx, dim);
}

// ============================================================================
// PHASE 1: E8 = so(16) (+) S_16^+ (120-D GAUGE (+) 128-D SPINOR) CROSS-GATING
// ============================================================================
// Extracts the 120-D so(16) Bosonic Gauge Sector (dims [0..119]: 8 Cartan + 112 integer roots)
fn geomind_e8_extract_gauge_120(v_248: ptr, out_120: ptr) -> float {
    if (v_248 == 0.0 || out_120 == 0.0) { return 0.0; }
    var d = 0.0;
    while (d < 120.0) {
        cartan_vec_set_f32(out_120, d, cartan_vec_get_f32(v_248, d));
        d = d + 1.0;
    }
    return 120.0;
}

// Extracts the 128-D S_16^+ Majorana-Weyl Spinor Sector (dims [120..247]: 128 half-integer roots)
fn geomind_e8_extract_spinor_128(v_248: ptr, out_128: ptr) -> float {
    if (v_248 == 0.0 || out_128 == 0.0) { return 0.0; }
    var d = 0.0;
    while (d < 128.0) {
        cartan_vec_set_f32(out_128, d, cartan_vec_get_f32(v_248, 120.0 + d));
        d = d + 1.0;
    }
    return 128.0;
}

// Persistent scratch buffers for 248-D E8 Gauge-on-Spinor Cross-Gating
var g_e8_gs_oct_a: ptr = 0.0;
var g_e8_gs_oct_b: ptr = 0.0;
var g_e8_gs_oct_c: ptr = 0.0;
var g_e8_gs_temp_248: ptr = 0.0;

fn geomind_init_e8_gs_scratch_if_needed() {
    if (g_e8_gs_oct_a == 0.0) {
        g_e8_gs_oct_a = cartan_vec_create();
        g_e8_gs_oct_b = cartan_vec_create();
        g_e8_gs_oct_c = cartan_vec_create();
        var k = 0.0;
        while (k < 8.0) {
            cartan_vec_push_f32(g_e8_gs_oct_a, 0.0);
            cartan_vec_push_f32(g_e8_gs_oct_b, 0.0);
            cartan_vec_push_f32(g_e8_gs_oct_c, 0.0);
            k = k + 1.0;
        }
    }
    if (g_e8_gs_temp_248 == 0.0) {
        g_e8_gs_temp_248 = cartan_vec_create();
        var d = 0.0;
        while (d < 248.0) {
            cartan_vec_push_f32(g_e8_gs_temp_248, 0.0);
            d = d + 1.0;
        }
    }
}

// Executes the Lie algebra bracket [so(16), S_16^+] -> S_16^+ and [S_16^+, S_16^+] -> so(16)
// on a single 248-D E8 block at offset `in_off`, writing the norm-preserved result to `out_vec` at `out_off`.
fn geomind_e8_gauge_spinor_cross_gate_block248(
    v_in: ptr,
    in_off: float,
    out_vec: ptr,
    out_off: float,
    eps: float
) -> float {
    if (v_in == 0.0 || out_vec == 0.0) { return 0.0; }
    geomind_init_e8_roots_if_needed();
    geomind_init_e8_gs_scratch_if_needed();

    var coup = 0.25;
    if (eps > 0.001 && eps <= 1.0) { coup = eps; }

    // Measure input Killing norm squared on the 248-D block for exact S^247 norm preservation
    var in_norm_sq = 0.0;
    var d = 0.0;
    var val = 0.0;
    while (d < 248.0) {
        val = cartan_vec_get_f32(v_in, in_off + d);
        cartan_vec_set_f32(g_e8_gs_temp_248, d, val);
        in_norm_sq = in_norm_sq + val * val;
        d = d + 1.0;
    }
    if (in_norm_sq < 0.0000000001) {
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(out_vec, out_off + d, 0.0);
            d = d + 1.0;
        }
        return 0.0;
    }

    // 1. GAUGE-ON-SPINOR ACTION: [so(16), S_16^+] -> S_16^+ (120 x 128 -> 128)
    var spin_blk = 0.0;
    var s_base = 0.0;
    var g_blk = 0.0;
    var g_base = 0.0;
    var g_norm_sq = 0.0;
    var k = 0.0;
    var gv = 0.0;
    var sv = 0.0;
    var g_inv = 1.0;
    var s_idx = 0.0;
    var root_r = 0.0;
    var cartan_dot = 0.0;
    var cd = 0.0;
    var h_cd = 0.0;
    var alpha_cd = 0.0;
    var orig_s = 0.0;
    var oct_rot = 0.0;
    var cartan_gate = 0.0;
    var new_s = 0.0;
    while (spin_blk < 16.0) {
        s_base = 120.0 + spin_blk * 8.0;
        g_blk = math_mod_val(spin_blk, 15.0);
        g_base = g_blk * 8.0;

        g_norm_sq = 0.0;
        k = 0.0;
        while (k < 8.0) {
            gv = cartan_vec_get_f32(v_in, in_off + g_base + k);
            g_norm_sq = g_norm_sq + gv * gv;
            k = k + 1.0;
        }
        g_inv = 1.0;
        if (g_norm_sq > 0.000001) { g_inv = 1.0 / sqrt(g_norm_sq); }

        k = 0.0;
        while (k < 8.0) {
            gv = cartan_vec_get_f32(v_in, in_off + g_base + k) * g_inv;
            sv = cartan_vec_get_f32(v_in, in_off + s_base + k);
            cartan_vec_set_f32(g_e8_gs_oct_a, k, gv);
            cartan_vec_set_f32(g_e8_gs_oct_b, k, sv);
            k = k + 1.0;
        }

        geom_octonion_mul_raw8(g_e8_gs_oct_a, 0.0, g_e8_gs_oct_b, 0.0, g_e8_gs_oct_c, 0.0);

        k = 0.0;
        while (k < 8.0) {
            s_idx = spin_blk * 8.0 + k;
            root_r = (112.0 + s_idx) * 8.0;
            cartan_dot = 0.0;
            cd = 0.0;
            while (cd < 8.0) {
                h_cd = cartan_vec_get_f32(v_in, in_off + cd);
                alpha_cd = cartan_vec_get_f32(g_e8_roots_table, root_r + cd);
                cartan_dot = cartan_dot + h_cd * alpha_cd;
                cd = cd + 1.0;
            }
            orig_s = cartan_vec_get_f32(v_in, in_off + s_base + k);
            oct_rot = cartan_vec_get_f32(g_e8_gs_oct_c, k);
            cartan_gate = tanh(cartan_dot * 0.5);
            new_s = orig_s + coup * (oct_rot + cartan_gate * orig_s);
            cartan_vec_set_f32(g_e8_gs_temp_248, s_base + k, new_s);
            k = k + 1.0;
        }
        spin_blk = spin_blk + 1.0;
    }

    // 2. SPINOR-ON-GAUGE BACK-REACTION: [S_16^+, S_16^+] -> so(16) (128 x 128 -> 120)
    var gauge_blk = 0.0;
    var s_base_a = 0.0;
    var s_base_b = 0.0;
    var s_norm_sq = 0.0;
    var sa = 0.0;
    var s_inv = 1.0;
    var orig_g = 0.0;
    var cur_j = 0.0;
    while (gauge_blk < 15.0) {
        g_base = gauge_blk * 8.0;
        s_base_a = 120.0 + gauge_blk * 8.0;
        s_base_b = 120.0 + (gauge_blk + 1.0) * 8.0;

        s_norm_sq = 0.0;
        k = 0.0;
        while (k < 8.0) {
            sa = cartan_vec_get_f32(v_in, in_off + s_base_a + k);
            s_norm_sq = s_norm_sq + sa * sa;
            k = k + 1.0;
        }
        s_inv = 1.0;
        if (s_norm_sq > 0.000001) { s_inv = 1.0 / sqrt(s_norm_sq); }

        cartan_vec_set_f32(g_e8_gs_oct_a, 0.0, cartan_vec_get_f32(v_in, in_off + s_base_a + 0.0) * s_inv);
        k = 1.0;
        while (k < 8.0) {
            cartan_vec_set_f32(g_e8_gs_oct_a, k, 0.0 - cartan_vec_get_f32(v_in, in_off + s_base_a + k) * s_inv);
            k = k + 1.0;
        }
        k = 0.0;
        while (k < 8.0) {
            cartan_vec_set_f32(g_e8_gs_oct_b, k, cartan_vec_get_f32(v_in, in_off + s_base_b + k));
            k = k + 1.0;
        }

        geom_octonion_mul_raw8(g_e8_gs_oct_a, 0.0, g_e8_gs_oct_b, 0.0, g_e8_gs_oct_c, 0.0);

        k = 0.0;
        while (k < 8.0) {
            orig_g = cartan_vec_get_f32(v_in, in_off + g_base + k);
            cur_j = cartan_vec_get_f32(g_e8_gs_oct_c, k);
            cartan_vec_set_f32(g_e8_gs_temp_248, g_base + k, orig_g + (0.5 * coup) * cur_j);
            k = k + 1.0;
        }
        gauge_blk = gauge_blk + 1.0;
    }

    // 3. EXACT S^247 KILLING-FORM NORM RETRACTION
    var out_norm_sq = 0.0;
    var tv = 0.0;
    d = 0.0;
    while (d < 248.0) {
        tv = cartan_vec_get_f32(g_e8_gs_temp_248, d);
        out_norm_sq = out_norm_sq + tv * tv;
        d = d + 1.0;
    }
    var retract_scale = 1.0;
    if (out_norm_sq > 0.0000000001) {
        retract_scale = sqrt(in_norm_sq / out_norm_sq);
    }
    d = 0.0;
    while (d < 248.0) {
        tv = cartan_vec_get_f32(g_e8_gs_temp_248, d) * retract_scale;
        cartan_vec_set_f32(out_vec, out_off + d, tv);
        d = d + 1.0;
    }
    return sqrt(in_norm_sq);
}

// Applies 120-D (+) 128-D E8 Gauge-on-Spinor Cross-Gating across any manifold tensor:
// - 248-D:  1 x 248-D E8 block
// - 1984-D: 8 x 248-D E8 blocks
// - 2560-D: 10 x 248-D E8 blocks + 80-D Cartan phase anchor (10 x 8-D)
fn geomind_e8_gauge_spinor_cross_gate(v_in: ptr, out_vec: ptr, eps: float) -> float {
    if (v_in == 0.0 || out_vec == 0.0) { return 0.0; }
    let len = cartan_vec_len(v_in);
    if (len < 248.0) {
        var i = 0.0;
        while (i < len) {
            cartan_vec_set_f32(out_vec, i, cartan_vec_get_f32(v_in, i));
            i = i + 1.0;
        }
        return len;
    }

    let num_blocks = floor(len / 248.0);
    var blk = 0.0;
    while (blk < num_blocks) {
        let off = blk * 248.0;
        geomind_e8_gauge_spinor_cross_gate_block248(v_in, off, out_vec, off, eps);
        blk = blk + 1.0;
    }

    // Handle trailing Cartan phase anchor dimensions (e.g. dims 2480..2559 in 2560-D hidden states)
    let rem_start = num_blocks * 248.0;
    if (rem_start < len) {
        var r = rem_start;
        while (r < len) {
            let blk_idx = math_mod_val(floor((r - rem_start) / 8.0), num_blocks);
            let c_dim = math_mod_val(r - rem_start, 8.0);
            let v_orig = cartan_vec_get_f32(v_in, r);
            let h_coupled = cartan_vec_get_f32(out_vec, blk_idx * 248.0 + c_dim);
            cartan_vec_set_f32(out_vec, r, v_orig * 0.85 + h_coupled * 0.15);
            r = r + 1.0;
        }
    }
    return len;
}

// ============================================================================
// FINSLER-RANDERS-SASAKI (FRS) BRAINSTEM ROUTER ENGINE
// ============================================================================
// Computes asymmetric Finsler-Randers phase-space geodesic distance on TM:
// F_FRS((x, x_dot), (y, y_dot)) = sqrt(g_Sasaki((x, x_dot), (y, y_dot))) + tilde{beta}_drift(y - x)
// Enforces strict Finsler convexity ||tilde{beta}||_{g^{-1}} <= 0.95 < 1.0 via smooth tanh bounding.
fn geomind_frs_brainstem_distance(
    pos1: ptr, mom1: ptr,
    pos2: ptr, mom2: ptr,
    drift_b: ptr,
    dim: float
) -> float {
    if (pos1 == 0.0 || pos2 == 0.0 || dim <= 0.0) { return 0.0; }

    var sum_pos_sq = 0.0;
    var sum_mom_sq = 0.0;
    var sum_cross = 0.0;
    var sum_drift = 0.0;
    var norm_b_sq = 0.0;

    var stride = 31.0;
    if (dim >= 2560.0) { stride = 320.0; }
    else if (dim >= 1984.0) { stride = 248.0; }

    var d = 0.0;
    while (d < dim) {
        let p1 = cartan_vec_get_f32(pos1, d);
        let p2 = cartan_vec_get_f32(pos2, d);
        // Causal displacement vector from pos1 -> pos2
        let dp = p2 - p1;

        var dm = 0.0;
        if (mom1 != 0.0 && mom2 != 0.0) {
            let m1 = cartan_vec_get_f32(mom1, d);
            let m2 = cartan_vec_get_f32(mom2, d);
            dm = m2 - m1;
        }

        // Submanifold Killing-Cartan Dynkin weight g_d across dynamic Lie sectors
        let sub_idx = math_mod_val(floor(d / stride), 8.0);
        let g_d = geom_killing_form_dynkin_weight(sub_idx);

        sum_pos_sq = sum_pos_sq + g_d * dp * dp;
        sum_mom_sq = sum_mom_sq + g_d * dm * dm;
        sum_cross = sum_cross + 0.10 * g_d * dp * dm;

        if (drift_b != 0.0) {
            let b_d = cartan_vec_get_f32(drift_b, d);
            norm_b_sq = norm_b_sq + (b_d * b_d) / g_d;
            sum_drift = sum_drift + b_d * (dp + 0.25 * dm);
        } else if (mom1 != 0.0) {
            // Intrinsic causal drift derived from initial tangent velocity mom1
            let m1 = cartan_vec_get_f32(mom1, d);
            norm_b_sq = norm_b_sq + (m1 * m1) / g_d;
            sum_drift = sum_drift + m1 * dp;
        }

        d = d + 1.0;
    }

    let sasaki_sq = sum_pos_sq + sum_mom_sq + sum_cross;
    var alpha = 0.0;
    if (sasaki_sq > 0.0) {
        alpha = sqrt(sasaki_sq);
    }

    // Smoothly bound drift 1-form ||tilde{beta}||_{g^{-1}} <= 0.95 < 1.0 for strict Finsler convexity
    var bounded_drift = 0.0;
    let norm_b = sqrt(norm_b_sq);
    if (norm_b > 0.000001) {
        let beta_scale = 0.95 * (tanh(norm_b) / norm_b);
        bounded_drift = sum_drift * beta_scale;
    }

    // FRS asymmetric metric: alpha (Riemannian-Sasaki norm) + bounded_drift (Randers 1-form)
    let frs_dist = alpha + bounded_drift;
    if (frs_dist < 0.0) { return 0.0; }
    return frs_dist;
}

// Persistent static scratch buffers for FRS Brainstem Router
var g_frs_stream_weights: ptr = 0.0;
var g_frs_stream_logits: ptr = 0.0;

// FRS Brainstem 8-Stream Routing: Dispatches incoming phase-space packet (x, x_dot)
// across the 8 Lie stream submanifolds with 120-D (+) 128-D Gauge-Spinor coupling
// and bounded Finsler-Randers directional drift
fn geomind_frs_stream_routing(position: ptr, momentum: ptr, temp: float) -> ptr {
    if (g_frs_stream_weights == 0.0) {
        g_frs_stream_weights = cartan_vec_create();
        g_frs_stream_logits = cartan_vec_create();
        var init_s = 0.0;
        while (init_s < 8.0) {
            cartan_vec_push_f32(g_frs_stream_weights, 0.125);
            cartan_vec_push_f32(g_frs_stream_logits, 0.0);
            init_s = init_s + 1.0;
        }
    }
    if (position == 0.0) {
        var s = 0.0;
        while (s < 8.0) {
            cartan_vec_set_f32(g_frs_stream_weights, s, 0.125);
            s = s + 1.0;
        }
        return g_frs_stream_weights;
    }

    var t = 0.70;
    if (temp > 0.05) { t = temp; }
    let plen = cartan_vec_len(position);
    var max_logit = -1000000.0;

    var stride = 31.0;
    if (plen >= 2560.0) { stride = 320.0; }
    else if (plen >= 1984.0) { stride = 248.0; }

    var s = 0.0;
    while (s < 8.0) {
        let start_d = s * stride;
        let kw = geom_killing_form_dynkin_weight(s);
        let gauge_split = floor(stride * (120.0 / 248.0));
        var pos_sq = 0.0;
        var mom_sq = 0.0;
        var dot_prod = 0.0;
        var drift_dot = 0.0;
        var norm_b_sq = 0.0;
        var gauge_energy = 0.0;
        var spinor_energy = 0.0;

        var d = 0.0;
        while (d < stride && (start_d + d) < plen) {
            let p = cartan_vec_get_f32(position, start_d + d);
            var m = 0.0;
            if (momentum != 0.0 && (start_d + d) < cartan_vec_len(momentum)) {
                m = cartan_vec_get_f32(momentum, start_d + d);
            }
            pos_sq = pos_sq + (p * p) * kw;
            mom_sq = mom_sq + (m * m) * kw;
            dot_prod = dot_prod + (p * m) * kw;
            if (d < gauge_split) {
                gauge_energy = gauge_energy + (p * p);
            } else {
                spinor_energy = spinor_energy + (p * p);
            }
            // Randers causal drift 1-form beta_d along active velocity m_d
            norm_b_sq = norm_b_sq + (p * p) / kw;
            drift_dot = drift_dot + p * m;
            d = d + 1.0;
        }

        let sasaki_energy = (pos_sq + mom_sq) / stride;
        let norm_prod = sqrt(pos_sq * mom_sq);
        var alignment = 0.0;
        if (norm_prod > 0.0000001) {
            alignment = dot_prod / norm_prod;
        }

        // Bounded Randers drift contribution (||tilde{beta}|| < 1)
        var randers_drift = 0.0;
        let norm_b = sqrt(norm_b_sq);
        if (norm_b > 0.000001) {
            randers_drift = (0.95 * tanh(norm_b) / norm_b) * (drift_dot / stride);
        }

        // Gauge-Spinor resonance bonus: rewards balanced so(16) (+) S_16^+ excitation
        var gs_balance = 0.0;
        let tot_gs = gauge_energy + spinor_energy;
        if (tot_gs > 0.000001) {
            gs_balance = 2.0 * sqrt(gauge_energy * spinor_energy) / tot_gs;
        }

        // FRS routing logit: Sasaki kinetic energy + velocity alignment + bounded Randers drift + Gauge-Spinor coupling
        let logit = sqrt(sasaki_energy) + alignment + randers_drift + 0.15 * gs_balance;
        cartan_vec_set_f32(g_frs_stream_logits, s, logit);
        if (logit > max_logit) { max_logit = logit; }
        s = s + 1.0;
    }

    // Numerically stable softmax with temperature t
    var sum_exp = 0.0;
    s = 0.0;
    while (s < 8.0) {
        let l_val = cartan_vec_get_f32(g_frs_stream_logits, s);
        let exp_val = exp((l_val - max_logit) / t);
        cartan_vec_set_f32(g_frs_stream_weights, s, exp_val);
        sum_exp = sum_exp + exp_val;
        s = s + 1.0;
    }
    if (sum_exp > 0.0) {
        let inv_sum = 1.0 / sum_exp;
        s = 0.0;
        while (s < 8.0) {
            let cur = cartan_vec_get_f32(g_frs_stream_weights, s);
            cartan_vec_set_f32(g_frs_stream_weights, s, cur * inv_sum);
            s = s + 1.0;
        }
    }
    return g_frs_stream_weights;
}
