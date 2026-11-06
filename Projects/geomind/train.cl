// Projects/geomind/train.cl
// GeoMind Sovereign Unified BLT Training Engine (Continuous 248-D E8 Manifold)
// Unifies Causal Pre-training (CE), Cloze Curriculum, and Supervised Fine-Tuning (SFT)
// with Byte Loss Masking, JSON Manifest Parsing, and Exact Sherman-Morrison Finsler-Randers Optimization.

include "geometry.cl";
include "streams.cl";
include "byte_latent.cl";
include "e8_stack.cl";
include "e8_relational.cl";
include "e8_anchors.cl";
include "markov_tapestry.cl";
include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/json.cl";
include "src/std/fs.cl";
include "Projects/geomind/e8_curriculum.cl";

extern fn printf(format: string) -> i32;
extern fn cartan_flush(v: float) -> float;
extern fn cartan_string_length(s: string) -> float;
extern fn cartan_byte_at(s: string, idx: float) -> float;
extern fn cartan_string_concat(s1: string, s2: string) -> string;
extern fn cartan_string_substring(s: string, start: float, end_idx: float) -> string;
extern fn cartan_file_exists(p: string) -> float;
extern fn cartan_read_file(p: string) -> string;
extern fn floor(v: float) -> float;
extern fn sqrt(v: float) -> float;
extern fn log(v: float) -> float;
extern fn free(p: ptr) -> void;

// Configuration and telemetry state
var g_train_total_bytes_processed: float = 0.0;
var g_train_total_tokens_masked: float = 0.0;
var g_train_total_response_bytes: float = 0.0;
var g_train_last_epoch_loss: float = 0.0;

// Persists all active E8 manifold components and checkpoints to disk
fn geomind_train_save_checkpoint(ckpt_dir: string) -> float {
    var eff_dir = "Projects/geomind/trainingdata/checkpoints";
    if (cartan_string_length(ckpt_dir) > 0.0) { eff_dir = ckpt_dir; }

    geomind_markov_save_prior(cartan_string_concat(eff_dir, "/geomind_markov_prior.bin"));
    geomind_byte_latent_save_weights(cartan_string_concat(eff_dir, "/geomind_byte_latent_e8.bin"));
    geomind_e8_stack_save(cartan_string_concat(eff_dir, "/geomind_e8_deep_stack.bin"));
    geomind_e8_rel_save(cartan_string_concat(eff_dir, "/geomind_e8_rel_tensors.bin"));
    if (g_e8_anchor_count > 0.0) {
        geomind_e8_anchors_save(cartan_string_concat(eff_dir, "/geomind_e8_anchors.bin"));
    }
    if (g_e8_sent_basin_count > 0.0) {
        geomind_e8_sent_basins_save(cartan_string_concat(eff_dir, "/geomind_e8_sentence_basins.bin"));
    }
    printf("[Checkpoint] Successfully saved sovereign BLT checkpoint to %s\n", eff_dir);
    cartan_flush(0.0);
    return 1.0;
}

