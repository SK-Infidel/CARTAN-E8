// src/std/sqlite_vec.cl
// CARTAN Standard Library: Embedded SQLite Tier 2 Cognitive Memory Engine
// Pure Native CARTAN Implementation (Zero C Dependency)
// Neuro-Symbolic Expert System (NSES) Two-Tier Memory Substrate

include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/cargraph.cl";

// Raw C-ABI SQLite3 Function Declarations
extern fn sqlite3_open(path: string, ppDb: ptr) -> float;
extern fn sqlite3_close(db: ptr) -> float;
extern fn sqlite3_exec(db: ptr, sql: string, cb: ptr, arg: ptr, errmsg: ptr) -> float;
extern fn sqlite3_prepare_v2(db: ptr, zSql: string, nByte: float, ppStmt: ptr, pzTail: ptr) -> float;
extern fn sqlite3_step(stmt: ptr) -> float;
extern fn sqlite3_finalize(stmt: ptr) -> float;
extern fn sqlite3_reset(stmt: ptr) -> float;
extern fn sqlite3_bind_int64(stmt: ptr, idx: float, val: float) -> float;
extern fn sqlite3_bind_double(stmt: ptr, idx: float, val: float) -> float;
extern fn sqlite3_bind_text(stmt: ptr, idx: float, text: string, len: float, xDel: ptr) -> float;
extern fn sqlite3_column_text(stmt: ptr, col: float) -> string;
extern fn sqlite3_column_double(stmt: ptr, col: float) -> float;
extern fn sqlite3_column_int(stmt: ptr, col: float) -> float;
extern fn sqlite3_errmsg(db: ptr) -> string;

// Native 64-bit Pointer and Memory Intrinsics
extern fn cartan_ptr_at(p: ptr, offset: float) -> ptr;
extern fn cartan_set_ptr(p: ptr, offset: float, val: ptr) -> void;
extern fn malloc(size: float) -> ptr;
extern fn free(p: ptr) -> void;
extern fn strlen(s: string) -> float;
extern fn memcpy(dest: ptr, src: ptr, count: float) -> ptr;

// Open embedded SQLite database file (or ":memory:")
fn sqlite_vec_open(filepath: string) -> ptr {
    if (filepath == 0.0) { return 0.0; }
    let pp_db = malloc(8.0);
    if (pp_db == 0.0) { return 0.0; }
    let rc = sqlite3_open(filepath, pp_db);
    if (rc != 0.0) {
        let db = cartan_ptr_at(pp_db, 0.0);
        if (db != 0.0) { sqlite3_close(db); }
        free(pp_db);
        return 0.0;
    }
    let db = cartan_ptr_at(pp_db, 0.0);
    free(pp_db);
    sqlite3_exec(db, "PRAGMA journal_mode = WAL;", 0.0, 0.0, 0.0);
    sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", 0.0, 0.0, 0.0);
    sqlite3_exec(db, "PRAGMA busy_timeout = 5000;", 0.0, 0.0, 0.0);
    return db;
}

// Close embedded SQLite database
fn sqlite_vec_close(db: ptr) -> float {
    if (db == 0.0) { return 0.0; }
    let rc = sqlite3_close(db);
    if (rc == 0.0) { return 1.0; }
    return 0.0;
}

// Execute arbitrary SQL statement
fn sqlite_vec_exec(db: ptr, sql: string) -> float {
    if (db == 0.0 || sql == 0.0) { return 0.0; }
    let rc = sqlite3_exec(db, sql, 0.0, 0.0, 0.0);
    if (rc == 0.0) { return 1.0; }
    return 0.0;
}

// Prepare a SQL statement handle
fn sqlite_vec_prepare(db: ptr, sql: string) -> ptr {
    if (db == 0.0 || sql == 0.0) { return 0.0; }
    let pp_stmt = malloc(8.0);
    if (pp_stmt == 0.0) { return 0.0; }
    let rc = sqlite3_prepare_v2(db, sql, -1.0, pp_stmt, 0.0);
    if (rc != 0.0) {
        free(pp_stmt);
        return 0.0;
    }
    let stmt = cartan_ptr_at(pp_stmt, 0.0);
    free(pp_stmt);
    return stmt;
}

// Advance prepared statement execution
fn sqlite_vec_step(stmt: ptr) -> float {
    if (stmt == 0.0) { return -1.0; }
    return sqlite3_step(stmt);
}

// Read text column with heap duplication for lifetime safety
fn sqlite_vec_column_text(stmt: ptr, col: float) -> string {
    if (stmt == 0.0) { return ""; }
    let raw_txt = sqlite3_column_text(stmt, col);
    if (raw_txt == 0.0) { return ""; }
    let len = strlen(raw_txt);
    let copy = malloc(len + 1.0);
    if (copy == 0.0) { return ""; }
    memcpy(copy, raw_txt, len + 1.0);
    return copy;
}

// Read 64-bit IEEE float column
fn sqlite_vec_column_double(stmt: ptr, col: float) -> float {
    if (stmt == 0.0) { return 0.0; }
    return sqlite3_column_double(stmt, col);
}

// Finalize prepared statement handle
fn sqlite_vec_finalize(stmt: ptr) -> float {
    if (stmt == 0.0) { return 0.0; }
    return sqlite3_finalize(stmt);
}

