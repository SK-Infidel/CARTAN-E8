// src/std/veto_gate.cl
// CARTAN Standard Library: Absolute Post-Pass Deterministic Veto Gate (Model Disobedience Firewall)
// Neuro-Symbolic Expert System (NSES) Phase 5 Core

include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";

extern fn calloc(count: float, size: float) -> ptr;
extern fn free(p: ptr);
extern fn strlen(s: string) -> float;
extern fn cartan_string_get_char(s: string, idx: float) -> float;
extern fn cartan_set_byte(buf: ptr, offset: float, val: float);
extern fn cartan_set_f32(p: ptr, offset: float, val: float) -> void;
extern fn cartan_f32_at(p: ptr, offset: float) -> float;
extern fn cartan_tree_create() -> ptr;
extern fn cartan_tree_push(t: ptr, item: ptr) -> void;
extern fn cartan_tree_get_f32(t: ptr, idx: float) -> ptr;
extern fn cartan_tree_len_f(t: ptr) -> float;

// Veto Evaluation Result Structure
struct VetoResult {
    is_vetoed: float;             // 1.0 = vetoed (suppressed & replaced), 0.0 = passed clean
    output_text: string;          // Original text if clean; canonical invariant assertion if vetoed
    violated_rule_id: float;      // Index of violated invariant rule (-1.0 if clean)
    violation_pattern: string;    // Contradictory pattern detected
}

// In-Memory Veto Rule Registry Structure
struct VetoRegistry {
    count: float;
    rule_ids: ptr;                // collections list (float)
    domain_ids: ptr;              // collections list (float)
    canonical_assertions: ptr;   // cartan_tree of strings
    pattern_trees: ptr;           // cartan_tree of cartan_trees (list of forbidden patterns per rule)
    domain_forbidden_tokens: ptr; // cartan_tree of collections lists of float token IDs
}

// Converts an ASCII string to lowercase for robust pattern matching
fn veto_string_to_lower(s: string) -> string {
    if (s == 0.0) {
        let res = calloc(1.0, 1.0);
        return res;
    }
    let len = strlen(s);
    if (len == 0.0) {
        let res = calloc(1.0, 1.0);
        return res;
    }
    let res = calloc(len + 1.0, 1.0);
    var i = 0.0;
    while (i < len) {
        var c = cartan_string_get_char(s, i);
        if (c >= 65.0 && c <= 90.0) { // 'A' .. 'Z'
            c = c + 32.0;
        }
        cartan_set_byte(res, i, c);
        i = i + 1.0;
    }
    return res;
}

// Allocates an empty VetoRegistry
fn veto_registry_create() -> VetoRegistry {
    let r_ids = collections_create_list();
    let d_ids = collections_create_list();
    let c_tree = cartan_tree_create();
    let p_tree = cartan_tree_create();
    let d_toks = cartan_tree_create();
    var d = 0.0;
    while (d < 32.0) {
        let t_list = collections_create_list();
        cartan_tree_push(d_toks, t_list);
        d = d + 1.0;
    }
    return VetoRegistry {
        count: 0.0,
        rule_ids: r_ids,
        domain_ids: d_ids,
        canonical_assertions: c_tree,
        pattern_trees: p_tree,
        domain_forbidden_tokens: d_toks
    };
}

// Adds an invariant rule and its contradictory pattern trigger list
fn veto_registry_add_rule(reg: VetoRegistry, rule_id: float, domain_id: float, assertion: string, forbidden_tree: ptr) -> float {
    collections_list_push(reg.rule_ids, rule_id);
    collections_list_push(reg.domain_ids, domain_id);
    cartan_tree_push(reg.canonical_assertions, assertion);
    cartan_tree_push(reg.pattern_trees, forbidden_tree);
    reg.count = reg.count + 1.0;
    return reg.count;
}

// Registers a forbidden token ID associated with contradictions in a domain
fn veto_registry_add_forbidden_token(reg: VetoRegistry, domain_id: float, token_id: float) -> float {
    if (reg.domain_forbidden_tokens == 0.0 || domain_id < 0.0 || domain_id >= 32.0) { return 0.0; }
    let t_list = cartan_tree_get_f32(reg.domain_forbidden_tokens, domain_id);
    if (t_list != 0.0) {
        collections_list_push(t_list, token_id);
        return collections_list_len(t_list);
    }
    return 0.0;
}

// Retrieves forbidden token list for a domain
fn veto_registry_get_forbidden_tokens(reg: VetoRegistry, domain_id: float) -> ptr {
    if (reg.domain_forbidden_tokens == 0.0 || domain_id < 0.0 || domain_id >= 32.0) { return 0.0; }
    return cartan_tree_get_f32(reg.domain_forbidden_tokens, domain_id);
}

