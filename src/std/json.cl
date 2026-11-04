// src/std/json.cl
// CARTAN Standard Library: Pure-CARTAN Zero-Allocation JSON Parsing & Serialization Engine

include "src/std/string.cl";
include "src/std/prompt_scaffold.cl";

extern fn malloc(size: float) -> ptr;
extern fn free(p: ptr) -> void;
extern fn atof(s: string) -> float;
extern fn cartan_string_length(s: string) -> float;
extern fn cartan_string_substring(s: string, start: float, end_idx: float) -> string;
extern fn cartan_string_concat(s1: string, s2: string) -> string;
extern fn cartan_string_eq(s1: string, s2: string) -> float;
extern fn cartan_byte_at(s: string, idx: float) -> float;
extern fn cartan_vec_create() -> ptr;
extern fn cartan_vec_push_f32(v: ptr, val: float) -> void;
extern fn cartan_vec_get_f32(v: ptr, idx: float) -> float;
extern fn cartan_vec_len(v: ptr) -> float;
extern fn cartan_vec_free(v: ptr) -> void;
extern fn cartan_tree_create() -> ptr;
extern fn cartan_tree_push(t: ptr, item: ptr) -> void;
extern fn cartan_tree_get_f32(t: ptr, idx: float) -> ptr;
extern fn cartan_tree_len_f(t: ptr) -> float;
extern fn cartan_tree_free(t: ptr) -> void;
extern fn cartan_float_to_string(v: float) -> string;

// Decodes standard JSON escape sequences in a string slice into unescaped text
fn json_unescape_string(raw: string) -> string {
    if (raw == 0.0) { return ""; }
    let len = cartan_string_length(raw);
    if (len == 0.0) { return ""; }

    // Fast path: check if any backslash escape is present
    var has_escape = 0.0;
    var i = 0.0;
    while (i < len) {
        if (cartan_byte_at(raw, i) == 92.0) { // '\'
            has_escape = 1.0;
            break;
        }
        i = i + 1.0;
    }
    if (has_escape == 0.0) {
        return cartan_string_concat(raw, "");
    }

    let scaffold = prompt_scaffold_create(len + 64.0);
    var p = 0.0;
    while (p < len) {
        let b = cartan_byte_at(raw, p);
        if (b == 92.0 && p + 1.0 < len) { // '\'
            let nb = cartan_byte_at(raw, p + 1.0);
            if (nb == 34.0) { // '\"' -> '"'
                prompt_scaffold_append_char(scaffold, 34.0);
                p = p + 2.0;
            } else if (nb == 92.0) { // '\\' -> '\'
                prompt_scaffold_append_char(scaffold, 92.0);
                p = p + 2.0;
            } else if (nb == 110.0) { // '\n' -> newline (10)
                prompt_scaffold_append_char(scaffold, 10.0);
                p = p + 2.0;
            } else if (nb == 114.0) { // '\r' -> carriage return (13)
                prompt_scaffold_append_char(scaffold, 13.0);
                p = p + 2.0;
            } else if (nb == 116.0) { // '\t' -> tab (9)
                prompt_scaffold_append_char(scaffold, 9.0);
                p = p + 2.0;
            } else if (nb == 47.0) { // '\/' -> '/' (47)
                prompt_scaffold_append_char(scaffold, 47.0);
                p = p + 2.0;
            } else {
                prompt_scaffold_append_char(scaffold, b);
                p = p + 1.0;
            }
        } else {
            prompt_scaffold_append_char(scaffold, b);
            p = p + 1.0;
        }
    }
    let res = prompt_scaffold_get_text(scaffold);
    let out_str = cartan_string_concat(res, "");
    prompt_scaffold_free(scaffold);
    return out_str;
}

// Locates the byte offset of a JSON key's value (immediately following the ':')
fn json_find_value_offset(json_str: string, key: string) -> float {
    if (json_str == 0.0 || key == 0.0) { return -1.0; }
    let len = cartan_string_length(json_str);
    let k_len = cartan_string_length(key);
    if (len <= 0.0 || k_len <= 0.0) { return -1.0; }

    var pattern = "\"";
    pattern = cartan_string_concat(pattern, key);
    pattern = cartan_string_concat(pattern, "\"");
    let pat_len = cartan_string_length(pattern);

    var pos = string_index_of_offset(json_str, pattern, 0.0);
    free(pattern);

    while (pos >= 0.0 && pos < len) {
        var colon_pos = pos + pat_len;
        while (colon_pos < len) {
            let b = cartan_byte_at(json_str, colon_pos);
            if (b == 58.0) { // ':'
                // Scan past whitespace
                var val_start = colon_pos + 1.0;
                while (val_start < len) {
                    let vb = cartan_byte_at(json_str, val_start);
                    if (vb != 32.0 && vb != 9.0 && vb != 10.0 && vb != 13.0) {
                        return val_start;
                    }
                    val_start = val_start + 1.0;
                }
                return -1.0;
            }
            if (b != 32.0 && b != 9.0 && b != 10.0 && b != 13.0) {
                // Not whitespace before colon -> false match (e.g. key inside string)
                break;
            }
            colon_pos = colon_pos + 1.0;
        }
        var next_pattern = "\"";
        next_pattern = cartan_string_concat(next_pattern, key);
        next_pattern = cartan_string_concat(next_pattern, "\"");
        pos = string_index_of_offset(json_str, next_pattern, pos + 1.0);
        free(next_pattern);
    }
    return -1.0;
}

