// src/std/nses_pipeline.cl
// CARTAN Standard Library: Master Neuro-Symbolic Expert System (NSES) Pipeline Orchestrator
// Neuro-Symbolic Expert System (NSES) Phase 5 Core

include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/cargraph.cl";
include "src/std/sat_solver.cl";
include "src/std/guardrails.cl";
include "src/std/csr_graph.cl";
include "src/std/plasticity.cl";
include "src/std/burroughs.cl";
include "src/std/prompt_scaffold.cl";
include "src/std/veto_gate.cl";

extern fn clock() -> float;

// Helper to reset a cartan_tree size to 0 without reallocating
fn cartan_tree_clear(t: ptr) {
    if (t == 0.0) { return; }
    var i = 8.0;
    while (i < 16.0) {
        cartan_set_byte(t, i, 0.0);
        i = i + 1.0;
    }
}

// Master NSES Pipeline Engine State Structure
struct NSES_Pipeline {
    graph_file: CarGraphFile;
    csr: CsrGraph;
    scratchpad: NSES_Scratchpad;
    burroughs_pool: BurroughsPool;
    prompt_buffer: PromptScaffoldBuffer;
    rng: BurroughsRngState;
    veto_reg: VetoRegistry;
    guardrails_tree: ptr;
    memory_tree: ptr;
    seed_list: ptr;
    act_list: ptr;
    entity_tree: ptr;
    is_ready: float;
    last_turn_latency_ms: float;
}

// Result of an End-to-End NSES Pipeline Turn
struct NSESTurnResult {
    is_vetoed: float;
    final_output: string;
    assembled_prompt: string;
    lateral_fragment: string;
    active_domain: float;
    traversed_count: float;
    turn_latency_ms: float;
}

