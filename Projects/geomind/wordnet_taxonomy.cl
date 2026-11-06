// Projects/geomind/wordnet_taxonomy.cl
// 4,096-Slot WordNet Synset + Information Content (IC) + SenseGuard Hash Table & DAG Loader

include "src/std/geom.cl";
include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/fs.cl";
include "Projects/geomind/geometry.cl";

var g_wordnet_initialized: float = 0.0;
var g_wordnet_lemma_hash: ptr = 0.0;
var g_wordnet_synset_hash: ptr = 0.0;
var g_wordnet_head_hash: ptr = 0.0;
var g_wordnet_ic_weight: ptr = 0.0;
var g_wordnet_sense_guard: ptr = 0.0;
var g_wordnet_lemma_vecs: ptr = 0.0;
var g_wordnet_head_b3: ptr = 0.0;
var g_wordnet_head_b2: ptr = 0.0;
var g_wordnet_head_b1: ptr = 0.0;


var g_wn_verb_to: float = 0.0;
var g_wn_verb_can: float = 0.0;
var g_wn_verb_will: float = 0.0;
var g_wn_verb_not: float = 0.0;
var g_wn_verb_do: float = 0.0;
var g_wn_hash_is: float = 0.0;
var g_wn_hash_a: float = 0.0;
var g_wn_hash_an: float = 0.0;
var g_wn_hash_the: float = 0.0;
var g_wn_hash_and: float = 0.0;
var g_wn_hash_in: float = 0.0;
var g_wn_hash_on: float = 0.0;
var g_wn_hash_when: float = 0.0;
var g_wn_hash_it: float = 0.0;
var g_wn_hash_you: float = 0.0;
var g_wn_hash_likes: float = 0.0;
var g_wn_hash_because: float = 0.0;



fn geomind_parse_simple_float(s: string) -> float {
    let n = cartan_string_length(s);
    var val = 0.0;
    var frac = 0.0;
    var div = 1.0;
    var in_frac = 0.0;
    var i = 0.0;
    while (i < n) {
        let b = cartan_byte_at(s, i);
        if (b == 46.0) {
            in_frac = 1.0;
        } else if (b >= 48.0 && b <= 57.0) {
            let dig = b - 48.0;
            if (in_frac == 0.0) {
                val = val * 10.0 + dig;
            } else {
                div = div * 10.0;
                frac = frac + dig / div;
            }
        }
        i = i + 1.0;
    }
    return val + frac;
}

fn geomind_wordnet_insert_hash(lh: float, sh: float, head_lh: float, ic_val: float, guard: float, vec_248: ptr, hb3: float, hb2: float, hb1: float) {
    if (lh <= 17.0 || sh <= 0.0) { return; }
    let h0 = math_mod_val(lh * 13331.0, 4096.0);
    var probe = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 4096.0);
        let cur_l = cartan_vec_get_f32(g_wordnet_lemma_hash, slot);
        if (cur_l == 0.0 || cur_l == lh) {
            cartan_vec_set_f32(g_wordnet_lemma_hash, slot, lh);
            cartan_vec_set_f32(g_wordnet_synset_hash, slot, sh);
            cartan_vec_set_f32(g_wordnet_head_hash, slot, head_lh);
            cartan_vec_set_f32(g_wordnet_ic_weight, slot, ic_val);
            cartan_vec_set_f32(g_wordnet_sense_guard, slot, guard);
            cartan_vec_set_f32(g_wordnet_head_b3, slot, hb3);
            cartan_vec_set_f32(g_wordnet_head_b2, slot, hb2);
            cartan_vec_set_f32(g_wordnet_head_b1, slot, hb1);
            if (vec_248 != 0.0) {
                let v_base = slot * 248.0;
                var d = 0.0;
                while (d < 248.0) {
                    cartan_vec_set_f32(g_wordnet_lemma_vecs, v_base + d, cartan_vec_get_f32(vec_248, d));
                    d = d + 1.0;
                }
            }
            return;
        }
        probe = probe + 1.0;
    }
}