// Fetch database error message
fn sqlite_vec_errmsg(db: ptr) -> string {
    if (db == 0.0) { return ""; }
    let msg = sqlite3_errmsg(db);
    if (msg == 0.0) { return ""; }
    return msg;
}

// Initialize the 7-table Cognitive Memory Schema (including Self-Deterministic cognitive_rules)
fn sqlite_vec_init_schema(db: ptr) -> float {
    if (db == 0.0) { return 0.0; }
    let schema = "CREATE TABLE IF NOT EXISTS domains (domain_id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, description TEXT, is_active INTEGER DEFAULT 1, created_at DATETIME DEFAULT CURRENT_TIMESTAMP); CREATE TABLE IF NOT EXISTS rule_elements (element_id INTEGER PRIMARY KEY, domain_id INTEGER, element_type TEXT NOT NULL, content TEXT NOT NULL, is_strict INTEGER DEFAULT 0, confidence REAL DEFAULT 1.0, status TEXT DEFAULT 'active', access_count INTEGER DEFAULT 0, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, last_accessed_at DATETIME DEFAULT CURRENT_TIMESTAMP, decay_half_life_days REAL DEFAULT 30.0); CREATE TABLE IF NOT EXISTS dependencies (dependency_id INTEGER PRIMARY KEY, source_element_id INTEGER, target_element_id INTEGER, relationship_type TEXT NOT NULL, weight REAL DEFAULT 1.0, last_traversed DATETIME DEFAULT CURRENT_TIMESTAMP, UNIQUE(source_element_id, target_element_id, relationship_type)); CREATE TABLE IF NOT EXISTS randomicity_fragments (fragment_id INTEGER PRIMARY KEY, domain_id INTEGER, fragment_text TEXT NOT NULL, entropy_tier INTEGER DEFAULT 1, usage_count INTEGER DEFAULT 0); CREATE TABLE IF NOT EXISTS episodes (episode_id INTEGER PRIMARY KEY, session_id TEXT NOT NULL, domain_id INTEGER, speaker TEXT NOT NULL, content TEXT NOT NULL, consolidated INTEGER DEFAULT 0, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP); CREATE TABLE IF NOT EXISTS entity_states (state_id INTEGER PRIMARY KEY, domain_id INTEGER, entity_name TEXT NOT NULL, attribute_name TEXT NOT NULL, attribute_value TEXT NOT NULL, confidence REAL DEFAULT 1.0, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP, UNIQUE(domain_id, entity_name, attribute_name)); CREATE TABLE IF NOT EXISTS cognitive_rules (rule_id TEXT PRIMARY KEY, enabled INTEGER DEFAULT 1, priority REAL DEFAULT 50.0, trigger_cond TEXT DEFAULT 'always', action_hook TEXT DEFAULT 'none', directive TEXT NOT NULL, source TEXT DEFAULT 'config', updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);";
    let rc = sqlite3_exec(db, schema, 0.0, 0.0, 0.0);
    if (rc == 0.0) { return 1.0; }
    return 0.0;
}

// Upsert a domain record
fn sqlite_vec_upsert_domain(db: ptr, domain_id: float, name: string, desc: string) -> float {
    if (db == 0.0 || name == 0.0) { return 0.0; }
    let sql = "INSERT INTO domains (domain_id, name, description, is_active) VALUES (?, ?, ?, 1) ON CONFLICT(name) DO UPDATE SET description = excluded.description, is_active = 1;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    sqlite3_bind_text(stmt, 2.0, name, -1.0, -1.0);
    var d = desc;
    if (d == 0.0) { d = ""; }
    sqlite3_bind_text(stmt, 3.0, d, -1.0, -1.0);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}

// Upsert an active entity state
fn sqlite_vec_upsert_entity_state(db: ptr, domain_id: float, entity_name: string, attr_name: string, attr_val: string, confidence: float) -> float {
    if (db == 0.0 || entity_name == 0.0 || attr_name == 0.0 || attr_val == 0.0) { return 0.0; }
    let sql = "INSERT INTO entity_states (domain_id, entity_name, attribute_name, attribute_value, confidence, updated_at) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP) ON CONFLICT(domain_id, entity_name, attribute_name) DO UPDATE SET attribute_value = excluded.attribute_value, confidence = excluded.confidence, updated_at = CURRENT_TIMESTAMP;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    sqlite3_bind_text(stmt, 2.0, entity_name, -1.0, -1.0);
    sqlite3_bind_text(stmt, 3.0, attr_name, -1.0, -1.0);
    sqlite3_bind_text(stmt, 4.0, attr_val, -1.0, -1.0);
    sqlite3_bind_double(stmt, 5.0, confidence);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}

// Upsert a semantic or guardrail rule element
fn sqlite_vec_upsert_rule(db: ptr, element_id: float, domain_id: float, elem_type: string, content: string, is_strict: float, conf: float) -> float {
    if (db == 0.0 || elem_type == 0.0 || content == 0.0) { return 0.0; }
    let sql = "INSERT INTO rule_elements (element_id, domain_id, element_type, content, is_strict, confidence, status) VALUES (?, ?, ?, ?, ?, ?, 'active');";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, element_id);
    sqlite3_bind_int64(stmt, 2.0, domain_id);
    sqlite3_bind_text(stmt, 3.0, elem_type, -1.0, -1.0);
    sqlite3_bind_text(stmt, 4.0, content, -1.0, -1.0);
    sqlite3_bind_int64(stmt, 5.0, is_strict);
    sqlite3_bind_double(stmt, 6.0, conf);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}

