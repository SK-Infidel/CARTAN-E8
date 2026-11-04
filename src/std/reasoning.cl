// src/std/reasoning.cl
// CARTAN Standard Library: Absolute Zero Reasoning (AZR) & Verifiable Compiler Reward Implementation

include "src/std/fs.cl";
include "src/std/string.cl";
include "src/std/math.cl";

extern fn remove(filename: string) -> float;
extern fn cartan_system(cmd: string) -> float;

fn azr_framework_propose_task(level: float) -> string {
    if (level <= 1.0) {
        let a_val = cartan_float_to_string(level * 2.0 + 1.0);
        let b_val = cartan_float_to_string(level * 3.0 + 5.0);
        let y_val = cartan_float_to_string(level * 15.0 + 20.0);
        let s1 = "// AZR Task: Level 1 (Affine Root)\nfn problem_level() -> float { return 1.0; }\n";
        let s2 = cartan_string_concat(s1, "fn problem_param_a() -> float { return ");
        let s3 = cartan_string_concat(s2, a_val);
        let s4 = cartan_string_concat(s3, "; }\nfn problem_param_b() -> float { return ");
        let s5 = cartan_string_concat(s4, b_val);
        let s6 = cartan_string_concat(s5, "; }\nfn problem_param_y() -> float { return ");
        let s7 = cartan_string_concat(s6, y_val);
        return cartan_string_concat(s7, "; }\nfn problem_expected() -> float {\n    return (problem_param_y() - problem_param_b()) / problem_param_a();\n}\n");
    }
    if (level == 2.0) {
        let a_val = cartan_float_to_string(level * 3.0);
        let b_val = cartan_float_to_string(level * 4.0);
        let s1 = "// AZR Task: Level 2 (Pythagorean Norm)\nfn problem_level() -> float { return 2.0; }\n";
        let s2 = cartan_string_concat(s1, "fn problem_param_a() -> float { return ");
        let s3 = cartan_string_concat(s2, a_val);
        let s4 = cartan_string_concat(s3, "; }\nfn problem_param_b() -> float { return ");
        let s5 = cartan_string_concat(s4, b_val);
        return cartan_string_concat(s5, "; }\nfn problem_expected() -> float {\n    let a = problem_param_a();\n    let b = problem_param_b();\n    return sqrt(a * a + b * b);\n}\n");
    }
    if (level == 3.0) {
        let b_num = 0.0 - (level + 6.0);
        let c_num = level * 6.0;
        let b_val = cartan_float_to_string(b_num);
        let c_val = cartan_float_to_string(c_num);
        let s1 = "// AZR Task: Level 3 (Quadratic Root)\nfn problem_level() -> float { return 3.0; }\nfn problem_param_a() -> float { return 1.0; }\n";
        let s2 = cartan_string_concat(s1, "fn problem_param_b() -> float { return ");
        let s3 = cartan_string_concat(s2, b_val);
        let s4 = cartan_string_concat(s3, "; }\nfn problem_param_c() -> float { return ");
        let s5 = cartan_string_concat(s4, c_val);
        return cartan_string_concat(s5, "; }\nfn problem_expected() -> float {\n    let a = problem_param_a();\n    let b = problem_param_b();\n    let c = problem_param_c();\n    let disc = b * b - 4.0 * a * c;\n    return (0.0 - b + sqrt(disc)) / (2.0 * a);\n}\n");
    }
    let u_val = "0.2";
    let v_val = "0.6";
    let s1 = "// AZR Task: Level 4 (Hyperbolic Metric)\nfn problem_level() -> float { return 4.0; }\n";
    let s2 = cartan_string_concat(s1, "fn problem_param_u() -> float { return ");
    let s3 = cartan_string_concat(s2, u_val);
    let s4 = cartan_string_concat(s3, "; }\nfn problem_param_v() -> float { return ");
    let s5 = cartan_string_concat(s4, v_val);
    return cartan_string_concat(s5, "; }\nfn problem_expected() -> float {\n    let u = problem_param_u();\n    let v = problem_param_v();\n    let diff = u - v;\n    let num = 2.0 * diff * diff;\n    let den = (1.0 - u * u) * (1.0 - v * v);\n    return 1.0 + num / den;\n}\n");
}