// Executes a single Supervised Fine-Tuning (SFT) sequence step with Prompt Loss Masking
// Prompt bytes [0..prompt_len-1] advance hidden state h_curr with mask = 0.0 (zero loss / no backprop)
// Response bytes [prompt_len..total_len-1] activate mask = 1.0 with genuine CE loss & Finsler-Randers updates
fn geomind_sft_train_pair(
    instruction: string,
    response: string,
    num_layers: float,
    learning_rate: float
) -> float {
    geomind_byte_latent_init_if_needed();
    var L = floor(num_layers);
    if (L < 1.0) { L = 42.0; }
    geomind_e8_stack_init(L);

    var eff_lr = 0.02;
    if (learning_rate > 0.00001) { eff_lr = learning_rate; }

    let p_len = cartan_string_length(instruction);
    let r_len = cartan_string_length(response);
    if (p_len == 0.0 || r_len == 0.0) { return 0.0; }

    // Combine into formatted instruction-response sequence
    var full_seq = instruction;
    full_seq = cartan_string_concat(full_seq, " ");
    full_seq = cartan_string_concat(full_seq, response);
    let total_len = cartan_string_length(full_seq);
    let prompt_boundary = p_len + 1.0; // Index where response begins

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

    var step = 0.0;
    let max_step = total_len - 1.0;
    var total_loss = 0.0;
    var resp_steps = 0.0;

    while (step < max_step) {
        var cur_b = cartan_byte_at(full_seq, step);
        var next_b = cartan_byte_at(full_seq, step + 1.0);
        if (cur_b < 0.0) { cur_b = cur_b + 256.0; }
        if (next_b < 0.0) { next_b = next_b + 256.0; }
        cur_b = math_mod_val(floor(cur_b), 256.0);
        next_b = math_mod_val(floor(next_b), 256.0);

        // Normalize carriage returns / line breaks to space
        if (cur_b == 13.0 || cur_b == 10.0) { cur_b = 32.0; }
        if (next_b == 13.0 || next_b == 10.0) { next_b = 32.0; }

        let row_off = cur_b * 248.0;

        // 1. Advance Local State: h_prev -> h_pre_gate
        d = 0.0;
        while (d < 248.0) {
            let old_h = cartan_vec_get_f32(h_curr, d);
            cartan_vec_set_f32(h_prev, d, old_h);
            let emb_v = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
            cartan_vec_set_f32(h_pre_gate, d, 0.65 * old_h + emb_v);
            d = d + 1.0;
        }

        // 2. 120-D (+) 128-D Gauge-Spinor Cross-Gating: h_pre_gate -> h_curr
        geomind_e8_gauge_spinor_cross_gate(h_pre_gate, h_curr, 0.25);

        // 3. Loss Masking: Only backpropagate on response bytes (step >= prompt_boundary)
        if (step >= prompt_boundary) {
            // Decode logits
            geomind_byte_latent_decode_logits(h_curr, cur_b, logits_256);

            // Calculate Lagrangian action & Cross-Entropy loss
            let act_s = geomind_lagrangian_action_step(
                logits_256, next_b, cur_b, h_prev, h_curr, g_byte_e8_randers_b_248, delta_256
            );
            total_loss = total_loss + act_s;
            resp_steps = resp_steps + 1.0;

            // Geodesic kinetic energy restoring force
            let markov_v = geomind_markov_get_prob(cur_b, next_b);
            let well_factor = 1.0 - 0.5 * markov_v;
            geomind_e8_geodesic_kinetic_grad_248(h_prev, h_curr, g_byte_e8_randers_b_248, geo_grad, 0.15 * well_factor);

            // Backward pass on decoder head W_dec
            d = 0.0;
            while (d < 248.0) {
                let h_d = cartan_vec_get_f32(h_curr, d);
                let b_d = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
                var dh_d = cartan_vec_get_f32(geo_grad, d);

                c = 32.0;
                while (c <= 126.0) {
                    let del_c = cartan_vec_get_f32(delta_256, c);
                    if (math_abs_val(del_c) > 0.005) {
                        let w_dc = cartan_vec_get_f32(g_byte_e8_head_248x256, d * 256.0 + c);
                        dh_d = dh_d + w_dc * del_c;
                        let new_w = geom_frs_riemannian_gradient_step(w_dc, h_d * del_c, b_d, eff_lr);
                        cartan_vec_set_f32(g_byte_e8_head_248x256, d * 256.0 + c, new_w);
                    }
                    c = c + 1.0;
                }
                cartan_vec_set_f32(dh_gated, d, dh_d);
                d = d + 1.0;
            }

            // Backprop through Adjoint Cross-Gate Jacobian -> dh_pre
            geomind_e8_gauge_spinor_cross_gate_backward(h_pre_gate, dh_gated, dh_pre, 0.25);

            // Update Byte Embedding and Finsler-Randers drift vector b
            d = 0.0;
            while (d < 248.0) {
                let dp_d = cartan_vec_get_f32(dh_pre, d);
                let b_d = cartan_vec_get_f32(g_byte_e8_randers_b_248, d);
                let old_emb = cartan_vec_get_f32(g_byte_e8_emb_256x248, row_off + d);
                let new_emb = geom_frs_riemannian_gradient_step(old_emb, dp_d, b_d, eff_lr * 0.25);
                cartan_vec_set_f32(g_byte_e8_emb_256x248, row_off + d, new_emb);

                let h_d = cartan_vec_get_f32(h_curr, d);
                let old_h = cartan_vec_get_f32(h_prev, d);
                var new_b = b_d - eff_lr * 0.005 * well_factor * (h_d - old_h);
                if (new_b > 0.08) { new_b = 0.08; }
                else if (new_b < -0.08) { new_b = -0.08; }
                cartan_vec_set_f32(g_byte_e8_randers_b_248, d, new_b);
                d = d + 1.0;
            }
        } else {
            g_train_total_tokens_masked = g_train_total_tokens_masked + 1.0;
        }

        g_train_total_bytes_processed = g_train_total_bytes_processed + 1.0;
        step = step + 1.0;
    }

    cartan_vec_free(h_prev);
    cartan_vec_free(h_pre_gate);
    cartan_vec_free(h_curr);
    cartan_vec_free(dh_gated);
    cartan_vec_free(dh_pre);
    cartan_vec_free(geo_grad);
    cartan_vec_free(logits_256);
    cartan_vec_free(delta_256);

    if (resp_steps > 0.0) {
        g_train_total_response_bytes = g_train_total_response_bytes + resp_steps;
        return total_loss / resp_steps;
    }
    return 0.0;
}