fn geomind_wordnet_register_node(synset_path: string, lemmas_csv: string, ic_val: float, sense_guard: float) {
    if (cartan_string_length(synset_path) == 0.0 || cartan_string_length(lemmas_csv) == 0.0) { return; }
    geomind_e8_rel_init_if_needed();
    let sh = 700000.0 + math_mod_val(geomind_word_patch_hash(synset_path), 250000.0);
    let n = cartan_string_length(lemmas_csv);
    var head_lh = 0.0;
    var head_str = "";
    var hb3 = 32.0;
    var hb2 = 32.0;
    var hb1 = 32.0;
    var lh = 17.0;
    var word_start = 0.0;
    var i = 0.0;
    while (i <= n) {
        var b = 44.0;
        if (i < n) {
            b = cartan_byte_at(lemmas_csv, i);
            if (b < 0.0) { b = b + 256.0; }
        }
        if (b == 44.0) {
            if (lh != 17.0) {
                while (word_start < i && cartan_byte_at(lemmas_csv, word_start) == 32.0) {
                    word_start = word_start + 1.0;
                }
                let lemma_str = cartan_string_substring(lemmas_csv, word_start, i);
                let had_ckpt_rels = (g_byte_e8_skip_disk_autoload == 0.0 && g_e8_vocab_count > 500.0);
                if (had_ckpt_rels == 0.0) {
                    geomind_e8_register_vocab_word(lemma_str);
                }
                if (head_lh == 0.0) {
                    head_lh = lh;
                    head_str = lemma_str;
                    let hlen = cartan_string_length(head_str);
                    if (hlen >= 1.0) { hb1 = cartan_byte_at(head_str, hlen - 1.0); }
                    if (hlen >= 2.0) { hb2 = cartan_byte_at(head_str, hlen - 2.0); }
                    if (hlen >= 3.0) { hb3 = cartan_byte_at(head_str, hlen - 3.0); }
                    // Train Stratum 2 (Layers 7..13) 2nd-Hop Superordinate Category R_super(head_lemma -> super_category) autonomously
                    // from the WordNet dot-delimited hypernym path (zero hardcoded category strings)
                    if (had_ckpt_rels == 0.0) {
                        let path_segs = string_split(synset_path, ".");
                        let n_segs = cartan_tree_len_f(path_segs);
                        if (n_segs >= 3.0) {
                            var sup_idx = n_segs - 2.0;
                            if (n_segs >= 7.0) { sup_idx = 4.0; }
                            let super_str = cartan_tree_get(path_segs, sup_idx);
                            geomind_e8_register_vocab_word(super_str);
                            geomind_e8_rel_train_words(g_e8_rel_super_248x248, head_str, super_str, 0.92, 5.0);
                        }
                    }
                    geomind_e8_word_to_vec_248(lemma_str, g_e8_rel_tmp_v);
                    geomind_wordnet_insert_hash(lh, sh, head_lh, ic_val, sense_guard, g_e8_rel_tmp_v, hb3, hb2, hb1);
                } else {
                    geomind_e8_word_to_vec_248(lemma_str, g_e8_rel_tmp_u);
                    geomind_wordnet_insert_hash(lh, sh, head_lh, ic_val, sense_guard, g_e8_rel_tmp_u, hb3, hb2, hb1);
                    // Train Stratum 1 (Layers 0..6) asymmetric R_isa(hyponym -> hypernym_head) weighted by WordNet IC specificity
                    if (had_ckpt_rels == 0.0) {
                        var w_target = 0.50 + 0.042 * ic_val;
                        if (w_target > 0.94) { w_target = 0.94; }
                        var p = 0.0;
                        while (p < 5.0) {
                            geomind_e8_rel_train_step(g_e8_rel_isa_248x248, g_e8_rel_tmp_u, g_e8_rel_tmp_v, w_target, 1.0, 0.45);
                            p = p + 1.0;
                        }
                    }
                }
            }
            lh = 17.0;
            word_start = i + 1.0;
        } else {
            if (b >= 65.0 && b <= 90.0) { b = b + 32.0; }
            if ((b >= 97.0 && b <= 122.0) || (b >= 48.0 && b <= 57.0)) {
                lh = math_mod_val(lh * 131.0 + b, 1000003.0);
            }
        }
        i = i + 1.0;
    }
}