// Extracts a string value for the given JSON key, handling unescaping
fn json_get_string(json_str: string, key: string) -> string {
    let val_start = json_find_value_offset(json_str, key);
    if (val_start < 0.0) { return ""; }
    let len = cartan_string_length(json_str);

    let first_b = cartan_byte_at(json_str, val_start);
    if (first_b == 34.0) { // Quoted string '"'
        let s_start = val_start + 1.0;
        var p = s_start;
        while (p < len) {
            let b = cartan_byte_at(json_str, p);
            if (b == 34.0) { // Closing quote
                // Check if escaped
                var backslashes = 0.0;
                var back_p = p - 1.0;
                while (back_p >= s_start && cartan_byte_at(json_str, back_p) == 92.0) {
                    backslashes = backslashes + 1.0;
                    back_p = back_p - 1.0;
                }
                let rem = backslashes - (floor(backslashes / 2.0) * 2.0);
                if (rem == 0.0) {
                    // Even number of backslashes -> genuine unescaped quote
                    let raw_slice = cartan_string_substring(json_str, s_start, p);
                    let unescaped = json_unescape_string(raw_slice);
                    free(raw_slice);
                    return unescaped;
                }
            }
            p = p + 1.0;
        }
        return "";
    }

    // Unquoted scalar fallback (e.g. null, true, false, number)
    var p_end = val_start;
    while (p_end < len) {
        let b = cartan_byte_at(json_str, p_end);
        if (b == 44.0 || b == 125.0 || b == 93.0 || b == 32.0 || b == 10.0 || b == 13.0) {
            break;
        }
        p_end = p_end + 1.0;
    }
    if (p_end > val_start) {
        return cartan_string_substring(json_str, val_start, p_end);
    }
    return "";
}

// Extracts a floating point number for the given JSON key
fn json_get_float(json_str: string, key: string, default_val: float) -> float {
    let val_start = json_find_value_offset(json_str, key);
    if (val_start < 0.0) { return default_val; }
    let len = cartan_string_length(json_str);

    var s_start = val_start;
    var is_quoted = 0.0;
    if (cartan_byte_at(json_str, s_start) == 34.0) { // '"'
        is_quoted = 1.0;
        s_start = s_start + 1.0;
    }

    var p_end = s_start;
    while (p_end < len) {
        let b = cartan_byte_at(json_str, p_end);
        if (is_quoted == 1.0) {
            if (b == 34.0) { break; }
        } else {
            if (b == 44.0 || b == 125.0 || b == 93.0 || b == 32.0 || b == 9.0 || b == 10.0 || b == 13.0) {
                break;
            }
        }
        p_end = p_end + 1.0;
    }

    if (p_end > s_start) {
        let num_str = cartan_string_substring(json_str, s_start, p_end);
        let val = atof(num_str);
        free(num_str);
        return val;
    }
    return default_val;
}

// Extracts a boolean flag (1.0 for true, 0.0 for false or absent)
fn json_get_bool(json_str: string, key: string) -> float {
    let val_start = json_find_value_offset(json_str, key);
    if (val_start < 0.0) { return 0.0; }
    let len = cartan_string_length(json_str);

    if (val_start + 4.0 <= len) {
        let b0 = cartan_byte_at(json_str, val_start);
        let b1 = cartan_byte_at(json_str, val_start + 1.0);
        let b2 = cartan_byte_at(json_str, val_start + 2.0);
        let b3 = cartan_byte_at(json_str, val_start + 3.0);
        if (b0 == 116.0 && b1 == 114.0 && b2 == 117.0 && b3 == 101.0) { // "true"
            return 1.0;
        }
    }
    return 0.0;
}

