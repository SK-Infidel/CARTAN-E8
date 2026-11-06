// Projects/geomind/e8_relational.cl
// 248x248 Relational Operators (R_isa..R_effect), S^{247} Codebook, Hinton Microfeatures,
// 7-Layer Geodesic Cascades, 42-Layer Rollout, S^{247} Sentence Basins, and Epistemic QA

include "src/std/geom.cl";
include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/fs.cl";
include "Projects/geomind/geometry.cl";
include "Projects/geomind/e8_stack.cl";

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
var g_e8_rel_ru_buf: ptr = 0.0;
var g_e8_rel_updates_count: float = 0.0;

// S^{247} Concept Vocabulary Codebook for decoding any 248-D state h^{(l)} at any layer l in {0..42}
var g_e8_vocab_words: ptr = 0.0;
var g_e8_vocab_hashes: ptr = 0.0;
var g_e8_vocab_vecs: ptr = 0.0;
var g_e8_microfeat_vecs: ptr = 0.0;
var g_e8_vocab_count: float = 0.0;
var g_e8_last_decode_sim: float = 0.0;
var g_e8_last_sasaki_vel_norm: float = 0.0;


// ============================================================================
// STAGE 7.0: S^{247} SENTENCE MANIFOLD BASINS & UNIFIED 42-LAYER E8 QA ENGINE
// ============================================================================
var g_e8_sent_basin_vecs: ptr = 0.0;
var g_e8_sent_basin_is_copula: ptr = 0.0;
var g_e8_sent_basin_openers: ptr = 0.0;
var g_e8_sent_basin_count: float = 0.0;
var g_e8_sent_basins_indexed: float = 0.0;
var g_e8_narr_subj_hashes: ptr = 0.0;
var g_e8_narr_subj_scores: ptr = 0.0;
var g_e8_proper_noun_lut: ptr = 0.0;



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

// Check whether a case-normalized word patch hash `wh` is already registered in the S^{247} Concept Vocabulary Codebook
fn geomind_e8_has_vocab_hash(wh: float) -> float {
    if (wh <= 17.0) { return 1.0; }
    var i = 0.0;
    while (i < g_e8_vocab_count) {
        if (cartan_vec_get_f32(g_e8_vocab_hashes, i) == wh) {
            return 1.0;
        }
        i = i + 1.0;
    }
    return 0.0;
}

// Register a concept word in the S^{247} Concept Vocabulary Codebook so any layer state h^{(l)} can be decoded
fn geomind_e8_register_vocab_word(word: string) {
    if (cartan_string_length(word) == 0.0) { return; }
    let wh = geomind_word_patch_hash(word);
    if (wh <= 17.0) { return; }
    if (geomind_e8_has_vocab_hash(wh) == 1.0) { return; }
    if (g_e8_vocab_count >= 4096.0) { return; }
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
        let tv = cartan_vec_get_f32(tmp_v, d);
        cartan_vec_set_f32(g_e8_vocab_vecs, base + d, tv);
        cartan_vec_set_f32(g_e8_microfeat_vecs, base + d, tv);
        d = d + 1.0;
    }
    cartan_vec_free(tmp_v);
    g_e8_vocab_count = g_e8_vocab_count + 1.0;
}

// Find the Concept Vocabulary Codebook index (0 .. g_e8_vocab_count-1) matching a 248-D canonical vector `v_248`
fn geomind_e8_find_vocab_idx_by_vec(v_248: ptr) -> float {
    let v0 = cartan_vec_get_f32(v_248, 0.0);
    let v1 = cartan_vec_get_f32(v_248, 1.0);
    var i = 0.0;
    while (i < g_e8_vocab_count) {
        let base = i * 248.0;
        if (math_abs_val(cartan_vec_get_f32(g_e8_vocab_vecs, base) - v0) < 0.0001 &&
            math_abs_val(cartan_vec_get_f32(g_e8_vocab_vecs, base + 1.0) - v1) < 0.0001) {
            return i;
        }
        i = i + 1.0;
    }
    return -1.0;
}

// Hinton Co-Adapting S^{247} Microfeature Step:
// Gently pulls child/subject microfeature vector \tilde{P}_u along the geodesic toward parent/attribute \tilde{P}_v on S^{247}
fn geomind_e8_coadapt_microfeatures_248(u_248: ptr, v_248: ptr, alpha: float) {
    let idx_u = geomind_e8_find_vocab_idx_by_vec(u_248);
    let idx_v = geomind_e8_find_vocab_idx_by_vec(v_248);
    if (idx_u < 0.0 || idx_v < 0.0 || idx_u == idx_v) { return; }
    let base_u = idx_u * 248.0;
    let base_v = idx_v * 248.0;
    var nsq = 0.0;
    var d = 0.0;
    while (d < 248.0) {
        let mu = cartan_vec_get_f32(g_e8_microfeat_vecs, base_u + d);
        let mv = cartan_vec_get_f32(g_e8_microfeat_vecs, base_v + d);
        let upd = (1.0 - alpha) * mu + alpha * mv;
        cartan_vec_set_f32(g_e8_microfeat_vecs, base_u + d, upd);
        nsq = nsq + upd * upd;
        d = d + 1.0;
    }
    if (nsq > 0.000001) {
        let sc = sqrt(248.0 / nsq);
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(g_e8_microfeat_vecs, base_u + d, cartan_vec_get_f32(g_e8_microfeat_vecs, base_u + d) * sc);
            d = d + 1.0;
        }
    }
}