fn geomind_wordnet_init_if_needed() {
    if (g_wordnet_initialized == 1.0) { return; }
    g_wordnet_initialized = 1.0;
    g_wordnet_lemma_hash = cartan_tensor_alloc(4096.0);
    g_wordnet_synset_hash = cartan_tensor_alloc(4096.0);
    g_wordnet_head_hash = cartan_tensor_alloc(4096.0);
    g_wordnet_ic_weight = cartan_tensor_alloc(4096.0);
    g_wordnet_sense_guard = cartan_tensor_alloc(4096.0);
    g_wordnet_lemma_vecs = cartan_tensor_alloc(4096.0 * 248.0);
    g_wordnet_head_b3 = cartan_tensor_alloc(4096.0);
    g_wordnet_head_b2 = cartan_tensor_alloc(4096.0);
    g_wordnet_head_b1 = cartan_tensor_alloc(4096.0);

    g_wn_verb_to = geomind_word_patch_hash("to");
    g_wn_verb_can = geomind_word_patch_hash("can");
    g_wn_verb_will = geomind_word_patch_hash("will");
    g_wn_verb_not = geomind_word_patch_hash("not");
    g_wn_verb_do = geomind_word_patch_hash("do");
    g_wn_hash_is = geomind_word_patch_hash("is");
    g_wn_hash_a = geomind_word_patch_hash("a");
    g_wn_hash_an = geomind_word_patch_hash("an");
    g_wn_hash_the = geomind_word_patch_hash("the");
    g_wn_hash_and = geomind_word_patch_hash("and");
    g_wn_hash_in = geomind_word_patch_hash("in");
    g_wn_hash_on = geomind_word_patch_hash("on");
    g_wn_hash_when = geomind_word_patch_hash("when");
    g_wn_hash_it = geomind_word_patch_hash("it");
    g_wn_hash_you = geomind_word_patch_hash("you");
    g_wn_hash_likes = geomind_word_patch_hash("likes");
    g_wn_hash_because = geomind_word_patch_hash("because");

    geomind_e8_rel_init_if_needed();

    let tax_path = "Projects/geomind/trainingdata/wordnet_taxonomy.txt";
    if (cartan_file_exists(tax_path) == 1.0) {
        let content = cartan_read_file(tax_path);
        if (content != 0.0 && cartan_string_length(content) > 0.0) {
            let lines = string_split(content, "\n");
            let num_lines = cartan_tree_len_f(lines);
            var cur_path = "";
            var cur_lemmas = "";
            var cur_ic = 10.0;
            var cur_guard = 1.0;
            var i = 0.0;
            while (i < num_lines) {
                let raw_l = cartan_tree_get(lines, i);
                let line = cartan_string_replace(cartan_string_replace(raw_l, "\r", ""), "\n", "");
                let llen = cartan_string_length(line);
                if (llen == 0.0) {
                    if (cartan_string_length(cur_path) > 0.0) {
                        geomind_wordnet_register_node(cur_path, cur_lemmas, cur_ic, cur_guard);
                        cur_path = "";
                        cur_lemmas = "";
                        cur_ic = 10.0;
                        cur_guard = 1.0;
                    }
                } else if (cartan_string_starts_with(line, "Path: ") != 0.0) {
                    if (cartan_string_length(cur_path) > 0.0) {
                        geomind_wordnet_register_node(cur_path, cur_lemmas, cur_ic, cur_guard);
                        cur_lemmas = "";
                        cur_ic = 10.0;
                        cur_guard = 1.0;
                    }
                    cur_path = cartan_string_substring(line, 6.0, llen);
                } else if (cartan_string_starts_with(line, "Lemmas: ") != 0.0) {
                    cur_lemmas = cartan_string_substring(line, 8.0, llen);
                } else if (cartan_string_starts_with(line, "SenseGuard: verb") != 0.0) {
                    cur_guard = 2.0;
                } else if (cartan_string_starts_with(line, "SenseGuard: noun") != 0.0) {
                    cur_guard = 1.0;
                } else if (cartan_string_starts_with(line, "IC: ") != 0.0) {
                    cur_ic = geomind_parse_simple_float(cartan_string_substring(line, 4.0, llen));
                }
                i = i + 1.0;
            }
            if (cartan_string_length(cur_path) > 0.0) {
                geomind_wordnet_register_node(cur_path, cur_lemmas, cur_ic, cur_guard);
            }
        }
    }
}