// Extracts raw JSON array substring "[...]" for the given key, balancing nested brackets
fn json_get_array(json_str: string, key: string) -> string {
    let val_start = json_find_value_offset(json_str, key);
    if (val_start < 0.0) { return ""; }
    let len = cartan_string_length(json_str);

    if (cartan_byte_at(json_str, val_start) != 91.0) { // '['
        return "";
    }

    var depth = 0.0;
    var in_string = 0.0;
    var p = val_start;

    while (p < len) {
        let b = cartan_byte_at(json_str, p);
        if (b == 34.0) { // '"'
            var backslashes = 0.0;
            var back_p = p - 1.0;
            while (back_p >= val_start && cartan_byte_at(json_str, back_p) == 92.0) {
                backslashes = backslashes + 1.0;
                back_p = back_p - 1.0;
            }
            let rem = backslashes - (floor(backslashes / 2.0) * 2.0);
            if (rem == 0.0) {
                if (in_string == 1.0) { in_string = 0.0; }
                else { in_string = 1.0; }
            }
        } else if (in_string == 0.0) {
            if (b == 91.0) { // '['
                depth = depth + 1.0;
            } else if (b == 93.0) { // ']'
                depth = depth - 1.0;
                if (depth == 0.0) {
                    return cartan_string_substring(json_str, val_start, p + 1.0);
                }
            }
        }
        p = p + 1.0;
    }
    return "";
}

// Parses a JSON array of floats into a newly allocated cartan_vec
fn json_parse_float_array(array_str: string, default_val: float) -> ptr {
    let vec = cartan_vec_create();
    if (array_str == 0.0) { return vec; }
    let len = cartan_string_length(array_str);
    if (len < 2.0) { return vec; }

    var p = 0.0;
    while (p < len && cartan_byte_at(array_str, p) != 91.0) { // '['
        p = p + 1.0;
    }
    if (p >= len) { return vec; }
    p = p + 1.0; // Skip '['

    while (p < len) {
        // Skip whitespace
        while (p < len) {
            let b = cartan_byte_at(array_str, p);
            if (b != 32.0 && b != 9.0 && b != 10.0 && b != 13.0) { break; }
            p = p + 1.0;
        }
        if (p >= len || cartan_byte_at(array_str, p) == 93.0) { // ']'
            break;
        }

        var num_start = p;
        var is_quoted = 0.0;
        if (cartan_byte_at(array_str, num_start) == 34.0) {
            is_quoted = 1.0;
            num_start = num_start + 1.0;
            p = num_start;
        }

        while (p < len) {
            let b = cartan_byte_at(array_str, p);
            if (is_quoted == 1.0) {
                if (b == 34.0) { break; }
            } else {
                if (b == 44.0 || b == 93.0 || b == 32.0 || b == 9.0 || b == 10.0 || b == 13.0) {
                    break;
                }
            }
            p = p + 1.0;
        }

        if (p > num_start) {
            let num_slice = cartan_string_substring(array_str, num_start, p);
            let val = atof(num_slice);
            free(num_slice);
            cartan_vec_push_f32(vec, val);
        }

        if (is_quoted == 1.0 && p < len && cartan_byte_at(array_str, p) == 34.0) {
            p = p + 1.0;
        }

        // Find next comma or bracket
        while (p < len) {
            let b = cartan_byte_at(array_str, p);
            if (b == 44.0) { // ','
                p = p + 1.0;
                break;
            }
            if (b == 93.0) { // ']'
                break;
            }
            p = p + 1.0;
        }
    }
    return vec;
}

// Parses a JSON array of strings into a newly allocated cartan_tree list
fn json_parse_string_array(array_str: string) -> ptr {
    let list = cartan_tree_create();
    if (array_str == 0.0) { return list; }
    let len = cartan_string_length(array_str);
    if (len < 2.0) { return list; }

    var p = 0.0;
    while (p < len && cartan_byte_at(array_str, p) != 91.0) { // '['
        p = p + 1.0;
    }
    if (p >= len) { return list; }
    p = p + 1.0;

    var in_str = 0.0;
    var str_start = 0.0;

    while (p < len) {
        let b = cartan_byte_at(array_str, p);
        if (b == 93.0 && in_str == 0.0) { // ']'
            break;
        }
        if (b == 34.0) { // '"'
            if (in_str == 0.0) {
                in_str = 1.0;
                str_start = p + 1.0;
            } else {
                // Check if escaped
                var backslashes = 0.0;
                var back_p = p - 1.0;
                while (back_p >= str_start && cartan_byte_at(array_str, back_p) == 92.0) {
                    backslashes = backslashes + 1.0;
                    back_p = back_p - 1.0;
                }
                let rem = backslashes - (floor(backslashes / 2.0) * 2.0);
                if (rem == 0.0) {
                    in_str = 0.0;
                    let raw_item = cartan_string_substring(array_str, str_start, p);
                    let unescaped = json_unescape_string(raw_item);
                    free(raw_item);
                    cartan_tree_push(list, unescaped);
                }
            }
        }
        p = p + 1.0;
    }
    return list;
}