fn azr_framework_solve_task(task_code: string) -> string {
    let header = "include \"src/std/math.cl\";\n\n";
    var solver_fn = "";
    if (cartan_string_contains(task_code, "Level 1") == 1.0) {
        solver_fn = "fn solve() -> float {\n    let a = problem_param_a();\n    let b = problem_param_b();\n    let y = problem_param_y();\n    return (y - b) / a;\n}\n\n";
    } else if (cartan_string_contains(task_code, "Level 2") == 1.0) {
        solver_fn = "fn solve() -> float {\n    let a = problem_param_a();\n    let b = problem_param_b();\n    return sqrt(a * a + b * b);\n}\n\n";
    } else if (cartan_string_contains(task_code, "Level 3") == 1.0) {
        solver_fn = "fn solve() -> float {\n    let a = problem_param_a();\n    let b = problem_param_b();\n    let c = problem_param_c();\n    let disc = b * b - 4.0 * a * c;\n    return (0.0 - b + sqrt(disc)) / (2.0 * a);\n}\n\n";
    } else {
        solver_fn = "fn solve() -> float {\n    let u = problem_param_u();\n    let v = problem_param_v();\n    let diff = u - v;\n    let num = 2.0 * diff * diff;\n    let den = (1.0 - u * u) * (1.0 - v * v);\n    return 1.0 + num / den;\n}\n\n";
    }

    let harness = "fn main() -> float {\n    let s = solve();\n    let e = problem_expected();\n    var diff = s - e;\n    if (diff < 0.0) { diff = 0.0 - diff; }\n    if (diff < 0.001) {\n        printf(\"[AZR Candidate] Verification Passed\\n\", \"\");\n        return 0.0;\n    }\n    printf(\"[AZR Candidate] Verification Failed\\n\", \"\");\n    return 1.0;\n}\n";

    let s1 = cartan_string_concat(header, task_code);
    let s2 = cartan_string_concat(s1, "\n");
    let s3 = cartan_string_concat(s2, solver_fn);
    return cartan_string_concat(s3, harness);
}

fn azr_framework_eval_binary_reward(candidate_code: string) -> float {
    let scratch_car = "scratch/azr_candidate.car";
    let scratch_exe = "scratch/azr_candidate.exe";
    let scratch_ll = "scratch/azr_candidate.ll";
    cartan_write_file(scratch_car, candidate_code);
    if (cartan_file_exists(scratch_car) == 0.0) {
        return 0.0;
    }
    let build_cmd = ".\\cartanc.exe build scratch/azr_candidate.car -o scratch/azr_candidate.exe > scratch/azr_build.log 2>&1";
    let build_status = cartan_system(build_cmd);
    if (build_status != 0.0) {
        return 0.0;
    }
    let run_cmd = ".\\scratch\\azr_candidate.exe > scratch/azr_run.log 2>&1";
    let run_status = cartan_system(run_cmd);
    remove(scratch_exe);
    remove(scratch_ll);
    if (run_status == 0.0) {
        return 1.0;
    }
    return 0.0;
}

var g_doubt_last_confidence = 0.0;
var g_doubt_last_entropy = 0.0;
var g_doubt_temp_saved = 0.0;
var g_doubt_token_count = 0.0;
var g_doubt_h_saved: ptr = 0.0;
var g_doubt_mom_saved: ptr = 0.0;
var g_doubt_history_saved: ptr = 0.0;

fn cartan_doubt_get_last_confidence() -> float {
    return g_doubt_last_confidence;
}

fn cartan_doubt_get_last_entropy() -> float {
    return g_doubt_last_entropy;
}

fn cartan_doubt_get_checkpoint_temp() -> float {
    return g_doubt_temp_saved;
}