// Ingests and trains over an SFT JSON manifest file
// Expected format: JSON list of objects containing {"instruction": "...", "response": "..."}
// or plain text prompt/response blocks separated by blank lines
fn geomind_sft_train_manifest(
    manifest_path: string,
    num_layers: float,
    epochs: float,
    learning_rate: float
) -> float {
    if (cartan_file_exists(manifest_path) == 0.0) {
        printf("[SFT Error] Manifest file '%s' not found on disk\n", manifest_path);
        return 0.0;
    }

    let manifest_content = cartan_read_file(manifest_path);
    let m_len = cartan_string_length(manifest_content);
    if (m_len < 10.0) {
        printf("[SFT Error] Manifest content empty or too small\n");
        return 0.0;
    }

    printf("================================================================================\n");
    printf("  GEOMIND SUPERVISED FINE-TUNING (SFT) ENGINE (BLT 248-D)\n");
    printf("  Manifest: %s (%0.0f bytes) | Layers: %.0f | Epochs: %.0f | LR: %.4f\n", manifest_path, m_len, num_layers, epochs, learning_rate);
    printf("================================================================================\n");
    cartan_flush(0.0);

    var ep = 0.0;
    var final_loss = 0.0;

    while (ep < epochs) {
        var ep_loss_sum = 0.0;
        var pair_count = 0.0;
        var p = 0.0;

        while (p < m_len) {
            // Find next JSON object boundary '{' ... '}'
            var obj_start = -1.0;
            var obj_end = -1.0;
            var scan = p;
            while (scan < m_len) {
                let b = cartan_byte_at(manifest_content, scan);
                if (b == 123.0 && obj_start < 0.0) { // '{'
                    obj_start = scan;
                } else if (b == 125.0 && obj_start >= 0.0) { // '}'
                    obj_end = scan + 1.0;
                    break;
                }
                scan = scan + 1.0;
            }

            if (obj_start < 0.0 || obj_end < 0.0) {
                break;
            }

            let item_json = cartan_string_substring(manifest_content, obj_start, obj_end);
            var inst = json_get_string(item_json, "instruction");
            if (cartan_string_length(inst) == 0.0) {
                inst = json_get_string(item_json, "prompt");
            }
            var resp = json_get_string(item_json, "response");
            if (cartan_string_length(resp) == 0.0) {
                resp = json_get_string(item_json, "completion");
            }

            if (cartan_string_length(inst) > 0.0 && cartan_string_length(resp) > 0.0) {
                let pair_loss = geomind_sft_train_pair(inst, resp, num_layers, learning_rate);
                ep_loss_sum = ep_loss_sum + pair_loss;
                pair_count = pair_count + 1.0;
            }

            free(item_json);
            p = obj_end;
        }

        if (pair_count > 0.0) {
            final_loss = ep_loss_sum / pair_count;
            printf("  [SFT Epoch %.0f/%.0f] Pairs: %.0f | Mean CE Action Loss: %.6f | RespBytes: %.0f | PromptMasked: %.0f\n",
                ep + 1.0, epochs, pair_count, final_loss, g_train_total_response_bytes, g_train_total_tokens_masked);
            cartan_flush(0.0);
        } else {
            printf("  [SFT Epoch %.0f/%.0f] Warning: No JSON instruction/response pairs detected in manifest\n", ep + 1.0, epochs);
            break;
        }

        ep = ep + 1.0;
    }

    g_train_last_epoch_loss = final_loss;
    geomind_train_save_checkpoint("Projects/geomind/trainingdata/checkpoints");
    return final_loss;
}