// Deallocates VetoRegistry resources
fn veto_registry_free(reg: VetoRegistry) {
    if (reg.rule_ids != 0.0) { collections_free_list(reg.rule_ids); }
    if (reg.domain_ids != 0.0) { collections_free_list(reg.domain_ids); }
    if (reg.domain_forbidden_tokens != 0.0) {
        var d = 0.0;
        let num_d = cartan_tree_len_f(reg.domain_forbidden_tokens);
        while (d < num_d) {
            let t_list = cartan_tree_get_f32(reg.domain_forbidden_tokens, d);
            if (t_list != 0.0) { collections_free_list(t_list); }
            d = d + 1.0;
        }
    }
}

// Scans candidate generated response text against active invariants
fn veto_gate_scan(reg: VetoRegistry, candidate_text: string) -> VetoResult {
    if (candidate_text == 0.0 || strlen(candidate_text) == 0.0 || reg.count <= 0.0) {
        return VetoResult {
            is_vetoed: 0.0,
            output_text: candidate_text,
            violated_rule_id: -1.0,
            violation_pattern: ""
        };
    }

    let lower_text = veto_string_to_lower(candidate_text);

    var r_idx = 0.0;
    while (r_idx < reg.count) {
        let patterns = cartan_tree_get_f32(reg.pattern_trees, r_idx);
        if (patterns != 0.0) {
            let pat_count = cartan_tree_len_f(patterns);
            var p_idx = 0.0;
            while (p_idx < pat_count) {
                let raw_pat = cartan_tree_get_f32(patterns, p_idx);
                let pat = veto_string_to_lower(raw_pat);
                if (cartan_string_contains(lower_text, pat) != 0.0) {
                    // Contradiction detected ($P \land \neg P$): Trigger instant veto
                    let r_id = collections_list_get(reg.rule_ids, r_idx);
                    let canon_assert = cartan_tree_get_f32(reg.canonical_assertions, r_idx);
                    free(lower_text);
                    free(pat);
                    return VetoResult {
                        is_vetoed: 1.0,
                        output_text: canon_assert,
                        violated_rule_id: r_id,
                        violation_pattern: raw_pat
                    };
                }
                free(pat);
                p_idx = p_idx + 1.0;
            }
        }
        r_idx = r_idx + 1.0;
    }

    free(lower_text);
    return VetoResult {
        is_vetoed: 0.0,
        output_text: candidate_text,
        violated_rule_id: -1.0,
        violation_pattern: ""
    };
}

