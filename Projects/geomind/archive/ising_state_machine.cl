include "../../src/std/physics.cl";
include "../../src/std/collections.cl";


struct IsingState {
    num_spins: float;
    temperature: float;
    spins: ptr;
}

fn geomind_ising_relax(spins: ptr, num_spins: float, temp: float, steps: float) -> ptr {
    if (spins == 0.0) { return spins; }
    var step = 0.0;
    while (step < steps) {
        var i = 0.0;
        while (i < num_spins) {
            let s = cartan_vec_get_f32(spins, i);
            let relaxed_s = hopfield_spin_relax(s, 0.0, temp);
            cartan_vec_set_f32(spins, i, relaxed_s);
            i = i + 1.0;
        }
        step = step + 1.0;
    }
    return spins;
}

// Coupled Glauber dynamics decision relaxation with interactive spin coupling J and external field h
fn geomind_ising_decision_step(spins: ptr, J: ptr, h: ptr, num_spins: float, beta: float, steps: float) {
    if (spins == 0.0 || num_spins <= 0.0) { return; }
    var step = 0.0;
    while (step < steps) {
        var i = 0.0;
        while (i < num_spins) {
            var h_ext = 0.0;
            if (h != 0.0) { h_ext = h[i]; }

            // Compute net internal magnetic field: h_int = sum_j J[i, j] * s[j]
            var h_int = 0.0;
            if (J != 0.0) {
                let row_offset = i * num_spins;
                var j = 0.0;
                while (j < num_spins) {
                    if (i != j) {
                        h_int = h_int + J[row_offset + j] * spins[j];
                    }
                    j = j + 1.0;
                }
            }

            let net_h = h_ext + h_int;
            let current_s = spins[i];
            let relaxed_s = hopfield_spin_relax(current_s, net_h, beta);
            spins[i] = relaxed_s;
            i = i + 1.0;
        }
        step = step + 1.0;
    }
}

// Computes thermodynamic variational free energy F = E - T * S (decision uncertainty metric)
fn geomind_ising_free_energy(spins: ptr, J: ptr, h: ptr, num_spins: float, beta: float) -> float {
    if (spins == 0.0 || num_spins <= 0.0) { return 0.0; }
    var energy = 0.0;
    var entropy = 0.0;

    var i = 0.0;
    while (i < num_spins) {
        let si = spins[i];
        // External field energy contribution: -h_i * s_i
        if (h != 0.0) {
            energy = energy - h[i] * si;
        }

        // Spin-spin coupling energy: -0.5 * sum_j J_ij * s_i * s_j
        if (J != 0.0) {
            let row_offset = i * num_spins;
            var j = 0.0;
            while (j < num_spins) {
                if (i != j) {
                    energy = energy - 0.5 * J[row_offset + j] * si * spins[j];
                }
                j = j + 1.0;
            }
        }

        // Mean-field entropy: -sum [ p+ ln p+ + p- ln p- ] where p+ = (1 + s)/2
        var p_plus = (1.0 + si) * 0.5;
        if (p_plus < 0.000001) { p_plus = 0.000001; }
        if (p_plus > 0.999999) { p_plus = 0.999999; }
        let p_minus = 1.0 - p_plus;

        entropy = entropy - (p_plus * log(p_plus) + p_minus * log(p_minus));
        i = i + 1.0;
    }

    var temp = 1.0;
    if (beta > 0.0) { temp = 1.0 / beta; }
    return energy - temp * entropy;
}

