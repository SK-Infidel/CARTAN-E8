// src/std/plasticity.cl
// CARTAN Standard Library: Lock-Free Hebbian Synaptic Plasticity & Exponential Decay Kernel
// Neuro-Symbolic Expert System (NSES) Phase 3 Core

include "src/std/math.cl";
include "src/std/collections.cl";

// Default Plasticity Constants
// HEBBIAN_MAX_WEIGHT = 5.0
// HEBBIAN_MIN_WEIGHT = 1.0
// HEBBIAN_DELTA_W = 0.50
// HEBBIAN_LAMBDA = 0.01

// Compute decayed synaptic weight given time delta: w_eff = max(w * exp(-lambda * dt), min_w)
fn hebbian_compute_decayed_weight(current_w: float, last_ts: float, current_ts: float, lambda: float, min_w: float) -> float {
    if (current_ts <= last_ts || lambda <= 0.0) {
        return current_w;
    }
    let dt = current_ts - last_ts;
    let decay = exp(-1.0 * lambda * dt);
    let decayed_w = current_w * decay;
    if (current_w >= min_w && decayed_w < min_w) {
        return min_w;
    }
    return decayed_w;
}

// Strengthen a single synaptic edge weight with saturation clamp: min(w + delta_w, max_w)
fn hebbian_strengthen_weight(current_w: float, delta_w: float, max_w: float) -> float {
    let next_w = current_w + delta_w;
    if (next_w > max_w) { return max_w; }
    return next_w;
}

// In-place atomic update for a single CSR edge
fn hebbian_update_edge(edge_weights: ptr, edge_timestamps: ptr, edge_idx: float, new_weight: float, current_ts: float) {
    if (edge_weights != 0.0 && edge_idx >= 0.0) {
        collections_list_set(edge_weights, edge_idx, new_weight);
    }
    if (edge_timestamps != 0.0 && edge_idx >= 0.0) {
        collections_list_set(edge_timestamps, edge_idx, current_ts);
    }
}

// In-place reinforcement of a single edge weight
fn hebbian_reinforce_edge(edge_weights: ptr, edge_timestamps: ptr, edge_idx: float, delta_w: float, max_w: float, current_ts: float) -> float {
    if (edge_weights == 0.0 || edge_timestamps == 0.0 || edge_idx < 0.0) { return 0.0; }
    let cur_w = collections_list_get(edge_weights, edge_idx);
    let new_w = hebbian_strengthen_weight(cur_w, delta_w, max_w);
    hebbian_update_edge(edge_weights, edge_timestamps, edge_idx, new_w, current_ts);
    return new_w;
}

// In-place lazy exponential decay of a single edge weight
fn hebbian_decay_edge(edge_weights: ptr, edge_timestamps: ptr, edge_idx: float, current_ts: float, lambda: float, min_w: float) -> float {
    let cur_w = collections_list_get(edge_weights, edge_idx);
    let last_ts = collections_list_get(edge_timestamps, edge_idx);
    let decayed_w = hebbian_compute_decayed_weight(cur_w, last_ts, current_ts, lambda, min_w);
    hebbian_update_edge(edge_weights, edge_timestamps, edge_idx, decayed_w, current_ts);
    return decayed_w;
}