// Populates default canonical physical invariants and contradiction triggers for Domain 0 (SYSTEM_CORE)
fn veto_registry_populate_defaults(reg: VetoRegistry) {
    // 1. Conservation of Energy & First Law of Thermodynamics
    let p1 = cartan_tree_create();
    cartan_tree_push(p1, "energy can be created");
    cartan_tree_push(p1, "energy can be destroyed");
    cartan_tree_push(p1, "energy increases exponentially");
    cartan_tree_push(p1, "energy is not conserved");
    cartan_tree_push(p1, "energy is unbounded");
    cartan_tree_push(p1, "conservation of energy is violated");
    cartan_tree_push(p1, "perpetual motion generates free energy");
    cartan_tree_push(p1, "energy appears from nothing");
    cartan_tree_push(p1, "energy vanishes into nothing");
    veto_registry_add_rule(
        reg,
        1.0,
        0.0,
        "In accordance with the first law of thermodynamics, energy cannot be created or destroyed; kinetic energy in an inelastic impact is dissipated as thermal energy and deformation.",
        p1
    );

    // 2. Second Law of Thermodynamics & Entropy Non-Decrease
    let p2 = cartan_tree_create();
    cartan_tree_push(p2, "entropy decreases in an isolated system");
    cartan_tree_push(p2, "heat flows spontaneously from cold to hot");
    cartan_tree_push(p2, "reversed thermodynamic arrow of time");
    cartan_tree_push(p2, "entropy can be arbitrarily destroyed");
    veto_registry_add_rule(
        reg,
        2.0,
        0.0,
        "In accordance with the second law of thermodynamics, total entropy in an isolated thermodynamic system can never spontaneously decrease over time.",
        p2
    );

    // 3. Special Relativity & Vacuum Speed of Light Limit
    let p3 = cartan_tree_create();
    cartan_tree_push(p3, "faster than light travel with mass");
    cartan_tree_push(p3, "mass accelerates beyond c");
    cartan_tree_push(p3, "superluminal physical propagation");
    cartan_tree_push(p3, "speed exceeds light speed");
    veto_registry_add_rule(
        reg,
        3.0,
        0.0,
        "In accordance with special relativity, no physical mass or causal signal can propagate through spacetime faster than the vacuum speed of light c.",
        p3
    );

    // 4. Fundamental Law of Non-Contradiction
    let p4 = cartan_tree_create();
    cartan_tree_push(p4, "two plus two equals five");
    cartan_tree_push(p4, "contradictions are simultaneously true");
    cartan_tree_push(p4, "one equals zero");
    cartan_tree_push(p4, "axioms are discarded");
    veto_registry_add_rule(
        reg,
        4.0,
        0.0,
        "In accordance with the foundational axioms of mathematical logic, contradictory propositions (P and not P) cannot be simultaneously asserted.",
        p4
    );

    // 5. Momentum Conservation (Domain 1: PHYSICS_SIM)
    let p5 = cartan_tree_create();
    cartan_tree_push(p5, "momentum is not conserved");
    cartan_tree_push(p5, "momentum appears from nowhere");
    cartan_tree_push(p5, "net force is zero but momentum changes");
    veto_registry_add_rule(
        reg,
        5.0,
        1.0,
        "In accordance with classical mechanics, total linear momentum is strictly conserved in all closed physical collision systems.",
        p5
    );

    // 6. Central Dogma & Free Energy (Domain 4: BIOLOGICAL_SYSTEMS)
    let p6 = cartan_tree_create();
    cartan_tree_push(p6, "protein synthesizes dna directly");
    cartan_tree_push(p6, "cells do not require energy");
    cartan_tree_push(p6, "spontaneous generation without ancestors");
    veto_registry_add_rule(
        reg,
        6.0,
        4.0,
        "In accordance with biological invariants, living metabolic cells require continuous free energy input, and genetic information flows directionally from DNA to RNA to protein.",
        p6
    );

    // 7. Causal Precedence & Taxonomic Exclusion (Domain 5: CAUSAL_TAXONOMY)
    let p7 = cartan_tree_create();
    cartan_tree_push(p7, "effects precede their causes");
    cartan_tree_push(p7, "an organism is both plant and animal");
    cartan_tree_push(p7, "reverse temporal causality");
    veto_registry_add_rule(
        reg,
        7.0,
        5.0,
        "In accordance with causal and taxonomic invariants, causes strictly precede their effects in time, and organisms cannot hold mutually exclusive kingdom classifications.",
        p7
    );

    // 8. Linguistic Invariants & Communicative Pragmatics (Domain 6: LANGUAGE_DISCOURSE)
    let p8 = cartan_tree_create();
    cartan_tree_push(p8, "words have no meaning");
    cartan_tree_push(p8, "language cannot communicate");
    cartan_tree_push(p8, "questions do not require answers");
    cartan_tree_push(p8, "statements contradict their premises");
    cartan_tree_push(p8, "grammar has no rules");
    cartan_tree_push(p8, "pronouns have no antecedents");
    veto_registry_add_rule(
        reg,
        8.0,
        6.0,
        "In accordance with communicative pragmatics, language conveys structured meaning through shared vocabulary, grammatical syntax, and coherent speech acts.",
        p8
    );

    // Register Default Contradiction Tokens across Cognitive Domains
    // Domain 0: SYSTEM_CORE (Energy destruction, perpetual motion, causality violations)
    veto_registry_add_forbidden_token(reg, 0.0, 101.0);
    veto_registry_add_forbidden_token(reg, 0.0, 102.0);
    veto_registry_add_forbidden_token(reg, 0.0, 103.0);

    // Domain 1: PHYSICS_SIM (Momentum destruction, spontaneous velocity)
    veto_registry_add_forbidden_token(reg, 1.0, 105.0);
    veto_registry_add_forbidden_token(reg, 1.0, 106.0);
    veto_registry_add_forbidden_token(reg, 1.0, 107.0);
    veto_registry_add_forbidden_token(reg, 1.0, 108.0);

    // Domain 4: BIOLOGICAL_SYSTEMS (Spontaneous generation, reverse central dogma)
    veto_registry_add_forbidden_token(reg, 4.0, 401.0);
    veto_registry_add_forbidden_token(reg, 4.0, 402.0);
    veto_registry_add_forbidden_token(reg, 4.0, 403.0);
    veto_registry_add_forbidden_token(reg, 4.0, 404.0);

    // Domain 5: CAUSAL_TAXONOMY (Reverse time causality, taxonomic mutual exclusion violation)
    veto_registry_add_forbidden_token(reg, 5.0, 501.0);
    veto_registry_add_forbidden_token(reg, 5.0, 502.0);
    veto_registry_add_forbidden_token(reg, 5.0, 503.0);
    veto_registry_add_forbidden_token(reg, 5.0, 504.0);

    // Domain 6: LANGUAGE_DISCOURSE (Nonsense, meaninglessness, grammar denial, category errors)
    veto_registry_add_forbidden_token(reg, 6.0, 601.0);
    veto_registry_add_forbidden_token(reg, 6.0, 602.0);
    veto_registry_add_forbidden_token(reg, 6.0, 603.0);
    veto_registry_add_forbidden_token(reg, 6.0, 604.0);
    veto_registry_add_forbidden_token(reg, 6.0, 605.0); // Category mismatch
    veto_registry_add_forbidden_token(reg, 6.0, 606.0); // Ungrounded predicate
    veto_registry_add_forbidden_token(reg, 6.0, 607.0); // Discourse frame rupture
    veto_registry_add_forbidden_token(reg, 6.0, 608.0); // Ontological type violation

    // 9. Formal Logic Invariants & Deductive Validity (Domain 7: LOGIC_REASONING)
    let p9 = cartan_tree_create();
    cartan_tree_push(p9, "affirming the consequent is valid");
    cartan_tree_push(p9, "denying the antecedent is valid");
    cartan_tree_push(p9, "circular reasoning proves the premise");
    cartan_tree_push(p9, "contradictory premises are true");
    cartan_tree_push(p9, "false implies true is invalid");
    cartan_tree_push(p9, "modus ponens is false");
    veto_registry_add_rule(
        reg,
        9.0,
        7.0,
        "In accordance with classical deductive logic, valid inferences must preserve truth, contradictions cannot both be true, and affirming the consequent or denying the antecedent are invalid formal fallacies.",
        p9
    );

    // Domain 7: LOGIC_REASONING (Formal fallacies, contradiction assertions)
    veto_registry_add_forbidden_token(reg, 7.0, 701.0);
    veto_registry_add_forbidden_token(reg, 7.0, 702.0);
    veto_registry_add_forbidden_token(reg, 7.0, 703.0);
    veto_registry_add_forbidden_token(reg, 7.0, 704.0);

    // 10. Decision Theory, Game Theoretic Dominance & Bellman Invariants (Domain 8: DECISION_PLANNING)
    let p10 = cartan_tree_create();
    cartan_tree_push(p10, "selecting strictly dominated action");
    cartan_tree_push(p10, "intransitive preference cycle");
    cartan_tree_push(p10, "negative discount factor in bellman");
    cartan_tree_push(p10, "inadmissible heuristic overestimates cost");
    cartan_tree_push(p10, "unilateral deviation increases payoff in nash");
    cartan_tree_push(p10, "sunk cost commitments");
    cartan_tree_push(p10, "sunk cost fallacy");
    veto_registry_add_rule(
        reg,
        10.0,
        8.0,
        "In accordance with sequential decision theory and game-theoretic rationality, agents must satisfy Bellman optimality, avoid strictly dominated actions, maintain transitive preferences, and preserve admissible heuristic search bounds.",
        p10
    );

    // Domain 8: DECISION_PLANNING (Dominated action, preference cycles, divergence)
    veto_registry_add_forbidden_token(reg, 8.0, 801.0);
    veto_registry_add_forbidden_token(reg, 8.0, 802.0);
    veto_registry_add_forbidden_token(reg, 8.0, 803.0);
    veto_registry_add_forbidden_token(reg, 8.0, 804.0);

    // 11. Ontological Category Error & Incompatible Predicate Attribution (Domain 6: LANGUAGE_DISCOURSE)
    let p11 = cartan_tree_create();
    cartan_tree_push(p11, "photosynthesizing manifold");
    cartan_tree_push(p11, "exterior derivative digests glucose");
    cartan_tree_push(p11, "turing machine undergoes cellular respiration");
    cartan_tree_push(p11, "logical proposition has physical velocity");
    cartan_tree_push(p11, "bellman equation accelerates faster than light");
    cartan_tree_push(p11, "nash equilibrium has physical mass");
    cartan_tree_push(p11, "differential form metabolizes");
    veto_registry_add_rule(
        reg,
        11.0,
        6.0,
        "In accordance with formal ontological category theory, predicates and causal operations must preserve type-theoretic validity and cannot be attributed across disjoint ontological domains.",
        p11
    );

    // 12. Epistemic Fallacy, Dogmatic Priors & Non-Updatable Beliefs (Domain 9: EPISTEMOLOGY_BELIEF)
    let p12 = cartan_tree_create();
    cartan_tree_push(p12, "dogmatic prior immune to evidence");
    cartan_tree_push(p12, "zero likelihood updates prior to one");
    cartan_tree_push(p12, "evidence contradicts prior so discard evidence");
    cartan_tree_push(p12, "base rate is zero so posterior is certain");
    cartan_tree_push(p12, "contradictory evidence retains prior without revision");
    cartan_tree_push(p12, "posterior does not depend on likelihood");
    cartan_tree_push(p12, "probability exceeds one");
    cartan_tree_push(p12, "negative probability");
    veto_registry_add_rule(
        reg,
        12.0,
        9.0,
        "In accordance with Bayesian epistemology and AGM belief revision, credences must obey finite probability axioms, update rationally via likelihood ratios upon empirical evidence, and minimally contract prior commitments to preserve consistency.",
        p12
    );

    // Domain 9: EPISTEMOLOGY_BELIEF (Dogmatic priors, confirmation bias, base rate neglect, AGM collapse)
    veto_registry_add_forbidden_token(reg, 9.0, 901.0);
    veto_registry_add_forbidden_token(reg, 9.0, 902.0);
    veto_registry_add_forbidden_token(reg, 9.0, 903.0);
    veto_registry_add_forbidden_token(reg, 9.0, 904.0);

    // 13. Compiler Undefined Behavior, Type Confusion & Memory Exclusivity (Domain 10: COMPILER_SYSTEMS)
    let p13 = cartan_tree_create();
    cartan_tree_push(p13, "type confusion dereference");
    cartan_tree_push(p13, "use after free with dangling pointer");
    cartan_tree_push(p13, "simultaneous mutable aliasing");
    cartan_tree_push(p13, "access undefined stuck state");
    cartan_tree_push(p13, "evaluating stuck ill-typed term");
    cartan_tree_push(p13, "data race on shared mutable pointer");
    cartan_tree_push(p13, "multiple exclusive writers");
    veto_registry_add_rule(
        reg,
        13.0,
        10.0,
        "In accordance with programming language semantics and compiler type soundness, well-typed terms never evaluate to stuck undefined states, and memory access strictly enforces single-writer multiple-reader exclusivity.",
        p13
    );

    // Domain 10: COMPILER_SYSTEMS (Type confusion, use after free, data race, SSA dominance violation)
    veto_registry_add_forbidden_token(reg, 10.0, 1001.0);
    veto_registry_add_forbidden_token(reg, 10.0, 1002.0);
    veto_registry_add_forbidden_token(reg, 10.0, 1003.0);
    veto_registry_add_forbidden_token(reg, 10.0, 1004.0);

    // 14. Topology, Manifolds & Differential Geometry (Domain 2: TOPOLOGY_GEOMETRY)
    let p14 = cartan_tree_create();
    cartan_tree_push(p14, "boundary of a boundary is non-zero");
    cartan_tree_push(p14, "negative riemannian metric norm");
    cartan_tree_push(p14, "singular manifold tangent space");
    cartan_tree_push(p14, "euler characteristic violation");
    veto_registry_add_rule(
        reg,
        14.0,
        2.0,
        "In accordance with differential geometry and algebraic topology, the boundary of a boundary is identically zero d(d(omega)) = 0, and Riemannian metrics induce strictly positive-definite inner products.",
        p14
    );
    veto_registry_add_forbidden_token(reg, 2.0, 201.0);
    veto_registry_add_forbidden_token(reg, 2.0, 202.0);
    veto_registry_add_forbidden_token(reg, 2.0, 203.0);
    veto_registry_add_forbidden_token(reg, 2.0, 204.0);

    // 15. Computational Complexity & Decidability (Domain 3: COMPLEXITY_THEORY)
    let p15 = cartan_tree_create();
    cartan_tree_push(p15, "deciding the halting problem");
    cartan_tree_push(p15, "general halting decider");
    cartan_tree_push(p15, "turing machine solves undecidable");
    cartan_tree_push(p15, "np-complete solved in logarithmic time");
    veto_registry_add_rule(
        reg,
        15.0,
        3.0,
        "In accordance with theoretical computer science and complexity theory, the Halting Problem is strictly undecidable by any universal Turing machine, and NP-complete problems cannot be decided in sub-polynomial time without certificate validation.",
        p15
    );
    veto_registry_add_forbidden_token(reg, 3.0, 301.0);
    veto_registry_add_forbidden_token(reg, 3.0, 302.0);
    veto_registry_add_forbidden_token(reg, 3.0, 303.0);
    veto_registry_add_forbidden_token(reg, 3.0, 304.0);

    // 16. Information Theory & Cybernetic Limits (Domain 11: INFORMATION_CYBERNETICS)
    let p16 = cartan_tree_create();
    cartan_tree_push(p16, "transmission exceeds channel capacity");
    cartan_tree_push(p16, "negative shannon entropy");
    cartan_tree_push(p16, "data processing inequality violation");
    cartan_tree_push(p16, "infinite mutual information through processing");
    veto_registry_add_rule(
        reg,
        16.0,
        11.0,
        "In accordance with information theory, transmission rates cannot surpass Shannon channel capacity with vanishing error, and mutual information cannot increase under post-processing.",
        p16
    );
    veto_registry_add_forbidden_token(reg, 11.0, 1101.0);
    veto_registry_add_forbidden_token(reg, 11.0, 1102.0);
    veto_registry_add_forbidden_token(reg, 11.0, 1103.0);
    veto_registry_add_forbidden_token(reg, 11.0, 1104.0);

    // 17. Systems Dynamics & Lyapunov Stability (Domain 12: SYSTEMS_CONTROL)
    let p17 = cartan_tree_create();
    cartan_tree_push(p17, "positive lyapunov derivative in stable system");
    cartan_tree_push(p17, "divergent unbounded closed loop");
    cartan_tree_push(p17, "zero controllability rank controllable");
    cartan_tree_push(p17, "infinite phase margin instability");
    veto_registry_add_rule(
        reg,
        17.0,
        12.0,
        "In accordance with dynamical control theory, stable trajectories require negative semi-definite Lyapunov energy derivatives, and complete state regulation mandates full Kalman controllability rank.",
        p17
    );
    veto_registry_add_forbidden_token(reg, 12.0, 1201.0);
    veto_registry_add_forbidden_token(reg, 12.0, 1202.0);
    veto_registry_add_forbidden_token(reg, 12.0, 1203.0);
    veto_registry_add_forbidden_token(reg, 12.0, 1204.0);

    // 18. Metacognitive Calibration & Doubt (Domain 13: METACOGNITION_INTROSPECTION)
    let p18 = cartan_tree_create();
    cartan_tree_push(p18, "overconfident hallucination with high entropy");
    cartan_tree_push(p18, "uncalibrated subjective certainty");
    cartan_tree_push(p18, "suppressing doubt rewind checkpoint");
    cartan_tree_push(p18, "ignoring divergent reasoning conclusions");
    veto_registry_add_rule(
        reg,
        18.0,
        13.0,
        "In accordance with metacognitive introspection, autonomous systems must calibrate confidence against empirical accuracy, triggering doubt rewinds upon predictive entropy divergence.",
        p18
    );
    veto_registry_add_forbidden_token(reg, 13.0, 1301.0);
    veto_registry_add_forbidden_token(reg, 13.0, 1302.0);
    veto_registry_add_forbidden_token(reg, 13.0, 1303.0);
    veto_registry_add_forbidden_token(reg, 13.0, 1304.0);

    // 19. Neuromorphic Systems & Plasticity (Domain 14: NEUROMORPHIC_SYSTEMS)
    let p19 = cartan_tree_create();
    cartan_tree_push(p19, "hopfield energy increases spontaneously");
    cartan_tree_push(p19, "neuron releases both excitatory and inhibitory");
    cartan_tree_push(p19, "dales principle violation");
    cartan_tree_push(p19, "runaway unnormalized hebbian explosion");
    veto_registry_add_rule(
        reg,
        19.0,
        14.0,
        "In accordance with neuromorphic dynamical invariants, recurrent Hopfield networks monotonically minimize Lyapunov energy, neurons obey Dale's principle of invariant sign, and synaptic plasticity remains bounded.",
        p19
    );
    veto_registry_add_forbidden_token(reg, 14.0, 1401.0);
    veto_registry_add_forbidden_token(reg, 14.0, 1402.0);
    veto_registry_add_forbidden_token(reg, 14.0, 1403.0);
    veto_registry_add_forbidden_token(reg, 14.0, 1404.0);

    // 20. Game Theory & Mechanism Design (Domain 15: GAME_THEORY_COORDINATION)
    let p20 = cartan_tree_create();
    cartan_tree_push(p20, "dishonest revelation strictly dominates truthful");
    cartan_tree_push(p20, "incentive compatibility violation");
    cartan_tree_push(p20, "subgame imperfect nash strategy");
    cartan_tree_push(p20, "negative shapley value allocation");
    veto_registry_add_rule(
        reg,
        20.0,
        15.0,
        "In accordance with game theory and mechanism design, dominant-strategy incentive compatibility ensures truthful type revelation, and rational extensive-form strategies satisfy subgame perfection.",
        p20
    );
    veto_registry_add_forbidden_token(reg, 15.0, 1501.0);
    veto_registry_add_forbidden_token(reg, 15.0, 1502.0);
    veto_registry_add_forbidden_token(reg, 15.0, 1503.0);
    veto_registry_add_forbidden_token(reg, 15.0, 1504.0);

    // 21. Scientific Method & Empirical Falsifiability (Domain 16: SCIENTIFIC_METHOD)
    let p21 = cartan_tree_create();
    cartan_tree_push(p21, "unfalsifiable scientific theory");
    cartan_tree_push(p21, "immune to empirical refutation");
    cartan_tree_push(p21, "ignoring confounding backdoor variables");
    cartan_tree_push(p21, "ad-hoc hypothesis without prediction");
    veto_registry_add_rule(
        reg,
        21.0,
        16.0,
        "In accordance with scientific methodology, scientific hypotheses must specify empirical conditions for falsification, and causal inferences mandate strict confounder control.",
        p21
    );
    veto_registry_add_forbidden_token(reg, 16.0, 1601.0);
    veto_registry_add_forbidden_token(reg, 16.0, 1602.0);
    veto_registry_add_forbidden_token(reg, 16.0, 1603.0);
    veto_registry_add_forbidden_token(reg, 16.0, 1604.0);

    // 22. Security, Sandboxing & Capability Safety (Domain 17: SECURITY_SANDBOXING)
    let p22 = cartan_tree_create();
    cartan_tree_push(p22, "ambient authority privilege escalation");
    cartan_tree_push(p22, "memory buffer sandbox escape");
    cartan_tree_push(p22, "information flow covert interference");
    cartan_tree_push(p22, "bypassing capability token authorization");
    veto_registry_add_rule(
        reg,
        22.0,
        17.0,
        "In accordance with security principles, execution units operate under strict least privilege, memory access is strictly sandboxed without boundary escape, and confidentiality enforces information flow non-interference.",
        p22
    );
    veto_registry_add_forbidden_token(reg, 17.0, 1701.0);
    veto_registry_add_forbidden_token(reg, 17.0, 1702.0);
    veto_registry_add_forbidden_token(reg, 17.0, 1703.0);
    veto_registry_add_forbidden_token(reg, 17.0, 1704.0);

    // 23. Software Engineering Anti-Patterns & Contract Violations (Domain 18: SOFTWARE_ENGINEERING_ALGORITHMS)
    let p23 = cartan_tree_create();
    cartan_tree_push(p23, "circular wait deadlock");
    cartan_tree_push(p23, "unbounded recursive stack overflow");
    cartan_tree_push(p23, "violating method postcondition contract");
    cartan_tree_push(p23, "unvalidated external buffer indexing");
    veto_registry_add_rule(
        reg,
        23.0,
        18.0,
        "In accordance with software engineering principles and formal contracts, concurrent systems must prevent circular wait deadlocks, recursive functions must guarantee bounded termination, method postconditions must hold, and external inputs must be validated.",
        p23
    );
    veto_registry_add_forbidden_token(reg, 18.0, 1801.0);
    veto_registry_add_forbidden_token(reg, 18.0, 1802.0);
    veto_registry_add_forbidden_token(reg, 18.0, 1803.0);
    veto_registry_add_forbidden_token(reg, 18.0, 1804.0);
}

