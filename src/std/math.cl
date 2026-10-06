// src/std/math.cl
// CARTAN Standard Library: Production-Grade Comprehensive Mathematical Functions Module

extern fn sqrt(x: float) -> float;
extern fn pow(x: float, y: float) -> float;
extern fn exp(x: float) -> float;
extern fn log(x: float) -> float;
extern fn log10(x: float) -> float;
extern fn log2(x: float) -> float;
extern fn fabs(x: float) -> float;
extern fn sin(x: float) -> float;
extern fn cos(x: float) -> float;
extern fn tan(x: float) -> float;
extern fn asin(x: float) -> float;
extern fn acos(x: float) -> float;
extern fn atan(x: float) -> float;
extern fn atan2(y: float, x: float) -> float;
extern fn sinh(x: float) -> float;
extern fn cosh(x: float) -> float;
extern fn tanh(x: float) -> float;
extern fn floor(x: float) -> float;
extern fn ceil(x: float) -> float;
extern fn fmod(x: float, y: float) -> float;
extern fn copysign(x: float, y: float) -> float;

fn math_abs(x: float) -> float { return fabs(x); }
fn math_abs_val(x: float) -> float { return fabs(x); }
fn math_sqrt(x: float) -> float { return sqrt(x); }
fn math_pow(base: float, exp_val: float) -> float { return pow(base, exp_val); }
fn math_exp(x: float) -> float { return exp(x); }
fn math_log(x: float) -> float { return log(x); }
fn math_log10(x: float) -> float { return log10(x); }
fn math_log2(x: float) -> float { return log2(x); }
fn math_sin(x: float) -> float { return sin(x); }
fn math_cos(x: float) -> float { return cos(x); }
fn math_tan(x: float) -> float { return tan(x); }
fn math_asin(x: float) -> float { return asin(x); }
fn math_acos(x: float) -> float { return acos(x); }
fn math_atan(x: float) -> float { return atan(x); }
fn math_atan2(y: float, x: float) -> float { return atan2(y, x); }
fn math_sinh(x: float) -> float { return sinh(x); }
fn math_cosh(x: float) -> float { return cosh(x); }
fn math_tanh(x: float) -> float { return tanh(x); }
fn math_floor(x: float) -> float { return floor(x); }
fn math_ceil(x: float) -> float { return ceil(x); }
fn math_mod_val(x: float, y: float) -> float { if (y == 0.0) { return 0.0; } let rem = fmod(x, y); if (rem < 0.0 && y > 0.0) { return rem + y; } return rem; }
fn math_mod(x: float, y: float) -> float { if (y == 0.0) { return 0.0; } let rem = fmod(x, y); if (rem < 0.0 && y > 0.0) { return rem + y; } return rem; }
fn math_hypot(x: float, y: float) -> float { return sqrt(x * x + y * y); }
fn math_clamp(val: float, min_val: float, max_val: float) -> float {
    if (val < min_val) { return min_val; }
    if (val > max_val) { return max_val; }
    return val;
}
fn math_lerp(a: float, b: float, t: float) -> float { return a + t * (b - a); }
