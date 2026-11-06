// Projects/geomind/e8_curriculum.cl
// Deep 42-Layer E8 Corpus Trainer & 4-Rung Concentric English Curriculum Runner

include "src/std/geom.cl";
include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/fs.cl";
include "Projects/geomind/geometry.cl";
include "Projects/geomind/e8_stack.cl";

// Configurable curriculum dataset paths and checkpoint directory:
var g_curriculum_rung1_path: string = "Projects/geomind/trainingdata/e8_nursery_primer.txt";
var g_curriculum_rung2_path: string = "Projects/geomind/trainingdata/e8_concept_triples.txt";
var g_curriculum_rung3_path: string = "Projects/geomind/trainingdata/storytelling_chunks/chunk_001_t1_TinyStories_Curated.txt";
var g_curriculum_chunk_modern_path: string = "Projects/geomind/trainingdata/storytelling_chunks/chunk_005_t1_GeoMind_Modern_Narratives.txt";
var g_curriculum_chunk_alice_path: string = "Projects/geomind/trainingdata/storytelling_chunks/chunk_007_t2_Alice_In_Wonderland.txt";
var g_curriculum_chunk_anthem_path: string = "Projects/geomind/trainingdata/storytelling_chunks/chunk_019_t2_Anthem.txt";
var g_curriculum_chunk_sherlock_path: string = "Projects/geomind/trainingdata/storytelling_chunks/chunk_028_t3_Sherlock_Holmes.txt";
var g_curriculum_checkpoint_dir: string = "Projects/geomind/trainingdata/checkpoints";
var g_curriculum_gguf_path: string = "Projects/geomind/trainingdata/checkpoints/cartan_e8_42L.gguf";

fn geomind_curriculum_set_rung1_path(p: string) { g_curriculum_rung1_path = p; }
fn geomind_curriculum_set_rung2_path(p: string) { g_curriculum_rung2_path = p; }
fn geomind_curriculum_set_rung3_path(p: string) { g_curriculum_rung3_path = p; }
fn geomind_curriculum_set_checkpoint_dir(p: string) { g_curriculum_checkpoint_dir = p; }
fn geomind_curriculum_set_gguf_path(p: string) { g_curriculum_gguf_path = p; }