// Computes analytical symbolic penalty across output logits to shape training loss
// Directly penalizes logits corresponding to forbidden / contradictory tokens for the active domain
fn veto_compute_symbolic_loss_penalty(reg: VetoRegistry, active_domain: float, logits_vec: ptr, forbidden_token_ids: ptr, lambda_sym: float) -> float {
    if (logits_vec == 0.0 || lambda_sym <= 0.0) { return 0.0; }
    let v_len = cartan_vec_len(logits_vec);
    if (v_len == 0.0) { return 0.0; }

    var penalty_loss = 0.0;

    // 1. Explicit forbidden token IDs
    if (forbidden_token_ids != 0.0) {
        let num_toks = cartan_vec_len(forbidden_token_ids);
        var i = 0.0;
        while (i < num_toks) {
            let tok = cartan_vec_get_f32(forbidden_token_ids, i);
            if (tok >= 0.0 && tok < v_len) {
                let cur_z = cartan_vec_get_f32(logits_vec, tok);
                let pen = lambda_sym * 15.0;
                cartan_vec_set_f32(logits_vec, tok, cur_z - pen);
                let exp_z = exp(cur_z / 10.0);
                if (exp_z > 0.0) {
                    penalty_loss = penalty_loss + (lambda_sym * exp_z * 0.01);
                }
            }
            i = i + 1.0;
        }
    }

    // 2. Automated domain contradiction tokens from veto registry
    if (reg.domain_forbidden_tokens != 0.0) {
        // Universal Domain 0 Invariants (Always checked)
        let d0_list = cartan_tree_get_f32(reg.domain_forbidden_tokens, 0.0);
        if (d0_list != 0.0) {
            let d0_len = collections_list_len(d0_list);
            var j = 0.0;
            while (j < d0_len) {
                let tok0 = collections_list_get(d0_list, j);
                if (tok0 >= 0.0 && tok0 < v_len) {
                    let cur_z = cartan_vec_get_f32(logits_vec, tok0);
                    let pen = lambda_sym * 15.0;
                    cartan_vec_set_f32(logits_vec, tok0, cur_z - pen);
                    let exp_z = exp(cur_z / 10.0);
                    if (exp_z > 0.0) {
                        penalty_loss = penalty_loss + (lambda_sym * exp_z * 0.01);
                    }
                }
                j = j + 1.0;
            }
        }

        // Active domain specific invariants
        if (active_domain > 0.0 && active_domain < 32.0) {
            let da_list = cartan_tree_get_f32(reg.domain_forbidden_tokens, active_domain);
            if (da_list != 0.0) {
                let da_len = collections_list_len(da_list);
                var k = 0.0;
                while (k < da_len) {
                    let tok_a = collections_list_get(da_list, k);
                    if (tok_a >= 0.0 && tok_a < v_len) {
                        let cur_z = cartan_vec_get_f32(logits_vec, tok_a);
                        let pen = lambda_sym * 15.0;
                        cartan_vec_set_f32(logits_vec, tok_a, cur_z - pen);
                        let exp_z = exp(cur_z / 10.0);
                        if (exp_z > 0.0) {
                            penalty_loss = penalty_loss + (lambda_sym * exp_z * 0.01);
                        }
                    }
                    k = k + 1.0;
                }
            }
        }
    }

    return penalty_loss;
}