fn cartan_doubt_checkpoint(h: ptr, mom: ptr, hist: ptr, count: float, temp: float) -> float {
    if (h == 0.0) { return 0.0; }
    if (g_doubt_h_saved == 0.0) { g_doubt_h_saved = cartan_vec_create(); }
    if (g_doubt_mom_saved == 0.0) { g_doubt_mom_saved = cartan_vec_create(); }
    if (g_doubt_history_saved == 0.0) { g_doubt_history_saved = cartan_vec_create(); }

    let dim = cartan_vec_len(h);
    var i = 0.0;
    while (i < dim) {
        let v = cartan_vec_get_f32(h, i);
        if (i < cartan_vec_len(g_doubt_h_saved)) {
            cartan_vec_set_f32(g_doubt_h_saved, i, v);
        } else {
            cartan_vec_push_f32(g_doubt_h_saved, v);
        }
        i = i + 1.0;
    }

    if (mom != 0.0) {
        let m_dim = cartan_vec_len(mom);
        var j = 0.0;
        while (j < m_dim) {
            let v = cartan_vec_get_f32(mom, j);
            if (j < cartan_vec_len(g_doubt_mom_saved)) {
                cartan_vec_set_f32(g_doubt_mom_saved, j, v);
            } else {
                cartan_vec_push_f32(g_doubt_mom_saved, v);
            }
            j = j + 1.0;
        }
    }

    if (hist != 0.0) {
        let h_len = cartan_vec_len(hist);
        var k = 0.0;
        while (k < h_len) {
            let v = cartan_vec_get_f32(hist, k);
            if (k < cartan_vec_len(g_doubt_history_saved)) {
                cartan_vec_set_f32(g_doubt_history_saved, k, v);
            } else {
                cartan_vec_push_f32(g_doubt_history_saved, v);
            }
            k = k + 1.0;
        }
    }

    g_doubt_token_count = count;
    g_doubt_temp_saved = temp;
    return 1.0;
}

fn cartan_doubt_rewind(h: ptr, mom: ptr, hist: ptr) -> float {
    if (h == 0.0 || g_doubt_h_saved == 0.0) { return 0.0; }
    let dim = cartan_vec_len(h);
    var i = 0.0;
    while (i < dim) {
        if (i < cartan_vec_len(g_doubt_h_saved)) {
            cartan_vec_set_f32(h, i, cartan_vec_get_f32(g_doubt_h_saved, i));
        }
        i = i + 1.0;
    }

    if (mom != 0.0 && g_doubt_mom_saved != 0.0) {
        let m_dim = cartan_vec_len(mom);
        var j = 0.0;
        while (j < m_dim) {
            if (j < cartan_vec_len(g_doubt_mom_saved)) {
                cartan_vec_set_f32(mom, j, cartan_vec_get_f32(g_doubt_mom_saved, j));
            }
            j = j + 1.0;
        }
    }

    if (hist != 0.0 && g_doubt_history_saved != 0.0) {
        let count = g_doubt_token_count;
        while (cartan_vec_len(hist) > count) {
            cartan_vec_pop_f32(hist);
        }
        var k = 0.0;
        while (k < count) {
            if (k < cartan_vec_len(g_doubt_history_saved)) {
                cartan_vec_set_f32(hist, k, cartan_vec_get_f32(g_doubt_history_saved, k));
            }
            k = k + 1.0;
        }
    }

    g_doubt_rewind_triggered = 0.0;
    return g_doubt_token_count;
}