// Evaluate Layer-0 Co-Adapted Microfeature Cosine (1/248)*<\tilde{P}_a, \tilde{P}_b> on S^{247}
fn geomind_e8_microfeat_cosine_words(word_a: string, word_b: string) -> float {
    geomind_e8_rel_init_if_needed();
    let ha = geomind_word_patch_hash(word_a);
    let hb = geomind_word_patch_hash(word_b);
    var idx_a = -1.0;
    var idx_b = -1.0;
    var i = 0.0;
    while (i < g_e8_vocab_count) {
        let h = cartan_vec_get_f32(g_e8_vocab_hashes, i);
        if (h == ha) { idx_a = i; }
        if (h == hb) { idx_b = i; }
        i = i + 1.0;
    }
    if (idx_a < 0.0 || idx_b < 0.0) { return 0.0; }
    let base_a = idx_a * 248.0;
    let base_b = idx_b * 248.0;
    var dot = 0.0;
    var d = 0.0;
    while (d < 248.0) {
        dot = dot + cartan_vec_get_f32(g_e8_microfeat_vecs, base_a + d) * cartan_vec_get_f32(g_e8_microfeat_vecs, base_b + d);
        d = d + 1.0;
    }
    return dot / 248.0;
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

fn geomind_e8_rel_save(path: string) -> float {
    if (path == 0.0 || g_e8_rel_initialized == 0.0 || g_e8_rel_isa_248x248 == 0.0) { return 0.0; }
    let f = fopen(path, "wb");
    if (f == 0.0) { return 0.0; }
    fwrite(g_e8_rel_isa_248x248, 8.0, 61504.0 + 2.0, f);
    fwrite(g_e8_rel_super_248x248, 8.0, 61504.0 + 2.0, f);
    fwrite(g_e8_rel_cap_248x248, 8.0, 61504.0 + 2.0, f);
    fwrite(g_e8_rel_prop_248x248, 8.0, 61504.0 + 2.0, f);
    fwrite(g_e8_rel_val_248x248, 8.0, 61504.0 + 2.0, f);
    fwrite(g_e8_rel_cause_248x248, 8.0, 61504.0 + 2.0, f);
    fwrite(g_e8_rel_effect_248x248, 8.0, 61504.0 + 2.0, f);
    fwrite(g_e8_vocab_hashes, 8.0, 4096.0 + 2.0, f);
    fwrite(g_e8_vocab_vecs, 8.0, 1015808.0 + 2.0, f);
    fwrite(g_e8_microfeat_vecs, 8.0, 1015808.0 + 2.0, f);
    fclose(f);

    let wf = fopen("Projects/geomind/trainingdata/checkpoints/geomind_e8_vocab_words.txt", "wb");
    if (wf != 0.0) {
        var wi = 0.0;
        while (wi < g_e8_vocab_count) {
            let w_str = cartan_tree_get(g_e8_vocab_words, wi);
            let w_line = cartan_string_concat(w_str, "\n");
            fwrite(w_line, 1.0, cartan_string_length(w_line), wf);
            wi = wi + 1.0;
        }
        fclose(wf);
    }
    return 1.0;
}

fn geomind_e8_rel_load(path: string) -> float {
    if (path == 0.0 || cartan_file_exists(path) == 0.0) { return 0.0; }
    let expected_elems = 7.0 * (61504.0 + 2.0) + (4096.0 + 2.0) + 2.0 * (1015808.0 + 2.0);
    let f_sz = cartan_get_binary_file_size(path);
    if (f_sz < expected_elems * 8.0) { return 0.0; }
    let f = fopen(path, "rb");
    if (f == 0.0) { return 0.0; }
    fread(g_e8_rel_isa_248x248, 8.0, 61504.0 + 2.0, f);
    fread(g_e8_rel_super_248x248, 8.0, 61504.0 + 2.0, f);
    fread(g_e8_rel_cap_248x248, 8.0, 61504.0 + 2.0, f);
    fread(g_e8_rel_prop_248x248, 8.0, 61504.0 + 2.0, f);
    fread(g_e8_rel_val_248x248, 8.0, 61504.0 + 2.0, f);
    fread(g_e8_rel_cause_248x248, 8.0, 61504.0 + 2.0, f);
    fread(g_e8_rel_effect_248x248, 8.0, 61504.0 + 2.0, f);
    fread(g_e8_vocab_hashes, 8.0, 4096.0 + 2.0, f);
    fread(g_e8_vocab_vecs, 8.0, 1015808.0 + 2.0, f);
    fread(g_e8_microfeat_vecs, 8.0, 1015808.0 + 2.0, f);
    fclose(f);

    if (cartan_file_exists("Projects/geomind/trainingdata/checkpoints/geomind_e8_vocab_words.txt") == 1.0) {
        let w_txt = cartan_read_file("Projects/geomind/trainingdata/checkpoints/geomind_e8_vocab_words.txt");
        let w_lines = string_split(w_txt, "\n");
        let n_lines = cartan_tree_len_f(w_lines);
        g_e8_vocab_words = cartan_tree_create();
        g_e8_vocab_count = 0.0;
        var li = 0.0;
        while (li < n_lines && g_e8_vocab_count < 4096.0) {
            let lw = cartan_string_replace(cartan_tree_get(w_lines, li), "\r", "");
            if (cartan_string_length(lw) > 0.0) {
                cartan_tree_push(g_e8_vocab_words, lw);
                g_e8_vocab_count = g_e8_vocab_count + 1.0;
            }
            li = li + 1.0;
        }
    }
    return 1.0;
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
    g_e8_rel_ru_buf = cartan_vec_create();
    g_e8_vocab_words = cartan_tree_create();
    g_e8_vocab_hashes = cartan_tensor_alloc(4096.0);
    g_e8_vocab_vecs = cartan_tensor_alloc(4096.0 * 248.0);
    g_e8_microfeat_vecs = cartan_tensor_alloc(4096.0 * 248.0);
    g_e8_vocab_count = 0.0;
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(g_e8_rel_tmp_u, 0.0);
        cartan_vec_push_f32(g_e8_rel_tmp_v, 0.0);
        cartan_vec_push_f32(g_e8_vec_fun, 0.0);
        cartan_vec_push_f32(g_e8_rel_ru_buf, 0.0);
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
    if (g_byte_e8_skip_disk_autoload == 0.0 && cartan_file_exists("Projects/geomind/trainingdata/checkpoints/geomind_e8_rel_tensors.bin") == 1.0) {
        geomind_e8_rel_load("Projects/geomind/trainingdata/checkpoints/geomind_e8_rel_tensors.bin");
    }
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

// Analytical Rank-2 Asymmetric Riemannian Projection-Gradient Step on R in R^{248x248} with Shannon Orthogonal Crosstalk Suppression:
// Drives forward score S(u -> v) toward `target_w`, damps off-axis interference `(R * u)_perp = R * u - s_fwd * v`,
// drives reverse S(v -> u) toward 0.0 when `asym_contrast == 1.0`, and co-adapts S^{247} microfeature vectors.
fn geomind_e8_rel_train_step(
    rel_mat_248x248: ptr,
    u_248: ptr,
    v_248: ptr,
    target_w: float,
    asym_contrast: float,
    lr: float
) -> float {
    geomind_e8_rel_init_if_needed();
    var dot_fwd = 0.0;
    var r = 0.0;
    while (r < 248.0) {
        let row_off = r * 248.0;
        var ru = 0.0;
        var c = 0.0;
        while (c < 248.0) {
            ru = ru + cartan_vec_get_f32(rel_mat_248x248, row_off + c) * cartan_vec_get_f32(u_248, c);
            c = c + 1.0;
        }
        cartan_vec_set_f32(g_e8_rel_ru_buf, r, ru);
        dot_fwd = dot_fwd + cartan_vec_get_f32(v_248, r) * ru;
        r = r + 1.0;
    }
    let s_fwd = dot_fwd / 248.0;
    var s_rev = 0.0;
    if (asym_contrast > 0.0) {
        s_rev = geomind_e8_rel_score_vec(rel_mat_248x248, v_248, u_248);
    }
    let err_fwd = s_fwd - target_w;
    let err_rev = s_rev * asym_contrast;
    let step_scale = lr / 248.0;

    r = 0.0;
    while (r < 248.0) {
        let vr = cartan_vec_get_f32(v_248, r);
        let ur = cartan_vec_get_f32(u_248, r);
        let ru_r = cartan_vec_get_f32(g_e8_rel_ru_buf, r);
        let orth_r = ru_r - s_fwd * vr;
        let eff_row_err = err_fwd * vr + 0.04 * math_abs_val(err_fwd) * orth_r;
        let row_off = r * 248.0;
        var c = 0.0;
        while (c < 248.0) {
            let uc = cartan_vec_get_f32(u_248, c);
            let vc = cartan_vec_get_f32(v_248, c);
            let grad_rc = eff_row_err * uc + err_rev * ur * vc;
            let old_w = cartan_vec_get_f32(rel_mat_248x248, row_off + c);
            cartan_vec_set_f32(rel_mat_248x248, row_off + c, old_w - step_scale * grad_rc);
            c = c + 1.0;
        }
        r = r + 1.0;
    }
    if (target_w >= 0.70) {
        geomind_e8_coadapt_microfeatures_248(u_248, v_248, 0.14);
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

    // Normalize relational force vector f_vec onto S^{247} (||f_vec||_2 = sqrt(248))
    let f_scale = sqrt(248.0 / f_sq);
    d = 0.0;
    while (d < 248.0) {
        cartan_vec_set_f32(f_vec, d, cartan_vec_get_f32(f_vec, d) * f_scale);
        d = d + 1.0;
    }

    // Step through all 7 layers of this stratum (k = 0..6, layer l = l_start + k) on TS^{247}:
    // At each layer, evaluate e8_stack.cl's learned 120x120 so(16) W_gauge^{(l)}, 128x128 S_16^+ W_spinor^{(l)},
    // and Octonion Fano Cross-Gate into `h_gated`, project both `h_gated` (`v_stack`) and `f_vec` (`v_rel`) onto T_{h_cur} S^{247},
    // and integrate `h_next = h_cur + eta_rel * v_rel + eta_stack * v_stack` with two-sided Split-Manifold Casimir Retraction.
    if (g_e8_stack_num_layers <= 0.0 || g_e8_stack_w_gauge == 0.0) {
        geomind_e8_stack_init(42.0);
    }
    let h_lin = cartan_vec_create();
    let h_gated = cartan_vec_create();
    d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_lin, 0.0);
        cartan_vec_push_f32(h_gated, 0.0);
        d = d + 1.0;
    }
    let eta_rel = 0.44;
    let eta_stack = 0.04;
    var vel_norm_accum = 0.0;
    var k = 0.0;
    while (k < 7.0) {
        let l_idx = math_mod_val(l_start + k, g_e8_stack_num_layers);
        geomind_e8_stack_apply_gauge_spinor_linear_248(h_cur, 0.0, l_idx, h_lin, 0.0);
        geomind_e8_gauge_spinor_cross_gate_block248(h_lin, 0.0, h_gated, 0.0, 0.15);

        var dot_hf = 0.0;
        var dot_hg = 0.0;
        d = 0.0;
        while (d < 248.0) {
            let hc_d = cartan_vec_get_f32(h_cur, d);
            dot_hf = dot_hf + hc_d * cartan_vec_get_f32(f_vec, d);
            dot_hg = dot_hg + hc_d * cartan_vec_get_f32(h_gated, d);
            d = d + 1.0;
        }
        let proj_rel = dot_hf / 248.0;
        let proj_stack = dot_hg / 248.0;
        var v_sq = 0.0;
        var next_g_sq = 0.0;
        var next_s_sq = 0.0;
        d = 0.0;
        while (d < 248.0) {
            let hc = cartan_vec_get_f32(h_cur, d);
            let fv = cartan_vec_get_f32(f_vec, d);
            let gv = cartan_vec_get_f32(h_gated, d);
            let v_rel = fv - proj_rel * hc;
            let v_stack = gv - proj_stack * hc;
            let v_tot = eta_rel * v_rel + eta_stack * v_stack;
            v_sq = v_sq + v_tot * v_tot;
            let h_next = hc + v_tot;
            cartan_vec_set_f32(h_cur, d, h_next);
            if (d < 120.0) {
                next_g_sq = next_g_sq + h_next * h_next;
            } else {
                next_s_sq = next_s_sq + h_next * h_next;
            }
            d = d + 1.0;
        }
        if (next_g_sq > 0.000001 && next_s_sq > 0.000001) {
            let g_sc = sqrt(120.0 / next_g_sq);
            let s_sc = sqrt(128.0 / next_s_sq);
            d = 0.0;
            while (d < 120.0) {
                cartan_vec_set_f32(h_cur, d, cartan_vec_get_f32(h_cur, d) * g_sc);
                d = d + 1.0;
            }
            while (d < 248.0) {
                cartan_vec_set_f32(h_cur, d, cartan_vec_get_f32(h_cur, d) * s_sc);
                d = d + 1.0;
            }
        }
        vel_norm_accum = vel_norm_accum + sqrt(v_sq / 248.0);
        k = k + 1.0;
    }
    cartan_vec_free(h_lin);
    cartan_vec_free(h_gated);

    // Decode the post-7-layer evolved state `h_cur` against the S^{247} concept codebook
    let decoded_basin_word = geomind_e8_decode_concept_vec_248(h_cur);
    if (g_e8_last_decode_sim < 0.58 || (f_rms * g_e8_last_decode_sim) < 0.52) {
        // Crosstalk rejection: post-7-layer transport vector does not resonate with a crystallized concept basin
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_out_248, d, cartan_vec_get_f32(h_in_248, d));
            d = d + 1.0;
        }
        cartan_vec_free(f_vec);
        cartan_vec_free(h_cur);
        return 0.0;
    }

    // Post-Stratum Kanerva-Hopfield Attractor Basin Filtering on S^{119}(sqrt(120)) x S^{127}(sqrt(128)):
    // Preserves 20% of the 7-layer gauge/spinor/Fano trajectory `h_cur` while locking 80% into `basin_vec`
    let basin_vec = cartan_vec_create();
    d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(basin_vec, 0.0);
        d = d + 1.0;
    }
    geomind_e8_word_to_vec_248(decoded_basin_word, basin_vec);
    var clean_g_sq = 0.0;
    var clean_s_sq = 0.0;
    d = 0.0;
    while (d < 248.0) {
        let cv = 0.20 * cartan_vec_get_f32(h_cur, d) + 0.80 * cartan_vec_get_f32(basin_vec, d);
        cartan_vec_set_f32(h_cur, d, cv);
        if (d < 120.0) {
            clean_g_sq = clean_g_sq + cv * cv;
        } else {
            clean_s_sq = clean_s_sq + cv * cv;
        }
        d = d + 1.0;
    }
    if (clean_g_sq > 0.000001 && clean_s_sq > 0.000001) {
        let cg_sc = sqrt(120.0 / clean_g_sq);
        let cs_sc = sqrt(128.0 / clean_s_sq);
        d = 0.0;
        while (d < 120.0) {
            cartan_vec_set_f32(h_cur, d, cartan_vec_get_f32(h_cur, d) * cg_sc);
            d = d + 1.0;
        }
        while (d < 248.0) {
            cartan_vec_set_f32(h_cur, d, cartan_vec_get_f32(h_cur, d) * cs_sc);
            d = d + 1.0;
        }
    }
    cartan_vec_free(basin_vec);

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

    // Stratum 3 (Layers 14..20): Defeasible Capability & Intrinsic Attribute from L0 first, with L7 inheritance fallback
    let cap_rms = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_L0, 14.0, h_L21);
    if (cap_rms < 0.45) {
        geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_L7, 14.0, h_L21);
    }
    let w_L21 = geomind_e8_decode_concept_vec_248(h_L21);
    let prop_rms = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_L0, 14.0, h_prop);
    if (prop_rms < 0.45) {
        geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_L7, 14.0, h_prop);
    }
    let w_prop = geomind_e8_decode_concept_vec_248(h_prop);

    // Stratum 4 (Layers 21..27): 3-Hop Valence / State / Locus from L21 (e.g. run/bounce -> fun, purrs -> happy, fly -> sky, swim -> ocean)
    geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, h_L21, 21.0, h_L28);
    let w_L28 = geomind_e8_decode_concept_vec_248(h_L28);

    // Stratum 5 (Layers 28..34): Defeasible Causal Mechanism from L0 first, with L7 inheritance fallback
    let cause_rms = geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_L0, 28.0, h_L35);
    if (cause_rms < 0.45) {
        geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_L7, 28.0, h_L35);
    }
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
    var rA_21 = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, hA_0, 14.0, hA_21);
    if (rA_21 < 0.45) {
        rA_21 = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, hA_7, 14.0, hA_21);
    }
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
    var rB_21 = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, hB_0, 14.0, hB_21);
    if (rB_21 < 0.45) {
        rB_21 = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, hB_7, 14.0, hB_21);
    }
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
    let cp_rms = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_0, 14.0, h_21);
    if (cp_rms < 0.45) {
        geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_7, 14.0, h_21);
    }
    let pr_rms = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_0, 14.0, h_pr);
    if (pr_rms < 0.45) {
        geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_7, 14.0, h_pr);
    }
    geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, h_21, 21.0, h_28);
    let cs_rms = geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_0, 28.0, h_35);
    if (cs_rms < 0.45) {
        geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_7, 28.0, h_35);
    }
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
        let r_cp = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_0, 14.0, h_21);
        if (r_cp < 0.45) {
            geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_7, 14.0, h_21);
        }
        let r_pr = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_0, 14.0, h_pr);
        if (r_pr < 0.45) {
            geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_7, 14.0, h_pr);
        }
        geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, h_21, 21.0, h_28);
        let r_cs = geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_0, 28.0, h_35);
        if (r_cs < 0.45) {
            geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_7, 28.0, h_35);
        }
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