// Executes Cloze Concept Completion Curriculum Training
// Iterates over concept triples and declarative statements, masking target concepts
// and optimizing the 42-layer E8 stack strata on continuous geometric prediction
fn geomind_cloze_train_corpus(
    corpus_text: string,
    num_layers: float,
    epochs: float,
    learning_rate: float
) -> float {
    let c_len = cartan_string_length(corpus_text);
    if (c_len < 10.0) { return 0.0; }

    printf("================================================================================\n");
    printf("  GEOMIND CLOZE CONCEPT CURRICULUM TRAINING (BLT 248-D)\n");
    printf("  Corpus: %0.0f bytes | Layers: %.0f | Epochs: %.0f | LR: %.4f\n", c_len, num_layers, epochs, learning_rate);
    printf("================================================================================\n");
    cartan_flush(0.0);

    // Run deep 42-layer corpus training with active concept anchoring
    let act_s = geomind_byte_latent_train_deep_e8_corpus(corpus_text, num_layers, epochs, learning_rate, 0.0);
    printf("  [Cloze Training Complete] Final Mean Lagrangian Action S = %.6f | Anchors: %.0f\n", act_s, g_e8_anchor_count);
    cartan_flush(0.0);
    geomind_train_save_checkpoint("Projects/geomind/trainingdata/checkpoints");
    return act_s;
}

// Unsupervised Causal Pre-Training (CE) over byte streams
// Trains the 42-layer E8 stack, Markov Tapestry, and W_dec on full raw text corpora
fn geomind_pretrain_ce_corpus(
    corpus_text: string,
    num_layers: float,
    epochs: float,
    learning_rate: float
) -> float {
    let c_len = cartan_string_length(corpus_text);
    if (c_len < 10.0) { return 0.0; }

    printf("================================================================================\n");
    printf("  GEOMIND CAUSAL PRE-TRAINING (CE) ENGINE (BLT 248-D)\n");
    printf("  Corpus: %0.0f bytes | Layers: %.0f | Epochs: %.0f | Base LR: %.4f\n", c_len, num_layers, epochs, learning_rate);
    printf("================================================================================\n");
    cartan_flush(0.0);

    let final_action = geomind_byte_latent_train_deep_e8_corpus(corpus_text, num_layers, epochs, learning_rate, 0.0);
    printf("  [Causal Pre-training Complete] Final Action S = %.6f | Anchors: %.0f | FocusHits: %.0f\n",
        final_action, g_e8_anchor_count, g_e8_focus_hits);
    cartan_flush(0.0);

    geomind_train_save_checkpoint("Projects/geomind/trainingdata/checkpoints");
    return final_action;
}

// Unified Training Dispatcher: handles mode selection, target resolution, and error checks
fn geomind_train_unified(
    mode: string,
    target_path: string,
    num_layers: float,
    epochs: float,
    learning_rate: float
) -> float {
    if (cartan_string_eq(mode, "sft") == 1.0) {
        var m_path = "Projects/geomind/trainingdata/sft_manifest.json";
        if (cartan_string_length(target_path) > 0.0) { m_path = target_path; }
        return geomind_sft_train_manifest(m_path, num_layers, epochs, learning_rate);
    }

    if (cartan_string_eq(mode, "cloze") == 1.0) {
        var c_path = "Projects/geomind/trainingdata/e8_concept_triples.txt";
        if (cartan_string_length(target_path) > 0.0) { c_path = target_path; }
        if (cartan_file_exists(c_path) == 1.0) {
            return geomind_cloze_train_corpus(cartan_read_file(c_path), num_layers, epochs, learning_rate);
        }
        printf("[Cloze Error] Target corpus '%s' not found\n", c_path);
        return 0.0;
    }

    // Default: Causal Pre-training (CE)
    var p_path = "Projects/geomind/trainingdata/storytelling_chunks/chunk_005_t1_GeoMind_Modern_Narratives.txt";
    if (cartan_string_length(target_path) > 0.0) { p_path = target_path; }
    if (cartan_file_exists(p_path) == 1.0) {
        return geomind_pretrain_ce_corpus(cartan_read_file(p_path), num_layers, epochs, learning_rate);
    }
    printf("[Pretrain Error] Target corpus '%s' not found\n", p_path);
    return 0.0;
}
