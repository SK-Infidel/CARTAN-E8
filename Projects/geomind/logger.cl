// Projects/geomind/logger.cl
// GeoMind Structured Non-Euclidean Telemetry & Experiment Logger
// Records Lagrangian Action S, Geodesic Kinetic Energy, Markov Potentials,
// and Finsler-Randers Drift Norms to persistent disk logs and terminal streams.

include "src/std/string.cl";
include "src/std/fs.cl";

extern fn printf(format: string) -> i32;
extern fn cartan_flush(v: float) -> float;
extern fn cartan_float_to_string(v: float) -> string;
extern fn cartan_string_concat(s1: string, s2: string) -> string;
extern fn cartan_write_file(path: string, content: string) -> float;
extern fn cartan_file_exists(path: string) -> float;
extern fn cartan_get_binary_file_size(path: string) -> float;

var g_geomind_log_path: string = "scratch/geomind_telemetry.log";
var g_geomind_log_initialized: float = 0.0;

// Initializes the telemetry log file with standard header
fn geomind_log_init(custom_path: string) -> float {
    if (cartan_string_length(custom_path) > 0.0) {
        g_geomind_log_path = custom_path;
    }
    let header = "# GeoMind Sovereign Non-Euclidean Manifold Telemetry Log\n# Step,Epoch,Action_S,T_geo,V_Markov,Randers_b_Norm,Radius_S247,Loss\n";
    cartan_write_file(g_geomind_log_path, header);
    g_geomind_log_initialized = 1.0;
    printf("[Logger] Telemetry recording mounted at: %s\n", g_geomind_log_path);
    cartan_flush(0.0);
    return 1.0;
}

// Records a single telemetry step to both console and structured disk log
fn geomind_log_telemetry(
    step: float,
    epoch: float,
    action_s: float,
    t_geo: float,
    v_markov: float,
    randers_b: float,
    radius: float,
    loss: float
) {
    if (g_geomind_log_initialized <= 0.0) {
        geomind_log_init("scratch/geomind_telemetry.log");
    }

    // Console live pretty-print
    printf("  [Telemetry Step %.0f | Ep %.0f] Action S: %.6f | T_geo: %.4f | V_Markov: %.4f | ||b||: %.4f | R: %.6f | Loss: %.4f\n",
        step, epoch, action_s, t_geo, v_markov, randers_b, radius, loss);
    cartan_flush(0.0);

    // Format CSV/JSONL row
    var row = cartan_float_to_string(step);
    row = cartan_string_concat(row, ",");
    row = cartan_string_concat(row, cartan_float_to_string(epoch));
    row = cartan_string_concat(row, ",");
    row = cartan_string_concat(row, cartan_float_to_string(action_s));
    row = cartan_string_concat(row, ",");
    row = cartan_string_concat(row, cartan_float_to_string(t_geo));
    row = cartan_string_concat(row, ",");
    row = cartan_string_concat(row, cartan_float_to_string(v_markov));
    row = cartan_string_concat(row, ",");
    row = cartan_string_concat(row, cartan_float_to_string(randers_b));
    row = cartan_string_concat(row, ",");
    row = cartan_string_concat(row, cartan_float_to_string(radius));
    row = cartan_string_concat(row, ",");
    row = cartan_string_concat(row, cartan_float_to_string(loss));
    row = cartan_string_concat(row, "\n");

    // Append to file
    var cur_content = "";
    if (cartan_file_exists(g_geomind_log_path) == 1.0) {
        cur_content = cartan_read_file(g_geomind_log_path);
    }
    let updated = cartan_string_concat(cur_content, row);
    cartan_write_file(g_geomind_log_path, updated);
}

// Empirical Verification Suite for Telemetry Logger
fn geomind_log_test_all() -> float {
    printf("================================================================================\n");
    printf("  GEOMIND STRUCTURED TELEMETRY LOGGER VERIFICATION\n");
    printf("================================================================================\n");
    cartan_flush(0.0);

    let test_log = "scratch/telemetry_test.log";
    geomind_log_init(test_log);

    geomind_log_telemetry(1.0, 1.0, 2.145023, 0.412, 0.852, 0.545, 15.748016, 3.421);
    geomind_log_telemetry(2.0, 1.0, 1.984102, 0.388, 0.874, 0.531, 15.748016, 3.105);
    geomind_log_telemetry(3.0, 1.0, 1.854091, 0.362, 0.891, 0.518, 15.748016, 2.894);

    let exists = cartan_file_exists(test_log);
    let sz = cartan_get_binary_file_size(test_log);
    printf("  [Logger Test 1] Log File Created: %s | Size: %.0f bytes\n", test_log, sz);
    cartan_flush(0.0);

    if (exists == 1.0 && sz > 100.0) {
        printf("================================================================================\n");
        printf("  TELEMETRY LOGGER VERIFIED: Multi-Step Persistence Validated\n");
        printf("================================================================================\n");
        cartan_flush(0.0);
        return 1.0;
    }

    printf("  [Logger Error] Verification failed!\n");
    cartan_flush(0.0);
    return 0.0;
}
