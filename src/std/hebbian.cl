// src/std/hebbian.cl
// Three-Factor Hebbian Synaptic Plasticity Engine for CARTAN & GeoMind
// Implements local, zero-backpropagation neuromodulated synaptic updates:
// ΔW = η · Pre · Post · M (Three-Factor Hebbian Rule)
// ΔW = η · M · (Pre · Post - α · Post² · W) (Stabilized Oja's Rule)
// e(t) = λ · e(t-1) + Pre · Post; ΔW = η · M · e(t) (Eligibility Trace)

include "math.cl";
include "collections.cl";
include "geom.cl";

// Outer product of pre-synaptic vector (len M) and post-synaptic vector (len N)
// Returns flattened row-major tensor of dimension M x N.
fn hebbian_vector_outer_product(pre: ptr, post: ptr) -> ptr {
    if (pre == 0.0 || post == 0.0) { return 0.0; }
    let m = cartan_vec_len(pre);
    let n = cartan_vec_len(post);
    let total = m * n;
    let out = cartan_tensor_alloc(total);
    var i = 0.0;
    while (i < m) {
        let pre_val = cartan_vec_get_f32(pre, i);
        var j = 0.0;
        while (j < n) {
            let post_val = cartan_vec_get_f32(post, j);
            let idx = i * n + j;
            cartan_vec_set_f32(out, idx, pre_val * post_val);
            j = j + 1.0;
        }
        i = i + 1.0;
    }
    return out;
}

// Canonical Three-Factor Hebbian Update:
// W[i, j] <- W[i, j] + η · M · (pre[i] · post[j]) - decay · W[i, j]
fn hebbian_three_factor_update(w_mat: ptr, rows: float, cols: float, pre: ptr, post: ptr, m: float, lr: float, decay: float) -> ptr {
    if (w_mat == 0.0 || pre == 0.0 || post == 0.0) { return w_mat; }
    let m_rows = cartan_vec_len(pre);
    let n_cols = cartan_vec_len(post);
    var r_limit = rows;
    if (m_rows < r_limit) { r_limit = m_rows; }
    var c_limit = cols;
    if (n_cols < c_limit) { c_limit = n_cols; }

    var i = 0.0;
    while (i < r_limit) {
        let pre_val = cartan_vec_get_f32(pre, i);
        var j = 0.0;
        while (j < c_limit) {
            let post_val = cartan_vec_get_f32(post, j);
            let idx = i * cols + j;
            let current_w = cartan_vec_get_f32(w_mat, idx);
            let delta = lr * m * (pre_val * post_val) - (decay * current_w);
            cartan_vec_set_f32(w_mat, idx, current_w + delta);
            j = j + 1.0;
        }
        i = i + 1.0;
    }
    return w_mat;
}

// Oja's Stabilized Neuromodulated Hebbian Update:
// W[i, j] <- W[i, j] + η · M · (pre[i] · post[j] - α · post[j]² · W[i, j])
fn hebbian_oja_update(w_mat: ptr, rows: float, cols: float, pre: ptr, post: ptr, m: float, lr: float, alpha: float) -> ptr {
    if (w_mat == 0.0 || pre == 0.0 || post == 0.0) { return w_mat; }
    let m_rows = cartan_vec_len(pre);
    let n_cols = cartan_vec_len(post);
    var r_limit = rows;
    if (m_rows < r_limit) { r_limit = m_rows; }
    var c_limit = cols;
    if (n_cols < c_limit) { c_limit = n_cols; }

    var i = 0.0;
    while (i < r_limit) {
        let pre_val = cartan_vec_get_f32(pre, i);
        var j = 0.0;
        while (j < c_limit) {
            let post_val = cartan_vec_get_f32(post, j);
            let idx = i * cols + j;
            let current_w = cartan_vec_get_f32(w_mat, idx);
            let oja_sub = alpha * (post_val * post_val) * current_w;
            let delta = lr * m * (pre_val * post_val - oja_sub);
            cartan_vec_set_f32(w_mat, idx, current_w + delta);
            j = j + 1.0;
        }
        i = i + 1.0;
    }
    return w_mat;
}