// Add a dependency causal edge
fn sqlite_vec_add_dependency(db: ptr, src_id: float, tgt_id: float, rel_type: string, weight: float) -> float {
    if (db == 0.0 || rel_type == 0.0) { return 0.0; }
    let sql = "INSERT OR REPLACE INTO dependencies (source_element_id, target_element_id, relationship_type, weight, last_traversed) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP);";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, src_id);
    sqlite3_bind_int64(stmt, 2.0, tgt_id);
    sqlite3_bind_text(stmt, 3.0, rel_type, -1.0, -1.0);
    sqlite3_bind_double(stmt, 4.0, weight);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}

// Add a Burroughs randomicity fragment
fn sqlite_vec_add_randomicity_fragment(db: ptr, domain_id: float, text: string, entropy: float) -> float {
    if (db == 0.0 || text == 0.0) { return 0.0; }
    let sql = "INSERT INTO randomicity_fragments (domain_id, fragment_text, entropy_tier) VALUES (?, ?, ?);";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    sqlite3_bind_text(stmt, 2.0, text, -1.0, -1.0);
    sqlite3_bind_int64(stmt, 3.0, entropy);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}

// Add an episodic conversation turn
fn sqlite_vec_add_episode(db: ptr, session_id: string, domain_id: float, speaker: string, content: string) -> float {
    if (db == 0.0 || session_id == 0.0 || speaker == 0.0 || content == 0.0) { return 0.0; }
    let sql = "INSERT INTO episodes (session_id, domain_id, speaker, content, consolidated) VALUES (?, ?, ?, ?, 0);";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_text(stmt, 1.0, session_id, -1.0, -1.0);
    sqlite3_bind_int64(stmt, 2.0, domain_id);
    sqlite3_bind_text(stmt, 3.0, speaker, -1.0, -1.0);
    sqlite3_bind_text(stmt, 4.0, content, -1.0, -1.0);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}

// Query an active entity state attribute value
fn sqlite_vec_get_entity_state(db: ptr, domain_id: float, entity_name: string, attr_name: string) -> string {
    if (db == 0.0 || entity_name == 0.0 || attr_name == 0.0) { return ""; }
    let sql = "SELECT attribute_value FROM entity_states WHERE domain_id = ? AND entity_name = ? AND attribute_name = ? LIMIT 1;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return ""; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    sqlite3_bind_text(stmt, 2.0, entity_name, -1.0, -1.0);
    sqlite3_bind_text(stmt, 3.0, attr_name, -1.0, -1.0);
    let rc = sqlite3_step(stmt);
    var res = "";
    if (rc == 100.0) {
        res = sqlite_vec_column_text(stmt, 0.0);
    }
    sqlite3_finalize(stmt);
    return res;
}

// Delete an entity state from a domain
fn sqlite_vec_delete_entity_state(db: ptr, domain_id: float, entity_name: string) -> float {
    if (db == 0.0 || entity_name == 0.0) { return 0.0; }
    let sql = "DELETE FROM entity_states WHERE domain_id = ? AND entity_name = ?;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    sqlite3_bind_text(stmt, 2.0, entity_name, -1.0, -1.0);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}


// Query count of active rules in a domain
fn sqlite_vec_get_rule_count(db: ptr, domain_id: float) -> float {
    if (db == 0.0) { return 0.0; }
    let sql = "SELECT COUNT(*) FROM rule_elements WHERE domain_id = ? AND status = 'active';";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    var cnt = 0.0;
    let rc = sqlite3_step(stmt);
    if (rc == 100.0) {
        cnt = sqlite3_column_double(stmt, 0.0);
    }
    sqlite3_finalize(stmt);
    return cnt;
}

// Query count of active entity states in a domain
fn sqlite_vec_get_entity_count(db: ptr, domain_id: float) -> float {
    if (db == 0.0) { return 0.0; }
    let sql = "SELECT COUNT(*) FROM entity_states WHERE domain_id = ?;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    var cnt = 0.0;
    let rc = sqlite3_step(stmt);
    if (rc == 100.0) {
        cnt = sqlite3_column_double(stmt, 0.0);
    }
    sqlite3_finalize(stmt);
    return cnt;
}

// Prepare statement for domain rules retrieval
fn sqlite_vec_prepare_domain_rules(db: ptr, domain_id: float) -> ptr {
    if (db == 0.0) { return 0.0; }
    let sql = "SELECT element_id, domain_id, element_type, is_strict, content FROM rule_elements WHERE domain_id = ? AND status = 'active' ORDER BY is_strict DESC, element_id ASC;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    return stmt;
}

// Prepare statement for domain entities retrieval
fn sqlite_vec_prepare_domain_entities(db: ptr, domain_id: float) -> ptr {
    if (db == 0.0) { return 0.0; }
    let sql = "SELECT domain_id, entity_name, attribute_name, attribute_value, confidence FROM entity_states WHERE domain_id = ? ORDER BY entity_name ASC, attribute_name ASC;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    return stmt;
}

// Query count of unconsolidated episodes in a domain
fn sqlite_vec_get_unconsolidated_count(db: ptr, domain_id: float) -> float {
    if (db == 0.0) { return 0.0; }
    let sql = "SELECT COUNT(*) FROM episodes WHERE domain_id = ? AND consolidated = 0;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    var cnt = 0.0;
    if (sqlite3_step(stmt) == 100.0) {
        cnt = sqlite3_column_double(stmt, 0.0);
    }
    sqlite3_finalize(stmt);
    return cnt;
}

// Consolidate unprocessed episodes into rule_elements and mark consolidated
fn sqlite_vec_consolidate_episodes(db: ptr, domain_id: float) -> float {
    if (db == 0.0) { return 0.0; }
    // 1. Fetch unconsolidated episodes for the domain
    let sql_fetch = "SELECT episode_id, speaker, content FROM episodes WHERE domain_id = ? AND consolidated = 0;";
    let stmt = sqlite_vec_prepare(db, sql_fetch);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);

    var count = 0.0;
    while (sqlite3_step(stmt) == 100.0) {
        let speaker = sqlite_vec_column_text(stmt, 1.0);
        let content = sqlite_vec_column_text(stmt, 2.0);

        // If speaker is user and has content, extract fact rule
        if (speaker != 0.0) {
            if (cartan_string_eq(speaker, "user") != 0.0 || cartan_string_eq(speaker, "User") != 0.0) {
                if (content != 0.0 && strlen(content) > 3.0) {
                    let sql_ins = "INSERT INTO rule_elements (domain_id, element_type, content, is_strict, confidence, status) VALUES (?, 'fact_grounding', ?, 0, 0.95, 'active');";
                    let ins_stmt = sqlite_vec_prepare(db, sql_ins);
                    if (ins_stmt != 0.0) {
                        sqlite3_bind_int64(ins_stmt, 1.0, domain_id);
                        sqlite3_bind_text(ins_stmt, 2.0, content, -1.0, -1.0);
                        sqlite3_step(ins_stmt);
                        sqlite3_finalize(ins_stmt);
                    }
                }
            }
        }
        count = count + 1.0;
    }
    sqlite3_finalize(stmt);

    // 2. Mark episodes as consolidated
    let sql_mark = "UPDATE episodes SET consolidated = 1 WHERE domain_id = ? AND consolidated = 0;";
    let mark_stmt = sqlite_vec_prepare(db, sql_mark);
    if (mark_stmt != 0.0) {
        sqlite3_bind_int64(mark_stmt, 1.0, domain_id);
        sqlite3_step(mark_stmt);
        sqlite3_finalize(mark_stmt);
    }

    return count;
}