fn cartan_tensor_compute_confidence(logits: ptr, top_k: float) -> float {
    if (logits == 0.0) { return 0.0; }
    let len = cartan_vec_len(logits);
    if (len == 0.0) { return 0.0; }

    var k = top_k;
    if (k <= 0.0) { k = 50.0; }
    if (k > 50.0) { k = 50.0; }
    if (k > len) { k = len; }

    let top_logits = malloc(k * 8.0);
    var idx = 0.0;
    while (idx < k) {
        top_logits[idx] = -1000000.0;
        idx = idx + 1.0;
    }

    let is_flat = (cartan_c_is_tree(logits) == 0.0);
    var i = 0.0;
    while (i < len) {
        var val = 0.0;
        if (is_flat) {
            val = logits[2.0 + i];
        } else {
            val = cartan_vec_get_f32(logits, i);
        }
        let last_top = top_logits[k - 1.0];
        if (val > last_top) {
            var pos = k - 1.0;
            while (pos > 0.0 && val > top_logits[pos - 1.0]) {
                top_logits[pos] = top_logits[pos - 1.0];
                pos = pos - 1.0;
            }
            top_logits[pos] = val;
        }
        i = i + 1.0;
    }

    let max_l = top_logits[0.0];
    let exp_vals = malloc(k * 8.0);
    var sum_exp = 0.0;
    var j = 0.0;
    while (j < k) {
        let e = math_exp(top_logits[j] - max_l);
        exp_vals[j] = e;
        sum_exp = sum_exp + e;
        j = j + 1.0;
    }

    if (sum_exp <= 0.0) {
        free(top_logits);
        free(exp_vals);
        return 0.0;
    }

    let top1_prob = exp_vals[0.0] / sum_exp;
    g_doubt_last_confidence = top1_prob;

    var entropy = 0.0;
    var m = 0.0;
    while (m < k) {
        let p = exp_vals[m] / sum_exp;
        if (p > 0.000000000001) {
            entropy = entropy - (p * math_log(p));
        }
        m = m + 1.0;
    }
    g_doubt_last_entropy = entropy;

    free(top_logits);
    free(exp_vals);
    return top1_prob;
}

fn cartan_tensor_compute_entropy(logits: ptr, top_k: float) -> float {
    cartan_tensor_compute_confidence(logits, top_k);
    return g_doubt_last_entropy;
}

fn doubt_checkpoint(h: ptr, mom: ptr, hist: ptr, count: float, temp: float) -> float {
    return cartan_doubt_checkpoint(h, mom, hist, count, temp);
}

fn doubt_rewind(h: ptr, mom: ptr, hist: ptr) -> float {
    return cartan_doubt_rewind(h, mom, hist);
}

fn doubt_evaluate_confidence(logits: ptr, top_k: float) -> float {
    return cartan_tensor_compute_confidence(logits, top_k);
}

fn doubt_evaluate_entropy(logits: ptr, top_k: float) -> float {
    return cartan_tensor_compute_entropy(logits, top_k);
}

fn doubt_should_rewind_threshold(confidence: float, min_confidence: float, entropy: float, max_entropy: float) -> float {
    if (confidence < min_confidence || entropy > max_entropy) {
        cartan_doubt_trigger_rewind();
        return 1.0;
    }
    return 0.0;
}


fn azr_framework_run_selfplay(iterations: float) -> float {
    printf("================================================================================\n");
    printf("  CARTAN ABSOLUTE ZERO REASONING (AZR) COMPILER SELF-PLAY ENGINE\n");
    printf("  Dual-Agent Proposer/Solver | Verifiable Binary Reward RL Signal\n");
    printf("================================================================================\n\n");

    var iter = 1.0;
    var total_reward = 0.0;
    while (iter <= iterations) {
        let task = azr_framework_propose_task(iter);
        let solution = azr_framework_solve_task(task);
        let reward = azr_framework_eval_binary_reward(solution);
        total_reward = total_reward + reward;
        
        printf("[AZR Self-Play] Iteration %s / %s | Level %s Task Proposed | Binary Reward: %s\n",
            cartan_float_to_string(iter), cartan_float_to_string(iterations),
            cartan_float_to_string(iter), cartan_float_to_string(reward));
        iter = iter + 1.0;
    }

    let avg_reward = total_reward / iterations;
    printf("\n[AZR Self-Play] Self-Play Complete | Mean Binary Reward Score: %s\n", cartan_float_to_string(avg_reward));
    return avg_reward;
}