// Eligibility Trace Neuromodulated Update:
// e[i, j] <- λ · e[i, j] + pre[i] · post[j]
// W[i, j] <- W[i, j] + η · M · e[i, j]
fn hebbian_trace_update(traces: ptr, w_mat: ptr, rows: float, cols: float, pre: ptr, post: ptr, m: float, lr: float, lambda_decay: float) -> float {
    if (traces == 0.0 || w_mat == 0.0 || pre == 0.0 || post == 0.0) { return 0.0; }
    let m_rows = cartan_vec_len(pre);
    let n_cols = cartan_vec_len(post);
    var r_limit = rows;
    if (m_rows < r_limit) { r_limit = m_rows; }
    var c_limit = cols;
    if (n_cols < c_limit) { c_limit = n_cols; }

    var i = 0.0;
    while (i < r_limit) {
        let pre_val = cartan_vec_get_f32(pre, i);
        var j = 0.0;
        while (j < c_limit) {
            let post_val = cartan_vec_get_f32(post, j);
            let idx = i * cols + j;
            let old_e = cartan_vec_get_f32(traces, idx);
            let new_e = lambda_decay * old_e + (pre_val * post_val);
            cartan_vec_set_f32(traces, idx, new_e);

            let current_w = cartan_vec_get_f32(w_mat, idx);
            cartan_vec_set_f32(w_mat, idx, current_w + lr * m * new_e);
            j = j + 1.0;
        }
        i = i + 1.0;
    }
    return 1.0;
}

// Frobenius / L2 norm of weight matrix for numerical stability monitoring
fn hebbian_matrix_norm(w_mat: ptr, total_len: float) -> float {
    if (w_mat == 0.0 || total_len <= 0.0) { return 0.0; }
    var sum_sq = 0.0;
    var i = 0.0;
    while (i < total_len) {
        let v = cartan_vec_get_f32(w_mat, i);
        sum_sq = sum_sq + (v * v);
        i = i + 1.0;
    }
    return math_sqrt(sum_sq);
}

var g_cortical_weights: ptr = 0.0;
var g_embedding_weights: ptr = 0.0;
var g_cortical_dim: float = 2560.0;
var g_cortical_vocab: float = 2560.0;

fn cartan_hebbian_set_dimensions(dim: float, vocab: float) {
    if (g_cortical_dim <= 0.0) { g_cortical_dim = 2560.0; }
    if (g_cortical_vocab <= 0.0) { g_cortical_vocab = 2560.0; }
    var changed = 0.0;
    if (dim > 0.0 && dim != g_cortical_dim) {
        g_cortical_dim = dim;
        changed = 1.0;
    }
    if (vocab > 0.0 && vocab != g_cortical_vocab) {
        g_cortical_vocab = vocab;
        changed = 1.0;
    }
    if (changed == 1.0) {
        if (g_cortical_weights != 0.0) {
            cartan_vec_free(g_cortical_weights);
            g_cortical_weights = 0.0;
        }
        if (g_embedding_weights != 0.0) {
            cartan_vec_free(g_embedding_weights);
            g_embedding_weights = 0.0;
        }
    }
}

fn cartan_init_cortical_weights_if_needed() {
    if (g_cortical_dim <= 0.0) { g_cortical_dim = 2560.0; }
    if (g_cortical_vocab <= 0.0) { g_cortical_vocab = 2560.0; }
    if (g_cortical_weights == 0.0) {
        let total = g_cortical_dim * g_cortical_vocab;
        g_cortical_weights = cartan_tensor_alloc(total);
        var i = 0.0;
        while (i < total) {
            let ph = math_mod_val(i * 37.0 + 13.0, 100.0) / 100.0 - 0.5;
            g_cortical_weights[2.0 + i] = ph * 0.01;
            i = i + 1.0;
        }
    }
    if (g_embedding_weights == 0.0) {
        let total_w = g_cortical_dim * g_cortical_vocab;
        g_embedding_weights = cartan_tensor_alloc(total_w);
        var j = 0.0;
        while (j < total_w) {
            let cw = g_cortical_weights[2.0 + j];
            g_embedding_weights[2.0 + j] = cw;
            j = j + 1.0;
        }
    }
}