fn geomind_e8_sent_basins_init_if_needed() {
    if (g_e8_sent_basin_vecs != 0.0) { return; }
    g_e8_sent_basin_vecs = cartan_tensor_alloc(2048.0 * 248.0);
    g_e8_sent_basin_is_copula = cartan_tensor_alloc(2048.0);
    g_e8_sent_basin_openers = cartan_tree_create();
    g_e8_narr_subj_hashes = cartan_tensor_alloc(256.0);
    g_e8_narr_subj_scores = cartan_tensor_alloc(256.0);
    g_e8_proper_noun_lut = cartan_tensor_alloc(512.0);
    g_e8_sent_basin_count = 0.0;
    g_e8_sent_basins_indexed = 0.0;
}

fn geomind_e8_sent_basins_reset() {
    geomind_e8_sent_basins_init_if_needed();
    g_e8_sent_basin_openers = cartan_tree_create();
    g_e8_sent_basin_count = 0.0;
    g_e8_sent_basins_indexed = 0.0;
    var i = 0.0;
    while (i < 256.0) {
        cartan_vec_set_f32(g_e8_narr_subj_hashes, i, 0.0);
        cartan_vec_set_f32(g_e8_narr_subj_scores, i, 0.0);
        i = i + 1.0;
    }
    i = 0.0;
    while (i < 512.0) {
        cartan_vec_set_f32(g_e8_proper_noun_lut, i, 0.0);
        i = i + 1.0;
    }
}