// Compute the continuous 248x248 manifold hypernym weight S(word --[R_isa]--> head_hypernym) on S^{247}
fn geomind_wordnet_get_isa_manifold_weight(patch_hash: float) -> float {
    geomind_wordnet_init_if_needed();
    if (patch_hash <= 17.0) { return 0.0; }
    let h0 = math_mod_val(patch_hash * 13331.0, 4096.0);
    var probe = 0.0;
    var word_slot = -1.0;
    var head_lh = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 4096.0);
        let cur_l = cartan_vec_get_f32(g_wordnet_lemma_hash, slot);
        if (cur_l == 0.0) { return 0.0; }
        if (cur_l == patch_hash) {
            word_slot = slot;
            head_lh = cartan_vec_get_f32(g_wordnet_head_hash, slot);
            break;
        }
        probe = probe + 1.0;
    }
    if (word_slot < 0.0 || head_lh <= 17.0) { return 0.0; }
    if (head_lh == patch_hash) { return 1.0; }

    let hh0 = math_mod_val(head_lh * 13331.0, 4096.0);
    var hprobe = 0.0;
    var head_slot = -1.0;
    while (hprobe < 32.0) {
        let hslot = math_mod_val(hh0 + hprobe * 7.0, 4096.0);
        let hcur = cartan_vec_get_f32(g_wordnet_lemma_hash, hslot);
        if (hcur == 0.0) { break; }
        if (hcur == head_lh) {
            head_slot = hslot;
            break;
        }
        hprobe = hprobe + 1.0;
    }
    if (head_slot < 0.0) { return 0.85; }

    let u_base = word_slot * 248.0;
    let v_base = head_slot * 248.0;
    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_set_f32(g_e8_rel_tmp_u, d, cartan_vec_get_f32(g_wordnet_lemma_vecs, u_base + d));
        cartan_vec_set_f32(g_e8_rel_tmp_v, d, cartan_vec_get_f32(g_wordnet_lemma_vecs, v_base + d));
        d = d + 1.0;
    }
    return geomind_e8_rel_score_vec(g_e8_rel_isa_248x248, g_e8_rel_tmp_u, g_e8_rel_tmp_v);
}

