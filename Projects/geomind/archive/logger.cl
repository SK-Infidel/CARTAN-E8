// test/geomind/logger.cl
// GeoMind Real-Time Metric Logger: test/geomind/logger.cl

extern fn printf(format: string) -> i32;
extern fn cartan_flush(v: float) -> float;
extern fn cartan_float_to_string(v: float) -> string;
extern fn cartan_string_concat(s1: string, s2: string) -> string;
extern fn cartan_write_file(path: string, content: string) -> float;

fn geomind_log_init() {
    printf("[Logger] Initializing GeoMind Log System in scratch/training.log...\n");
    cartan_write_file("scratch/training.log", "# GeoMind Training Telemetry Log\n# Step, Total_Steps, Loss, Tokens_Per_Sec, Phase_Coherence\n");
    cartan_flush(0.0);
}

fn geomind_format_metrics(step: float, total_steps: float, loss: float, tokens_per_sec: float, phase_coherence: float) -> string {
    var line = "  [Step ";
    line = cartan_string_concat(line, cartan_float_to_string(step));
    line = cartan_string_concat(line, "/");
    line = cartan_string_concat(line, cartan_float_to_string(total_steps));
    line = cartan_string_concat(line, "] Loss: ");
    line = cartan_string_concat(line, cartan_float_to_string(loss));
    line = cartan_string_concat(line, " | Tok/s: ");
    line = cartan_string_concat(line, cartan_float_to_string(tokens_per_sec));
    line = cartan_string_concat(line, " | Phase Coherence: ");
    line = cartan_string_concat(line, cartan_float_to_string(phase_coherence));
    line = cartan_string_concat(line, "\n");
    return line;
}

fn geomind_log_step(step: float, total_steps: float, loss: float, tokens_per_sec: float, phase_coherence: float) {
    let formatted = geomind_format_metrics(step, total_steps, loss, tokens_per_sec, phase_coherence);
    printf(formatted);
    cartan_flush(0.0);
}