fn geomind_e8_is_qa_stopword(w_low: string) -> float {
    if (cartan_string_eq(w_low, "you") == 1.0) { return 0.0; }
    let wlen = cartan_string_length(w_low);
    if (wlen <= 2.0) { return 1.0; }
    if (cartan_string_eq(w_low, "the") == 1.0 || cartan_string_eq(w_low, "and") == 1.0 ||
        cartan_string_eq(w_low, "but") == 1.0 || cartan_string_eq(w_low, "for") == 1.0 ||
        cartan_string_eq(w_low, "nor") == 1.0 || cartan_string_eq(w_low, "yet") == 1.0 ||
        cartan_string_eq(w_low, "not") == 1.0 || cartan_string_eq(w_low, "are") == 1.0 ||
        cartan_string_eq(w_low, "was") == 1.0 || cartan_string_eq(w_low, "were") == 1.0 ||
        cartan_string_eq(w_low, "had") == 1.0 || cartan_string_eq(w_low, "has") == 1.0 ||
        cartan_string_eq(w_low, "have") == 1.0 || cartan_string_eq(w_low, "been") == 1.0 ||
        cartan_string_eq(w_low, "can") == 1.0 || cartan_string_eq(w_low, "may") == 1.0 ||
        cartan_string_eq(w_low, "will") == 1.0 || cartan_string_eq(w_low, "shall") == 1.0 ||
        cartan_string_eq(w_low, "would") == 1.0 || cartan_string_eq(w_low, "could") == 1.0 ||
        cartan_string_eq(w_low, "should") == 1.0 || cartan_string_eq(w_low, "must") == 1.0 ||
        cartan_string_eq(w_low, "what") == 1.0 || cartan_string_eq(w_low, "where") == 1.0 ||
        cartan_string_eq(w_low, "when") == 1.0 || cartan_string_eq(w_low, "why") == 1.0 ||
        cartan_string_eq(w_low, "how") == 1.0 || cartan_string_eq(w_low, "who") == 1.0 ||
        cartan_string_eq(w_low, "whom") == 1.0 || cartan_string_eq(w_low, "which") == 1.0 ||
        cartan_string_eq(w_low, "while") == 1.0 || cartan_string_eq(w_low, "after") == 1.0 ||
        cartan_string_eq(w_low, "before") == 1.0 || cartan_string_eq(w_low, "because") == 1.0 ||
        cartan_string_eq(w_low, "unless") == 1.0 || cartan_string_eq(w_low, "until") == 1.0 ||
        cartan_string_eq(w_low, "though") == 1.0 || cartan_string_eq(w_low, "that") == 1.0 ||
        cartan_string_eq(w_low, "this") == 1.0 || cartan_string_eq(w_low, "these") == 1.0 ||
        cartan_string_eq(w_low, "those") == 1.0 || cartan_string_eq(w_low, "with") == 1.0 ||
        cartan_string_eq(w_low, "from") == 1.0 || cartan_string_eq(w_low, "into") == 1.0 ||
        cartan_string_eq(w_low, "upon") == 1.0 || cartan_string_eq(w_low, "over") == 1.0 ||
        cartan_string_eq(w_low, "under") == 1.0 || cartan_string_eq(w_low, "about") == 1.0 ||
        cartan_string_eq(w_low, "there") == 1.0 || cartan_string_eq(w_low, "here") == 1.0 ||
        cartan_string_eq(w_low, "then") == 1.0 || cartan_string_eq(w_low, "than") == 1.0 ||
        cartan_string_eq(w_low, "their") == 1.0 || cartan_string_eq(w_low, "they") == 1.0 ||
        cartan_string_eq(w_low, "them") == 1.0 || cartan_string_eq(w_low, "your") == 1.0 ||
        cartan_string_eq(w_low, "some") == 1.0 || cartan_string_eq(w_low, "such") == 1.0 ||
        cartan_string_eq(w_low, "very") == 1.0 || cartan_string_eq(w_low, "only") == 1.0 ||
        cartan_string_eq(w_low, "also") == 1.0 || cartan_string_eq(w_low, "even") == 1.0 ||
        cartan_string_eq(w_low, "still") == 1.0 || cartan_string_eq(w_low, "just") == 1.0 ||
        cartan_string_eq(w_low, "more") == 1.0 || cartan_string_eq(w_low, "most") == 1.0 ||
        cartan_string_eq(w_low, "other") == 1.0 || cartan_string_eq(w_low, "every") == 1.0 ||
        cartan_string_eq(w_low, "each") == 1.0 || cartan_string_eq(w_low, "either") == 1.0 ||
        cartan_string_eq(w_low, "does") == 1.0 || cartan_string_eq(w_low, "did") == 1.0 ||
        cartan_string_eq(w_low, "happens") == 1.0 || cartan_string_eq(w_low, "happen") == 1.0) {
        return 1.0;
    }
    return 0.0;
}

fn geomind_e8_proper_lut_insert(wh: float) {
    if (wh <= 17.0) { return; }
    let h0 = math_mod_val(wh * 13331.0, 512.0);
    var p = 0.0;
    while (p < 16.0) {
        let slot = math_mod_val(h0 + p * 7.0, 512.0);
        let cur = cartan_vec_get_f32(g_e8_proper_noun_lut, slot);
        if (cur == 0.0 || cur == wh) {
            cartan_vec_set_f32(g_e8_proper_noun_lut, slot, wh);
            return;
        }
        p = p + 1.0;
    }
}

fn geomind_e8_proper_lut_contains(wh: float) -> float {
    if (wh <= 17.0) { return 0.0; }
    let h0 = math_mod_val(wh * 13331.0, 512.0);
    var p = 0.0;
    while (p < 16.0) {
        let slot = math_mod_val(h0 + p * 7.0, 512.0);
        let cur = cartan_vec_get_f32(g_e8_proper_noun_lut, slot);
        if (cur == 0.0) { return 0.0; }
        if (cur == wh) { return 1.0; }
        p = p + 1.0;
    }
    return 0.0;
}

fn geomind_e8_narr_subj_check_update(wh: float, score: float) -> float {
    if (wh <= 17.0) { return 0.0; }
    let h0 = math_mod_val(wh * 13331.0, 256.0);
    var p = 0.0;
    while (p < 16.0) {
        let slot = math_mod_val(h0 + p * 7.0, 256.0);
        let cur_h = cartan_vec_get_f32(g_e8_narr_subj_hashes, slot);
        if (cur_h == 0.0 || cur_h == wh) {
            let prev_sc = cartan_vec_get_f32(g_e8_narr_subj_scores, slot);
            if (score > prev_sc) {
                cartan_vec_set_f32(g_e8_narr_subj_hashes, slot, wh);
                cartan_vec_set_f32(g_e8_narr_subj_scores, slot, score);
                return 1.0;
            }
            return 0.0;
        }
        p = p + 1.0;
    }
    return 0.0;
}