// Mark an old belief as superseded and link superseding dependency
fn sqlite_vec_supersede_rule(db: ptr, old_elem_id: float, new_elem_id: float) -> float {
    if (db == 0.0) { return 0.0; }
    // Mark old element as superseded
    let sql_upd = "UPDATE rule_elements SET status = 'superseded', confidence = 0.0 WHERE element_id = ?;";
    let stmt = sqlite_vec_prepare(db, sql_upd);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, old_elem_id);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    // Record superseding dependency if new_elem_id is specified
    if (new_elem_id > 0.0) {
        let sql_dep = "INSERT OR REPLACE INTO dependencies (source_element_id, target_element_id, relationship_type, weight, last_traversed) VALUES (?, ?, 'supersedes', 1.0, CURRENT_TIMESTAMP);";
        let dep_stmt = sqlite_vec_prepare(db, sql_dep);
        if (dep_stmt != 0.0) {
            sqlite3_bind_int64(dep_stmt, 1.0, new_elem_id);
            sqlite3_bind_int64(dep_stmt, 2.0, old_elem_id);
            sqlite3_step(dep_stmt);
            sqlite3_finalize(dep_stmt);
        }
    }
    return 1.0;
}

// Apply Ebbinghaus synaptic decay to non-strict rules and prune low confidence
fn sqlite_vec_apply_ebbinghaus_decay(db: ptr, domain_id: float, min_confidence_thresh: float) -> float {
    if (db == 0.0) { return 0.0; }
    var thresh = min_confidence_thresh;
    if (thresh <= 0.0) { thresh = 0.20; }

    // Apply 10% decay step to non-strict active rules with access_count < 5
    let sql_decay = "UPDATE rule_elements SET confidence = confidence * 0.90 WHERE domain_id = ? AND is_strict = 0 AND status = 'active' AND access_count < 5;";
    let stmt = sqlite_vec_prepare(db, sql_decay);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, domain_id);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    // Prune rules whose confidence dropped below min_confidence_thresh
    let sql_prune = "UPDATE rule_elements SET status = 'pruned' WHERE domain_id = ? AND is_strict = 0 AND status = 'active' AND confidence < ?;";
    let prune_stmt = sqlite_vec_prepare(db, sql_prune);
    if (prune_stmt != 0.0) {
        sqlite3_bind_int64(prune_stmt, 1.0, domain_id);
        sqlite3_bind_double(prune_stmt, 2.0, thresh);
        sqlite3_step(prune_stmt);
        sqlite3_finalize(prune_stmt);
    }
    return 1.0;
}

// Flush Hebbian dynamic CSR weight back to dependencies table
fn sqlite_vec_flush_hebbian_weight(db: ptr, src_id: float, tgt_id: float, weight: float) -> float {
    if (db == 0.0) { return 0.0; }
    let sql = "INSERT INTO dependencies (source_element_id, target_element_id, relationship_type, weight, last_traversed) VALUES (?, ?, 'hebbian_association', ?, CURRENT_TIMESTAMP) ON CONFLICT(source_element_id, target_element_id, relationship_type) DO UPDATE SET weight = excluded.weight, last_traversed = CURRENT_TIMESTAMP;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, src_id);
    sqlite3_bind_int64(stmt, 2.0, tgt_id);
    sqlite3_bind_double(stmt, 3.0, weight);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}