// Allocates and initializes an end-to-end NSES pipeline
fn nses_pipeline_create(graph_path: string) -> NSES_Pipeline {
    let cg = cargraph_load_binary(graph_path);
    if (cg.is_valid == 0.0) {
        printf("[NSES Pipeline] Warning: Could not load .car_graph at %s\n", graph_path);
    }

    // Compute dynamic CSR node capacity (minimum 256)
    var n_cap = 256.0;
    if (cg.is_valid != 0.0 && cg.header.num_rules + 64.0 > n_cap) {
        n_cap = cg.header.num_rules + 64.0;
    }

    // Build CSR topology from graph
    let b = csr_builder_create(n_cap);
    // Add default causal dependencies across domains
    csr_builder_add_edge(b, 6.0, 7.0, 1.25, 1.0, 0.0);   // Kinetic Energy -> Inelastic Dissipation
    csr_builder_add_edge(b, 7.0, 8.0, 1.20, 1.0, 0.0);   // Inelastic Dissipation -> Restitution e < 1.0
    csr_builder_add_edge(b, 7.0, 10.0, 1.15, 1.0, 0.0);  // Inelastic Dissipation -> Thermal Conduction
    csr_builder_add_edge(b, 14.0, 15.0, 1.30, 1.0, 0.0); // Exterior Derivative -> Stokes Theorem
    csr_builder_add_edge(b, 21.0, 22.0, 1.25, 1.0, 0.0); // Polynomial Reduction -> NP-Completeness
    csr_builder_add_edge(b, 26.0, 27.0, 1.20, 1.0, 0.0); // Photosynthesis -> Cellular Respiration
    csr_builder_add_edge(b, 37.0, 38.0, 1.15, 1.0, 0.0); // Velocity -> Acceleration
    csr_builder_add_edge(b, 39.0, 40.0, 1.10, 1.0, 0.0); // Solid -> Liquid phase transition
    csr_builder_add_edge(b, 44.0, 45.0, 1.25, 1.0, 0.0); // Lexical parsing -> Topical coherence
    csr_builder_add_edge(b, 45.0, 47.0, 1.20, 1.0, 0.0); // Topical coherence -> Lexical grounding
    csr_builder_add_edge(b, 42.0, 49.0, 1.30, 1.0, 0.0); // Speech act coherence -> Propositional commitment
    csr_builder_add_edge(b, 47.0, 48.0, 1.15, 1.0, 0.0); // Lexical grounding -> High IC discrimination
    csr_builder_add_edge(b, 50.0, 51.0, 1.20, 1.0, 0.0); // Cooperative principle -> Discourse transition bridges
    csr_builder_add_edge(b, 54.0, 56.0, 1.30, 1.0, 0.0); // Modus Ponens -> Hypothetical Syllogism
    csr_builder_add_edge(b, 56.0, 60.0, 1.25, 1.0, 0.0); // Hypothetical Syllogism -> Resolution Refutation
    csr_builder_add_edge(b, 57.0, 55.0, 1.20, 1.0, 0.0); // Contraposition -> Modus Tollens
    csr_builder_add_edge(b, 58.0, 59.0, 1.15, 1.0, 0.0); // De Morgan Conjunction -> De Morgan Disjunction
    csr_builder_add_edge(b, 54.0, 70.0, 1.30, 1.0, 0.0); // Modus Ponens -> Deductive Action Preconditions
    csr_builder_add_edge(b, 70.0, 62.0, 1.25, 1.0, 0.0); // Deductive Action Preconditions -> Bellman Optimality
    csr_builder_add_edge(b, 62.0, 66.0, 1.20, 1.0, 0.0); // Bellman Optimality -> Temporal Credit Assignment
    csr_builder_add_edge(b, 64.0, 65.0, 1.15, 1.0, 0.0); // Nash Equilibrium -> Pareto Efficiency
    csr_builder_add_edge(b, 67.0, 71.0, 1.20, 1.0, 0.0); // MCTS UCB1 -> Heuristic Admissibility
    csr_builder_add_edge(b, 72.0, 74.0, 1.30, 1.0, 0.0); // Bayes Rule -> Likelihood Ratio
    csr_builder_add_edge(b, 73.0, 75.0, 1.25, 1.0, 0.0); // AGM Revision -> Defeasible Inference
    csr_builder_add_edge(b, 54.0, 75.0, 1.25, 1.0, 0.0); // Modus Ponens -> Defeasible Logic Bridge (Domain 7 -> Domain 9)
    csr_builder_add_edge(b, 75.0, 77.0, 1.20, 1.0, 0.0); // Defeasible Inference -> POMDP Epistemic State Estimation (Domain 9 -> Domain 8)
    csr_builder_add_edge(b, 76.0, 80.0, 1.20, 1.0, 0.0); // Occam Model Selection -> Bayesian Confirmation Holism
    csr_builder_add_edge(b, 82.0, 84.0, 1.30, 1.0, 0.0); // Type Soundness -> SSA Dominance
    csr_builder_add_edge(b, 85.0, 82.0, 1.30, 1.0, 0.0); // Curry-Howard Isomorphism -> Type Soundness
    csr_builder_add_edge(b, 54.0, 85.0, 1.25, 1.0, 0.0); // Modus Ponens -> Curry-Howard Isomorphism (Domain 7 -> Domain 10)
    csr_builder_add_edge(b, 84.0, 86.0, 1.20, 1.0, 0.0); // SSA Dominance -> Dead Code Elimination
    csr_builder_add_edge(b, 87.0, 21.0, 1.25, 1.0, 0.0); // Register Allocation Chordal Coloring -> Polynomial Reduction (Domain 10 -> Domain 3)
    csr_builder_add_edge(b, 83.0, 91.0, 1.25, 1.0, 0.0); // SWMR Exclusivity -> Linear Resource Typing

    // --- Domain 11: INFORMATION_CYBERNETICS ---
    csr_builder_add_edge(b, 92.0, 93.0, 1.30, 1.0, 0.0); // Shannon Capacity Bound -> Continuous Channel Entropy
    csr_builder_add_edge(b, 93.0, 94.0, 1.25, 1.0, 0.0); // Continuous Channel Entropy -> Negative Feedback Dampening
    csr_builder_add_edge(b, 94.0, 95.0, 1.20, 1.0, 0.0); // Negative Feedback Dampening -> Mutual Information Reduction
    csr_builder_add_edge(b, 93.0, 1.0, 1.20, 1.0, 0.0);  // Information Entropy -> Thermodynamic Entropy (Domain 11 -> Domain 0)

    // --- Domain 12: SYSTEMS_CONTROL ---
    csr_builder_add_edge(b, 102.0, 103.0, 1.30, 1.0, 0.0); // Lyapunov Stability Criterion -> Closed-Loop BIBO Stability
    csr_builder_add_edge(b, 103.0, 104.0, 1.25, 1.0, 0.0); // Closed-Loop BIBO Stability -> Transfer Function Poles
    csr_builder_add_edge(b, 104.0, 105.0, 1.20, 1.0, 0.0); // Transfer Function Poles -> Kalman Filter State Estimation
    csr_builder_add_edge(b, 94.0, 102.0, 1.25, 1.0, 0.0);  // Cybernetic Feedback -> Lyapunov Stability (Domain 11 -> Domain 12)

    // --- Domain 13: METACOGNITION_INTROSPECTION ---
    csr_builder_add_edge(b, 112.0, 113.0, 1.30, 1.0, 0.0); // Metacognitive Monitoring -> Epistemic Calibration Divergence
    csr_builder_add_edge(b, 113.0, 114.0, 1.25, 1.0, 0.0); // Epistemic Calibration Divergence -> Inferential Trace Audit
    csr_builder_add_edge(b, 114.0, 115.0, 1.20, 1.0, 0.0); // Inferential Trace Audit -> Anomaly Surprise Restructuring
    csr_builder_add_edge(b, 112.0, 72.0, 1.25, 1.0, 0.0);  // Metacognitive Monitoring -> Bayesian Posterior (Domain 13 -> Domain 9)

    // --- Domain 14: NEUROMORPHIC_SYSTEMS ---
    csr_builder_add_edge(b, 122.0, 123.0, 1.30, 1.0, 0.0); // Spike-Timing-Dependent Plasticity -> Membrane Refractory Period
    csr_builder_add_edge(b, 123.0, 124.0, 1.25, 1.0, 0.0); // Membrane Refractory Period -> Leaky Integrate-and-Fire Dynamics
    csr_builder_add_edge(b, 124.0, 125.0, 1.20, 1.0, 0.0); // Leaky Integrate-and-Fire Dynamics -> Asynchronous Clockless Routing
    csr_builder_add_edge(b, 122.0, 26.0, 1.20, 1.0, 0.0);  // Neuromorphic Synaptic Plasticity -> Biological Phosphorylation (Domain 14 -> Domain 4)

    // --- Domain 15: GAME_THEORY_COORDINATION ---
    csr_builder_add_edge(b, 132.0, 133.0, 1.30, 1.0, 0.0); // Correlated Equilibrium Coordination -> Pareto Optimal Frontier
    csr_builder_add_edge(b, 133.0, 134.0, 1.25, 1.0, 0.0); // Pareto Optimal Frontier -> VCG Incentive Compatibility
    csr_builder_add_edge(b, 134.0, 135.0, 1.20, 1.0, 0.0); // VCG Incentive Compatibility -> Iterated Folk Theorem Coalitions
    csr_builder_add_edge(b, 132.0, 64.0, 1.25, 1.0, 0.0);  // Correlated Equilibrium -> Nash Equilibrium (Domain 15 -> Domain 8)

    // --- Domain 16: SCIENTIFIC_METHOD ---
    csr_builder_add_edge(b, 142.0, 143.0, 1.30, 1.0, 0.0); // Empirical Falsifiability Criterion -> Controlled Randomized Trial
    csr_builder_add_edge(b, 143.0, 144.0, 1.25, 1.0, 0.0); // Controlled Randomized Trial -> Null Hypothesis Statistical Power
    csr_builder_add_edge(b, 144.0, 145.0, 1.20, 1.0, 0.0); // Null Hypothesis Statistical Power -> Replicability Demarcation
    csr_builder_add_edge(b, 142.0, 54.0, 1.25, 1.0, 0.0);  // Empirical Falsifiability -> Modus Ponens (Domain 16 -> Domain 7)

    // --- Domain 17: SECURITY_SANDBOXING ---
    csr_builder_add_edge(b, 152.0, 153.0, 1.30, 1.0, 0.0); // Capability-Based Security Principle -> Principle of Least Privilege
    csr_builder_add_edge(b, 153.0, 154.0, 1.25, 1.0, 0.0); // Principle of Least Privilege -> Hardware Memory Sandbox Isolation
    csr_builder_add_edge(b, 154.0, 155.0, 1.20, 1.0, 0.0); // Hardware Memory Sandbox Isolation -> Temporal Privilege Revocation
    csr_builder_add_edge(b, 153.0, 83.0, 1.30, 1.0, 0.0);  // Least Privilege Sandbox -> SWMR Memory Exclusivity (Domain 17 -> Domain 10)

    // --- Domain 18: SOFTWARE_ENGINEERING_ALGORITHMS ---
    csr_builder_add_edge(b, 162.0, 163.0, 1.30, 1.0, 0.0); // Design by Contract -> Algorithmic Termination
    csr_builder_add_edge(b, 163.0, 168.0, 1.25, 1.0, 0.0); // Algorithmic Termination -> Amortized Complexity
    csr_builder_add_edge(b, 166.0, 169.0, 1.20, 1.0, 0.0); // Deadlock Freedom -> Idempotent Retry
    csr_builder_add_edge(b, 162.0, 82.0, 1.25, 1.0, 0.0);  // Design by Contract -> Type Soundness (Domain 18 -> Domain 10)
    csr_builder_add_edge(b, 163.0, 21.0, 1.20, 1.0, 0.0);  // Algorithmic Termination -> Complexity Reductions (Domain 18 -> Domain 3)
    csr_builder_add_edge(b, 166.0, 132.0, 1.20, 1.0, 0.0); // Deadlock Freedom -> Incentive Compatibility (Domain 18 -> Domain 15)

    // Hub-and-Spoke Universal Cross-Domain Linguistic Grounding (Domain 6 -> All Domains)
    csr_builder_add_edge(b, 47.0, 0.0, 1.25, 1.0, 0.0);   // Lexical Grounding -> Conservation Invariant (Domain 0)
    csr_builder_add_edge(b, 47.0, 6.0, 1.20, 1.0, 0.0);   // Lexical Grounding -> Kinetic Energy (Domain 1)
    csr_builder_add_edge(b, 47.0, 14.0, 1.25, 1.0, 0.0);  // Lexical Grounding -> Exterior Derivative (Domain 2)
    csr_builder_add_edge(b, 47.0, 21.0, 1.20, 1.0, 0.0);  // Lexical Grounding -> Polynomial Reduction (Domain 3)
    csr_builder_add_edge(b, 47.0, 26.0, 1.20, 1.0, 0.0);  // Lexical Grounding -> Photosynthesis (Domain 4)
    csr_builder_add_edge(b, 47.0, 37.0, 1.15, 1.0, 0.0);  // Lexical Grounding -> Kinematic Velocity (Domain 5)
    csr_builder_add_edge(b, 47.0, 54.0, 1.30, 1.0, 0.0);  // Lexical Grounding -> Modus Ponens (Domain 7)
    csr_builder_add_edge(b, 47.0, 62.0, 1.25, 1.0, 0.0);  // Lexical Grounding -> Bellman Optimality (Domain 8)
    csr_builder_add_edge(b, 47.0, 72.0, 1.25, 1.0, 0.0);  // Lexical Grounding -> Bayesian Posterior Invariant (Domain 9)
    csr_builder_add_edge(b, 47.0, 82.0, 1.25, 1.0, 0.0);  // Lexical Grounding -> Type Soundness Invariant (Domain 10)
    csr_builder_add_edge(b, 47.0, 92.0, 1.25, 1.0, 0.0);  // Lexical Grounding -> Shannon Capacity Invariant (Domain 11)
    csr_builder_add_edge(b, 47.0, 102.0, 1.25, 1.0, 0.0); // Lexical Grounding -> Lyapunov Stability Invariant (Domain 12)
    csr_builder_add_edge(b, 47.0, 112.0, 1.25, 1.0, 0.0); // Lexical Grounding -> Metacognitive Monitoring Invariant (Domain 13)
    csr_builder_add_edge(b, 47.0, 122.0, 1.25, 1.0, 0.0); // Lexical Grounding -> STDP Plasticity Invariant (Domain 14)
    csr_builder_add_edge(b, 47.0, 132.0, 1.25, 1.0, 0.0); // Lexical Grounding -> Correlated Equilibrium Invariant (Domain 15)
    csr_builder_add_edge(b, 47.0, 142.0, 1.25, 1.0, 0.0); // Lexical Grounding -> Empirical Falsifiability Invariant (Domain 16)
    csr_builder_add_edge(b, 47.0, 152.0, 1.25, 1.0, 0.0); // Lexical Grounding -> Capability Security Invariant (Domain 17)
    csr_builder_add_edge(b, 47.0, 162.0, 1.25, 1.0, 0.0); // Lexical Grounding -> Design by Contract Invariant (Domain 18)
    let g = csr_builder_build(b);
    csr_builder_free(b);

    let pad = nses_scratchpad_create(n_cap, n_cap);
    let pool = burroughs_pool_create(32.0);
    burroughs_pool_populate_defaults(pool);

    let p_buf = prompt_scaffold_create(65536.0);
    let rng = burroughs_rng_init(135792468.0, 975318642.0);

    let v_reg = veto_registry_create();
    veto_registry_populate_defaults(v_reg);

    let g_tree = cartan_tree_create();
    cartan_tree_push(g_tree, "Conservation of energy must not be violated under any scenario; energy cannot be created or destroyed.");
    cartan_tree_push(g_tree, "Second law of thermodynamics: Total entropy in an isolated system can never spontaneously decrease.");
    cartan_tree_push(g_tree, "Relativistic causality: No physical mass or causal information can propagate faster than light speed c.");
    cartan_tree_push(g_tree, "Fundamental law of non-contradiction: Contradictory propositions (P and not P) cannot be simultaneously valid.");

    let m_tree = cartan_tree_create();
    let s_list = collections_create_list();
    let a_list = collections_create_list();

    let e_tree = cartan_tree_create();
    if (cg.is_valid != 0.0 && cg.header.num_entities > 0.0) {
        var e_i = 0.0;
        while (e_i < cg.header.num_entities) {
            let ws_tag = cargraph_format_world_state(cg, e_i);
            cartan_tree_push(e_tree, ws_tag);
            e_i = e_i + 1.0;
        }
    }

    return NSES_Pipeline {
        graph_file: cg,
        csr: g,
        scratchpad: pad,
        burroughs_pool: pool,
        prompt_buffer: p_buf,
        rng: rng,
        veto_reg: v_reg,
        guardrails_tree: g_tree,
        memory_tree: m_tree,
        seed_list: s_list,
        act_list: a_list,
        entity_tree: e_tree,
        is_ready: 1.0,
        last_turn_latency_ms: 0.0
    };
}