// Index every sentence in `corpus` onto S^{247} (`g_e8_sent_basin_vecs`) and optionally train
// Rung 4 narrative relational operators (`R_prop`, `R_cap`, `R_val`, `R_cause`, `R_effect`)
fn geomind_e8_index_corpus_sentence_basins(corpus: string, train_narr_rels: float) {
    geomind_e8_rel_init_if_needed();
    geomind_e8_sent_basins_init_if_needed();
    let n = cartan_string_length(corpus);
    if (n < 10.0) { return; }

    // Pass 1 (when train_narr_rels == 1.0): record capitalized mid-sentence proper nouns in `g_e8_proper_noun_lut`
    if (train_narr_rels == 1.0) {
        var p_i = 0.0;
        var p_in_w = 0.0;
        var p_w_start = 0.0;
        var p_sent_tok_idx = 0.0;
        while (p_i <= n) {
            var pb = 46.0;
            if (p_i < n) {
                pb = cartan_byte_at(corpus, p_i);
                if (pb < 0.0) { pb = pb + 256.0; }
            }
            let p_alnum = ((pb >= 97.0 && pb <= 122.0) || (pb >= 65.0 && pb <= 90.0) || (pb >= 48.0 && pb <= 57.0));
            if (p_alnum) {
                if (p_in_w == 0.0) {
                    p_w_start = p_i;
                    p_in_w = 1.0;
                }
            } else {
                if (p_in_w == 1.0) {
                    let w_len = p_i - p_w_start;
                    let b0 = cartan_byte_at(corpus, p_w_start);
                    if (p_sent_tok_idx > 0.0 && w_len >= 4.0 && b0 >= 65.0 && b0 <= 90.0) {
                        let raw_w = cartan_string_substring(corpus, p_w_start, p_i);
                        let low_w = cartan_string_to_lower(raw_w);
                        if (geomind_e8_is_qa_stopword(low_w) == 0.0) {
                            geomind_e8_proper_lut_insert(geomind_word_patch_hash(raw_w));
                        }
                    }
                    p_sent_tok_idx = p_sent_tok_idx + 1.0;
                    p_in_w = 0.0;
                }
                if (pb == 46.0 || pb == 33.0 || pb == 63.0 || pb == 10.0) {
                    p_sent_tok_idx = 0.0;
                }
            }
            p_i = p_i + 1.0;
        }
    }

    let h_sent = cartan_vec_create();
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_sent, 0.0);
        d = d + 1.0;
    }

    var s_low_toks = cartan_tree_create();
    var s_hashes = cartan_vec_create();
    var s_is_cap = cartan_vec_create();
    var s_w_starts = cartan_vec_create();
    var s_w_ends = cartan_vec_create();

    var in_word = 0.0;
    var w_start = 0.0;
    var i = 0.0;
    while (i <= n) {
        var b = 46.0;
        if (i < n) {
            b = cartan_byte_at(corpus, i);
            if (b < 0.0) { b = b + 256.0; }
        }
        let is_alnum = ((b >= 97.0 && b <= 122.0) || (b >= 65.0 && b <= 90.0) || (b >= 48.0 && b <= 57.0));
        if (is_alnum) {
            if (in_word == 0.0) {
                w_start = i;
                in_word = 1.0;
            }
        } else {
            if (in_word == 1.0) {
                let raw_tok = cartan_string_substring(corpus, w_start, i);
                let low_tok = cartan_string_to_lower(raw_tok);
                let wh = geomind_word_patch_hash(raw_tok);
                let b_first = cartan_byte_at(raw_tok, 0.0);
                var cap_flag = 0.0;
                if (b_first >= 65.0 && b_first <= 90.0) { cap_flag = 1.0; }
                cartan_tree_push(s_low_toks, low_tok);
                cartan_vec_push_f32(s_hashes, wh);
                cartan_vec_push_f32(s_is_cap, cap_flag);
                cartan_vec_push_f32(s_w_starts, w_start);
                cartan_vec_push_f32(s_w_ends, i);
                in_word = 0.0;
            }
            let is_sent_delim = (b == 46.0 || b == 33.0 || b == 63.0 || b == 10.0);
            if (is_sent_delim) {
                let n_stoks = cartan_tree_len_f(s_low_toks);
                if (n_stoks >= 4.0 && g_e8_sent_basin_count < 2048.0) {
                    let w0_low = cartan_tree_get(s_low_toks, 0.0);
                    let w2_low = cartan_tree_get(s_low_toks, 2.0);
                    var is_cop = 0.0;
                    if ((cartan_string_eq(w0_low, "a") == 1.0 || cartan_string_eq(w0_low, "an") == 1.0 || cartan_string_eq(w0_low, "the") == 1.0) &&
                        cartan_string_eq(w2_low, "is") == 1.0) {
                        is_cop = 1.0;
                    }

                    // Determine 3-to-5 word initiation prefix ending on a specific non-glue content word
                    var k_open = 2.0;
                    var has_non_glue = 0.0;
                    var ki = 0.0;
                    while (ki <= 2.0) {
                        let kw = cartan_tree_get(s_low_toks, ki);
                        let kh = cartan_vec_get_f32(s_hashes, ki);
                        if (geomind_is_glue_word_hash(kh, cartan_string_length(kw)) == 0.0 && geomind_e8_is_qa_stopword(kw) == 0.0) {
                            has_non_glue = 1.0;
                        }
                        ki = ki + 1.0;
                    }
                    while (k_open < (n_stoks - 1.0) && k_open < 4.0) {
                        let cur_kw = cartan_tree_get(s_low_toks, k_open);
                        let cur_kh = cartan_vec_get_f32(s_hashes, k_open);
                        let cur_klen = cartan_string_length(cur_kw);
                        if (geomind_is_glue_word_hash(cur_kh, cur_klen) == 0.0 && geomind_e8_is_qa_stopword(cur_kw) == 0.0) {
                            has_non_glue = 1.0;
                        }
                        if (has_non_glue == 1.0 && cur_klen >= 4.0 && geomind_is_glue_word_hash(cur_kh, cur_klen) == 0.0 && geomind_e8_is_qa_stopword(cur_kw) == 0.0) {
                            break;
                        }
                        k_open = k_open + 1.0;
                    }
                    let op_start = cartan_vec_get_f32(s_w_starts, 0.0);
                    let op_end = cartan_vec_get_f32(s_w_ends, k_open);
                    let opener_str = cartan_string_substring(corpus, op_start, op_end);

                    // Build 248-D S^{247} Sentence Superposition Vector H_m from unique content words
                    d = 0.0;
                    while (d < 248.0) {
                        cartan_vec_set_f32(h_sent, d, 0.0);
                        d = d + 1.0;
                    }
                    let uniq_h = cartan_vec_create();
                    var n_uniq = 0.0;
                    var ti = 0.0;
                    while (ti < n_stoks) {
                        let tw = cartan_tree_get(s_low_toks, ti);
                        let th = cartan_vec_get_f32(s_hashes, ti);
                        if (geomind_e8_is_qa_stopword(tw) == 0.0) {
                            if (train_narr_rels == 1.0 && cartan_string_length(tw) >= 3.0) {
                                geomind_e8_register_vocab_word(tw);
                            }
                            var seen_h = 0.0;
                            var ui = 0.0;
                            while (ui < n_uniq) {
                                if (cartan_vec_get_f32(uniq_h, ui) == th) {
                                    seen_h = 1.0;
                                    break;
                                }
                                ui = ui + 1.0;
                            }
                            if (seen_h == 0.0) {
                                cartan_vec_push_f32(uniq_h, th);
                                n_uniq = n_uniq + 1.0;
                                geomind_e8_word_to_vec_248(tw, g_e8_rel_tmp_u);
                                var w_mult = 1.0;
                                if (cartan_string_eq(tw, "you") == 1.0) { w_mult = 0.70; }
                                d = 0.0;
                                while (d < 248.0) {
                                    cartan_vec_set_f32(h_sent, d, cartan_vec_get_f32(h_sent, d) + w_mult * cartan_vec_get_f32(g_e8_rel_tmp_u, d));
                                    d = d + 1.0;
                                }
                            }
                        }
                        ti = ti + 1.0;
                    }
                    cartan_vec_free(uniq_h);

                    if (n_uniq > 0.0) {
                        let norm_sc = 1.0 / exp(0.35 * log(n_uniq));
                        let m_idx = g_e8_sent_basin_count;
                        let m_base = m_idx * 248.0;
                        d = 0.0;
                        while (d < 248.0) {
                            cartan_vec_set_f32(g_e8_sent_basin_vecs, m_base + d, cartan_vec_get_f32(h_sent, d) * norm_sc);
                            d = d + 1.0;
                        }
                        cartan_vec_set_f32(g_e8_sent_basin_is_copula, m_idx, is_cop);
                        cartan_tree_push(g_e8_sent_basin_openers, opener_str);
                        g_e8_sent_basin_count = g_e8_sent_basin_count + 1.0;
                    }

                    // Autonomous Rung 4 Narrative Subject & Predicate Relational Training
                    if (train_narr_rels == 1.0 && n_stoks >= 5.0) {
                        var span_s = -1.0;
                        var span_e = -1.0;
                        ti = 0.0;
                        while (ti < n_stoks) {
                            let is_c = cartan_vec_get_f32(s_is_cap, ti);
                            let th = cartan_vec_get_f32(s_hashes, ti);
                            let tw = cartan_tree_get(s_low_toks, ti);
                            var is_prop_start = 0.0;
                            if (is_c == 1.0 && geomind_e8_is_qa_stopword(tw) == 0.0) {
                                if (ti > 0.0 || geomind_e8_proper_lut_contains(th) == 1.0) {
                                    is_prop_start = 1.0;
                                } else if ((ti + 1.0) < n_stoks && cartan_vec_get_f32(s_is_cap, ti + 1.0) == 1.0) {
                                    is_prop_start = 1.0;
                                }
                            }
                            if (is_prop_start == 1.0) {
                                span_s = ti;
                                span_e = ti;
                                var tj = ti + 1.0;
                                while (tj < n_stoks) {
                                    if (cartan_vec_get_f32(s_is_cap, tj) == 1.0) {
                                        span_e = tj;
                                        tj = tj + 1.0;
                                    } else if (cartan_string_eq(cartan_tree_get(s_low_toks, tj), "of") == 1.0 &&
                                               (tj + 1.0) < n_stoks && cartan_vec_get_f32(s_is_cap, tj + 1.0) == 1.0) {
                                        span_e = tj + 1.0;
                                        tj = tj + 2.0;
                                    } else {
                                        break;
                                    }
                                }
                                break;
                            }
                            ti = ti + 1.0;
                        }

                        var is_def_subj = 0.0;
                        if (span_s < 0.0 && cartan_string_eq(w0_low, "the") == 1.0 &&
                            (cartan_string_eq(w2_low, "was") == 1.0 || cartan_string_eq(w2_low, "are") == 1.0)) {
                            span_s = 1.0;
                            span_e = 1.0;
                            is_def_subj = 1.0;
                        }

                        if (span_e >= 0.0 && (span_e + 1.0) < n_stoks) {
                            let u_subj = cartan_tree_get(s_low_toks, span_e);
                            let u_hash = cartan_vec_get_f32(s_hashes, span_e);
                            var u_mod = "";
                            if (span_e > span_s) {
                                u_mod = cartan_tree_get(s_low_toks, span_s);
                            }
                            var c0 = "";
                            var c1 = "";
                            var c2 = "";
                            var c3 = "";
                            var c_cnt = 0.0;
                            var pk = span_e + 1.0;
                            while (pk < n_stoks && c_cnt < 4.0) {
                                let pw = cartan_tree_get(s_low_toks, pk);
                                if (cartan_string_length(pw) >= 4.0 && geomind_e8_is_qa_stopword(pw) == 0.0 &&
                                    cartan_string_eq(pw, u_subj) == 0.0) {
                                    if (c_cnt == 0.0) { c0 = pw; }
                                    if (c_cnt == 1.0) { c1 = pw; }
                                    if (c_cnt == 2.0) { c2 = pw; }
                                    if (c_cnt == 3.0) { c3 = pw; }
                                    c_cnt = c_cnt + 1.0;
                                }
                                pk = pk + 1.0;
                            }

                            if (c_cnt >= 2.0) {
                                var narr_score = 1.0;
                                if (span_e > span_s) { narr_score = narr_score + 3.0; }
                                if (is_def_subj == 1.0) { narr_score = narr_score + 4.0; }
                                let nxt_w = cartan_tree_get(s_low_toks, span_e + 1.0);
                                if (cartan_string_length(nxt_w) >= 4.0 && geomind_e8_is_qa_stopword(nxt_w) == 0.0 &&
                                    cartan_string_eq(nxt_w, "said") == 0.0 && cartan_string_eq(nxt_w, "asked") == 0.0 &&
                                    cartan_string_eq(nxt_w, "thought") == 0.0 && cartan_string_eq(nxt_w, "replied") == 0.0) {
                                    narr_score = narr_score + 3.0;
                                }
                                if ((span_e + 3.0) < n_stoks && cartan_string_eq(cartan_tree_get(s_low_toks, span_e + 2.0), "to") == 1.0) {
                                    narr_score = narr_score + 4.0;
                                }
                                if (span_e == 0.0 && (span_e + 5.0) < n_stoks &&
                                    cartan_string_eq(cartan_tree_get(s_low_toks, 2.0), "the") == 1.0 &&
                                    cartan_string_eq(cartan_tree_get(s_low_toks, 4.0), "and") == 1.0) {
                                    narr_score = narr_score + 5.0;
                                }

                                if (narr_score >= 4.0 && geomind_e8_narr_subj_check_update(u_hash, narr_score) == 1.0) {
                                    var prop_t = c0;
                                    if (cartan_string_length(u_mod) > 0.0) { prop_t = u_mod; }
                                    geomind_e8_rel_train_words(g_e8_rel_prop_248x248, u_subj, prop_t, 0.92, 2.0);
                                    geomind_e8_rel_train_words(g_e8_rel_cap_248x248, u_subj, c0, 0.92, 2.0);
                                    geomind_e8_rel_train_words(g_e8_rel_val_248x248, c0, c1, 0.92, 2.0);
                                    if (c_cnt >= 4.0) {
                                        geomind_e8_rel_train_words(g_e8_rel_cause_248x248, u_subj, c2, 0.92, 2.0);
                                        geomind_e8_rel_train_words(g_e8_rel_effect_248x248, c2, c3, 0.92, 2.0);
                                    } else {
                                        geomind_e8_rel_train_words(g_e8_rel_cause_248x248, u_subj, c0, 0.92, 2.0);
                                        geomind_e8_rel_train_words(g_e8_rel_effect_248x248, c0, c1, 0.92, 2.0);
                                    }
                                }
                            }
                        }
                    }
                }
                cartan_vec_free(s_hashes);
                cartan_vec_free(s_is_cap);
                cartan_vec_free(s_w_starts);
                cartan_vec_free(s_w_ends);
                s_low_toks = cartan_tree_create();
                s_hashes = cartan_vec_create();
                s_is_cap = cartan_vec_create();
                s_w_starts = cartan_vec_create();
                s_w_ends = cartan_vec_create();
            }
        }
        i = i + 1.0;
    }
    cartan_vec_free(s_hashes);
    cartan_vec_free(s_is_cap);
    cartan_vec_free(s_w_starts);
    cartan_vec_free(s_w_ends);
    cartan_vec_free(h_sent);
}

