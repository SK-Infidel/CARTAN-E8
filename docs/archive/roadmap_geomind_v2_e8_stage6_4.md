# CARTAN-E8 (GeoMind v2) Stage 6.4 Walkthrough: Layer-0 Sibling Differentiation, Persistent Episodic Memory, & Langevin Geodesic Exploration

## Summary of Completed Milestones
1. **Layer-0 Sibling Concept Differentiation (`g_e8_traj_waypt3_str = w_prop`) & Multi-Path Rung 2 Concept Triples**:
   - Enriched [`Projects/geomind/trainingdata/e8_concept_triples.txt`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/trainingdata/e8_concept_triples.txt) with sibling-specific Layer-0 properties (`robin -> cheerful = 0.8116`, `sphere -> smooth = 0.8262`) alongside shared hypernym capabilities (`bird -> fly`, `ball -> bounce`).
   - Added a 3rd full-word multi-byte trajectory waypoint `g_e8_traj_waypt3_str = w_prop` in [`geomind_byte_latent_generate_deep_e8`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/byte_latent.cl#L4191-L4268) and [`geomind_e8_answer_epistemic_question`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/byte_latent.cl#L4528-L4587).
2. **Rebalanced 248-D E8 Readout (+80%), Persistent Cross-Turn Episodic Refractory Memory, & Langevin Geodesic Exploration**:
   - Increased the 248-D E8 manifold readout weight in [`geomind_byte_latent_decode_logits_blt`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/byte_latent.cl#L1079) from `0.25` to `0.45`.
   - Added a persistent 32-slot cross-call episodic refractory buffer (`g_e8_episodic_ref_w1`, `g_e8_episodic_ref_byte`) and Killing-Cartan kinetic-energy-driven Langevin exploration (`g_e8_langevin_phase`, `g_e8_langevin_temp = 0.28`) gated to competing word-boundary candidates (`lv >= max_raw_l - 1.8`).
3. **Empirical Verification (`task-3651`, Exit Code `0`)**:
   - `Q1 ('sparrow')` $\to$ `"A sparrow is a small bird with feathers and wings. A sparrow can fly high in the sky. [42L Waypoints: sparrow(small)->bird->animal | fly->sky]"`
   - `Q6 ('robin')` $\to$ `"A robin is a cheerful bird that sings sweet songs in the garden. A robin can fly high above the bramble bushes, searching for shiny berries and  [42L Waypoints: robin(cheerful)->bird->animal | fly->sky]"`
   - `Q4 ('orb')` $\to$ `"When you drop a orb, gravity pulls the ball down to the ground. You can bounce the orb on the ground. Bouncing a ball is fun. [42L Waypoints: orb(round)->ball->plaything | gravity->ground]"`
   - `Q7 ('sphere')` $\to$ `"When you drop a sphere, gravity pulls the ball down to the ground. A sphere is a smooth ball that rolls fast across the floor. [42L Waypoints: sphere(smooth)->ball->plaything | gravity->ground]"`
   - `Test 3 (Backward Abductive Diagnosis)`:
     - `Clues (small, fly, sky) -> Abduced Concept: 'sparrow' (L7 class: 'bird')`
     - `Clues (cheerful, fly, sky) -> Abduced Concept: 'robin' (L7 class: 'bird')`
     - `Clues (round, bounce, ground) -> Abduced Concept: 'orb' (L7 class: 'ball')`
     - `Clues (smooth, bounce, ground) -> Abduced Concept: 'sphere' (L7 class: 'ball')`
     - `Clues (young, purrs, happy) -> Abduced Concept: 'kitten' (L7 class: 'cat')`