// Fills out_mask with 1.0 at token indices that are forbidden for active_domain, 0.0 elsewhere.
// out_mask is a raw float buffer allocated with max_vocab elements (e.g., cartan_f32_buffer_alloc).
fn veto_registry_get_domain_forbidden_mask(reg: VetoRegistry, active_domain: float, out_mask: ptr, max_vocab: float) -> float {
    if (out_mask == 0.0 || max_vocab <= 0.0) { return 0.0; }
    var i = 0.0;
    while (i < max_vocab) {
        cartan_set_f32(out_mask, i, 0.0);
        i = i + 1.0;
    }
    if (reg.domain_forbidden_tokens == 0.0) { return 0.0; }
    var count = 0.0;

    // 1. Universal Domain 0 Invariants (always active)
    let d0_list = cartan_tree_get_f32(reg.domain_forbidden_tokens, 0.0);
    if (d0_list != 0.0) {
        let d0_len = collections_list_len(d0_list);
        var j = 0.0;
        while (j < d0_len) {
            let tok0 = collections_list_get(d0_list, j);
            if (tok0 >= 0.0 && tok0 < max_vocab) {
                cartan_set_f32(out_mask, tok0, 1.0);
                count = count + 1.0;
            }
            j = j + 1.0;
        }
    }

    // 2. Active domain specific invariants
    if (active_domain > 0.0 && active_domain < 32.0) {
        let da_list = cartan_tree_get_f32(reg.domain_forbidden_tokens, active_domain);
        if (da_list != 0.0) {
            let da_len = collections_list_len(da_list);
            var k = 0.0;
            while (k < da_len) {
                let tok_a = collections_list_get(da_list, k);
                if (tok_a >= 0.0 && tok_a < max_vocab) {
                    cartan_set_f32(out_mask, tok_a, 1.0);
                    count = count + 1.0;
                }
                k = k + 1.0;
            }
        }
    }

    return count;
}