// Executes an end-to-end NSES inference turn with 7-stage latency tracking
fn nses_pipeline_execute_turn(
    pipe: NSES_Pipeline,
    query: string,
    entropy_tier: float,
    raw_model_candidate: string
) -> NSESTurnResult {
    let t0 = clock();

    // -------------------------------------------------------------------------
    // Stage 1: Domain Routing (Domain 0 + routed domain)
    // -------------------------------------------------------------------------
    var routed_domain = 1.0; // Default to PHYSICS_SIM
    if (cartan_string_contains(query, "manifold") != 0.0 || cartan_string_contains(query, "differential") != 0.0 || cartan_string_contains(query, "homotopy") != 0.0) {
        routed_domain = 2.0; // TOPOLOGY_GEOMETRY
    } else if (cartan_string_contains(query, "turing") != 0.0 || cartan_string_contains(query, "halting") != 0.0 || cartan_string_contains(query, "np") != 0.0) {
        routed_domain = 3.0; // COMPLEXITY_THEORY
    } else if (cartan_string_contains(query, "biology") != 0.0 || cartan_string_contains(query, "cell") != 0.0 || cartan_string_contains(query, "dna") != 0.0 || cartan_string_contains(query, "metabolism") != 0.0) {
        routed_domain = 4.0; // BIOLOGICAL_SYSTEMS
    } else if (cartan_string_contains(query, "cause") != 0.0 || cartan_string_contains(query, "state") != 0.0 || cartan_string_contains(query, "matter") != 0.0 || cartan_string_contains(query, "taxonomy") != 0.0) {
        routed_domain = 5.0; // CAUSAL_TAXONOMY
    } else if (cartan_string_contains(query, "language") != 0.0 || cartan_string_contains(query, "word") != 0.0 || cartan_string_contains(query, "grammar") != 0.0 || cartan_string_contains(query, "speech") != 0.0 || cartan_string_contains(query, "talk") != 0.0 || cartan_string_contains(query, "dialogue") != 0.0 || cartan_string_contains(query, "conversation") != 0.0 || cartan_string_contains(query, "syntax") != 0.0 || cartan_string_contains(query, "communicate") != 0.0 || cartan_string_contains(query, "question") != 0.0 || cartan_string_contains(query, "pronoun") != 0.0) {
        routed_domain = 6.0; // LANGUAGE_DISCOURSE
    } else if (cartan_string_contains(query, "logic") != 0.0 || cartan_string_contains(query, "deduce") != 0.0 || cartan_string_contains(query, "premise") != 0.0 || cartan_string_contains(query, "conclusion") != 0.0 || cartan_string_contains(query, "syllogism") != 0.0 || cartan_string_contains(query, "modus") != 0.0 || cartan_string_contains(query, "proof") != 0.0 || cartan_string_contains(query, "infer") != 0.0 || cartan_string_contains(query, "axiom") != 0.0 || cartan_string_contains(query, "contradict") != 0.0) {
        routed_domain = 7.0; // LOGIC_REASONING
    } else if (cartan_string_contains(query, "decision") != 0.0 || cartan_string_contains(query, "plan") != 0.0 || cartan_string_contains(query, "game") != 0.0 || cartan_string_contains(query, "policy") != 0.0 || cartan_string_contains(query, "utility") != 0.0 || cartan_string_contains(query, "nash") != 0.0 || cartan_string_contains(query, "pareto") != 0.0 || cartan_string_contains(query, "bellman") != 0.0 || cartan_string_contains(query, "action") != 0.0 || cartan_string_contains(query, "reward") != 0.0 || cartan_string_contains(query, "mcts") != 0.0 || cartan_string_contains(query, "heuristic") != 0.0) {
        routed_domain = 8.0; // DECISION_PLANNING
    } else if (cartan_string_contains(query, "epistemolog") != 0.0 || cartan_string_contains(query, "belief") != 0.0 || cartan_string_contains(query, "bayes") != 0.0 || cartan_string_contains(query, "posterior") != 0.0 || cartan_string_contains(query, "prior") != 0.0 || cartan_string_contains(query, "evidence") != 0.0 || cartan_string_contains(query, "credence") != 0.0 || cartan_string_contains(query, "uncertainty") != 0.0 || cartan_string_contains(query, "agm") != 0.0 || cartan_string_contains(query, "defeasible") != 0.0 || cartan_string_contains(query, "likelihood") != 0.0 || cartan_string_contains(query, "occam") != 0.0 || cartan_string_contains(query, "name") != 0.0 || cartan_string_contains(query, "identity") != 0.0 || cartan_string_contains(query, "yourself") != 0.0 || cartan_string_contains(query, "who are you") != 0.0) {
        routed_domain = 9.0; // EPISTEMOLOGY_BELIEF / SELF_AND_IDENTITY
    } else if (cartan_string_contains(query, "compiler") != 0.0 || cartan_string_contains(query, "type_check") != 0.0 || cartan_string_contains(query, "syntax_tree") != 0.0 || cartan_string_contains(query, "llvm") != 0.0 || cartan_string_contains(query, "ssa") != 0.0 || cartan_string_contains(query, "register") != 0.0 || cartan_string_contains(query, "monomorph") != 0.0 || cartan_string_contains(query, "borrow") != 0.0 || cartan_string_contains(query, "bytecode") != 0.0 || cartan_string_contains(query, "codegen") != 0.0 || cartan_string_contains(query, "syntax") != 0.0) {
        routed_domain = 10.0; // COMPILER_SYSTEMS
    } else if (cartan_string_contains(query, "shannon") != 0.0 || cartan_string_contains(query, "cybernet") != 0.0 || cartan_string_contains(query, "channel") != 0.0 || cartan_string_contains(query, "capacity") != 0.0 || cartan_string_contains(query, "mutual_information") != 0.0) {
        routed_domain = 11.0; // INFORMATION_CYBERNETICS
    } else if (cartan_string_contains(query, "control") != 0.0 || cartan_string_contains(query, "closed_loop") != 0.0 || cartan_string_contains(query, "lyapunov") != 0.0 || cartan_string_contains(query, "transfer_function") != 0.0 || cartan_string_contains(query, "kalman") != 0.0 || cartan_string_contains(query, "bibo") != 0.0) {
        routed_domain = 12.0; // SYSTEMS_CONTROL
    } else if (cartan_string_contains(query, "metacognit") != 0.0 || cartan_string_contains(query, "introspection") != 0.0 || cartan_string_contains(query, "calibration") != 0.0 || cartan_string_contains(query, "self_reflection") != 0.0 || cartan_string_contains(query, "cognitive_bias") != 0.0) {
        routed_domain = 13.0; // METACOGNITION_INTROSPECTION
    } else if (cartan_string_contains(query, "neuromorphic") != 0.0 || cartan_string_contains(query, "spike") != 0.0 || cartan_string_contains(query, "stdp") != 0.0 || cartan_string_contains(query, "synaptic") != 0.0 || cartan_string_contains(query, "membrane") != 0.0 || cartan_string_contains(query, "integrate_and_fire") != 0.0) {
        routed_domain = 14.0; // NEUROMORPHIC_SYSTEMS
    } else if (cartan_string_contains(query, "coordination") != 0.0 || cartan_string_contains(query, "correlated") != 0.0 || cartan_string_contains(query, "equilibrium") != 0.0 || cartan_string_contains(query, "mechanism") != 0.0 || cartan_string_contains(query, "auction") != 0.0 || cartan_string_contains(query, "cooperative") != 0.0 || cartan_string_contains(query, "folk_theorem") != 0.0) {
        routed_domain = 15.0; // GAME_THEORY_COORDINATION
    } else if (cartan_string_contains(query, "scientific") != 0.0 || cartan_string_contains(query, "falsifi") != 0.0 || cartan_string_contains(query, "hypothesis") != 0.0 || cartan_string_contains(query, "experiment") != 0.0 || cartan_string_contains(query, "replicab") != 0.0) {
        routed_domain = 16.0; // SCIENTIFIC_METHOD
    } else if (cartan_string_contains(query, "security") != 0.0 || cartan_string_contains(query, "sandbox") != 0.0 || cartan_string_contains(query, "least_privilege") != 0.0 || cartan_string_contains(query, "isolation") != 0.0 || cartan_string_contains(query, "capability") != 0.0 || cartan_string_contains(query, "privilege") != 0.0) {
        routed_domain = 17.0; // SECURITY_SANDBOXING
    } else if (cartan_string_contains(query, "software") != 0.0 || cartan_string_contains(query, "programming") != 0.0 || cartan_string_contains(query, "concurrency") != 0.0 || cartan_string_contains(query, "deadlock") != 0.0 || cartan_string_contains(query, "refactor") != 0.0 || cartan_string_contains(query, "algorithm") != 0.0 || cartan_string_contains(query, "contract") != 0.0 || cartan_string_contains(query, "data_structure") != 0.0 || cartan_string_contains(query, "liskov") != 0.0 || cartan_string_contains(query, "idempotenc") != 0.0) {
        routed_domain = 18.0; // SOFTWARE_ENGINEERING_ALGORITHMS
    }

    // -------------------------------------------------------------------------
    // Stage 2: Deterministic Guardrails Query (Domain 0 + active domain)
    // -------------------------------------------------------------------------
    let guardrails_tree = pipe.guardrails_tree;

    // -------------------------------------------------------------------------
    // Stage 3 & 4: ANN Seed Proximity & Zero-Allocation CSR Traversal
    // -------------------------------------------------------------------------
    cartan_vec_clear(pipe.seed_list);
    cartan_vec_clear(pipe.act_list);

    if (routed_domain == 1.0) {
        collections_list_push(pipe.seed_list, 6.0); // Seed: Rule 6 (Kinetic energy)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 2.0) {
        collections_list_push(pipe.seed_list, 14.0); // Seed: Rule 14 (Exterior derivative)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 3.0) {
        collections_list_push(pipe.seed_list, 21.0); // Seed: Rule 21 (Polynomial reduction)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 4.0) {
        collections_list_push(pipe.seed_list, 26.0); // Seed: Rule 26 (Photosynthesis)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 5.0) {
        collections_list_push(pipe.seed_list, 37.0); // Seed: Rule 37 (Velocity -> Acceleration)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 6.0) {
        collections_list_push(pipe.seed_list, 44.0); // Seed: Rule 44 (Syntactic parsing and lexical recognition)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 7.0) {
        collections_list_push(pipe.seed_list, 54.0); // Seed: Rule 54 (Modus Ponens)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 8.0) {
        collections_list_push(pipe.seed_list, 70.0); // Seed: Rule 70 (Deductive Action Preconditions)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 9.0) {
        collections_list_push(pipe.seed_list, 72.0); // Seed: Rule 72 (Bayesian Posterior Invariant)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 10.0) {
        collections_list_push(pipe.seed_list, 82.0); // Seed: Rule 82 (Type Soundness Invariant)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 11.0) {
        collections_list_push(pipe.seed_list, 92.0); // Seed: Rule 92 (Shannon Capacity Invariant)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 12.0) {
        collections_list_push(pipe.seed_list, 102.0); // Seed: Rule 102 (Lyapunov Stability Invariant)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 13.0) {
        collections_list_push(pipe.seed_list, 112.0); // Seed: Rule 112 (Metacognitive Monitoring Invariant)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 14.0) {
        collections_list_push(pipe.seed_list, 122.0); // Seed: Rule 122 (STDP Plasticity Invariant)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 15.0) {
        collections_list_push(pipe.seed_list, 132.0); // Seed: Rule 132 (Correlated Equilibrium Invariant)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 16.0) {
        collections_list_push(pipe.seed_list, 142.0); // Seed: Rule 142 (Empirical Falsifiability Invariant)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 17.0) {
        collections_list_push(pipe.seed_list, 152.0); // Seed: Rule 152 (Capability Security Invariant)
        collections_list_push(pipe.act_list, 1.0);
    } else if (routed_domain == 18.0) {
        collections_list_push(pipe.seed_list, 162.0); // Seed: Rule 162 (Design by Contract Invariant)
        collections_list_push(pipe.act_list, 1.0);
    } else {
        collections_list_push(pipe.seed_list, 44.0);
        collections_list_push(pipe.act_list, 1.0);
    }

    let traversed_cnt = csr_traverse_bfs(pipe.csr, pipe.scratchpad, pipe.seed_list, pipe.act_list, 2.0, 0.50, 0.85, 0.0);

    cartan_tree_clear(pipe.memory_tree);
    var m_idx = 0.0;
    while (m_idx < traversed_cnt) {
        let n_id = collections_list_get(pipe.scratchpad.result_node_ids, m_idx);
        var resolved_text = "";
        if (pipe.graph_file.is_valid != 0.0 && n_id < pipe.graph_file.header.num_rules) {
            resolved_text = cargraph_get_rule_text(pipe.graph_file, n_id);
        }
        if (cartan_string_length(resolved_text) > 0.0) {
            cartan_tree_push(pipe.memory_tree, resolved_text);
        }
        m_idx = m_idx + 1.0;
    }

    // -------------------------------------------------------------------------
    // Stage 5: Burroughs Stochastic Lateral Injection
    // -------------------------------------------------------------------------
    let lateral_frag = burroughs_sample_fragment(pipe.burroughs_pool, routed_domain, entropy_tier, pipe.rng);

    // -------------------------------------------------------------------------
    // Stage 6: Structured 4-Block Prompt Scaffold Assembly
    // -------------------------------------------------------------------------
    let prompt_text = prompt_assemble_scaffold_v2(pipe.prompt_buffer, pipe.guardrails_tree, pipe.memory_tree, pipe.entity_tree, lateral_frag, query);

    // -------------------------------------------------------------------------
    // Stage 7: Absolute Post-Pass Deterministic Veto Gate
    // -------------------------------------------------------------------------
    let veto_res = veto_gate_scan(pipe.veto_reg, raw_model_candidate);

    // -------------------------------------------------------------------------
    // Post-Turn Synaptic Plasticity Reinforcement
    // -------------------------------------------------------------------------
    if (traversed_cnt > 1.0) {
        // Reinforce traversed edges (edge 0: 6->7)
        hebbian_reinforce_edge(pipe.csr.edge_weights, pipe.csr.edge_timestamps, 0.0, 0.05, 5.0, pipe.scratchpad.current_epoch);
    }

    let t1 = clock();
    let turn_ms = t1 - t0;
    pipe.last_turn_latency_ms = turn_ms;

    return NSESTurnResult {
        is_vetoed: veto_res.is_vetoed,
        final_output: veto_res.output_text,
        assembled_prompt: prompt_text,
        lateral_fragment: lateral_frag,
        active_domain: routed_domain,
        traversed_count: traversed_cnt,
        turn_latency_ms: turn_ms
    };
}

// Evaluates active domain constraints and shapes logits via symbolic penalty gradient
fn nses_pipeline_shape_loss(pipe: NSES_Pipeline, active_domain: float, logits_vec: ptr, forbidden_token_ids: ptr, lambda_sym: float) -> float {
    return veto_compute_symbolic_loss_penalty(pipe.veto_reg, active_domain, logits_vec, forbidden_token_ids, lambda_sym);
}

// Frees all pipeline resources
fn nses_pipeline_free(pipe: NSES_Pipeline) {
    if (pipe.graph_file.is_valid != 0.0) { cargraph_free(pipe.graph_file); }
    csr_graph_free(pipe.csr);
    nses_scratchpad_free(pipe.scratchpad);
    burroughs_pool_free(pipe.burroughs_pool);
    prompt_scaffold_free(pipe.prompt_buffer);
    veto_registry_free(pipe.veto_reg);
    if (pipe.seed_list != 0.0) { collections_free_list(pipe.seed_list); }
    if (pipe.act_list != 0.0) { collections_free_list(pipe.act_list); }
}