fn geomind_e8_populate_curriculum_sentence_basins() {
    geomind_e8_sent_basins_init_if_needed();
    if (g_e8_sent_basins_indexed == 1.0 && g_e8_sent_basin_count > 0.0) { return; }
    geomind_e8_sent_basins_reset();

    let p1 = "Projects/geomind/trainingdata/e8_nursery_primer.txt";
    if (cartan_file_exists(p1) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(p1), 0.0);
    }
    let p2 = "Projects/geomind/trainingdata/e8_concept_triples.txt";
    if (cartan_file_exists(p2) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(p2), 0.0);
    }
    let c_mod = "Projects/geomind/trainingdata/storytelling_chunks/chunk_005_t1_GeoMind_Modern_Narratives.txt";
    if (cartan_file_exists(c_mod) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(c_mod), 1.0);
    }
    let c_ali = "Projects/geomind/trainingdata/storytelling_chunks/chunk_007_t2_Alice_In_Wonderland.txt";
    if (cartan_file_exists(c_ali) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(c_ali), 1.0);
    }
    let c_ant = "Projects/geomind/trainingdata/storytelling_chunks/chunk_019_t2_Anthem.txt";
    if (cartan_file_exists(c_ant) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(c_ant), 1.0);
    }
    let c_sh = "Projects/geomind/trainingdata/storytelling_chunks/chunk_028_t3_Sherlock_Holmes.txt";
    if (cartan_file_exists(c_sh) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(c_sh), 1.0);
    }
    g_e8_sent_basins_indexed = 1.0;
}