// Train the 248-D E8 Byte-Latent + Markov-Lagrangian engine over a UTF-8 text corpus for `epochs`
// Uses Sherman-Morrison inverse Finsler-Randers gradient descent (`geom_frs_riemannian_gradient_step`)
// and exact Adjoint Gauge-Spinor Cross-Gate Backpropagation + Geodesic Kinetic Energy Restoring Force
// Returns the final epoch average Lagrangian Action S = T * (1 - 0.5 * V)
fn geomind_byte_latent_train_corpus(corpus: string, epochs: float, lr: float, record_vis: float) -> float {
    geomind_byte_latent_init_if_needed();
    let n_bytes = cartan_string_length(corpus);
    if (n_bytes < 2.0) { return 0.0; }

    // Index S^{247} sentence basins and train narrative relational operators if large chunk:
    var train_narr = 0.0;
    if (n_bytes >= 4000.0) { train_narr = 1.0; }
    geomind_e8_index_corpus_sentence_basins(corpus, train_narr);

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


fn geomind_byte_latent_train_deep_e8_corpus(
    corpus: string,
    num_layers: float,
    epochs: float,
    lr: float,
    record_vis: float
) -> float {
    geomind_byte_latent_init_if_needed();
    var L = floor(num_layers);
    if (L < 1.0) { L = 42.0; }
    let was_stack_init = g_e8_stack_initialized;
    geomind_e8_stack_init(L);
    if (was_stack_init == 0.0 && cartan_file_exists("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin") == 1.0) {
        geomind_e8_stack_load("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin");
    }

    let n_bytes = cartan_string_length(corpus);
    if (n_bytes < 2.0) { return 0.0; }

    // Index S^{247} sentence basins and train narrative relational operators if large chunk:
    var train_narr = 0.0;
    if (n_bytes >= 4000.0) { train_narr = 1.0; }
    geomind_e8_index_corpus_sentence_basins(corpus, train_narr);

    var num_epochs = 1.0;
    if (epochs > 1.0) { num_epochs = epochs; }
    var eff_lr = 0.025;
    if (lr > 0.00001) { eff_lr = lr; }

    let h_prev_local = cartan_vec_create();
    let h_pre_local = cartan_vec_create();
    let h_local = cartan_vec_create();
    let h_patch_accum = cartan_vec_create();
    let h_prev_patch = cartan_vec_create();
    let h_top_patch = cartan_vec_create();
    let dh_local = cartan_vec_create();
    let dh_pre_local = cartan_vec_create();
    let dh_patch_accum = cartan_vec_create();
    let dh_in_stack = cartan_vec_create();
    let geo_grad = cartan_vec_create();
    let emb_vec = cartan_vec_create();
    let p_v4 = cartan_vec_create();
    let p_v3 = cartan_vec_create();
    let p_v2 = cartan_vec_create();
    let p_v1 = cartan_vec_create();
    let p_v0 = cartan_vec_create();
    let cur_p_vec = cartan_vec_create();
    let logits_256 = cartan_vec_create();
    let delta_256 = cartan_vec_create();

    var d = 0.0;
    while (d < 248.0) {
        cartan_vec_push_f32(h_prev_local, 0.0);
        cartan_vec_push_f32(h_pre_local, 0.0);
        cartan_vec_push_f32(h_local, 0.0);
        cartan_vec_push_f32(h_patch_accum, 0.0);
        cartan_vec_push_f32(h_prev_patch, 0.0);
        cartan_vec_push_f32(h_top_patch, 0.0);
        cartan_vec_push_f32(dh_local, 0.0);
        cartan_vec_push_f32(dh_pre_local, 0.0);
        cartan_vec_push_f32(dh_patch_accum, 0.0);
        cartan_vec_push_f32(dh_in_stack, 0.0);
        cartan_vec_push_f32(geo_grad, 0.0);
        cartan_vec_push_f32(emb_vec, 0.0);
        cartan_vec_push_f32(p_v4, 0.0);
        cartan_vec_push_f32(p_v3, 0.0);
        cartan_vec_push_f32(p_v2, 0.0);
        cartan_vec_push_f32(p_v1, 0.0);
        cartan_vec_push_f32(p_v0, 0.0);
        cartan_vec_push_f32(cur_p_vec, 0.0);
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
        var patch_steps_taken = 0.0;
        d = 0.0;
        while (d < 248.0) {
            cartan_vec_set_f32(h_prev_local, d, 0.0);
            cartan_vec_set_f32(h_pre_local, d, 0.0);
            cartan_vec_set_f32(h_local, d, 0.0);
            cartan_vec_set_f32(h_patch_accum, d, 0.0);
            cartan_vec_set_f32(h_prev_patch, d, 0.0);
            cartan_vec_set_f32(h_top_patch, d, 0.0);
            cartan_vec_set_f32(dh_patch_accum, d, 0.0);
            d = d + 1.0;
        }

        var step = 0.0;
        var b3 = 32.0;
        var b2 = 32.0;
        var cur_b = 32.0;
        var next_b = 32.0;
        var patch_len = 0.0;
        var patch_alnum_len = 0.0;
        var patch_word_start = 0.0;
        var patch_word_end = 0.0;
        var patch_hash = 17.0;
        var patch_sent_end = 0.0;
        var patch_comma_end = 0.0;
        var patch_act_sum = 0.0;
        var focus_horizon = 0.0;
        var stack_t_geo = 0.0;
        var p_h4 = 17.0;
        var p_h3 = 17.0;
        var p_h2 = 17.0;
        var p_h1 = 17.0;
        var p_h0 = 17.0;
        var sent_word_idx = 0.0;
        var sent_first_h = 17.0;
        var sent_second_h = 17.0;
        var sent_subj_h = 17.0;
        var sent_verb_h = 17.0;
        var sent_act_h = 17.0;
        var sent_cond_obj_h = 17.0;
        var sent_cause_h = 17.0;
        geomind_markov_reset_patch_context();

        while (step < max_steps) {
            cur_b = cartan_byte_at(corpus, step);
            if (cur_b < 0.0) { cur_b = cur_b + 256.0; }
            next_b = cartan_byte_at(corpus, step + 1.0);
            if (next_b < 0.0) { next_b = next_b + 256.0; }
            cur_b = math_mod_val(floor(cur_b), 256.0);
            next_b = math_mod_val(floor(next_b), 256.0);
            var is_para_break = 0.0;
            if (cur_b == 10.0) { is_para_break = 1.0; }
            // Normalize CR/LF line breaks to space (32) so multi-line corpora form continuous printable byte streams
            if (cur_b == 13.0 || cur_b == 10.0) { cur_b = 32.0; }
            if (next_b == 13.0 || next_b == 10.0) { next_b = 32.0; }
            if (cur_b == 32.0 && next_b == 32.0) {
                if (is_para_break == 1.0) {
                    geomind_markov_reset_patch_context();
                    p_h4 = 17.0;
                    p_h3 = 17.0;
                    p_h2 = 17.0;
                    p_h1 = 17.0;
                    p_h0 = 17.0;
                    sent_word_idx = 0.0;
                    sent_first_h = 17.0;
                    sent_second_h = 17.0;
                    sent_subj_h = 17.0;
                    sent_verb_h = 17.0;
                    sent_act_h = 17.0;
                    sent_cond_obj_h = 17.0;
                    sent_cause_h = 17.0;
                }
                step = step + 1.0;
                continue;
            }

            // 1. Fold alphanumeric stem byte into current 248-D E8 Patch Accumulator (ignoring punctuation/space)
            let is_alnum = ((cur_b >= 97.0 && cur_b <= 122.0) || (cur_b >= 65.0 && cur_b <= 90.0) || (cur_b >= 48.0 && cur_b <= 57.0));
            if (is_alnum) {
                if (patch_alnum_len == 0.0) { patch_word_start = step; }
                patch_word_end = step + 1.0;
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
                if (step == 0.0) {
                    cartan_vec_set_f32(h_pre_local, d, e_d);
                } else {
                    cartan_vec_set_f32(h_pre_local, d, loc_d);
                }
                d = d + 1.0;
            }
            if (step > 0.0) {
                geom_retract_sphere_step(h_pre_local, emb_vec, 0.55);
            }
            geomind_weyl_reflect_vector_248(h_pre_local, math_mod_val(cur_b, 240.0));

            // 2. Tier 1 (Every Byte): Fast Local 120 (+) 128 Gauge-Spinor Cross-Gate
            geomind_e8_gauge_spinor_cross_gate(h_pre_local, h_local, 0.25);

            // 3. Tier 2 (Invariant Morphological/Delimiter Patch Boundary & Selective Resonance Focus Filter):
            let is_patch_boundary = ((cur_b == 32.0 || patch_len >= 16.0 || step == (max_steps - 1.0)) && patch_hash != 17.0);
            var saved_patch_hash = patch_hash;
            var patch_res = 0.0;
            var in_focus = 1.0;

            if (is_patch_boundary) {
                if (g_e8_primer_crystallize_all == 1.0) {
                    in_focus = 1.0;
                    g_e8_focus_hits = g_e8_focus_hits + 1.0;
                } else if (g_e8_anchor_count > 0.0) {
                    patch_res = geomind_e8_query_anchor_resonance(h_patch_accum, patch_hash);
                    if (patch_res >= 0.85) {
                        // Child heard a resonant Anchor concept! Open Laser-Focus Window for (i + 1) neighbor:
                        focus_horizon = 1.0;
                        in_focus = 1.0;
                        g_e8_focus_hits = g_e8_focus_hits + 1.0;
                    } else if (focus_horizon > 0.0) {
                        // Neighbor patch inside the active (i + 1) Laser-Focus Window:
                        in_focus = 1.0;
                        focus_horizon = focus_horizon - 1.0;
                        g_e8_focus_hits = g_e8_focus_hits + 1.0;
                    } else {
                        // "Blah Blah Blah" Uncomprehended Noise State: suppress 42-layer plasticity!
                        in_focus = 0.0;
                        g_e8_noise_skips = g_e8_noise_skips + 1.0;
                    }
                }

                sent_word_idx = sent_word_idx + 1.0;
                if (ep == 0.0 && patch_alnum_len >= 2.0 && geomind_e8_has_vocab_hash(saved_patch_hash) == 0.0) {
                    let raw_w = cartan_string_substring(corpus, patch_word_start, patch_word_end);
                    let low_w = cartan_string_to_lower(raw_w);
                    geomind_e8_register_vocab_word(low_w);
                }
                geomind_e8_hash_to_vec_248(saved_patch_hash, cur_p_vec);
                if (sent_word_idx == 1.0) { sent_first_h = saved_patch_hash; }
                if (sent_word_idx == 2.0) { sent_second_h = saved_patch_hash; }
                if (p_h1 == g_wn_hash_a && saved_patch_hash != g_wn_hash_is && saved_patch_hash != g_wn_verb_can && sent_subj_h == 17.0) {
                    sent_subj_h = p_h0;
                    sent_act_h = saved_patch_hash;
                }

                if (in_focus == 1.0) {
                    d = 0.0;
                    while (d < 248.0) {
                        cartan_vec_set_f32(h_prev_patch, d, cartan_vec_get_f32(h_top_patch, d));
                        d = d + 1.0;
                    }
                    var prev_patch_ptr: ptr = 0.0;
                    if (patch_steps_taken > 0.0) { prev_patch_ptr = h_prev_patch; }
                    let mv_step = geomind_markov_get_prob(b2, cur_b);
                    stack_t_geo = geomind_e8_stack_forward_step(h_patch_accum, prev_patch_ptr, mv_step, 0.85, h_top_patch);
                    patch_steps_taken = patch_steps_taken + 1.0;

                    // Stage 7.0: Position-Independent Closed-Class Syntactic Frame Extractor for all 6 Strata
                    // Frame 1 (Stratum 1 & Stratum 3): Taxonomic & Property Copula ("a/the <Subj> is a <Adj> <Hypernym>")
                    // Note: Stratum 2 (`R_super`, e.g., `bird -> animal`) is anchored directly by `wordnet_taxonomy.txt`.
                    if ((p_h4 == g_wn_hash_a || p_h4 == g_wn_hash_the) && p_h3 != 17.0 && p_h2 == g_wn_hash_is && p_h1 == g_wn_hash_a && p_h0 != 17.0) {
                        if (geomind_wordnet_is_head_lemma(p_h3) == 0.0) {
                            geomind_e8_rel_train_step(g_e8_rel_isa_248x248, p_v3, cur_p_vec, 0.92, 1.0, 0.45);
                        }
                        geomind_e8_rel_train_step(g_e8_rel_prop_248x248, p_v3, p_v0, 0.90, 1.0, 0.45);
                    }
                    // Frame 2 (Stratum 3 & Stratum 4): Attributive, Gerund, & Affective State Copulas
                    //   - "<Gerund> a <Noun> is <Valence>" ("Bouncing a ball is fun")
                    //   - "<Subj> <Verb> when it is <State>" ("A gentle cat purrs when it is happy")
                    //   - "[The/A] <Subj> is <Prop>" ("The ball is round", "Water is clear")
                    if (p_h1 != 17.0 && p_h0 == g_wn_hash_is && saved_patch_hash != g_wn_hash_a && saved_patch_hash != g_wn_hash_the) {
                        if (p_h3 != 17.0 && p_h2 == g_wn_hash_a) {
                            geomind_e8_rel_train_step(g_e8_rel_prop_248x248, p_v3, cur_p_vec, 0.92, 1.0, 0.45);
                            geomind_e8_rel_train_step(g_e8_rel_val_248x248, p_v3, cur_p_vec, 0.92, 1.0, 0.45);
                        } else if (p_h4 != 17.0 && p_h2 == g_wn_hash_when && p_h1 == g_wn_hash_it) {
                            geomind_e8_rel_train_step(g_e8_rel_cap_248x248, p_v4, p_v3, 0.92, 1.0, 0.45);
                            geomind_e8_rel_train_step(g_e8_rel_val_248x248, p_v3, cur_p_vec, 0.92, 1.0, 0.45);
                        } else if (p_h2 == 17.0 || p_h2 == g_wn_hash_the || p_h2 == g_wn_hash_a) {
                            geomind_e8_rel_train_step(g_e8_rel_prop_248x248, p_v1, cur_p_vec, 0.90, 1.0, 0.45);
                        }
                    }
                    // Frame 3 (Stratum 3 & Stratum 4): Modal Capability, Transitive Affordance, & Action-Locus Frames
                    //   - "A/The <Subj> can <Verb> ... in the [Adj] <Locus>." ("A bird can fly high in the sky.", "The penguin can swim in the cold ocean.")
                    //   - "You can <Verb> the <Obj> on the <Locus>" ("You can bounce the ball on the ground")
                    //   - "A <Subj> <Verb> in the <Adj> <Locus>." ("A fish swims in the deep water.")
                    if ((p_h2 == g_wn_hash_a || p_h2 == g_wn_hash_the) && p_h1 != 17.0 && p_h0 == g_wn_verb_can) {
                        if (geomind_wordnet_resolve_synset(p_h1, 17.0) == 0.0 || geomind_wordnet_is_head_lemma(p_h1) == 1.0) {
                            geomind_e8_rel_train_step(g_e8_rel_cap_248x248, p_v1, cur_p_vec, 0.92, 1.0, 0.45);
                        }
                        sent_verb_h = saved_patch_hash;
                    }
                    if (patch_sent_end == 1.0 && sent_verb_h != 17.0 &&
                        ((p_h1 == g_wn_hash_in && p_h0 == g_wn_hash_the) || (p_h2 == g_wn_hash_in && p_h1 == g_wn_hash_the))) {
                        geomind_e8_hash_to_vec_248(sent_verb_h, g_e8_rel_tmp_u);
                        geomind_e8_rel_train_step(g_e8_rel_val_248x248, g_e8_rel_tmp_u, cur_p_vec, 0.92, 1.0, 0.45);
                        sent_verb_h = 17.0;
                    }
                    if (p_h4 == g_wn_verb_can && p_h2 == g_wn_hash_the && p_h0 == g_wn_hash_on && saved_patch_hash == g_wn_hash_the) {
                        geomind_e8_rel_train_step(g_e8_rel_cap_248x248, p_v1, p_v3, 0.92, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_prop_248x248, p_v3, g_e8_vec_fun, 0.90, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_val_248x248, p_v3, g_e8_vec_fun, 0.92, 1.0, 0.45);
                    }
                    if (patch_sent_end == 1.0 && p_h2 == g_wn_hash_in && p_h1 == g_wn_hash_the && sent_subj_h != 17.0 && sent_act_h != 17.0) {
                        geomind_e8_hash_to_vec_248(sent_subj_h, g_e8_rel_tmp_u);
                        geomind_e8_hash_to_vec_248(sent_act_h, g_e8_rel_tmp_v);
                        geomind_e8_rel_train_step(g_e8_rel_cap_248x248, g_e8_rel_tmp_u, g_e8_rel_tmp_v, 0.92, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_val_248x248, g_e8_rel_tmp_v, cur_p_vec, 0.92, 1.0, 0.45);
                    }
                    // Frame 4 (Stratum 3 & Stratum 4): Hedonic Preference ("<Subj> likes to <Verb> in ..." / "likes to <Verb1> and <Verb2>")
                    if ((p_h1 == g_wn_hash_likes && p_h0 == g_wn_verb_to) ||
                        (p_h3 == g_wn_hash_likes && p_h2 == g_wn_verb_to && p_h0 == g_wn_hash_and)) {
                        geomind_e8_rel_train_step(g_e8_rel_prop_248x248, cur_p_vec, g_e8_vec_fun, 0.90, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_val_248x248, cur_p_vec, g_e8_vec_fun, 0.92, 1.0, 0.45);
                    }
                    if (p_h2 == g_wn_hash_likes && p_h1 == g_wn_verb_to && saved_patch_hash == g_wn_hash_in) {
                        geomind_e8_rel_train_step(g_e8_rel_cap_248x248, p_v3, p_v0, 0.92, 1.0, 0.45);
                    }
                    // Frame 5 (Stratum 5 & Stratum 6): Causal Explanation ("<Subj> <EffectVerb> ... because <Subj> is <CauseAdj>")
                    if (p_h2 == g_wn_hash_because && p_h1 == sent_first_h && p_h0 == g_wn_hash_is && sent_second_h != 17.0) {
                        geomind_e8_rel_train_step(g_e8_rel_cause_248x248, p_v1, cur_p_vec, 0.92, 1.0, 0.45);
                        geomind_e8_rel_train_step(g_e8_rel_prop_248x248, p_v1, cur_p_vec, 0.90, 1.0, 0.45);
                        geomind_e8_hash_to_vec_248(sent_second_h, g_e8_rel_tmp_v);
                        geomind_e8_rel_train_step(g_e8_rel_effect_248x248, cur_p_vec, g_e8_rel_tmp_v, 0.92, 1.0, 0.45);
                    }
                    // Frame 6 (Stratum 5 & Stratum 6): Conditional Physical Cause-Effect ("When you <Act> a <Subj>, <Force> ... to the <Dest>.")
                    if (p_h3 == g_wn_hash_when && p_h2 == g_wn_hash_you && p_h0 == g_wn_hash_a && patch_comma_end == 1.0) {
                        sent_cond_obj_h = saved_patch_hash;
                    }
                    if (p_h0 == sent_cond_obj_h && sent_cond_obj_h != 17.0) {
                        geomind_e8_rel_train_step(g_e8_rel_cause_248x248, p_v0, cur_p_vec, 0.92, 1.0, 0.45);
                        sent_cause_h = saved_patch_hash;
                        sent_cond_obj_h = 17.0;
                    }
                    if (patch_sent_end == 1.0 && p_h1 == g_wn_verb_to && p_h0 == g_wn_hash_the && sent_cause_h != 17.0) {
                        geomind_e8_hash_to_vec_248(sent_cause_h, g_e8_rel_tmp_u);
                        geomind_e8_rel_train_step(g_e8_rel_effect_248x248, g_e8_rel_tmp_u, cur_p_vec, 0.92, 1.0, 0.45);
                    }
                }

                if (is_para_break == 1.0 || patch_sent_end == 1.0) {
                    p_h4 = 17.0;
                    p_h3 = 17.0;
                    p_h2 = 17.0;
                    p_h1 = 17.0;
                    p_h0 = 17.0;
                    sent_word_idx = 0.0;
                    sent_first_h = 17.0;
                    sent_second_h = 17.0;
                    sent_subj_h = 17.0;
                    sent_verb_h = 17.0;
                    sent_act_h = 17.0;
                    sent_cond_obj_h = 17.0;
                    sent_cause_h = 17.0;
                } else {
                    p_h4 = p_h3;
                    p_h3 = p_h2;
                    p_h2 = p_h1;
                    p_h1 = p_h0;
                    p_h0 = saved_patch_hash;
                    d = 0.0;
                    while (d < 248.0) {
                        cartan_vec_set_f32(p_v4, d, cartan_vec_get_f32(p_v3, d));
                        cartan_vec_set_f32(p_v3, d, cartan_vec_get_f32(p_v2, d));
                        cartan_vec_set_f32(p_v2, d, cartan_vec_get_f32(p_v1, d));
                        cartan_vec_set_f32(p_v1, d, cartan_vec_get_f32(p_v0, d));
                        cartan_vec_set_f32(p_v0, d, cartan_vec_get_f32(cur_p_vec, d));
                        d = d + 1.0;
                    }
                }

                geomind_markov_advance_patch_context(patch_hash, patch_alnum_len, is_para_break, patch_sent_end, patch_comma_end);
                patch_sent_end = 0.0;
                patch_comma_end = 0.0;
                patch_alnum_len = 0.0;
            }

            // 4. Decode 256 byte logits from fused (h_local, h_top_patch) + pre-update 3-gram Markov prior
            let markov_v = geomind_markov_get_3gram_prob(b3, b2, cur_b, next_b);
            geomind_byte_latent_decode_logits_blt(h_local, h_top_patch, b3, b2, cur_b, logits_256);
            if (is_para_break == 0.0) {
                geomind_markov_update_3gram(b3, b2, cur_b, next_b);
            }

            // 5. Evaluate Markov-Lagrangian Action Loss
            let base_act = geomind_lagrangian_action_step(
                logits_256, next_b, cur_b, h_prev_local, h_local, g_byte_e8_randers_b_248, delta_256
            );
            let well_factor = 1.0 - 0.5 * markov_v;
            let act_s = base_act + 0.04 * stack_t_geo * well_factor;
            epoch_action_sum = epoch_action_sum + act_s;
            patch_act_sum = patch_act_sum + act_s;

            // 6. Geodesic Kinetic Energy Restoring Force & Readout Head Backprop (Gated by Selective Focus)
            var local_lr_scale = 1.0;
            if (g_e8_primer_crystallize_all == 0.0 && g_e8_anchor_count > 0.0 && in_focus == 0.0 && focus_horizon <= 0.0) {
                local_lr_scale = 0.05; // 95% plasticity suppression during "blah blah blah" noise
            }
            geomind_e8_geodesic_kinetic_grad_248(h_prev_local, h_local, g_byte_e8_randers_b_248, geo_grad, 0.12 * well_factor);

            d = 0.0;
            while (d < 248.0) {
                let hl_d = cartan_vec_get_f32(h_local, d);
                let hp_d = cartan_vec_get_f32(h_top_patch, d);
                // Match forward pass 0.5 * hl + 0.5 * hp readout scale in geomind_byte_latent_decode_logits_blt
                var h_comb = hl_d;
                if (patch_steps_taken > 0.0) {
                    h_comb = 0.5 * hl_d + 0.5 * hp_d;
                }
                let b_d = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
                var dh_d = cartan_vec_get_f32(geo_grad, d);

                c = 32.0;
                while (c <= 126.0) {
                    let del_c = cartan_vec_get_f32(delta_256, c);
                    if (math_abs_val(del_c) > 0.005) {
                        let w_dc = cartan_vec_get_f32(g_byte_e8_head_248x256, d * 256.0 + c);
                        dh_d = dh_d + w_dc * del_c;
                        let new_w = geom_frs_riemannian_gradient_step(w_dc, h_comb * del_c * 4.0, b_d, eff_lr * local_lr_scale);
                        cartan_vec_set_f32(g_byte_e8_head_248x256, d * 256.0 + c, new_w);
                    }
                    c = c + 1.0;
                }
                cartan_vec_set_f32(dh_local, d, 0.5 * dh_d * local_lr_scale);
                cartan_vec_set_f32(dh_patch_accum, d, cartan_vec_get_f32(dh_patch_accum, d) + 0.5 * dh_d * local_lr_scale);
                d = d + 1.0;
            }

            // 7. Tier 1 Backward: Adjoint Local Cross-Gate -> Byte Embedding Update
            geomind_e8_gauge_spinor_cross_gate_backward(h_pre_local, dh_local, dh_pre_local, 0.25);

            // 8. Tier 2 Backward (At Patch Boundary):
            // Only backpropagate through the 42-Layer Deep E8 Stack if in_focus == 1.0!
            // If this neighbor patch inside the focus window achieved low Lagrangian Action, crystallize it as a new Anchor!
            if (is_patch_boundary) {
                let avg_patch_act = patch_act_sum / patch_len;
                if (in_focus == 1.0) {
                    geomind_e8_stack_backward_step(dh_patch_accum, eff_lr * 0.15, 0.04 * well_factor, dh_in_stack);
                    // Automatic Frontier Crystallization: Rung 1 Primer crystallizes all words (patch_len >= 2.0),
                    // while Rung 2/3 Frontier Crystallization crystallizes stabilized neighbor content words (patch_len >= 4.0)
                    var min_cryst_len = 4.0;
                    if (g_e8_primer_crystallize_all == 1.0) { min_cryst_len = 2.0; }
                    if ((g_e8_primer_crystallize_all == 1.0 || g_e8_anchor_count > 0.0) && patch_len >= min_cryst_len && avg_patch_act <= 1.35) {
                        geomind_e8_crystallize_patch_vec(h_patch_accum, saved_patch_hash, 0.60);
                    }
                }
                d = 0.0;
                while (d < 248.0) {
                    if (in_focus == 1.0) {
                        cartan_vec_set_f32(dh_pre_local, d, cartan_vec_get_f32(dh_pre_local, d) + 0.35 * cartan_vec_get_f32(dh_in_stack, d));
                    }
                    cartan_vec_set_f32(dh_patch_accum, d, 0.0);
                    cartan_vec_set_f32(h_patch_accum, d, 0.0);
                    d = d + 1.0;
                }
                patch_len = 0.0;
                patch_hash = 17.0;
                patch_act_sum = 0.0;
            }

            // 9. Update Byte-to-E8 Embedding row and Finsler-Randers Drift 1-form beta
            var emb_nsq = 0.0;
            d = 0.0;
            while (d < 248.0) {
                let dp_d = cartan_vec_get_f32(dh_pre_local, d);
                let b_d = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
                let old_emb = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                var new_emb = geom_frs_riemannian_gradient_step(old_emb, dp_d, b_d, eff_lr * 0.015);
                if (new_emb > old_emb + 0.008) { new_emb = old_emb + 0.008; }
                else if (new_emb < old_emb - 0.008) { new_emb = old_emb - 0.008; }
                cartan_vec_set_f32(g_byte_e8_emb_256x248, row_off + d, new_emb);
                emb_nsq = emb_nsq + new_emb * new_emb;

                let h_d = cartan_vec_get_f32(h_local, d);
                let old_h = cartan_vec_get_f32(h_prev_local, d);
                var new_b = b_d - eff_lr * 0.005 * well_factor * (h_d - old_h);
                if (new_b > 0.08) { new_b = 0.08; }
                else if (new_b < -0.08) { new_b = -0.08; }
                cartan_vec_set_f32(g_byte_e8_randers_b_248, d, new_b);
                d = d + 1.0;
            }
            if (emb_nsq > 0.000001) {
                let emb_sc = sqrt(5.58 / emb_nsq);
                d = 0.0;
                while (d < 248.0) {
                    cartan_vec_set_f32(g_byte_e8_emb_256x248, row_off + d, cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d) * emb_sc);
                    d = d + 1.0;
                }
            }

            b3 = b2;
            b2 = cur_b;
            step = step + 1.0;
        }

        g_blt_last_patch_count = patch_steps_taken;
        final_avg_action = epoch_action_sum / max_steps;
        if (record_vis == 1.0) {
            let mv = geomind_markov_get_3gram_prob(b3, b2, cur_b, next_b);
            geomind_visualizer_record_step(final_avg_action, h_top_patch, mv);
        }
        ep = ep + 1.0;
    }

    if (g_byte_e8_defer_disk_save == 0.0) {
        geomind_markov_save_prior("Projects/geomind/trainingdata/checkpoints/geomind_markov_prior.bin");
        geomind_byte_latent_save_weights("Projects/geomind/trainingdata/checkpoints/geomind_byte_latent_e8.bin");
        geomind_e8_stack_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin");
        geomind_e8_rel_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_rel_tensors.bin");
        if (g_e8_anchor_count > 0.0) {
            geomind_e8_anchors_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_anchors.bin");
        }
    }

    cartan_vec_free(h_prev_local);
    cartan_vec_free(h_pre_local);
    cartan_vec_free(h_local);
    cartan_vec_free(h_patch_accum);
    cartan_vec_free(h_prev_patch);
    cartan_vec_free(h_top_patch);
    cartan_vec_free(dh_local);
    cartan_vec_free(dh_pre_local);
    cartan_vec_free(dh_patch_accum);
    cartan_vec_free(dh_in_stack);
    cartan_vec_free(geo_grad);
    cartan_vec_free(emb_vec);
    cartan_vec_free(p_v4);
    cartan_vec_free(p_v3);
    cartan_vec_free(p_v2);
    cartan_vec_free(p_v1);
    cartan_vec_free(p_v0);
    cartan_vec_free(cur_p_vec);
    cartan_vec_free(logits_256);
    cartan_vec_free(delta_256);
    return final_avg_action;
}