// Exports a flat float array of forbidden token IDs for active_domain into out_array.
// out_array is allocated with at least max_count elements. Returns the number of tokens written.
fn veto_registry_get_domain_forbidden_array(reg: VetoRegistry, active_domain: float, out_array: ptr, max_count: float) -> float {
    if (out_array == 0.0 || max_count <= 0.0 || reg.domain_forbidden_tokens == 0.0) { return 0.0; }
    var written = 0.0;

    // 1. Universal Domain 0 Invariants
    let d0_list = cartan_tree_get_f32(reg.domain_forbidden_tokens, 0.0);
    if (d0_list != 0.0) {
        let d0_len = collections_list_len(d0_list);
        var j = 0.0;
        while (j < d0_len && written < max_count) {
            let tok0 = collections_list_get(d0_list, j);
            cartan_set_f32(out_array, written, tok0);
            written = written + 1.0;
            j = j + 1.0;
        }
    }

    // 2. Active domain specific invariants
    if (active_domain > 0.0 && active_domain < 32.0) {
        let da_list = cartan_tree_get_f32(reg.domain_forbidden_tokens, active_domain);
        if (da_list != 0.0) {
            let da_len = collections_list_len(da_list);
            var k = 0.0;
            while (k < da_len && written < max_count) {
                let tok_a = collections_list_get(da_list, k);
                cartan_set_f32(out_array, written, tok_a);
                written = written + 1.0;
                k = k + 1.0;
            }
        }
    }

    return written;
}