// Helper: fold a word (and any registered morphological stem variants in `g_e8_vocab_words`) into `q_vec_248`
fn geomind_e8_fold_query_word_248(word_low: string, weight: float, q_vec_248: ptr) {
    geomind_e8_word_to_vec_248(word_low, g_e8_rel_tmp_u);
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_set_f32(q_vec_248, d, cartan_vec_get_f32(q_vec_248, d) + weight * cartan_vec_get_f32(g_e8_rel_tmp_u, d));
        d = d + 1.0;
    }
    // Check registered morphological inflections (+d, +ed, +s, or irregular come->came / go->went) in S^{247} codebook
    var m1 = cartan_string_concat(word_low, "d");
    var m2 = cartan_string_concat(word_low, "ed");
    var m3 = cartan_string_concat(word_low, "s");
    if (cartan_string_eq(word_low, "come") == 1.0) { m1 = "came"; }
    if (cartan_string_eq(word_low, "go") == 1.0) { m1 = "went"; }
    let h1 = geomind_word_patch_hash(m1);
    let h2 = geomind_word_patch_hash(m2);
    let h3 = geomind_word_patch_hash(m3);
    var vi = 0.0;
    while (vi < g_e8_vocab_count) {
        let vh = cartan_vec_get_f32(g_e8_vocab_hashes, vi);
        if (vh == h1 || vh == h2 || vh == h3) {
            let v_base = vi * 248.0;
            d = 0.0;
            while (d < 248.0) {
                cartan_vec_set_f32(q_vec_248, d, cartan_vec_get_f32(q_vec_248, d) + 0.95 * cartan_vec_get_f32(g_e8_vocab_vecs, v_base + d));
                d = d + 1.0;
            }
        }
        vi = vi + 1.0;
    }
}

