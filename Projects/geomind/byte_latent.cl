// Projects/geomind/byte_latent.cl
// Core Byte-Latent Manifold Engine: 256x248 Embedding, 248x256 Head, Finsler-Randers Drift,
// Dynamic Entropy Patcher, Autoregressive BLT Decode, & Deep Generation

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

var g_byte_e8_skip_disk_autoload: float = 0.0;
var g_byte_e8_defer_disk_save: float = 0.0;

// ============================================================================
// PHASE 3: BYTE-LATENT DYNAMIC PATCHING (256x248 L2-RESIDENT E8 MANIFOLD)
// ============================================================================
// - g_byte_e8_emb_256x248:  256 byte rows x 248 E8 dims = 63,488 floats (253 KB)
// - g_byte_e8_head_248x256: 248 E8 dims x 256 byte cols = 63,488 floats (253 KB)
// - g_byte_e8_randers_b_248: 248-D Finsler-Randers directional drift 1-form beta
var g_byte_e8_emb_256x248: ptr = 0.0;
var g_byte_e8_head_248x256: ptr = 0.0;
var g_byte_e8_randers_b_248: ptr = 0.0;
var g_blt_decode_hv_248: ptr = 0.0;
var g_e8_episodic_ref_w1: ptr = 0.0;
var g_e8_episodic_ref_byte: ptr = 0.0;
var g_e8_episodic_ref_ptr: float = 0.0;
var g_e8_langevin_phase: float = 0.0;
var g_e8_langevin_temp: float = 0.28;
var g_byte_e8_initialized: float = 0.0;
var g_byte_latent_coast_count: float = 0.0;
var g_e8_gen_prev_patch: ptr = 0.0;
var g_e8_gen_top_patch: ptr = 0.0;
var g_e8_gen_has_prev: float = 0.0;