// Pure CARTAN Three-Factor Synaptic Plasticity Update
fn cartan_tensor_hebbian_update(pre: ptr, post: ptr, neuromodulator: float, lr: float) -> float {
    if (pre == 0.0 || post == 0.0) { return 0.0; }
    cartan_init_cortical_weights_if_needed();
    var pre_len = cartan_vec_len(pre);
    if (pre_len > g_cortical_dim) { pre_len = g_cortical_dim; }
    var post_len = cartan_vec_len(post);
    if (post_len > g_cortical_vocab) { post_len = g_cortical_vocab; }
    if (pre_len == 0.0 || post_len == 0.0) { return 0.0; }

    var m = neuromodulator;
    if (m == 0.0) { m = 1.0; }
    var eta = lr;
    if (eta == 0.0) { eta = 0.001; }
    let alpha = 0.01;

    var stride = floor(pre_len / 8.0);
    if (stride < 1.0) { stride = 1.0; }

    var r = 0.0;
    while (r < pre_len) {
        let pre_val = cartan_vec_get_f32(pre, r);
        let sub_r = math_mod_val(floor(r / stride), 8.0);
        let g_r = geom_killing_form_dynkin_weight(sub_r);
        var c = 0.0;
        while (c < post_len) {
            let post_val = cartan_vec_get_f32(post, c);
            let idx = r * g_cortical_vocab + c;
            let cur_w = cartan_vec_get_f32(g_cortical_weights, idx);
            let oja_term = alpha * (post_val * post_val) * cur_w;
            let delta = eta * m * (pre_val * post_val * g_r - oja_term);
            cartan_vec_set_f32(g_cortical_weights, idx, cur_w + delta);
            c = c + 1.0;
        }
        r = r + 1.0;
    }
    return 1.0;
}

// Pure CARTAN Online Single-Column Token-Level Synaptic Reinforcement
fn cartan_hebbian_step_token(hidden_ptr: ptr, tok_id: float, neuromodulator: float, lr: float) -> float {
    if (hidden_ptr == 0.0) { return 0.0; }
    cartan_init_cortical_weights_if_needed();
    var h_len = cartan_vec_len(hidden_ptr);
    if (h_len > g_cortical_dim) { h_len = g_cortical_dim; }
    if (h_len == 0.0) { return 0.0; }

    var target_idx = tok_id;
    if (target_idx < 0.0 || target_idx >= g_cortical_vocab) {
        target_idx = math_mod_val(target_idx, g_cortical_vocab);
    }
    if (target_idx < 0.0 || target_idx >= g_cortical_vocab) {
        return 0.0;
    }

    var m = neuromodulator;
    if (m == 0.0) { m = 1.0; }
    var eta = lr;
    if (eta == 0.0) { eta = 0.001; }
    let alpha = 0.01;

    var stride = floor(h_len / 8.0);
    if (stride < 1.0) { stride = 1.0; }

    var r = 0.0;
    while (r < h_len) {
        let pre_val = cartan_vec_get_f32(hidden_ptr, r);
        let sub_r = math_mod_val(floor(r / stride), 8.0);
        let g_r = geom_killing_form_dynkin_weight(sub_r);
        let post_val = 1.0;
        let idx = r * g_cortical_vocab + target_idx;
        let cur_w = cartan_vec_get_f32(g_cortical_weights, idx);
        let delta = eta * m * (pre_val * post_val * g_r - alpha * cur_w);
        cartan_vec_set_f32(g_cortical_weights, idx, cur_w + delta);
        r = r + 1.0;
    }
    return 1.0;
}