// Parses a JSON array of objects "[{...}, {...}]" into a cartan_tree list of raw object substrings
fn json_parse_object_array(array_str: string) -> ptr {
    let list = cartan_tree_create();
    if (array_str == 0.0) { return list; }
    let len = cartan_string_length(array_str);
    if (len < 2.0) { return list; }

    var p = 0.0;
    while (p < len && cartan_byte_at(array_str, p) != 91.0) { // '['
        p = p + 1.0;
    }
    if (p >= len) { return list; }
    p = p + 1.0;

    var in_str = 0.0;
    var brace_depth = 0.0;
    var obj_start = -1.0;

    while (p < len) {
        let b = cartan_byte_at(array_str, p);
        if (b == 34.0) { // '"'
            var backslashes = 0.0;
            var back_p = p - 1.0;
            while (back_p >= 0.0 && cartan_byte_at(array_str, back_p) == 92.0) {
                backslashes = backslashes + 1.0;
                back_p = back_p - 1.0;
            }
            let rem = backslashes - (floor(backslashes / 2.0) * 2.0);
            if (rem == 0.0) {
                if (in_str == 1.0) { in_str = 0.0; }
                else { in_str = 1.0; }
            }
        } else if (in_str == 0.0) {
            if (b == 123.0) { // '{'
                if (brace_depth == 0.0) {
                    obj_start = p;
                }
                brace_depth = brace_depth + 1.0;
            } else if (b == 125.0) { // '}'
                if (brace_depth > 0.0) {
                    brace_depth = brace_depth - 1.0;
                    if (brace_depth == 0.0 && obj_start >= 0.0) {
                        let obj_slice = cartan_string_substring(array_str, obj_start, p + 1.0);
                        cartan_tree_push(list, obj_slice);
                        obj_start = -1.0;
                    }
                }
            } else if (b == 93.0 && brace_depth == 0.0) { // ']'
                break;
            }
        }
        p = p + 1.0;
    }
    return list;
}

// Deallocates string pointers stored in tree list, then frees tree structure
fn json_free_string_array(t: ptr) {
    if (t == 0.0) { return; }
    let count = cartan_tree_len_f(t);
    var i = 0.0;
    while (i < count) {
        let s = cartan_tree_get_f32(t, i);
        if (s != 0.0 && cartan_string_length(s) > 0.0) {
            free(s);
        }
        i = i + 1.0;
    }
    cartan_tree_free(t);
}

// Encodes special characters in a string for safe inclusion in JSON
fn json_escape_string(s: string) -> string {
    if (s == 0.0) { return ""; }
    let len = cartan_string_length(s);
    if (len == 0.0) { return ""; }

    let scaffold = prompt_scaffold_create(len * 2.0 + 16.0);
    var i = 0.0;
    while (i < len) {
        let b = cartan_byte_at(s, i);
        if (b == 34.0) { // '"' -> '\"'
            prompt_scaffold_append(scaffold, "\\\"");
        } else if (b == 92.0) { // '\' -> '\\'
            prompt_scaffold_append(scaffold, "\\\\");
        } else if (b == 10.0) { // newline -> '\n'
            prompt_scaffold_append(scaffold, "\\n");
        } else if (b == 13.0) { // carriage return -> '\r'
            prompt_scaffold_append(scaffold, "\\r");
        } else if (b == 9.0) { // tab -> '\t'
            prompt_scaffold_append(scaffold, "\\t");
        } else {
            prompt_scaffold_append_char(scaffold, b);
        }
        i = i + 1.0;
    }
    let res = prompt_scaffold_get_text(scaffold);
    let out_str = cartan_string_concat(res, "");
    prompt_scaffold_free(scaffold);
    return out_str;
}

// Formats a JSON string field: "key": "escaped_val"
fn json_serialize_field_string(key: string, val: string) -> string {
    var s = "\"";
    s = cartan_string_concat(s, key);
    s = cartan_string_concat(s, "\": \"");
    let esc = json_escape_string(val);
    s = cartan_string_concat(s, esc);
    free(esc);
    s = cartan_string_concat(s, "\"");
    return s;
}

// Formats a JSON float field: "key": val
fn json_serialize_field_float(key: string, val: float) -> string {
    var s = "\"";
    s = cartan_string_concat(s, key);
    s = cartan_string_concat(s, "\": ");
    let f_str = cartan_float_to_string(val);
    s = cartan_string_concat(s, f_str);
    free(f_str);
    return s;
}

// Formats a JSON boolean field: "key": true / "key": false
fn json_serialize_field_bool(key: string, val: float) -> string {
    var s = "\"";
    s = cartan_string_concat(s, key);
    if (val != 0.0) {
        s = cartan_string_concat(s, "\": true");
    } else {
        s = cartan_string_concat(s, "\": false");
    }
    return s;
}