// Phase A Two-Way Sync Bridge: Materialize active domain rules & entity states from Tier 2 DB into Tier 1 .car_graph v2 binary file
fn sqlite_vec_materialize_to_cargraph(db: ptr, domain_id: float, out_path: string) -> float {
    if (db == 0.0) { return 0.0; }

    let b = cargraph_builder_create(1536.0);

    // 1. Fetch domain rules via prepared statement
    let stmt = sqlite_vec_prepare_domain_rules(db, domain_id);
    var rule_cnt = 0.0;
    var strict_cnt = 0.0;

    if (stmt != 0.0) {
        while (sqlite_vec_step(stmt) == 100.0) {
            let is_str = sqlite_vec_column_double(stmt, 3.0);
            let content = sqlite_vec_column_text(stmt, 4.0);
            let e_type_str = sqlite_vec_column_text(stmt, 2.0);
            var e_type = 1.0; // fact_grounding
            if (cartan_string_contains(e_type_str, "guardrail") != 0.0) { e_type = 0.0; }
            if (is_str > 0.0) { strict_cnt = strict_cnt + 1.0; }

            cargraph_builder_add_rule(b, domain_id, e_type, is_str, content, 0.0);
            rule_cnt = rule_cnt + 1.0;
        }
        sqlite_vec_finalize(stmt);
    }

    // Register domain partition
    cargraph_builder_add_domain(b, domain_id, 0.0, rule_cnt, strict_cnt);

    // 2. Fetch active entity states via prepared statement
    let e_stmt = sqlite_vec_prepare_domain_entities(db, domain_id);
    if (e_stmt != 0.0) {
        while (sqlite_vec_step(e_stmt) == 100.0) {
            let ent_name = sqlite_vec_column_text(e_stmt, 1.0);
            let ent_attr = sqlite_vec_column_text(e_stmt, 2.0);
            let ent_val = sqlite_vec_column_text(e_stmt, 3.0);
            let ent_conf = sqlite_vec_column_double(e_stmt, 4.0);
            cargraph_builder_add_entity(b, domain_id, ent_name, ent_attr, ent_val, ent_conf);
        }
        sqlite_vec_finalize(e_stmt);
    }

    // 3. Serialize to .car_graph v2 with strict 64-byte alignment
    let ok = cargraph_serialize_to_file(b, out_path);
    cargraph_builder_free(b);
    return ok;
}

// Find matching entity attribute in prompt dynamically across registered entity states
fn sqlite_vec_find_entity_attribute_in_prompt(db: ptr, prompt: string) -> string {
    if (db == 0.0 || prompt == 0.0) { return ""; }
    let prompt_len = cartan_string_length(prompt);
    if (prompt_len == 0.0) { return ""; }

    let sql = "SELECT entity_name, attribute_name, attribute_value FROM entity_states WHERE domain_id != 0 ORDER BY domain_id ASC, confidence DESC;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return ""; }

    let lower_prompt = cartan_string_to_lower(prompt);
    var matched_val = "";

    while (sqlite3_step(stmt) == 100.0) {
        let ent = sqlite_vec_column_text(stmt, 0.0);
        let attr = sqlite_vec_column_text(stmt, 1.0);
        let val = sqlite_vec_column_text(stmt, 2.0);

        if (cartan_string_length(ent) > 1.0) {
            let lower_ent = cartan_string_to_lower(ent);
            if (cartan_string_contains(lower_prompt, lower_ent) != 0.0) {
                if (cartan_string_length(val) > 0.0) {
                    if (cartan_string_length(attr) > 0.0) {
                        let lower_attr = cartan_string_to_lower(attr);
                        if (cartan_string_contains(lower_prompt, lower_attr) != 0.0) {
                            matched_val = val;
                            free(lower_attr);
                            free(lower_ent);
                            break;
                        }
                        free(lower_attr);
                    }
                    if (cartan_string_length(matched_val) == 0.0) {
                        matched_val = val;
                    }
                }
            }
            free(lower_ent);
        }
    }
    free(lower_prompt);
    sqlite3_finalize(stmt);
    return matched_val;
}

// Prepare statement for retrieving prior session episodes (excluding the currently active prompt turn)
fn sqlite_vec_prepare_prior_episodes(db: ptr, session_id: string, limit: float) -> ptr {
    if (db == 0.0 || session_id == 0.0) { return 0.0; }
    var lim = limit;
    if (lim <= 0.0) { lim = 6.0; }
    let sql = "SELECT speaker, content FROM (SELECT episode_id, speaker, content FROM episodes WHERE session_id = ? AND episode_id < (SELECT MAX(episode_id) FROM episodes WHERE session_id = ?) ORDER BY episode_id DESC LIMIT ?) ORDER BY episode_id ASC;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_text(stmt, 1.0, session_id, -1.0, -1.0);
    sqlite3_bind_text(stmt, 2.0, session_id, -1.0, -1.0);
    sqlite3_bind_int64(stmt, 3.0, lim);
    return stmt;
}

