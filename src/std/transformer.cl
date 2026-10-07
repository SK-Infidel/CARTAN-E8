// src/std/transformer.cl
// CARTAN Standard Library: Native Causal Transformer Decoder Architecture
// Layer 1 Module: std::transformer
// Implements Sovereign GeoMind Causal Transformer Manifold: RMSNorm, RoPE, Grouped-Query Attention (GQA), and SwiGLU MLP

include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/tensor.cl";
include "src/std/gpu.cl";

extern fn exp(x: float) -> float;
extern fn sqrt(x: float) -> float;
extern fn tanh(x: float) -> float;
extern fn sin(x: float) -> float;
extern fn cos(x: float) -> float;
extern fn pow(base: float, exp: float) -> float;
extern fn fmod(x: float, y: float) -> float;
extern fn floor(x: float) -> float;

extern fn calloc(count: float, size: float) -> ptr;
extern fn malloc(size: float) -> ptr;
extern fn free(p: ptr);
extern fn fopen(path: string, mode: string) -> ptr;
extern fn fclose(file: ptr) -> float;
extern fn _fseeki64(file: ptr, offset: float, origin: float) -> float;
extern fn fread(buffer: ptr, size: float, count: float, file: ptr) -> float;
extern fn cartan_mmap_file(path: string) -> ptr;
extern fn cartan_munmap_file(view: ptr) -> float;
extern fn CreateThread(lpThreadAttributes: ptr, dwStackSize: float, lpStartAddress: ptr, lpParameter: ptr, dwCreationFlags: float, lpThreadId: ptr) -> ptr;
extern fn WaitForSingleObject(hHandle: ptr, dwMilliseconds: float) -> float;
extern fn CloseHandle(hObject: ptr) -> float;
extern fn SwitchToThread() -> float;
extern fn Sleep(dwMilliseconds: float) -> void;
extern fn cartan_simd_dot_i8_f32(w_i8: ptr, x_f32: ptr, scale: float, count: float) -> float;
extern fn cartan_simd_dot_i4_f32(w_i4: ptr, x_f32: ptr, scale: float, count: float) -> float;
extern fn cartan_c_ptr_add(p: ptr, offset: float) -> ptr;
extern fn cartan_atomic_f32_at(p: ptr, offset: float) -> float;
extern fn cartan_atomic_set_f32(p: ptr, offset: float, val: float) -> void;
extern fn cartan_memory_fence() -> void;

// 42-Layer Pinned Contiguous KV Cache Arena in pure CARTAN heap
var g_k_cache_arena: ptr = 0.0;
var g_v_cache_arena: ptr = 0.0;
var g_native_emb_buf: ptr = 0.0;
var g_ple_mmap_ptr: ptr = 0.0;
var g_ple_file_handle: ptr = 0.0;
var s_ple_tok_buf: ptr = 0.0;
var g_ple_model_proj_ptr: ptr = 0.0;
var g_ple_proj_norm_ptr: ptr = 0.0;
var s_cached_pli: ptr = 0.0;
var s_cached_proj_all: ptr = 0.0;
var s_cached_pli_token: float = -1.0;
var g_kv_cache_max_seq: float = 16384.0;

fn cartan_kv_cache_set_capacity(max_seq: float) -> float {
    if (max_seq <= 0.0) { return 0.0; }
    if (g_k_cache_arena != 0.0 && g_kv_cache_max_seq == max_seq) { return 1.0; }
    let total_floats = 24.0 * max_seq * 1024.0;
    let new_k = calloc(total_floats, 4.0);
    let new_v = calloc(total_floats, 4.0);
    if (new_k == 0.0 || new_v == 0.0) {
        if (new_k != 0.0) { free(new_k); }
        if (new_v != 0.0) { free(new_v); }
        return 0.0;
    }
    if (g_k_cache_arena != 0.0) { free(g_k_cache_arena); }
    if (g_v_cache_arena != 0.0) { free(g_v_cache_arena); }
    g_k_cache_arena = new_k;
    g_v_cache_arena = new_v;
    g_kv_cache_max_seq = max_seq;
    if (g_trans_scores != 0.0) {
        free(g_trans_scores);
        g_trans_scores = malloc(max_seq * 4.0);
    }
    s_cached_pli_token = -1.0;
    return 1.0;
}

fn cartan_kv_cache_get_capacity() -> float {
    return g_kv_cache_max_seq;
}

fn cartan_kv_cache_init() -> float {
    if (g_k_cache_arena == 0.0) {
        let total_floats = 24.0 * g_kv_cache_max_seq * 1024.0;
        g_k_cache_arena = calloc(total_floats, 4.0);
        g_v_cache_arena = calloc(total_floats, 4.0);
    }
    if (s_cached_pli == 0.0) {
        s_cached_pli = calloc(10752.0, 4.0); // 42 layers * 256 floats
        s_cached_proj_all = calloc(10752.0, 4.0);
    }
    if (g_k_cache_arena != 0.0 && g_v_cache_arena != 0.0) {
        return 1.0;
    }
    return 0.0;
}

fn cartan_kv_cache_reset() -> float {
    cartan_kv_cache_init();
    s_cached_pli_token = -1.0;
    return 1.0;
}

fn cartan_kv_cache_get_k(layer_idx: float) -> ptr {
    if (g_k_cache_arena == 0.0 || layer_idx < 0.0 || layer_idx >= 24.0) { return 0.0; }
    return cartan_f32_ptr_add(g_k_cache_arena, layer_idx * g_kv_cache_max_seq * 1024.0);
}

fn cartan_kv_cache_get_v(layer_idx: float) -> ptr {
    if (g_v_cache_arena == 0.0 || layer_idx < 0.0 || layer_idx >= 24.0) { return 0.0; }
    return cartan_f32_ptr_add(g_v_cache_arena, layer_idx * g_kv_cache_max_seq * 1024.0);
}

// Zero-allocation persistent block for high-throughput KV cache zeroing
var g_kv_zero_block: ptr = 0.0;
var g_kv_mask_block: ptr = 0.0;

// StreamingLLM Attention Sinks & Local Sliding Window Attention (Prefix Sinks = 96.0, Window = 256.0)
var g_attention_sink_tokens: float = 96.0;
var g_attention_window_size: float = 256.0;

fn cartan_transformer_set_attention_window(sink_count: float, window_size: float) {
    g_attention_sink_tokens = sink_count;
    g_attention_window_size = window_size;
}

fn cartan_transformer_get_attention_sink_tokens() -> float {
    return g_attention_sink_tokens;
}

fn cartan_transformer_get_attention_window_size() -> float {
    return g_attention_window_size;
}

// Zero out key/value cache entries across all 24 active layers for rejected sequence positions
// Fills K slots with -10000.0 sentinel and V slots with 0.0, guaranteeing zero softmax attention contribution
fn cartan_kv_cache_clear_range(start_pos: float, end_pos: float) -> float {
    if (g_k_cache_arena == 0.0 || g_v_cache_arena == 0.0) { return 0.0; }
    var sp = start_pos;
    var ep = end_pos;
    if (sp < 0.0) { sp = 0.0; }
    if (ep > g_kv_cache_max_seq) { ep = g_kv_cache_max_seq; }
    if (sp >= ep) { return 0.0; }

    if (g_kv_zero_block == 0.0) {
        g_kv_zero_block = calloc(1024.0, 4.0); // 1 position = 1024 floats = 4096 bytes
    }
    if (g_kv_mask_block == 0.0) {
        g_kv_mask_block = malloc(4096.0);
        var bi = 0.0;
        while (bi < 1024.0) {
            cartan_set_f32(g_kv_mask_block, bi, -10000.0);
            bi = bi + 1.0;
        }
    }

    var l = 0.0;
    while (l < 24.0) {
        let k_base = cartan_kv_cache_get_k(l);
        let v_base = cartan_kv_cache_get_v(l);
        if (k_base != 0.0 && v_base != 0.0) {
            var p = sp;
            while (p < ep) {
                let k_ptr = cartan_f32_ptr_add(k_base, p * 1024.0);
                let v_ptr = cartan_f32_ptr_add(v_base, p * 1024.0);
                cartan_c_memcpy(k_ptr, g_kv_mask_block, 4096.0);
                cartan_c_memcpy(v_ptr, g_kv_zero_block, 4096.0);
                p = p + 1.0;
            }
        }
        l = l + 1.0;
    }
    return ep - sp;
}

// -----------------------------------------------------------------------------
// Thermodynamic Layer Early Exit State & Relative Delta Metric
// -----------------------------------------------------------------------------
var g_early_exit_enabled: float = 1.0;
var g_early_exit_min_layer: float = 30.0;
var g_early_exit_threshold: float = 0.16;

fn cartan_transformer_set_early_exit(enabled: float, min_layer: float, threshold: float) {
    g_early_exit_enabled = enabled;
    var ml = min_layer;
    if (ml < 24.0) { ml = 24.0; } // Invariant: layers 0..23 write KV cache, clamped to >= 24
    g_early_exit_min_layer = ml;
    if (threshold > 0.0) {
        g_early_exit_threshold = threshold;
    }
}

fn cartan_transformer_get_early_exit_enabled() -> float {
    return g_early_exit_enabled;
}

fn cartan_transformer_get_early_exit_min_layer() -> float {
    return g_early_exit_min_layer;
}

fn cartan_transformer_get_early_exit_threshold() -> float {
    return g_early_exit_threshold;
}

// Computes relative Euclidean residual delta: ||v1 - v2||_2 / (||v1||_2 + 1e-12)
fn cartan_vec_relative_delta(v1: ptr, v2: ptr, dim: float) -> float {
    if (v1 == 0.0 || v2 == 0.0 || dim <= 0.0) { return 1.0; }
    var diff_sq = 0.0;
    var norm_sq = 0.0;
    var d = 0.0;
    let limit = dim - 3.0;
    while (d < limit) {
        let a0 = cartan_vec_get_f32(v1, d);
        let b0 = cartan_vec_get_f32(v2, d);
        let diff0 = a0 - b0;
        diff_sq = diff_sq + diff0 * diff0;
        norm_sq = norm_sq + a0 * a0;

        let a1 = cartan_vec_get_f32(v1, d + 1.0);
        let b1 = cartan_vec_get_f32(v2, d + 1.0);
        let diff1 = a1 - b1;
        diff_sq = diff_sq + diff1 * diff1;
        norm_sq = norm_sq + a1 * a1;

        let a2 = cartan_vec_get_f32(v1, d + 2.0);
        let b2 = cartan_vec_get_f32(v2, d + 2.0);
        let diff2 = a2 - b2;
        diff_sq = diff_sq + diff2 * diff2;
        norm_sq = norm_sq + a2 * a2;

        let a3 = cartan_vec_get_f32(v1, d + 3.0);
        let b3 = cartan_vec_get_f32(v2, d + 3.0);
        let diff3 = a3 - b3;
        diff_sq = diff_sq + diff3 * diff3;
        norm_sq = norm_sq + a3 * a3;

        d = d + 4.0;
    }
    while (d < dim) {
        let a = cartan_vec_get_f32(v1, d);
        let b = cartan_vec_get_f32(v2, d);
        let diff = a - b;
        diff_sq = diff_sq + diff * diff;
        norm_sq = norm_sq + a * a;
        d = d + 1.0;
    }
    return sqrt(diff_sq) / (sqrt(norm_sq) + 0.000000000001);
}

fn cartan_set_embedding_buffer(buf: ptr) -> float {
    g_native_emb_buf = buf;
    return 1.0;
}

fn cartan_mmap_ple(path: string) -> float {
    if (g_ple_file_handle != 0.0) { return 1.0; }
    let f = fopen(path, "rb");
    if (f != 0.0) {
        g_ple_file_handle = f;
        if (s_ple_tok_buf == 0.0) {
            s_ple_tok_buf = malloc(43008.0);
        }
        return 1.0;
    }
    return 0.0;
}

fn cartan_set_ple_mmap_ptr(p: ptr) {
    g_ple_mmap_ptr = p;
}

fn cartan_mmap_ple_projection(proj_path: string, norm_path: string) -> float {
    if (g_ple_model_proj_ptr == 0.0 && proj_path != "") {
        g_ple_model_proj_ptr = cartan_mmap_file(proj_path);
    }
    if (g_ple_proj_norm_ptr == 0.0 && norm_path != "") {
        g_ple_proj_norm_ptr = cartan_mmap_file(norm_path);
    }
    if (g_ple_model_proj_ptr != 0.0 && g_ple_proj_norm_ptr != 0.0) {
        return 1.0;
    }
    return 0.0;
}

fn cartan_update_pli_cache_if_needed(tok_id: float) {
    if (tok_id == s_cached_pli_token) { return; }
    s_cached_pli_token = tok_id;
    if (tok_id < 0.0 || tok_id >= 262144.0) { return; }
    if (s_cached_pli == 0.0) {
        s_cached_pli = calloc(10752.0, 4.0);
        s_cached_proj_all = calloc(10752.0, 4.0);
    }

    var ple_tok_row: ptr = 0.0;
    if (g_ple_mmap_ptr != 0.0) {
        ple_tok_row = cartan_f32_ptr_add(g_ple_mmap_ptr, tok_id * 10752.0);
    } else if (g_ple_file_handle != 0.0 && s_ple_tok_buf != 0.0) {
        let byte_offset = tok_id * 43008.0;
        _fseeki64(g_ple_file_handle, byte_offset, 0.0);
        fread(s_ple_tok_buf, 4.0, 10752.0, g_ple_file_handle);
        ple_tok_row = s_ple_tok_buf;
    }
    if (ple_tok_row == 0.0) { return; }

    if (g_ple_model_proj_ptr != 0.0 && g_ple_proj_norm_ptr != 0.0 && g_native_emb_buf != 0.0) {
        let emb_row = cartan_f32_ptr_add(g_native_emb_buf, tok_id * 2560.0);
        var j = 0.0;
        while (j < 10752.0) {
            let p_row = cartan_f32_ptr_add(g_ple_model_proj_ptr, j * 2560.0);
            let dot = cartan_simd_dot_f32(p_row, emb_row, 2560.0);
            cartan_set_f32(s_cached_proj_all, j, dot);
            j = j + 1.0;
        }

        var l = 0.0;
        while (l < 42.0) {
            let p_layer = cartan_f32_ptr_add(s_cached_proj_all, l * 256.0);
            var sq = 0.0;
            var p = 0.0;
            while (p < 256.0) {
                let pv = cartan_f32_at(p_layer, p);
                sq = sq + pv * pv;
                p = p + 1.0;
            }
            let inv_rms = 1.0 / sqrt((sq / 256.0) + 0.000001);
            let pli_layer = cartan_f32_ptr_add(s_cached_pli, l * 256.0);
            let tok_layer = cartan_f32_ptr_add(ple_tok_row, l * 256.0);
            p = 0.0;
            while (p < 256.0) {
                let pv = cartan_f32_at(p_layer, p);
                let norm_val = cartan_f32_at(g_ple_proj_norm_ptr, p);
                let norm_proj = pv * inv_rms * norm_val;
                let tok_ident = cartan_f32_at(tok_layer, p) * 16.0;
                cartan_set_f32(pli_layer, p, (norm_proj + tok_ident) * 0.70710678118);
                p = p + 1.0;
            }
            l = l + 1.0;
        }
    } else {
        var i = 0.0;
        while (i < 10752.0) {
            let tv = cartan_f32_at(ple_tok_row, i);
            cartan_set_f32(s_cached_pli, i, tv * 16.0);
            i = i + 1.0;
        }
    }
}

fn cartan_get_cached_pli(layer_idx: float, tok_id: float) -> ptr {
    cartan_update_pli_cache_if_needed(tok_id);
    if (s_cached_pli == 0.0 || layer_idx < 0.0 || layer_idx >= 42.0) { return 0.0; }
    return cartan_f32_ptr_add(s_cached_pli, layer_idx * 256.0);
}

var g_prompt_pli_buf: ptr = 0.0;

fn cartan_precompute_prompt_pli(prompt_tokens: ptr, num_tokens: float) {
    if (g_prompt_pli_buf != 0.0) {
        free(g_prompt_pli_buf);
        g_prompt_pli_buf = 0.0;
    }
    if (prompt_tokens == 0.0 || num_tokens <= 0.0) { return; }
    let total_bytes = num_tokens * 10752.0 * 4.0;
    g_prompt_pli_buf = malloc(total_bytes);
    if (g_prompt_pli_buf == 0.0) { return; }
    cartan_init_transformer_scratch_buffers();

    var p = 0.0;
    var l = 0.0;
    var pi = 0.0;
    var sq = 0.0;
    var ple_tok_row: ptr = 0.0;
    var tok_layer: ptr = 0.0;
    var tok_ident = 0.0;

    if (g_ple_model_proj_ptr != 0.0 && g_ple_proj_norm_ptr != 0.0 && g_native_emb_buf != 0.0) {
        let b_in_emb = malloc(num_tokens * 2560.0 * 4.0);
        let b_out_proj = malloc(num_tokens * 10752.0 * 4.0);

        p = 0.0;
        while (p < num_tokens) {
            let tok_id = cartan_vec_get_f32(prompt_tokens, p);
            if (tok_id >= 0.0 && tok_id < 262144.0) {
                let src_emb = cartan_f32_ptr_add(g_native_emb_buf, tok_id * 2560.0);
                let dst_emb = cartan_f32_ptr_add(b_in_emb, p * 2560.0);
                cartan_c_memcpy(dst_emb, src_emb, 10240.0);
            }
            p = p + 1.0;
        }

        cartan_trans_pool_dispatch_batch(4.0, 10752.0, 2560.0, num_tokens, 10752.0, g_ple_model_proj_ptr, g_trans_null_ptr, b_in_emb, b_out_proj, g_trans_null_ptr);

        p = 0.0;
        while (p < num_tokens) {
            let tok_id = cartan_vec_get_f32(prompt_tokens, p);
            ple_tok_row = 0.0;
            if (tok_id >= 0.0 && tok_id < 262144.0) {
                if (g_ple_mmap_ptr != 0.0) {
                    ple_tok_row = cartan_f32_ptr_add(g_ple_mmap_ptr, tok_id * 10752.0);
                } else if (g_ple_file_handle != 0.0 && s_ple_tok_buf != 0.0) {
                    let byte_offset = tok_id * 43008.0;
                    _fseeki64(g_ple_file_handle, byte_offset, 0.0);
                    fread(s_ple_tok_buf, 4.0, 10752.0, g_ple_file_handle);
                    ple_tok_row = s_ple_tok_buf;
                }
            }

            l = 0.0;
            while (l < 42.0) {
                let p_layer = cartan_f32_ptr_add(b_out_proj, p * 10752.0 + l * 256.0);
                sq = 0.0;
                pi = 0.0;
                while (pi < 256.0) {
                    let pv = cartan_f32_at(p_layer, pi);
                    sq = sq + pv * pv;
                    pi = pi + 1.0;
                }
                let inv_rms = 1.0 / sqrt((sq / 256.0) + 0.000001);
                let pli_layer = cartan_f32_ptr_add(g_prompt_pli_buf, p * 10752.0 + l * 256.0);
                tok_layer = 0.0;
                if (ple_tok_row != 0.0) {
                    tok_layer = cartan_f32_ptr_add(ple_tok_row, l * 256.0);
                }
                pi = 0.0;
                while (pi < 256.0) {
                    let pv = cartan_f32_at(p_layer, pi);
                    let norm_val = cartan_f32_at(g_ple_proj_norm_ptr, pi);
                    let norm_proj = pv * inv_rms * norm_val;
                    tok_ident = 0.0;
                    if (tok_layer != 0.0) {
                        tok_ident = cartan_f32_at(tok_layer, pi) * 16.0;
                    }
                    cartan_set_f32(pli_layer, pi, (norm_proj + tok_ident) * 0.70710678118);
                    pi = pi + 1.0;
                }
                l = l + 1.0;
            }
            p = p + 1.0;
        }

        free(b_in_emb);
        free(b_out_proj);
    } else {
        p = 0.0;
        while (p < num_tokens) {
            let tok_id = cartan_vec_get_f32(prompt_tokens, p);
            if (tok_id >= 0.0 && tok_id < 262144.0) {
                cartan_update_pli_cache_if_needed(tok_id);
                if (s_cached_pli != 0.0) {
                    let dst = cartan_f32_ptr_add(g_prompt_pli_buf, p * 10752.0);
                    cartan_c_memcpy(dst, s_cached_pli, 43008.0);
                }
            }
            p = p + 1.0;
        }
    }
}

fn cartan_free_prompt_pli() {
    if (g_prompt_pli_buf != 0.0) {
        free(g_prompt_pli_buf);
        g_prompt_pli_buf = 0.0;
    }
}

var g_current_ple_vec: ptr = 0.0;
fn cartan_manifold_layer_set_ple_vec(ple: ptr) {
    g_current_ple_vec = ple;
}

var g_current_token_id: float = -1.0;
fn cartan_manifold_layer_set_current_token(tok: float) {
    g_current_token_id = tok;
}

var g_manifold_is_decode: float = 0.0;
fn cartan_manifold_set_decode_mode(mode: float) {
    g_manifold_is_decode = mode;
}

// -----------------------------------------------------------------------------
// 1. Root Mean Square Layer Normalization (RMSNorm)
// -----------------------------------------------------------------------------
fn cartan_rmsnorm(x: ptr, w: ptr, dim: float, eps: float) -> ptr {
    if (x == 0.0 || dim <= 0.0) { return 0.0; }
    var sum_sq = 0.0;
    var i = 0.0;
    while (i < dim) {
        let val = cartan_vec_get_f32(x, i);
        sum_sq = sum_sq + val * val;
        i = i + 1.0;
    }
    let mean_sq = sum_sq / dim;
    let inv_rms = 1.0 / sqrt(mean_sq + eps);

    let out = cartan_vec_create();
    i = 0.0;
    while (i < dim) {
        let val = cartan_vec_get_f32(x, i);
        var scale = 1.0;
        if (w != 0.0) {
            scale = cartan_vec_get_f32(w, i);
        }
        cartan_vec_push_f32(out, val * inv_rms * scale);
        i = i + 1.0;
    }
    return out;
}

// -----------------------------------------------------------------------------
// 2. Rotary Position Embedding (RoPE)
// -----------------------------------------------------------------------------
fn cartan_rope_apply(vec: ptr, pos: float, head_dim: float, theta_base: float) -> ptr {
    if (vec == 0.0 || head_dim <= 0.0) { return 0.0; }
    let out = cartan_tensor_alloc(head_dim);
    let half = head_dim / 2.0;
    var k = 0.0;
    while (k < half) {
        let x0 = cartan_vec_get_f32(vec, k);
        let x1 = cartan_vec_get_f32(vec, k + half);
        
        let exponent = (k * 2.0) / head_dim;
        var base = theta_base;
        if (base <= 0.0) { base = 10000.0; }
        let freq = 1.0 / pow(base, exponent);
        let theta = pos * freq;
        let c = cos(theta);
        let s = sin(theta);

        // Canonical Manifold / HuggingFace rotate_half:
        // out[k] = x0 * cos - x1 * sin
        // out[k + half] = x1 * cos + x0 * sin
        let rx0 = x0 * c - x1 * s;
        let rx1 = x1 * c + x0 * s;
        cartan_vec_set_f32(out, k, rx0);
        cartan_vec_set_f32(out, k + half, rx1);
        k = k + 1.0;
    }
    return out;
}

// -----------------------------------------------------------------------------
// 3. Activations: GELU (PyTorch Tanh Approximation) & SiLU
// -----------------------------------------------------------------------------
fn cartan_gelu_tanh(x: float) -> float {
    let sqrt_2_over_pi = 0.7978845608;
    let inner = sqrt_2_over_pi * (x + 0.044715 * x * x * x);
    return 0.5 * x * (1.0 + tanh(inner));
}

fn cartan_silu(x: float) -> float {
    return x / (1.0 + exp(0.0 - x));
}

// -----------------------------------------------------------------------------
// 4. SwiGLU / GeGLU Feedforward MLP
// FFN(x) = (SiLU(x * W_gate) * (x * W_up)) * W_down
// -----------------------------------------------------------------------------
fn cartan_swiglu_mlp_forward(x: ptr, gate_w: ptr, up_w: ptr, down_w: ptr, in_dim: float, inter_dim: float) -> ptr {
    if (x == 0.0 || in_dim <= 0.0 || inter_dim <= 0.0) { return 0.0; }
    if (gate_w == 0.0 || up_w == 0.0 || down_w == 0.0) { return 0.0; }
    
    // 1. Compute gate and up projections: [inter_dim]
    let hidden_act = cartan_vec_create();
    var j = 0.0;
    while (j < inter_dim) {
        var dot_gate = 0.0;
        var dot_up = 0.0;
        var i = 0.0;
        let row_off = j * in_dim;
        while (i < in_dim) {
            let xi = cartan_vec_get_f32(x, i);
            dot_gate = dot_gate + xi * cartan_vec_get_f32(gate_w, row_off + i);
            dot_up = dot_up + xi * cartan_vec_get_f32(up_w, row_off + i);
            i = i + 1.0;
        }
        let act = cartan_silu(dot_gate) * dot_up;
        cartan_vec_push_f32(hidden_act, act);
        j = j + 1.0;
    }

    // 2. Compute down projection back to in_dim: [in_dim]
    let out = cartan_vec_create();
    var d = 0.0;
    while (d < in_dim) {
        var dot_down = 0.0;
        j = 0.0;
        let down_row_off = d * inter_dim;
        while (j < inter_dim) {
            let act_j = cartan_vec_get_f32(hidden_act, j);
            dot_down = dot_down + act_j * cartan_vec_get_f32(down_w, down_row_off + j);
            j = j + 1.0;
        }
        cartan_vec_push_f32(out, dot_down);
        d = d + 1.0;
    }
    cartan_vec_free(hidden_act);
    return out;
}

// -----------------------------------------------------------------------------
// 5. Grouped-Query Causal Attention (GQA)
// 8 Query Heads mapped to 2 KV Heads (4:1 head sharing) with head_dim 256
// -----------------------------------------------------------------------------
fn cartan_gqa_causal_attention(q_proj: ptr, k_cache: ptr, v_cache: ptr, seq_len: float, q_heads: float, kv_heads: float, head_dim: float) -> ptr {
    if (q_proj == 0.0 || k_cache == 0.0 || v_cache == 0.0 || seq_len <= 0.0) { return 0.0; }
    
    let total_q_dim = q_heads * head_dim;
    let heads_per_kv = q_heads / kv_heads;
    let inv_scale = 1.0 / sqrt(head_dim);
    let out = cartan_vec_create();

    var qh = 0.0;
    while (qh < q_heads) {
        let kvh = floor(qh / heads_per_kv);
        let q_off = qh * head_dim;
        
        // Compute causal attention scores across sequence history: scores[t] = q · k_t / sqrt(d)
        let scores = cartan_vec_create();
        var max_score = -1000000.0;
        var t = 0.0;
        while (t < seq_len) {
            var dot = 0.0;
            var d = 0.0;
            let k_off = (t * kv_heads + kvh) * head_dim;
            while (d < head_dim) {
                let q_val = cartan_vec_get_f32(q_proj, q_off + d);
                let k_val = cartan_vec_get_f32(k_cache, k_off + d);
                dot = dot + q_val * k_val;
                d = d + 1.0;
            }
            let s = dot * inv_scale;
            if (s > max_score) { max_score = s; }
            cartan_vec_push_f32(scores, s);
            t = t + 1.0;
        }

        // Softmax with numerical stabilization: p_t = exp(s_t - max) / sum(exp(s - max))
        var sum_exp = 0.0;
        t = 0.0;
        while (t < seq_len) {
            let s = cartan_vec_get_f32(scores, t);
            let ep = exp(s - max_score);
            cartan_vec_set_f32(scores, t, ep);
            sum_exp = sum_exp + ep;
            t = t + 1.0;
        }
        if (sum_exp <= 0.0) { sum_exp = 1.0; }

        // Context weighted sum: context_d = sum_t (p_t * v_t,d)
        var cd = 0.0;
        while (cd < head_dim) {
            var weighted_val = 0.0;
            t = 0.0;
            while (t < seq_len) {
                let p_t = cartan_vec_get_f32(scores, t) / sum_exp;
                let v_off = (t * kv_heads + kvh) * head_dim;
                let v_val = cartan_vec_get_f32(v_cache, v_off + cd);
                weighted_val = weighted_val + p_t * v_val;
                t = t + 1.0;
            }
            cartan_vec_push_f32(out, weighted_val);
            cd = cd + 1.0;
        }
        cartan_vec_free(scores);
        qh = qh + 1.0;
    }
    return out;
}

// -----------------------------------------------------------------------------
// 6. Complete Causal Transformer Decoder Layer Forward Step
// h_1 = h + Attention(RMSNorm(h))
// h_2 = h_1 + MLP(RMSNorm(h_1))
// -----------------------------------------------------------------------------
fn cartan_transformer_layer_forward(
    h: ptr,
    w_q: ptr, w_k: ptr, w_v: ptr, w_o: ptr,
    norm_attn_w: ptr, norm_ffn_w: ptr,
    gate_w: ptr, up_w: ptr, down_w: ptr,
    pos: float, seq_len: float, dim: float, inter_dim: float,
    q_heads: float, kv_heads: float, head_dim: float,
    k_cache: ptr, v_cache: ptr
) -> ptr {
    if (h == 0.0 || dim <= 0.0) { return 0.0; }
    if (w_q == 0.0 || w_o == 0.0) { return 0.0; }
    if (gate_w == 0.0 || up_w == 0.0 || down_w == 0.0) { return 0.0; }

    // 1. Pre-Attention RMSNorm
    let normed_h1 = cartan_rmsnorm(h, norm_attn_w, dim, 0.000001);

    // 2. Project to Q, K, V
    let q_raw = cartan_vec_create();
    let q_dim = q_heads * head_dim;
    var q_i = 0.0;
    while (q_i < q_dim) {
        var dot_q = 0.0;
        var r = 0.0;
        let q_row = q_i * dim;
        while (r < dim) {
            let x_r = cartan_vec_get_f32(normed_h1, r);
            dot_q = dot_q + x_r * cartan_vec_get_f32(w_q, q_row + r);
            r = r + 1.0;
        }
        cartan_vec_push_f32(q_raw, dot_q);
        q_i = q_i + 1.0;
    }

    // Apply RoPE on Query heads
    let q_rot = cartan_vec_create();
    var qh = 0.0;
    while (qh < q_heads) {
        let single_head = cartan_vec_create();
        var hd = 0.0;
        let head_off = qh * head_dim;
        while (hd < head_dim) {
            cartan_vec_push_f32(single_head, cartan_vec_get_f32(q_raw, head_off + hd));
            hd = hd + 1.0;
        }
        let rot_head = cartan_rope_apply(single_head, pos, head_dim, 10000.0);
        hd = 0.0;
        while (hd < head_dim) {
            cartan_vec_push_f32(q_rot, cartan_vec_get_f32(rot_head, hd));
            hd = hd + 1.0;
        }
        cartan_vec_free(single_head);
        cartan_vec_free(rot_head);
        qh = qh + 1.0;
    }
    cartan_vec_free(q_raw);

    // 3. Multi-Head GQA Attention
    let attn_heads_out = cartan_gqa_causal_attention(q_rot, k_cache, v_cache, seq_len, q_heads, kv_heads, head_dim);
    cartan_vec_free(q_rot);

    // 4. Output projection W_o: [q_dim] -> [dim] & Residual Addition
    let h1 = cartan_vec_create();
    var d = 0.0;
    while (d < dim) {
        var dot_o = 0.0;
        var c = 0.0;
        let o_row = d * q_dim;
        while (c < q_dim) {
            let ac = cartan_vec_get_f32(attn_heads_out, c);
            dot_o = dot_o + ac * cartan_vec_get_f32(w_o, o_row + c);
            c = c + 1.0;
        }
        let orig = cartan_vec_get_f32(h, d);
        cartan_vec_push_f32(h1, orig + dot_o);
        d = d + 1.0;
    }
    cartan_vec_free(normed_h1);
    cartan_vec_free(attn_heads_out);

    // 5. Pre-FFN RMSNorm
    let normed_h2 = cartan_rmsnorm(h1, norm_ffn_w, dim, 0.000001);

    // 6. SwiGLU MLP & Residual Addition
    let ffn_out = cartan_swiglu_mlp_forward(normed_h2, gate_w, up_w, down_w, dim, inter_dim);
    cartan_vec_free(normed_h2);

    let h2 = cartan_vec_create();
    d = 0.0;
    while (d < dim) {
        let val1 = cartan_vec_get_f32(h1, d);
        let ffn_val = cartan_vec_get_f32(ffn_out, d);
        cartan_vec_push_f32(h2, val1 + ffn_val);
        d = d + 1.0;
    }
    cartan_vec_free(h1);
    cartan_vec_free(ffn_out);

    return h2;
}

// -----------------------------------------------------------------------------
// 7. Manifold Per-Head RMSNorm (QK-Norm)
// Normalizes each of the num_heads slices of size head_dim independently
// -----------------------------------------------------------------------------
fn cartan_rmsnorm_head(vec: ptr, w: ptr, num_heads: float, head_dim: float, eps: float) -> ptr {
    if (vec == 0.0 || num_heads <= 0.0 || head_dim <= 0.0) { return 0.0; }
    let total_dim = num_heads * head_dim;
    let out = cartan_vec_create();
    var h = 0.0;
    while (h < num_heads) {
        let head_off = h * head_dim;
        var sum_sq = 0.0;
        var d = 0.0;
        while (d < head_dim) {
            let val = cartan_vec_get_f32(vec, head_off + d);
            sum_sq = sum_sq + val * val;
            d = d + 1.0;
        }
        let inv_rms = 1.0 / sqrt((sum_sq / head_dim) + eps);
        d = 0.0;
        while (d < head_dim) {
            let val = cartan_vec_get_f32(vec, head_off + d);
            var scale = 1.0;
            if (w != 0.0) {
                scale = cartan_vec_get_f32(w, d);
            }
            cartan_vec_push_f32(out, val * inv_rms * scale);
            d = d + 1.0;
        }
        h = h + 1.0;
    }
    return out;
}

// -----------------------------------------------------------------------------
// 8. GeGLU Feedforward MLP (Manifold Standard Activation)
// FFN(x) = (GELU_tanh(x * W_gate) * (x * W_up)) * W_down
// -----------------------------------------------------------------------------
fn cartan_geglu_mlp_forward(x: ptr, gate_w: ptr, up_w: ptr, down_w: ptr, in_dim: float, inter_dim: float) -> ptr {
    if (x == 0.0 || in_dim <= 0.0 || inter_dim <= 0.0) { return 0.0; }
    if (gate_w == 0.0 || up_w == 0.0 || down_w == 0.0) { return 0.0; }
    
    // 1. Compute gate and up projections: [inter_dim]
    let hidden_act = cartan_vec_create();
    var j = 0.0;
    while (j < inter_dim) {
        var dot_gate = 0.0;
        var dot_up = 0.0;
        var i = 0.0;
        let row_off = j * in_dim;
        while (i < in_dim) {
            let xi = cartan_vec_get_f32(x, i);
            dot_gate = dot_gate + xi * cartan_vec_get_f32(gate_w, row_off + i);
            dot_up = dot_up + xi * cartan_vec_get_f32(up_w, row_off + i);
            i = i + 1.0;
        }
        let act = cartan_gelu_tanh(dot_gate) * dot_up;
        cartan_vec_push_f32(hidden_act, act);
        j = j + 1.0;
    }

    // 2. Compute down projection back to in_dim: [in_dim]
    let out = cartan_vec_create();
    var d = 0.0;
    while (d < in_dim) {
        var dot_down = 0.0;
        j = 0.0;
        let down_row_off = d * inter_dim;
        while (j < inter_dim) {
            let act_j = cartan_vec_get_f32(hidden_act, j);
            dot_down = dot_down + act_j * cartan_vec_get_f32(down_w, down_row_off + j);
            j = j + 1.0;
        }
        cartan_vec_push_f32(out, dot_down);
        d = d + 1.0;
    }
    cartan_vec_free(hidden_act);
    return out;
}

// -----------------------------------------------------------------------------
// 9. Per-Layer Embedding (PLE) Gating Block (Sovereign Manifold Architecture)
// gate = GELU_tanh(W_ple_gate * h) * ple_vec
// h_out = h + RMSNorm(W_ple_proj * gate, norm_w)
// -----------------------------------------------------------------------------
fn cartan_ple_gate_forward(h: ptr, ple_vec: ptr, gate_w: ptr, proj_w: ptr, norm_w: ptr, dim: float, ple_dim: float) -> ptr {
    if (h == 0.0 || ple_vec == 0.0 || dim <= 0.0 || ple_dim <= 0.0) { return h; }
    if (gate_w == 0.0 || proj_w == 0.0) { return h; }

    // 1. Project h to PLE dimension: [ple_dim]
    let act_ple = cartan_vec_create();
    var p = 0.0;
    while (p < ple_dim) {
        var dot_gate = 0.0;
        var d = 0.0;
        let row_off = p * dim;
        while (d < dim) {
            let hd = cartan_vec_get_f32(h, d);
            dot_gate = dot_gate + hd * cartan_vec_get_f32(gate_w, row_off + d);
            d = d + 1.0;
        }
        let ple_val = cartan_vec_get_f32(ple_vec, p);
        let act = cartan_gelu_tanh(dot_gate) * ple_val;
        cartan_vec_push_f32(act_ple, act);
        p = p + 1.0;
    }

    // 2. Project back to hidden dimension: [dim]
    let raw_proj = cartan_vec_create();
    var d_out = 0.0;
    while (d_out < dim) {
        var dot_proj = 0.0;
        p = 0.0;
        let proj_row = d_out * ple_dim;
        while (p < ple_dim) {
            let ap = cartan_vec_get_f32(act_ple, p);
            dot_proj = dot_proj + ap * cartan_vec_get_f32(proj_w, proj_row + p);
            p = p + 1.0;
        }
        cartan_vec_push_f32(raw_proj, dot_proj);
        d_out = d_out + 1.0;
    }
    cartan_vec_free(act_ple);

    // 3. Post-PLE RMSNorm
    let normed_proj = cartan_rmsnorm(raw_proj, norm_w, dim, 0.000001);
    cartan_vec_free(raw_proj);

    // 4. Residual Addition
    let out = cartan_vec_create();
    d_out = 0.0;
    while (d_out < dim) {
        let orig = cartan_vec_get_f32(h, d_out);
        let add_val = cartan_vec_get_f32(normed_proj, d_out);
        cartan_vec_push_f32(out, orig + add_val);
        d_out = d_out + 1.0;
    }
    cartan_vec_free(normed_proj);
    return out;
}

// -----------------------------------------------------------------------------
// 10. Logit Soft-Capping (Manifold Standard: cap = 30.0)
// capped_logit = cap * tanh(logit / cap)
// -----------------------------------------------------------------------------
fn cartan_logit_softcap(logits: ptr, cap: float) -> ptr {
    if (logits == 0.0 || cap <= 0.0) { return logits; }
    let len = cartan_vec_len(logits);
    var i = 0.0;
    let inv_cap = 1.0 / cap;
    while (i < len) {
        let val = cartan_vec_get_f32(logits, i);
        let capped = cap * tanh(val * inv_cap);
        cartan_vec_set_f32(logits, i, capped);
        i = i + 1.0;
    }
    return logits;
}

// -----------------------------------------------------------------------------
// 11. Complete Sovereign GeoMind Causal Transformer Decoder Layer Forward Step
// Supports per-head QK-Norm, sliding (d_head=256) and global (d_head=512) attention,
// dual-theta RoPE, GeGLU MLP, PLE gating, and layer scalar multiplication.
// -----------------------------------------------------------------------------
fn cartan_manifold_layer_forward(
    h: ptr,
    w_q: ptr, w_k: ptr, w_v: ptr, w_o: ptr,
    q_norm_w: ptr, k_norm_w: ptr,
    norm_attn_w: ptr, norm_ffn_w: ptr,
    post_attn_norm_w: ptr, post_ffn_norm_w: ptr,
    gate_w: ptr, up_w: ptr, down_w: ptr,
    ple_vec: ptr, ple_gate_w: ptr, ple_proj_w: ptr, ple_norm_w: ptr,
    layer_scalar: float,
    pos: float, seq_len: float, dim: float, inter_dim: float,
    q_heads: float, kv_heads: float, head_dim: float, rope_theta: float,
    k_cache: ptr, v_cache: ptr
) -> ptr {
    if (h == 0.0 || dim <= 0.0) { return 0.0; }
    if (w_q == 0.0 || w_o == 0.0) { return 0.0; }
    if (gate_w == 0.0 || up_w == 0.0 || down_w == 0.0) { return 0.0; }

    // 1. Pre-Attention RMSNorm
    let normed_h1 = cartan_rmsnorm(h, norm_attn_w, dim, 0.000001);

    // 2. Project to Q, K, V
    let q_raw = cartan_vec_create();
    let q_dim = q_heads * head_dim;
    var q_i = 0.0;
    while (q_i < q_dim) {
        var dot_q = 0.0;
        var r = 0.0;
        let q_row = q_i * dim;
        while (r < dim) {
            let x_r = cartan_vec_get_f32(normed_h1, r);
            dot_q = dot_q + x_r * cartan_vec_get_f32(w_q, q_row + r);
            r = r + 1.0;
        }
        cartan_vec_push_f32(q_raw, dot_q);
        q_i = q_i + 1.0;
    }

    // 3. Per-Head Q-Norm
    let q_normed = cartan_rmsnorm_head(q_raw, q_norm_w, q_heads, head_dim, 0.000001);
    cartan_vec_free(q_raw);

    // 4. Apply RoPE on Query heads with dynamic rope_theta
    let q_rot = cartan_vec_create();
    var qh = 0.0;
    while (qh < q_heads) {
        let single_head = cartan_vec_create();
        var hd = 0.0;
        let head_off = qh * head_dim;
        while (hd < head_dim) {
            cartan_vec_push_f32(single_head, cartan_vec_get_f32(q_normed, head_off + hd));
            hd = hd + 1.0;
        }
        var theta_val = rope_theta;
        if (theta_val <= 0.0) { theta_val = 10000.0; }
        let rot_head = cartan_rope_apply(single_head, pos, head_dim, theta_val);
        hd = 0.0;
        while (hd < head_dim) {
            cartan_vec_push_f32(q_rot, cartan_vec_get_f32(rot_head, hd));
            hd = hd + 1.0;
        }
        cartan_vec_free(single_head);
        cartan_vec_free(rot_head);
        qh = qh + 1.0;
    }
    cartan_vec_free(q_normed);

    // 5. Multi-Head GQA Attention
    let attn_heads_out = cartan_gqa_causal_attention(q_rot, k_cache, v_cache, seq_len, q_heads, kv_heads, head_dim);
    cartan_vec_free(q_rot);

    // 6. Output projection W_o: [q_dim] -> [dim] & Post-Attention RMSNorm
    let o_raw = cartan_vec_create();
    var d = 0.0;
    while (d < dim) {
        var dot_o = 0.0;
        var c = 0.0;
        let o_row = d * q_dim;
        while (c < q_dim) {
            let ac = cartan_vec_get_f32(attn_heads_out, c);
            dot_o = dot_o + ac * cartan_vec_get_f32(w_o, o_row + c);
            c = c + 1.0;
        }
        cartan_vec_push_f32(o_raw, dot_o);
        d = d + 1.0;
    }
    cartan_vec_free(normed_h1);
    cartan_vec_free(attn_heads_out);

    var o_normed = o_raw;
    if (post_attn_norm_w != 0.0) {
        o_normed = cartan_rmsnorm(o_raw, post_attn_norm_w, dim, 0.000001);
        cartan_vec_free(o_raw);
    }

    // Residual Addition: h1 = h + o_normed
    let h1 = cartan_vec_create();
    d = 0.0;
    while (d < dim) {
        let orig = cartan_vec_get_f32(h, d);
        let add_o = cartan_vec_get_f32(o_normed, d);
        cartan_vec_push_f32(h1, orig + add_o);
        d = d + 1.0;
    }
    cartan_vec_free(o_normed);

    // 7. Pre-FFN RMSNorm
    let normed_h2 = cartan_rmsnorm(h1, norm_ffn_w, dim, 0.000001);

    // 8. GeGLU MLP & Post-FFN RMSNorm
    let ffn_raw = cartan_geglu_mlp_forward(normed_h2, gate_w, up_w, down_w, dim, inter_dim);
    cartan_vec_free(normed_h2);

    var ffn_normed = ffn_raw;
    if (post_ffn_norm_w != 0.0) {
        ffn_normed = cartan_rmsnorm(ffn_raw, post_ffn_norm_w, dim, 0.000001);
        cartan_vec_free(ffn_raw);
    }

    // Residual Addition: h2 = h1 + ffn_normed
    let h2 = cartan_vec_create();
    d = 0.0;
    while (d < dim) {
        let val1 = cartan_vec_get_f32(h1, d);
        let ffn_val = cartan_vec_get_f32(ffn_normed, d);
        cartan_vec_push_f32(h2, val1 + ffn_val);
        d = d + 1.0;
    }
    cartan_vec_free(h1);
    cartan_vec_free(ffn_normed);

    // 9. Per-Layer Embedding (PLE) Gating
    var h3 = h2;
    if (ple_vec != 0.0 && ple_gate_w != 0.0 && ple_proj_w != 0.0) {
        h3 = cartan_ple_gate_forward(h2, ple_vec, ple_gate_w, ple_proj_w, ple_norm_w, dim, 256.0);
        cartan_vec_free(h2);
    }

    // 10. Layer Scalar Multiplier
    var scalar_val = layer_scalar;
    if (scalar_val == 0.0) { scalar_val = 1.0; }
    let h_out = cartan_vec_create();
    d = 0.0;
    while (d < dim) {
        let v = cartan_vec_get_f32(h3, d);
        cartan_vec_push_f32(h_out, v * scalar_val);
        d = d + 1.0;
    }
    cartan_vec_free(h3);

    return h_out;
}

// -----------------------------------------------------------------------------
// 12. Ultra-Fast In-Place Sovereign Manifold Transformer Decoder Layer Forward from Raw Binary Buffer
// -----------------------------------------------------------------------------
// Pure Native CARTAN Fast GELU Tanh Activation
// -----------------------------------------------------------------------------
fn cartan_fast_gelu_tanh(x: float) -> float {
    if (x > 10.0) { return x; }
    if (x < -10.0) { return 0.0; }
    let x3 = x * x * x;
    let inner = 0.79788456 * (x + 0.044715 * x3);
    var t = inner;
    if (t > 10.0) { t = 1.0; }
    else if (t < -10.0) { t = -1.0; }
    else { t = tanh(t); }
    return 0.5 * x * (1.0 + t);
}

// -----------------------------------------------------------------------------
// WebGPU Full-VRAM Resident INT8 Manifold Engine
// Pins all 42 INT8 layers (3.73 GB total) permanently resident in GPU GDDR6 VRAM
// Pre-creates persistent bind groups to eliminate descriptor table churn ([ISSUE-360])
// Dispatches fused GeGLU + Down GEMVs via single command submission (< 1.5 ms / layer)
// -----------------------------------------------------------------------------
var g_trans_gpu_int8_ready: float = 0.0;
var g_trans_gpu_int8_pipe_geglu: ptr = 0.0;
var g_trans_gpu_int8_pipe_down: ptr = 0.0;
var g_trans_gpu_int8_pipe_geglu_global: ptr = 0.0;
var g_trans_gpu_int8_pipe_down_global: ptr = 0.0;
var g_trans_gpu_int8_x: ptr = 0.0;
var g_trans_gpu_int8_act: ptr = 0.0;
var g_trans_gpu_int8_out: ptr = 0.0;
var g_trans_gpu_int8_layers: ptr = 0.0;
var g_trans_gpu_int8_bgs_geglu: ptr = 0.0;
var g_trans_gpu_int8_bgs_down: ptr = 0.0;

fn cartan_transformer_init_gpu_resident_int8() -> float {
    if (g_trans_gpu_int8_ready == 1.0) { return 1.0; }
    let ok = gpu_init();
    if (ok != 1.0) { return 0.0; }

    let dim = 2560.0;
    let inter_dim = 10240.0;

    g_trans_gpu_int8_x = gpu_alloc(dim * 4.0);
    g_trans_gpu_int8_act = gpu_alloc(inter_dim * 4.0);
    g_trans_gpu_int8_out = gpu_alloc(dim * 4.0);

    let wgsl_geglu = "fn cartan_fast_gelu_tanh(x: f32) -> f32 {\n    if (x > 10.0f) { return x; }\n    if (x < -10.0f) { return 0.0f; }\n    let x3: f32 = x * x * x;\n    let inner: f32 = 0.79788456f * (x + 0.044715f * x3);\n    var t: f32 = inner;\n    if (t > 10.0f) { t = 1.0f; }\n    else if (t < -10.0f) { t = -1.0f; }\n    else { t = tanh(t);\n    }\n    return 0.5f * x * (1.0f + t);\n}\n\n@group(0) @binding(0) var<storage, read> in_x: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_act: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn geglu_int8_fwd(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    if (row >= 10240u) { return; }\n    let row_gate_offset: u32 = 3301392u + row * 640u;\n    let row_up_offset: u32 = 9865232u + row * 640u;\n    var dot_gate: f32 = 0.0;\n    var dot_up: f32 = 0.0;\n    for (var k: u32 = 0u; k < 640u; k = k + 4u) {\n        let xv0: vec4<f32> = in_x[k];\n        let xv1: vec4<f32> = in_x[k + 1u];\n        let xv2: vec4<f32> = in_x[k + 2u];\n        let xv3: vec4<f32> = in_x[k + 3u];\n        let wg0: vec4<f32> = unpack4x8snorm(layer_weights[row_gate_offset + k]);\n        let wg1: vec4<f32> = unpack4x8snorm(layer_weights[row_gate_offset + k + 1u]);\n        let wg2: vec4<f32> = unpack4x8snorm(layer_weights[row_gate_offset + k + 2u]);\n        let wg3: vec4<f32> = unpack4x8snorm(layer_weights[row_gate_offset + k + 3u]);\n        let wu0: vec4<f32> = unpack4x8snorm(layer_weights[row_up_offset + k]);\n        let wu1: vec4<f32> = unpack4x8snorm(layer_weights[row_up_offset + k + 1u]);\n        let wu2: vec4<f32> = unpack4x8snorm(layer_weights[row_up_offset + k + 2u]);\n        let wu3: vec4<f32> = unpack4x8snorm(layer_weights[row_up_offset + k + 3u]);\n        dot_gate = dot_gate + (dot(wg0, xv0) + dot(wg1, xv1) + dot(wg2, xv2) + dot(wg3, xv3));\n        dot_up = dot_up + (dot(wu0, xv0) + dot(wu1, xv1) + dot(wu2, xv2) + dot(wu3, xv3));\n    }\n    let scale_gate: f32 = bitcast<f32>(layer_weights[3291152u + row]) * 127.0;\n    let scale_up: f32 = bitcast<f32>(layer_weights[9854992u + row]) * 127.0;\n    let v_gate: f32 = dot_gate * scale_gate;\n    let v_up: f32 = dot_up * scale_up;\n    out_act[row] = cartan_fast_gelu_tanh(v_gate) * v_up;\n}\n";

    let wgsl_down = "@group(0) @binding(0) var<storage, read> in_act: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_ffn: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn down_proj_int8_fwd(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    if (row >= 2560u) { return; }\n    let row_offset: u32 = 16421392u + row * 2560u;\n    var sum: f32 = 0.0;\n    for (var k: u32 = 0u; k < 2560u; k = k + 4u) {\n        let act_v0: vec4<f32> = in_act[k];\n        let act_v1: vec4<f32> = in_act[k + 1u];\n        let act_v2: vec4<f32> = in_act[k + 2u];\n        let act_v3: vec4<f32> = in_act[k + 3u];\n        let wd0: vec4<f32> = unpack4x8snorm(layer_weights[row_offset + k]);\n        let wd1: vec4<f32> = unpack4x8snorm(layer_weights[row_offset + k + 1u]);\n        let wd2: vec4<f32> = unpack4x8snorm(layer_weights[row_offset + k + 2u]);\n        let wd3: vec4<f32> = unpack4x8snorm(layer_weights[row_offset + k + 3u]);\n        sum = sum + (dot(wd0, act_v0) + dot(wd1, act_v1) + dot(wd2, act_v2) + dot(wd3, act_v3));\n    }\n    let scale_down: f32 = bitcast<f32>(layer_weights[16418832u + row]) * 127.0;\n    out_ffn[row] = sum * scale_down;\n}\n";

    let wgsl_geglu_global = "fn cartan_fast_gelu_tanh(x: f32) -> f32 {\n    if (x > 10.0f) { return x; }\n    if (x < -10.0f) { return 0.0f; }\n    let x3: f32 = x * x * x;\n    let inner: f32 = 0.79788456f * (x + 0.044715f * x3);\n    var t: f32 = inner;\n    if (t > 10.0f) { t = 1.0f; }\n    else if (t < -10.0f) { t = -1.0f; }\n    else { t = tanh(t);\n    }\n    return 0.5f * x * (1.0f + t);\n}\n\n@group(0) @binding(0) var<storage, read> in_x: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_act: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn geglu_int8_fwd_global(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    if (row >= 10240u) { return; }\n    let row_gate_offset: u32 = 6581264u + row * 640u;\n    let row_up_offset: u32 = 13145104u + row * 640u;\n    var dot_gate: f32 = 0.0;\n    var dot_up: f32 = 0.0;\n    for (var k: u32 = 0u; k < 640u; k = k + 4u) {\n        let xv0: vec4<f32> = in_x[k];\n        let xv1: vec4<f32> = in_x[k + 1u];\n        let xv2: vec4<f32> = in_x[k + 2u];\n        let xv3: vec4<f32> = in_x[k + 3u];\n        let wg0: vec4<f32> = unpack4x8snorm(layer_weights[row_gate_offset + k]);\n        let wg1: vec4<f32> = unpack4x8snorm(layer_weights[row_gate_offset + k + 1u]);\n        let wg2: vec4<f32> = unpack4x8snorm(layer_weights[row_gate_offset + k + 2u]);\n        let wg3: vec4<f32> = unpack4x8snorm(layer_weights[row_gate_offset + k + 3u]);\n        let wu0: vec4<f32> = unpack4x8snorm(layer_weights[row_up_offset + k]);\n        let wu1: vec4<f32> = unpack4x8snorm(layer_weights[row_up_offset + k + 1u]);\n        let wu2: vec4<f32> = unpack4x8snorm(layer_weights[row_up_offset + k + 2u]);\n        let wu3: vec4<f32> = unpack4x8snorm(layer_weights[row_up_offset + k + 3u]);\n        dot_gate = dot_gate + (dot(wg0, xv0) + dot(wg1, xv1) + dot(wg2, xv2) + dot(wg3, xv3));\n        dot_up = dot_up + (dot(wu0, xv0) + dot(wu1, xv1) + dot(wu2, xv2) + dot(wu3, xv3));\n    }\n    let scale_gate: f32 = bitcast<f32>(layer_weights[6571024u + row]) * 127.0;\n    let scale_up: f32 = bitcast<f32>(layer_weights[13134864u + row]) * 127.0;\n    let v_gate: f32 = dot_gate * scale_gate;\n    let v_up: f32 = dot_up * scale_up;\n    out_act[row] = cartan_fast_gelu_tanh(v_gate) * v_up;\n}\n";

    let wgsl_down_global = "@group(0) @binding(0) var<storage, read> in_act: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_ffn: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn down_proj_int8_fwd_global(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    if (row >= 2560u) { return; }\n    let row_offset: u32 = 19701264u + row * 2560u;\n    var sum: f32 = 0.0;\n    for (var k: u32 = 0u; k < 2560u; k = k + 4u) {\n        let act_v0: vec4<f32> = in_act[k];\n        let act_v1: vec4<f32> = in_act[k + 1u];\n        let act_v2: vec4<f32> = in_act[k + 2u];\n        let act_v3: vec4<f32> = in_act[k + 3u];\n        let wd0: vec4<f32> = unpack4x8snorm(layer_weights[row_offset + k]);\n        let wd1: vec4<f32> = unpack4x8snorm(layer_weights[row_offset + k + 1u]);\n        let wd2: vec4<f32> = unpack4x8snorm(layer_weights[row_offset + k + 2u]);\n        let wd3: vec4<f32> = unpack4x8snorm(layer_weights[row_offset + k + 3u]);\n        sum = sum + (dot(wd0, act_v0) + dot(wd1, act_v1) + dot(wd2, act_v2) + dot(wd3, act_v3));\n    }\n    let scale_down: f32 = bitcast<f32>(layer_weights[19698704u + row]) * 127.0;\n    out_ffn[row] = sum * scale_down;\n}\n";

    g_trans_gpu_int8_pipe_geglu = gpu_create_pipeline(wgsl_geglu, "geglu_int8_fwd");
    g_trans_gpu_int8_pipe_down = gpu_create_pipeline(wgsl_down, "down_proj_int8_fwd");
    g_trans_gpu_int8_pipe_geglu_global = gpu_create_pipeline(wgsl_geglu_global, "geglu_int8_fwd_global");
    g_trans_gpu_int8_pipe_down_global = gpu_create_pipeline(wgsl_down_global, "down_proj_int8_fwd_global");

    if (g_trans_gpu_int8_pipe_geglu == 0.0 || g_trans_gpu_int8_pipe_down == 0.0 ||
        g_trans_gpu_int8_pipe_geglu_global == 0.0 || g_trans_gpu_int8_pipe_down_global == 0.0) {
        return 0.0;
    }

    g_trans_gpu_int8_layers = malloc(42.0 * 8.0);
    g_trans_gpu_int8_bgs_geglu = malloc(42.0 * 8.0);
    g_trans_gpu_int8_bgs_down = malloc(42.0 * 8.0);

    var l = 0.0;
    while (l < 42.0) {
        cartan_set_ptr(g_trans_gpu_int8_layers, l, 0.0);
        cartan_set_ptr(g_trans_gpu_int8_bgs_geglu, l, 0.0);
        cartan_set_ptr(g_trans_gpu_int8_bgs_down, l, 0.0);
        l = l + 1.0;
    }

    g_trans_gpu_int8_ready = 1.0;
    return 1.0;
}

fn cartan_transformer_upload_gpu_resident_layer(layer_idx: float, host_layer_buf: ptr) -> float {
    if (g_trans_gpu_int8_ready == 0.0) {
        let init_ok = cartan_transformer_init_gpu_resident_int8();
        if (init_ok != 1.0) { return 0.0; }
    }
    if (layer_idx < 0.0 || layer_idx >= 42.0 || host_layer_buf == 0.0) { return 0.0; }

    let is_int8 = cartan_f32_at(host_layer_buf, 11.0);
    if (is_int8 != 1.0) { return 0.0; }

    // Check if already uploaded
    let existing_buf = cartan_ptr_at(g_trans_gpu_int8_layers, layer_idx);
    if (existing_buf != 0.0) { return 1.0; }

    let is_global = (fmod(layer_idx + 1.0, 6.0) == 0.0);
    var total_bytes = 93242432.0;
    var pipe_geglu = g_trans_gpu_int8_pipe_geglu;
    var pipe_down = g_trans_gpu_int8_pipe_down;
    if (is_global > 0.0) {
        total_bytes = 106361920.0;
        pipe_geglu = g_trans_gpu_int8_pipe_geglu_global;
        pipe_down = g_trans_gpu_int8_pipe_down_global;
    }

    let gpu_layer = gpu_alloc(total_bytes);
    if (gpu_layer == 0.0) { return 0.0; }

    let w_ok = gpu_write(gpu_layer, host_layer_buf, total_bytes);
    if (w_ok != 1.0) {
        gpu_free(gpu_layer);
        return 0.0;
    }

    // Pre-create persistent GeGLU Bind Group (in_x=0, layer_weights=1, out_act=2)
    let tree_geglu = cartan_tree_create();
    cartan_tree_push(tree_geglu, g_trans_gpu_int8_x);
    cartan_tree_push(tree_geglu, gpu_layer);
    cartan_tree_push(tree_geglu, g_trans_gpu_int8_act);
    let bg_geglu = gpu_create_bind_group(pipe_geglu, tree_geglu, 3.0);
    cartan_tree_free(tree_geglu);

    // Pre-create persistent Down Bind Group (in_act=0, layer_weights=1, out_ffn=2)
    let tree_down = cartan_tree_create();
    cartan_tree_push(tree_down, g_trans_gpu_int8_act);
    cartan_tree_push(tree_down, gpu_layer);
    cartan_tree_push(tree_down, g_trans_gpu_int8_out);
    let bg_down = gpu_create_bind_group(pipe_down, tree_down, 3.0);
    cartan_tree_free(tree_down);

    if (bg_geglu == 0.0 || bg_down == 0.0) {
        return 0.0;
    }

    cartan_set_ptr(g_trans_gpu_int8_layers, layer_idx, gpu_layer);
    cartan_set_ptr(g_trans_gpu_int8_bgs_geglu, layer_idx, bg_geglu);
    cartan_set_ptr(g_trans_gpu_int8_bgs_down, layer_idx, bg_down);
    return 1.0;
}

fn cartan_transformer_dispatch_gpu_layer_int8(
    layer_idx: float,
    in_norm_h2: ptr,
    out_ffn_raw: ptr,
    dim: float,
    inter_dim: float
) -> float {
    if (g_trans_gpu_int8_ready == 0.0 || in_norm_h2 == 0.0 || out_ffn_raw == 0.0) { return 0.0; }
    if (layer_idx < 0.0 || layer_idx >= 42.0) { return 0.0; }

    let bg_geglu = cartan_ptr_at(g_trans_gpu_int8_bgs_geglu, layer_idx);
    let bg_down = cartan_ptr_at(g_trans_gpu_int8_bgs_down, layer_idx);
    if (bg_geglu == 0.0 || bg_down == 0.0) { return 0.0; }

    let is_global = (fmod(layer_idx + 1.0, 6.0) == 0.0);
    var pipe_geglu = g_trans_gpu_int8_pipe_geglu;
    var pipe_down = g_trans_gpu_int8_pipe_down;
    if (is_global > 0.0) {
        pipe_geglu = g_trans_gpu_int8_pipe_geglu_global;
        pipe_down = g_trans_gpu_int8_pipe_down_global;
    }

    let bytes_x = dim * 4.0;
    gpu_write(g_trans_gpu_int8_x, in_norm_h2, bytes_x);

    let ok = gpu_dispatch_fused_geglu_down_read(
        pipe_geglu,
        bg_geglu,
        pipe_down,
        bg_down,
        inter_dim,
        dim,
        g_trans_gpu_int8_out,
        out_ffn_raw,
        bytes_x
    );
    return ok;
}

// -----------------------------------------------------------------------------
// WebGPU Full-VRAM Resident INT4 Manifold Engine
// Pins all 42 INT4 layers (1.87 GB total) permanently resident in GPU GDDR6 VRAM
// Pre-creates persistent bind groups to eliminate descriptor table churn ([ISSUE-360])
// Dispatches fused GeGLU + Down GEMVs via single command submission (< 1.5 ms / layer)
// -----------------------------------------------------------------------------
var g_trans_gpu_int4_ready: float = 0.0;
var g_trans_gpu_int4_pipe_geglu: ptr = 0.0;
var g_trans_gpu_int4_pipe_down: ptr = 0.0;
var g_trans_gpu_int4_pipe_geglu_global: ptr = 0.0;
var g_trans_gpu_int4_pipe_down_global: ptr = 0.0;
var g_trans_gpu_int4_pipe_geglu_batch: ptr = 0.0;
var g_trans_gpu_int4_pipe_down_batch: ptr = 0.0;
var g_trans_gpu_int4_pipe_geglu_batch_global: ptr = 0.0;
var g_trans_gpu_int4_pipe_down_batch_global: ptr = 0.0;
var g_trans_gpu_int4_x: ptr = 0.0;
var g_trans_gpu_int4_act: ptr = 0.0;
var g_trans_gpu_int4_out: ptr = 0.0;
var g_trans_gpu_int4_batch_cap: float = 16384.0;
var g_trans_gpu_int4_batch_x: ptr = 0.0;
var g_trans_gpu_int4_batch_act: ptr = 0.0;
var g_trans_gpu_int4_batch_out: ptr = 0.0;
var g_trans_gpu_int4_layers: ptr = 0.0;
var g_trans_gpu_int4_bgs_geglu: ptr = 0.0;
var g_trans_gpu_int4_bgs_down: ptr = 0.0;
var g_trans_gpu_int4_bgs_geglu_batch: ptr = 0.0;
var g_trans_gpu_int4_bgs_down_batch: ptr = 0.0;

fn cartan_transformer_init_gpu_resident_int4() -> float {
    if (g_trans_gpu_int4_ready == 1.0) { return 1.0; }
    let ok = gpu_init();
    if (ok != 1.0) { return 0.0; }

    let dim = 2560.0;
    let inter_dim = 10240.0;

    g_trans_gpu_int4_x = gpu_alloc(dim * 4.0);
    g_trans_gpu_int4_act = gpu_alloc(inter_dim * 4.0);
    g_trans_gpu_int4_out = gpu_alloc(dim * 4.0);

    let batch_cap = g_trans_gpu_int4_batch_cap;
    g_trans_gpu_int4_batch_x = gpu_alloc(batch_cap * dim * 4.0);
    g_trans_gpu_int4_batch_act = gpu_alloc(batch_cap * inter_dim * 4.0);
    g_trans_gpu_int4_batch_out = gpu_alloc(batch_cap * dim * 4.0);

    let wgsl_geglu = "fn cartan_fast_gelu_tanh(x: f32) -> f32 {\n    if (x > 10.0f) { return x; }\n    if (x < -10.0f) { return 0.0f; }\n    let x3: f32 = x * x * x;\n    let inner: f32 = 0.79788456f * (x + 0.044715f * x3);\n    var t: f32 = inner;\n    if (t > 10.0f) { t = 1.0f; }\n    else if (t < -10.0f) { t = -1.0f; }\n    else { t = tanh(t);\n    }\n    return 0.5f * x * (1.0f + t);\n}\n\n@group(0) @binding(0) var<storage, read> in_x: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_act: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn geglu_int4_fwd(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    if (row >= 10240u) { return; }\n    let row_gate_offset: u32 = 1662992u + row * 320u;\n    let row_up_offset: u32 = 4950032u + row * 320u;\n    var dot_gate: f32 = 0.0;\n    var dot_up: f32 = 0.0;\n    for (var k: u32 = 0u; k < 320u; k = k + 2u) {\n        let xv0: vec4<f32> = in_x[k * 2u];\n        let xv1: vec4<f32> = in_x[k * 2u + 1u];\n        let xv2: vec4<f32> = in_x[k * 2u + 2u];\n        let xv3: vec4<f32> = in_x[k * 2u + 3u];\n        let raw_g0: u32 = layer_weights[row_gate_offset + k];\n        let vg0_l = round(unpack4x8unorm(raw_g0 & 0x0F0F0F0Fu) * 255.0f);\n        let sg0_l = select(vg0_l, vg0_l - 16.0f, vg0_l >= vec4<f32>(8.0f));\n        let vg0_h = round(unpack4x8unorm((raw_g0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let sg0_h = select(vg0_h, vg0_h - 16.0f, vg0_h >= vec4<f32>(8.0f));\n        let wg0 = vec4<f32>(sg0_l.x, sg0_h.x, sg0_l.y, sg0_h.y);\n        let wg1 = vec4<f32>(sg0_l.z, sg0_h.z, sg0_l.w, sg0_h.w);\n        let raw_g1: u32 = layer_weights[row_gate_offset + k + 1u];\n        let vg1_l = round(unpack4x8unorm(raw_g1 & 0x0F0F0F0Fu) * 255.0f);\n        let sg1_l = select(vg1_l, vg1_l - 16.0f, vg1_l >= vec4<f32>(8.0f));\n        let vg1_h = round(unpack4x8unorm((raw_g1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let sg1_h = select(vg1_h, vg1_h - 16.0f, vg1_h >= vec4<f32>(8.0f));\n        let wg2 = vec4<f32>(sg1_l.x, sg1_h.x, sg1_l.y, sg1_h.y);\n        let wg3 = vec4<f32>(sg1_l.z, sg1_h.z, sg1_l.w, sg1_h.w);\n        let raw_u0: u32 = layer_weights[row_up_offset + k];\n        let vu0_l = round(unpack4x8unorm(raw_u0 & 0x0F0F0F0Fu) * 255.0f);\n        let su0_l = select(vu0_l, vu0_l - 16.0f, vu0_l >= vec4<f32>(8.0f));\n        let vu0_h = round(unpack4x8unorm((raw_u0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let su0_h = select(vu0_h, vu0_h - 16.0f, vu0_h >= vec4<f32>(8.0f));\n        let wu0 = vec4<f32>(su0_l.x, su0_h.x, su0_l.y, su0_h.y);\n        let wu1 = vec4<f32>(su0_l.z, su0_h.z, su0_l.w, su0_h.w);\n        let raw_u1: u32 = layer_weights[row_up_offset + k + 1u];\n        let vu1_l = round(unpack4x8unorm(raw_u1 & 0x0F0F0F0Fu) * 255.0f);\n        let su1_l = select(vu1_l, vu1_l - 16.0f, vu1_l >= vec4<f32>(8.0f));\n        let vu1_h = round(unpack4x8unorm((raw_u1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let su1_h = select(vu1_h, vu1_h - 16.0f, vu1_h >= vec4<f32>(8.0f));\n        let wu2 = vec4<f32>(su1_l.x, su1_h.x, su1_l.y, su1_h.y);\n        let wu3 = vec4<f32>(su1_l.z, su1_h.z, su1_l.w, su1_h.w);\n        dot_gate = dot_gate + (dot(wg0, xv0) + dot(wg1, xv1) + dot(wg2, xv2) + dot(wg3, xv3));\n        dot_up = dot_up + (dot(wu0, xv0) + dot(wu1, xv1) + dot(wu2, xv2) + dot(wu3, xv3));\n    }\n    let scale_gate: f32 = bitcast<f32>(layer_weights[1652752u + row]);\n    let scale_up: f32 = bitcast<f32>(layer_weights[4939792u + row]);\n    let v_gate: f32 = dot_gate * scale_gate;\n    let v_up: f32 = dot_up * scale_up;\n    out_act[row] = cartan_fast_gelu_tanh(v_gate) * v_up;\n}\n";

    let wgsl_down = "@group(0) @binding(0) var<storage, read> in_act: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_ffn: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn down_proj_int4_fwd(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    if (row >= 2560u) { return; }\n    let row_offset: u32 = 8229392u + row * 1280u;\n    var sum: f32 = 0.0;\n    for (var k: u32 = 0u; k < 1280u; k = k + 2u) {\n        let act_v0: vec4<f32> = in_act[k * 2u];\n        let act_v1: vec4<f32> = in_act[k * 2u + 1u];\n        let act_v2: vec4<f32> = in_act[k * 2u + 2u];\n        let act_v3: vec4<f32> = in_act[k * 2u + 3u];\n        let raw0: u32 = layer_weights[row_offset + k];\n        let v0_l = round(unpack4x8unorm(raw0 & 0x0F0F0F0Fu) * 255.0f);\n        let s0_l = select(v0_l, v0_l - 16.0f, v0_l >= vec4<f32>(8.0f));\n        let v0_h = round(unpack4x8unorm((raw0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let s0_h = select(v0_h, v0_h - 16.0f, v0_h >= vec4<f32>(8.0f));\n        let wd0 = vec4<f32>(s0_l.x, s0_h.x, s0_l.y, s0_h.y);\n        let wd1 = vec4<f32>(s0_l.z, s0_h.z, s0_l.w, s0_h.w);\n        let raw1: u32 = layer_weights[row_offset + k + 1u];\n        let v1_l = round(unpack4x8unorm(raw1 & 0x0F0F0F0Fu) * 255.0f);\n        let s1_l = select(v1_l, v1_l - 16.0f, v1_l >= vec4<f32>(8.0f));\n        let v1_h = round(unpack4x8unorm((raw1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let s1_h = select(v1_h, v1_h - 16.0f, v1_h >= vec4<f32>(8.0f));\n        let wd2 = vec4<f32>(s1_l.x, s1_h.x, s1_l.y, s1_h.y);\n        let wd3 = vec4<f32>(s1_l.z, s1_h.z, s1_l.w, s1_h.w);\n        sum = sum + (dot(wd0, act_v0) + dot(wd1, act_v1) + dot(wd2, act_v2) + dot(wd3, act_v3));\n    }\n    let scale_down: f32 = bitcast<f32>(layer_weights[8226832u + row]);\n    out_ffn[row] = sum * scale_down;\n}\n";

    let wgsl_geglu_global = "fn cartan_fast_gelu_tanh(x: f32) -> f32 {\n    if (x > 10.0f) { return x; }\n    if (x < -10.0f) { return 0.0f; }\n    let x3: f32 = x * x * x;\n    let inner: f32 = 0.79788456f * (x + 0.044715f * x3);\n    var t: f32 = inner;\n    if (t > 10.0f) { t = 1.0f; }\n    else if (t < -10.0f) { t = -1.0f; }\n    else { t = tanh(t);\n    }\n    return 0.5f * x * (1.0f + t);\n}\n\n@group(0) @binding(0) var<storage, read> in_x: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_act: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn geglu_int4_fwd_global(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    if (row >= 10240u) { return; }\n    let row_gate_offset: u32 = 3304464u + row * 320u;\n    let row_up_offset: u32 = 6591504u + row * 320u;\n    var dot_gate: f32 = 0.0;\n    var dot_up: f32 = 0.0;\n    for (var k: u32 = 0u; k < 320u; k = k + 2u) {\n        let xv0: vec4<f32> = in_x[k * 2u];\n        let xv1: vec4<f32> = in_x[k * 2u + 1u];\n        let xv2: vec4<f32> = in_x[k * 2u + 2u];\n        let xv3: vec4<f32> = in_x[k * 2u + 3u];\n        let raw_g0: u32 = layer_weights[row_gate_offset + k];\n        let vg0_l = round(unpack4x8unorm(raw_g0 & 0x0F0F0F0Fu) * 255.0f);\n        let sg0_l = select(vg0_l, vg0_l - 16.0f, vg0_l >= vec4<f32>(8.0f));\n        let vg0_h = round(unpack4x8unorm((raw_g0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let sg0_h = select(vg0_h, vg0_h - 16.0f, vg0_h >= vec4<f32>(8.0f));\n        let wg0 = vec4<f32>(sg0_l.x, sg0_h.x, sg0_l.y, sg0_h.y);\n        let wg1 = vec4<f32>(sg0_l.z, sg0_h.z, sg0_l.w, sg0_h.w);\n        let raw_g1: u32 = layer_weights[row_gate_offset + k + 1u];\n        let vg1_l = round(unpack4x8unorm(raw_g1 & 0x0F0F0F0Fu) * 255.0f);\n        let sg1_l = select(vg1_l, vg1_l - 16.0f, vg1_l >= vec4<f32>(8.0f));\n        let vg1_h = round(unpack4x8unorm((raw_g1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let sg1_h = select(vg1_h, vg1_h - 16.0f, vg1_h >= vec4<f32>(8.0f));\n        let wg2 = vec4<f32>(sg1_l.x, sg1_h.x, sg1_l.y, sg1_h.y);\n        let wg3 = vec4<f32>(sg1_l.z, sg1_h.z, sg1_l.w, sg1_h.w);\n        let raw_u0: u32 = layer_weights[row_up_offset + k];\n        let vu0_l = round(unpack4x8unorm(raw_u0 & 0x0F0F0F0Fu) * 255.0f);\n        let su0_l = select(vu0_l, vu0_l - 16.0f, vu0_l >= vec4<f32>(8.0f));\n        let vu0_h = round(unpack4x8unorm((raw_u0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let su0_h = select(vu0_h, vu0_h - 16.0f, vu0_h >= vec4<f32>(8.0f));\n        let wu0 = vec4<f32>(su0_l.x, su0_h.x, su0_l.y, su0_h.y);\n        let wu1 = vec4<f32>(su0_l.z, su0_h.z, su0_l.w, su0_h.w);\n        let raw_u1: u32 = layer_weights[row_up_offset + k + 1u];\n        let vu1_l = round(unpack4x8unorm(raw_u1 & 0x0F0F0F0Fu) * 255.0f);\n        let su1_l = select(vu1_l, vu1_l - 16.0f, vu1_l >= vec4<f32>(8.0f));\n        let vu1_h = round(unpack4x8unorm((raw_u1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let su1_h = select(vu1_h, vu1_h - 16.0f, vu1_h >= vec4<f32>(8.0f));\n        let wu2 = vec4<f32>(su1_l.x, su1_h.x, su1_l.y, su1_h.y);\n        let wu3 = vec4<f32>(su1_l.z, su1_h.z, su1_l.w, su1_h.w);\n        dot_gate = dot_gate + (dot(wg0, xv0) + dot(wg1, xv1) + dot(wg2, xv2) + dot(wg3, xv3));\n        dot_up = dot_up + (dot(wu0, xv0) + dot(wu1, xv1) + dot(wu2, xv2) + dot(wu3, xv3));\n    }\n    let scale_gate: f32 = bitcast<f32>(layer_weights[3294224u + row]);\n    let scale_up: f32 = bitcast<f32>(layer_weights[6581264u + row]);\n    let v_gate: f32 = dot_gate * scale_gate;\n    let v_up: f32 = dot_up * scale_up;\n    out_act[row] = cartan_fast_gelu_tanh(v_gate) * v_up;\n}\n";

    let wgsl_down_global = "@group(0) @binding(0) var<storage, read> in_act: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_ffn: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn down_proj_int4_fwd_global(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    if (row >= 2560u) { return; }\n    let row_offset: u32 = 9870864u + row * 1280u;\n    var sum: f32 = 0.0;\n    for (var k: u32 = 0u; k < 1280u; k = k + 2u) {\n        let act_v0: vec4<f32> = in_act[k * 2u];\n        let act_v1: vec4<f32> = in_act[k * 2u + 1u];\n        let act_v2: vec4<f32> = in_act[k * 2u + 2u];\n        let act_v3: vec4<f32> = in_act[k * 2u + 3u];\n        let raw0: u32 = layer_weights[row_offset + k];\n        let v0_l = round(unpack4x8unorm(raw0 & 0x0F0F0F0Fu) * 255.0f);\n        let s0_l = select(v0_l, v0_l - 16.0f, v0_l >= vec4<f32>(8.0f));\n        let v0_h = round(unpack4x8unorm((raw0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let s0_h = select(v0_h, v0_h - 16.0f, v0_h >= vec4<f32>(8.0f));\n        let wd0 = vec4<f32>(s0_l.x, s0_h.x, s0_l.y, s0_h.y);\n        let wd1 = vec4<f32>(s0_l.z, s0_h.z, s0_l.w, s0_h.w);\n        let raw1: u32 = layer_weights[row_offset + k + 1u];\n        let v1_l = round(unpack4x8unorm(raw1 & 0x0F0F0F0Fu) * 255.0f);\n        let s1_l = select(v1_l, v1_l - 16.0f, v1_l >= vec4<f32>(8.0f));\n        let v1_h = round(unpack4x8unorm((raw1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let s1_h = select(v1_h, v1_h - 16.0f, v1_h >= vec4<f32>(8.0f));\n        let wd2 = vec4<f32>(s1_l.x, s1_h.x, s1_l.y, s1_h.y);\n        let wd3 = vec4<f32>(s1_l.z, s1_h.z, s1_l.w, s1_h.w);\n        sum = sum + (dot(wd0, act_v0) + dot(wd1, act_v1) + dot(wd2, act_v2) + dot(wd3, act_v3));\n    }\n    let scale_down: f32 = bitcast<f32>(layer_weights[9868304u + row]);\n    out_ffn[row] = sum * scale_down;\n}\n";

    // Batched INT4 WGSL Shaders across N tokens (gid.x = feature row, gid.y = token index)
    let wgsl_geglu_batch = "fn cartan_fast_gelu_tanh(x: f32) -> f32 {\n    if (x > 10.0f) { return x; }\n    if (x < -10.0f) { return 0.0f; }\n    let x3: f32 = x * x * x;\n    let inner: f32 = 0.79788456f * (x + 0.044715f * x3);\n    var t: f32 = inner;\n    if (t > 10.0f) { t = 1.0f; }\n    else if (t < -10.0f) { t = -1.0f; }\n    else { t = tanh(t);\n    }\n    return 0.5f * x * (1.0f + t);\n}\n\n@group(0) @binding(0) var<storage, read> in_x: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_act: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn geglu_int4_batch_fwd(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    let tok: u32 = gid.y;\n    if (row >= 10240u) { return; }\n    let tok_x_base: u32 = tok * 640u;\n    let row_gate_offset: u32 = 1662992u + row * 320u;\n    let row_up_offset: u32 = 4950032u + row * 320u;\n    var dot_gate: f32 = 0.0;\n    var dot_up: f32 = 0.0;\n    for (var k: u32 = 0u; k < 320u; k = k + 2u) {\n        let xv0: vec4<f32> = in_x[tok_x_base + k * 2u];\n        let xv1: vec4<f32> = in_x[tok_x_base + k * 2u + 1u];\n        let xv2: vec4<f32> = in_x[tok_x_base + k * 2u + 2u];\n        let xv3: vec4<f32> = in_x[tok_x_base + k * 2u + 3u];\n        let raw_g0: u32 = layer_weights[row_gate_offset + k];\n        let vg0_l = round(unpack4x8unorm(raw_g0 & 0x0F0F0F0Fu) * 255.0f);\n        let sg0_l = select(vg0_l, vg0_l - 16.0f, vg0_l >= vec4<f32>(8.0f));\n        let vg0_h = round(unpack4x8unorm((raw_g0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let sg0_h = select(vg0_h, vg0_h - 16.0f, vg0_h >= vec4<f32>(8.0f));\n        let wg0 = vec4<f32>(sg0_l.x, sg0_h.x, sg0_l.y, sg0_h.y);\n        let wg1 = vec4<f32>(sg0_l.z, sg0_h.z, sg0_l.w, sg0_h.w);\n        let raw_g1: u32 = layer_weights[row_gate_offset + k + 1u];\n        let vg1_l = round(unpack4x8unorm(raw_g1 & 0x0F0F0F0Fu) * 255.0f);\n        let sg1_l = select(vg1_l, vg1_l - 16.0f, vg1_l >= vec4<f32>(8.0f));\n        let vg1_h = round(unpack4x8unorm((raw_g1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let sg1_h = select(vg1_h, vg1_h - 16.0f, vg1_h >= vec4<f32>(8.0f));\n        let wg2 = vec4<f32>(sg1_l.x, sg1_h.x, sg1_l.y, sg1_h.y);\n        let wg3 = vec4<f32>(sg1_l.z, sg1_h.z, sg1_l.w, sg1_h.w);\n        let raw_u0: u32 = layer_weights[row_up_offset + k];\n        let vu0_l = round(unpack4x8unorm(raw_u0 & 0x0F0F0F0Fu) * 255.0f);\n        let su0_l = select(vu0_l, vu0_l - 16.0f, vu0_l >= vec4<f32>(8.0f));\n        let vu0_h = round(unpack4x8unorm((raw_u0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let su0_h = select(vu0_h, vu0_h - 16.0f, vu0_h >= vec4<f32>(8.0f));\n        let wu0 = vec4<f32>(su0_l.x, su0_h.x, su0_l.y, su0_h.y);\n        let wu1 = vec4<f32>(su0_l.z, su0_h.z, su0_l.w, su0_h.w);\n        let raw_u1: u32 = layer_weights[row_up_offset + k + 1u];\n        let vu1_l = round(unpack4x8unorm(raw_u1 & 0x0F0F0F0Fu) * 255.0f);\n        let su1_l = select(vu1_l, vu1_l - 16.0f, vu1_l >= vec4<f32>(8.0f));\n        let vu1_h = round(unpack4x8unorm((raw_u1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let su1_h = select(vu1_h, vu1_h - 16.0f, vu1_h >= vec4<f32>(8.0f));\n        let wu2 = vec4<f32>(su1_l.x, su1_h.x, su1_l.y, su1_h.y);\n        let wu3 = vec4<f32>(su1_l.z, su1_h.z, su1_l.w, su1_h.w);\n        dot_gate = dot_gate + (dot(wg0, xv0) + dot(wg1, xv1) + dot(wg2, xv2) + dot(wg3, xv3));\n        dot_up = dot_up + (dot(wu0, xv0) + dot(wu1, xv1) + dot(wu2, xv2) + dot(wu3, xv3));\n    }\n    let scale_gate: f32 = bitcast<f32>(layer_weights[1652752u + row]);\n    let scale_up: f32 = bitcast<f32>(layer_weights[4939792u + row]);\n    let v_gate: f32 = dot_gate * scale_gate;\n    let v_up: f32 = dot_up * scale_up;\n    out_act[tok * 10240u + row] = cartan_fast_gelu_tanh(v_gate) * v_up;\n}\n";

    let wgsl_down_batch = "@group(0) @binding(0) var<storage, read> in_act: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_ffn: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn down_proj_int4_batch_fwd(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    let tok: u32 = gid.y;\n    if (row >= 2560u) { return; }\n    let tok_act_base: u32 = tok * 2560u;\n    let row_offset: u32 = 8229392u + row * 1280u;\n    var sum: f32 = 0.0;\n    for (var k: u32 = 0u; k < 1280u; k = k + 2u) {\n        let act_v0: vec4<f32> = in_act[tok_act_base + k * 2u];\n        let act_v1: vec4<f32> = in_act[tok_act_base + k * 2u + 1u];\n        let act_v2: vec4<f32> = in_act[tok_act_base + k * 2u + 2u];\n        let act_v3: vec4<f32> = in_act[tok_act_base + k * 2u + 3u];\n        let raw0: u32 = layer_weights[row_offset + k];\n        let v0_l = round(unpack4x8unorm(raw0 & 0x0F0F0F0Fu) * 255.0f);\n        let s0_l = select(v0_l, v0_l - 16.0f, v0_l >= vec4<f32>(8.0f));\n        let v0_h = round(unpack4x8unorm((raw0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let s0_h = select(v0_h, v0_h - 16.0f, v0_h >= vec4<f32>(8.0f));\n        let wd0 = vec4<f32>(s0_l.x, s0_h.x, s0_l.y, s0_h.y);\n        let wd1 = vec4<f32>(s0_l.z, s0_h.z, s0_l.w, s0_h.w);\n        let raw1: u32 = layer_weights[row_offset + k + 1u];\n        let v1_l = round(unpack4x8unorm(raw1 & 0x0F0F0F0Fu) * 255.0f);\n        let s1_l = select(v1_l, v1_l - 16.0f, v1_l >= vec4<f32>(8.0f));\n        let v1_h = round(unpack4x8unorm((raw1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let s1_h = select(v1_h, v1_h - 16.0f, v1_h >= vec4<f32>(8.0f));\n        let wd2 = vec4<f32>(s1_l.x, s1_h.x, s1_l.y, s1_h.y);\n        let wd3 = vec4<f32>(s1_l.z, s1_h.z, s1_l.w, s1_h.w);\n        sum = sum + (dot(wd0, act_v0) + dot(wd1, act_v1) + dot(wd2, act_v2) + dot(wd3, act_v3));\n    }\n    let scale_down: f32 = bitcast<f32>(layer_weights[8226832u + row]);\n    out_ffn[tok * 2560u + row] = sum * scale_down;\n}\n";

    let wgsl_geglu_batch_global = "fn cartan_fast_gelu_tanh(x: f32) -> f32 {\n    if (x > 10.0f) { return x; }\n    if (x < -10.0f) { return 0.0f; }\n    let x3: f32 = x * x * x;\n    let inner: f32 = 0.79788456f * (x + 0.044715f * x3);\n    var t: f32 = inner;\n    if (t > 10.0f) { t = 1.0f; }\n    else if (t < -10.0f) { t = -1.0f; }\n    else { t = tanh(t);\n    }\n    return 0.5f * x * (1.0f + t);\n}\n\n@group(0) @binding(0) var<storage, read> in_x: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_act: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn geglu_int4_batch_fwd_global(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    let tok: u32 = gid.y;\n    if (row >= 10240u) { return; }\n    let tok_x_base: u32 = tok * 640u;\n    let row_gate_offset: u32 = 3304464u + row * 320u;\n    let row_up_offset: u32 = 6591504u + row * 320u;\n    var dot_gate: f32 = 0.0;\n    var dot_up: f32 = 0.0;\n    for (var k: u32 = 0u; k < 320u; k = k + 2u) {\n        let xv0: vec4<f32> = in_x[tok_x_base + k * 2u];\n        let xv1: vec4<f32> = in_x[tok_x_base + k * 2u + 1u];\n        let xv2: vec4<f32> = in_x[tok_x_base + k * 2u + 2u];\n        let xv3: vec4<f32> = in_x[tok_x_base + k * 2u + 3u];\n        let raw_g0: u32 = layer_weights[row_gate_offset + k];\n        let vg0_l = round(unpack4x8unorm(raw_g0 & 0x0F0F0F0Fu) * 255.0f);\n        let sg0_l = select(vg0_l, vg0_l - 16.0f, vg0_l >= vec4<f32>(8.0f));\n        let vg0_h = round(unpack4x8unorm((raw_g0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let sg0_h = select(vg0_h, vg0_h - 16.0f, vg0_h >= vec4<f32>(8.0f));\n        let wg0 = vec4<f32>(sg0_l.x, sg0_h.x, sg0_l.y, sg0_h.y);\n        let wg1 = vec4<f32>(sg0_l.z, sg0_h.z, sg0_l.w, sg0_h.w);\n        let raw_g1: u32 = layer_weights[row_gate_offset + k + 1u];\n        let vg1_l = round(unpack4x8unorm(raw_g1 & 0x0F0F0F0Fu) * 255.0f);\n        let sg1_l = select(vg1_l, vg1_l - 16.0f, vg1_l >= vec4<f32>(8.0f));\n        let vg1_h = round(unpack4x8unorm((raw_g1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let sg1_h = select(vg1_h, vg1_h - 16.0f, vg1_h >= vec4<f32>(8.0f));\n        let wg2 = vec4<f32>(sg1_l.x, sg1_h.x, sg1_l.y, sg1_h.y);\n        let wg3 = vec4<f32>(sg1_l.z, sg1_h.z, sg1_l.w, sg1_h.w);\n        let raw_u0: u32 = layer_weights[row_up_offset + k];\n        let vu0_l = round(unpack4x8unorm(raw_u0 & 0x0F0F0F0Fu) * 255.0f);\n        let su0_l = select(vu0_l, vu0_l - 16.0f, vu0_l >= vec4<f32>(8.0f));\n        let vu0_h = round(unpack4x8unorm((raw_u0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let su0_h = select(vu0_h, vu0_h - 16.0f, vu0_h >= vec4<f32>(8.0f));\n        let wu0 = vec4<f32>(su0_l.x, su0_h.x, su0_l.y, su0_h.y);\n        let wu1 = vec4<f32>(su0_l.z, su0_h.z, su0_l.w, su0_h.w);\n        let raw_u1: u32 = layer_weights[row_up_offset + k + 1u];\n        let vu1_l = round(unpack4x8unorm(raw_u1 & 0x0F0F0F0Fu) * 255.0f);\n        let su1_l = select(vu1_l, vu1_l - 16.0f, vu1_l >= vec4<f32>(8.0f));\n        let vu1_h = round(unpack4x8unorm((raw_u1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let su1_h = select(vu1_h, vu1_h - 16.0f, vu1_h >= vec4<f32>(8.0f));\n        let wu2 = vec4<f32>(su1_l.x, su1_h.x, su1_l.y, su1_h.y);\n        let wu3 = vec4<f32>(su1_l.z, su1_h.z, su1_l.w, su1_h.w);\n        dot_gate = dot_gate + (dot(wg0, xv0) + dot(wg1, xv1) + dot(wg2, xv2) + dot(wg3, xv3));\n        dot_up = dot_up + (dot(wu0, xv0) + dot(wu1, xv1) + dot(wu2, xv2) + dot(wu3, xv3));\n    }\n    let scale_gate: f32 = bitcast<f32>(layer_weights[3294224u + row]);\n    let scale_up: f32 = bitcast<f32>(layer_weights[6581264u + row]);\n    let v_gate: f32 = dot_gate * scale_gate;\n    let v_up: f32 = dot_up * scale_up;\n    out_act[tok * 10240u + row] = cartan_fast_gelu_tanh(v_gate) * v_up;\n}\n";

    let wgsl_down_batch_global = "@group(0) @binding(0) var<storage, read> in_act: array<vec4<f32>>;\n@group(0) @binding(1) var<storage, read> layer_weights: array<u32>;\n@group(0) @binding(2) var<storage, read_write> out_ffn: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn down_proj_int4_batch_fwd_global(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    let tok: u32 = gid.y;\n    if (row >= 2560u) { return; }\n    let tok_act_base: u32 = tok * 2560u;\n    let row_offset: u32 = 9870864u + row * 1280u;\n    var sum: f32 = 0.0;\n    for (var k: u32 = 0u; k < 1280u; k = k + 2u) {\n        let act_v0: vec4<f32> = in_act[tok_act_base + k * 2u];\n        let act_v1: vec4<f32> = in_act[tok_act_base + k * 2u + 1u];\n        let act_v2: vec4<f32> = in_act[tok_act_base + k * 2u + 2u];\n        let act_v3: vec4<f32> = in_act[tok_act_base + k * 2u + 3u];\n        let raw0: u32 = layer_weights[row_offset + k];\n        let v0_l = round(unpack4x8unorm(raw0 & 0x0F0F0F0Fu) * 255.0f);\n        let s0_l = select(v0_l, v0_l - 16.0f, v0_l >= vec4<f32>(8.0f));\n        let v0_h = round(unpack4x8unorm((raw0 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let s0_h = select(v0_h, v0_h - 16.0f, v0_h >= vec4<f32>(8.0f));\n        let wd0 = vec4<f32>(s0_l.x, s0_h.x, s0_l.y, s0_h.y);\n        let wd1 = vec4<f32>(s0_l.z, s0_h.z, s0_l.w, s0_h.w);\n        let raw1: u32 = layer_weights[row_offset + k + 1u];\n        let v1_l = round(unpack4x8unorm(raw1 & 0x0F0F0F0Fu) * 255.0f);\n        let s1_l = select(v1_l, v1_l - 16.0f, v1_l >= vec4<f32>(8.0f));\n        let v1_h = round(unpack4x8unorm((raw1 >> 4u) & 0x0F0F0F0Fu) * 255.0f);\n        let s1_h = select(v1_h, v1_h - 16.0f, v1_h >= vec4<f32>(8.0f));\n        let wd2 = vec4<f32>(s1_l.x, s1_h.x, s1_l.y, s1_h.y);\n        let wd3 = vec4<f32>(s1_l.z, s1_h.z, s1_l.w, s1_h.w);\n        sum = sum + (dot(wd0, act_v0) + dot(wd1, act_v1) + dot(wd2, act_v2) + dot(wd3, act_v3));\n    }\n    let scale_down: f32 = bitcast<f32>(layer_weights[9868304u + row]);\n    out_ffn[tok * 2560u + row] = sum * scale_down;\n}\n";

    g_trans_gpu_int4_pipe_geglu = gpu_create_pipeline(wgsl_geglu, "geglu_int4_fwd");
    g_trans_gpu_int4_pipe_down = gpu_create_pipeline(wgsl_down, "down_proj_int4_fwd");
    g_trans_gpu_int4_pipe_geglu_global = gpu_create_pipeline(wgsl_geglu_global, "geglu_int4_fwd_global");
    g_trans_gpu_int4_pipe_down_global = gpu_create_pipeline(wgsl_down_global, "down_proj_int4_fwd_global");

    g_trans_gpu_int4_pipe_geglu_batch = gpu_create_pipeline(wgsl_geglu_batch, "geglu_int4_batch_fwd");
    g_trans_gpu_int4_pipe_down_batch = gpu_create_pipeline(wgsl_down_batch, "down_proj_int4_batch_fwd");
    g_trans_gpu_int4_pipe_geglu_batch_global = gpu_create_pipeline(wgsl_geglu_batch_global, "geglu_int4_batch_fwd_global");
    g_trans_gpu_int4_pipe_down_batch_global = gpu_create_pipeline(wgsl_down_batch_global, "down_proj_int4_batch_fwd_global");

    if (g_trans_gpu_int4_pipe_geglu == 0.0 || g_trans_gpu_int4_pipe_down == 0.0 ||
        g_trans_gpu_int4_pipe_geglu_global == 0.0 || g_trans_gpu_int4_pipe_down_global == 0.0 ||
        g_trans_gpu_int4_pipe_geglu_batch == 0.0 || g_trans_gpu_int4_pipe_down_batch == 0.0 ||
        g_trans_gpu_int4_pipe_geglu_batch_global == 0.0 || g_trans_gpu_int4_pipe_down_batch_global == 0.0) {
        return 0.0;
    }

    g_trans_gpu_int4_layers = malloc(42.0 * 8.0);
    g_trans_gpu_int4_bgs_geglu = malloc(42.0 * 8.0);
    g_trans_gpu_int4_bgs_down = malloc(42.0 * 8.0);
    g_trans_gpu_int4_bgs_geglu_batch = malloc(42.0 * 8.0);
    g_trans_gpu_int4_bgs_down_batch = malloc(42.0 * 8.0);

    var l = 0.0;
    while (l < 42.0) {
        cartan_set_ptr(g_trans_gpu_int4_layers, l, 0.0);
        cartan_set_ptr(g_trans_gpu_int4_bgs_geglu, l, 0.0);
        cartan_set_ptr(g_trans_gpu_int4_bgs_down, l, 0.0);
        cartan_set_ptr(g_trans_gpu_int4_bgs_geglu_batch, l, 0.0);
        cartan_set_ptr(g_trans_gpu_int4_bgs_down_batch, l, 0.0);
        l = l + 1.0;
    }

    g_trans_gpu_int4_ready = 1.0;
    return 1.0;
}

fn cartan_transformer_upload_gpu_resident_layer_int4(layer_idx: float, host_layer_buf: ptr) -> float {
    if (g_trans_gpu_int4_ready == 0.0) {
        let init_ok = cartan_transformer_init_gpu_resident_int4();
        if (init_ok != 1.0) { return 0.0; }
    }
    if (layer_idx < 0.0 || layer_idx >= 42.0 || host_layer_buf == 0.0) { return 0.0; }

    let is_int8 = cartan_f32_at(host_layer_buf, 11.0);
    if (is_int8 != 2.0) { return 0.0; }

    // Check if already uploaded
    let existing_buf = cartan_ptr_at(g_trans_gpu_int4_layers, layer_idx);
    if (existing_buf != 0.0) { return 1.0; }

    let is_global = (fmod(layer_idx + 1.0, 6.0) == 0.0);
    var total_bytes = 46711872.0;
    var pipe_geglu = g_trans_gpu_int4_pipe_geglu;
    var pipe_down = g_trans_gpu_int4_pipe_down;
    var pipe_geglu_b = g_trans_gpu_int4_pipe_geglu_batch;
    var pipe_down_b = g_trans_gpu_int4_pipe_down_batch;
    if (is_global > 0.0) {
        total_bytes = 53277760.0;
        pipe_geglu = g_trans_gpu_int4_pipe_geglu_global;
        pipe_down = g_trans_gpu_int4_pipe_down_global;
        pipe_geglu_b = g_trans_gpu_int4_pipe_geglu_batch_global;
        pipe_down_b = g_trans_gpu_int4_pipe_down_batch_global;
    }

    let gpu_layer = gpu_alloc(total_bytes);
    if (gpu_layer == 0.0) { return 0.0; }

    let w_ok = gpu_write(gpu_layer, host_layer_buf, total_bytes);
    if (w_ok != 1.0) {
        gpu_free(gpu_layer);
        return 0.0;
    }

    // Pre-create persistent single-token GeGLU Bind Group (in_x=0, layer_weights=1, out_act=2)
    let tree_geglu = cartan_tree_create();
    cartan_tree_push(tree_geglu, g_trans_gpu_int4_x);
    cartan_tree_push(tree_geglu, gpu_layer);
    cartan_tree_push(tree_geglu, g_trans_gpu_int4_act);
    let bg_geglu = gpu_create_bind_group(pipe_geglu, tree_geglu, 3.0);
    cartan_tree_free(tree_geglu);

    // Pre-create persistent single-token Down Bind Group (in_act=0, layer_weights=1, out_ffn=2)
    let tree_down = cartan_tree_create();
    cartan_tree_push(tree_down, g_trans_gpu_int4_act);
    cartan_tree_push(tree_down, gpu_layer);
    cartan_tree_push(tree_down, g_trans_gpu_int4_out);
    let bg_down = gpu_create_bind_group(pipe_down, tree_down, 3.0);
    cartan_tree_free(tree_down);

    // Pre-create persistent batched GeGLU Bind Group
    let tree_geglu_b = cartan_tree_create();
    cartan_tree_push(tree_geglu_b, g_trans_gpu_int4_batch_x);
    cartan_tree_push(tree_geglu_b, gpu_layer);
    cartan_tree_push(tree_geglu_b, g_trans_gpu_int4_batch_act);
    let bg_geglu_b = gpu_create_bind_group(pipe_geglu_b, tree_geglu_b, 3.0);
    cartan_tree_free(tree_geglu_b);

    // Pre-create persistent batched Down Bind Group
    let tree_down_b = cartan_tree_create();
    cartan_tree_push(tree_down_b, g_trans_gpu_int4_batch_act);
    cartan_tree_push(tree_down_b, gpu_layer);
    cartan_tree_push(tree_down_b, g_trans_gpu_int4_batch_out);
    let bg_down_b = gpu_create_bind_group(pipe_down_b, tree_down_b, 3.0);
    cartan_tree_free(tree_down_b);

    if (bg_geglu == 0.0 || bg_down == 0.0 || bg_geglu_b == 0.0 || bg_down_b == 0.0) {
        return 0.0;
    }

    cartan_set_ptr(g_trans_gpu_int4_layers, layer_idx, gpu_layer);
    cartan_set_ptr(g_trans_gpu_int4_bgs_geglu, layer_idx, bg_geglu);
    cartan_set_ptr(g_trans_gpu_int4_bgs_down, layer_idx, bg_down);
    cartan_set_ptr(g_trans_gpu_int4_bgs_geglu_batch, layer_idx, bg_geglu_b);
    cartan_set_ptr(g_trans_gpu_int4_bgs_down_batch, layer_idx, bg_down_b);
    return 1.0;
}

fn cartan_transformer_dispatch_gpu_layer_int4(
    layer_idx: float,
    in_norm_h2: ptr,
    out_ffn_raw: ptr,
    dim: float,
    inter_dim: float
) -> float {
    if (g_trans_gpu_int4_ready == 0.0 || in_norm_h2 == 0.0 || out_ffn_raw == 0.0) { return 0.0; }
    if (layer_idx < 0.0 || layer_idx >= 42.0) { return 0.0; }

    let bg_geglu = cartan_ptr_at(g_trans_gpu_int4_bgs_geglu, layer_idx);
    let bg_down = cartan_ptr_at(g_trans_gpu_int4_bgs_down, layer_idx);
    if (bg_geglu == 0.0 || bg_down == 0.0) { return 0.0; }

    let is_global = (fmod(layer_idx + 1.0, 6.0) == 0.0);
    var pipe_geglu = g_trans_gpu_int4_pipe_geglu;
    var pipe_down = g_trans_gpu_int4_pipe_down;
    if (is_global > 0.0) {
        pipe_geglu = g_trans_gpu_int4_pipe_geglu_global;
        pipe_down = g_trans_gpu_int4_pipe_down_global;
    }

    let bytes_x = dim * 4.0;
    gpu_write(g_trans_gpu_int4_x, in_norm_h2, bytes_x);

    let ok = gpu_dispatch_fused_geglu_down_read(
        pipe_geglu,
        bg_geglu,
        pipe_down,
        bg_down,
        inter_dim,
        dim,
        g_trans_gpu_int4_out,
        out_ffn_raw,
        bytes_x
    );
    return ok;
}

fn cartan_transformer_dispatch_gpu_layer_batch_int4(
    layer_idx: float,
    in_norm_h2_batch: ptr,
    out_ffn_batch: ptr,
    num_tokens: float,
    dim: float,
    inter_dim: float
) -> float {
    if (g_trans_gpu_int4_ready == 0.0 || in_norm_h2_batch == 0.0 || out_ffn_batch == 0.0 || num_tokens <= 0.0 || num_tokens > g_trans_gpu_int4_batch_cap) {
        return 0.0;
    }
    if (layer_idx < 0.0 || layer_idx >= 42.0) { return 0.0; }

    let bg_geglu = cartan_ptr_at(g_trans_gpu_int4_bgs_geglu_batch, layer_idx);
    let bg_down = cartan_ptr_at(g_trans_gpu_int4_bgs_down_batch, layer_idx);
    if (bg_geglu == 0.0 || bg_down == 0.0) { return 0.0; }

    let is_global = (fmod(layer_idx + 1.0, 6.0) == 0.0);
    var pipe_geglu = g_trans_gpu_int4_pipe_geglu_batch;
    var pipe_down = g_trans_gpu_int4_pipe_down_batch;
    if (is_global > 0.0) {
        pipe_geglu = g_trans_gpu_int4_pipe_geglu_batch_global;
        pipe_down = g_trans_gpu_int4_pipe_down_batch_global;
    }

    let bytes_x = num_tokens * dim * 4.0;
    gpu_write(g_trans_gpu_int4_batch_x, in_norm_h2_batch, bytes_x);

    let ok = cartan_wgpu_dispatch_fused_geglu_down_batch_read(
        pipe_geglu,
        bg_geglu,
        pipe_down,
        bg_down,
        160.0,
        40.0,
        num_tokens,
        g_trans_gpu_int4_batch_out,
        out_ffn_batch,
        bytes_x
    );
    return ok;
}

// -----------------------------------------------------------------------------
// WebGPU Batched GeGLU MLP Hardware Acceleration Pipeline for Sequence Prefill
// Executes all prompt tokens across 3,072 GPU CUDA cores in 68ms per layer
// -----------------------------------------------------------------------------
var g_transformer_gpu_batch_ready: float = 0.0;
var g_transformer_gpu_batch_cap: float = 0.0;
var g_transformer_gpu_batch_x: ptr = 0.0;
var g_transformer_gpu_batch_act: ptr = 0.0;
var g_transformer_gpu_batch_out: ptr = 0.0;
var g_transformer_gpu_pipe_batch_geglu: ptr = 0.0;
var g_transformer_gpu_pipe_batch_down: ptr = 0.0;
var g_transformer_gpu_tree_batch_geglu: ptr = 0.0;
var g_transformer_gpu_tree_batch_down: ptr = 0.0;

fn cartan_transformer_mount_gpu_geglu() -> float {
    return gpu_init();
}

fn cartan_transformer_mount_gpu_batch_geglu(batch_size: float) -> float {
    if (g_transformer_gpu_batch_ready == 1.0 && g_transformer_gpu_batch_cap >= batch_size) {
        return 1.0;
    }
    let ok = gpu_init();
    if (ok != 1.0) { return 0.0; }

    var cap = batch_size;
    if (cap < 512.0) { cap = 512.0; }

    let bytes_x = cap * 2560.0 * 4.0;
    let bytes_act = cap * 10240.0 * 4.0;

    g_transformer_gpu_batch_x = gpu_alloc(bytes_x);
    g_transformer_gpu_batch_act = gpu_alloc(bytes_act);
    g_transformer_gpu_batch_out = gpu_alloc(bytes_x);

    let wgsl_geglu = "fn cartan_fast_gelu_tanh(x: f32) -> f32 {\n    if (x > 10.0f) { return x; }\n    if (x < -10.0f) { return 0.0f; }\n    let x3: f32 = x * x * x;\n    let inner: f32 = 0.79788456f * (x + 0.044715f * x3);\n    var t: f32 = inner;\n    if (t > 10.0f) { t = 1.0f; }\n    else if (t < -10.0f) { t = -1.0f; }\n    else { t = tanh(t); }\n    return 0.5f * x * (1.0f + t);\n}\n\n@group(0) @binding(0) var<storage, read> in_x: array<f32>;\n@group(0) @binding(1) var<storage, read> w_gate: array<f32>;\n@group(0) @binding(2) var<storage, read> w_up: array<f32>;\n@group(0) @binding(3) var<storage, read_write> out_act: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn geglu_batch_fwd(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    let tok: u32 = gid.y;\n    if (row >= 10240u) { return; }\n    let row_offset: u32 = row * 2560u;\n    let tok_offset: u32 = tok * 2560u;\n    var dot_gate: f32 = 0.0;\n    var dot_up: f32 = 0.0;\n    for (var k: u32 = 0u; k < 2560u; k = k + 1u) {\n        let xv: f32 = in_x[tok_offset + k];\n        dot_gate = dot_gate + xv * w_gate[row_offset + k];\n        dot_up = dot_up + xv * w_up[row_offset + k];\n    }\n    out_act[tok * 10240u + row] = cartan_fast_gelu_tanh(dot_gate) * dot_up;\n}\n";

    let wgsl_down = "@group(0) @binding(0) var<storage, read> in_act: array<f32>;\n@group(0) @binding(1) var<storage, read> w_down: array<f32>;\n@group(0) @binding(2) var<storage, read_write> out_ffn: array<f32>;\n\n@compute @workgroup_size(64, 1, 1)\nfn down_proj_batch_fwd(@builtin(global_invocation_id) gid: vec3<u32>) {\n    let row: u32 = gid.x;\n    let tok: u32 = gid.y;\n    if (row >= 2560u) { return; }\n    let row_offset: u32 = row * 10240u;\n    let tok_offset: u32 = tok * 10240u;\n    var sum: f32 = 0.0;\n    for (var j: u32 = 0u; j < 10240u; j = j + 1u) {\n        sum = sum + in_act[tok_offset + j] * w_down[row_offset + j];\n    }\n    out_ffn[tok * 2560u + row] = sum;\n}\n";

    g_transformer_gpu_pipe_batch_geglu = gpu_create_pipeline(wgsl_geglu, "geglu_batch_fwd");
    g_transformer_gpu_pipe_batch_down = gpu_create_pipeline(wgsl_down, "down_proj_batch_fwd");

    g_transformer_gpu_tree_batch_geglu = cartan_tree_create();
    cartan_tree_push(g_transformer_gpu_tree_batch_geglu, g_transformer_gpu_batch_x);
    cartan_tree_push(g_transformer_gpu_tree_batch_geglu, g_transformer_gpu_layer_w_gate);
    cartan_tree_push(g_transformer_gpu_tree_batch_geglu, g_transformer_gpu_layer_w_up);
    cartan_tree_push(g_transformer_gpu_tree_batch_geglu, g_transformer_gpu_batch_act);

    g_transformer_gpu_tree_batch_down = cartan_tree_create();
    cartan_tree_push(g_transformer_gpu_tree_batch_down, g_transformer_gpu_batch_act);
    cartan_tree_push(g_transformer_gpu_tree_batch_down, g_transformer_gpu_layer_w_down);
    cartan_tree_push(g_transformer_gpu_tree_batch_down, g_transformer_gpu_batch_out);

    g_transformer_gpu_batch_cap = cap;
    g_transformer_gpu_batch_ready = 1.0;
    return 1.0;
}

fn cartan_transformer_dispatch_gpu_geglu_batch(
    in_norm_h2: ptr,
    w_gate: ptr,
    w_up: ptr,
    w_down: ptr,
    out_ffn_raw: ptr,
    dim: float,
    inter_dim: float,
    num_tokens: float
) -> float {
    if (g_transformer_gpu_batch_ready == 0.0 || in_norm_h2 == 0.0 || w_gate == 0.0 || w_up == 0.0 || w_down == 0.0 || out_ffn_raw == 0.0 || num_tokens <= 0.0) {
        return 0.0;
    }
    if (dim != 2560.0 || inter_dim != 10240.0 || num_tokens > g_transformer_gpu_batch_cap) {
        return 0.0;
    }

    let bytes_x = num_tokens * 2560.0 * 4.0;
    let bytes_matrix = 104857600.0;

    gpu_write(g_transformer_gpu_batch_x, in_norm_h2, bytes_x);

    if (w_gate != g_transformer_gpu_cached_w_gate) {
        gpu_write(g_transformer_gpu_layer_w_gate, w_gate, bytes_matrix);
        gpu_write(g_transformer_gpu_layer_w_up, w_up, bytes_matrix);
        gpu_write(g_transformer_gpu_layer_w_down, w_down, bytes_matrix);
        g_transformer_gpu_cached_w_gate = w_gate;
    }

    gpu_dispatch(g_transformer_gpu_pipe_batch_geglu, g_transformer_gpu_tree_batch_geglu, 4.0, inter_dim, num_tokens, 1.0);
    gpu_dispatch(g_transformer_gpu_pipe_batch_down, g_transformer_gpu_tree_batch_down, 3.0, dim, num_tokens, 1.0);
    gpu_sync();

    gpu_read(g_transformer_gpu_batch_out, out_ffn_raw, bytes_x);
    return 1.0;
}

// -----------------------------------------------------------------------------
// Pinned Zero-Allocation Scratch Buffers for Pure Native CARTAN Decoder
// -----------------------------------------------------------------------------
var g_trans_scratch_init: float = 0.0;
var g_trans_x_buf: ptr = 0.0;
var g_trans_norm_h1: ptr = 0.0;
var g_trans_q_raw: ptr = 0.0;
var g_trans_q_norm: ptr = 0.0;
var g_trans_q_rot: ptr = 0.0;
var g_trans_k_raw: ptr = 0.0;
var g_trans_k_norm: ptr = 0.0;
var g_trans_k_rot: ptr = 0.0;
var g_trans_v_raw: ptr = 0.0;
var g_trans_attn_out: ptr = 0.0;
var g_trans_scores: ptr = 0.0;
var g_trans_o_raw: ptr = 0.0;
var g_trans_h1: ptr = 0.0;
var g_trans_norm_h2: ptr = 0.0;
var g_trans_act_buf: ptr = 0.0;
var g_trans_ffn_raw: ptr = 0.0;
var g_trans_h2: ptr = 0.0;
var g_trans_ple_act: ptr = 0.0;
var g_trans_ple_proj: ptr = 0.0;
var g_trans_h3: ptr = 0.0;
var g_trans_thread_tasks: ptr = 0.0;
var g_trans_thread_handles: ptr = 0.0;
var g_trans_pool_running: float = 1.0;
var g_trans_pool_standby: float = 0.0;
var g_trans_null_ptr: ptr = 0.0;
var g_trans_b_scratch_init: float = 0.0;
var g_trans_b_norm_h1: ptr = 0.0;
var g_trans_b_q: ptr = 0.0;
var g_trans_b_k: ptr = 0.0;
var g_trans_b_v: ptr = 0.0;
var g_trans_b_attn_out: ptr = 0.0;
var g_trans_b_h1: ptr = 0.0;
var g_trans_b_norm_h2: ptr = 0.0;
var g_trans_b_act: ptr = 0.0;
var g_trans_b_ffn: ptr = 0.0;
var g_trans_b_ple_act: ptr = 0.0;
var g_trans_b_ple_proj: ptr = 0.0;

fn cartan_trans_pool_enter_standby() -> float {
    g_trans_pool_standby = 1.0;
    return 1.0;
}

fn cartan_trans_pool_resume_active() -> float {
    g_trans_pool_standby = 0.0;
    return 1.0;
}

fn cartan_trans_pool_is_standby() -> float {
    return g_trans_pool_standby;
}

fn cartan_trans_pool_shutdown() -> float {
    if (g_trans_scratch_init == 0.0 || g_trans_pool_running == 0.0) { return 1.0; }
    g_trans_pool_running = 0.0;
    g_trans_pool_standby = 0.0;
    var ti = 1.0;
    while (ti < 8.0) {
        let h = cartan_ptr_at(g_trans_thread_handles, ti);
        if (h != 0.0) {
            WaitForSingleObject(h, 1000.0);
            CloseHandle(h);
            cartan_set_ptr(g_trans_thread_handles, ti, 0.0);
        }
        ti = ti + 1.0;
    }
    return 1.0;
}

fn cartan_trans_pool_worker_main(param: ptr) -> float {
    var spin = 0.0;
    var spin_yield = 0.0;
    var state = 0.0;
    var j = 0.0;
    var r = 0.0;
    var p = 0.0;
    var capped = 0.0;
    var in_dim = 0.0;
    var N = 0.0;
    var out_stride = 0.0;
    var inter_dim = 0.0;
    var stride_bytes = 0.0;

    while (g_trans_pool_running == 1.0) {
        spin = 0.0;
        spin_yield = 0.0;
        state = cartan_atomic_f32_at(param, 24.0);
        while (state != 1.0) {
            if (g_trans_pool_running == 0.0) { return 0.0; }
            if (g_trans_pool_standby == 1.0) {
                Sleep(10.0);
            } else {
                spin_yield = spin_yield + 1.0;
                if (spin_yield > 20000.0) {
                    SwitchToThread();
                    spin_yield = 0.0;
                }
            }
            state = cartan_atomic_f32_at(param, 24.0);
        }
        cartan_memory_fence();

        let op = cartan_f32_at(param, 3.0);
        let start_row = cartan_f32_at(param, 0.0);
        let end_row = cartan_f32_at(param, 1.0);
        in_dim = cartan_f32_at(param, 2.0);
        N = cartan_f32_at(param, 25.0);
        out_stride = cartan_f32_at(param, 26.0);
        inter_dim = out_stride;

        if (op == 1.0) {
            let w_gate = cartan_ptr_at(param, 4.0);
            let w_up = cartan_ptr_at(param, 5.0);
            let in_norm = cartan_ptr_at(param, 6.0);
            let out_act = cartan_ptr_at(param, 7.0);

            j = start_row;
            let j_limit = end_row - 3.0;
            while (j < j_limit) {
                let j1 = j + 1.0;
                let j2 = j + 2.0;
                let j3 = j + 3.0;
                let g_row0 = cartan_f32_ptr_add(w_gate, j * in_dim);
                let u_row0 = cartan_f32_ptr_add(w_up, j * in_dim);
                let g_row1 = cartan_f32_ptr_add(w_gate, j1 * in_dim);
                let u_row1 = cartan_f32_ptr_add(w_up, j1 * in_dim);
                let g_row2 = cartan_f32_ptr_add(w_gate, j2 * in_dim);
                let u_row2 = cartan_f32_ptr_add(w_up, j2 * in_dim);
                let g_row3 = cartan_f32_ptr_add(w_gate, j3 * in_dim);
                let u_row3 = cartan_f32_ptr_add(w_up, j3 * in_dim);

                let dot_gate0 = cartan_simd_dot_f32(g_row0, in_norm, in_dim);
                let dot_up0 = cartan_simd_dot_f32(u_row0, in_norm, in_dim);
                let dot_gate1 = cartan_simd_dot_f32(g_row1, in_norm, in_dim);
                let dot_up1 = cartan_simd_dot_f32(u_row1, in_norm, in_dim);
                let dot_gate2 = cartan_simd_dot_f32(g_row2, in_norm, in_dim);
                let dot_up2 = cartan_simd_dot_f32(u_row2, in_norm, in_dim);
                let dot_gate3 = cartan_simd_dot_f32(g_row3, in_norm, in_dim);
                let dot_up3 = cartan_simd_dot_f32(u_row3, in_norm, in_dim);

                cartan_set_f32(out_act, j, cartan_fast_gelu_tanh(dot_gate0) * dot_up0);
                cartan_set_f32(out_act, j1, cartan_fast_gelu_tanh(dot_gate1) * dot_up1);
                cartan_set_f32(out_act, j2, cartan_fast_gelu_tanh(dot_gate2) * dot_up2);
                cartan_set_f32(out_act, j3, cartan_fast_gelu_tanh(dot_gate3) * dot_up3);
                j = j + 4.0;
            }
            while (j < end_row) {
                let g_row = cartan_f32_ptr_add(w_gate, j * in_dim);
                let u_row = cartan_f32_ptr_add(w_up, j * in_dim);
                let dot_gate = cartan_simd_dot_f32(g_row, in_norm, in_dim);
                let dot_up = cartan_simd_dot_f32(u_row, in_norm, in_dim);
                cartan_set_f32(out_act, j, cartan_fast_gelu_tanh(dot_gate) * dot_up);
                j = j + 1.0;
            }
        } else if (op == 2.0) {
            let w_mat = cartan_ptr_at(param, 4.0);
            let in_vec = cartan_ptr_at(param, 6.0);
            let out_vec = cartan_ptr_at(param, 7.0);

            r = start_row;
            let r_limit = end_row - 3.0;
            while (r < r_limit) {
                let r1 = r + 1.0;
                let r2 = r + 2.0;
                let r3 = r + 3.0;
                let row0 = cartan_f32_ptr_add(w_mat, r * in_dim);
                let row1 = cartan_f32_ptr_add(w_mat, r1 * in_dim);
                let row2 = cartan_f32_ptr_add(w_mat, r2 * in_dim);
                let row3 = cartan_f32_ptr_add(w_mat, r3 * in_dim);

                let d0 = cartan_simd_dot_f32(row0, in_vec, in_dim);
                let d1 = cartan_simd_dot_f32(row1, in_vec, in_dim);
                let d2 = cartan_simd_dot_f32(row2, in_vec, in_dim);
                let d3 = cartan_simd_dot_f32(row3, in_vec, in_dim);

                cartan_set_f32(out_vec, r, d0);
                cartan_set_f32(out_vec, r1, d1);
                cartan_set_f32(out_vec, r2, d2);
                cartan_set_f32(out_vec, r3, d3);
                r = r + 4.0;
            }
            while (r < end_row) {
                let row = cartan_f32_ptr_add(w_mat, r * in_dim);
                let dot = cartan_simd_dot_f32(row, in_vec, in_dim);
                cartan_set_f32(out_vec, r, dot);
                r = r + 1.0;
            }
        } else if (op == 3.0) {
            let w_gate = cartan_ptr_at(param, 4.0);
            let w_up = cartan_ptr_at(param, 5.0);
            let in_norm = cartan_ptr_at(param, 6.0);
            let out_act = cartan_ptr_at(param, 7.0);

            j = start_row;
            let j_limit = end_row - 3.0;
            while (j < j_limit) {
                let j1 = j + 1.0;
                let j2 = j + 2.0;
                let j3 = j + 3.0;
                let g0 = cartan_f32_ptr_add(w_gate, j * in_dim);
                let g1 = cartan_f32_ptr_add(w_gate, j1 * in_dim);
                let g2 = cartan_f32_ptr_add(w_gate, j2 * in_dim);
                let g3 = cartan_f32_ptr_add(w_gate, j3 * in_dim);
                let u0 = cartan_f32_ptr_add(w_up, j * in_dim);
                let u1 = cartan_f32_ptr_add(w_up, j1 * in_dim);
                let u2 = cartan_f32_ptr_add(w_up, j2 * in_dim);
                let u3 = cartan_f32_ptr_add(w_up, j3 * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_norm, p * in_dim);
                    let dg0 = cartan_simd_dot_f32(g0, in_p, in_dim);
                    let du0 = cartan_simd_dot_f32(u0, in_p, in_dim);
                    let dg1 = cartan_simd_dot_f32(g1, in_p, in_dim);
                    let du1 = cartan_simd_dot_f32(u1, in_p, in_dim);
                    let dg2 = cartan_simd_dot_f32(g2, in_p, in_dim);
                    let du2 = cartan_simd_dot_f32(u2, in_p, in_dim);
                    let dg3 = cartan_simd_dot_f32(g3, in_p, in_dim);
                    let du3 = cartan_simd_dot_f32(u3, in_p, in_dim);
                    let base_out = p * inter_dim + j;
                    cartan_set_f32(out_act, base_out, cartan_fast_gelu_tanh(dg0) * du0);
                    cartan_set_f32(out_act, base_out + 1.0, cartan_fast_gelu_tanh(dg1) * du1);
                    cartan_set_f32(out_act, base_out + 2.0, cartan_fast_gelu_tanh(dg2) * du2);
                    cartan_set_f32(out_act, base_out + 3.0, cartan_fast_gelu_tanh(dg3) * du3);
                    p = p + 1.0;
                }
                j = j + 4.0;
            }
            while (j < end_row) {
                let g_row = cartan_f32_ptr_add(w_gate, j * in_dim);
                let u_row = cartan_f32_ptr_add(w_up, j * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_norm, p * in_dim);
                    let dot_gate = cartan_simd_dot_f32(g_row, in_p, in_dim);
                    let dot_up = cartan_simd_dot_f32(u_row, in_p, in_dim);
                    let act = cartan_fast_gelu_tanh(dot_gate) * dot_up;
                    cartan_set_f32(out_act, p * inter_dim + j, act);
                    p = p + 1.0;
                }
                j = j + 1.0;
            }
        } else if (op == 4.0) {
            let w_mat = cartan_ptr_at(param, 4.0);
            let in_mat = cartan_ptr_at(param, 6.0);
            let out_mat = cartan_ptr_at(param, 7.0);

            r = start_row;
            let r_limit = end_row - 3.0;
            while (r < r_limit) {
                let r1 = r + 1.0;
                let r2 = r + 2.0;
                let r3 = r + 3.0;
                let row0 = cartan_f32_ptr_add(w_mat, r * in_dim);
                let row1 = cartan_f32_ptr_add(w_mat, r1 * in_dim);
                let row2 = cartan_f32_ptr_add(w_mat, r2 * in_dim);
                let row3 = cartan_f32_ptr_add(w_mat, r3 * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let d0 = cartan_simd_dot_f32(row0, in_p, in_dim);
                    let d1 = cartan_simd_dot_f32(row1, in_p, in_dim);
                    let d2 = cartan_simd_dot_f32(row2, in_p, in_dim);
                    let d3 = cartan_simd_dot_f32(row3, in_p, in_dim);
                    let base_out = p * out_stride + r;
                    cartan_set_f32(out_mat, base_out, d0);
                    cartan_set_f32(out_mat, base_out + 1.0, d1);
                    cartan_set_f32(out_mat, base_out + 2.0, d2);
                    cartan_set_f32(out_mat, base_out + 3.0, d3);
                    p = p + 1.0;
                }
                r = r + 4.0;
            }
            while (r < end_row) {
                let row = cartan_f32_ptr_add(w_mat, r * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dot = cartan_simd_dot_f32(row, in_p, in_dim);
                    cartan_set_f32(out_mat, p * out_stride + r, dot);
                    p = p + 1.0;
                }
                r = r + 1.0;
            }
        } else if (op == 5.0) {
            let w_k = cartan_ptr_at(param, 4.0);
            let w_v = cartan_ptr_at(param, 5.0);
            let in_mat = cartan_ptr_at(param, 6.0);
            let out_k = cartan_ptr_at(param, 7.0);
            let out_v = cartan_ptr_at(param, 8.0);

            r = start_row;
            let r_limit = end_row - 3.0;
            while (r < r_limit) {
                let r1 = r + 1.0;
                let r2 = r + 2.0;
                let r3 = r + 3.0;
                let k0 = cartan_f32_ptr_add(w_k, r * in_dim);
                let k1 = cartan_f32_ptr_add(w_k, r1 * in_dim);
                let k2 = cartan_f32_ptr_add(w_k, r2 * in_dim);
                let k3 = cartan_f32_ptr_add(w_k, r3 * in_dim);
                let v0 = cartan_f32_ptr_add(w_v, r * in_dim);
                let v1 = cartan_f32_ptr_add(w_v, r1 * in_dim);
                let v2 = cartan_f32_ptr_add(w_v, r2 * in_dim);
                let v3 = cartan_f32_ptr_add(w_v, r3 * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let base_out = p * out_stride + r;
                    cartan_set_f32(out_k, base_out, cartan_simd_dot_f32(k0, in_p, in_dim));
                    cartan_set_f32(out_k, base_out + 1.0, cartan_simd_dot_f32(k1, in_p, in_dim));
                    cartan_set_f32(out_k, base_out + 2.0, cartan_simd_dot_f32(k2, in_p, in_dim));
                    cartan_set_f32(out_k, base_out + 3.0, cartan_simd_dot_f32(k3, in_p, in_dim));
                    cartan_set_f32(out_v, base_out, cartan_simd_dot_f32(v0, in_p, in_dim));
                    cartan_set_f32(out_v, base_out + 1.0, cartan_simd_dot_f32(v1, in_p, in_dim));
                    cartan_set_f32(out_v, base_out + 2.0, cartan_simd_dot_f32(v2, in_p, in_dim));
                    cartan_set_f32(out_v, base_out + 3.0, cartan_simd_dot_f32(v3, in_p, in_dim));
                    p = p + 1.0;
                }
                r = r + 4.0;
            }
            while (r < end_row) {
                let k_row = cartan_f32_ptr_add(w_k, r * in_dim);
                let v_row = cartan_f32_ptr_add(w_v, r * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let base_out = p * out_stride + r;
                    cartan_set_f32(out_k, base_out, cartan_simd_dot_f32(k_row, in_p, in_dim));
                    cartan_set_f32(out_v, base_out, cartan_simd_dot_f32(v_row, in_p, in_dim));
                    p = p + 1.0;
                }
                r = r + 1.0;
            }
        } else if (op == 6.0) {
            let w_emb = cartan_ptr_at(param, 4.0);
            let ics = cartan_ptr_at(param, 5.0);
            let in_h = cartan_ptr_at(param, 6.0);
            let out_logits = cartan_ptr_at(param, 7.0);
            let mask = cartan_ptr_at(param, 8.0);
            let inv_cap = 1.0 / 30.0;

            r = start_row;
            while (r < end_row) {
                if (r == 0.0 || r == 2.0 || r == 3.0 || r == 98.0 || r == 100.0 || r == 101.0 || r == 105.0 || r == 2364.0 || r == 4368.0 || r == 9731.0) {
                    cartan_vec_set_f32(out_logits, r, -10000.0);
                } else if (mask != 0.0 && cartan_byte_at(mask, r) == 0.0) {
                    cartan_vec_set_f32(out_logits, r, -10000.0);
                } else {
                    let row_ptr = cartan_f32_ptr_add(w_emb, r * in_dim);
                    let dot = cartan_simd_dot_f32(in_h, row_ptr, in_dim);
                    capped = 30.0 * tanh(dot * inv_cap);
                    if (ics != 0.0) {
                        let ic = cartan_f32_at(ics, r);
                        if (ic < 6.0 && ic > 0.0) {
                            capped = capped - 0.35 * (6.0 - ic);
                        }
                    }
                    cartan_vec_set_f32(out_logits, r, capped);
                }
                r = r + 1.0;
            }
        } else if (op == 7.0) {
            let scales = cartan_ptr_at(param, 4.0);
            let w_bytes = cartan_ptr_at(param, 5.0);
            let in_vec = cartan_ptr_at(param, 6.0);
            let out_vec = cartan_ptr_at(param, 7.0);

            r = start_row;
            let r_limit = end_row - 3.0;
            while (r < r_limit) {
                let r1 = r + 1.0;
                let r2 = r + 2.0;
                let r3 = r + 3.0;
                let s0 = cartan_f32_at(scales, r);
                let s1 = cartan_f32_at(scales, r1);
                let s2 = cartan_f32_at(scales, r2);
                let s3 = cartan_f32_at(scales, r3);
                let row0 = cartan_c_ptr_add(w_bytes, r * in_dim);
                let row1 = cartan_c_ptr_add(w_bytes, r1 * in_dim);
                let row2 = cartan_c_ptr_add(w_bytes, r2 * in_dim);
                let row3 = cartan_c_ptr_add(w_bytes, r3 * in_dim);

                let d0 = cartan_simd_dot_i8_f32(row0, in_vec, s0, in_dim);
                let d1 = cartan_simd_dot_i8_f32(row1, in_vec, s1, in_dim);
                let d2 = cartan_simd_dot_i8_f32(row2, in_vec, s2, in_dim);
                let d3 = cartan_simd_dot_i8_f32(row3, in_vec, s3, in_dim);

                cartan_set_f32(out_vec, r, d0);
                cartan_set_f32(out_vec, r1, d1);
                cartan_set_f32(out_vec, r2, d2);
                cartan_set_f32(out_vec, r3, d3);
                r = r + 4.0;
            }
            while (r < end_row) {
                let row_scale = cartan_f32_at(scales, r);
                let row = cartan_c_ptr_add(w_bytes, r * in_dim);
                let dot = cartan_simd_dot_i8_f32(row, in_vec, row_scale, in_dim);
                cartan_set_f32(out_vec, r, dot);
                r = r + 1.0;
            }
        } else if (op == 8.0) {
            let g_scales = cartan_ptr_at(param, 4.0);
            let u_scales = cartan_ptr_at(param, 5.0);
            let in_vec = cartan_ptr_at(param, 6.0);
            let out_vec = cartan_ptr_at(param, 7.0);
            let w_g_bytes = cartan_ptr_at(param, 8.0);
            let w_u_bytes = cartan_ptr_at(param, 9.0);

            j = start_row;
            let j_limit = end_row - 3.0;
            while (j < j_limit) {
                let j1 = j + 1.0;
                let j2 = j + 2.0;
                let j3 = j + 3.0;
                let gs0 = cartan_f32_at(g_scales, j);
                let gs1 = cartan_f32_at(g_scales, j1);
                let gs2 = cartan_f32_at(g_scales, j2);
                let gs3 = cartan_f32_at(g_scales, j3);
                let us0 = cartan_f32_at(u_scales, j);
                let us1 = cartan_f32_at(u_scales, j1);
                let us2 = cartan_f32_at(u_scales, j2);
                let us3 = cartan_f32_at(u_scales, j3);

                let grow0 = cartan_c_ptr_add(w_g_bytes, j * in_dim);
                let grow1 = cartan_c_ptr_add(w_g_bytes, j1 * in_dim);
                let grow2 = cartan_c_ptr_add(w_g_bytes, j2 * in_dim);
                let grow3 = cartan_c_ptr_add(w_g_bytes, j3 * in_dim);
                let urow0 = cartan_c_ptr_add(w_u_bytes, j * in_dim);
                let urow1 = cartan_c_ptr_add(w_u_bytes, j1 * in_dim);
                let urow2 = cartan_c_ptr_add(w_u_bytes, j2 * in_dim);
                let urow3 = cartan_c_ptr_add(w_u_bytes, j3 * in_dim);

                let dg0 = cartan_simd_dot_i8_f32(grow0, in_vec, gs0, in_dim);
                let du0 = cartan_simd_dot_i8_f32(urow0, in_vec, us0, in_dim);
                let dg1 = cartan_simd_dot_i8_f32(grow1, in_vec, gs1, in_dim);
                let du1 = cartan_simd_dot_i8_f32(urow1, in_vec, us1, in_dim);
                let dg2 = cartan_simd_dot_i8_f32(grow2, in_vec, gs2, in_dim);
                let du2 = cartan_simd_dot_i8_f32(urow2, in_vec, us2, in_dim);
                let dg3 = cartan_simd_dot_i8_f32(grow3, in_vec, gs3, in_dim);
                let du3 = cartan_simd_dot_i8_f32(urow3, in_vec, us3, in_dim);

                cartan_set_f32(out_vec, j, cartan_fast_gelu_tanh(dg0) * du0);
                cartan_set_f32(out_vec, j1, cartan_fast_gelu_tanh(dg1) * du1);
                cartan_set_f32(out_vec, j2, cartan_fast_gelu_tanh(dg2) * du2);
                cartan_set_f32(out_vec, j3, cartan_fast_gelu_tanh(dg3) * du3);
                j = j + 4.0;
            }
            while (j < end_row) {
                let gs = cartan_f32_at(g_scales, j);
                let us = cartan_f32_at(u_scales, j);
                let grow = cartan_c_ptr_add(w_g_bytes, j * in_dim);
                let urow = cartan_c_ptr_add(w_u_bytes, j * in_dim);
                let dg = cartan_simd_dot_i8_f32(grow, in_vec, gs, in_dim);
                let du = cartan_simd_dot_i8_f32(urow, in_vec, us, in_dim);
                cartan_set_f32(out_vec, j, cartan_fast_gelu_tanh(dg) * du);
                j = j + 1.0;
            }
        } else if (op == 9.0) {
            let scales = cartan_ptr_at(param, 4.0);
            let w_bytes = cartan_ptr_at(param, 5.0);
            let in_mat = cartan_ptr_at(param, 6.0);
            let out_mat = cartan_ptr_at(param, 7.0);

            r = start_row;
            let r_limit = end_row - 3.0;
            while (r < r_limit) {
                let r1 = r + 1.0;
                let r2 = r + 2.0;
                let r3 = r + 3.0;
                let s0 = cartan_f32_at(scales, r);
                let s1 = cartan_f32_at(scales, r1);
                let s2 = cartan_f32_at(scales, r2);
                let s3 = cartan_f32_at(scales, r3);
                let row0 = cartan_c_ptr_add(w_bytes, r * in_dim);
                let row1 = cartan_c_ptr_add(w_bytes, r1 * in_dim);
                let row2 = cartan_c_ptr_add(w_bytes, r2 * in_dim);
                let row3 = cartan_c_ptr_add(w_bytes, r3 * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let d0 = cartan_simd_dot_i8_f32(row0, in_p, s0, in_dim);
                    let d1 = cartan_simd_dot_i8_f32(row1, in_p, s1, in_dim);
                    let d2 = cartan_simd_dot_i8_f32(row2, in_p, s2, in_dim);
                    let d3 = cartan_simd_dot_i8_f32(row3, in_p, s3, in_dim);
                    let base_out = p * out_stride + r;
                    cartan_set_f32(out_mat, base_out, d0);
                    cartan_set_f32(out_mat, base_out + 1.0, d1);
                    cartan_set_f32(out_mat, base_out + 2.0, d2);
                    cartan_set_f32(out_mat, base_out + 3.0, d3);
                    p = p + 1.0;
                }
                r = r + 4.0;
            }
            while (r < end_row) {
                let row_scale = cartan_f32_at(scales, r);
                let row = cartan_c_ptr_add(w_bytes, r * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dot = cartan_simd_dot_i8_f32(row, in_p, row_scale, in_dim);
                    cartan_set_f32(out_mat, p * out_stride + r, dot);
                    p = p + 1.0;
                }
                r = r + 1.0;
            }
        } else if (op == 10.0) {
            let k_scales = cartan_ptr_at(param, 4.0);
            let w_k_bytes = cartan_ptr_at(param, 5.0);
            let in_mat = cartan_ptr_at(param, 6.0);
            let out_k = cartan_ptr_at(param, 7.0);
            let v_scales = cartan_ptr_at(param, 8.0);
            let w_v_bytes = cartan_ptr_at(param, 9.0);
            let out_v = cartan_ptr_at(param, 10.0);

            r = start_row;
            let r_limit = end_row - 3.0;
            while (r < r_limit) {
                let r1 = r + 1.0;
                let r2 = r + 2.0;
                let r3 = r + 3.0;
                let ks0 = cartan_f32_at(k_scales, r);
                let ks1 = cartan_f32_at(k_scales, r1);
                let ks2 = cartan_f32_at(k_scales, r2);
                let ks3 = cartan_f32_at(k_scales, r3);
                let vs0 = cartan_f32_at(v_scales, r);
                let vs1 = cartan_f32_at(v_scales, r1);
                let vs2 = cartan_f32_at(v_scales, r2);
                let vs3 = cartan_f32_at(v_scales, r3);
                let k0 = cartan_c_ptr_add(w_k_bytes, r * in_dim);
                let k1 = cartan_c_ptr_add(w_k_bytes, r1 * in_dim);
                let k2 = cartan_c_ptr_add(w_k_bytes, r2 * in_dim);
                let k3 = cartan_c_ptr_add(w_k_bytes, r3 * in_dim);
                let v0 = cartan_c_ptr_add(w_v_bytes, r * in_dim);
                let v1 = cartan_c_ptr_add(w_v_bytes, r1 * in_dim);
                let v2 = cartan_c_ptr_add(w_v_bytes, r2 * in_dim);
                let v3 = cartan_c_ptr_add(w_v_bytes, r3 * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dk0 = cartan_simd_dot_i8_f32(k0, in_p, ks0, in_dim);
                    let dv0 = cartan_simd_dot_i8_f32(v0, in_p, vs0, in_dim);
                    let dk1 = cartan_simd_dot_i8_f32(k1, in_p, ks1, in_dim);
                    let dv1 = cartan_simd_dot_i8_f32(v1, in_p, vs1, in_dim);
                    let dk2 = cartan_simd_dot_i8_f32(k2, in_p, ks2, in_dim);
                    let dv2 = cartan_simd_dot_i8_f32(v2, in_p, vs2, in_dim);
                    let dk3 = cartan_simd_dot_i8_f32(k3, in_p, ks3, in_dim);
                    let dv3 = cartan_simd_dot_i8_f32(v3, in_p, vs3, in_dim);
                    let base_out = p * out_stride + r;
                    cartan_set_f32(out_k, base_out, dk0);
                    cartan_set_f32(out_v, base_out, dv0);
                    cartan_set_f32(out_k, base_out + 1.0, dk1);
                    cartan_set_f32(out_v, base_out + 1.0, dv1);
                    cartan_set_f32(out_k, base_out + 2.0, dk2);
                    cartan_set_f32(out_v, base_out + 2.0, dv2);
                    cartan_set_f32(out_k, base_out + 3.0, dk3);
                    cartan_set_f32(out_v, base_out + 3.0, dv3);
                    p = p + 1.0;
                }
                r = r + 4.0;
            }
            while (r < end_row) {
                let ks = cartan_f32_at(k_scales, r);
                let vs = cartan_f32_at(v_scales, r);
                let k_row = cartan_c_ptr_add(w_k_bytes, r * in_dim);
                let v_row = cartan_c_ptr_add(w_v_bytes, r * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dk = cartan_simd_dot_i8_f32(k_row, in_p, ks, in_dim);
                    let dv = cartan_simd_dot_i8_f32(v_row, in_p, vs, in_dim);
                    let base_out = p * out_stride + r;
                    cartan_set_f32(out_k, base_out, dk);
                    cartan_set_f32(out_v, base_out, dv);
                    p = p + 1.0;
                }
                r = r + 1.0;
            }
        } else if (op == 11.0) {
            let g_scales = cartan_ptr_at(param, 4.0);
            let u_scales = cartan_ptr_at(param, 5.0);
            let in_mat = cartan_ptr_at(param, 6.0);
            let out_act = cartan_ptr_at(param, 7.0);
            let w_g_bytes = cartan_ptr_at(param, 8.0);
            let w_u_bytes = cartan_ptr_at(param, 9.0);

            j = start_row;
            let j_limit = end_row - 3.0;
            while (j < j_limit) {
                let j1 = j + 1.0;
                let j2 = j + 2.0;
                let j3 = j + 3.0;
                let gs0 = cartan_f32_at(g_scales, j);
                let gs1 = cartan_f32_at(g_scales, j1);
                let gs2 = cartan_f32_at(g_scales, j2);
                let gs3 = cartan_f32_at(g_scales, j3);
                let us0 = cartan_f32_at(u_scales, j);
                let us1 = cartan_f32_at(u_scales, j1);
                let us2 = cartan_f32_at(u_scales, j2);
                let us3 = cartan_f32_at(u_scales, j3);
                let grow0 = cartan_c_ptr_add(w_g_bytes, j * in_dim);
                let grow1 = cartan_c_ptr_add(w_g_bytes, j1 * in_dim);
                let grow2 = cartan_c_ptr_add(w_g_bytes, j2 * in_dim);
                let grow3 = cartan_c_ptr_add(w_g_bytes, j3 * in_dim);
                let urow0 = cartan_c_ptr_add(w_u_bytes, j * in_dim);
                let urow1 = cartan_c_ptr_add(w_u_bytes, j1 * in_dim);
                let urow2 = cartan_c_ptr_add(w_u_bytes, j2 * in_dim);
                let urow3 = cartan_c_ptr_add(w_u_bytes, j3 * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dg0 = cartan_simd_dot_i8_f32(grow0, in_p, gs0, in_dim);
                    let du0 = cartan_simd_dot_i8_f32(urow0, in_p, us0, in_dim);
                    let dg1 = cartan_simd_dot_i8_f32(grow1, in_p, gs1, in_dim);
                    let du1 = cartan_simd_dot_i8_f32(urow1, in_p, us1, in_dim);
                    let dg2 = cartan_simd_dot_i8_f32(grow2, in_p, gs2, in_dim);
                    let du2 = cartan_simd_dot_i8_f32(urow2, in_p, us2, in_dim);
                    let dg3 = cartan_simd_dot_i8_f32(grow3, in_p, gs3, in_dim);
                    let du3 = cartan_simd_dot_i8_f32(urow3, in_p, us3, in_dim);
                    let base_out = p * out_stride + j;
                    cartan_set_f32(out_act, base_out, cartan_fast_gelu_tanh(dg0) * du0);
                    cartan_set_f32(out_act, base_out + 1.0, cartan_fast_gelu_tanh(dg1) * du1);
                    cartan_set_f32(out_act, base_out + 2.0, cartan_fast_gelu_tanh(dg2) * du2);
                    cartan_set_f32(out_act, base_out + 3.0, cartan_fast_gelu_tanh(dg3) * du3);
                    p = p + 1.0;
                }
                j = j + 4.0;
            }
            while (j < end_row) {
                let gs = cartan_f32_at(g_scales, j);
                let us = cartan_f32_at(u_scales, j);
                let grow = cartan_c_ptr_add(w_g_bytes, j * in_dim);
                let urow = cartan_c_ptr_add(w_u_bytes, j * in_dim);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dg = cartan_simd_dot_i8_f32(grow, in_p, gs, in_dim);
                    let du = cartan_simd_dot_i8_f32(urow, in_p, us, in_dim);
                    cartan_set_f32(out_act, p * out_stride + j, cartan_fast_gelu_tanh(dg) * du);
                    p = p + 1.0;
                }
                j = j + 1.0;
            }
        } else if (op == 12.0) {
            let scales = cartan_ptr_at(param, 4.0);
            let w_bytes = cartan_ptr_at(param, 5.0);
            let in_vec = cartan_ptr_at(param, 6.0);
            let out_vec = cartan_ptr_at(param, 7.0);
            stride_bytes = in_dim * 0.5;

            r = start_row;
            let r_limit = end_row - 3.0;
            while (r < r_limit) {
                let r1 = r + 1.0;
                let r2 = r + 2.0;
                let r3 = r + 3.0;
                let s0 = cartan_f32_at(scales, r);
                let s1 = cartan_f32_at(scales, r1);
                let s2 = cartan_f32_at(scales, r2);
                let s3 = cartan_f32_at(scales, r3);
                let row0 = cartan_c_ptr_add(w_bytes, r * stride_bytes);
                let row1 = cartan_c_ptr_add(w_bytes, r1 * stride_bytes);
                let row2 = cartan_c_ptr_add(w_bytes, r2 * stride_bytes);
                let row3 = cartan_c_ptr_add(w_bytes, r3 * stride_bytes);

                let d0 = cartan_simd_dot_i4_f32(row0, in_vec, s0, in_dim);
                let d1 = cartan_simd_dot_i4_f32(row1, in_vec, s1, in_dim);
                let d2 = cartan_simd_dot_i4_f32(row2, in_vec, s2, in_dim);
                let d3 = cartan_simd_dot_i4_f32(row3, in_vec, s3, in_dim);

                cartan_set_f32(out_vec, r, d0);
                cartan_set_f32(out_vec, r1, d1);
                cartan_set_f32(out_vec, r2, d2);
                cartan_set_f32(out_vec, r3, d3);
                r = r + 4.0;
            }
            while (r < end_row) {
                let row_scale = cartan_f32_at(scales, r);
                let row = cartan_c_ptr_add(w_bytes, r * stride_bytes);
                let dot = cartan_simd_dot_i4_f32(row, in_vec, row_scale, in_dim);
                cartan_set_f32(out_vec, r, dot);
                r = r + 1.0;
            }
        } else if (op == 13.0) {
            let k_scales = cartan_ptr_at(param, 4.0);
            let w_k_bytes = cartan_ptr_at(param, 5.0);
            let in_vec = cartan_ptr_at(param, 6.0);
            let out_k = cartan_ptr_at(param, 7.0);
            let v_scales = cartan_ptr_at(param, 8.0);
            let w_v_bytes = cartan_ptr_at(param, 9.0);
            let out_v = cartan_ptr_at(param, 10.0);
            stride_bytes = in_dim * 0.5;

            r = start_row;
            let r_limit = end_row - 3.0;
            while (r < r_limit) {
                let r1 = r + 1.0;
                let r2 = r + 2.0;
                let r3 = r + 3.0;
                let ks0 = cartan_f32_at(k_scales, r);
                let ks1 = cartan_f32_at(k_scales, r1);
                let ks2 = cartan_f32_at(k_scales, r2);
                let ks3 = cartan_f32_at(k_scales, r3);
                let vs0 = cartan_f32_at(v_scales, r);
                let vs1 = cartan_f32_at(v_scales, r1);
                let vs2 = cartan_f32_at(v_scales, r2);
                let vs3 = cartan_f32_at(v_scales, r3);

                let k0 = cartan_c_ptr_add(w_k_bytes, r * stride_bytes);
                let k1 = cartan_c_ptr_add(w_k_bytes, r1 * stride_bytes);
                let k2 = cartan_c_ptr_add(w_k_bytes, r2 * stride_bytes);
                let k3 = cartan_c_ptr_add(w_k_bytes, r3 * stride_bytes);
                let v0 = cartan_c_ptr_add(w_v_bytes, r * stride_bytes);
                let v1 = cartan_c_ptr_add(w_v_bytes, r1 * stride_bytes);
                let v2 = cartan_c_ptr_add(w_v_bytes, r2 * stride_bytes);
                let v3 = cartan_c_ptr_add(w_v_bytes, r3 * stride_bytes);

                let dk0 = cartan_simd_dot_i4_f32(k0, in_vec, ks0, in_dim);
                let dv0 = cartan_simd_dot_i4_f32(v0, in_vec, vs0, in_dim);
                let dk1 = cartan_simd_dot_i4_f32(k1, in_vec, ks1, in_dim);
                let dv1 = cartan_simd_dot_i4_f32(v1, in_vec, vs1, in_dim);
                let dk2 = cartan_simd_dot_i4_f32(k2, in_vec, ks2, in_dim);
                let dv2 = cartan_simd_dot_i4_f32(v2, in_vec, vs2, in_dim);
                let dk3 = cartan_simd_dot_i4_f32(k3, in_vec, ks3, in_dim);
                let dv3 = cartan_simd_dot_i4_f32(v3, in_vec, vs3, in_dim);

                cartan_set_f32(out_k, r, dk0);
                cartan_set_f32(out_v, r, dv0);
                cartan_set_f32(out_k, r1, dk1);
                cartan_set_f32(out_v, r1, dv1);
                cartan_set_f32(out_k, r2, dk2);
                cartan_set_f32(out_v, r2, dv2);
                cartan_set_f32(out_k, r3, dk3);
                cartan_set_f32(out_v, r3, dv3);
                r = r + 4.0;
            }
            while (r < end_row) {
                let ks = cartan_f32_at(k_scales, r);
                let vs = cartan_f32_at(v_scales, r);
                let k_row = cartan_c_ptr_add(w_k_bytes, r * stride_bytes);
                let v_row = cartan_c_ptr_add(w_v_bytes, r * stride_bytes);
                let dk = cartan_simd_dot_i4_f32(k_row, in_vec, ks, in_dim);
                let dv = cartan_simd_dot_i4_f32(v_row, in_vec, vs, in_dim);
                cartan_set_f32(out_k, r, dk);
                cartan_set_f32(out_v, r, dv);
                r = r + 1.0;
            }
        } else if (op == 14.0) {
            let g_scales = cartan_ptr_at(param, 4.0);
            let u_scales = cartan_ptr_at(param, 5.0);
            let in_vec = cartan_ptr_at(param, 6.0);
            let out_vec = cartan_ptr_at(param, 7.0);
            let w_g_bytes = cartan_ptr_at(param, 8.0);
            let w_u_bytes = cartan_ptr_at(param, 9.0);
            stride_bytes = in_dim * 0.5;

            j = start_row;
            let j_limit = end_row - 3.0;
            while (j < j_limit) {
                let j1 = j + 1.0;
                let j2 = j + 2.0;
                let j3 = j + 3.0;
                let gs0 = cartan_f32_at(g_scales, j);
                let gs1 = cartan_f32_at(g_scales, j1);
                let gs2 = cartan_f32_at(g_scales, j2);
                let gs3 = cartan_f32_at(g_scales, j3);
                let us0 = cartan_f32_at(u_scales, j);
                let us1 = cartan_f32_at(u_scales, j1);
                let us2 = cartan_f32_at(u_scales, j2);
                let us3 = cartan_f32_at(u_scales, j3);

                let grow0 = cartan_c_ptr_add(w_g_bytes, j * stride_bytes);
                let grow1 = cartan_c_ptr_add(w_g_bytes, j1 * stride_bytes);
                let grow2 = cartan_c_ptr_add(w_g_bytes, j2 * stride_bytes);
                let grow3 = cartan_c_ptr_add(w_g_bytes, j3 * stride_bytes);
                let urow0 = cartan_c_ptr_add(w_u_bytes, j * stride_bytes);
                let urow1 = cartan_c_ptr_add(w_u_bytes, j1 * stride_bytes);
                let urow2 = cartan_c_ptr_add(w_u_bytes, j2 * stride_bytes);
                let urow3 = cartan_c_ptr_add(w_u_bytes, j3 * stride_bytes);

                let dg0 = cartan_simd_dot_i4_f32(grow0, in_vec, gs0, in_dim);
                let du0 = cartan_simd_dot_i4_f32(urow0, in_vec, us0, in_dim);
                let dg1 = cartan_simd_dot_i4_f32(grow1, in_vec, gs1, in_dim);
                let du1 = cartan_simd_dot_i4_f32(urow1, in_vec, us1, in_dim);
                let dg2 = cartan_simd_dot_i4_f32(grow2, in_vec, gs2, in_dim);
                let du2 = cartan_simd_dot_i4_f32(urow2, in_vec, us2, in_dim);
                let dg3 = cartan_simd_dot_i4_f32(grow3, in_vec, gs3, in_dim);
                let du3 = cartan_simd_dot_i4_f32(urow3, in_vec, us3, in_dim);

                cartan_set_f32(out_vec, j, cartan_fast_gelu_tanh(dg0) * du0);
                cartan_set_f32(out_vec, j1, cartan_fast_gelu_tanh(dg1) * du1);
                cartan_set_f32(out_vec, j2, cartan_fast_gelu_tanh(dg2) * du2);
                cartan_set_f32(out_vec, j3, cartan_fast_gelu_tanh(dg3) * du3);
                j = j + 4.0;
            }
            while (j < end_row) {
                let gs = cartan_f32_at(g_scales, j);
                let us = cartan_f32_at(u_scales, j);
                let grow = cartan_c_ptr_add(w_g_bytes, j * stride_bytes);
                let urow = cartan_c_ptr_add(w_u_bytes, j * stride_bytes);
                let dg = cartan_simd_dot_i4_f32(grow, in_vec, gs, in_dim);
                let du = cartan_simd_dot_i4_f32(urow, in_vec, us, in_dim);
                cartan_set_f32(out_vec, j, cartan_fast_gelu_tanh(dg) * du);
                j = j + 1.0;
            }
        } else if (op == 15.0) {
            let scales = cartan_ptr_at(param, 4.0);
            let w_bytes = cartan_ptr_at(param, 5.0);
            let in_mat = cartan_ptr_at(param, 6.0);
            let out_mat = cartan_ptr_at(param, 7.0);
            stride_bytes = in_dim * 0.5;

            r = start_row;
            let r_limit = end_row - 3.0;
            while (r < r_limit) {
                let r1 = r + 1.0;
                let r2 = r + 2.0;
                let r3 = r + 3.0;
                let s0 = cartan_f32_at(scales, r);
                let s1 = cartan_f32_at(scales, r1);
                let s2 = cartan_f32_at(scales, r2);
                let s3 = cartan_f32_at(scales, r3);
                let row0 = cartan_c_ptr_add(w_bytes, r * stride_bytes);
                let row1 = cartan_c_ptr_add(w_bytes, r1 * stride_bytes);
                let row2 = cartan_c_ptr_add(w_bytes, r2 * stride_bytes);
                let row3 = cartan_c_ptr_add(w_bytes, r3 * stride_bytes);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let d0 = cartan_simd_dot_i4_f32(row0, in_p, s0, in_dim);
                    let d1 = cartan_simd_dot_i4_f32(row1, in_p, s1, in_dim);
                    let d2 = cartan_simd_dot_i4_f32(row2, in_p, s2, in_dim);
                    let d3 = cartan_simd_dot_i4_f32(row3, in_p, s3, in_dim);
                    let base_out = p * out_stride + r;
                    cartan_set_f32(out_mat, base_out, d0);
                    cartan_set_f32(out_mat, base_out + 1.0, d1);
                    cartan_set_f32(out_mat, base_out + 2.0, d2);
                    cartan_set_f32(out_mat, base_out + 3.0, d3);
                    p = p + 1.0;
                }
                r = r + 4.0;
            }
            while (r < end_row) {
                let row_scale = cartan_f32_at(scales, r);
                let row = cartan_c_ptr_add(w_bytes, r * stride_bytes);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dot = cartan_simd_dot_i4_f32(row, in_p, row_scale, in_dim);
                    cartan_set_f32(out_mat, p * out_stride + r, dot);
                    p = p + 1.0;
                }
                r = r + 1.0;
            }
        } else if (op == 16.0) {
            let k_scales = cartan_ptr_at(param, 4.0);
            let w_k_bytes = cartan_ptr_at(param, 5.0);
            let in_mat = cartan_ptr_at(param, 6.0);
            let out_k = cartan_ptr_at(param, 7.0);
            let v_scales = cartan_ptr_at(param, 8.0);
            let w_v_bytes = cartan_ptr_at(param, 9.0);
            let out_v = cartan_ptr_at(param, 10.0);
            stride_bytes = in_dim * 0.5;

            r = start_row;
            let r_limit = end_row - 3.0;
            while (r < r_limit) {
                let r1 = r + 1.0;
                let r2 = r + 2.0;
                let r3 = r + 3.0;
                let ks0 = cartan_f32_at(k_scales, r);
                let ks1 = cartan_f32_at(k_scales, r1);
                let ks2 = cartan_f32_at(k_scales, r2);
                let ks3 = cartan_f32_at(k_scales, r3);
                let vs0 = cartan_f32_at(v_scales, r);
                let vs1 = cartan_f32_at(v_scales, r1);
                let vs2 = cartan_f32_at(v_scales, r2);
                let vs3 = cartan_f32_at(v_scales, r3);
                let k0 = cartan_c_ptr_add(w_k_bytes, r * stride_bytes);
                let k1 = cartan_c_ptr_add(w_k_bytes, r1 * stride_bytes);
                let k2 = cartan_c_ptr_add(w_k_bytes, r2 * stride_bytes);
                let k3 = cartan_c_ptr_add(w_k_bytes, r3 * stride_bytes);
                let v0 = cartan_c_ptr_add(w_v_bytes, r * stride_bytes);
                let v1 = cartan_c_ptr_add(w_v_bytes, r1 * stride_bytes);
                let v2 = cartan_c_ptr_add(w_v_bytes, r2 * stride_bytes);
                let v3 = cartan_c_ptr_add(w_v_bytes, r3 * stride_bytes);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dk0 = cartan_simd_dot_i4_f32(k0, in_p, ks0, in_dim);
                    let dv0 = cartan_simd_dot_i4_f32(v0, in_p, vs0, in_dim);
                    let dk1 = cartan_simd_dot_i4_f32(k1, in_p, ks1, in_dim);
                    let dv1 = cartan_simd_dot_i4_f32(v1, in_p, vs1, in_dim);
                    let dk2 = cartan_simd_dot_i4_f32(k2, in_p, ks2, in_dim);
                    let dv2 = cartan_simd_dot_i4_f32(v2, in_p, vs2, in_dim);
                    let dk3 = cartan_simd_dot_i4_f32(k3, in_p, ks3, in_dim);
                    let dv3 = cartan_simd_dot_i4_f32(v3, in_p, vs3, in_dim);
                    let base_out = p * out_stride + r;
                    cartan_set_f32(out_k, base_out, dk0);
                    cartan_set_f32(out_v, base_out, dv0);
                    cartan_set_f32(out_k, base_out + 1.0, dk1);
                    cartan_set_f32(out_v, base_out + 1.0, dv1);
                    cartan_set_f32(out_k, base_out + 2.0, dk2);
                    cartan_set_f32(out_v, base_out + 2.0, dv2);
                    cartan_set_f32(out_k, base_out + 3.0, dk3);
                    cartan_set_f32(out_v, base_out + 3.0, dv3);
                    p = p + 1.0;
                }
                r = r + 4.0;
            }
            while (r < end_row) {
                let ks = cartan_f32_at(k_scales, r);
                let vs = cartan_f32_at(v_scales, r);
                let k_row = cartan_c_ptr_add(w_k_bytes, r * stride_bytes);
                let v_row = cartan_c_ptr_add(w_v_bytes, r * stride_bytes);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dk = cartan_simd_dot_i4_f32(k_row, in_p, ks, in_dim);
                    let dv = cartan_simd_dot_i4_f32(v_row, in_p, vs, in_dim);
                    let base_out = p * out_stride + r;
                    cartan_set_f32(out_k, base_out, dk);
                    cartan_set_f32(out_v, base_out, dv);
                    p = p + 1.0;
                }
                r = r + 1.0;
            }
        } else if (op == 17.0) {
            let g_scales = cartan_ptr_at(param, 4.0);
            let u_scales = cartan_ptr_at(param, 5.0);
            let in_mat = cartan_ptr_at(param, 6.0);
            let out_act = cartan_ptr_at(param, 7.0);
            let w_g_bytes = cartan_ptr_at(param, 8.0);
            let w_u_bytes = cartan_ptr_at(param, 9.0);
            stride_bytes = in_dim * 0.5;

            j = start_row;
            let j_limit = end_row - 3.0;
            while (j < j_limit) {
                let j1 = j + 1.0;
                let j2 = j + 2.0;
                let j3 = j + 3.0;
                let gs0 = cartan_f32_at(g_scales, j);
                let gs1 = cartan_f32_at(g_scales, j1);
                let gs2 = cartan_f32_at(g_scales, j2);
                let gs3 = cartan_f32_at(g_scales, j3);
                let us0 = cartan_f32_at(u_scales, j);
                let us1 = cartan_f32_at(u_scales, j1);
                let us2 = cartan_f32_at(u_scales, j2);
                let us3 = cartan_f32_at(u_scales, j3);
                let grow0 = cartan_c_ptr_add(w_g_bytes, j * stride_bytes);
                let grow1 = cartan_c_ptr_add(w_g_bytes, j1 * stride_bytes);
                let grow2 = cartan_c_ptr_add(w_g_bytes, j2 * stride_bytes);
                let grow3 = cartan_c_ptr_add(w_g_bytes, j3 * stride_bytes);
                let urow0 = cartan_c_ptr_add(w_u_bytes, j * stride_bytes);
                let urow1 = cartan_c_ptr_add(w_u_bytes, j1 * stride_bytes);
                let urow2 = cartan_c_ptr_add(w_u_bytes, j2 * stride_bytes);
                let urow3 = cartan_c_ptr_add(w_u_bytes, j3 * stride_bytes);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dg0 = cartan_simd_dot_i4_f32(grow0, in_p, gs0, in_dim);
                    let du0 = cartan_simd_dot_i4_f32(urow0, in_p, us0, in_dim);
                    let dg1 = cartan_simd_dot_i4_f32(grow1, in_p, gs1, in_dim);
                    let du1 = cartan_simd_dot_i4_f32(urow1, in_p, us1, in_dim);
                    let dg2 = cartan_simd_dot_i4_f32(grow2, in_p, gs2, in_dim);
                    let du2 = cartan_simd_dot_i4_f32(urow2, in_p, us2, in_dim);
                    let dg3 = cartan_simd_dot_i4_f32(grow3, in_p, gs3, in_dim);
                    let du3 = cartan_simd_dot_i4_f32(urow3, in_p, us3, in_dim);
                    let base_out = p * out_stride + j;
                    cartan_set_f32(out_act, base_out, cartan_fast_gelu_tanh(dg0) * du0);
                    cartan_set_f32(out_act, base_out + 1.0, cartan_fast_gelu_tanh(dg1) * du1);
                    cartan_set_f32(out_act, base_out + 2.0, cartan_fast_gelu_tanh(dg2) * du2);
                    cartan_set_f32(out_act, base_out + 3.0, cartan_fast_gelu_tanh(dg3) * du3);
                    p = p + 1.0;
                }
                j = j + 4.0;
            }
            while (j < end_row) {
                let gs = cartan_f32_at(g_scales, j);
                let us = cartan_f32_at(u_scales, j);
                let grow = cartan_c_ptr_add(w_g_bytes, j * stride_bytes);
                let urow = cartan_c_ptr_add(w_u_bytes, j * stride_bytes);
                p = 0.0;
                while (p < N) {
                    let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                    let dg = cartan_simd_dot_i4_f32(grow, in_p, gs, in_dim);
                    let du = cartan_simd_dot_i4_f32(urow, in_p, us, in_dim);
                    cartan_set_f32(out_act, p * out_stride + j, cartan_fast_gelu_tanh(dg) * du);
                    p = p + 1.0;
                }
                j = j + 1.0;
            }
        }

        cartan_memory_fence();
        cartan_atomic_set_f32(param, 24.0, 2.0);
    }
    return 0.0;
}

fn cartan_trans_pool_dispatch(op: float, total_rows: float, in_dim: float, w_mat1: ptr, w_mat2: ptr, in_vec: ptr, out_vec: ptr) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 0.0;
    var j = 0.0;
    var r = 0.0;
    var spin = 0.0;
    var end_r = 0.0;
    var s = 0.0;

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, op);
        cartan_set_ptr(tp, 4.0, w_mat1);
        cartan_set_ptr(tp, 5.0, w_mat2);
        cartan_set_ptr(tp, 6.0, in_vec);
        cartan_set_ptr(tp, 7.0, out_vec);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    if (op == 1.0) {
        j = 0.0;
        let j_limit = chunk - 3.0;
        while (j < j_limit) {
            let j1 = j + 1.0;
            let j2 = j + 2.0;
            let j3 = j + 3.0;
            let g_row0 = cartan_f32_ptr_add(w_mat1, j * in_dim);
            let u_row0 = cartan_f32_ptr_add(w_mat2, j * in_dim);
            let g_row1 = cartan_f32_ptr_add(w_mat1, j1 * in_dim);
            let u_row1 = cartan_f32_ptr_add(w_mat2, j1 * in_dim);
            let g_row2 = cartan_f32_ptr_add(w_mat1, j2 * in_dim);
            let u_row2 = cartan_f32_ptr_add(w_mat2, j2 * in_dim);
            let g_row3 = cartan_f32_ptr_add(w_mat1, j3 * in_dim);
            let u_row3 = cartan_f32_ptr_add(w_mat2, j3 * in_dim);

            let dot_gate0 = cartan_simd_dot_f32(g_row0, in_vec, in_dim);
            let dot_up0 = cartan_simd_dot_f32(u_row0, in_vec, in_dim);
            let dot_gate1 = cartan_simd_dot_f32(g_row1, in_vec, in_dim);
            let dot_up1 = cartan_simd_dot_f32(u_row1, in_vec, in_dim);
            let dot_gate2 = cartan_simd_dot_f32(g_row2, in_vec, in_dim);
            let dot_up2 = cartan_simd_dot_f32(u_row2, in_vec, in_dim);
            let dot_gate3 = cartan_simd_dot_f32(g_row3, in_vec, in_dim);
            let dot_up3 = cartan_simd_dot_f32(u_row3, in_vec, in_dim);

            cartan_set_f32(out_vec, j, cartan_fast_gelu_tanh(dot_gate0) * dot_up0);
            cartan_set_f32(out_vec, j1, cartan_fast_gelu_tanh(dot_gate1) * dot_up1);
            cartan_set_f32(out_vec, j2, cartan_fast_gelu_tanh(dot_gate2) * dot_up2);
            cartan_set_f32(out_vec, j3, cartan_fast_gelu_tanh(dot_gate3) * dot_up3);
            j = j + 4.0;
        }
        while (j < chunk) {
            let g_row = cartan_f32_ptr_add(w_mat1, j * in_dim);
            let u_row = cartan_f32_ptr_add(w_mat2, j * in_dim);
            let dot_gate = cartan_simd_dot_f32(g_row, in_vec, in_dim);
            let dot_up = cartan_simd_dot_f32(u_row, in_vec, in_dim);
            cartan_set_f32(out_vec, j, cartan_fast_gelu_tanh(dot_gate) * dot_up);
            j = j + 1.0;
        }
    } else if (op == 2.0) {
        r = 0.0;
        let r_limit = chunk - 3.0;
        while (r < r_limit) {
            let r1 = r + 1.0;
            let r2 = r + 2.0;
            let r3 = r + 3.0;
            let row0 = cartan_f32_ptr_add(w_mat1, r * in_dim);
            let row1 = cartan_f32_ptr_add(w_mat1, r1 * in_dim);
            let row2 = cartan_f32_ptr_add(w_mat1, r2 * in_dim);
            let row3 = cartan_f32_ptr_add(w_mat1, r3 * in_dim);

            let d0 = cartan_simd_dot_f32(row0, in_vec, in_dim);
            let d1 = cartan_simd_dot_f32(row1, in_vec, in_dim);
            let d2 = cartan_simd_dot_f32(row2, in_vec, in_dim);
            let d3 = cartan_simd_dot_f32(row3, in_vec, in_dim);

            cartan_set_f32(out_vec, r, d0);
            cartan_set_f32(out_vec, r1, d1);
            cartan_set_f32(out_vec, r2, d2);
            cartan_set_f32(out_vec, r3, d3);
            r = r + 4.0;
        }
        while (r < chunk) {
            let row = cartan_f32_ptr_add(w_mat1, r * in_dim);
            let dot = cartan_simd_dot_f32(row, in_vec, in_dim);
            cartan_set_f32(out_vec, r, dot);
            r = r + 1.0;
        }
    } else if (op == 7.0) {
        r = 0.0;
        let r_limit = chunk - 3.0;
        while (r < r_limit) {
            let r1 = r + 1.0;
            let r2 = r + 2.0;
            let r3 = r + 3.0;
            let s0 = cartan_f32_at(w_mat1, r);
            let s1 = cartan_f32_at(w_mat1, r1);
            let s2 = cartan_f32_at(w_mat1, r2);
            let s3 = cartan_f32_at(w_mat1, r3);
            let row0 = cartan_c_ptr_add(w_mat2, r * in_dim);
            let row1 = cartan_c_ptr_add(w_mat2, r1 * in_dim);
            let row2 = cartan_c_ptr_add(w_mat2, r2 * in_dim);
            let row3 = cartan_c_ptr_add(w_mat2, r3 * in_dim);

            let d0 = cartan_simd_dot_i8_f32(row0, in_vec, s0, in_dim);
            let d1 = cartan_simd_dot_i8_f32(row1, in_vec, s1, in_dim);
            let d2 = cartan_simd_dot_i8_f32(row2, in_vec, s2, in_dim);
            let d3 = cartan_simd_dot_i8_f32(row3, in_vec, s3, in_dim);

            cartan_set_f32(out_vec, r, d0);
            cartan_set_f32(out_vec, r1, d1);
            cartan_set_f32(out_vec, r2, d2);
            cartan_set_f32(out_vec, r3, d3);
            r = r + 4.0;
        }
        while (r < chunk) {
            let row_scale = cartan_f32_at(w_mat1, r);
            let row = cartan_c_ptr_add(w_mat2, r * in_dim);
            let dot = cartan_simd_dot_i8_f32(row, in_vec, row_scale, in_dim);
            cartan_set_f32(out_vec, r, dot);
            r = r + 1.0;
        }
    } else if (op == 12.0) {
        let stride_bytes = in_dim * 0.5;
        r = 0.0;
        let r_limit = chunk - 3.0;
        while (r < r_limit) {
            let r1 = r + 1.0;
            let r2 = r + 2.0;
            let r3 = r + 3.0;
            let s0 = cartan_f32_at(w_mat1, r);
            let s1 = cartan_f32_at(w_mat1, r1);
            let s2 = cartan_f32_at(w_mat1, r2);
            let s3 = cartan_f32_at(w_mat1, r3);
            let row0 = cartan_c_ptr_add(w_mat2, r * stride_bytes);
            let row1 = cartan_c_ptr_add(w_mat2, r1 * stride_bytes);
            let row2 = cartan_c_ptr_add(w_mat2, r2 * stride_bytes);
            let row3 = cartan_c_ptr_add(w_mat2, r3 * stride_bytes);

            let d0 = cartan_simd_dot_i4_f32(row0, in_vec, s0, in_dim);
            let d1 = cartan_simd_dot_i4_f32(row1, in_vec, s1, in_dim);
            let d2 = cartan_simd_dot_i4_f32(row2, in_vec, s2, in_dim);
            let d3 = cartan_simd_dot_i4_f32(row3, in_vec, s3, in_dim);

            cartan_set_f32(out_vec, r, d0);
            cartan_set_f32(out_vec, r1, d1);
            cartan_set_f32(out_vec, r2, d2);
            cartan_set_f32(out_vec, r3, d3);
            r = r + 4.0;
        }
        while (r < chunk) {
            let row_scale = cartan_f32_at(w_mat1, r);
            let row = cartan_c_ptr_add(w_mat2, r * stride_bytes);
            let dot = cartan_simd_dot_i4_f32(row, in_vec, row_scale, in_dim);
            cartan_set_f32(out_vec, r, dot);
            r = r + 1.0;
        }
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_int8_geglu(
    total_rows: float,
    in_dim: float,
    g_scales: ptr,
    u_scales: ptr,
    w_g_bytes: ptr,
    w_u_bytes: ptr,
    in_vec: ptr,
    out_vec: ptr
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 1.0;
    var j = 0.0;
    var end_r = 0.0;
    var spin = 0.0;
    var s = 0.0;

    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, 8.0);
        cartan_set_ptr(tp, 4.0, g_scales);
        cartan_set_ptr(tp, 5.0, u_scales);
        cartan_set_ptr(tp, 6.0, in_vec);
        cartan_set_ptr(tp, 7.0, out_vec);
        cartan_set_ptr(tp, 8.0, w_g_bytes);
        cartan_set_ptr(tp, 9.0, w_u_bytes);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    j = 0.0;
    let j_limit = chunk - 3.0;
    while (j < j_limit) {
        let j1 = j + 1.0;
        let j2 = j + 2.0;
        let j3 = j + 3.0;
        let gs0 = cartan_f32_at(g_scales, j);
        let gs1 = cartan_f32_at(g_scales, j1);
        let gs2 = cartan_f32_at(g_scales, j2);
        let gs3 = cartan_f32_at(g_scales, j3);
        let us0 = cartan_f32_at(u_scales, j);
        let us1 = cartan_f32_at(u_scales, j1);
        let us2 = cartan_f32_at(u_scales, j2);
        let us3 = cartan_f32_at(u_scales, j3);

        let grow0 = cartan_c_ptr_add(w_g_bytes, j * in_dim);
        let grow1 = cartan_c_ptr_add(w_g_bytes, j1 * in_dim);
        let grow2 = cartan_c_ptr_add(w_g_bytes, j2 * in_dim);
        let grow3 = cartan_c_ptr_add(w_g_bytes, j3 * in_dim);
        let urow0 = cartan_c_ptr_add(w_u_bytes, j * in_dim);
        let urow1 = cartan_c_ptr_add(w_u_bytes, j1 * in_dim);
        let urow2 = cartan_c_ptr_add(w_u_bytes, j2 * in_dim);
        let urow3 = cartan_c_ptr_add(w_u_bytes, j3 * in_dim);

        let dg0 = cartan_simd_dot_i8_f32(grow0, in_vec, gs0, in_dim);
        let du0 = cartan_simd_dot_i8_f32(urow0, in_vec, us0, in_dim);
        let dg1 = cartan_simd_dot_i8_f32(grow1, in_vec, gs1, in_dim);
        let du1 = cartan_simd_dot_i8_f32(urow1, in_vec, us1, in_dim);
        let dg2 = cartan_simd_dot_i8_f32(grow2, in_vec, gs2, in_dim);
        let du2 = cartan_simd_dot_i8_f32(urow2, in_vec, us2, in_dim);
        let dg3 = cartan_simd_dot_i8_f32(grow3, in_vec, gs3, in_dim);
        let du3 = cartan_simd_dot_i8_f32(urow3, in_vec, us3, in_dim);

        cartan_set_f32(out_vec, j, cartan_fast_gelu_tanh(dg0) * du0);
        cartan_set_f32(out_vec, j1, cartan_fast_gelu_tanh(dg1) * du1);
        cartan_set_f32(out_vec, j2, cartan_fast_gelu_tanh(dg2) * du2);
        cartan_set_f32(out_vec, j3, cartan_fast_gelu_tanh(dg3) * du3);
        j = j + 4.0;
    }
    while (j < chunk) {
        let gs = cartan_f32_at(g_scales, j);
        let us = cartan_f32_at(u_scales, j);
        let grow = cartan_c_ptr_add(w_g_bytes, j * in_dim);
        let urow = cartan_c_ptr_add(w_u_bytes, j * in_dim);
        let dg = cartan_simd_dot_i8_f32(grow, in_vec, gs, in_dim);
        let du = cartan_simd_dot_i8_f32(urow, in_vec, us, in_dim);
        cartan_set_f32(out_vec, j, cartan_fast_gelu_tanh(dg) * du);
        j = j + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_int4_geglu(
    total_rows: float,
    in_dim: float,
    g_scales: ptr,
    u_scales: ptr,
    w_g_bytes: ptr,
    w_u_bytes: ptr,
    in_vec: ptr,
    out_vec: ptr
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 1.0;
    var j = 0.0;
    var end_r = 0.0;
    var spin = 0.0;
    var s = 0.0;

    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, 14.0);
        cartan_set_ptr(tp, 4.0, g_scales);
        cartan_set_ptr(tp, 5.0, u_scales);
        cartan_set_ptr(tp, 6.0, in_vec);
        cartan_set_ptr(tp, 7.0, out_vec);
        cartan_set_ptr(tp, 8.0, w_g_bytes);
        cartan_set_ptr(tp, 9.0, w_u_bytes);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    let stride_bytes = in_dim * 0.5;
    j = 0.0;
    let j_limit = chunk - 3.0;
    while (j < j_limit) {
        let j1 = j + 1.0;
        let j2 = j + 2.0;
        let j3 = j + 3.0;
        let gs0 = cartan_f32_at(g_scales, j);
        let gs1 = cartan_f32_at(g_scales, j1);
        let gs2 = cartan_f32_at(g_scales, j2);
        let gs3 = cartan_f32_at(g_scales, j3);
        let us0 = cartan_f32_at(u_scales, j);
        let us1 = cartan_f32_at(u_scales, j1);
        let us2 = cartan_f32_at(u_scales, j2);
        let us3 = cartan_f32_at(u_scales, j3);

        let grow0 = cartan_c_ptr_add(w_g_bytes, j * stride_bytes);
        let grow1 = cartan_c_ptr_add(w_g_bytes, j1 * stride_bytes);
        let grow2 = cartan_c_ptr_add(w_g_bytes, j2 * stride_bytes);
        let grow3 = cartan_c_ptr_add(w_g_bytes, j3 * stride_bytes);
        let urow0 = cartan_c_ptr_add(w_u_bytes, j * stride_bytes);
        let urow1 = cartan_c_ptr_add(w_u_bytes, j1 * stride_bytes);
        let urow2 = cartan_c_ptr_add(w_u_bytes, j2 * stride_bytes);
        let urow3 = cartan_c_ptr_add(w_u_bytes, j3 * stride_bytes);

        let dg0 = cartan_simd_dot_i4_f32(grow0, in_vec, gs0, in_dim);
        let du0 = cartan_simd_dot_i4_f32(urow0, in_vec, us0, in_dim);
        let dg1 = cartan_simd_dot_i4_f32(grow1, in_vec, gs1, in_dim);
        let du1 = cartan_simd_dot_i4_f32(urow1, in_vec, us1, in_dim);
        let dg2 = cartan_simd_dot_i4_f32(grow2, in_vec, gs2, in_dim);
        let du2 = cartan_simd_dot_i4_f32(urow2, in_vec, us2, in_dim);
        let dg3 = cartan_simd_dot_i4_f32(grow3, in_vec, gs3, in_dim);
        let du3 = cartan_simd_dot_i4_f32(urow3, in_vec, us3, in_dim);

        cartan_set_f32(out_vec, j, cartan_fast_gelu_tanh(dg0) * du0);
        cartan_set_f32(out_vec, j1, cartan_fast_gelu_tanh(dg1) * du1);
        cartan_set_f32(out_vec, j2, cartan_fast_gelu_tanh(dg2) * du2);
        cartan_set_f32(out_vec, j3, cartan_fast_gelu_tanh(dg3) * du3);
        j = j + 4.0;
    }
    while (j < chunk) {
        let gs = cartan_f32_at(g_scales, j);
        let us = cartan_f32_at(u_scales, j);
        let grow = cartan_c_ptr_add(w_g_bytes, j * stride_bytes);
        let urow = cartan_c_ptr_add(w_u_bytes, j * stride_bytes);
        let dg = cartan_simd_dot_i4_f32(grow, in_vec, gs, in_dim);
        let du = cartan_simd_dot_i4_f32(urow, in_vec, us, in_dim);
        cartan_set_f32(out_vec, j, cartan_fast_gelu_tanh(dg) * du);
        j = j + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_int4_dual_gemv(
    total_rows: float,
    in_dim: float,
    k_scales: ptr,
    w_k_bytes: ptr,
    v_scales: ptr,
    w_v_bytes: ptr,
    in_vec: ptr,
    out_k: ptr,
    out_v: ptr
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 1.0;
    var r = 0.0;
    var end_r = 0.0;
    var spin = 0.0;
    var s = 0.0;

    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, 13.0);
        cartan_set_ptr(tp, 4.0, k_scales);
        cartan_set_ptr(tp, 5.0, w_k_bytes);
        cartan_set_ptr(tp, 6.0, in_vec);
        cartan_set_ptr(tp, 7.0, out_k);
        cartan_set_ptr(tp, 8.0, v_scales);
        cartan_set_ptr(tp, 9.0, w_v_bytes);
        cartan_set_ptr(tp, 10.0, out_v);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    let stride_bytes = in_dim * 0.5;
    r = 0.0;
    let r_limit = chunk - 3.0;
    while (r < r_limit) {
        let r1 = r + 1.0;
        let r2 = r + 2.0;
        let r3 = r + 3.0;
        let ks0 = cartan_f32_at(k_scales, r);
        let ks1 = cartan_f32_at(k_scales, r1);
        let ks2 = cartan_f32_at(k_scales, r2);
        let ks3 = cartan_f32_at(k_scales, r3);
        let vs0 = cartan_f32_at(v_scales, r);
        let vs1 = cartan_f32_at(v_scales, r1);
        let vs2 = cartan_f32_at(v_scales, r2);
        let vs3 = cartan_f32_at(v_scales, r3);

        let k0 = cartan_c_ptr_add(w_k_bytes, r * stride_bytes);
        let k1 = cartan_c_ptr_add(w_k_bytes, r1 * stride_bytes);
        let k2 = cartan_c_ptr_add(w_k_bytes, r2 * stride_bytes);
        let k3 = cartan_c_ptr_add(w_k_bytes, r3 * stride_bytes);
        let v0 = cartan_c_ptr_add(w_v_bytes, r * stride_bytes);
        let v1 = cartan_c_ptr_add(w_v_bytes, r1 * stride_bytes);
        let v2 = cartan_c_ptr_add(w_v_bytes, r2 * stride_bytes);
        let v3 = cartan_c_ptr_add(w_v_bytes, r3 * stride_bytes);

        let dk0 = cartan_simd_dot_i4_f32(k0, in_vec, ks0, in_dim);
        let dv0 = cartan_simd_dot_i4_f32(v0, in_vec, vs0, in_dim);
        let dk1 = cartan_simd_dot_i4_f32(k1, in_vec, ks1, in_dim);
        let dv1 = cartan_simd_dot_i4_f32(v1, in_vec, vs1, in_dim);
        let dk2 = cartan_simd_dot_i4_f32(k2, in_vec, ks2, in_dim);
        let dv2 = cartan_simd_dot_i4_f32(v2, in_vec, vs2, in_dim);
        let dk3 = cartan_simd_dot_i4_f32(k3, in_vec, ks3, in_dim);
        let dv3 = cartan_simd_dot_i4_f32(v3, in_vec, vs3, in_dim);

        cartan_set_f32(out_k, r, dk0);
        cartan_set_f32(out_v, r, dv0);
        cartan_set_f32(out_k, r1, dk1);
        cartan_set_f32(out_v, r1, dv1);
        cartan_set_f32(out_k, r2, dk2);
        cartan_set_f32(out_v, r2, dv2);
        cartan_set_f32(out_k, r3, dk3);
        cartan_set_f32(out_v, r3, dv3);
        r = r + 4.0;
    }
    while (r < chunk) {
        let ks = cartan_f32_at(k_scales, r);
        let vs = cartan_f32_at(v_scales, r);
        let k_row = cartan_c_ptr_add(w_k_bytes, r * stride_bytes);
        let v_row = cartan_c_ptr_add(w_v_bytes, r * stride_bytes);
        let dk = cartan_simd_dot_i4_f32(k_row, in_vec, ks, in_dim);
        let dv = cartan_simd_dot_i4_f32(v_row, in_vec, vs, in_dim);
        cartan_set_f32(out_k, r, dk);
        cartan_set_f32(out_v, r, dv);
        r = r + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_batch(
    op: float,
    total_rows: float,
    in_dim: float,
    N: float,
    out_stride: float,
    w_mat1: ptr,
    w_mat2: ptr,
    in_mat: ptr,
    out_mat1: ptr,
    out_mat2: ptr
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 0.0;
    var j = 0.0;
    var r = 0.0;
    var p = 0.0;
    var spin = 0.0;
    var end_r = 0.0;
    var s = 0.0;

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, op);
        cartan_set_ptr(tp, 4.0, w_mat1);
        cartan_set_ptr(tp, 5.0, w_mat2);
        cartan_set_ptr(tp, 6.0, in_mat);
        cartan_set_ptr(tp, 7.0, out_mat1);
        cartan_set_ptr(tp, 8.0, out_mat2);
        cartan_set_f32(tp, 25.0, N);
        cartan_set_f32(tp, 26.0, out_stride);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    if (op == 3.0) {
        j = 0.0;
        let j_limit = chunk - 3.0;
        while (j < j_limit) {
            let j1 = j + 1.0;
            let j2 = j + 2.0;
            let j3 = j + 3.0;
            let g0 = cartan_f32_ptr_add(w_mat1, j * in_dim);
            let g1 = cartan_f32_ptr_add(w_mat1, j1 * in_dim);
            let g2 = cartan_f32_ptr_add(w_mat1, j2 * in_dim);
            let g3 = cartan_f32_ptr_add(w_mat1, j3 * in_dim);
            let u0 = cartan_f32_ptr_add(w_mat2, j * in_dim);
            let u1 = cartan_f32_ptr_add(w_mat2, j1 * in_dim);
            let u2 = cartan_f32_ptr_add(w_mat2, j2 * in_dim);
            let u3 = cartan_f32_ptr_add(w_mat2, j3 * in_dim);
            p = 0.0;
            while (p < N) {
                let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                let dg0 = cartan_simd_dot_f32(g0, in_p, in_dim);
                let du0 = cartan_simd_dot_f32(u0, in_p, in_dim);
                let dg1 = cartan_simd_dot_f32(g1, in_p, in_dim);
                let du1 = cartan_simd_dot_f32(u1, in_p, in_dim);
                let dg2 = cartan_simd_dot_f32(g2, in_p, in_dim);
                let du2 = cartan_simd_dot_f32(u2, in_p, in_dim);
                let dg3 = cartan_simd_dot_f32(g3, in_p, in_dim);
                let du3 = cartan_simd_dot_f32(u3, in_p, in_dim);
                let base_out = p * out_stride + j;
                cartan_set_f32(out_mat1, base_out, cartan_fast_gelu_tanh(dg0) * du0);
                cartan_set_f32(out_mat1, base_out + 1.0, cartan_fast_gelu_tanh(dg1) * du1);
                cartan_set_f32(out_mat1, base_out + 2.0, cartan_fast_gelu_tanh(dg2) * du2);
                cartan_set_f32(out_mat1, base_out + 3.0, cartan_fast_gelu_tanh(dg3) * du3);
                p = p + 1.0;
            }
            j = j + 4.0;
        }
        while (j < chunk) {
            let g_row = cartan_f32_ptr_add(w_mat1, j * in_dim);
            let u_row = cartan_f32_ptr_add(w_mat2, j * in_dim);
            p = 0.0;
            while (p < N) {
                let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                let dot_gate = cartan_simd_dot_f32(g_row, in_p, in_dim);
                let dot_up = cartan_simd_dot_f32(u_row, in_p, in_dim);
                let act = cartan_fast_gelu_tanh(dot_gate) * dot_up;
                cartan_set_f32(out_mat1, p * out_stride + j, act);
                p = p + 1.0;
            }
            j = j + 1.0;
        }
    } else if (op == 4.0) {
        r = 0.0;
        let r_limit = chunk - 3.0;
        while (r < r_limit) {
            let r1 = r + 1.0;
            let r2 = r + 2.0;
            let r3 = r + 3.0;
            let row0 = cartan_f32_ptr_add(w_mat1, r * in_dim);
            let row1 = cartan_f32_ptr_add(w_mat1, r1 * in_dim);
            let row2 = cartan_f32_ptr_add(w_mat1, r2 * in_dim);
            let row3 = cartan_f32_ptr_add(w_mat1, r3 * in_dim);
            p = 0.0;
            while (p < N) {
                let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                let d0 = cartan_simd_dot_f32(row0, in_p, in_dim);
                let d1 = cartan_simd_dot_f32(row1, in_p, in_dim);
                let d2 = cartan_simd_dot_f32(row2, in_p, in_dim);
                let d3 = cartan_simd_dot_f32(row3, in_p, in_dim);
                let base_out = p * out_stride + r;
                cartan_set_f32(out_mat1, base_out, d0);
                cartan_set_f32(out_mat1, base_out + 1.0, d1);
                cartan_set_f32(out_mat1, base_out + 2.0, d2);
                cartan_set_f32(out_mat1, base_out + 3.0, d3);
                p = p + 1.0;
            }
            r = r + 4.0;
        }
        while (r < chunk) {
            let row = cartan_f32_ptr_add(w_mat1, r * in_dim);
            p = 0.0;
            while (p < N) {
                let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                let dot = cartan_simd_dot_f32(row, in_p, in_dim);
                cartan_set_f32(out_mat1, p * out_stride + r, dot);
                p = p + 1.0;
            }
            r = r + 1.0;
        }
    } else if (op == 5.0) {
        r = 0.0;
        let r_limit = chunk - 3.0;
        while (r < r_limit) {
            let r1 = r + 1.0;
            let r2 = r + 2.0;
            let r3 = r + 3.0;
            let k0 = cartan_f32_ptr_add(w_mat1, r * in_dim);
            let k1 = cartan_f32_ptr_add(w_mat1, r1 * in_dim);
            let k2 = cartan_f32_ptr_add(w_mat1, r2 * in_dim);
            let k3 = cartan_f32_ptr_add(w_mat1, r3 * in_dim);
            let v0 = cartan_f32_ptr_add(w_mat2, r * in_dim);
            let v1 = cartan_f32_ptr_add(w_mat2, r1 * in_dim);
            let v2 = cartan_f32_ptr_add(w_mat2, r2 * in_dim);
            let v3 = cartan_f32_ptr_add(w_mat2, r3 * in_dim);
            p = 0.0;
            while (p < N) {
                let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                let base_out = p * out_stride + r;
                cartan_set_f32(out_mat1, base_out, cartan_simd_dot_f32(k0, in_p, in_dim));
                cartan_set_f32(out_mat1, base_out + 1.0, cartan_simd_dot_f32(k1, in_p, in_dim));
                cartan_set_f32(out_mat1, base_out + 2.0, cartan_simd_dot_f32(k2, in_p, in_dim));
                cartan_set_f32(out_mat1, base_out + 3.0, cartan_simd_dot_f32(k3, in_p, in_dim));
                cartan_set_f32(out_mat2, base_out, cartan_simd_dot_f32(v0, in_p, in_dim));
                cartan_set_f32(out_mat2, base_out + 1.0, cartan_simd_dot_f32(v1, in_p, in_dim));
                cartan_set_f32(out_mat2, base_out + 2.0, cartan_simd_dot_f32(v2, in_p, in_dim));
                cartan_set_f32(out_mat2, base_out + 3.0, cartan_simd_dot_f32(v3, in_p, in_dim));
                p = p + 1.0;
            }
            r = r + 4.0;
        }
        while (r < chunk) {
            let k_row = cartan_f32_ptr_add(w_mat1, r * in_dim);
            let v_row = cartan_f32_ptr_add(w_mat2, r * in_dim);
            p = 0.0;
            while (p < N) {
                let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
                let base_out = p * out_stride + r;
                cartan_set_f32(out_mat1, base_out, cartan_simd_dot_f32(k_row, in_p, in_dim));
                cartan_set_f32(out_mat2, base_out, cartan_simd_dot_f32(v_row, in_p, in_dim));
                p = p + 1.0;
            }
            r = r + 1.0;
        }
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_batch_int8_gemv(
    total_rows: float,
    in_dim: float,
    scales: ptr,
    w_bytes: ptr,
    in_mat: ptr,
    out_mat: ptr,
    N: float,
    out_stride: float
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 0.0;
    var r = 0.0;
    var p = 0.0;
    var spin = 0.0;
    var end_r = 0.0;
    var s = 0.0;

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, 9.0);
        cartan_set_ptr(tp, 4.0, scales);
        cartan_set_ptr(tp, 5.0, w_bytes);
        cartan_set_ptr(tp, 6.0, in_mat);
        cartan_set_ptr(tp, 7.0, out_mat);
        cartan_set_f32(tp, 25.0, N);
        cartan_set_f32(tp, 26.0, out_stride);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    r = 0.0;
    let r_limit = chunk - 3.0;
    while (r < r_limit) {
        let r1 = r + 1.0;
        let r2 = r + 2.0;
        let r3 = r + 3.0;
        let s0 = cartan_f32_at(scales, r);
        let s1 = cartan_f32_at(scales, r1);
        let s2 = cartan_f32_at(scales, r2);
        let s3 = cartan_f32_at(scales, r3);
        let row0 = cartan_c_ptr_add(w_bytes, r * in_dim);
        let row1 = cartan_c_ptr_add(w_bytes, r1 * in_dim);
        let row2 = cartan_c_ptr_add(w_bytes, r2 * in_dim);
        let row3 = cartan_c_ptr_add(w_bytes, r3 * in_dim);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let d0 = cartan_simd_dot_i8_f32(row0, in_p, s0, in_dim);
            let d1 = cartan_simd_dot_i8_f32(row1, in_p, s1, in_dim);
            let d2 = cartan_simd_dot_i8_f32(row2, in_p, s2, in_dim);
            let d3 = cartan_simd_dot_i8_f32(row3, in_p, s3, in_dim);
            let base_out = p * out_stride + r;
            cartan_set_f32(out_mat, base_out, d0);
            cartan_set_f32(out_mat, base_out + 1.0, d1);
            cartan_set_f32(out_mat, base_out + 2.0, d2);
            cartan_set_f32(out_mat, base_out + 3.0, d3);
            p = p + 1.0;
        }
        r = r + 4.0;
    }
    while (r < chunk) {
        let row_scale = cartan_f32_at(scales, r);
        let row = cartan_c_ptr_add(w_bytes, r * in_dim);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let dot = cartan_simd_dot_i8_f32(row, in_p, row_scale, in_dim);
            cartan_set_f32(out_mat, p * out_stride + r, dot);
            p = p + 1.0;
        }
        r = r + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_batch_int8_dual_gemv(
    total_rows: float,
    in_dim: float,
    k_scales: ptr,
    w_k_bytes: ptr,
    v_scales: ptr,
    w_v_bytes: ptr,
    in_mat: ptr,
    out_k: ptr,
    out_v: ptr,
    N: float,
    out_stride: float
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 0.0;
    var r = 0.0;
    var p = 0.0;
    var spin = 0.0;
    var end_r = 0.0;
    var s = 0.0;

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, 10.0);
        cartan_set_ptr(tp, 4.0, k_scales);
        cartan_set_ptr(tp, 5.0, w_k_bytes);
        cartan_set_ptr(tp, 6.0, in_mat);
        cartan_set_ptr(tp, 7.0, out_k);
        cartan_set_ptr(tp, 8.0, v_scales);
        cartan_set_ptr(tp, 9.0, w_v_bytes);
        cartan_set_ptr(tp, 10.0, out_v);
        cartan_set_f32(tp, 25.0, N);
        cartan_set_f32(tp, 26.0, out_stride);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    r = 0.0;
    let r_limit = chunk - 3.0;
    while (r < r_limit) {
        let r1 = r + 1.0;
        let r2 = r + 2.0;
        let r3 = r + 3.0;
        let ks0 = cartan_f32_at(k_scales, r);
        let ks1 = cartan_f32_at(k_scales, r1);
        let ks2 = cartan_f32_at(k_scales, r2);
        let ks3 = cartan_f32_at(k_scales, r3);
        let vs0 = cartan_f32_at(v_scales, r);
        let vs1 = cartan_f32_at(v_scales, r1);
        let vs2 = cartan_f32_at(v_scales, r2);
        let vs3 = cartan_f32_at(v_scales, r3);
        let k0 = cartan_c_ptr_add(w_k_bytes, r * in_dim);
        let k1 = cartan_c_ptr_add(w_k_bytes, r1 * in_dim);
        let k2 = cartan_c_ptr_add(w_k_bytes, r2 * in_dim);
        let k3 = cartan_c_ptr_add(w_k_bytes, r3 * in_dim);
        let v0 = cartan_c_ptr_add(w_v_bytes, r * in_dim);
        let v1 = cartan_c_ptr_add(w_v_bytes, r1 * in_dim);
        let v2 = cartan_c_ptr_add(w_v_bytes, r2 * in_dim);
        let v3 = cartan_c_ptr_add(w_v_bytes, r3 * in_dim);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let dk0 = cartan_simd_dot_i8_f32(k0, in_p, ks0, in_dim);
            let dv0 = cartan_simd_dot_i8_f32(v0, in_p, vs0, in_dim);
            let dk1 = cartan_simd_dot_i8_f32(k1, in_p, ks1, in_dim);
            let dv1 = cartan_simd_dot_i8_f32(v1, in_p, vs1, in_dim);
            let dk2 = cartan_simd_dot_i8_f32(k2, in_p, ks2, in_dim);
            let dv2 = cartan_simd_dot_i8_f32(v2, in_p, vs2, in_dim);
            let dk3 = cartan_simd_dot_i8_f32(k3, in_p, ks3, in_dim);
            let dv3 = cartan_simd_dot_i8_f32(v3, in_p, vs3, in_dim);
            let base_out = p * out_stride + r;
            cartan_set_f32(out_k, base_out, dk0);
            cartan_set_f32(out_v, base_out, dv0);
            cartan_set_f32(out_k, base_out + 1.0, dk1);
            cartan_set_f32(out_v, base_out + 1.0, dv1);
            cartan_set_f32(out_k, base_out + 2.0, dk2);
            cartan_set_f32(out_v, base_out + 2.0, dv2);
            cartan_set_f32(out_k, base_out + 3.0, dk3);
            cartan_set_f32(out_v, base_out + 3.0, dv3);
            p = p + 1.0;
        }
        r = r + 4.0;
    }
    while (r < chunk) {
        let ks = cartan_f32_at(k_scales, r);
        let vs = cartan_f32_at(v_scales, r);
        let k_row = cartan_c_ptr_add(w_k_bytes, r * in_dim);
        let v_row = cartan_c_ptr_add(w_v_bytes, r * in_dim);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let dk = cartan_simd_dot_i8_f32(k_row, in_p, ks, in_dim);
            let dv = cartan_simd_dot_i8_f32(v_row, in_p, vs, in_dim);
            let base_out = p * out_stride + r;
            cartan_set_f32(out_k, base_out, dk);
            cartan_set_f32(out_v, base_out, dv);
            p = p + 1.0;
        }
        r = r + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_batch_int8_geglu(
    total_rows: float,
    in_dim: float,
    g_scales: ptr,
    u_scales: ptr,
    w_g_bytes: ptr,
    w_u_bytes: ptr,
    in_mat: ptr,
    out_act: ptr,
    N: float,
    out_stride: float
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 0.0;
    var j = 0.0;
    var p = 0.0;
    var spin = 0.0;
    var end_r = 0.0;
    var s = 0.0;

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, 11.0);
        cartan_set_ptr(tp, 4.0, g_scales);
        cartan_set_ptr(tp, 5.0, u_scales);
        cartan_set_ptr(tp, 6.0, in_mat);
        cartan_set_ptr(tp, 7.0, out_act);
        cartan_set_ptr(tp, 8.0, w_g_bytes);
        cartan_set_ptr(tp, 9.0, w_u_bytes);
        cartan_set_f32(tp, 25.0, N);
        cartan_set_f32(tp, 26.0, out_stride);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    j = 0.0;
    let j_limit = chunk - 3.0;
    while (j < j_limit) {
        let j1 = j + 1.0;
        let j2 = j + 2.0;
        let j3 = j + 3.0;
        let gs0 = cartan_f32_at(g_scales, j);
        let gs1 = cartan_f32_at(g_scales, j1);
        let gs2 = cartan_f32_at(g_scales, j2);
        let gs3 = cartan_f32_at(g_scales, j3);
        let us0 = cartan_f32_at(u_scales, j);
        let us1 = cartan_f32_at(u_scales, j1);
        let us2 = cartan_f32_at(u_scales, j2);
        let us3 = cartan_f32_at(u_scales, j3);
        let grow0 = cartan_c_ptr_add(w_g_bytes, j * in_dim);
        let grow1 = cartan_c_ptr_add(w_g_bytes, j1 * in_dim);
        let grow2 = cartan_c_ptr_add(w_g_bytes, j2 * in_dim);
        let grow3 = cartan_c_ptr_add(w_g_bytes, j3 * in_dim);
        let urow0 = cartan_c_ptr_add(w_u_bytes, j * in_dim);
        let urow1 = cartan_c_ptr_add(w_u_bytes, j1 * in_dim);
        let urow2 = cartan_c_ptr_add(w_u_bytes, j2 * in_dim);
        let urow3 = cartan_c_ptr_add(w_u_bytes, j3 * in_dim);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let dg0 = cartan_simd_dot_i8_f32(grow0, in_p, gs0, in_dim);
            let du0 = cartan_simd_dot_i8_f32(urow0, in_p, us0, in_dim);
            let dg1 = cartan_simd_dot_i8_f32(grow1, in_p, gs1, in_dim);
            let du1 = cartan_simd_dot_i8_f32(urow1, in_p, us1, in_dim);
            let dg2 = cartan_simd_dot_i8_f32(grow2, in_p, gs2, in_dim);
            let du2 = cartan_simd_dot_i8_f32(urow2, in_p, us2, in_dim);
            let dg3 = cartan_simd_dot_i8_f32(grow3, in_p, gs3, in_dim);
            let du3 = cartan_simd_dot_i8_f32(urow3, in_p, us3, in_dim);
            let base_out = p * out_stride + j;
            cartan_set_f32(out_act, base_out, cartan_fast_gelu_tanh(dg0) * du0);
            cartan_set_f32(out_act, base_out + 1.0, cartan_fast_gelu_tanh(dg1) * du1);
            cartan_set_f32(out_act, base_out + 2.0, cartan_fast_gelu_tanh(dg2) * du2);
            cartan_set_f32(out_act, base_out + 3.0, cartan_fast_gelu_tanh(dg3) * du3);
            p = p + 1.0;
        }
        j = j + 4.0;
    }
    while (j < chunk) {
        let gs = cartan_f32_at(g_scales, j);
        let us = cartan_f32_at(u_scales, j);
        let grow = cartan_c_ptr_add(w_g_bytes, j * in_dim);
        let urow = cartan_c_ptr_add(w_u_bytes, j * in_dim);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let dg = cartan_simd_dot_i8_f32(grow, in_p, gs, in_dim);
            let du = cartan_simd_dot_i8_f32(urow, in_p, us, in_dim);
            cartan_set_f32(out_act, p * out_stride + j, cartan_fast_gelu_tanh(dg) * du);
            p = p + 1.0;
        }
        j = j + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_batch_int4_gemv(
    total_rows: float,
    in_dim: float,
    scales: ptr,
    w_bytes: ptr,
    in_mat: ptr,
    out_mat: ptr,
    N: float,
    out_stride: float
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 0.0;
    var r = 0.0;
    var p = 0.0;
    var spin = 0.0;
    var end_r = 0.0;
    var s = 0.0;

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, 15.0);
        cartan_set_ptr(tp, 4.0, scales);
        cartan_set_ptr(tp, 5.0, w_bytes);
        cartan_set_ptr(tp, 6.0, in_mat);
        cartan_set_ptr(tp, 7.0, out_mat);
        cartan_set_f32(tp, 25.0, N);
        cartan_set_f32(tp, 26.0, out_stride);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    let stride_bytes = in_dim * 0.5;
    r = 0.0;
    let r_limit = chunk - 3.0;
    while (r < r_limit) {
        let r1 = r + 1.0;
        let r2 = r + 2.0;
        let r3 = r + 3.0;
        let s0 = cartan_f32_at(scales, r);
        let s1 = cartan_f32_at(scales, r1);
        let s2 = cartan_f32_at(scales, r2);
        let s3 = cartan_f32_at(scales, r3);
        let row0 = cartan_c_ptr_add(w_bytes, r * stride_bytes);
        let row1 = cartan_c_ptr_add(w_bytes, r1 * stride_bytes);
        let row2 = cartan_c_ptr_add(w_bytes, r2 * stride_bytes);
        let row3 = cartan_c_ptr_add(w_bytes, r3 * stride_bytes);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let d0 = cartan_simd_dot_i4_f32(row0, in_p, s0, in_dim);
            let d1 = cartan_simd_dot_i4_f32(row1, in_p, s1, in_dim);
            let d2 = cartan_simd_dot_i4_f32(row2, in_p, s2, in_dim);
            let d3 = cartan_simd_dot_i4_f32(row3, in_p, s3, in_dim);
            let base_out = p * out_stride + r;
            cartan_set_f32(out_mat, base_out, d0);
            cartan_set_f32(out_mat, base_out + 1.0, d1);
            cartan_set_f32(out_mat, base_out + 2.0, d2);
            cartan_set_f32(out_mat, base_out + 3.0, d3);
            p = p + 1.0;
        }
        r = r + 4.0;
    }
    while (r < chunk) {
        let row_scale = cartan_f32_at(scales, r);
        let row = cartan_c_ptr_add(w_bytes, r * stride_bytes);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let dot = cartan_simd_dot_i4_f32(row, in_p, row_scale, in_dim);
            cartan_set_f32(out_mat, p * out_stride + r, dot);
            p = p + 1.0;
        }
        r = r + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_batch_int4_dual_gemv(
    total_rows: float,
    in_dim: float,
    k_scales: ptr,
    w_k_bytes: ptr,
    v_scales: ptr,
    w_v_bytes: ptr,
    in_mat: ptr,
    out_k: ptr,
    out_v: ptr,
    N: float,
    out_stride: float
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 0.0;
    var r = 0.0;
    var p = 0.0;
    var spin = 0.0;
    var end_r = 0.0;
    var s = 0.0;

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, 16.0);
        cartan_set_ptr(tp, 4.0, k_scales);
        cartan_set_ptr(tp, 5.0, w_k_bytes);
        cartan_set_ptr(tp, 6.0, in_mat);
        cartan_set_ptr(tp, 7.0, out_k);
        cartan_set_ptr(tp, 8.0, v_scales);
        cartan_set_ptr(tp, 9.0, w_v_bytes);
        cartan_set_ptr(tp, 10.0, out_v);
        cartan_set_f32(tp, 25.0, N);
        cartan_set_f32(tp, 26.0, out_stride);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    let stride_bytes = in_dim * 0.5;
    r = 0.0;
    let r_limit = chunk - 3.0;
    while (r < r_limit) {
        let r1 = r + 1.0;
        let r2 = r + 2.0;
        let r3 = r + 3.0;
        let ks0 = cartan_f32_at(k_scales, r);
        let ks1 = cartan_f32_at(k_scales, r1);
        let ks2 = cartan_f32_at(k_scales, r2);
        let ks3 = cartan_f32_at(k_scales, r3);
        let vs0 = cartan_f32_at(v_scales, r);
        let vs1 = cartan_f32_at(v_scales, r1);
        let vs2 = cartan_f32_at(v_scales, r2);
        let vs3 = cartan_f32_at(v_scales, r3);
        let k0 = cartan_c_ptr_add(w_k_bytes, r * stride_bytes);
        let k1 = cartan_c_ptr_add(w_k_bytes, r1 * stride_bytes);
        let k2 = cartan_c_ptr_add(w_k_bytes, r2 * stride_bytes);
        let k3 = cartan_c_ptr_add(w_k_bytes, r3 * stride_bytes);
        let v0 = cartan_c_ptr_add(w_v_bytes, r * stride_bytes);
        let v1 = cartan_c_ptr_add(w_v_bytes, r1 * stride_bytes);
        let v2 = cartan_c_ptr_add(w_v_bytes, r2 * stride_bytes);
        let v3 = cartan_c_ptr_add(w_v_bytes, r3 * stride_bytes);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let dk0 = cartan_simd_dot_i4_f32(k0, in_p, ks0, in_dim);
            let dv0 = cartan_simd_dot_i4_f32(v0, in_p, vs0, in_dim);
            let dk1 = cartan_simd_dot_i4_f32(k1, in_p, ks1, in_dim);
            let dv1 = cartan_simd_dot_i4_f32(v1, in_p, vs1, in_dim);
            let dk2 = cartan_simd_dot_i4_f32(k2, in_p, ks2, in_dim);
            let dv2 = cartan_simd_dot_i4_f32(v2, in_p, vs2, in_dim);
            let dk3 = cartan_simd_dot_i4_f32(k3, in_p, ks3, in_dim);
            let dv3 = cartan_simd_dot_i4_f32(v3, in_p, vs3, in_dim);
            let base_out = p * out_stride + r;
            cartan_set_f32(out_k, base_out, dk0);
            cartan_set_f32(out_v, base_out, dv0);
            cartan_set_f32(out_k, base_out + 1.0, dk1);
            cartan_set_f32(out_v, base_out + 1.0, dv1);
            cartan_set_f32(out_k, base_out + 2.0, dk2);
            cartan_set_f32(out_v, base_out + 2.0, dv2);
            cartan_set_f32(out_k, base_out + 3.0, dk3);
            cartan_set_f32(out_v, base_out + 3.0, dv3);
            p = p + 1.0;
        }
        r = r + 4.0;
    }
    while (r < chunk) {
        let ks = cartan_f32_at(k_scales, r);
        let vs = cartan_f32_at(v_scales, r);
        let k_row = cartan_c_ptr_add(w_k_bytes, r * stride_bytes);
        let v_row = cartan_c_ptr_add(w_v_bytes, r * stride_bytes);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let dk = cartan_simd_dot_i4_f32(k_row, in_p, ks, in_dim);
            let dv = cartan_simd_dot_i4_f32(v_row, in_p, vs, in_dim);
            let base_out = p * out_stride + r;
            cartan_set_f32(out_k, base_out, dk);
            cartan_set_f32(out_v, base_out, dv);
            p = p + 1.0;
        }
        r = r + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_batch_int4_geglu(
    total_rows: float,
    in_dim: float,
    g_scales: ptr,
    u_scales: ptr,
    w_g_bytes: ptr,
    w_u_bytes: ptr,
    in_mat: ptr,
    out_act: ptr,
    N: float,
    out_stride: float
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    let chunk = total_rows / 8.0;
    var ti = 0.0;
    var j = 0.0;
    var p = 0.0;
    var spin = 0.0;
    var end_r = 0.0;
    var s = 0.0;

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = total_rows; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, in_dim);
        cartan_set_f32(tp, 3.0, 17.0);
        cartan_set_ptr(tp, 4.0, g_scales);
        cartan_set_ptr(tp, 5.0, u_scales);
        cartan_set_ptr(tp, 6.0, in_mat);
        cartan_set_ptr(tp, 7.0, out_act);
        cartan_set_ptr(tp, 8.0, w_g_bytes);
        cartan_set_ptr(tp, 9.0, w_u_bytes);
        cartan_set_f32(tp, 25.0, N);
        cartan_set_f32(tp, 26.0, out_stride);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    let stride_bytes = in_dim * 0.5;
    j = 0.0;
    let j_limit = chunk - 3.0;
    while (j < j_limit) {
        let j1 = j + 1.0;
        let j2 = j + 2.0;
        let j3 = j + 3.0;
        let gs0 = cartan_f32_at(g_scales, j);
        let gs1 = cartan_f32_at(g_scales, j1);
        let gs2 = cartan_f32_at(g_scales, j2);
        let gs3 = cartan_f32_at(g_scales, j3);
        let us0 = cartan_f32_at(u_scales, j);
        let us1 = cartan_f32_at(u_scales, j1);
        let us2 = cartan_f32_at(u_scales, j2);
        let us3 = cartan_f32_at(u_scales, j3);
        let grow0 = cartan_c_ptr_add(w_g_bytes, j * stride_bytes);
        let grow1 = cartan_c_ptr_add(w_g_bytes, j1 * stride_bytes);
        let grow2 = cartan_c_ptr_add(w_g_bytes, j2 * stride_bytes);
        let grow3 = cartan_c_ptr_add(w_g_bytes, j3 * stride_bytes);
        let urow0 = cartan_c_ptr_add(w_u_bytes, j * stride_bytes);
        let urow1 = cartan_c_ptr_add(w_u_bytes, j1 * stride_bytes);
        let urow2 = cartan_c_ptr_add(w_u_bytes, j2 * stride_bytes);
        let urow3 = cartan_c_ptr_add(w_u_bytes, j3 * stride_bytes);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let dg0 = cartan_simd_dot_i4_f32(grow0, in_p, gs0, in_dim);
            let du0 = cartan_simd_dot_i4_f32(urow0, in_p, us0, in_dim);
            let dg1 = cartan_simd_dot_i4_f32(grow1, in_p, gs1, in_dim);
            let du1 = cartan_simd_dot_i4_f32(urow1, in_p, us1, in_dim);
            let dg2 = cartan_simd_dot_i4_f32(grow2, in_p, gs2, in_dim);
            let du2 = cartan_simd_dot_i4_f32(urow2, in_p, us2, in_dim);
            let dg3 = cartan_simd_dot_i4_f32(grow3, in_p, gs3, in_dim);
            let du3 = cartan_simd_dot_i4_f32(urow3, in_p, us3, in_dim);
            let base_out = p * out_stride + j;
            cartan_set_f32(out_act, base_out, cartan_fast_gelu_tanh(dg0) * du0);
            cartan_set_f32(out_act, base_out + 1.0, cartan_fast_gelu_tanh(dg1) * du1);
            cartan_set_f32(out_act, base_out + 2.0, cartan_fast_gelu_tanh(dg2) * du2);
            cartan_set_f32(out_act, base_out + 3.0, cartan_fast_gelu_tanh(dg3) * du3);
            p = p + 1.0;
        }
        j = j + 4.0;
    }
    while (j < chunk) {
        let gs = cartan_f32_at(g_scales, j);
        let us = cartan_f32_at(u_scales, j);
        let grow = cartan_c_ptr_add(w_g_bytes, j * stride_bytes);
        let urow = cartan_c_ptr_add(w_u_bytes, j * stride_bytes);
        p = 0.0;
        while (p < N) {
            let in_p = cartan_f32_ptr_add(in_mat, p * in_dim);
            let dg = cartan_simd_dot_i4_f32(grow, in_p, gs, in_dim);
            let du = cartan_simd_dot_i4_f32(urow, in_p, us, in_dim);
            cartan_set_f32(out_act, p * out_stride + j, cartan_fast_gelu_tanh(dg) * du);
            p = p + 1.0;
        }
        j = j + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_trans_pool_dispatch_lm_head(
    vocab_size: float,
    dim: float,
    w_emb: ptr,
    ics: ptr,
    in_h: ptr,
    out_logits: ptr,
    mask: ptr
) {
    if (g_trans_pool_standby == 1.0) { g_trans_pool_standby = 0.0; }
    cartan_init_transformer_scratch_buffers();
    let chunk = vocab_size / 8.0;
    var ti = 0.0;
    var r = 0.0;
    var spin = 0.0;
    var end_r = 0.0;
    var s = 0.0;
    var capped = 0.0;
    let inv_cap = 1.0 / 30.0;

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_set_f32(tp, 0.0, ti * chunk);
        end_r = (ti + 1.0) * chunk;
        if (ti == 7.0) { end_r = vocab_size; }
        cartan_set_f32(tp, 1.0, end_r);
        cartan_set_f32(tp, 2.0, dim);
        cartan_set_f32(tp, 3.0, 6.0);
        cartan_set_ptr(tp, 4.0, w_emb);
        cartan_set_ptr(tp, 5.0, ics);
        cartan_set_ptr(tp, 6.0, in_h);
        cartan_set_ptr(tp, 7.0, out_logits);
        cartan_set_ptr(tp, 8.0, mask);
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 1.0);
        ti = ti + 1.0;
    }

    r = 0.0;
    while (r < chunk) {
        if (r == 0.0 || r == 2.0 || r == 3.0 || r == 98.0 || r == 100.0 || r == 101.0 || r == 105.0 || r == 2364.0 || r == 4368.0 || r == 9731.0) {
            cartan_vec_set_f32(out_logits, r, -10000.0);
        } else if (mask != 0.0 && cartan_byte_at(mask, r) == 0.0) {
            cartan_vec_set_f32(out_logits, r, -10000.0);
        } else {
            let row_ptr = cartan_f32_ptr_add(w_emb, r * dim);
            let dot = cartan_simd_dot_f32(in_h, row_ptr, dim);
            capped = 30.0 * tanh(dot * inv_cap);
            if (ics != 0.0) {
                let ic = cartan_f32_at(ics, r);
                if (ic < 6.0 && ic > 0.0) {
                    capped = capped - 0.35 * (6.0 - ic);
                }
            }
            cartan_vec_set_f32(out_logits, r, capped);
        }
        r = r + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        spin = 0.0;
        s = cartan_atomic_f32_at(tp, 24.0);
        while (s != 2.0) {
            spin = spin + 1.0;
            if (spin > 5000.0) {
                SwitchToThread();
                spin = 0.0;
            }
            s = cartan_atomic_f32_at(tp, 24.0);
        }
        cartan_memory_fence();
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }
}

fn cartan_init_transformer_scratch_buffers() -> float {
    if (g_trans_scratch_init == 1.0) { return 1.0; }
    g_trans_x_buf = malloc(4096.0 * 4.0);
    g_trans_norm_h1 = malloc(4096.0 * 4.0);
    g_trans_q_raw = malloc(4096.0 * 4.0);
    g_trans_q_norm = malloc(4096.0 * 4.0);
    g_trans_q_rot = malloc(4096.0 * 4.0);
    g_trans_k_raw = malloc(4096.0 * 4.0);
    g_trans_k_norm = malloc(4096.0 * 4.0);
    g_trans_k_rot = malloc(4096.0 * 4.0);
    g_trans_v_raw = malloc(4096.0 * 4.0);
    g_trans_attn_out = malloc(4096.0 * 4.0);
    g_trans_scores = malloc(g_kv_cache_max_seq * 4.0);
    g_trans_o_raw = malloc(4096.0 * 4.0);
    g_trans_h1 = malloc(4096.0 * 4.0);
    g_trans_norm_h2 = malloc(4096.0 * 4.0);
    g_trans_act_buf = malloc(16384.0 * 4.0);
    g_trans_ffn_raw = malloc(4096.0 * 4.0);
    g_trans_h2 = malloc(4096.0 * 4.0);
    g_trans_ple_act = malloc(512.0 * 4.0);
    g_trans_ple_proj = malloc(4096.0 * 4.0);
    g_trans_h3 = malloc(4096.0 * 4.0);
    g_trans_thread_tasks = malloc(8.0 * 256.0);
    g_trans_thread_handles = malloc(8.0 * 8.0);

    let max_n = 4096.0;
    g_trans_b_norm_h1 = malloc(max_n * 2560.0 * 4.0);
    g_trans_b_q = malloc(max_n * 2560.0 * 4.0);
    g_trans_b_k = malloc(max_n * 2048.0 * 4.0);
    g_trans_b_v = malloc(max_n * 2048.0 * 4.0);
    g_trans_b_attn_out = malloc(max_n * 2560.0 * 4.0);
    g_trans_b_h1 = malloc(max_n * 2560.0 * 4.0);
    g_trans_b_norm_h2 = malloc(max_n * 2560.0 * 4.0);
    g_trans_b_act = malloc(max_n * 10240.0 * 4.0);
    g_trans_b_ffn = malloc(max_n * 2560.0 * 4.0);
    g_trans_b_ple_act = malloc(max_n * 512.0 * 4.0);
    g_trans_b_ple_proj = malloc(max_n * 2560.0 * 4.0);
    g_trans_b_scratch_init = 1.0;

    var ti = 0.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        cartan_atomic_set_f32(tp, 24.0, 0.0);
        ti = ti + 1.0;
    }

    ti = 1.0;
    while (ti < 8.0) {
        let tp = cartan_f32_ptr_add(g_trans_thread_tasks, ti * 64.0);
        let h = CreateThread(0.0, 0.0, cartan_trans_pool_worker_main, tp, 0.0, 0.0);
        cartan_set_ptr(g_trans_thread_handles, ti, h);
        ti = ti + 1.0;
    }

    g_trans_scratch_init = 1.0;
    return 1.0;
}

// -----------------------------------------------------------------------------
// Pure Native CARTAN Sovereign Manifold Decoder Layer Forward Kernel
// Direct AVX2 SIMD FMA execution with zero intermediate allocations
// -----------------------------------------------------------------------------
fn cartan_manifold_layer_forward_native(
    h_out_vec: ptr,
    h_in_vec: ptr,
    layer_buf: ptr,
    pos: float,
    seq_len: float,
    tok_id: float
) -> float {
    if (h_out_vec == 0.0 || h_in_vec == 0.0 || layer_buf == 0.0) { return 0.0; }
    cartan_init_transformer_scratch_buffers();
    cartan_kv_cache_init();

    let layer_idx = cartan_f32_at(layer_buf, 1.0);
    var head_dim = cartan_f32_at(layer_buf, 2.0);
    if (head_dim <= 0.0) { head_dim = 256.0; }
    var rope_theta = cartan_f32_at(layer_buf, 3.0);
    if (rope_theta <= 0.0) { rope_theta = 10000.0; }
    if (g_kv_cache_max_seq > 2048.0) {
        rope_theta = rope_theta * (g_kv_cache_max_seq / 2048.0);
    }
    var layer_scalar = cartan_f32_at(layer_buf, 4.0);
    if (layer_scalar == 0.0) { layer_scalar = 1.0; }
    let has_ple = cartan_f32_at(layer_buf, 5.0);
    let dim = cartan_f32_at(layer_buf, 6.0);
    let inter_dim = cartan_f32_at(layer_buf, 7.0);
    let q_dim = cartan_f32_at(layer_buf, 8.0);
    let kv_dim = cartan_f32_at(layer_buf, 9.0);
    let ple_dim = cartan_f32_at(layer_buf, 10.0);

    let q_heads = q_dim / head_dim;
    var kv_heads = kv_dim / head_dim;
    if (kv_heads <= 0.0) { kv_heads = 1.0; }
    let heads_per_kv = q_heads / kv_heads;
    var hd = 0.0;

    let is_int8 = cartan_f32_at(layer_buf, 11.0);

    var w_in_norm = 0.0;
    var w_q_norm = 0.0;
    var w_k_norm = 0.0;
    var w_post_attn = 0.0;
    var w_pre_ffn = 0.0;
    var w_post_ffn = 0.0;
    var w_ple_norm = 0.0;

    var q_scales = 0.0; var w_q_bytes = 0.0;
    var k_scales = 0.0; var w_k_bytes = 0.0;
    var v_scales = 0.0; var w_v_bytes = 0.0;
    var o_scales = 0.0; var w_o_bytes = 0.0;
    var gate_scales = 0.0; var w_gate_bytes = 0.0;
    var up_scales = 0.0; var w_up_bytes = 0.0;
    var down_scales = 0.0; var w_down_bytes = 0.0;
    var ple_gate_scales = 0.0; var w_ple_gate_bytes = 0.0;
    var ple_proj_scales = 0.0; var w_ple_proj_bytes = 0.0;

    var w_q = 0.0; var w_k = 0.0; var w_v = 0.0; var w_o = 0.0;
    var w_gate = 0.0; var w_up = 0.0; var w_down = 0.0;
    var w_ple_gate = 0.0; var w_ple_proj = 0.0;

    if (is_int8 == 1.0 || is_int8 == 2.0) {
        var w_stride = 1.0;
        if (is_int8 == 2.0) {
            w_stride = 0.5;
        }
        w_in_norm = cartan_c_ptr_add(layer_buf, 64.0);
        var bo = 64.0 + dim * 4.0;

        q_scales = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + q_dim * 4.0;
        w_q_bytes = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + q_dim * dim * w_stride;

        k_scales = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + kv_dim * 4.0;
        w_k_bytes = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + kv_dim * dim * w_stride;

        v_scales = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + kv_dim * 4.0;
        w_v_bytes = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + kv_dim * dim * w_stride;

        o_scales = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + dim * 4.0;
        w_o_bytes = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + dim * q_dim * w_stride;

        w_q_norm = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + 512.0 * 4.0;
        w_k_norm = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + 512.0 * 4.0;

        w_post_attn = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + dim * 4.0;
        w_pre_ffn = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + dim * 4.0;

        gate_scales = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + inter_dim * 4.0;
        w_gate_bytes = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + inter_dim * dim * w_stride;

        up_scales = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + inter_dim * 4.0;
        w_up_bytes = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + inter_dim * dim * w_stride;

        down_scales = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + dim * 4.0;
        w_down_bytes = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + dim * inter_dim * w_stride;

        w_post_ffn = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + dim * 4.0;

        ple_gate_scales = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + ple_dim * 4.0;
        w_ple_gate_bytes = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + ple_dim * dim * w_stride;

        ple_proj_scales = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + dim * 4.0;
        w_ple_proj_bytes = cartan_c_ptr_add(layer_buf, bo);
        bo = bo + dim * ple_dim * w_stride;

        w_ple_norm = cartan_c_ptr_add(layer_buf, bo);
    } else {
        let off_in_norm = 16.0;
        let off_w_q = 2576.0;
        let off_w_k = off_w_q + q_dim * dim;
        let off_w_v = off_w_k + kv_dim * dim;
        let off_w_o = off_w_v + kv_dim * dim;
        let off_q_norm = off_w_o + dim * q_dim;
        let off_k_norm = off_q_norm + 512.0;
        let off_post_attn_norm = off_k_norm + 512.0;
        let off_pre_ffn_norm = off_post_attn_norm + dim;
        let off_gate_proj = off_pre_ffn_norm + dim;
        let off_up_proj = off_gate_proj + inter_dim * dim;
        let off_down_proj = off_up_proj + inter_dim * dim;
        let off_post_ffn_norm = off_down_proj + dim * inter_dim;
        let off_ple_gate = off_post_ffn_norm + dim;
        let off_ple_proj = off_ple_gate + ple_dim * dim;
        let off_ple_norm = off_ple_proj + dim * ple_dim;

        w_in_norm = cartan_f32_ptr_add(layer_buf, off_in_norm);
        w_q = cartan_f32_ptr_add(layer_buf, off_w_q);
        w_k = cartan_f32_ptr_add(layer_buf, off_w_k);
        w_v = cartan_f32_ptr_add(layer_buf, off_w_v);
        w_o = cartan_f32_ptr_add(layer_buf, off_w_o);
        w_q_norm = cartan_f32_ptr_add(layer_buf, off_q_norm);
        w_k_norm = cartan_f32_ptr_add(layer_buf, off_k_norm);
        w_post_attn = cartan_f32_ptr_add(layer_buf, off_post_attn_norm);
        w_pre_ffn = cartan_f32_ptr_add(layer_buf, off_pre_ffn_norm);
        w_gate = cartan_f32_ptr_add(layer_buf, off_gate_proj);
        w_up = cartan_f32_ptr_add(layer_buf, off_up_proj);
        w_down = cartan_f32_ptr_add(layer_buf, off_down_proj);
        w_post_ffn = cartan_f32_ptr_add(layer_buf, off_post_ffn_norm);
        w_ple_gate = cartan_f32_ptr_add(layer_buf, off_ple_gate);
        w_ple_proj = cartan_f32_ptr_add(layer_buf, off_ple_proj);
        w_ple_norm = cartan_f32_ptr_add(layer_buf, off_ple_norm);
    }

    // Extract input vector into scratch float buffer
    var d = 0.0;
    while (d < dim) {
        cartan_set_f32(g_trans_x_buf, d, cartan_vec_get_f32(h_in_vec, d));
        d = d + 1.0;
    }

    // 1. Pre-Attention RMSNorm: bar(h)_1 = RMSNorm(h, w_in_norm)
    let sum_sq = cartan_simd_dot_f32(g_trans_x_buf, g_trans_x_buf, dim);
    let inv_rms1 = 1.0 / sqrt((sum_sq / dim) + 0.000001);
    d = 0.0;
    while (d < dim) {
        let val = cartan_f32_at(g_trans_x_buf, d);
        let w = cartan_f32_at(w_in_norm, d);
        cartan_set_f32(g_trans_norm_h1, d, val * inv_rms1 * w);
        d = d + 1.0;
    }

    // 2. Q Projections (Persistent Worker Thread Pool GEMV)
    if (is_int8 == 2.0) {
        cartan_trans_pool_dispatch(12.0, q_dim, dim, q_scales, w_q_bytes, g_trans_norm_h1, g_trans_q_raw);
    } else if (is_int8 == 1.0) {
        cartan_trans_pool_dispatch(7.0, q_dim, dim, q_scales, w_q_bytes, g_trans_norm_h1, g_trans_q_raw);
    } else {
        cartan_trans_pool_dispatch(2.0, q_dim, dim, w_q, g_trans_null_ptr, g_trans_norm_h1, g_trans_q_raw);
    }

    // 3. Per-Head Q-Norm
    var qh = 0.0;
    while (qh < q_heads) {
        let qh_base = qh * head_dim;
        let q_head_ptr = cartan_f32_ptr_add(g_trans_q_raw, qh_base);
        let h_sq = cartan_simd_dot_f32(q_head_ptr, q_head_ptr, head_dim);
        let inv_q_rms = 1.0 / sqrt((h_sq / head_dim) + 0.000001);
        hd = 0.0;
        while (hd < head_dim) {
            let v = cartan_f32_at(g_trans_q_raw, qh_base + hd);
            let w = cartan_f32_at(w_q_norm, hd);
            cartan_set_f32(g_trans_q_norm, qh_base + hd, v * inv_q_rms * w);
            hd = hd + 1.0;
        }
        qh = qh + 1.0;
    }

    let half = head_dim / 2.0;
    let is_global = (fmod(layer_idx + 1.0, 6.0) == 0.0);
    var rope_angles = half;
    if (is_global > 0.0) {
        rope_angles = 64.0;
    }

    // 4. RoPE on Q heads (Manifold rotate_half with proportional rotary factor)
    qh = 0.0;
    while (qh < q_heads) {
        let qh_base = qh * head_dim;
        var k = 0.0;
        while (k < half) {
            let x0 = cartan_f32_at(g_trans_q_norm, qh_base + k);
            let x1 = cartan_f32_at(g_trans_q_norm, qh_base + k + half);
            var c = 1.0;
            var s = 0.0;
            if (k < rope_angles) {
                let exponent = (k * 2.0) / head_dim;
                let freq = 1.0 / pow(rope_theta, exponent);
                let theta = pos * freq;
                c = cos(theta);
                s = sin(theta);
            }
            cartan_set_f32(g_trans_q_rot, qh_base + k, x0 * c - x1 * s);
            cartan_set_f32(g_trans_q_rot, qh_base + k + half, x1 * c + x0 * s);
            k = k + 1.0;
        }
        qh = qh + 1.0;
    }
    let is_kv_shared = (layer_idx >= 24.0);
    var kv_source_layer = layer_idx;
    if (is_kv_shared > 0.0) {
        if (is_global > 0.0) {
            kv_source_layer = 23.0;
        } else {
            kv_source_layer = 22.0;
        }
    }

    if (is_kv_shared == 0.0) {
        if (is_int8 == 2.0) {
            cartan_trans_pool_dispatch_int4_dual_gemv(kv_dim, dim, k_scales, w_k_bytes, v_scales, w_v_bytes, g_trans_norm_h1, g_trans_k_raw, g_trans_v_raw);
        } else if (is_int8 == 1.0) {
            cartan_trans_pool_dispatch(7.0, kv_dim, dim, k_scales, w_k_bytes, g_trans_norm_h1, g_trans_k_raw);
            cartan_trans_pool_dispatch(7.0, kv_dim, dim, v_scales, w_v_bytes, g_trans_norm_h1, g_trans_v_raw);
        } else {
            cartan_trans_pool_dispatch(2.0, kv_dim, dim, w_k, g_trans_null_ptr, g_trans_norm_h1, g_trans_k_raw);
            cartan_trans_pool_dispatch(2.0, kv_dim, dim, w_v, g_trans_null_ptr, g_trans_norm_h1, g_trans_v_raw);
        }

        var kvh = 0.0;
        while (kvh < kv_heads) {
            let kh_base = kvh * head_dim;
            let k_head_ptr = cartan_f32_ptr_add(g_trans_k_raw, kh_base);
            let kh_sq = cartan_simd_dot_f32(k_head_ptr, k_head_ptr, head_dim);
            let inv_k_rms = 1.0 / sqrt((kh_sq / head_dim) + 0.000001);
            hd = 0.0;
            while (hd < head_dim) {
                let v = cartan_f32_at(g_trans_k_raw, kh_base + hd);
                let w = cartan_f32_at(w_k_norm, hd);
                cartan_set_f32(g_trans_k_norm, kh_base + hd, v * inv_k_rms * w);
                hd = hd + 1.0;
            }
            kvh = kvh + 1.0;
        }

        kvh = 0.0;
        while (kvh < kv_heads) {
            let kh_base = kvh * head_dim;
            var k = 0.0;
            while (k < half) {
                let x0 = cartan_f32_at(g_trans_k_norm, kh_base + k);
                let x1 = cartan_f32_at(g_trans_k_norm, kh_base + k + half);
                var c = 1.0;
                var s = 0.0;
                if (k < rope_angles) {
                    let exponent = (k * 2.0) / head_dim;
                    let freq = 1.0 / pow(rope_theta, exponent);
                    let theta = pos * freq;
                    c = cos(theta);
                    s = sin(theta);
                }
                cartan_set_f32(g_trans_k_rot, kh_base + k, x0 * c - x1 * s);
                cartan_set_f32(g_trans_k_rot, kh_base + k + half, x1 * c + x0 * s);
                k = k + 1.0;
            }
            kvh = kvh + 1.0;
        }

        // 5. Append to Contiguous KV Cache Arena
        let k_layer_base = cartan_kv_cache_get_k(layer_idx);
        let v_layer_base = cartan_kv_cache_get_v(layer_idx);
        if (k_layer_base != 0.0 && v_layer_base != 0.0 && layer_idx >= 0.0 && layer_idx < 24.0 && pos >= 0.0 && pos < g_kv_cache_max_seq) {
            let k_dst = cartan_f32_ptr_add(k_layer_base, pos * kv_dim);
            let v_dst = cartan_f32_ptr_add(v_layer_base, pos * kv_dim);
            cartan_c_memcpy(k_dst, g_trans_k_rot, kv_dim * 4.0);

            // Manifold v_norm: unit RMS normalization per KV head (with_scale=False)
            var h = 0.0;
            while (h < kv_heads) {
                let v_base = h * head_dim;
                let v_head_ptr = cartan_f32_ptr_add(g_trans_v_raw, v_base);
                let v_sq = cartan_simd_dot_f32(v_head_ptr, v_head_ptr, head_dim);
                let inv_v_rms = 1.0 / sqrt((v_sq / head_dim) + 0.000001);
                let v_dst_h = cartan_f32_ptr_add(v_dst, v_base);
                hd = 0.0;
                while (hd < head_dim) {
                    let val = cartan_f32_at(g_trans_v_raw, v_base + hd);
                    cartan_set_f32(v_dst_h, hd, val * inv_v_rms);
                    hd = hd + 1.0;
                }
                h = h + 1.0;
            }
        }
    }

    // 6. GQA Causal Attention (reusing KV from kv_source_layer for shared layers)
    let k_cache = cartan_kv_cache_get_k(kv_source_layer);
    let v_cache = cartan_kv_cache_get_v(kv_source_layer);
    var max_seq = pos + 1.0;
    if (max_seq > g_kv_cache_max_seq) { max_seq = g_kv_cache_max_seq; }

    var sink_limit = g_attention_sink_tokens;
    if (sink_limit > max_seq) { sink_limit = max_seq; }
    var win_start = 0.0;
    let win_size = g_attention_window_size;
    if (win_size > 0.0 && max_seq > (sink_limit + win_size)) {
        win_start = max_seq - win_size;
    }
    var p1_limit = max_seq;
    if (win_start > 0.0) { p1_limit = sink_limit; }

    qh = 0.0;
    while (qh < q_heads) {
        let kvh = floor(qh / heads_per_kv);
        let q_h = cartan_f32_ptr_add(g_trans_q_rot, qh * head_dim);
        var max_score = -1000000000.0;

        // Phase 1a: Attention Sinks (0 .. p1_limit)
        var t = 0.0;
        while (t < p1_limit) {
            var dot = -10000.0;
            if (k_cache != 0.0) {
                let k_ht = cartan_f32_ptr_add(k_cache, t * kv_dim + kvh * head_dim);
                if (cartan_f32_at(k_ht, 0.0) > -9999.0) {
                    dot = cartan_simd_dot_f32(q_h, k_ht, head_dim);
                }
            }
            cartan_set_f32(g_trans_scores, t, dot);
            if (dot > max_score) { max_score = dot; }
            t = t + 1.0;
        }

        // Phase 1b: Local Sliding Window (win_start .. max_seq)
        if (win_start > 0.0) {
            t = win_start;
            while (t < max_seq) {
                var dot = -10000.0;
                if (k_cache != 0.0) {
                    let k_ht = cartan_f32_ptr_add(k_cache, t * kv_dim + kvh * head_dim);
                    if (cartan_f32_at(k_ht, 0.0) > -9999.0) {
                        dot = cartan_simd_dot_f32(q_h, k_ht, head_dim);
                    }
                }
                cartan_set_f32(g_trans_scores, t, dot);
                if (dot > max_score) { max_score = dot; }
                t = t + 1.0;
            }
        }

        var sum_exp = 0.0;
        // Phase 2a: Sinks Exponent
        t = 0.0;
        while (t < p1_limit) {
            let ep = exp(cartan_f32_at(g_trans_scores, t) - max_score);
            cartan_set_f32(g_trans_scores, t, ep);
            sum_exp = sum_exp + ep;
            t = t + 1.0;
        }

        // Phase 2b: Sliding Window Exponent
        if (win_start > 0.0) {
            t = win_start;
            while (t < max_seq) {
                let ep = exp(cartan_f32_at(g_trans_scores, t) - max_score);
                cartan_set_f32(g_trans_scores, t, ep);
                sum_exp = sum_exp + ep;
                t = t + 1.0;
            }
        }
        var inv_sum = 1.0;
        if (sum_exp > 0.000000000001) { inv_sum = 1.0 / sum_exp; }

        let out_h = cartan_f32_ptr_add(g_trans_attn_out, qh * head_dim);
        hd = 0.0;
        while (hd < head_dim) {
            cartan_set_f32(out_h, hd, 0.0);
            hd = hd + 1.0;
        }
        if (v_cache != 0.0) {
            let hd_unroll_limit = head_dim - 3.0;

            // Phase 3a: Sinks V Accumulation
            t = 0.0;
            while (t < p1_limit) {
                let p_t = cartan_f32_at(g_trans_scores, t) * inv_sum;
                if (p_t > 0.000000001) {
                    let v_ht = cartan_f32_ptr_add(v_cache, t * kv_dim + kvh * head_dim);
                    hd = 0.0;
                    while (hd < hd_unroll_limit) {
                        let hd1 = hd + 1.0;
                        let hd2 = hd + 2.0;
                        let hd3 = hd + 3.0;
                        let o0 = cartan_f32_at(out_h, hd) + p_t * cartan_f32_at(v_ht, hd);
                        let o1 = cartan_f32_at(out_h, hd1) + p_t * cartan_f32_at(v_ht, hd1);
                        let o2 = cartan_f32_at(out_h, hd2) + p_t * cartan_f32_at(v_ht, hd2);
                        let o3 = cartan_f32_at(out_h, hd3) + p_t * cartan_f32_at(v_ht, hd3);
                        cartan_set_f32(out_h, hd, o0);
                        cartan_set_f32(out_h, hd1, o1);
                        cartan_set_f32(out_h, hd2, o2);
                        cartan_set_f32(out_h, hd3, o3);
                        hd = hd + 4.0;
                    }
                    while (hd < head_dim) {
                        let cur = cartan_f32_at(out_h, hd);
                        let val = cartan_f32_at(v_ht, hd);
                        cartan_set_f32(out_h, hd, cur + p_t * val);
                        hd = hd + 1.0;
                    }
                }
                t = t + 1.0;
            }

            // Phase 3b: Sliding Window V Accumulation
            if (win_start > 0.0) {
                t = win_start;
                while (t < max_seq) {
                    let p_t = cartan_f32_at(g_trans_scores, t) * inv_sum;
                    if (p_t > 0.000000001) {
                        let v_ht = cartan_f32_ptr_add(v_cache, t * kv_dim + kvh * head_dim);
                        hd = 0.0;
                        while (hd < hd_unroll_limit) {
                            let hd1 = hd + 1.0;
                            let hd2 = hd + 2.0;
                            let hd3 = hd + 3.0;
                            let o0 = cartan_f32_at(out_h, hd) + p_t * cartan_f32_at(v_ht, hd);
                            let o1 = cartan_f32_at(out_h, hd1) + p_t * cartan_f32_at(v_ht, hd1);
                            let o2 = cartan_f32_at(out_h, hd2) + p_t * cartan_f32_at(v_ht, hd2);
                            let o3 = cartan_f32_at(out_h, hd3) + p_t * cartan_f32_at(v_ht, hd3);
                            cartan_set_f32(out_h, hd, o0);
                            cartan_set_f32(out_h, hd1, o1);
                            cartan_set_f32(out_h, hd2, o2);
                            cartan_set_f32(out_h, hd3, o3);
                            hd = hd + 4.0;
                        }
                        while (hd < head_dim) {
                            let cur = cartan_f32_at(out_h, hd);
                            let val = cartan_f32_at(v_ht, hd);
                            cartan_set_f32(out_h, hd, cur + p_t * val);
                            hd = hd + 1.0;
                        }
                    }
                    t = t + 1.0;
                }
            }
        }
        qh = qh + 1.0;
    }

    // 7. Output Projection W_o (Persistent Worker Thread Pool GEMV)
    if (is_int8 == 2.0) {
        cartan_trans_pool_dispatch(12.0, dim, q_dim, o_scales, w_o_bytes, g_trans_attn_out, g_trans_o_raw);
    } else if (is_int8 == 1.0) {
        cartan_trans_pool_dispatch(7.0, dim, q_dim, o_scales, w_o_bytes, g_trans_attn_out, g_trans_o_raw);
    } else {
        cartan_trans_pool_dispatch(2.0, dim, q_dim, w_o, g_trans_null_ptr, g_trans_attn_out, g_trans_o_raw);
    }
    let o_sq_sum = cartan_simd_dot_f32(g_trans_o_raw, g_trans_o_raw, dim);
    let inv_o_rms = 1.0 / sqrt((o_sq_sum / dim) + 0.000001);
    d = 0.0;
    while (d < dim) {
        let x = cartan_f32_at(g_trans_x_buf, d);
        let o = cartan_f32_at(g_trans_o_raw, d);
        let w = cartan_f32_at(w_post_attn, d);
        cartan_set_f32(g_trans_h1, d, x + o * inv_o_rms * w);
        d = d + 1.0;
    }

    // 8. Pre-FFN RMSNorm
    let h1_sq_sum = cartan_simd_dot_f32(g_trans_h1, g_trans_h1, dim);
    let inv_h1_rms = 1.0 / sqrt((h1_sq_sum / dim) + 0.000001);
    d = 0.0;
    while (d < dim) {
        let val = cartan_f32_at(g_trans_h1, d);
        let w = cartan_f32_at(w_pre_ffn, d);
        cartan_set_f32(g_trans_norm_h2, d, val * inv_h1_rms * w);
        d = d + 1.0;
    }

    // 9. GeGLU MLP: Hardware Full-VRAM Resident Acceleration with CPU Multithreaded Fallback
    var gpu_done = 0.0;
    if (is_int8 == 2.0 && g_trans_gpu_int4_ready == 1.0 && layer_idx >= 0.0 && layer_idx < 42.0) {
        gpu_done = cartan_transformer_dispatch_gpu_layer_int4(layer_idx, g_trans_norm_h2, g_trans_ffn_raw, dim, inter_dim);
    } else if (is_int8 == 1.0 && g_trans_gpu_int8_ready == 1.0 && layer_idx >= 0.0 && layer_idx < 42.0) {
        gpu_done = cartan_transformer_dispatch_gpu_layer_int8(layer_idx, g_trans_norm_h2, g_trans_ffn_raw, dim, inter_dim);
    }
    if (gpu_done == 0.0) {
        if (is_int8 == 2.0) {
            cartan_trans_pool_dispatch_int4_geglu(inter_dim, dim, gate_scales, up_scales, w_gate_bytes, w_up_bytes, g_trans_norm_h2, g_trans_act_buf);
            cartan_trans_pool_dispatch(12.0, dim, inter_dim, down_scales, w_down_bytes, g_trans_act_buf, g_trans_ffn_raw);
        } else if (is_int8 == 1.0) {
            cartan_trans_pool_dispatch_int8_geglu(inter_dim, dim, gate_scales, up_scales, w_gate_bytes, w_up_bytes, g_trans_norm_h2, g_trans_act_buf);
            cartan_trans_pool_dispatch(7.0, dim, inter_dim, down_scales, w_down_bytes, g_trans_act_buf, g_trans_ffn_raw);
        } else {
            cartan_trans_pool_dispatch(1.0, inter_dim, dim, w_gate, w_up, g_trans_norm_h2, g_trans_act_buf);
            cartan_trans_pool_dispatch(2.0, dim, inter_dim, w_down, g_trans_null_ptr, g_trans_act_buf, g_trans_ffn_raw);
        }
    }

    let ffn_sq_sum = cartan_simd_dot_f32(g_trans_ffn_raw, g_trans_ffn_raw, dim);
    let inv_ffn_rms = 1.0 / sqrt((ffn_sq_sum / dim) + 0.000001);
    d = 0.0;
    while (d < dim) {
        let h1_val = cartan_f32_at(g_trans_h1, d);
        let ffn_val = cartan_f32_at(g_trans_ffn_raw, d);
        let w = cartan_f32_at(w_post_ffn, d);
        cartan_set_f32(g_trans_h2, d, h1_val + ffn_val * inv_ffn_rms * w);
        d = d + 1.0;
    }

    // 10. Per-Layer Embedding (PLE) Gating
    if (has_ple > 0.0 && tok_id >= 0.0 && tok_id < 262144.0) {
        let pli_l = cartan_get_cached_pli(layer_idx, tok_id);
        if (pli_l != 0.0) {
            if (is_int8 == 2.0) {
                var p = 0.0;
                let ple_stride = dim * 0.5;
                while (p < ple_dim) {
                    let ps = cartan_f32_at(ple_gate_scales, p);
                    let g_row = cartan_c_ptr_add(w_ple_gate_bytes, p * ple_stride);
                    let dot_gate = cartan_simd_dot_i4_f32(g_row, g_trans_h2, ps, dim);
                    let pli_val = cartan_f32_at(pli_l, p);
                    cartan_set_f32(g_trans_ple_act, p, cartan_fast_gelu_tanh(dot_gate) * pli_val);
                    p = p + 1.0;
                }
                var ple_sq = 0.0;
                d = 0.0;
                let ple_proj_stride = ple_dim * 0.5;
                while (d < dim) {
                    let ps = cartan_f32_at(ple_proj_scales, d);
                    let p_row = cartan_c_ptr_add(w_ple_proj_bytes, d * ple_proj_stride);
                    let dot_p = cartan_simd_dot_i4_f32(p_row, g_trans_ple_act, ps, ple_dim);
                    cartan_set_f32(g_trans_ple_proj, d, dot_p);
                    ple_sq = ple_sq + dot_p * dot_p;
                    d = d + 1.0;
                }
                let inv_ple_rms = 1.0 / sqrt((ple_sq / dim) + 0.000001);
                d = 0.0;
                while (d < dim) {
                    let h2_val = cartan_f32_at(g_trans_h2, d);
                    let proj_val = cartan_f32_at(g_trans_ple_proj, d);
                    let norm_val = cartan_f32_at(w_ple_norm, d);
                    cartan_set_f32(g_trans_h3, d, h2_val + proj_val * inv_ple_rms * norm_val);
                    d = d + 1.0;
                }
            } else if (is_int8 == 1.0) {
                var p = 0.0;
                while (p < ple_dim) {
                    let ps = cartan_f32_at(ple_gate_scales, p);
                    let g_row = cartan_c_ptr_add(w_ple_gate_bytes, p * dim);
                    let dot_gate = cartan_simd_dot_i8_f32(g_row, g_trans_h2, ps, dim);
                    let pli_val = cartan_f32_at(pli_l, p);
                    cartan_set_f32(g_trans_ple_act, p, cartan_fast_gelu_tanh(dot_gate) * pli_val);
                    p = p + 1.0;
                }
                var ple_sq = 0.0;
                d = 0.0;
                while (d < dim) {
                    let ps = cartan_f32_at(ple_proj_scales, d);
                    let p_row = cartan_c_ptr_add(w_ple_proj_bytes, d * ple_dim);
                    let dot_p = cartan_simd_dot_i8_f32(p_row, g_trans_ple_act, ps, ple_dim);
                    cartan_set_f32(g_trans_ple_proj, d, dot_p);
                    ple_sq = ple_sq + dot_p * dot_p;
                    d = d + 1.0;
                }
                let inv_ple_rms = 1.0 / sqrt((ple_sq / dim) + 0.000001);
                d = 0.0;
                while (d < dim) {
                    let h2_val = cartan_f32_at(g_trans_h2, d);
                    let proj_val = cartan_f32_at(g_trans_ple_proj, d);
                    let norm_val = cartan_f32_at(w_ple_norm, d);
                    cartan_set_f32(g_trans_h3, d, h2_val + proj_val * inv_ple_rms * norm_val);
                    d = d + 1.0;
                }
            } else {
                var p = 0.0;
                while (p < ple_dim) {
                    let g_row = cartan_f32_ptr_add(w_ple_gate, p * dim);
                    let dot_gate = cartan_simd_dot_f32(g_row, g_trans_h2, dim);
                    let pli_val = cartan_f32_at(pli_l, p);
                    cartan_set_f32(g_trans_ple_act, p, cartan_fast_gelu_tanh(dot_gate) * pli_val);
                    p = p + 1.0;
                }
                var ple_sq = 0.0;
                d = 0.0;
                while (d < dim) {
                    let p_row = cartan_f32_ptr_add(w_ple_proj, d * ple_dim);
                    let dot_p = cartan_simd_dot_f32(p_row, g_trans_ple_act, ple_dim);
                    cartan_set_f32(g_trans_ple_proj, d, dot_p);
                    ple_sq = ple_sq + dot_p * dot_p;
                    d = d + 1.0;
                }
                let inv_ple_rms = 1.0 / sqrt((ple_sq / dim) + 0.000001);
                d = 0.0;
                while (d < dim) {
                    let h2_val = cartan_f32_at(g_trans_h2, d);
                    let proj_val = cartan_f32_at(g_trans_ple_proj, d);
                    let norm_val = cartan_f32_at(w_ple_norm, d);
                    cartan_set_f32(g_trans_h3, d, h2_val + proj_val * inv_ple_rms * norm_val);
                    d = d + 1.0;
                }
            }
        } else {
            d = 0.0;
            while (d < dim) {
                cartan_set_f32(g_trans_h3, d, cartan_f32_at(g_trans_h2, d));
                d = d + 1.0;
            }
        }
    } else {
        d = 0.0;
        while (d < dim) {
            cartan_set_f32(g_trans_h3, d, cartan_f32_at(g_trans_h2, d));
            d = d + 1.0;
        }
    }

    // 11. Layer Scalar Scaling & CARTAN Vector Output
    d = 0.0;
    while (d < dim) {
        cartan_vec_set_f32(h_out_vec, d, cartan_f32_at(g_trans_h3, d) * layer_scalar);
        d = d + 1.0;
    }
    return 1.0;
}

// -----------------------------------------------------------------------------
// 12. Ultra-Fast In-Place Sovereign Manifold Decoder Layer Forward from Raw Binary Buffer
// Pure Native CARTAN decoder using hardware SIMD FMA dot products
// -----------------------------------------------------------------------------
fn cartan_manifold_layer_forward_raw(
    h: ptr,
    layer_buf: ptr,
    pos: float,
    seq_len: float,
    k_cache: ptr,
    v_cache: ptr
) -> ptr {
    if (h == 0.0 || layer_buf == 0.0) { return 0.0; }
    let dim = cartan_f32_at(layer_buf, 6.0);
    let h_out = cartan_tensor_alloc(dim);
    cartan_manifold_layer_forward_native(h_out, h, layer_buf, pos, seq_len, g_current_token_id);
    return h_out;
}

// -----------------------------------------------------------------------------
// 13b. High-Throughput Batched INT8 Sequence Prefill Layer Forward Kernel
// Row-outer INT8 execution: Streams quantized 8-bit weight matrices across N tokens
// with AVX2 SIMD dot-product accumulation, reducing host DDR5 bandwidth by 4x.
// -----------------------------------------------------------------------------
fn cartan_manifold_layer_forward_batch_int8(
    token_states: ptr,
    layer_buf: ptr,
    prompt_tokens: ptr,
    num_tokens: float,
    start_pos: float
) -> float {
    if (token_states == 0.0 || layer_buf == 0.0 || prompt_tokens == 0.0 || num_tokens <= 0.0) {
        return 0.0;
    }
    cartan_init_transformer_scratch_buffers();
    cartan_kv_cache_init();

    let layer_idx = cartan_f32_at(layer_buf, 1.0);
    var head_dim = cartan_f32_at(layer_buf, 2.0);
    if (head_dim <= 0.0) { head_dim = 256.0; }
    var rope_theta = cartan_f32_at(layer_buf, 3.0);
    if (rope_theta <= 0.0) { rope_theta = 10000.0; }
    if (g_kv_cache_max_seq > 2048.0) {
        rope_theta = rope_theta * (g_kv_cache_max_seq / 2048.0);
    }
    var layer_scalar = cartan_f32_at(layer_buf, 4.0);
    if (layer_scalar == 0.0) { layer_scalar = 1.0; }
    let has_ple = cartan_f32_at(layer_buf, 5.0);
    let dim = cartan_f32_at(layer_buf, 6.0);
    let inter_dim = cartan_f32_at(layer_buf, 7.0);
    let q_dim = cartan_f32_at(layer_buf, 8.0);
    let kv_dim = cartan_f32_at(layer_buf, 9.0);
    let ple_dim = cartan_f32_at(layer_buf, 10.0);

    let q_heads = q_dim / head_dim;
    var kv_heads = kv_dim / head_dim;
    if (kv_heads <= 0.0) { kv_heads = 1.0; }
    let heads_per_kv = q_heads / kv_heads;

    let half = head_dim / 2.0;
    let is_global = (fmod(layer_idx + 1.0, 6.0) == 0.0);
    var rope_angles = half;
    if (is_global > 0.0) {
        rope_angles = 64.0;
    }

    let w_in_norm = cartan_c_ptr_add(layer_buf, 64.0);
    var bo = 64.0 + dim * 4.0;

    let q_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + q_dim * 4.0;
    let w_q_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + q_dim * dim;

    let k_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + kv_dim * 4.0;
    let w_k_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + kv_dim * dim;

    let v_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + kv_dim * 4.0;
    let w_v_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + kv_dim * dim;

    let o_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;
    let w_o_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * q_dim;

    let w_q_norm = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + 512.0 * 4.0;
    let w_k_norm = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + 512.0 * 4.0;

    let w_post_attn = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;
    let w_pre_ffn = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;

    let gate_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + inter_dim * 4.0;
    let w_gate_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + inter_dim * dim;

    let up_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + inter_dim * 4.0;
    let w_up_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + inter_dim * dim;

    let down_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;
    let w_down_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * inter_dim;

    let w_post_ffn = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;

    let ple_gate_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + ple_dim * 4.0;
    let w_ple_gate_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + ple_dim * dim;

    let ple_proj_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;
    let w_ple_proj_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * ple_dim;

    let w_ple_norm = cartan_c_ptr_add(layer_buf, bo);

    let N = num_tokens;
    var b_norm_h1 = g_trans_b_norm_h1;
    var b_q = g_trans_b_q;
    var b_k = g_trans_b_k;
    var b_v = g_trans_b_v;
    var b_attn_out = g_trans_b_attn_out;
    var b_h1 = g_trans_b_h1;
    var b_norm_h2 = g_trans_b_norm_h2;
    var b_act = g_trans_b_act;
    var b_ffn = g_trans_b_ffn;

    var is_dynamic = 0.0;
    if (N > 4096.0 || b_norm_h1 == 0.0) {
        is_dynamic = 1.0;
        b_norm_h1 = malloc(N * dim * 4.0);
        b_q = malloc(N * q_dim * 4.0);
        b_k = malloc(N * kv_dim * 4.0);
        b_v = malloc(N * kv_dim * 4.0);
        b_attn_out = malloc(N * q_dim * 4.0);
        b_h1 = malloc(N * dim * 4.0);
        b_norm_h2 = malloc(N * dim * 4.0);
        b_act = malloc(N * inter_dim * 4.0);
        b_ffn = malloc(N * dim * 4.0);
    }

    var p = 0.0;
    var d = 0.0;
    var sq_sum = 0.0;
    var h1_sq_sum = 0.0;
    var ffn_sq_sum = 0.0;
    var pli_l: ptr = 0.0;
    var pl = 0.0;
    var ple_sq = 0.0;
    var pli_val = 1.0;

    // 1. Batched Input RMSNorm
    p = 0.0;
    while (p < N) {
        let h_in_vec = cartan_tree_get_f32(token_states, p);
        let norm_dst = cartan_f32_ptr_add(b_norm_h1, p * dim);
        sq_sum = 0.0;
        d = 0.0;
        while (d < dim) {
            let val = cartan_vec_get_f32(h_in_vec, d);
            sq_sum = sq_sum + val * val;
            d = d + 1.0;
        }
        let inv_rms = 1.0 / sqrt((sq_sum / dim) + 0.000001);
        d = 0.0;
        while (d < dim) {
            let val = cartan_vec_get_f32(h_in_vec, d);
            let w = cartan_f32_at(w_in_norm, d);
            cartan_set_f32(norm_dst, d, val * inv_rms * w);
            d = d + 1.0;
        }
        p = p + 1.0;
    }

    // 2. Batched Q Projections (Row-Outer Multi-Threaded AVX2 INT8 GEMV Engine)
    cartan_trans_pool_dispatch_batch_int8_gemv(q_dim, dim, q_scales, w_q_bytes, b_norm_h1, b_q, N, q_dim);

    // 3. Batched K & V Projections (Row-Outer Multi-Threaded AVX2 INT8 Dual GEMV Engine)
    let is_kv_shared = (layer_idx >= 24.0);
    var kv_source_layer = layer_idx;
    if (is_kv_shared > 0.0) {
        if (is_global > 0.0) {
            kv_source_layer = 23.0;
        } else {
            kv_source_layer = 22.0;
        }
    }

    if (is_kv_shared == 0.0) {
        cartan_trans_pool_dispatch_batch_int8_dual_gemv(kv_dim, dim, k_scales, w_k_bytes, v_scales, w_v_bytes, b_norm_h1, b_k, b_v, N, kv_dim);
    }

    // 4. Per-Head Q-Norm, RoPE, Store KV, and Causal GQA Attention across all sequence positions
    let qh_norm_limit = q_dim - 3.0;
    var q_dot = 0.0;
    let inv_scale = 1.0 / sqrt(head_dim);
    let k_cache = cartan_kv_cache_get_k(kv_source_layer);
    let v_cache = cartan_kv_cache_get_v(kv_source_layer);
    let max_seq = g_kv_cache_max_seq;
    let scores_buf = g_trans_scores;

    p = 0.0;
    while (p < N) {
        let cur_pos = start_pos + p;
        let q_p = cartan_f32_ptr_add(b_q, p * q_dim);
        let k_p = cartan_f32_ptr_add(b_k, p * kv_dim);
        let v_p = cartan_f32_ptr_add(b_v, p * kv_dim);
        let out_p = cartan_f32_ptr_add(b_attn_out, p * q_dim);

        // Q RMSNorm across each 256-dim head
        var qh = 0.0;
        while (qh < q_dim) {
            let q_head_ptr = cartan_f32_ptr_add(q_p, qh);
            q_dot = cartan_simd_dot_f32(q_head_ptr, q_head_ptr, head_dim);
            let inv_q_rms = 1.0 / sqrt((q_dot / head_dim) + 0.000001);
            var hd = 0.0;
            while (hd < head_dim) {
                let q_val = cartan_f32_at(q_head_ptr, hd);
                let w = cartan_f32_at(w_q_norm, hd);
                cartan_set_f32(q_head_ptr, hd, q_val * inv_q_rms * w);
                hd = hd + 1.0;
            }
            qh = qh + head_dim;
        }

        // RoPE on Q heads
        qh = 0.0;
        while (qh < q_heads) {
            let qh_base = qh * head_dim;
            var k = 0.0;
            while (k < half) {
                let x0 = cartan_f32_at(q_p, qh_base + k);
                let x1 = cartan_f32_at(q_p, qh_base + k + half);
                var c = 1.0;
                var s = 0.0;
                if (k < rope_angles) {
                    let exponent = (k * 2.0) / head_dim;
                    let freq = 1.0 / pow(rope_theta, exponent);
                    let theta = cur_pos * freq;
                    c = cos(theta);
                    s = sin(theta);
                }
                cartan_set_f32(q_p, qh_base + k, x0 * c - x1 * s);
                cartan_set_f32(q_p, qh_base + k + half, x1 * c + x0 * s);
                k = k + 1.0;
            }
            qh = qh + 1.0;
        }

        // K-Norm, RoPE, and append to KV Cache (only for non-shared layers)
        if (is_kv_shared == 0.0 && k_cache != 0.0 && v_cache != 0.0 && cur_pos < g_kv_cache_max_seq) {
            let k_dst = cartan_f32_ptr_add(k_cache, cur_pos * kv_dim);
            let v_dst = cartan_f32_ptr_add(v_cache, cur_pos * kv_dim);

            var kvh = 0.0;
            while (kvh < kv_heads) {
                let kh_base = kvh * head_dim;
                let k_head_ptr = cartan_f32_ptr_add(k_p, kh_base);
                let kh_sq = cartan_simd_dot_f32(k_head_ptr, k_head_ptr, head_dim);
                let inv_k_rms = 1.0 / sqrt((kh_sq / head_dim) + 0.000001);
                var hd = 0.0;
                while (hd < head_dim) {
                    let v = cartan_f32_at(k_p, kh_base + hd);
                    let w = cartan_f32_at(w_k_norm, hd);
                    cartan_set_f32(k_p, kh_base + hd, v * inv_k_rms * w);
                    hd = hd + 1.0;
                }

                var k = 0.0;
                while (k < half) {
                    let x0 = cartan_f32_at(k_p, kh_base + k);
                    let x1 = cartan_f32_at(k_p, kh_base + k + half);
                    var c = 1.0;
                    var s = 0.0;
                    if (k < rope_angles) {
                        let exponent = (k * 2.0) / head_dim;
                        let freq = 1.0 / pow(rope_theta, exponent);
                        let theta = cur_pos * freq;
                        c = cos(theta);
                        s = sin(theta);
                    }
                    cartan_set_f32(k_dst, kh_base + k, x0 * c - x1 * s);
                    cartan_set_f32(k_dst, kh_base + k + half, x1 * c + x0 * s);
                    k = k + 1.0;
                }

                let v_head_ptr = cartan_f32_ptr_add(v_p, kh_base);
                let v_sq = cartan_simd_dot_f32(v_head_ptr, v_head_ptr, head_dim);
                let inv_v_rms = 1.0 / sqrt((v_sq / head_dim) + 0.000001);
                hd = 0.0;
                while (hd < head_dim) {
                    let val = cartan_f32_at(v_p, kh_base + hd);
                    cartan_set_f32(v_dst, kh_base + hd, val * inv_v_rms);
                    hd = hd + 1.0;
                }

                kvh = kvh + 1.0;
            }
        }

        // Causal GQA Attention
        var max_seq = cur_pos + 1.0;
        if (max_seq > g_kv_cache_max_seq) { max_seq = g_kv_cache_max_seq; }
        let hd_unroll_limit = head_dim - 3.0;

        var sink_limit = g_attention_sink_tokens;
        if (sink_limit > max_seq) { sink_limit = max_seq; }
        var win_start = 0.0;
        let win_size = g_attention_window_size;
        if (win_size > 0.0 && max_seq > (sink_limit + win_size)) {
            win_start = max_seq - win_size;
        }
        var p1_limit = max_seq;
        if (win_start > 0.0) { p1_limit = sink_limit; }

        qh = 0.0;
        while (qh < q_heads) {
            let kvh = floor(qh / heads_per_kv);
            let q_h = cartan_f32_ptr_add(q_p, qh * head_dim);
            let out_h = cartan_f32_ptr_add(out_p, qh * head_dim);

            var max_val = -1000000000.0;

            // Phase 1a: Attention Sinks (0 .. p1_limit)
            var t = 0.0;
            while (t < p1_limit) {
                var score = -10000.0;
                if (k_cache != 0.0) {
                    let k_ht = cartan_f32_ptr_add(k_cache, t * kv_dim + kvh * head_dim);
                    if (cartan_f32_at(k_ht, 0.0) > -9999.0) {
                        score = cartan_simd_dot_f32(q_h, k_ht, head_dim);
                    }
                }
                cartan_set_f32(scores_buf, t, score);
                if (score > max_val) { max_val = score; }
                t = t + 1.0;
            }

            // Phase 1b: Local Sliding Window (win_start .. max_seq)
            if (win_start > 0.0) {
                t = win_start;
                while (t < max_seq) {
                    var score = -10000.0;
                    if (k_cache != 0.0) {
                        let k_ht = cartan_f32_ptr_add(k_cache, t * kv_dim + kvh * head_dim);
                        if (cartan_f32_at(k_ht, 0.0) > -9999.0) {
                            score = cartan_simd_dot_f32(q_h, k_ht, head_dim);
                        }
                    }
                    cartan_set_f32(scores_buf, t, score);
                    if (score > max_val) { max_val = score; }
                    t = t + 1.0;
                }
            }

            var sum_exp = 0.0;
            // Phase 2a: Sinks Exponent
            t = 0.0;
            while (t < p1_limit) {
                let s_val = exp(cartan_f32_at(scores_buf, t) - max_val);
                cartan_set_f32(scores_buf, t, s_val);
                sum_exp = sum_exp + s_val;
                t = t + 1.0;
            }

            // Phase 2b: Sliding Window Exponent
            if (win_start > 0.0) {
                t = win_start;
                while (t < max_seq) {
                    let s_val = exp(cartan_f32_at(scores_buf, t) - max_val);
                    cartan_set_f32(scores_buf, t, s_val);
                    sum_exp = sum_exp + s_val;
                    t = t + 1.0;
                }
            }

            var inv_sum = 1.0;
            if (sum_exp > 0.000000000001) { inv_sum = 1.0 / sum_exp; }
            var hd = 0.0;
            while (hd < head_dim) {
                cartan_set_f32(out_h, hd, 0.0);
                hd = hd + 1.0;
            }

            // Phase 3a: Sinks V Accumulation
            t = 0.0;
            while (t < p1_limit) {
                let p_t = cartan_f32_at(scores_buf, t) * inv_sum;
                if (p_t > 0.000000001) {
                    let v_ht = cartan_f32_ptr_add(v_cache, t * kv_dim + kvh * head_dim);
                    hd = 0.0;
                    while (hd < hd_unroll_limit) {
                        let hd1 = hd + 1.0;
                        let hd2 = hd + 2.0;
                        let hd3 = hd + 3.0;
                        let o0 = cartan_f32_at(out_h, hd) + p_t * cartan_f32_at(v_ht, hd);
                        let o1 = cartan_f32_at(out_h, hd1) + p_t * cartan_f32_at(v_ht, hd1);
                        let o2 = cartan_f32_at(out_h, hd2) + p_t * cartan_f32_at(v_ht, hd2);
                        let o3 = cartan_f32_at(out_h, hd3) + p_t * cartan_f32_at(v_ht, hd3);
                        cartan_set_f32(out_h, hd, o0);
                        cartan_set_f32(out_h, hd1, o1);
                        cartan_set_f32(out_h, hd2, o2);
                        cartan_set_f32(out_h, hd3, o3);
                        hd = hd + 4.0;
                    }
                    while (hd < head_dim) {
                        let cur = cartan_f32_at(out_h, hd);
                        let val = cartan_f32_at(v_ht, hd);
                        cartan_set_f32(out_h, hd, cur + p_t * val);
                        hd = hd + 1.0;
                    }
                }
                t = t + 1.0;
            }

            // Phase 3b: Sliding Window V Accumulation
            if (win_start > 0.0) {
                t = win_start;
                while (t < max_seq) {
                    let p_t = cartan_f32_at(scores_buf, t) * inv_sum;
                    if (p_t > 0.000000001) {
                        let v_ht = cartan_f32_ptr_add(v_cache, t * kv_dim + kvh * head_dim);
                        hd = 0.0;
                        while (hd < hd_unroll_limit) {
                            let hd1 = hd + 1.0;
                            let hd2 = hd + 2.0;
                            let hd3 = hd + 3.0;
                            let o0 = cartan_f32_at(out_h, hd) + p_t * cartan_f32_at(v_ht, hd);
                            let o1 = cartan_f32_at(out_h, hd1) + p_t * cartan_f32_at(v_ht, hd1);
                            let o2 = cartan_f32_at(out_h, hd2) + p_t * cartan_f32_at(v_ht, hd2);
                            let o3 = cartan_f32_at(out_h, hd3) + p_t * cartan_f32_at(v_ht, hd3);
                            cartan_set_f32(out_h, hd, o0);
                            cartan_set_f32(out_h, hd1, o1);
                            cartan_set_f32(out_h, hd2, o2);
                            cartan_set_f32(out_h, hd3, o3);
                            hd = hd + 4.0;
                        }
                        while (hd < head_dim) {
                            let cur = cartan_f32_at(out_h, hd);
                            let val = cartan_f32_at(v_ht, hd);
                            cartan_set_f32(out_h, hd, cur + p_t * val);
                            hd = hd + 1.0;
                        }
                    }
                    t = t + 1.0;
                }
            }
            qh = qh + 1.0;
        }
        p = p + 1.0;
    }

    // 5. Batched Output Projection W_o (Row-Outer Multi-Threaded AVX2 INT8 GEMV Engine)
    cartan_trans_pool_dispatch_batch_int8_gemv(dim, q_dim, o_scales, w_o_bytes, b_attn_out, b_h1, N, dim);

    // Post-Attention RMSNorm + Residual + Pre-FFN RMSNorm for each token p
    p = 0.0;
    while (p < N) {
        let x_in_vec = cartan_tree_get_f32(token_states, p);
        let o_p = cartan_f32_ptr_add(b_h1, p * dim);
        let h1_sq = cartan_simd_dot_f32(o_p, o_p, dim);
        let inv_o_rms = 1.0 / sqrt((h1_sq / dim) + 0.000001);
        d = 0.0;
        while (d < dim) {
            let x = cartan_vec_get_f32(x_in_vec, d);
            let o = cartan_f32_at(o_p, d);
            let w = cartan_f32_at(w_post_attn, d);
            cartan_set_f32(o_p, d, x + o * inv_o_rms * w);
            d = d + 1.0;
        }
        h1_sq_sum = cartan_simd_dot_f32(o_p, o_p, dim);
        let inv_h1_rms = 1.0 / sqrt((h1_sq_sum / dim) + 0.000001);
        let norm_dst = cartan_f32_ptr_add(b_norm_h2, p * dim);
        d = 0.0;
        while (d < dim) {
            let val = cartan_f32_at(o_p, d);
            let w = cartan_f32_at(w_pre_ffn, d);
            cartan_set_f32(norm_dst, d, val * inv_h1_rms * w);
            d = d + 1.0;
        }
        p = p + 1.0;
    }

    // 6. Batched GeGLU Gate & Up and Down Projections (Row-Outer Multi-Threaded AVX2 INT8 Engine)
    cartan_trans_pool_dispatch_batch_int8_geglu(inter_dim, dim, gate_scales, up_scales, w_gate_bytes, w_up_bytes, b_norm_h2, b_act, N, inter_dim);
    cartan_trans_pool_dispatch_batch_int8_gemv(dim, inter_dim, down_scales, w_down_bytes, b_act, b_ffn, N, dim);

    // 7. Post-FFN RMSNorm, Residual Addition, PLE Gating, and Layer Scalar Scaling
    p = 0.0;
    while (p < N) {
        let h1_p = cartan_f32_ptr_add(b_h1, p * dim);
        let ffn_p = cartan_f32_ptr_add(b_ffn, p * dim);
        ffn_sq_sum = cartan_simd_dot_f32(ffn_p, ffn_p, dim);
        let inv_ffn_rms = 1.0 / sqrt((ffn_sq_sum / dim) + 0.000001);
        d = 0.0;
        while (d < dim) {
            let h1_val = cartan_f32_at(h1_p, d);
            let ffn_val = cartan_f32_at(ffn_p, d);
            let w = cartan_f32_at(w_post_ffn, d);
            cartan_set_f32(h1_p, d, h1_val + ffn_val * inv_ffn_rms * w);
            d = d + 1.0;
        }
        p = p + 1.0;
    }

    if (has_ple > 0.0) {
        var b_ple_act = g_trans_b_ple_act;
        var b_ple_proj = g_trans_b_ple_proj;
        var is_ple_dynamic = 0.0;
        if (N > 4096.0 || b_ple_act == 0.0) {
            is_ple_dynamic = 1.0;
            b_ple_act = malloc(N * ple_dim * 4.0);
            b_ple_proj = malloc(N * dim * 4.0);
        }

        // Batched PLE Gate GEMV across all N prompt tokens
        cartan_trans_pool_dispatch_batch_int8_gemv(ple_dim, dim, ple_gate_scales, w_ple_gate_bytes, b_h1, b_ple_act, N, ple_dim);

        p = 0.0;
        while (p < N) {
            let tok_id = cartan_vec_get_f32(prompt_tokens, p);
            pli_l = 0.0;
            if (g_prompt_pli_buf != 0.0) {
                pli_l = cartan_f32_ptr_add(g_prompt_pli_buf, p * 10752.0 + layer_idx * 256.0);
            } else if (tok_id >= 0.0 && tok_id < 262144.0) {
                pli_l = cartan_get_cached_pli(layer_idx, tok_id);
            }
            let act_p = cartan_f32_ptr_add(b_ple_act, p * ple_dim);
            pl = 0.0;
            while (pl < ple_dim) {
                let dot_gate = cartan_f32_at(act_p, pl);
                pli_val = 1.0;
                if (pli_l != 0.0) {
                    pli_val = cartan_f32_at(pli_l, pl);
                }
                cartan_set_f32(act_p, pl, cartan_fast_gelu_tanh(dot_gate) * pli_val);
                pl = pl + 1.0;
            }
            p = p + 1.0;
        }

        // Batched PLE Projection GEMV across all N prompt tokens
        cartan_trans_pool_dispatch_batch_int8_gemv(dim, ple_dim, ple_proj_scales, w_ple_proj_bytes, b_ple_act, b_ple_proj, N, dim);

        p = 0.0;
        while (p < N) {
            let h_in_vec = cartan_tree_get_f32(token_states, p);
            let h2_p = cartan_f32_ptr_add(b_h1, p * dim);
            let proj_p = cartan_f32_ptr_add(b_ple_proj, p * dim);
            ple_sq = cartan_simd_dot_f32(proj_p, proj_p, dim);
            let inv_ple_rms = 1.0 / sqrt((ple_sq / dim) + 0.000001);
            d = 0.0;
            while (d < dim) {
                let h2_val = cartan_f32_at(h2_p, d);
                let proj_val = cartan_f32_at(proj_p, d);
                let norm_val = cartan_f32_at(w_ple_norm, d);
                cartan_vec_set_f32(h_in_vec, d, (h2_val + proj_val * inv_ple_rms * norm_val) * layer_scalar);
                d = d + 1.0;
            }
            p = p + 1.0;
        }

        if (is_ple_dynamic == 1.0) {
            free(b_ple_act);
            free(b_ple_proj);
        }
    } else {
        p = 0.0;
        while (p < N) {
            let h_in_vec = cartan_tree_get_f32(token_states, p);
            let h2_p = cartan_f32_ptr_add(b_h1, p * dim);
            d = 0.0;
            while (d < dim) {
                cartan_vec_set_f32(h_in_vec, d, cartan_f32_at(h2_p, d) * layer_scalar);
                d = d + 1.0;
            }
            p = p + 1.0;
        }
    }

    if (is_dynamic == 1.0) {
        free(b_norm_h1);
        free(b_q);
        free(b_k);
        free(b_v);
        free(b_attn_out);
        free(b_h1);
        free(b_norm_h2);
        free(b_act);
        free(b_ffn);
    }

    return 1.0;
}

// -----------------------------------------------------------------------------
// Batched Sequence Prefill Layer Forward Kernel for INT4 Weights
// -----------------------------------------------------------------------------
fn cartan_manifold_layer_forward_batch_int4(
    token_states: ptr,
    layer_buf: ptr,
    prompt_tokens: ptr,
    num_tokens: float,
    start_pos: float
) -> float {
    let layer_idx = cartan_f32_at(layer_buf, 1.0);
    var head_dim = cartan_f32_at(layer_buf, 2.0);
    if (head_dim <= 0.0) { head_dim = 256.0; }
    var rope_theta = cartan_f32_at(layer_buf, 3.0);
    if (rope_theta <= 0.0) { rope_theta = 10000.0; }
    if (g_kv_cache_max_seq > 2048.0) {
        rope_theta = rope_theta * (g_kv_cache_max_seq / 2048.0);
    }
    var layer_scalar = cartan_f32_at(layer_buf, 4.0);
    if (layer_scalar == 0.0) { layer_scalar = 1.0; }
    let has_ple = cartan_f32_at(layer_buf, 5.0);
    let dim = cartan_f32_at(layer_buf, 6.0);
    let inter_dim = cartan_f32_at(layer_buf, 7.0);
    let q_dim = cartan_f32_at(layer_buf, 8.0);
    let kv_dim = cartan_f32_at(layer_buf, 9.0);
    let ple_dim = cartan_f32_at(layer_buf, 10.0);

    let q_heads = q_dim / head_dim;
    var kv_heads = kv_dim / head_dim;
    if (kv_heads <= 0.0) { kv_heads = 1.0; }
    let heads_per_kv = q_heads / kv_heads;

    let half = head_dim / 2.0;
    let is_global = (fmod(layer_idx + 1.0, 6.0) == 0.0);
    var rope_angles = half;
    if (is_global > 0.0) {
        rope_angles = 64.0;
    }

    let w_in_norm = cartan_c_ptr_add(layer_buf, 64.0);
    var bo = 64.0 + dim * 4.0;

    let q_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + q_dim * 4.0;
    let w_q_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + q_dim * dim * 0.5;

    let k_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + kv_dim * 4.0;
    let w_k_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + kv_dim * dim * 0.5;

    let v_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + kv_dim * 4.0;
    let w_v_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + kv_dim * dim * 0.5;

    let o_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;
    let w_o_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * q_dim * 0.5;

    let w_q_norm = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + 512.0 * 4.0;
    let w_k_norm = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + 512.0 * 4.0;

    let w_post_attn = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;
    let w_pre_ffn = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;

    let gate_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + inter_dim * 4.0;
    let w_gate_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + inter_dim * dim * 0.5;

    let up_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + inter_dim * 4.0;
    let w_up_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + inter_dim * dim * 0.5;

    let down_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;
    let w_down_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * inter_dim * 0.5;

    let w_post_ffn = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;

    let ple_gate_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + ple_dim * 4.0;
    let w_ple_gate_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + ple_dim * dim * 0.5;

    let ple_proj_scales = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * 4.0;
    let w_ple_proj_bytes = cartan_c_ptr_add(layer_buf, bo);
    bo = bo + dim * ple_dim * 0.5;

    let w_ple_norm = cartan_c_ptr_add(layer_buf, bo);

    let N = num_tokens;
    var b_norm_h1 = g_trans_b_norm_h1;
    var b_q = g_trans_b_q;
    var b_k = g_trans_b_k;
    var b_v = g_trans_b_v;
    var b_attn_out = g_trans_b_attn_out;
    var b_h1 = g_trans_b_h1;
    var b_norm_h2 = g_trans_b_norm_h2;
    var b_act = g_trans_b_act;
    var b_ffn = g_trans_b_ffn;

    var is_dynamic = 0.0;
    if (N > 4096.0 || b_norm_h1 == 0.0) {
        is_dynamic = 1.0;
        b_norm_h1 = malloc(N * dim * 4.0);
        b_q = malloc(N * q_dim * 4.0);
        b_k = malloc(N * kv_dim * 4.0);
        b_v = malloc(N * kv_dim * 4.0);
        b_attn_out = malloc(N * q_dim * 4.0);
        b_h1 = malloc(N * dim * 4.0);
        b_norm_h2 = malloc(N * dim * 4.0);
        b_act = malloc(N * inter_dim * 4.0);
        b_ffn = malloc(N * dim * 4.0);
    }

    var p = 0.0;
    var d = 0.0;
    var sq_sum = 0.0;
    var h1_sq_sum = 0.0;
    var ffn_sq_sum = 0.0;
    var pli_l: ptr = 0.0;
    var pl = 0.0;
    var ple_sq = 0.0;
    var pli_val = 1.0;

    // 1. Batched Input RMSNorm
    p = 0.0;
    while (p < N) {
        let h_in_vec = cartan_tree_get_f32(token_states, p);
        let norm_dst = cartan_f32_ptr_add(b_norm_h1, p * dim);
        sq_sum = 0.0;
        d = 0.0;
        while (d < dim) {
            let val = cartan_vec_get_f32(h_in_vec, d);
            sq_sum = sq_sum + val * val;
            d = d + 1.0;
        }
        let inv_rms = 1.0 / sqrt((sq_sum / dim) + 0.000001);
        d = 0.0;
        while (d < dim) {
            let val = cartan_vec_get_f32(h_in_vec, d);
            let w = cartan_f32_at(w_in_norm, d);
            cartan_set_f32(norm_dst, d, val * inv_rms * w);
            d = d + 1.0;
        }
        p = p + 1.0;
    }

    // 2. Batched Q Projections (Row-Outer Multi-Threaded AVX2 INT4 GEMV Engine)
    cartan_trans_pool_dispatch_batch_int4_gemv(q_dim, dim, q_scales, w_q_bytes, b_norm_h1, b_q, N, q_dim);

    // 3. Batched K & V Projections (Row-Outer Multi-Threaded AVX2 INT4 Dual GEMV Engine)
    let is_kv_shared = (layer_idx >= 24.0);
    var kv_source_layer = layer_idx;
    if (is_kv_shared > 0.0) {
        if (is_global > 0.0) {
            kv_source_layer = 23.0;
        } else {
            kv_source_layer = 22.0;
        }
    }

    if (is_kv_shared == 0.0) {
        cartan_trans_pool_dispatch_batch_int4_dual_gemv(kv_dim, dim, k_scales, w_k_bytes, v_scales, w_v_bytes, b_norm_h1, b_k, b_v, N, kv_dim);
    }

    // 4. Per-Head Q-Norm, RoPE, Store KV, and Causal GQA Attention across all sequence positions
    let qh_norm_limit = q_dim - 3.0;
    var q_dot = 0.0;
    let inv_scale = 1.0 / sqrt(head_dim);
    let k_cache = cartan_kv_cache_get_k(kv_source_layer);
    let v_cache = cartan_kv_cache_get_v(kv_source_layer);
    let max_seq = g_kv_cache_max_seq;
    let scores_buf = g_trans_scores;

    p = 0.0;
    while (p < N) {
        let cur_pos = start_pos + p;
        let q_p = cartan_f32_ptr_add(b_q, p * q_dim);
        let k_p = cartan_f32_ptr_add(b_k, p * kv_dim);
        let v_p = cartan_f32_ptr_add(b_v, p * kv_dim);
        let out_p = cartan_f32_ptr_add(b_attn_out, p * q_dim);

        // Q RMSNorm across each 256-dim head
        var qh = 0.0;
        while (qh < q_dim) {
            let q_head_ptr = cartan_f32_ptr_add(q_p, qh);
            q_dot = cartan_simd_dot_f32(q_head_ptr, q_head_ptr, head_dim);
            let inv_q_rms = 1.0 / sqrt((q_dot / head_dim) + 0.000001);
            var hd = 0.0;
            while (hd < head_dim) {
                let q_val = cartan_f32_at(q_head_ptr, hd);
                let w = cartan_f32_at(w_q_norm, hd);
                cartan_set_f32(q_head_ptr, hd, q_val * inv_q_rms * w);
                hd = hd + 1.0;
            }
            qh = qh + head_dim;
        }

        // RoPE on Q heads
        qh = 0.0;
        while (qh < q_heads) {
            let qh_base = qh * head_dim;
            var k = 0.0;
            while (k < half) {
                let x0 = cartan_f32_at(q_p, qh_base + k);
                let x1 = cartan_f32_at(q_p, qh_base + k + half);
                var c = 1.0;
                var s = 0.0;
                if (k < rope_angles) {
                    let exponent = (k * 2.0) / head_dim;
                    let freq = 1.0 / pow(rope_theta, exponent);
                    let theta = cur_pos * freq;
                    c = cos(theta);
                    s = sin(theta);
                }
                cartan_set_f32(q_p, qh_base + k, x0 * c - x1 * s);
                cartan_set_f32(q_p, qh_base + k + half, x1 * c + x0 * s);
                k = k + 1.0;
            }
            qh = qh + 1.0;
        }

        // K-Norm, RoPE, and append to KV Cache (only for non-shared layers)
        if (is_kv_shared == 0.0 && k_cache != 0.0 && v_cache != 0.0 && cur_pos < g_kv_cache_max_seq) {
            let k_dst = cartan_f32_ptr_add(k_cache, cur_pos * kv_dim);
            let v_dst = cartan_f32_ptr_add(v_cache, cur_pos * kv_dim);

            var kvh = 0.0;
            while (kvh < kv_heads) {
                let kh_base = kvh * head_dim;
                let k_head_ptr = cartan_f32_ptr_add(k_p, kh_base);
                let kh_sq = cartan_simd_dot_f32(k_head_ptr, k_head_ptr, head_dim);
                let inv_k_rms = 1.0 / sqrt((kh_sq / head_dim) + 0.000001);
                var hd = 0.0;
                while (hd < head_dim) {
                    let v = cartan_f32_at(k_p, kh_base + hd);
                    let w = cartan_f32_at(w_k_norm, hd);
                    cartan_set_f32(k_p, kh_base + hd, v * inv_k_rms * w);
                    hd = hd + 1.0;
                }

                var k = 0.0;
                while (k < half) {
                    let x0 = cartan_f32_at(k_p, kh_base + k);
                    let x1 = cartan_f32_at(k_p, kh_base + k + half);
                    var c = 1.0;
                    var s = 0.0;
                    if (k < rope_angles) {
                        let exponent = (k * 2.0) / head_dim;
                        let freq = 1.0 / pow(rope_theta, exponent);
                        let theta = cur_pos * freq;
                        c = cos(theta);
                        s = sin(theta);
                    }
                    cartan_set_f32(k_dst, kh_base + k, x0 * c - x1 * s);
                    cartan_set_f32(k_dst, kh_base + k + half, x1 * c + x0 * s);
                    k = k + 1.0;
                }

                let v_head_ptr = cartan_f32_ptr_add(v_p, kh_base);
                let v_sq = cartan_simd_dot_f32(v_head_ptr, v_head_ptr, head_dim);
                let inv_v_rms = 1.0 / sqrt((v_sq / head_dim) + 0.000001);
                hd = 0.0;
                while (hd < head_dim) {
                    let val = cartan_f32_at(v_p, kh_base + hd);
                    cartan_set_f32(v_dst, kh_base + hd, val * inv_v_rms);
                    hd = hd + 1.0;
                }

                kvh = kvh + 1.0;
            }
        }

        // Causal GQA Attention
        var max_seq = cur_pos + 1.0;
        if (max_seq > g_kv_cache_max_seq) { max_seq = g_kv_cache_max_seq; }
        let hd_unroll_limit = head_dim - 3.0;

        var sink_limit = g_attention_sink_tokens;
        if (sink_limit > max_seq) { sink_limit = max_seq; }
        var win_start = 0.0;
        let win_size = g_attention_window_size;
        if (win_size > 0.0 && max_seq > (sink_limit + win_size)) {
            win_start = max_seq - win_size;
        }
        var p1_limit = max_seq;
        if (win_start > 0.0) { p1_limit = sink_limit; }

        qh = 0.0;
        while (qh < q_heads) {
            let kvh = floor(qh / heads_per_kv);
            let q_h = cartan_f32_ptr_add(q_p, qh * head_dim);
            let out_h = cartan_f32_ptr_add(out_p, qh * head_dim);

            var max_val = -1000000000.0;

            // Phase 1a: Attention Sinks (0 .. p1_limit)
            var t = 0.0;
            while (t < p1_limit) {
                var score = -10000.0;
                if (k_cache != 0.0) {
                    let k_ht = cartan_f32_ptr_add(k_cache, t * kv_dim + kvh * head_dim);
                    if (cartan_f32_at(k_ht, 0.0) > -9999.0) {
                        score = cartan_simd_dot_f32(q_h, k_ht, head_dim);
                    }
                }
                cartan_set_f32(scores_buf, t, score);
                if (score > max_val) { max_val = score; }
                t = t + 1.0;
            }

            // Phase 1b: Local Sliding Window (win_start .. max_seq)
            if (win_start > 0.0) {
                t = win_start;
                while (t < max_seq) {
                    var score = -10000.0;
                    if (k_cache != 0.0) {
                        let k_ht = cartan_f32_ptr_add(k_cache, t * kv_dim + kvh * head_dim);
                        if (cartan_f32_at(k_ht, 0.0) > -9999.0) {
                            score = cartan_simd_dot_f32(q_h, k_ht, head_dim);
                        }
                    }
                    cartan_set_f32(scores_buf, t, score);
                    if (score > max_val) { max_val = score; }
                    t = t + 1.0;
                }
            }

            var sum_exp = 0.0;
            // Phase 2a: Sinks Exponent
            t = 0.0;
            while (t < p1_limit) {
                let s_val = exp(cartan_f32_at(scores_buf, t) - max_val);
                cartan_set_f32(scores_buf, t, s_val);
                sum_exp = sum_exp + s_val;
                t = t + 1.0;
            }

            // Phase 2b: Sliding Window Exponent
            if (win_start > 0.0) {
                t = win_start;
                while (t < max_seq) {
                    let s_val = exp(cartan_f32_at(scores_buf, t) - max_val);
                    cartan_set_f32(scores_buf, t, s_val);
                    sum_exp = sum_exp + s_val;
                    t = t + 1.0;
                }
            }

            var inv_sum = 1.0;
            if (sum_exp > 0.000000000001) { inv_sum = 1.0 / sum_exp; }
            var hd = 0.0;
            while (hd < head_dim) {
                cartan_set_f32(out_h, hd, 0.0);
                hd = hd + 1.0;
            }

            // Phase 3a: Sinks V Accumulation
            t = 0.0;
            while (t < p1_limit) {
                let p_t = cartan_f32_at(scores_buf, t) * inv_sum;
                if (p_t > 0.000000001) {
                    let v_ht = cartan_f32_ptr_add(v_cache, t * kv_dim + kvh * head_dim);
                    hd = 0.0;
                    while (hd < hd_unroll_limit) {
                        let hd1 = hd + 1.0;
                        let hd2 = hd + 2.0;
                        let hd3 = hd + 3.0;
                        let o0 = cartan_f32_at(out_h, hd) + p_t * cartan_f32_at(v_ht, hd);
                        let o1 = cartan_f32_at(out_h, hd1) + p_t * cartan_f32_at(v_ht, hd1);
                        let o2 = cartan_f32_at(out_h, hd2) + p_t * cartan_f32_at(v_ht, hd2);
                        let o3 = cartan_f32_at(out_h, hd3) + p_t * cartan_f32_at(v_ht, hd3);
                        cartan_set_f32(out_h, hd, o0);
                        cartan_set_f32(out_h, hd1, o1);
                        cartan_set_f32(out_h, hd2, o2);
                        cartan_set_f32(out_h, hd3, o3);
                        hd = hd + 4.0;
                    }
                    while (hd < head_dim) {
                        let cur = cartan_f32_at(out_h, hd);
                        let val = cartan_f32_at(v_ht, hd);
                        cartan_set_f32(out_h, hd, cur + p_t * val);
                        hd = hd + 1.0;
                    }
                }
                t = t + 1.0;
            }

            // Phase 3b: Sliding Window V Accumulation
            if (win_start > 0.0) {
                t = win_start;
                while (t < max_seq) {
                    let p_t = cartan_f32_at(scores_buf, t) * inv_sum;
                    if (p_t > 0.000000001) {
                        let v_ht = cartan_f32_ptr_add(v_cache, t * kv_dim + kvh * head_dim);
                        hd = 0.0;
                        while (hd < hd_unroll_limit) {
                            let hd1 = hd + 1.0;
                            let hd2 = hd + 2.0;
                            let hd3 = hd + 3.0;
                            let o0 = cartan_f32_at(out_h, hd) + p_t * cartan_f32_at(v_ht, hd);
                            let o1 = cartan_f32_at(out_h, hd1) + p_t * cartan_f32_at(v_ht, hd1);
                            let o2 = cartan_f32_at(out_h, hd2) + p_t * cartan_f32_at(v_ht, hd2);
                            let o3 = cartan_f32_at(out_h, hd3) + p_t * cartan_f32_at(v_ht, hd3);
                            cartan_set_f32(out_h, hd, o0);
                            cartan_set_f32(out_h, hd1, o1);
                            cartan_set_f32(out_h, hd2, o2);
                            cartan_set_f32(out_h, hd3, o3);
                            hd = hd + 4.0;
                        }
                        while (hd < head_dim) {
                            let cur = cartan_f32_at(out_h, hd);
                            let val = cartan_f32_at(v_ht, hd);
                            cartan_set_f32(out_h, hd, cur + p_t * val);
                            hd = hd + 1.0;
                        }
                    }
                    t = t + 1.0;
                }
            }
            qh = qh + 1.0;
        }
        p = p + 1.0;
    }

    // 5. Batched Output Projection W_o (Row-Outer Multi-Threaded AVX2 INT4 GEMV Engine)
    cartan_trans_pool_dispatch_batch_int4_gemv(dim, q_dim, o_scales, w_o_bytes, b_attn_out, b_h1, N, dim);

    // Post-Attention RMSNorm + Residual + Pre-FFN RMSNorm for each token p
    p = 0.0;
    while (p < N) {
        let x_in_vec = cartan_tree_get_f32(token_states, p);
        let o_p = cartan_f32_ptr_add(b_h1, p * dim);
        let h1_sq = cartan_simd_dot_f32(o_p, o_p, dim);
        let inv_o_rms = 1.0 / sqrt((h1_sq / dim) + 0.000001);
        d = 0.0;
        while (d < dim) {
            let x = cartan_vec_get_f32(x_in_vec, d);
            let o = cartan_f32_at(o_p, d);
            let w = cartan_f32_at(w_post_attn, d);
            cartan_set_f32(o_p, d, x + o * inv_o_rms * w);
            d = d + 1.0;
        }
        h1_sq_sum = cartan_simd_dot_f32(o_p, o_p, dim);
        let inv_h1_rms = 1.0 / sqrt((h1_sq_sum / dim) + 0.000001);
        let norm_dst = cartan_f32_ptr_add(b_norm_h2, p * dim);
        d = 0.0;
        while (d < dim) {
            let val = cartan_f32_at(o_p, d);
            let w = cartan_f32_at(w_pre_ffn, d);
            cartan_set_f32(norm_dst, d, val * inv_h1_rms * w);
            d = d + 1.0;
        }
        p = p + 1.0;
    }

    // 6. Batched GeGLU Gate & Up and Down Projections (GPU VRAM-Resident INT4 with CPU Fallback)
    var gpu_ffn_ok = 0.0;
    if (g_trans_gpu_int4_ready == 1.0) {
        gpu_ffn_ok = cartan_transformer_dispatch_gpu_layer_batch_int4(layer_idx, b_norm_h2, b_ffn, N, dim, inter_dim);
    }
    if (gpu_ffn_ok == 0.0) {
        cartan_trans_pool_dispatch_batch_int4_geglu(inter_dim, dim, gate_scales, up_scales, w_gate_bytes, w_up_bytes, b_norm_h2, b_act, N, inter_dim);
        cartan_trans_pool_dispatch_batch_int4_gemv(dim, inter_dim, down_scales, w_down_bytes, b_act, b_ffn, N, dim);
    }

    // 7. Post-FFN RMSNorm, Residual Addition, PLE Gating, and Layer Scalar Scaling
    p = 0.0;
    while (p < N) {
        let h1_p = cartan_f32_ptr_add(b_h1, p * dim);
        let ffn_p = cartan_f32_ptr_add(b_ffn, p * dim);
        ffn_sq_sum = cartan_simd_dot_f32(ffn_p, ffn_p, dim);
        let inv_ffn_rms = 1.0 / sqrt((ffn_sq_sum / dim) + 0.000001);
        d = 0.0;
        while (d < dim) {
            let h1_val = cartan_f32_at(h1_p, d);
            let ffn_val = cartan_f32_at(ffn_p, d);
            let w = cartan_f32_at(w_post_ffn, d);
            cartan_set_f32(h1_p, d, h1_val + ffn_val * inv_ffn_rms * w);
            d = d + 1.0;
        }
        p = p + 1.0;
    }

    if (has_ple > 0.0) {
        var b_ple_act = g_trans_b_ple_act;
        var b_ple_proj = g_trans_b_ple_proj;
        var is_ple_dynamic = 0.0;
        if (N > 4096.0 || b_ple_act == 0.0) {
            is_ple_dynamic = 1.0;
            b_ple_act = malloc(N * ple_dim * 4.0);
            b_ple_proj = malloc(N * dim * 4.0);
        }

        // Batched PLE Gate GEMV across all N prompt tokens
        cartan_trans_pool_dispatch_batch_int4_gemv(ple_dim, dim, ple_gate_scales, w_ple_gate_bytes, b_h1, b_ple_act, N, ple_dim);

        p = 0.0;
        while (p < N) {
            let tok_id = cartan_vec_get_f32(prompt_tokens, p);
            pli_l = 0.0;
            if (g_prompt_pli_buf != 0.0) {
                pli_l = cartan_f32_ptr_add(g_prompt_pli_buf, p * 10752.0 + layer_idx * 256.0);
            } else if (tok_id >= 0.0 && tok_id < 262144.0) {
                pli_l = cartan_get_cached_pli(layer_idx, tok_id);
            }
            let act_p = cartan_f32_ptr_add(b_ple_act, p * ple_dim);
            pl = 0.0;
            while (pl < ple_dim) {
                let dot_gate = cartan_f32_at(act_p, pl);
                pli_val = 1.0;
                if (pli_l != 0.0) {
                    pli_val = cartan_f32_at(pli_l, pl);
                }
                cartan_set_f32(act_p, pl, cartan_fast_gelu_tanh(dot_gate) * pli_val);
                pl = pl + 1.0;
            }
            p = p + 1.0;
        }

        // Batched PLE Projection GEMV across all N prompt tokens
        cartan_trans_pool_dispatch_batch_int4_gemv(dim, ple_dim, ple_proj_scales, w_ple_proj_bytes, b_ple_act, b_ple_proj, N, dim);

        p = 0.0;
        while (p < N) {
            let h_in_vec = cartan_tree_get_f32(token_states, p);
            let h2_p = cartan_f32_ptr_add(b_h1, p * dim);
            let proj_p = cartan_f32_ptr_add(b_ple_proj, p * dim);
            ple_sq = cartan_simd_dot_f32(proj_p, proj_p, dim);
            let inv_ple_rms = 1.0 / sqrt((ple_sq / dim) + 0.000001);
            d = 0.0;
            while (d < dim) {
                let h2_val = cartan_f32_at(h2_p, d);
                let proj_val = cartan_f32_at(proj_p, d);
                let norm_val = cartan_f32_at(w_ple_norm, d);
                cartan_vec_set_f32(h_in_vec, d, (h2_val + proj_val * inv_ple_rms * norm_val) * layer_scalar);
                d = d + 1.0;
            }
            p = p + 1.0;
        }

        if (is_ple_dynamic == 1.0) {
            free(b_ple_act);
            free(b_ple_proj);
        }
    } else {
        p = 0.0;
        while (p < N) {
            let h_in_vec = cartan_tree_get_f32(token_states, p);
            let h2_p = cartan_f32_ptr_add(b_h1, p * dim);
            d = 0.0;
            while (d < dim) {
                cartan_vec_set_f32(h_in_vec, d, cartan_f32_at(h2_p, d) * layer_scalar);
                d = d + 1.0;
            }
            p = p + 1.0;
        }
    }

    if (is_dynamic == 1.0) {
        free(b_norm_h1);
        free(b_q);
        free(b_k);
        free(b_v);
        free(b_attn_out);
        free(b_h1);
        free(b_norm_h2);
        free(b_act);
        free(b_ffn);
    }

    return 1.0;
}

// -----------------------------------------------------------------------------
// 13. High-Throughput Batched Sequence Prefill Layer Forward Kernel
// Row-outer execution: Streams each weight matrix from RAM exactly ONCE per layer,
// achieving a 93x memory bandwidth reduction and sub-second prefill latency.
// -----------------------------------------------------------------------------
fn cartan_manifold_layer_forward_batch(
    token_states: ptr,
    layer_buf: ptr,
    prompt_tokens: ptr,
    num_tokens: float,
    start_pos: float
) -> float {
    if (token_states == 0.0 || layer_buf == 0.0 || prompt_tokens == 0.0 || num_tokens <= 0.0) {
        return 0.0;
    }
    cartan_init_transformer_scratch_buffers();
    cartan_kv_cache_init();

    let layer_idx = cartan_f32_at(layer_buf, 1.0);
    var head_dim = cartan_f32_at(layer_buf, 2.0);
    if (head_dim <= 0.0) { head_dim = 256.0; }
    var rope_theta = cartan_f32_at(layer_buf, 3.0);
    if (rope_theta <= 0.0) { rope_theta = 10000.0; }
    if (g_kv_cache_max_seq > 2048.0) {
        rope_theta = rope_theta * (g_kv_cache_max_seq / 2048.0);
    }
    var layer_scalar = cartan_f32_at(layer_buf, 4.0);
    if (layer_scalar == 0.0) { layer_scalar = 1.0; }
    let has_ple = cartan_f32_at(layer_buf, 5.0);
    let dim = cartan_f32_at(layer_buf, 6.0);
    let inter_dim = cartan_f32_at(layer_buf, 7.0);
    let q_dim = cartan_f32_at(layer_buf, 8.0);
    let kv_dim = cartan_f32_at(layer_buf, 9.0);
    let ple_dim = cartan_f32_at(layer_buf, 10.0);

    let is_int8 = cartan_f32_at(layer_buf, 11.0);
    if (is_int8 == 1.0) {
        return cartan_manifold_layer_forward_batch_int8(token_states, layer_buf, prompt_tokens, num_tokens, start_pos);
    }
    if (is_int8 == 2.0) {
        return cartan_manifold_layer_forward_batch_int4(token_states, layer_buf, prompt_tokens, num_tokens, start_pos);
    }

    let q_heads = q_dim / head_dim;
    var kv_heads = kv_dim / head_dim;
    if (kv_heads <= 0.0) { kv_heads = 1.0; }
    let heads_per_kv = q_heads / kv_heads;

    let off_in_norm = 16.0;
    let off_w_q = 2576.0;
    let off_w_k = off_w_q + q_dim * dim;
    let off_w_v = off_w_k + kv_dim * dim;
    let off_w_o = off_w_v + kv_dim * dim;
    let off_q_norm = off_w_o + dim * q_dim;
    let off_k_norm = off_q_norm + 512.0;
    let off_post_attn_norm = off_k_norm + 512.0;
    let off_pre_ffn_norm = off_post_attn_norm + dim;
    let off_gate_proj = off_pre_ffn_norm + dim;
    let off_up_proj = off_gate_proj + inter_dim * dim;
    let off_down_proj = off_up_proj + inter_dim * dim;
    let off_post_ffn_norm = off_down_proj + dim * inter_dim;
    let off_ple_gate = off_post_ffn_norm + dim;
    let off_ple_proj = off_ple_gate + ple_dim * dim;
    let off_ple_norm = off_ple_proj + dim * ple_dim;

    let w_in_norm = cartan_f32_ptr_add(layer_buf, off_in_norm);
    let w_q = cartan_f32_ptr_add(layer_buf, off_w_q);
    let w_k = cartan_f32_ptr_add(layer_buf, off_w_k);
    let w_v = cartan_f32_ptr_add(layer_buf, off_w_v);
    let w_o = cartan_f32_ptr_add(layer_buf, off_w_o);
    let w_q_norm = cartan_f32_ptr_add(layer_buf, off_q_norm);
    let w_k_norm = cartan_f32_ptr_add(layer_buf, off_k_norm);
    let w_post_attn = cartan_f32_ptr_add(layer_buf, off_post_attn_norm);
    let w_pre_ffn = cartan_f32_ptr_add(layer_buf, off_pre_ffn_norm);
    let w_gate = cartan_f32_ptr_add(layer_buf, off_gate_proj);
    let w_up = cartan_f32_ptr_add(layer_buf, off_up_proj);
    let w_down = cartan_f32_ptr_add(layer_buf, off_down_proj);
    let w_post_ffn = cartan_f32_ptr_add(layer_buf, off_post_ffn_norm);
    let w_ple_gate = cartan_f32_ptr_add(layer_buf, off_ple_gate);
    let w_ple_proj = cartan_f32_ptr_add(layer_buf, off_ple_proj);
    let w_ple_norm = cartan_f32_ptr_add(layer_buf, off_ple_norm);

    let N = num_tokens;
    var b_norm_h1 = g_trans_b_norm_h1;
    var b_q = g_trans_b_q;
    var b_k = g_trans_b_k;
    var b_v = g_trans_b_v;
    var b_attn_out = g_trans_b_attn_out;
    var b_h1 = g_trans_b_h1;
    var b_norm_h2 = g_trans_b_norm_h2;
    var b_act = g_trans_b_act;
    var b_ffn = g_trans_b_ffn;
    var is_dynamic = 0.0;

    if (N > 4096.0 || b_norm_h1 == 0.0) {
        is_dynamic = 1.0;
        b_norm_h1 = malloc(N * dim * 4.0);
        b_q = malloc(N * q_dim * 4.0);
        b_k = malloc(N * kv_dim * 4.0);
        b_v = malloc(N * kv_dim * 4.0);
        b_attn_out = malloc(N * q_dim * 4.0);
        b_h1 = malloc(N * dim * 4.0);
        b_norm_h2 = malloc(N * dim * 4.0);
        b_act = malloc(N * inter_dim * 4.0);
        b_ffn = malloc(N * dim * 4.0);
    }

    var p = 0.0;
    var d = 0.0;
    var sum_sq = 0.0;
    var kv_source_layer = 0.0;
    var rope_angles = 0.0;
    var qh = 0.0;
    var h_sq = 0.0;
    var hd = 0.0;
    var k = 0.0;
    var c = 1.0;
    var s = 0.0;
    var kvh = 0.0;
    var kh_sq = 0.0;
    var v_sq = 0.0;
    var max_seq = 0.0;
    var max_score = 0.0;
    var t = 0.0;
    var dot = 0.0;
    var sum_exp = 0.0;
    var inv_sum = 1.0;
    var o_sq_sum = 0.0;
    var h1_sq_sum = 0.0;
    var ffn_sq_sum = 0.0;
    var pli_l: ptr = 0.0;
    var pl = 0.0;
    var ple_sq = 0.0;
    var pli_val = 1.0;

    // 1. Pre-Attention RMSNorm for all prompt tokens: bar(h)_1 = RMSNorm(h, w_in_norm)
    p = 0.0;
    while (p < N) {
        let h_in_vec = cartan_tree_get_f32(token_states, p);
        let dst_norm = cartan_f32_ptr_add(b_norm_h1, p * dim);
        sum_sq = 0.0;
        d = 0.0;
        while (d < dim) {
            let val = cartan_vec_get_f32(h_in_vec, d);
            sum_sq = sum_sq + val * val;
            d = d + 1.0;
        }
        let inv_rms1 = 1.0 / sqrt((sum_sq / dim) + 0.000001);
        d = 0.0;
        while (d < dim) {
            let val = cartan_vec_get_f32(h_in_vec, d);
            let w = cartan_f32_at(w_in_norm, d);
            cartan_set_f32(dst_norm, d, val * inv_rms1 * w);
            d = d + 1.0;
        }
        p = p + 1.0;
    }

    // 2. Batched Q Projections (Row-Outer Multi-Threaded AVX2 GEMV Engine)
    cartan_trans_pool_dispatch_batch(4.0, q_dim, dim, N, q_dim, w_q, g_trans_null_ptr, b_norm_h1, b_q, g_trans_null_ptr);

    // 3. Batched K & V Projections (Row-Outer Multi-Threaded AVX2 Dual GEMV Engine)
    let is_kv_shared = (layer_idx >= 24.0);
    kv_source_layer = layer_idx;
    let is_global = (fmod(layer_idx + 1.0, 6.0) == 0.0);
    if (is_kv_shared > 0.0) {
        if (is_global > 0.0) {
            kv_source_layer = 23.0;
        } else {
            kv_source_layer = 22.0;
        }
    }

    if (is_kv_shared == 0.0) {
        cartan_trans_pool_dispatch_batch(5.0, kv_dim, dim, N, kv_dim, w_k, w_v, b_norm_h1, b_k, b_v);
    }

    // 4. Per-Head Q-Norm, RoPE, Store KV, and Causal GQA Attention across all sequence positions
    let k_cache = cartan_kv_cache_get_k(kv_source_layer);
    let v_cache = cartan_kv_cache_get_v(kv_source_layer);
    let half = head_dim / 2.0;
    rope_angles = half;
    if (is_global > 0.0) {
        rope_angles = 64.0;
    }

    p = 0.0;
    while (p < N) {
        let q_p = cartan_f32_ptr_add(b_q, p * q_dim);

        // Per-Head Q-Norm
        qh = 0.0;
        while (qh < q_heads) {
            let qh_base = qh * head_dim;
            let q_head_ptr = cartan_f32_ptr_add(q_p, qh_base);
            let h_sq = cartan_simd_dot_f32(q_head_ptr, q_head_ptr, head_dim);
            let inv_q_rms = 1.0 / sqrt((h_sq / head_dim) + 0.000001);
            hd = 0.0;
            while (hd < head_dim) {
                let v = cartan_f32_at(q_p, qh_base + hd);
                let w = cartan_f32_at(w_q_norm, hd);
                cartan_set_f32(q_p, qh_base + hd, v * inv_q_rms * w);
                hd = hd + 1.0;
            }
            qh = qh + 1.0;
        }

        // RoPE on Q heads
        qh = 0.0;
        while (qh < q_heads) {
            let qh_base = qh * head_dim;
            k = 0.0;
            while (k < half) {
                let x0 = cartan_f32_at(q_p, qh_base + k);
                let x1 = cartan_f32_at(q_p, qh_base + k + half);
                c = 1.0;
                s = 0.0;
                if (k < rope_angles) {
                    let exponent = (k * 2.0) / head_dim;
                    let freq = 1.0 / pow(rope_theta, exponent);
                    let theta = (start_pos + p) * freq;
                    c = cos(theta);
                    s = sin(theta);
                }
                cartan_set_f32(q_p, qh_base + k, x0 * c - x1 * s);
                cartan_set_f32(q_p, qh_base + k + half, x1 * c + x0 * s);
                k = k + 1.0;
            }
            qh = qh + 1.0;
        }

        // K-Norm, RoPE, and append to KV Cache (only for non-shared layers)
        if (is_kv_shared == 0.0 && k_cache != 0.0 && v_cache != 0.0 && (start_pos + p) < g_kv_cache_max_seq) {
            let k_p = cartan_f32_ptr_add(b_k, p * kv_dim);
            let v_p = cartan_f32_ptr_add(b_v, p * kv_dim);
            let k_dst = cartan_f32_ptr_add(k_cache, (start_pos + p) * kv_dim);
            let v_dst = cartan_f32_ptr_add(v_cache, (start_pos + p) * kv_dim);

            kvh = 0.0;
            while (kvh < kv_heads) {
                let kh_base = kvh * head_dim;
                let k_head_ptr = cartan_f32_ptr_add(k_p, kh_base);
                let kh_sq = cartan_simd_dot_f32(k_head_ptr, k_head_ptr, head_dim);
                let inv_k_rms = 1.0 / sqrt((kh_sq / head_dim) + 0.000001);
                hd = 0.0;
                while (hd < head_dim) {
                    let v = cartan_f32_at(k_p, kh_base + hd);
                    let w = cartan_f32_at(w_k_norm, hd);
                    cartan_set_f32(k_p, kh_base + hd, v * inv_k_rms * w);
                    hd = hd + 1.0;
                }

                k = 0.0;
                while (k < half) {
                    let x0 = cartan_f32_at(k_p, kh_base + k);
                    let x1 = cartan_f32_at(k_p, kh_base + k + half);
                    c = 1.0;
                    s = 0.0;
                    if (k < rope_angles) {
                        let exponent = (k * 2.0) / head_dim;
                        let freq = 1.0 / pow(rope_theta, exponent);
                        let theta = (start_pos + p) * freq;
                        c = cos(theta);
                        s = sin(theta);
                    }
                    cartan_set_f32(k_dst, kh_base + k, x0 * c - x1 * s);
                    cartan_set_f32(k_dst, kh_base + k + half, x1 * c + x0 * s);
                    k = k + 1.0;
                }

                let v_head_ptr = cartan_f32_ptr_add(v_p, kh_base);
                let v_sq = cartan_simd_dot_f32(v_head_ptr, v_head_ptr, head_dim);
                let inv_v_rms = 1.0 / sqrt((v_sq / head_dim) + 0.000001);
                hd = 0.0;
                while (hd < head_dim) {
                    let val = cartan_f32_at(v_p, kh_base + hd);
                    cartan_set_f32(v_dst, kh_base + hd, val * inv_v_rms);
                    hd = hd + 1.0;
                }

                kvh = kvh + 1.0;
            }
        }

        // Causal GQA Attention for token p (attending to positions t = 0 .. start_pos + p)
        let out_p = cartan_f32_ptr_add(b_attn_out, p * q_dim);
        max_seq = start_pos + p + 1.0;
        if (max_seq > g_kv_cache_max_seq) { max_seq = g_kv_cache_max_seq; }
        let hd_unroll_limit = head_dim - 3.0;

        var sink_limit = g_attention_sink_tokens;
        if (sink_limit > max_seq) { sink_limit = max_seq; }
        var win_start = 0.0;
        let win_size = g_attention_window_size;
        if (win_size > 0.0 && max_seq > (sink_limit + win_size)) {
            win_start = max_seq - win_size;
        }
        var p1_limit = max_seq;
        if (win_start > 0.0) { p1_limit = sink_limit; }

        qh = 0.0;
        while (qh < q_heads) {
            kvh = floor(qh / heads_per_kv);
            let q_h = cartan_f32_ptr_add(q_p, qh * head_dim);
            max_score = -1000000000.0;

            // Phase 1a: Attention Sinks (0 .. p1_limit)
            t = 0.0;
            while (t < p1_limit) {
                dot = -10000.0;
                if (k_cache != 0.0) {
                    let k_ht = cartan_f32_ptr_add(k_cache, t * kv_dim + kvh * head_dim);
                    if (cartan_f32_at(k_ht, 0.0) > -9999.0) {
                        dot = cartan_simd_dot_f32(q_h, k_ht, head_dim);
                    }
                }
                cartan_set_f32(g_trans_scores, t, dot);
                if (dot > max_score) { max_score = dot; }
                t = t + 1.0;
            }

            // Phase 1b: Local Sliding Window (win_start .. max_seq)
            if (win_start > 0.0) {
                t = win_start;
                while (t < max_seq) {
                    dot = -10000.0;
                    if (k_cache != 0.0) {
                        let k_ht = cartan_f32_ptr_add(k_cache, t * kv_dim + kvh * head_dim);
                        if (cartan_f32_at(k_ht, 0.0) > -9999.0) {
                            dot = cartan_simd_dot_f32(q_h, k_ht, head_dim);
                        }
                    }
                    cartan_set_f32(g_trans_scores, t, dot);
                    if (dot > max_score) { max_score = dot; }
                    t = t + 1.0;
                }
            }

            sum_exp = 0.0;
            // Phase 2a: Sinks Exponent
            t = 0.0;
            while (t < p1_limit) {
                let ep = exp(cartan_f32_at(g_trans_scores, t) - max_score);
                cartan_set_f32(g_trans_scores, t, ep);
                sum_exp = sum_exp + ep;
                t = t + 1.0;
            }

            // Phase 2b: Sliding Window Exponent
            if (win_start > 0.0) {
                t = win_start;
                while (t < max_seq) {
                    let ep = exp(cartan_f32_at(g_trans_scores, t) - max_score);
                    cartan_set_f32(g_trans_scores, t, ep);
                    sum_exp = sum_exp + ep;
                    t = t + 1.0;
                }
            }

            inv_sum = 1.0;
            if (sum_exp > 0.000000000001) { inv_sum = 1.0 / sum_exp; }

            let out_h = cartan_f32_ptr_add(out_p, qh * head_dim);
            hd = 0.0;
            while (hd < head_dim) {
                cartan_set_f32(out_h, hd, 0.0);
                hd = hd + 1.0;
            }
            if (v_cache != 0.0) {
                // Phase 3a: Sinks V Accumulation
                t = 0.0;
                while (t < p1_limit) {
                    let p_t = cartan_f32_at(g_trans_scores, t) * inv_sum;
                    if (p_t > 0.000000001) {
                        let v_ht = cartan_f32_ptr_add(v_cache, t * kv_dim + kvh * head_dim);
                        hd = 0.0;
                        while (hd < hd_unroll_limit) {
                            let hd1 = hd + 1.0;
                            let hd2 = hd + 2.0;
                            let hd3 = hd + 3.0;
                            let o0 = cartan_f32_at(out_h, hd) + p_t * cartan_f32_at(v_ht, hd);
                            let o1 = cartan_f32_at(out_h, hd1) + p_t * cartan_f32_at(v_ht, hd1);
                            let o2 = cartan_f32_at(out_h, hd2) + p_t * cartan_f32_at(v_ht, hd2);
                            let o3 = cartan_f32_at(out_h, hd3) + p_t * cartan_f32_at(v_ht, hd3);
                            cartan_set_f32(out_h, hd, o0);
                            cartan_set_f32(out_h, hd1, o1);
                            cartan_set_f32(out_h, hd2, o2);
                            cartan_set_f32(out_h, hd3, o3);
                            hd = hd + 4.0;
                        }
                        while (hd < head_dim) {
                            let prev = cartan_f32_at(out_h, hd);
                            let v_val = cartan_f32_at(v_ht, hd);
                            cartan_set_f32(out_h, hd, prev + p_t * v_val);
                            hd = hd + 1.0;
                        }
                    }
                    t = t + 1.0;
                }

                // Phase 3b: Sliding Window V Accumulation
                if (win_start > 0.0) {
                    t = win_start;
                    while (t < max_seq) {
                        let p_t = cartan_f32_at(g_trans_scores, t) * inv_sum;
                        if (p_t > 0.000000001) {
                            let v_ht = cartan_f32_ptr_add(v_cache, t * kv_dim + kvh * head_dim);
                            hd = 0.0;
                            while (hd < hd_unroll_limit) {
                                let hd1 = hd + 1.0;
                                let hd2 = hd + 2.0;
                                let hd3 = hd + 3.0;
                                let o0 = cartan_f32_at(out_h, hd) + p_t * cartan_f32_at(v_ht, hd);
                                let o1 = cartan_f32_at(out_h, hd1) + p_t * cartan_f32_at(v_ht, hd1);
                                let o2 = cartan_f32_at(out_h, hd2) + p_t * cartan_f32_at(v_ht, hd2);
                                let o3 = cartan_f32_at(out_h, hd3) + p_t * cartan_f32_at(v_ht, hd3);
                                cartan_set_f32(out_h, hd, o0);
                                cartan_set_f32(out_h, hd1, o1);
                                cartan_set_f32(out_h, hd2, o2);
                                cartan_set_f32(out_h, hd3, o3);
                                hd = hd + 4.0;
                            }
                            while (hd < head_dim) {
                                let prev = cartan_f32_at(out_h, hd);
                                let v_val = cartan_f32_at(v_ht, hd);
                                cartan_set_f32(out_h, hd, prev + p_t * v_val);
                                hd = hd + 1.0;
                            }
                        }
                        t = t + 1.0;
                    }
                }
            }
            qh = qh + 1.0;
        }

        p = p + 1.0;
    }

    // 5. Batched Output Projection W_o (Row-Outer Multi-Threaded AVX2 GEMV Engine)
    cartan_trans_pool_dispatch_batch(4.0, dim, q_dim, N, dim, w_o, g_trans_null_ptr, b_attn_out, b_h1, g_trans_null_ptr);

    // Post-Attention RMSNorm + Residual + Pre-FFN RMSNorm for each token p
    p = 0.0;
    while (p < N) {
        let h_in_vec = cartan_tree_get_f32(token_states, p);
        let o_raw = cartan_f32_ptr_add(b_h1, p * dim);
        o_sq_sum = cartan_simd_dot_f32(o_raw, o_raw, dim);
        let inv_o_rms = 1.0 / sqrt((o_sq_sum / dim) + 0.000001);
        let h1_p = cartan_f32_ptr_add(b_h1, p * dim);
        h1_sq_sum = 0.0;
        d = 0.0;
        while (d < dim) {
            let x = cartan_vec_get_f32(h_in_vec, d);
            let o = cartan_f32_at(o_raw, d);
            let w = cartan_f32_at(w_post_attn, d);
            let h1_val = x + o * inv_o_rms * w;
            cartan_set_f32(h1_p, d, h1_val);
            h1_sq_sum = h1_sq_sum + h1_val * h1_val;
            d = d + 1.0;
        }

        let inv_h1_rms = 1.0 / sqrt((h1_sq_sum / dim) + 0.000001);
        let norm_h2_p = cartan_f32_ptr_add(b_norm_h2, p * dim);
        d = 0.0;
        while (d < dim) {
            let val = cartan_f32_at(h1_p, d);
            let w = cartan_f32_at(w_pre_ffn, d);
            cartan_set_f32(norm_h2_p, d, val * inv_h1_rms * w);
            d = d + 1.0;
        }
        p = p + 1.0;
    }

    // 6. Batched GeGLU Gate & Up and Down Projections (Row-Outer Multi-Threaded AVX2 GEMV Engine)
    cartan_trans_pool_dispatch_batch(3.0, inter_dim, dim, N, inter_dim, w_gate, w_up, b_norm_h2, b_act, g_trans_null_ptr);
    cartan_trans_pool_dispatch_batch(4.0, dim, inter_dim, N, dim, w_down, g_trans_null_ptr, b_act, b_ffn, g_trans_null_ptr);

    // 7. Post-FFN RMSNorm, Residual Addition, PLE Gating, and Layer Scalar Scaling
    p = 0.0;
    while (p < N) {
        let h1_p = cartan_f32_ptr_add(b_h1, p * dim);
        let ffn_p = cartan_f32_ptr_add(b_ffn, p * dim);
        ffn_sq_sum = cartan_simd_dot_f32(ffn_p, ffn_p, dim);
        let inv_ffn_rms = 1.0 / sqrt((ffn_sq_sum / dim) + 0.000001);
        d = 0.0;
        while (d < dim) {
            let h1_val = cartan_f32_at(h1_p, d);
            let ffn_val = cartan_f32_at(ffn_p, d);
            let w = cartan_f32_at(w_post_ffn, d);
            cartan_set_f32(h1_p, d, h1_val + ffn_val * inv_ffn_rms * w);
            d = d + 1.0;
        }
        p = p + 1.0;
    }

    if (has_ple > 0.0) {
        var b_ple_act = g_trans_b_ple_act;
        var b_ple_proj = g_trans_b_ple_proj;
        var is_ple_dynamic = 0.0;
        if (N > 4096.0 || b_ple_act == 0.0) {
            is_ple_dynamic = 1.0;
            b_ple_act = malloc(N * ple_dim * 4.0);
            b_ple_proj = malloc(N * dim * 4.0);
        }

        // Batched PLE Gate GEMV across all N prompt tokens
        cartan_trans_pool_dispatch_batch(4.0, ple_dim, dim, N, ple_dim, w_ple_gate, g_trans_null_ptr, b_h1, b_ple_act, g_trans_null_ptr);

        p = 0.0;
        while (p < N) {
            let tok_id = cartan_vec_get_f32(prompt_tokens, p);
            pli_l = 0.0;
            if (g_prompt_pli_buf != 0.0) {
                pli_l = cartan_f32_ptr_add(g_prompt_pli_buf, p * 10752.0 + layer_idx * 256.0);
            } else if (tok_id >= 0.0 && tok_id < 262144.0) {
                pli_l = cartan_get_cached_pli(layer_idx, tok_id);
            }
            let act_p = cartan_f32_ptr_add(b_ple_act, p * ple_dim);
            pl = 0.0;
            while (pl < ple_dim) {
                let dot_gate = cartan_f32_at(act_p, pl);
                pli_val = 1.0;
                if (pli_l != 0.0) {
                    pli_val = cartan_f32_at(pli_l, pl);
                }
                cartan_set_f32(act_p, pl, cartan_fast_gelu_tanh(dot_gate) * pli_val);
                pl = pl + 1.0;
            }
            p = p + 1.0;
        }

        // Batched PLE Projection GEMV across all N prompt tokens
        cartan_trans_pool_dispatch_batch(4.0, dim, ple_dim, N, dim, w_ple_proj, g_trans_null_ptr, b_ple_act, b_ple_proj, g_trans_null_ptr);

        p = 0.0;
        while (p < N) {
            let h_in_vec = cartan_tree_get_f32(token_states, p);
            let h2_p = cartan_f32_ptr_add(b_h1, p * dim);
            let proj_p = cartan_f32_ptr_add(b_ple_proj, p * dim);
            ple_sq = cartan_simd_dot_f32(proj_p, proj_p, dim);
            let inv_ple_rms = 1.0 / sqrt((ple_sq / dim) + 0.000001);
            d = 0.0;
            while (d < dim) {
                let h2_val = cartan_f32_at(h2_p, d);
                let proj_val = cartan_f32_at(proj_p, d);
                let norm_val = cartan_f32_at(w_ple_norm, d);
                cartan_vec_set_f32(h_in_vec, d, (h2_val + proj_val * inv_ple_rms * norm_val) * layer_scalar);
                d = d + 1.0;
            }
            p = p + 1.0;
        }

        if (is_ple_dynamic == 1.0) {
            free(b_ple_act);
            free(b_ple_proj);
        }
    } else {
        p = 0.0;
        while (p < N) {
            let h_in_vec = cartan_tree_get_f32(token_states, p);
            let h2_p = cartan_f32_ptr_add(b_h1, p * dim);
            d = 0.0;
            while (d < dim) {
                cartan_vec_set_f32(h_in_vec, d, cartan_f32_at(h2_p, d) * layer_scalar);
                d = d + 1.0;
            }
            p = p + 1.0;
        }
    }

    if (is_dynamic == 1.0) {
        free(b_norm_h1);
        free(b_q);
        free(b_k);
        free(b_v);
        free(b_attn_out);
        free(b_h1);
        free(b_norm_h2);
        free(b_act);
        free(b_ffn);
    }

    return 1.0;
}