// Resolve `patch_hash` to its canonical WordNet Synset ID (`700000..949999`), gated by syntactic `SenseGuard`
// AND continuous 248x248 manifold `R_isa` weight verification (`w_isa >= 0.35`).
fn geomind_wordnet_resolve_synset(patch_hash: float, prev_patch_hash: float) -> float {
    geomind_wordnet_init_if_needed();
    if (patch_hash <= 17.0) { return 0.0; }
    let h0 = math_mod_val(patch_hash * 13331.0, 4096.0);
    var probe = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 4096.0);
        let cur_l = cartan_vec_get_f32(g_wordnet_lemma_hash, slot);
        if (cur_l == 0.0) { return 0.0; }
        if (cur_l == patch_hash) {
            let guard = cartan_vec_get_f32(g_wordnet_sense_guard, slot);
            if (guard == 1.0) {
                if (prev_patch_hash == g_wn_verb_to || prev_patch_hash == g_wn_verb_can ||
                    prev_patch_hash == g_wn_verb_will || prev_patch_hash == g_wn_verb_not ||
                    prev_patch_hash == g_wn_verb_do) {
                    return 0.0;
                }
            }
            let head_lh = cartan_vec_get_f32(g_wordnet_head_hash, slot);
            if (head_lh != patch_hash) {
                let w_isa = geomind_wordnet_get_isa_manifold_weight(patch_hash);
                if (w_isa < 0.35) {
                    return 0.0;
                }
                g_markov_ctx_syn_weight = w_isa;
            } else {
                g_markov_ctx_syn_weight = 1.0;
            }
            return cartan_vec_get_f32(g_wordnet_synset_hash, slot);
        }
        probe = probe + 1.0;
    }
    return 0.0;
}

// Returns 1.0 if `patch_hash` is the canonical head prototype lemma of its WordNet synset (e.g. bird, ball, cat, dog, fish)
fn geomind_wordnet_is_head_lemma(patch_hash: float) -> float {
    geomind_wordnet_init_if_needed();
    if (patch_hash <= 17.0) { return 0.0; }
    let h0 = math_mod_val(patch_hash * 13331.0, 4096.0);
    var probe = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 4096.0);
        let cur_l = cartan_vec_get_f32(g_wordnet_lemma_hash, slot);
        if (cur_l == 0.0) { return 0.0; }
        if (cur_l == patch_hash) {
            if (cartan_vec_get_f32(g_wordnet_head_hash, slot) == patch_hash) {
                return 1.0;
            }
            return 0.0;
        }
        probe = probe + 1.0;
    }
    return 0.0;
}

// Resolve `patch_hash` to its hypernym head lemma's 3-byte suffix `(hb3, hb2, hb1)` when `patch_hash` is a valid SenseGuarded WordNet member
fn geomind_wordnet_resolve_head_suffix(patch_hash: float, prev_patch_hash: float, out_b321: ptr) -> float {
    if (geomind_wordnet_resolve_synset(patch_hash, prev_patch_hash) <= 0.0) { return 0.0; }
    let h0 = math_mod_val(patch_hash * 13331.0, 4096.0);
    var probe = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 4096.0);
        let cur_l = cartan_vec_get_f32(g_wordnet_lemma_hash, slot);
        if (cur_l == 0.0) { return 0.0; }
        if (cur_l == patch_hash) {
            cartan_vec_set_f32(out_b321, 0.0, cartan_vec_get_f32(g_wordnet_head_b3, slot));
            cartan_vec_set_f32(out_b321, 1.0, cartan_vec_get_f32(g_wordnet_head_b2, slot));
            cartan_vec_set_f32(out_b321, 2.0, cartan_vec_get_f32(g_wordnet_head_b1, slot));
            return 1.0;
        }
        probe = probe + 1.0;
    }
    return 0.0;
}

fn geomind_wordnet_get_ic(patch_hash: float) -> float {
    geomind_wordnet_init_if_needed();
    if (patch_hash <= 17.0) { return 8.0; }
    let h0 = math_mod_val(patch_hash * 13331.0, 4096.0);
    var probe = 0.0;
    while (probe < 32.0) {
        let slot = math_mod_val(h0 + probe * 7.0, 4096.0);
        let cur_l = cartan_vec_get_f32(g_wordnet_lemma_hash, slot);
        if (cur_l == 0.0) { return 8.0; }
        if (cur_l == patch_hash) {
            return cartan_vec_get_f32(g_wordnet_ic_weight, slot);
        }
        probe = probe + 1.0;
    }
    return 8.0;
}
