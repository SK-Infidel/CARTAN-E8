// test/geomind/e8_eval_suite.cl
// Epistemic Evaluation Suite: Q1-Q20 Relational QA, Novel Recombination, Grokking, & S^247 Microfeatures

include "src/std/geom.cl";
include "src/std/math.cl";
include "src/std/collections.cl";
include "src/std/string.cl";
include "src/std/fs.cl";

// Run the complete Epistemic, Taxonomic, & Subtle Geometric Reasoning Evaluation Suite (callable from --curriculum or standalone --eval-qa)
fn geomind_run_epistemic_eval_suite(num_layers: float) -> float {
    var L = floor(num_layers);
    if (L < 1.0) { L = 42.0; }
    geomind_markov_init_if_needed();
    geomind_byte_latent_init_if_needed();
    if (g_e8_stack_initialized == 0.0) {
        geomind_e8_stack_init(L);
        let stack_path = "Projects/geomind/trainingdata/checkpoints/geomind_e8_deep_stack.bin";
        if (cartan_file_exists(stack_path) == 1.0) {
            geomind_e8_stack_load(stack_path);
        }
    }
    geomind_wordnet_init_if_needed();
    geomind_e8_rel_init_if_needed();
    geomind_e8_anchors_init_if_needed();

    printf("--------------------------------------------------------------------------------\n");
    printf("  NOVEL CONCEPT RECOMBINATION TEST (Unseen Prefixes Bridging Shared Word Hubs)\n");
    printf("--------------------------------------------------------------------------------\n");
    printf("  -> Novel 1 ('The cat likes to play'):    %s\n", geomind_byte_latent_generate_deep_e8("The cat likes to play", L, 48.0));
    printf("  -> Novel 2 ('A small dog found'):        %s\n", geomind_byte_latent_generate_deep_e8("A small dog found", L, 48.0));
    printf("  -> Novel 3 ('Cold water is'):            %s\n", geomind_byte_latent_generate_deep_e8("Cold water is", L, 48.0));
    printf("  -> Novel 4 ('When rain falls, the cat'): %s\n", geomind_byte_latent_generate_deep_e8("When rain falls, the cat", L, 48.0));
    printf("  -> Novel 5 ('The dog can bounce'):       %s\n", geomind_byte_latent_generate_deep_e8("The dog can bounce", L, 48.0));
    printf("  -> Novel 6 ('Alice stood on the'):       %s\n", geomind_byte_latent_generate_deep_e8("Alice stood on the", L, 56.0));
    printf("  -> Novel 7 ('Commander Vane found a'):   %s\n", geomind_byte_latent_generate_deep_e8("Commander Vane found a", L, 56.0));
    printf("  -> Novel 8 ('Sherlock Holmes stood on'): %s\n", geomind_byte_latent_generate_deep_e8("Sherlock Holmes stood on", L, 56.0));
    printf("--------------------------------------------------------------------------------\n");
    printf("  WORDNET + IC TAXONOMIC GROKKING TEST (Zero-Shot Synset Property Inheritance)\n");
    printf("--------------------------------------------------------------------------------\n");
    printf("  -> Grok 1 ('The puppy likes to'):        %s\n", geomind_byte_latent_generate_deep_e8("The puppy likes to", L, 48.0));
    printf("  -> Grok 2 ('A gentle kitten'):           %s\n", geomind_byte_latent_generate_deep_e8("A gentle kitten", L, 48.0));
    printf("  -> Grok 3 ('A sparrow can'):             %s\n", geomind_byte_latent_generate_deep_e8("A sparrow can", L, 48.0));
    printf("  -> Grok 4 ('You can bounce the orb'):    %s\n", geomind_byte_latent_generate_deep_e8("You can bounce the orb", L, 48.0));
    printf("--------------------------------------------------------------------------------\n");
    printf("  248x248 MANIFOLD CONCEPT-WEIGHTING & RELATIONAL UNDERSTANDING AUDIT (S^247)\n");
    printf("--------------------------------------------------------------------------------\n");
    let w_sparrow_bird = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "sparrow", "bird");
    let w_bird_sparrow = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "bird", "sparrow");
    let w_robin_bird   = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "robin", "bird");
    let w_kitten_cat   = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "kitten", "cat");
    let w_cat_kitten   = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "cat", "kitten");
    let w_puppy_dog    = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "puppy", "dog");
    let w_dog_puppy    = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "dog", "puppy");
    let w_orb_ball     = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "orb", "ball");
    let w_sphere_ball  = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "sphere", "ball");
    let w_ball_orb     = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "ball", "orb");
    let w_sparrow_dog  = geomind_e8_rel_score_words(g_e8_rel_isa_248x248, "sparrow", "dog");
    printf("  [Asymmetric IS_A Operator <P_hyper, R_isa * P_hypo> / 248 (Codebook = %.0f / 4096 words)]:\n", g_e8_vocab_count);
    printf("    * sparrow -> bird = %.4f | Zero-Shot robin  -> bird = %.4f (Reverse bird -> sparrow = %.4f)\n", w_sparrow_bird, w_robin_bird, w_bird_sparrow);
    printf("    * kitten  -> cat  = %.4f  (Reverse cat  -> kitten  = %.4f)\n", w_kitten_cat, w_cat_kitten);
    printf("    * puppy   -> dog  = %.4f  (Reverse dog  -> puppy   = %.4f)\n", w_puppy_dog, w_dog_puppy);
    printf("    * orb     -> ball = %.4f | Zero-Shot sphere -> ball = %.4f (Reverse ball -> orb = %.4f | sparrow -> dog = %.4f)\n", w_orb_ball, w_sphere_ball, w_ball_orb, w_sparrow_dog);

    let p_kitten_young = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "kitten", "young");
    let p_puppy_young  = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "puppy", "young");
    let p_sparrow_sm   = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "sparrow", "small");
    let p_ball_round   = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "ball", "round");
    let p_bouncing_fun = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "bouncing", "fun");
    let p_run_fun      = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "run", "fun");
    let p_play_fun     = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "play", "fun");
    let p_bounce_fun   = geomind_e8_rel_score_words(g_e8_rel_prop_248x248, "bounce", "fun");
    let cos_run_play   = geomind_e8_rel_prop_cosine_words("run", "play");
    printf("  [Property & Activity Valence Operator <P_attr, R_prop * P_concept> / 248]:\n");
    printf("    * kitten -> young = %.4f | puppy -> young = %.4f | sparrow -> small = %.4f | ball -> round = %.4f\n",
        p_kitten_young, p_puppy_young, p_sparrow_sm, p_ball_round);
    printf("    * bouncing -> fun = %.4f | run   -> fun   = %.4f | play    -> fun   = %.4f | bounce -> fun = %.4f\n",
        p_bouncing_fun, p_run_fun, p_play_fun, p_bounce_fun);
    printf("    * Shared Activity Valence Cosine cos(R_prop*run, R_prop*play) = %.4f\n", cos_run_play);
    printf("--------------------------------------------------------------------------------\n");
    printf("  42-LAYER STRATIFIED E8 DEEP-THOUGHT GEODESIC ROLLOUT (6 x 7-Layer Cascades)\n");
    printf("--------------------------------------------------------------------------------\n");
    printf("  -> Rollout 1  ('sparrow'):   %s\n", geomind_e8_deep_thought_rollout_42L("sparrow"));
    printf("  -> Rollout 2  ('robin'):     %s\n", geomind_e8_deep_thought_rollout_42L("robin"));
    printf("  -> Rollout 3  ('penguin'):   %s\n", geomind_e8_deep_thought_rollout_42L("penguin"));
    printf("  -> Rollout 4  ('ostrich'):   %s\n", geomind_e8_deep_thought_rollout_42L("ostrich"));
    printf("  -> Rollout 5  ('emu'):       %s\n", geomind_e8_deep_thought_rollout_42L("emu"));
    printf("  -> Rollout 6  ('cassowary'): %s\n", geomind_e8_deep_thought_rollout_42L("cassowary"));
    printf("  -> Rollout 7  ('kitten'):    %s\n", geomind_e8_deep_thought_rollout_42L("kitten"));
    printf("  -> Rollout 8  ('puppy'):     %s\n", geomind_e8_deep_thought_rollout_42L("puppy"));
    printf("  -> Rollout 9  ('orb'):       %s\n", geomind_e8_deep_thought_rollout_42L("orb"));
    printf("  -> Rollout 10 ('sphere'):    %s\n", geomind_e8_deep_thought_rollout_42L("sphere"));
    printf("  -> Rollout 11 ('wood'):      %s\n", geomind_e8_deep_thought_rollout_42L("wood"));
    printf("--------------------------------------------------------------------------------\n");
    printf("  DAY-ZERO EPISTEMIC REASONING & QUESTION-ANSWERING TEST (Coupled 42L + Tapestry)\n");
    printf("--------------------------------------------------------------------------------\n");
    printf("  -> Q1 ('Is a sparrow an animal and where can it fly?'):\n");
    printf("     A1: %s\n", geomind_e8_answer_epistemic_question("Is a sparrow an animal and where can it fly?"));
    printf("  -> Q2 ('Why does a puppy like to run?'):\n");
    printf("     A2: %s\n", geomind_e8_answer_epistemic_question("Why does a puppy like to run?"));
    printf("  -> Q3 ('How does a kitten feel when it purrs?'):\n");
    printf("     A3: %s\n", geomind_e8_answer_epistemic_question("How does a kitten feel when it purrs?"));
    printf("  -> Q4 [Zero-Shot Unseen Sibling ('orb')] ('What happens when you drop an orb?'):\n");
    printf("     A4: %s\n", geomind_e8_answer_epistemic_question("What happens when you drop an orb?"));
    printf("  -> Q5 ('Why does wood float on water?'):\n");
    printf("     A5: %s\n", geomind_e8_answer_epistemic_question("Why does wood float on water?"));
    printf("  -> Q6 [Zero-Shot Unseen Sibling ('robin' vs 'sparrow')] ('Is a robin an animal and where can it fly?'):\n");
    printf("     A6: %s\n", geomind_e8_answer_epistemic_question("Is a robin an animal and where can it fly?"));
    printf("  -> Q7 [Solid Geometry & Zero-G Fluid Physics ('sphere')] ('What is a sphere and how does liquid water form a sphere in zero gravity?'):\n");
    printf("     A7: %s\n", geomind_e8_answer_epistemic_question("What is a sphere and how does liquid water form a sphere in zero gravity?"));
    printf("  -> Q8 [Ball Affordance - Playing Catch] ('How do you play catch with a ball?'):\n");
    printf("     A8: %s\n", geomind_e8_answer_epistemic_question("How do you play catch with a ball?"));
    printf("  -> Q9 [Defeasible Flightless Bird - Penguin] ('Can a penguin fly or where can a penguin swim?'):\n");
    printf("     A9: %s\n", geomind_e8_answer_epistemic_question("Can a penguin fly or where can a penguin swim?"));
    printf("  -> Q10 [Defeasible Flightless Bird - Ostrich] ('Can an ostrich fly or where can an ostrich sprint?'):\n");
    printf("     A10: %s\n", geomind_e8_answer_epistemic_question("Can an ostrich fly or where can an ostrich sprint?"));
    printf("  -> Q11 [Defeasible Flightless Bird - Emu] ('Can an emu fly or where can an emu stride?'):\n");
    printf("     A11: %s\n", geomind_e8_answer_epistemic_question("Can an emu fly or where can an emu stride?"));
    printf("  -> Q12 [Defeasible Flightless Bird - Cassowary] ('Can a cassowary fly or where can a cassowary leap?'):\n");
    printf("     A12: %s\n", geomind_e8_answer_epistemic_question("Can a cassowary fly or where can a cassowary leap?"));
    printf("  -> Q13 [Rung 4a | Modern Narratives - Sci-Fi] ('Where did Commander Vane stood on Orbital Station Epsilon?'):\n");
    printf("     A13: %s\n", geomind_e8_answer_epistemic_question("Where did Commander Vane stood on Orbital Station Epsilon?"));
    printf("  -> Q14 [Rung 4a | Modern Narratives - Mystery] ('Where did Detective Julian Sterling arrive as twilight settled?'):\n");
    printf("     A14: %s\n", geomind_e8_answer_epistemic_question("Where did Detective Julian Sterling arrive as twilight settled?"));
    printf("  -> Q15 [Rung 4b | Alice in Wonderland] ('What did Alice opened and found along the passage?'):\n");
    printf("     A15: %s\n", geomind_e8_answer_epistemic_question("What did Alice opened and found along the passage?"));
    printf("  -> Q16 [Rung 4c | Anthem] ('Why did the Council of Vocations come to give us our life Mandates?'):\n");
    printf("     A16: %s\n", geomind_e8_answer_epistemic_question("Why did the Council of Vocations come to give us our life Mandates?"));
    printf("  -> Q17 [Rung 4d | Sherlock Holmes - Irene Adler] ('Who is always the woman to Sherlock Holmes?'):\n");
    printf("     A17: %s\n", geomind_e8_answer_epistemic_question("Who is always the woman to Sherlock Holmes?"));
    printf("  -> Q18 [Rung 4d | Sherlock Holmes - Mystery Note] ('How was the note undated without signature or address?'):\n");
    printf("     A18: %s\n", geomind_e8_answer_epistemic_question("How was the note undated without signature or address?"));
    printf("  -> Q19 [Rung 4c | Anthem - Underground Tunnel] ('How were the walls cracked in the dark tunnel?'):\n");
    printf("     A19: %s\n", geomind_e8_answer_epistemic_question("How were the walls cracked in the dark tunnel?"));
    printf("  -> Q20 [Rung 4b | Alice - Non-Initial Subject] ('How did Alice go like the wind when there was not a moment to be lost?'):\n");
    printf("     A20: %s\n", geomind_e8_answer_epistemic_question("How did Alice go like the wind when there was not a moment to be lost?"));
    printf("--------------------------------------------------------------------------------\n");
    printf("  STAGE 6.1 SUBTLE GEOMETRIC REASONING & FALSIFICATION SUITE (Zero Word Rules)\n");
    printf("--------------------------------------------------------------------------------\n");
    printf("  [Test 1 | Zero-Shot 42-Layer Trajectory Intersection ('What do X & Y share?')]:\n");
    printf("    * ('kitten',  'puppy')  -> %s\n", geomind_e8_trajectory_intersection_42L("kitten", "puppy"));
    printf("    * ('sparrow', 'puppy')  -> %s\n", geomind_e8_trajectory_intersection_42L("sparrow", "puppy"));
    printf("    * ('run',     'bounce') -> %s\n", geomind_e8_trajectory_intersection_42L("run", "bounce"));
    printf("    * ('sparrow', 'orb')    -> %s\n", geomind_e8_trajectory_intersection_42L("sparrow", "orb"));
    printf("  [Test 2 | Counterfactual & False-Premise Rejection + Adjoint R^T Attribution]:\n");
    printf("    * Claim('kitten',  'fly')    -> %s\n", geomind_e8_verify_counterfactual_42L("kitten", "fly"));
    printf("    * Claim('penguin', 'fly')    -> %s\n", geomind_e8_verify_counterfactual_42L("penguin", "fly"));
    printf("    * Claim('ostrich', 'fly')    -> %s\n", geomind_e8_verify_counterfactual_42L("ostrich", "fly"));
    printf("    * Claim('sparrow', 'dog')    -> %s\n", geomind_e8_verify_counterfactual_42L("sparrow", "dog"));
    printf("    * Claim('orb',     'ground') -> %s\n", geomind_e8_verify_counterfactual_42L("orb", "ground"));
    printf("  [Test 3 | Backward Abductive Diagnosis from Downstream Clues (Inverting L42->L0)]:\n");
    printf("    * %s\n", geomind_e8_abductive_diagnosis_42L("small", "fly", "sky"));
    printf("    * %s\n", geomind_e8_abductive_diagnosis_42L("round", "bounce", "ground"));
    printf("    * %s\n", geomind_e8_abductive_diagnosis_42L("young", "purrs", "happy"));
    printf("  [Test 4 | Unstated Multi-Sentence Cross-Rung Bridging (WordNet + Rung 1)]:\n");
    printf("    * Bridge 1 ('trout'):  %s\n", geomind_e8_cross_rung_bridge_42L("trout"));
    printf("    * Bridge 2 ('salmon'): %s\n", geomind_e8_cross_rung_bridge_42L("salmon"));
    printf("--------------------------------------------------------------------------------\n");
    printf("  STAGE 6.2 CO-ADAPTED S^247 MICROFEATURES & SHANNON DECORRELATION AUDIT\n");
    printf("--------------------------------------------------------------------------------\n");
    let mf_sparrow_robin = geomind_e8_microfeat_cosine_words("sparrow", "robin");
    let mf_trout_salmon  = geomind_e8_microfeat_cosine_words("trout", "salmon");
    let mf_orb_sphere    = geomind_e8_microfeat_cosine_words("orb", "sphere");
    let mf_run_play      = geomind_e8_microfeat_cosine_words("run", "play");
    let mf_kitten_puppy  = geomind_e8_microfeat_cosine_words("kitten", "puppy");
    let mf_sparrow_orb   = geomind_e8_microfeat_cosine_words("sparrow", "orb");
    printf("  [Layer-0 Co-Adapted S^247 Microfeature Cosine <\\tilde{P}_a, \\tilde{P}_b> / 248]:\n");
    printf("    * Sibling Birds   cos(sparrow, robin) = %.4f | Sibling Fish cos(trout, salmon) = %.4f\n", mf_sparrow_robin, mf_trout_salmon);
    printf("    * Sibling Spheres cos(orb, sphere)    = %.4f | Activities   cos(run, play)     = %.4f\n", mf_orb_sphere, mf_run_play);
    printf("    * Young Animals   cos(kitten, puppy)  = %.4f | Disjoint     cos(sparrow, orb)  = %.4f\n", mf_kitten_puppy, mf_sparrow_orb);
    cartan_flush(0.0);
    return 1.0;
}

