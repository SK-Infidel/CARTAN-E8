// Projects/geomind/e8_anchors.cl
// 65,536 S^{247} Selective Resonance Anchor Basins & Developmental Concept Crystallization

include "src/std/geom.cl";
include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/fs.cl";
include "Projects/geomind/geometry.cl";

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