// ============================================================================
// STAGE 1-3: DEEP L-LAYER E8 GAUGE-SPINOR MANIFOLD BYTE-LATENT TRAINER & GENERATOR
// ============================================================================
// True Two-Tier Byte-Latent Transformer (BLT) Manifold Pipeline:
// - Tier 1 (Every Byte): Local Weyl root reflection + Octonion Fano Cross-Gate on S^{247}
//   conditioned on 3-gram Markov transition prior P(b_t | b_{t-3}, b_{t-2}, b_{t-1}).
// - Tier 2 (At Surprisal Patch Boundaries): Full 42-Layer Deep E8 Gauge-Spinor +
//   Finsler-Randers Causal Attention + 4x4 Freudenthal Magic Square MoE forward & backward step.
var g_blt_last_patch_count: float = 0.0;


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
    if (g_blt_decode_hv_248 == 0.0) { g_blt_decode_hv_248 = cartan_tensor_alloc(248.0); }
    if (g_e8_gen_prev_patch == 0.0) { g_e8_gen_prev_patch = cartan_tensor_alloc(248.0); }
    if (g_e8_gen_top_patch == 0.0) { g_e8_gen_top_patch = cartan_tensor_alloc(248.0); }
    if (g_e8_episodic_ref_w1 == 0.0) {
        g_e8_episodic_ref_w1 = cartan_tensor_alloc(32.0);
        g_e8_episodic_ref_byte = cartan_tensor_alloc(32.0);
        var er_i = 0.0;
        while (er_i < 32.0) {
            cartan_vec_set_f32(g_e8_episodic_ref_w1, er_i, -1.0);
            cartan_vec_set_f32(g_e8_episodic_ref_byte, er_i, -1.0);
            er_i = er_i + 1.0;
        }
        g_e8_episodic_ref_ptr = 0.0;
    }
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
    if (g_blt_decode_hv_248 == 0.0) { g_blt_decode_hv_248 = cartan_tensor_alloc(248.0); }
    if (g_e8_gen_prev_patch == 0.0) { g_e8_gen_prev_patch = cartan_tensor_alloc(248.0); }
    if (g_e8_gen_top_patch == 0.0) { g_e8_gen_top_patch = cartan_tensor_alloc(248.0); }
    if (g_e8_episodic_ref_w1 == 0.0) {
        g_e8_episodic_ref_w1 = cartan_tensor_alloc(32.0);
        g_e8_episodic_ref_byte = cartan_tensor_alloc(32.0);
        var er_i = 0.0;
        while (er_i < 32.0) {
            cartan_vec_set_f32(g_e8_episodic_ref_w1, er_i, -1.0);
            cartan_vec_set_f32(g_e8_episodic_ref_byte, er_i, -1.0);
            er_i = er_i + 1.0;
        }
        g_e8_episodic_ref_ptr = 0.0;
    }

    // Initialize 256 x 248 Byte-to-E8 table with mutually quasi-orthogonal 248-D E8 root + golden-ratio harmonic vectors
    // Normalized to ||e_b||_2 = 0.15 * sqrt(248) (||e_b||^2 = 5.58) with W_dec[:, b] = 0.25 * e_b so <e_b, W_dec[:, b]> = +1.395
    let tmp_row = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(tmp_row, 0.0);
        d = d + 1.0;
    }
    var b = 0.0;
    var root_idx = 0.0;
    var root_c = 0.0;
    var ph1 = 0.0;
    var ph2 = 0.0;
    var val = 0.0;
    var flat_idx = 0.0;
    while (b < 256.0) {
        let bh1 = math_mod_val((b + 19.0) * 7919.0 + 104729.0, 1000003.0);
        let bh2 = math_mod_val((b + 37.0) * 15485863.0 + 32452843.0, 1000003.0);
        d = 0.0;
        while (d < 248.0) {
            ph1 = math_mod_val(bh1 * (d + 1.0) * 0.6180339887, 6.283185307);
            ph2 = math_mod_val(bh2 * (248.0 - d) * 0.4142135623, 6.283185307);
            if (d < 8.0) {
                val = cos(ph1) + 0.70710678 * sin(ph2);
            } else {
                root_idx = math_mod_val((d - 8.0) + b * 17.0, 240.0);
                root_c = geomind_e8_get_root_coord(root_idx, math_mod_val(b * 3.0 + d, 8.0));
                val = 0.45 * root_c + 0.85 * cos(ph1) + 0.65 * sin(ph2 + d * 0.137);
            }
            cartan_vec_set_f32(tmp_row, d, val);
            d = d + 1.0;
        }
        geomind_weyl_reflect_vector_248(tmp_row, math_mod_val(b * 29.0 + 7.0, 240.0));
        var nsq = 0.0;
        d = 0.0;
        while (d < 248.0) {
            let rv = cartan_vec_get_f32(tmp_row, d);
            nsq = nsq + rv * rv;
            d = d + 1.0;
        }
        var sc = 1.0;
        if (nsq > 0.000001) {
            sc = sqrt(5.58 / nsq);
        }
        d = 0.0;
        while (d < 248.0) {
            val = cartan_vec_get_f32(tmp_row, d) * sc;
            cartan_vec_set_f32(g_byte_e8_emb_256x248, flat_idx, val);
            cartan_vec_set_f32(g_byte_e8_head_248x256, d * 256.0 + b, val * 0.25);
            flat_idx = flat_idx + 1.0;
            d = d + 1.0;
        }
        b = b + 1.0;
    }
    cartan_vec_free(tmp_row);

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

    // Hoist the 248-D Local + Patch state fusion outside the 256-byte readout loop (eliminates 96 x 248 redundant multiply-adds per byte)
    // S^{247}(\sqrt{248}) states produce natural unsuppressed E8 readout dot products matching log(m_prob) on equal thermodynamic footing:
    var d_pre = 0.0;
    while (d_pre < 248.0) {
        let hl = cartan_vec_get_f32(h_local_248, d_pre);
        var hp = 0.0;
        if (h_patch_248 != 0.0) {
            hp = cartan_vec_get_f32(h_patch_248, d_pre);
        }
        var hv_val = hl;
        if (h_patch_248 != 0.0) {
            hv_val = 0.5 * hl + 0.5 * hp;
        }
        cartan_vec_set_f32(g_blt_decode_hv_248, d_pre, hv_val);
        d_pre = d_pre + 1.0;
    }

    var c = 0.0;
    while (c < 256.0) {
        if ((c >= 32.0 && c <= 126.0) || c == 10.0) {
            var sum = 0.0;
            var d = 0.0;
            while (d < 248.0) {
                let hv = cartan_vec_get_f32(g_blt_decode_hv_248, d);
                let wv = cartan_vec_get_f32(g_byte_e8_head_248x256, d * 256.0 + c);
                sum = sum + hv * wv;
                d = d + 1.0;
            }
            let m_prob = geomind_markov_get_3gram_prob_fast(b1, c, c_idx, tot3, w1_idx, tot_w1, w2_idx, tot_w2, w3_idx, tot_w3);
            var m_logit = 0.65 * log(m_prob + 0.0005);
            if (m_logit < -5.0) { m_logit = -5.0; }
            cartan_vec_set_f32(out_logits_256, c, sum * 4.0 + m_logit);
        } else {
            cartan_vec_set_f32(out_logits_256, c, -35.0);
        }
        c = c + 1.0;
    }
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
    if (g_e8_gen_has_prev == 1.0) {
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_prev_patch, d, cartan_vec_get_f32(g_e8_gen_prev_patch, d));
            cartan_vec_set_f32(h_top_patch, d, cartan_vec_get_f32(g_e8_gen_top_patch, d));
            d = d + 1.0;
        }
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
            if (patch_steps > 0.0 || g_e8_gen_has_prev == 1.0) { prev_patch_ptr = h_prev_patch; }
            let mv = geomind_markov_get_prob(b2, cur_b);
            geomind_e8_stack_forward_step(h_patch_accum, prev_patch_ptr, mv, 0.85, h_top_patch);
            patch_steps = patch_steps + 1.0;
            g_e8_gen_has_prev = 1.0;
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(g_e8_gen_prev_patch, d, cartan_vec_get_f32(h_prev_patch, d));
                cartan_vec_set_f32(g_e8_gen_top_patch, d, cartan_vec_get_f32(h_top_patch, d));
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

    // If the prompt ended on an unterminated word (no trailing space) whose 3-byte suffix has no space transition in the active hub,
    // resolve its WordNet hypernym head suffix `(hb3, hb2, hb1)` so zero-shot hyponyms transition into delimiters natively:
    if (cur_b != 32.0 && patch_hash != 17.0) {
        let end_hub_c = geomind_markov_hub_ctx_idx(b3, b2, cur_b);
        let cur_w1_id = math_mod_val(patch_hash, 8388607.0) + 1.0;
        let end_w1_idx = geomind_markov_hub_row_idx(32768.0, 262144.0, cur_w1_id, end_hub_c, 0.0);
        var end_space_cnt = 0.0;
        if (end_w1_idx >= 32768.0) {
            end_space_cnt = cartan_vec_get_f32(g_markov_3gram_counts, end_w1_idx * 128.0 + 32.0);
        }
        if (end_space_cnt < 0.5) {
            let head_b321 = cartan_vec_create();
            cartan_vec_push_f32(head_b321, 32.0);
            cartan_vec_push_f32(head_b321, 32.0);
            cartan_vec_push_f32(head_b321, 32.0);
            if (geomind_wordnet_resolve_head_suffix(patch_hash, g_ctx_last_hash, head_b321) == 1.0) {
                b3 = cartan_vec_get_f32(head_b321, 0.0);
                b2 = cartan_vec_get_f32(head_b321, 1.0);
                cur_b = cartan_vec_get_f32(head_b321, 2.0);
            }
            cartan_vec_free(head_b321);
        }
    }

    var out_str = prompt;
    var step = 0.0;
    let max_grace_len = gen_len + 12.0;
    while (step < max_grace_len) {
        if (step >= gen_len && (cur_b == 32.0 || cur_b == 46.0 || cur_b == 33.0 || cur_b == 63.0)) {
            break;
        }
        let ref_hc = geomind_markov_hub_ctx_idx(b3, b2, cur_b);
        var ref_hub_id = g_markov_ctx_word2_id;
        if (g_markov_ctx_syn2_id > 0.0 && geomind_markov_hub_row_idx(294912.0, 393216.0, g_markov_ctx_word2_id, ref_hc, 0.0) < 0.0) {
            ref_hub_id = g_markov_ctx_syn2_id;
        }
        if (ref_hub_id <= 0.0) {
            ref_hub_id = g_markov_ctx_word1_id;
            if (g_markov_ctx_syn1_id > 0.0 && geomind_markov_hub_row_idx(32768.0, 262144.0, g_markov_ctx_word1_id, ref_hc, 0.0) < 0.0) {
                ref_hub_id = g_markov_ctx_syn1_id;
            }
        }

        // Pure 1:1 248-D E8 Readout (`h_local` + 42-Layer `h_top_patch`) + 3-Gram Markov Prior (Zero Character/String Waypoint Forcing):
        geomind_byte_latent_decode_logits_blt(h_local, h_top_patch, b3, b2, cur_b, logits_256);
        var max_raw_l = -100000.0;
        if (cur_b == 32.0) {
            c = 97.0;
            while (c <= 122.0) {
                let rlv = cartan_vec_get_f32(logits_256, c);
                if (rlv > max_raw_l) { max_raw_l = rlv; }
                c = c + 1.0;
            }
        }
        var best_b = 32.0;
        var best_l = -100000.0;
        c = 32.0;
        while (c <= 126.0) {
            var lv = cartan_vec_get_f32(logits_256, c);
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
                // Stage 6.4: Persistent Cross-Turn Episodic Refractory Memory + Langevin Geodesic Exploration
                // Only activates among competing high-likelihood branches (lv >= max_raw_l - 1.8) so unambiguous syntax is untouched
                if (lv >= (max_raw_l - 1.8)) {
                    var er_idx = 0.0;
                    while (er_idx < 32.0) {
                        if (cartan_vec_get_f32(g_e8_episodic_ref_w1, er_idx) == ref_hub_id &&
                            cartan_vec_get_f32(g_e8_episodic_ref_byte, er_idx) == c) {
                            lv = lv - 1.15;
                            break;
                        }
                        er_idx = er_idx + 1.0;
                    }
                    lv = lv + g_e8_langevin_temp * sin(g_e8_langevin_phase + c * 1.6180339);
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
            cartan_vec_set_f32(g_e8_episodic_ref_w1, g_e8_episodic_ref_ptr, ref_hub_id);
            cartan_vec_set_f32(g_e8_episodic_ref_byte, g_e8_episodic_ref_ptr, best_b);
            g_e8_episodic_ref_ptr = math_mod_val(g_e8_episodic_ref_ptr + 1.0, 32.0);
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
        g_e8_langevin_phase = math_mod_val(g_e8_langevin_phase + t_geo * 1.37 + math_abs_val(cartan_vec_get_f32(h_local, 0.0)) + 0.41, 628.31853);
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
            if (patch_steps > 0.0 || g_e8_gen_has_prev == 1.0) { prev_patch_ptr2 = h_prev_patch; }
            let mv_step = geomind_markov_get_prob(b2, cur_b);
            geomind_e8_stack_forward_step(h_patch_accum, prev_patch_ptr2, mv_step, 0.85, h_top_patch);
            patch_steps = patch_steps + 1.0;
            g_e8_gen_has_prev = 1.0;
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(g_e8_gen_prev_patch, d, cartan_vec_get_f32(h_prev_patch, d));
                cartan_vec_set_f32(g_e8_gen_top_patch, d, cartan_vec_get_f32(h_top_patch, d));
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

// Trim a byte-generated Tapestry stream cleanly at the `max_sents`-th sentence boundary ('.', '!', '?')
fn geomind_truncate_sentences(text: string, max_sents: float) -> string {
    let n = cartan_string_length(text);
    var sents = 0.0;
    var i = 0.0;
    while (i < n) {
        let b = cartan_byte_at(text, i);
        if (b == 46.0 || b == 33.0 || b == 63.0) {
            sents = sents + 1.0;
            if (sents >= max_sents) {
                return cartan_string_substring(text, 0.0, i + 1.0);
            }
        }
        i = i + 1.0;
    }
    return text;
}