// Autoregressive generation through the Two-Tier BLT Deep L-Layer E8 Gauge-Spinor Stack
// Tier 1 steps every byte with 3-gram Markov + local Weyl/Fano; Tier 2 steps the 42-Layer E8 Stack at patch boundaries.

// ============================================================================
// STAGE 5.3: 4-RUNG CONCENTRIC ENGLISH DEVELOPMENTAL CURRICULUM (--curriculum)
// ============================================================================
// Rung 1: Nursery Primer (`e8_nursery_primer.txt`) - Full Foundation Mode, crystallizes core English SVO + glue anchors.
// Rung 2: Grounded Concept Triples (`e8_concept_triples.txt`) - Selective Resonance Focus around Rung 1 anchors.
// Rung 3: Multi-Pass TinyStories (`hf_roneneldan_TinyStories.txt`) - Progressive comprehension expansion across passes.
// Rung 4: Digestible Storytelling Chunks (`storytelling_chunks/`) - Multi-genre narratives & classical literature.
fn geomind_run_english_curriculum(num_layers: float, lr: float) -> float {
    var L = floor(num_layers);
    if (L < 1.0) { L = 42.0; }
    var eff_lr = 0.03;
    if (lr > 0.0001) { eff_lr = lr; }

    printf("\n================================================================================\n");
    printf("  CARTAN-E8 CONCENTRIC ENGLISH DEVELOPMENTAL CURRICULUM (L=%.0f Layers)\n", L);
    printf("================================================================================\n");
    cartan_flush(0.0);

    // Start from a clean Anchor Basin registry, Markov Tapestry, Relational Codebook, and 42-Layer E8 Stack
    g_byte_e8_skip_disk_autoload = 1.0;
    g_byte_e8_defer_disk_save = 1.0;
    g_e8_sent_basins_indexed = 0.0;
    g_markov_initialized = 0.0;
    geomind_markov_init_if_needed();
    g_byte_e8_initialized = 0.0;
    geomind_byte_latent_init_if_needed();
    g_e8_rel_initialized = 0.0;
    g_wordnet_initialized = 0.0;
    geomind_wordnet_init_if_needed();
    g_byte_e8_skip_disk_autoload = 0.0;
    g_e8_stack_initialized = 0.0;
    geomind_e8_stack_init(L);
    geomind_e8_anchors_reset();
    geomind_visualizer_reset();

    // ------------------------------------------------------------------------
    // RUNG 1: Nursery Primer (Atomic SVO & Glue Words - 100% Foundation Focus)
    // ------------------------------------------------------------------------
    let rung1_path = g_curriculum_rung1_path;
    var rung1_text = "The ball is round and red. You can throw the ball. You can bounce the ball on the ground. Bouncing a ball is fun. Water is clear and wet.";
    if (cartan_file_exists(rung1_path) == 1.0) {
        rung1_text = cartan_read_file(rung1_path);
    }
    g_e8_primer_crystallize_all = 1.0;
    let s_rung1 = geomind_byte_latent_train_deep_e8_corpus(rung1_text, L, 4.0, eff_lr, 1.0);
    g_e8_primer_crystallize_all = 0.0;
    let gen_r1_a = geomind_byte_latent_generate_deep_e8("The ball is", L, 52.0);
    let gen_r1_b = geomind_byte_latent_generate_deep_e8("Water is", L, 52.0);
    printf("[Rung 1 | Nursery Primer] Action S = %.6f | Anchors = %.0f / 65536 | TapestryHubs = %.0f / 1048576\n",
        s_rung1, g_e8_anchor_count, g_markov_hub_occupied_slots);
    printf("  -> Gen 1: %s\n", gen_r1_a);
    printf("  -> Gen 2: %s\n", gen_r1_b);
    cartan_flush(0.0);

    // ------------------------------------------------------------------------
    // RUNG 2: Grounded Taxonomic & Causal Concept Triples (Selective Focus)
    // ------------------------------------------------------------------------
    let rung2_path = g_curriculum_rung2_path;
    var rung2_text = "When you drop a ball, gravity pulls the ball down to the ground. Wood floats on water because wood is lighter than water.";
    if (cartan_file_exists(rung2_path) == 1.0) {
        rung2_text = cartan_read_file(rung2_path);
    }
    g_e8_focus_hits = 0.0;
    g_e8_noise_skips = 0.0;
    let anchors_before_r2 = g_e8_anchor_count;
    let s_rung2 = geomind_byte_latent_train_deep_e8_corpus(rung2_text, L, 4.0, eff_lr, 1.0);
    let gen_r2 = geomind_byte_latent_generate_deep_e8("When you drop a ball", L, 58.0);
    printf("[Rung 2 | Concept Triples] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
        s_rung2, anchors_before_r2, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips, g_markov_hub_occupied_slots);
    printf("  -> Gen 3: %s\n", gen_r2);
    cartan_flush(0.0);

    // ------------------------------------------------------------------------
    // RUNG 3: TinyStories Progressive Multi-Pass Comprehension (Pass 1 vs Pass 2)
    // ------------------------------------------------------------------------
    let rung3_path = g_curriculum_rung3_path;
    if (cartan_file_exists(rung3_path) == 1.0) {
        let stories_slice = cartan_read_file(rung3_path);

        // Pass 1 over full 12KB TinyStories chunk:
        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let anchors_p0 = g_e8_anchor_count;
        let s_r3_p1 = geomind_byte_latent_train_deep_e8_corpus(stories_slice, L, 2.0, eff_lr * 0.85, 1.0);
        let p1_focus = g_e8_focus_hits;
        let p1_skip = g_e8_noise_skips;
        let anchors_p1 = g_e8_anchor_count;

        // Pass 2 over the SAME 12KB TinyStories chunk (with newly crystallized Pass 1 anchors!):
        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let s_r3_p2 = geomind_byte_latent_train_deep_e8_corpus(stories_slice, L, 2.0, eff_lr * 0.85, 1.0);
        let p2_focus = g_e8_focus_hits;
        let p2_skip = g_e8_noise_skips;
        let anchors_p2 = g_e8_anchor_count;

        let gen_r3 = geomind_byte_latent_generate_deep_e8("Once upon a time", L, 64.0);
        printf("[Rung 3 | TinyStories 12KB Pass 1] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f\n",
            s_r3_p1, anchors_p0, anchors_p1, p1_focus, p1_skip);
        printf("[Rung 3 | TinyStories 12KB Pass 2] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
            s_r3_p2, anchors_p1, anchors_p2, p2_focus, p2_skip, g_markov_hub_occupied_slots);
        printf("  -> Gen 4: %s\n", gen_r3);
        cartan_flush(0.0);
    }

    // ------------------------------------------------------------------------
    // RUNG 4: Full 12KB Storytelling Chunks (Modern Narratives + Alice + Anthem + Sherlock Holmes)
    // ------------------------------------------------------------------------
    let chunk_modern = g_curriculum_chunk_modern_path;
    let chunk_alice = g_curriculum_chunk_alice_path;
    let chunk_anthem = g_curriculum_chunk_anthem_path;
    let chunk_sherlock = g_curriculum_chunk_sherlock_path;
    if (cartan_file_exists(chunk_modern) == 1.0 && cartan_file_exists(chunk_alice) == 1.0 && cartan_file_exists(chunk_anthem) == 1.0) {
        let txt_modern = cartan_read_file(chunk_modern);
        let txt_alice = cartan_read_file(chunk_alice);
        let txt_anthem = cartan_read_file(chunk_anthem);

        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let a_pre_mod = g_e8_anchor_count;
        let s_mod = geomind_byte_latent_train_deep_e8_corpus(txt_modern, L, 2.0, eff_lr * 0.80, 1.0);
        printf("[Rung 4a | Chunk 005 Modern Narratives (12KB)] Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
            s_mod, a_pre_mod, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips, g_markov_hub_occupied_slots);

        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let a_pre_ali = g_e8_anchor_count;
        let s_ali = geomind_byte_latent_train_deep_e8_corpus(txt_alice, L, 2.0, eff_lr * 0.80, 1.0);
        printf("[Rung 4b | Chunk 007 Alice Wonderland (12KB)]  Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
            s_ali, a_pre_ali, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips, g_markov_hub_occupied_slots);

        g_e8_focus_hits = 0.0;
        g_e8_noise_skips = 0.0;
        let a_pre_ant = g_e8_anchor_count;
        let s_ant = geomind_byte_latent_train_deep_e8_corpus(txt_anthem, L, 2.0, eff_lr * 0.80, 1.0);
        printf("[Rung 4c | Chunk 019 Anthem (12KB)]            Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
            s_ant, a_pre_ant, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips, g_markov_hub_occupied_slots);

        if (cartan_file_exists(chunk_sherlock) == 1.0) {
            let txt_sher = cartan_read_file(chunk_sherlock);
            g_e8_focus_hits = 0.0;
            g_e8_noise_skips = 0.0;
            let a_pre_sh = g_e8_anchor_count;
            let s_sh = geomind_byte_latent_train_deep_e8_corpus(txt_sher, L, 2.0, eff_lr * 0.80, 1.0);
            printf("[Rung 4d | Chunk 028 Sherlock Holmes (12KB)]   Action S = %.6f | Anchors: %.0f -> %.0f | FocusHits = %.0f | NoiseSkipped = %.0f | Hubs = %.0f\n",
                s_sh, a_pre_sh, g_e8_anchor_count, g_e8_focus_hits, g_e8_noise_skips, g_markov_hub_occupied_slots);
        }

        printf("  -> Gen 5 (Sci-Fi):   %s\n", geomind_byte_latent_generate_deep_e8("Commander Vane stood on", L, 60.0));
        printf("  -> Gen 6 (Alice):    %s\n", geomind_byte_latent_generate_deep_e8("Alice was beginning to", L, 60.0));
        printf("  -> Gen 7 (Anthem):   %s\n", geomind_byte_latent_generate_deep_e8("It is a sin to write", L, 60.0));
        printf("  -> Gen 8 (Sherlock): %s\n", geomind_byte_latent_generate_deep_e8("To Sherlock Holmes she", L, 60.0));
        cartan_flush(0.0);
    }

    geomind_run_epistemic_eval_suite(L);

    // Save consolidated checkpoints once at the end of the curriculum
    g_byte_e8_defer_disk_save = 0.0;
    geomind_markov_save_prior("Projects/geomind/trainingdata/checkpoints/geomind_markov_prior.bin");
    geomind_byte_latent_save_weights("Projects/geomind/trainingdata/checkpoints/geomind_byte_latent_e8.bin");
    geomind_e8_stack_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin");
    geomind_e8_rel_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_rel_tensors.bin");
    if (g_e8_anchor_count > 0.0) {
        geomind_e8_anchors_save("Projects/geomind/trainingdata/checkpoints/geomind_e8_anchors.bin");
    }
    var eff_ckpt_dir = "Projects/geomind/trainingdata/checkpoints";
    if (cartan_string_length(g_curriculum_checkpoint_dir) > 0.0) { eff_ckpt_dir = g_curriculum_checkpoint_dir; }
    if (g_e8_sent_basin_count > 0.0) {
        geomind_e8_sent_basins_save(cartan_string_concat(eff_ckpt_dir, "/geomind_e8_sentence_basins.bin"));
    }

    // Stage 5.6: Export & Self-Verify Spec-Compliant GGUF v3 Open-Weights File
    let gguf_path = g_curriculum_gguf_path;
    printf("--------------------------------------------------------------------------------\n");
    printf("  GGUF v3 OPEN-WEIGHTS EXPORT & CARTAN MOVING-FRAME PULLBACK (248x248)\n");
    printf("--------------------------------------------------------------------------------\n");
    geomind_export_gguf_v3(gguf_path);
    geomind_verify_gguf_v3(gguf_path);

    geomind_visualizer_export_html("manifold_relaxation.html", "4-Rung Concentric Storytelling Curriculum");
    printf("================================================================================\n");
    cartan_flush(0.0);
    return g_e8_anchor_count;
}