// -------------------------------------------------------------------------
// Domain 10: USERS_AND_RELATIONSHIPS Registration & Seeding
// -------------------------------------------------------------------------
fn sqlite_vec_init_domain10(db: ptr) -> float {
    if (db == 0.0) { return 0.0; }
    sqlite_vec_upsert_domain(db, 10.0, "USERS_AND_RELATIONSHIPS", "Interpersonal identities, user profiles, face maps, and creator relationships");

    // Seed User:Rick (Creator / Root Profile) if not already present
    let r_name = sqlite_vec_get_entity_state(db, 10.0, "User:Rick", "preferred_name");
    if (cartan_string_length(r_name) == 0.0) {
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Rick", "first_name", "Richard", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Rick", "surname", "Weber", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Rick", "preferred_name", "Rick", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Rick", "nicknames", "Rich", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Rick", "role", "Creator & Architect", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Rick", "relationship", "Creator & Lead Architect", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Rick", "permission_tier", "root", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Rick", "face_registered", "0", 1.0);
    }

    // Seed User:Guest (Unverified Profile) if not already present
    let g_name = sqlite_vec_get_entity_state(db, 10.0, "User:Guest", "preferred_name");
    if (cartan_string_length(g_name) == 0.0) {
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Guest", "first_name", "Guest", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Guest", "surname", "", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Guest", "preferred_name", "Guest", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Guest", "nicknames", "", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Guest", "role", "Visitor", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Guest", "relationship", "Unverified Interlocutor", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Guest", "permission_tier", "guest", 1.0);
        sqlite_vec_upsert_entity_state(db, 10.0, "User:Guest", "face_registered", "0", 1.0);
    }
    return 1.0;
}

// Fetch user profile attribute from Domain 10
fn sqlite_vec_get_user_attr(db: ptr, user_id: string, attr: string) -> string {
    if (db == 0.0 || user_id == 0.0 || attr == 0.0) { return ""; }
    return sqlite_vec_get_entity_state(db, 10.0, user_id, attr);
}

// Set user profile attribute in Domain 10
fn sqlite_vec_set_user_attr(db: ptr, user_id: string, attr: string, val: string) -> float {
    if (db == 0.0 || user_id == 0.0 || attr == 0.0 || val == 0.0) { return 0.0; }
    return sqlite_vec_upsert_entity_state(db, 10.0, user_id, attr, val, 1.0);
}

// Store serialized 320-D eikonal face embedding string in Domain 10
fn sqlite_vec_save_user_face_embedding(db: ptr, user_id: string, emb_str: string) -> float {
    if (db == 0.0 || user_id == 0.0 || emb_str == 0.0) { return 0.0; }
    let s1 = sqlite_vec_upsert_entity_state(db, 10.0, user_id, "face_embedding", emb_str, 1.0);
    let s2 = sqlite_vec_upsert_entity_state(db, 10.0, user_id, "face_registered", "1", 1.0);
    if (s1 == 1.0 && s2 == 1.0) { return 1.0; }
    return 0.0;
}

// Retrieve serialized face embedding string from Domain 10
fn sqlite_vec_get_user_face_embedding(db: ptr, user_id: string) -> string {
    if (db == 0.0 || user_id == 0.0) { return ""; }
    return sqlite_vec_get_entity_state(db, 10.0, user_id, "face_embedding");
}

// Prepare statement to enumerate all users with active registered face maps in Domain 10
fn sqlite_vec_prepare_registered_face_users(db: ptr) -> ptr {
    if (db == 0.0) { return 0.0; }
    let sql = "SELECT entity_name FROM entity_states WHERE domain_id = 10.0 AND attribute_name = 'face_registered' AND attribute_value = '1';";
    return sqlite_vec_prepare(db, sql);
}

// Prepare statement to enumerate all custom/semantic user profile attributes (excluding technical metadata)
fn sqlite_vec_prepare_user_custom_attrs(db: ptr, user_id: string) -> ptr {
    if (db == 0.0 || user_id == 0.0) { return 0.0; }
    var sql = "SELECT attribute_name, attribute_value FROM entity_states WHERE domain_id = 10.0 AND entity_name = '";
    sql = cartan_string_concat(sql, user_id);
    sql = cartan_string_concat(sql, "' AND attribute_name NOT IN ('face_embedding', 'face_registered', 'permission_tier') ORDER BY attribute_name ASC;");
    let stmt = sqlite_vec_prepare(db, sql);
    return stmt;
}

// -------------------------------------------------------------------------
// Self-Deterministic & Hybrid Config Cognitive Rules Engine (cognitive_rules)
// -------------------------------------------------------------------------
fn sqlite_vec_upsert_cognitive_rule(db: ptr, rule_id: string, enabled: float, priority: float, trigger_cond: string, action_hook: string, directive: string, source: string) -> float {
    if (db == 0.0 || rule_id == 0.0 || cartan_string_length(rule_id) == 0.0) { return 0.0; }
    let sql = "INSERT INTO cognitive_rules (rule_id, enabled, priority, trigger_cond, action_hook, directive, source, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP) ON CONFLICT(rule_id) DO UPDATE SET enabled = excluded.enabled, priority = excluded.priority, trigger_cond = excluded.trigger_cond, action_hook = excluded.action_hook, directive = excluded.directive, source = excluded.source, updated_at = CURRENT_TIMESTAMP;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    var trig = trigger_cond;
    if (trig == 0.0 || cartan_string_length(trig) == 0.0) { trig = "always"; }
    var act = action_hook;
    if (act == 0.0 || cartan_string_length(act) == 0.0) { act = "none"; }
    var dir = directive;
    if (dir == 0.0) { dir = ""; }
    var src = source;
    if (src == 0.0 || cartan_string_length(src) == 0.0) { src = "config"; }
    sqlite3_bind_text(stmt, 1.0, rule_id, -1.0, -1.0);
    sqlite3_bind_int64(stmt, 2.0, enabled);
    sqlite3_bind_double(stmt, 3.0, priority);
    sqlite3_bind_text(stmt, 4.0, trig, -1.0, -1.0);
    sqlite3_bind_text(stmt, 5.0, act, -1.0, -1.0);
    sqlite3_bind_text(stmt, 6.0, dir, -1.0, -1.0);
    sqlite3_bind_text(stmt, 7.0, src, -1.0, -1.0);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}