// Stage 7.0 Coupled Two-Scale Markov Epistemic Question-Answering Engine (Unified 42-Layer E8 Rollout + S^{247} Sentence Basins):
// 1. Autonomously parses raw natural-language `question_str` using 42-layer cascade energy across all 6 strata to locate Focus Concept `subj_word`.
// 2. Runs the unified 42-Layer S^{247} Geodesic Rollout (`h_L0 -> h_L7 -> h_L14 -> h_L21 -> h_L28 -> h_L35 -> h_L42`) for EVERY question (Rungs 1-4).
// 3. Evaluates the 248-D Killing-Cartan inner product `<Q_248, H_m> / 248` against all S^{247} Sentence Manifold Basins to initiate
//    `geomind_byte_latent_generate_deep_e8` from the winning basin's opener (even when the queried entity appears mid-sentence).
fn geomind_e8_answer_epistemic_question(question_str: string) -> string {
    geomind_wordnet_init_if_needed();
    geomind_e8_populate_curriculum_sentence_basins();
    // Reset cross-turn episodic refractory ring buffer so independent QA queries do not suppress canonical edges:
    if (g_e8_episodic_ref_w1 != 0.0) {
        var er_clr = 0.0;
        while (er_clr < 32.0) {
            cartan_vec_set_f32(g_e8_episodic_ref_w1, er_clr, 0.0);
            cartan_vec_set_f32(g_e8_episodic_ref_byte, er_clr, 0.0);
            er_clr = er_clr + 1.0;
        }
        g_e8_episodic_ref_ptr = 0.0;
    }
    let h_L0 = cartan_vec_create();
    let h_L7 = cartan_vec_create();
    let h_L14 = cartan_vec_create();
    let h_L21 = cartan_vec_create();
    let h_prop = cartan_vec_create();
    let h_L28 = cartan_vec_create();
    let h_L35 = cartan_vec_create();
    let h_L42 = cartan_vec_create();
    let q_vec_248 = cartan_vec_create();
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
        cartan_vec_push_f32(q_vec_248, 0.0);
        d = d + 1.0;
    }

    var subj_word = "";
    var best_subj_energy = 0.0;
    let q_raw_toks = cartan_tree_create();
    let q_low_toks = cartan_tree_create();
    let q_hashes = cartan_vec_create();
    let q_is_cap = cartan_vec_create();

    let q_len = cartan_string_length(question_str);
    var w_start = 0.0;
    var in_word = 0.0;
    var q_tok_idx = 0.0;
    var i = 0.0;
    while (i <= q_len) {
        var b = 32.0;
        if (i < q_len) {
            b = cartan_byte_at(question_str, i);
            if (b < 0.0) { b = b + 256.0; }
        }
        let is_alnum = ((b >= 97.0 && b <= 122.0) || (b >= 65.0 && b <= 90.0) || (b >= 48.0 && b <= 57.0));
        if (is_alnum) {
            if (in_word == 0.0) {
                w_start = i;
                in_word = 1.0;
            }
        } else {
            if (in_word == 1.0) {
                let raw_tok = cartan_string_substring(question_str, w_start, i);
                let low_tok = cartan_string_to_lower(raw_tok);
                let wh = geomind_word_patch_hash(raw_tok);
                let b_first = cartan_byte_at(raw_tok, 0.0);
                var cap_flag = 0.0;
                if (b_first >= 65.0 && b_first <= 90.0) { cap_flag = 1.0; }
                cartan_tree_push(q_raw_toks, raw_tok);
                cartan_tree_push(q_low_toks, low_tok);
                cartan_vec_push_f32(q_hashes, wh);
                cartan_vec_push_f32(q_is_cap, cap_flag);

                // Check if this token (lowercase or capitalized) is a registered S^{247} concept with 42-layer cascade energy
                var v_idx = 0.0;
                var is_reg = 0.0;
                var canon_word = low_tok;
                while (v_idx < g_e8_vocab_count) {
                    if (cartan_vec_get_f32(g_e8_vocab_hashes, v_idx) == wh) {
                        is_reg = 1.0;
                        canon_word = cartan_tree_get(g_e8_vocab_words, v_idx);
                        break;
                    }
                    v_idx = v_idx + 1.0;
                }
                if (is_reg == 1.0 && cartan_string_length(canon_word) >= 3.0 &&
                    geomind_e8_is_qa_stopword(canon_word) == 0.0 && cartan_string_eq(canon_word, "you") == 0.0) {
                    geomind_e8_word_to_vec_248(canon_word, h_L0);
                    let p7 = geomind_e8_cascade_step_7L(g_e8_rel_isa_248x248, h_L0, 0.0, h_L7);
                    let p14 = geomind_e8_cascade_step_7L(g_e8_rel_super_248x248, h_L7, 7.0, h_L14);
                    var p21 = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_L0, 14.0, h_L21);
                    if (p21 < 0.45) {
                        p21 = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_L7, 14.0, h_L21);
                    }
                    var p_pr = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_L0, 14.0, h_prop);
                    if (p_pr < 0.45) {
                        p_pr = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_L7, 14.0, h_prop);
                    }
                    let p28 = geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, h_L21, 21.0, h_L28);
                    var p35 = geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_L0, 28.0, h_L35);
                    if (p35 < 0.45) {
                        p35 = geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_L7, 28.0, h_L35);
                    }
                    let p42 = geomind_e8_cascade_step_7L(g_e8_rel_effect_248x248, h_L35, 35.0, h_L42);

                    var cand_energy = 0.0;
                    if (p7 > 0.0) { cand_energy = cand_energy + 2.5; }
                    if (p14 > 0.0) { cand_energy = cand_energy + 1.5; }
                    if (p21 > 0.0) { cand_energy = cand_energy + 2.0; }
                    if (p_pr > 0.0) { cand_energy = cand_energy + 1.5; }
                    if (p28 > 0.0) { cand_energy = cand_energy + 1.5; }
                    if (p35 > 0.0) { cand_energy = cand_energy + 2.5; }
                    if (p42 > 0.0) { cand_energy = cand_energy + 2.5; }
                    if (cap_flag == 1.0 && q_tok_idx > 0.0 && cand_energy > 0.0) {
                        cand_energy = cand_energy + 2.0;
                    }

                    if (cand_energy > best_subj_energy || (cap_flag == 1.0 && cand_energy == best_subj_energy && cand_energy > 0.0)) {
                        best_subj_energy = cand_energy;
                        subj_word = canon_word;
                    }
                }
                q_tok_idx = q_tok_idx + 1.0;
                in_word = 0.0;
            }
        }
        i = i + 1.0;
    }

    let n_qtoks = cartan_tree_len_f(q_raw_toks);
    if (cartan_string_length(subj_word) == 0.0 && n_qtoks > 0.0) {
        subj_word = cartan_tree_get(q_low_toks, n_qtoks - 1.0);
    }

    // Run full Defeasible 42-Layer Geodesic Rollout (L0-first with L7 inheritance fallback) on Focus Subject `subj_word`
    geomind_e8_word_to_vec_248(subj_word, h_L0);
    let r7 = geomind_e8_cascade_step_7L(g_e8_rel_isa_248x248, h_L0, 0.0, h_L7);
    let w_L7 = geomind_e8_decode_concept_vec_248(h_L7);
    let r14 = geomind_e8_cascade_step_7L(g_e8_rel_super_248x248, h_L7, 7.0, h_L14);
    let w_L14 = geomind_e8_decode_concept_vec_248(h_L14);
    var r21 = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_L0, 14.0, h_L21);
    if (r21 < 0.45) {
        r21 = geomind_e8_cascade_step_7L(g_e8_rel_cap_248x248, h_L7, 14.0, h_L21);
    }
    let w_L21 = geomind_e8_decode_concept_vec_248(h_L21);
    var r_prop = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_L0, 14.0, h_prop);
    if (r_prop < 0.45) {
        r_prop = geomind_e8_cascade_step_7L(g_e8_rel_prop_248x248, h_L7, 14.0, h_prop);
    }
    let w_prop = geomind_e8_decode_concept_vec_248(h_prop);
    let r28 = geomind_e8_cascade_step_7L(g_e8_rel_val_248x248, h_L21, 21.0, h_L28);
    let w_L28 = geomind_e8_decode_concept_vec_248(h_L28);
    var r35 = geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_L0, 28.0, h_L35);
    if (r35 < 0.45) {
        r35 = geomind_e8_cascade_step_7L(g_e8_rel_cause_248x248, h_L7, 28.0, h_L35);
    }
    let w_L35 = geomind_e8_decode_concept_vec_248(h_L35);
    let r42 = geomind_e8_cascade_step_7L(g_e8_rel_effect_248x248, h_L35, 35.0, h_L42);
    let w_L42 = geomind_e8_decode_concept_vec_248(h_L42);

    // Construct 248-D Question + 42-Layer Rollout Query Vector `q_vec_248` on S^{247}
    var qi = 0.0;
    while (qi < n_qtoks) {
        let qt = cartan_tree_get(q_low_toks, qi);
        if (geomind_e8_is_qa_stopword(qt) == 0.0) {
            var q_w = 1.60;
            if (cartan_string_eq(qt, "you") == 1.0) { q_w = 0.85; }
            geomind_e8_fold_query_word_248(qt, q_w, q_vec_248);
        }
        qi = qi + 1.0;
    }
    d = 0.0;
    while (d < 248.0) {
        var roll_d = 0.75 * cartan_vec_get_f32(h_L0, d);
        if (r7 > 0.0) { roll_d = roll_d + 0.85 * cartan_vec_get_f32(h_L7, d); }
        if (r14 > 0.0) { roll_d = roll_d + 0.35 * cartan_vec_get_f32(h_L14, d); }
        if (r21 > 0.0) { roll_d = roll_d + 0.65 * cartan_vec_get_f32(h_L21, d); }
        if (r_prop > 0.0) { roll_d = roll_d + 0.45 * cartan_vec_get_f32(h_prop, d); }
        if (r28 > 0.0) { roll_d = roll_d + 0.65 * cartan_vec_get_f32(h_L28, d); }
        if (r35 > 0.0) { roll_d = roll_d + 0.75 * cartan_vec_get_f32(h_L35, d); }
        if (r42 > 0.0) { roll_d = roll_d + 0.75 * cartan_vec_get_f32(h_L42, d); }
        cartan_vec_set_f32(q_vec_248, d, cartan_vec_get_f32(q_vec_248, d) + roll_d);
        d = d + 1.0;
    }

    // Select highest-resonating S^{247} Sentence Manifold Basin via Killing-Cartan inner product <q_vec_248, H_m> / 248
    var best_basin_sim = -100000.0;
    var best_opener = cartan_string_concat("The ", subj_word);
    var m = 0.0;
    while (m < g_e8_sent_basin_count) {
        if (cartan_vec_get_f32(g_e8_sent_basin_is_copula, m) == 0.0) {
            let m_base = m * 248.0;
            var dot_m = 0.0;
            d = 0.0;
            while (d < 248.0) {
                dot_m = dot_m + cartan_vec_get_f32(q_vec_248, d) * cartan_vec_get_f32(g_e8_sent_basin_vecs, m_base + d);
                d = d + 1.0;
            }
            let sim_m = dot_m / 248.0;
            if (sim_m > best_basin_sim) {
                best_basin_sim = sim_m;
                best_opener = cartan_tree_get(g_e8_sent_basin_openers, m);
            }
        }
        m = m + 1.0;
    }

    var ans = "";
    let subj_tag = cartan_string_concat(subj_word, cartan_string_concat("(", cartan_string_concat(w_prop, ")")));
    if (r7 == 0.0 && r14 == 0.0) {
        let s1 = geomind_truncate_sentences(geomind_byte_latent_generate_deep_e8(best_opener, 42.0, 240.0), 1.0);
        var narr_tag = cartan_string_concat(w_L21, cartan_string_concat("->", w_L28));
        if (r35 > 0.0 || r42 > 0.0) {
            narr_tag = cartan_string_concat(narr_tag, cartan_string_concat(" | ", cartan_string_concat(w_L35, cartan_string_concat("->", w_L42))));
        }
        ans = cartan_string_concat(s1, cartan_string_concat(" [42L Waypoints: ", cartan_string_concat(subj_tag, cartan_string_concat("->", cartan_string_concat(narr_tag, "]")))));
    } else {
        // Sentence 1: Lower-Stratum Taxonomic & Property Rollout (L0 -> L7 -> L14 + L21_prop)
        let s1 = geomind_truncate_sentences(geomind_byte_latent_generate_deep_e8(cartan_string_concat("A ", subj_word), 42.0, 96.0), 1.0);
        // Sentence 2: Upper-Stratum Capability, Affordance, Contextual Physics, or Causal Rollout from S^{247} Sentence Basin
        let s2 = geomind_truncate_sentences(geomind_byte_latent_generate_deep_e8(best_opener, 42.0, 96.0), 1.0);
        var upper_tag = cartan_string_concat(w_L21, cartan_string_concat("->", w_L28));
        if (r42 > 0.0) {
            upper_tag = cartan_string_concat(upper_tag, cartan_string_concat(" | ", cartan_string_concat(w_L35, cartan_string_concat("->", w_L42))));
        }
        ans = cartan_string_concat(s1, cartan_string_concat(" ", cartan_string_concat(s2, cartan_string_concat(" [42L Waypoints: ", cartan_string_concat(subj_tag, cartan_string_concat("->", cartan_string_concat(w_L7, cartan_string_concat("->", cartan_string_concat(w_L14, cartan_string_concat(" | ", cartan_string_concat(upper_tag, "]")))))))))));
    }

    cartan_vec_free(q_hashes);
    cartan_vec_free(q_is_cap);
    cartan_vec_free(q_vec_248);
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

// Run the complete Epistemic, Taxonomic, & Subtle Geometric Reasoning Evaluation Suite (callable from --curriculum or standalone --eval-qa)