// One-time offline indexing and serialization of S^{247} sentence basins and narrative relations
fn geomind_e8_populate_and_save_sentence_basins(checkpoint_dir: string) -> float {
    geomind_e8_rel_init_if_needed();
    geomind_e8_sent_basins_reset();

    var eff_dir = "Projects/geomind/trainingdata/checkpoints";
    if (cartan_string_length(checkpoint_dir) > 0.0) { eff_dir = checkpoint_dir; }

    var p1 = "Projects/geomind/trainingdata/e8_nursery_primer.txt";
    if (cartan_string_length(g_curriculum_rung1_path) > 0.0) { p1 = g_curriculum_rung1_path; }
    if (cartan_file_exists(p1) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(p1), 0.0);
    }
    var p2 = "Projects/geomind/trainingdata/e8_concept_triples.txt";
    if (cartan_string_length(g_curriculum_rung2_path) > 0.0) { p2 = g_curriculum_rung2_path; }
    if (cartan_file_exists(p2) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(p2), 0.0);
    }
    var c_mod = "Projects/geomind/trainingdata/storytelling_chunks/chunk_005_t1_GeoMind_Modern_Narratives.txt";
    if (cartan_string_length(g_curriculum_chunk_modern_path) > 0.0) { c_mod = g_curriculum_chunk_modern_path; }
    if (cartan_file_exists(c_mod) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(c_mod), 1.0);
    }
    var c_ali = "Projects/geomind/trainingdata/storytelling_chunks/chunk_007_t2_Alice_In_Wonderland.txt";
    if (cartan_string_length(g_curriculum_chunk_alice_path) > 0.0) { c_ali = g_curriculum_chunk_alice_path; }
    if (cartan_file_exists(c_ali) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(c_ali), 1.0);
    }
    var c_ant = "Projects/geomind/trainingdata/storytelling_chunks/chunk_019_t2_Anthem.txt";
    if (cartan_string_length(g_curriculum_chunk_anthem_path) > 0.0) { c_ant = g_curriculum_chunk_anthem_path; }
    if (cartan_file_exists(c_ant) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(c_ant), 1.0);
    }
    var c_sh = "Projects/geomind/trainingdata/storytelling_chunks/chunk_028_t3_Sherlock_Holmes.txt";
    if (cartan_string_length(g_curriculum_chunk_sherlock_path) > 0.0) { c_sh = g_curriculum_chunk_sherlock_path; }
    if (cartan_file_exists(c_sh) == 1.0) {
        geomind_e8_index_corpus_sentence_basins(cartan_read_file(c_sh), 1.0);
    }

    let bin_path = cartan_string_concat(eff_dir, "/geomind_e8_sentence_basins.bin");
    geomind_e8_sent_basins_save(bin_path);
    let rel_path = cartan_string_concat(eff_dir, "/geomind_e8_rel_tensors.bin");
    geomind_e8_rel_save(rel_path);
    printf("[Sentence Basins] Indexed and saved %.0f basins to %s\n", g_e8_sent_basin_count, bin_path);
    return g_e8_sent_basin_count;
}