fn sqlite_vec_get_cognitive_rule_source(db: ptr, rule_id: string) -> string {
    if (db == 0.0 || rule_id == 0.0) { return ""; }
    let sql = "SELECT source FROM cognitive_rules WHERE rule_id = ? LIMIT 1;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return ""; }
    sqlite3_bind_text(stmt, 1.0, rule_id, -1.0, -1.0);
    var res = "";
    if (sqlite3_step(stmt) == 100.0) {
        res = sqlite_vec_column_text(stmt, 0.0);
    }
    sqlite3_finalize(stmt);
    return res;
}

fn sqlite_vec_set_cognitive_rule_enabled(db: ptr, rule_id: string, enabled: float) -> float {
    if (db == 0.0 || rule_id == 0.0) { return 0.0; }
    let sql = "UPDATE cognitive_rules SET enabled = ?, updated_at = CURRENT_TIMESTAMP WHERE rule_id = ?;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_int64(stmt, 1.0, enabled);
    sqlite3_bind_text(stmt, 2.0, rule_id, -1.0, -1.0);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}

fn sqlite_vec_delete_cognitive_rule(db: ptr, rule_id: string) -> float {
    if (db == 0.0 || rule_id == 0.0) { return 0.0; }
    let sql = "DELETE FROM cognitive_rules WHERE rule_id = ?;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    sqlite3_bind_text(stmt, 1.0, rule_id, -1.0, -1.0);
    let rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc == 101.0) { return 1.0; }
    return 0.0;
}

fn sqlite_vec_prepare_cognitive_rules(db: ptr, only_enabled: float) -> ptr {
    if (db == 0.0) { return 0.0; }
    var sql = "SELECT rule_id, enabled, priority, trigger_cond, action_hook, directive, source FROM cognitive_rules ORDER BY priority DESC, rule_id ASC;";
    if (only_enabled == 1.0) {
        sql = "SELECT rule_id, enabled, priority, trigger_cond, action_hook, directive, source FROM cognitive_rules WHERE enabled = 1 ORDER BY priority DESC, rule_id ASC;";
    }
    return sqlite_vec_prepare(db, sql);
}

fn sqlite_vec_get_cognitive_rule_count(db: ptr) -> float {
    if (db == 0.0) { return 0.0; }
    let sql = "SELECT COUNT(*) FROM cognitive_rules WHERE enabled = 1;";
    let stmt = sqlite_vec_prepare(db, sql);
    if (stmt == 0.0) { return 0.0; }
    var cnt = 0.0;
    if (sqlite3_step(stmt) == 100.0) {
        cnt = sqlite3_column_double(stmt, 0.0);
    }
    sqlite3_finalize(stmt);
    return cnt;
}

// -------------------------------------------------------------------------
// Backward-Compatible Aliases for Legacy cartan_sqlite_* Callers
// -------------------------------------------------------------------------
fn cartan_sqlite_open(path: string) -> ptr { return sqlite_vec_open(path); }
fn cartan_sqlite_close(db: ptr) -> float { return sqlite_vec_close(db); }
fn cartan_sqlite_exec(db: ptr, sql: string) -> float { return sqlite_vec_exec(db, sql); }
fn cartan_sqlite_prepare(db: ptr, sql: string) -> ptr { return sqlite_vec_prepare(db, sql); }
fn cartan_sqlite_step(stmt: ptr) -> float { return sqlite_vec_step(stmt); }
fn cartan_sqlite_column_text(stmt: ptr, col: float) -> string { return sqlite_vec_column_text(stmt, col); }
fn cartan_sqlite_column_double(stmt: ptr, col: float) -> float { return sqlite_vec_column_double(stmt, col); }
fn cartan_sqlite_finalize(stmt: ptr) -> float { return sqlite_vec_finalize(stmt); }
fn cartan_sqlite_errmsg(db: ptr) -> string { return sqlite_vec_errmsg(db); }
fn cartan_sqlite_init_schema(db: ptr) -> float { return sqlite_vec_init_schema(db); }
fn cartan_sqlite_upsert_domain(db: ptr, domain_id: float, name: string, desc: string) -> float { return sqlite_vec_upsert_domain(db, domain_id, name, desc); }
fn cartan_sqlite_upsert_entity_state(db: ptr, domain_id: float, entity: string, attr: string, val: string, conf: float) -> float { return sqlite_vec_upsert_entity_state(db, domain_id, entity, attr, val, conf); }
fn cartan_sqlite_upsert_rule(db: ptr, elem_id: float, domain_id: float, elem_type: string, content: string, is_strict: float, conf: float) -> float { return sqlite_vec_upsert_rule(db, elem_id, domain_id, elem_type, content, is_strict, conf); }
fn cartan_sqlite_add_dependency(db: ptr, src_id: float, tgt_id: float, rel_type: string, weight: float) -> float { return sqlite_vec_add_dependency(db, src_id, tgt_id, rel_type, weight); }
fn cartan_sqlite_add_randomicity_fragment(db: ptr, domain_id: float, text: string, entropy: float) -> float { return sqlite_vec_add_randomicity_fragment(db, domain_id, text, entropy); }
fn cartan_sqlite_add_episode(db: ptr, session_id: string, domain_id: float, speaker: string, content: string) -> float { return sqlite_vec_add_episode(db, session_id, domain_id, speaker, content); }
fn cartan_sqlite_get_entity_state(db: ptr, domain_id: float, entity: string, attr: string) -> string { return sqlite_vec_get_entity_state(db, domain_id, entity, attr); }
fn cartan_sqlite_delete_entity_state(db: ptr, domain_id: float, entity: string) -> float { return sqlite_vec_delete_entity_state(db, domain_id, entity); }
fn cartan_sqlite_get_rule_count(db: ptr, domain_id: float) -> float { return sqlite_vec_get_rule_count(db, domain_id); }

fn cartan_sqlite_get_entity_count(db: ptr, domain_id: float) -> float { return sqlite_vec_get_entity_count(db, domain_id); }
fn cartan_sqlite_prepare_domain_rules(db: ptr, domain_id: float) -> ptr { return sqlite_vec_prepare_domain_rules(db, domain_id); }
fn cartan_sqlite_prepare_domain_entities(db: ptr, domain_id: float) -> ptr { return sqlite_vec_prepare_domain_entities(db, domain_id); }
fn cartan_sqlite_get_unconsolidated_count(db: ptr, domain_id: float) -> float { return sqlite_vec_get_unconsolidated_count(db, domain_id); }
fn cartan_sqlite_consolidate_unprocessed_episodes(db: ptr, domain_id: float) -> float { return sqlite_vec_consolidate_episodes(db, domain_id); }
fn cartan_sqlite_supersede_rule(db: ptr, old_elem_id: float, new_elem_id: float) -> float { return sqlite_vec_supersede_rule(db, old_elem_id, new_elem_id); }
fn cartan_sqlite_apply_ebbinghaus_decay(db: ptr, domain_id: float, min_confidence_thresh: float) -> float { return sqlite_vec_apply_ebbinghaus_decay(db, domain_id, min_confidence_thresh); }
fn cartan_sqlite_flush_hebbian_weight(db: ptr, src_id: float, tgt_id: float, weight: float) -> float { return sqlite_vec_flush_hebbian_weight(db, src_id, tgt_id, weight); }
fn cartan_sqlite_find_entity_attribute_in_prompt(db: ptr, prompt: string) -> string { return sqlite_vec_find_entity_attribute_in_prompt(db, prompt); }
fn cartan_sqlite_prepare_prior_episodes(db: ptr, session_id: string, limit: float) -> ptr { return sqlite_vec_prepare_prior_episodes(db, session_id, limit); }
fn cartan_sqlite_init_domain10(db: ptr) -> float { return sqlite_vec_init_domain10(db); }
fn cartan_sqlite_get_user_attr(db: ptr, user_id: string, attr: string) -> string { return sqlite_vec_get_user_attr(db, user_id, attr); }
fn cartan_sqlite_set_user_attr(db: ptr, user_id: string, attr: string, val: string) -> float { return sqlite_vec_set_user_attr(db, user_id, attr, val); }
fn cartan_sqlite_save_user_face_embedding(db: ptr, user_id: string, emb_str: string) -> float { return sqlite_vec_save_user_face_embedding(db, user_id, emb_str); }
fn cartan_sqlite_get_user_face_embedding(db: ptr, user_id: string) -> string { return sqlite_vec_get_user_face_embedding(db, user_id); }
fn cartan_sqlite_prepare_registered_face_users(db: ptr) -> ptr { return sqlite_vec_prepare_registered_face_users(db); }
fn cartan_sqlite_prepare_user_custom_attrs(db: ptr, user_id: string) -> ptr { return sqlite_vec_prepare_user_custom_attrs(db, user_id); }
fn cartan_sqlite_upsert_cognitive_rule(db: ptr, rule_id: string, enabled: float, priority: float, trigger_cond: string, action_hook: string, directive: string, source: string) -> float { return sqlite_vec_upsert_cognitive_rule(db, rule_id, enabled, priority, trigger_cond, action_hook, directive, source); }
fn cartan_sqlite_get_cognitive_rule_source(db: ptr, rule_id: string) -> string { return sqlite_vec_get_cognitive_rule_source(db, rule_id); }
fn cartan_sqlite_set_cognitive_rule_enabled(db: ptr, rule_id: string, enabled: float) -> float { return sqlite_vec_set_cognitive_rule_enabled(db, rule_id, enabled); }
fn cartan_sqlite_delete_cognitive_rule(db: ptr, rule_id: string) -> float { return sqlite_vec_delete_cognitive_rule(db, rule_id); }
fn cartan_sqlite_prepare_cognitive_rules(db: ptr, only_enabled: float) -> ptr { return sqlite_vec_prepare_cognitive_rules(db, only_enabled); }
fn cartan_sqlite_get_cognitive_rule_count(db: ptr) -> float { return sqlite_vec_get_cognitive_rule_count(db); }

