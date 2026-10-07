# tools/run_affected_tests.ps1
# CARTAN Agile Selective Regression Test Runner
# Restricts test execution strictly to targets affected by current sprint/code edits.

param (
    [string]$Target = "",
    [int]$Sprint = 0,
    [switch]$All,
    [switch]$Auto,
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"

# -----------------------------------------------------------------------------
# Target Catalog (All 88 Compiler Regression Suite Targets)
# -----------------------------------------------------------------------------
$TargetCatalog = @{
    1  = @{ Name = "test_primitives"; File = "Projects/geomind/Testing-scratch/test_primitives.car"; Run = $false; Negative = $false }
    2  = @{ Name = "test_enums"; File = "Projects/geomind/Testing-scratch/test_enums.car"; Run = $false; Negative = $false }
    3  = @{ Name = "test_modules"; File = "Projects/geomind/Testing-scratch/test_modules.car"; Run = $false; Negative = $false }
    4  = @{ Name = "test_fail_syntax"; File = "Projects/geomind/Testing-scratch/test_fail_syntax.car"; Run = $false; Negative = $true }
    5  = @{ Name = "test_slices_tuples"; File = "Projects/geomind/Testing-scratch/test_slices_tuples.car"; Run = $false; Negative = $false }
    6  = @{ Name = "test_dlpack_slicing"; File = "Projects/geomind/Testing-scratch/test_dlpack_slicing.car"; Run = $false; Negative = $false }
    7  = @{ Name = "test_security_sandboxing"; File = "Projects/geomind/Testing-scratch/test_security_sandboxing.car"; Run = $false; Negative = $false }
    8  = @{ Name = "test_static_assert"; File = "Projects/geomind/Testing-scratch/test_static_assert.car"; Run = $false; Negative = $false }
    9  = @{ Name = "test_comptime_autograd"; File = "Projects/geomind/Testing-scratch/test_comptime_autograd.car"; Run = $false; Negative = $false }
    10 = @{ Name = "test_stdlib"; File = "Projects/geomind/Testing-scratch/test_stdlib.car"; Run = $false; Negative = $false }
    11 = @{ Name = "test_variadic_ret"; File = "Projects/geomind/Testing-scratch/test_variadic_ret.car"; Run = $false; Negative = $false }
    12 = @{ Name = "test_tensor_opt"; File = "Projects/geomind/Testing-scratch/test_tensor_opt.car"; Run = $false; Negative = $false }
    13 = @{ Name = "test_optimizer"; File = "Projects/geomind/Testing-scratch/test_optimizer.car"; Run = $false; Negative = $false }
    14 = @{ Name = "test_std_abstraction"; File = "Projects/geomind/Testing-scratch/test_std_abstraction.car"; Run = $false; Negative = $false }
    15 = @{ Name = "test_net_abstraction"; File = "Projects/geomind/Testing-scratch/test_net_abstraction.car"; Run = $false; Negative = $false }
    16 = @{ Name = "test_jit_engine"; File = "Projects/geomind/Testing-scratch/test_jit_engine.car"; Run = $false; Negative = $false }
    17 = @{ Name = "test_generics"; File = "Projects/geomind/Testing-scratch/test_generics.car"; Run = $false; Negative = $false }
    18 = @{ Name = "test_async_coroutines"; File = "Projects/geomind/Testing-scratch/test_async_coroutines.car"; Run = $true; Negative = $false }
    19 = @{ Name = "test_package_manager"; File = "Projects/geomind/Testing-scratch/test_package_manager.car"; Run = $false; Negative = $false }
    20 = @{ Name = "test_http_xml"; File = "Projects/geomind/Testing-scratch/test_http_xml.car"; Run = $false; Negative = $false }
    21 = @{ Name = "test_physics_math"; File = "Projects/geomind/Testing-scratch/test_physics_math.car"; Run = $false; Negative = $false }
    22 = @{ Name = "test_math_string_full"; File = "Projects/geomind/Testing-scratch/test_math_string_full.car"; Run = $false; Negative = $false }
    23 = @{ Name = "test_physics_geom_advanced"; File = "Projects/geomind/Testing-scratch/test_physics_geom_advanced.car"; Run = $false; Negative = $false }
    24 = @{ Name = "test_tokenizer"; File = "Projects/geomind/Testing-scratch/test_tokenizer.car"; Run = $false; Negative = $false }
    25 = @{ Name = "test_collections_ingest_env"; File = "Projects/geomind/Testing-scratch/test_collections_ingest_env.car"; Run = $false; Negative = $false }
    26 = @{ Name = "test_framework_layer2"; File = "Projects/geomind/Testing-scratch/test_framework_layer2.car"; Run = $false; Negative = $false }
    27 = @{ Name = "test_repl"; File = "Projects/geomind/Testing-scratch/test_repl.car"; Run = $false; Negative = $false }
    28 = @{ Name = "test_bindgen"; File = "Projects/geomind/Testing-scratch/test_bindgen.car"; Run = $false; Negative = $false }
    29 = @{ Name = "test_lsp"; File = "Projects/geomind/Testing-scratch/test_lsp.car"; Run = $false; Negative = $false }
    30 = @{ Name = "test_doc"; File = "Projects/geomind/Testing-scratch/test_doc.car"; Run = $false; Negative = $false }
    31 = @{ Name = "test_llvm_opt_pipeline"; File = "Projects/geomind/Testing-scratch/test_llvm_opt_pipeline.car"; Run = $false; Negative = $false }
    32 = @{ Name = "test_dist_parallelism"; File = "Projects/geomind/Testing-scratch/test_dist_parallelism.car"; Run = $false; Negative = $false }
    33 = @{ Name = "test_hf_hub"; File = "Projects/geomind/Testing-scratch/test_hf_hub.car"; Run = $false; Negative = $false }
    34 = @{ Name = "test_vision"; File = "Projects/geomind/Testing-scratch/test_vision.car"; Run = $false; Negative = $false }
    35 = @{ Name = "test_autotune"; File = "Projects/geomind/Testing-scratch/test_autotune.car"; Run = $false; Negative = $false }
    36 = @{ Name = "test_fusion_distill"; File = "Projects/geomind/Testing-scratch/test_fusion_distill.car"; Run = $false; Negative = $false }
    37 = @{ Name = "test_merge_model_weights"; File = "Projects/geomind/Testing-scratch/test_merge_model_weights.car"; Run = $false; Negative = $false }
    38 = @{ Name = "test_semantics_ic"; File = "Projects/geomind/Testing-scratch/test_semantics_ic.car"; Run = $false; Negative = $false }
    39 = @{ Name = "test_novel_ai_libs"; File = "Projects/geomind/Testing-scratch/test_novel_ai_libs.car"; Run = $false; Negative = $false }
    40 = @{ Name = "test_es_opt"; File = "Projects/geomind/Testing-scratch/test_es_opt.car"; Run = $false; Negative = $false }
    41 = @{ Name = "test_evolution_master"; File = "Projects/geomind/Testing-scratch/test_evolution_master.car"; Run = $false; Negative = $false }
    42 = @{ Name = "test_xml_ingest_pipeline"; File = "Projects/geomind/Testing-scratch/test_xml_ingest_pipeline.car"; Run = $false; Negative = $false }
    43 = @{ Name = "test_inductive_biases"; File = "Projects/geomind/Testing-scratch/test_inductive_biases.car"; Run = $false; Negative = $false }
    44 = @{ Name = "test_net_and_logger"; File = "Projects/geomind/Testing-scratch/test_net_and_logger.car"; Run = $false; Negative = $false }
    45 = @{ Name = "test_hopfield_buffer"; File = "Projects/geomind/Testing-scratch/test_hopfield_buffer.car"; Run = $false; Negative = $false }
    46 = @{ Name = "test_lie_streams"; File = "Projects/geomind/Testing-scratch/test_lie_streams.car"; Run = $true; Negative = $false }
    47 = @{ Name = "test_hebbian_plasticity"; File = "Projects/geomind/Testing-scratch/test_hebbian_plasticity.car"; Run = $false; Negative = $false }
    48 = @{ Name = "test_multimodal_grounding"; File = "Projects/geomind/Testing-scratch/test_multimodal_grounding.car"; Run = $false; Negative = $false }
    49 = @{ Name = "test_sleep_consolidation"; File = "Projects/geomind/Testing-scratch/test_sleep_consolidation.car"; Run = $false; Negative = $false }
    50 = @{ Name = "test_language_acquisition_cloze"; File = "Projects/geomind/Testing-scratch/test_language_acquisition_cloze.car"; Run = $false; Negative = $false }
    51 = @{ Name = "test_model_grafting"; File = "Projects/geomind/Testing-scratch/test_model_grafting.car"; Run = $false; Negative = $false }
    52 = @{ Name = "test_native_multimodal_io"; File = "Projects/geomind/Testing-scratch/test_native_multimodal_io.car"; Run = $false; Negative = $false }
    53 = @{ Name = "test_sasaki_brainstem_routing"; File = "Projects/geomind/Testing-scratch/test_sasaki_brainstem_routing.car"; Run = $true; Negative = $false }
    54 = @{ Name = "test_continuous_hopfield_recall"; File = "Projects/geomind/Testing-scratch/test_continuous_hopfield_recall.car"; Run = $true; Negative = $false }
    55 = @{ Name = "test_wordnet_taxonomy_dag"; File = "Projects/geomind/Testing-scratch/test_wordnet_taxonomy_dag.car"; Run = $false; Negative = $false }
    56 = @{ Name = "test_doubt_reflective_rewind"; File = "Projects/geomind/Testing-scratch/test_doubt_reflective_rewind.car"; Run = $false; Negative = $false }
    57 = @{ Name = "test_markov_conscious_agent"; File = "Projects/geomind/Testing-scratch/test_markov_conscious_agent.car"; Run = $false; Negative = $false }
    58 = @{ Name = "test_hybrid_resonant_transformer"; File = "Projects/geomind/Testing-scratch/test_hybrid_resonant_transformer.car"; Run = $true; Negative = $false }
    59 = @{ Name = "test_finsler_randers"; File = "Projects/geomind/Testing-scratch/test_finsler_randers.car"; Run = $false; Negative = $false }
    60 = @{ Name = "test_core_builtins"; File = "Projects/geomind/Testing-scratch/test_core_builtins.car"; Run = $false; Negative = $false }
    61 = @{ Name = "test_language_primitives"; File = "Projects/geomind/Testing-scratch/test_language_primitives.car"; Run = $false; Negative = $false }
    62 = @{ Name = "test_transforms_and_logic"; File = "Projects/geomind/Testing-scratch/test_transforms_and_logic.car"; Run = $false; Negative = $false }
    63 = @{ Name = "test_loops_and_primitives"; File = "Projects/geomind/Testing-scratch/test_loops_and_primitives.car"; Run = $false; Negative = $false }
    64 = @{ Name = "test_geometric_and_search_primitives"; File = "Projects/geomind/Testing-scratch/test_geometric_and_search_primitives.car"; Run = $false; Negative = $false }
    65 = @{ Name = "test_tensor_and_pointer_ops"; File = "Projects/geomind/Testing-scratch/test_tensor_and_pointer_ops.car"; Run = $false; Negative = $false }
    66 = @{ Name = "test_geometric_bridge_and_reflection"; File = "Projects/geomind/Testing-scratch/test_geometric_bridge_and_reflection.car"; Run = $false; Negative = $false }
    67 = @{ Name = "test_attention_fused_methods"; File = "Projects/geomind/Testing-scratch/test_attention_fused_methods.car"; Run = $false; Negative = $false }
    68 = @{ Name = "test_async_spawn_evolve"; File = "Projects/geomind/Testing-scratch/test_async_spawn_evolve.car"; Run = $false; Negative = $false }
    69 = @{ Name = "test_neuro_symbolic_jit"; File = "Projects/geomind/Testing-scratch/test_neuro_symbolic_jit.car"; Run = $false; Negative = $false }
    70 = @{ Name = "test_impl_trait_methods"; File = "Projects/geomind/Testing-scratch/test_impl_trait_methods.car"; Run = $false; Negative = $false }
    71 = @{ Name = "test_nses_language_domain"; File = "Projects/geomind/Testing-scratch/test_nses_language_domain.car"; Run = $true; Negative = $false }
    72 = @{ Name = "test_ns_rule_generator"; File = "Projects/geomind/Testing-scratch/test_ns_rule_generator.car"; Run = $true; Negative = $false }
    73 = @{ Name = "test_bulk_corpus_ingestion"; File = "Projects/geomind/Testing-scratch/test_bulk_corpus_ingestion.car"; Run = $true; Negative = $false }
    74 = @{ Name = "test_chat_train_nses_forward_integration"; File = "Projects/geomind/Testing-scratch/test_chat_train_nses_forward_integration.car"; Run = $true; Negative = $false }
    75 = @{ Name = "test_nses_logic_domain"; File = "Projects/geomind/Testing-scratch/test_nses_logic_domain.car"; Run = $true; Negative = $false }
    76 = @{ Name = "test_nses_decision_domain"; File = "Projects/geomind/Testing-scratch/test_nses_decision_domain.car"; Run = $true; Negative = $false }
    77 = @{ Name = "test_universal_domain_lexicon"; File = "Projects/geomind/Testing-scratch/test_universal_domain_lexicon.car"; Run = $true; Negative = $false }
    78 = @{ Name = "test_nses_epistemology_domain"; File = "Projects/geomind/Testing-scratch/test_nses_epistemology_domain.car"; Run = $true; Negative = $false }
    79 = @{ Name = "test_nses_compiler_domain"; File = "Projects/geomind/Testing-scratch/test_nses_compiler_domain.car"; Run = $true; Negative = $false }
    80 = @{ Name = "test_nses_universal_cognitive_domains"; File = "Projects/geomind/Testing-scratch/test_nses_universal_cognitive_domains.car"; Run = $true; Negative = $false }
    81 = @{ Name = "test_nses_software_engineering_domain"; File = "Projects/geomind/Testing-scratch/test_nses_software_engineering_domain.car"; Run = $true; Negative = $false }
    82 = @{ Name = "test_compiler_simd_tensor_math"; File = "Projects/geomind/Testing-scratch/test_compiler_simd_tensor_math.car"; Run = $true; Negative = $false }
    83 = @{ Name = "test_manifold_layer_alignment"; File = "Projects/geomind/Testing-scratch/test_manifold_layer_alignment.car"; Run = $true; Negative = $false }
    84 = @{ Name = "test_manifold_full_model_execution"; File = "Projects/geomind/Testing-scratch/test_manifold_full_model_execution.car"; Run = $true; Negative = $false }
    85 = @{ Name = "test_model_config_decoupling"; File = "Projects/geomind/Testing-scratch/test_model_config_decoupling.car"; Run = $true; Negative = $false }
    86 = @{ Name = "test_manifold_layer_streaming_pipeline"; File = "Projects/geomind/Testing-scratch/test_manifold_layer_streaming_pipeline.car"; Run = $true; Negative = $false }
    87 = @{ Name = "test_ns_gradient_supervision"; File = "Projects/geomind/Testing-scratch/test_ns_gradient_supervision.car"; Run = $true; Negative = $false }
    88 = @{ Name = "test_autodiff_backward_syntax"; File = "Projects/geomind/Testing-scratch/test_autodiff_backward_syntax.car"; Run = $true; Negative = $false }
    89 = @{ Name = "test_stdlib_string_terminal_html"; File = "Projects/geomind/Testing-scratch/test_stdlib_string_terminal_html.car"; Run = $true; Negative = $false }
    90 = @{ Name = "test_stdlib_json_process_xml"; File = "Projects/geomind/Testing-scratch/test_stdlib_json_process_xml.car"; Run = $true; Negative = $false }
    91 = @{ Name = "test_stdlib_algebra_tensor"; File = "Projects/geomind/Testing-scratch/test_stdlib_algebra_tensor.car"; Run = $true; Negative = $false }
    92 = @{ Name = "test_stdlib_algebra_geometric"; File = "Projects/geomind/Testing-scratch/test_stdlib_algebra_geometric.car"; Run = $true; Negative = $false }
    93 = @{ Name = "test_stdlib_algebra_lie"; File = "Projects/geomind/Testing-scratch/test_stdlib_algebra_lie.car"; Run = $true; Negative = $false }
    94 = @{ Name = "test_stdlib_algebra_abstract"; File = "Projects/geomind/Testing-scratch/test_stdlib_algebra_abstract.car"; Run = $true; Negative = $false }
}

# -----------------------------------------------------------------------------
# Sprint Preset Mapping
# -----------------------------------------------------------------------------
$SprintMapping = @{
    550 = @(1, 2, 3, 4, 5, 10, 18, 20, 24, 82, 89, 90)
    549 = @(1, 2, 3, 4, 5, 10, 18, 20, 24, 82, 89, 90)
    548 = @(1, 2, 3, 4, 5, 10, 18, 20, 24, 82, 89, 90)
    547 = @(1, 2, 3, 4, 5, 10, 18, 20, 24, 82, 89, 90, 91, 92, 93, 94)
    546 = @(1, 2, 3, 4, 5, 10, 18, 20, 24, 82, 89, 90, 91, 92, 93)
    545 = @(1, 2, 3, 4, 5, 10, 18, 20, 24, 82, 89, 90, 91, 92)
    544 = @(1, 2, 3, 4, 5, 10, 18, 20, 24, 82, 89, 90, 91)
    543 = @(1, 2, 3, 4, 5, 10, 18, 20, 24, 82, 89, 90)
    542 = @(1, 2, 3, 4, 5, 18, 24, 82, 89)
    541 = @(1, 2, 3, 4, 5, 18, 24, 31, 33, 34, 36, 37, 45, 46, 53, 54, 58, 74, 80, 82, 83, 84, 85, 86)
    540 = @(1, 2, 3, 4, 5, 18, 24, 33, 34, 36, 37, 45, 46, 53, 54, 58, 74, 80, 82, 83, 84, 85, 86)
    539 = @(1, 2, 3, 4, 5, 18, 24, 33, 34, 36, 37, 45, 46, 53, 54, 58, 74, 80, 82, 83, 84, 85, 86)
    538 = @(1, 2, 3, 4, 5, 18, 24, 33, 34, 36, 37, 45, 46, 53, 54, 58, 74, 80, 82, 83, 84, 85, 86)
    537 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 74, 80, 82, 83, 84, 85, 86)
    536 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    535 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    534 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    533 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    532 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    531 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    530 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    529 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    528 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    527 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    526 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    525 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    524 = @(1, 2, 3, 4, 5, 18, 45, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    523 = @(1, 2, 3, 4, 5, 18, 46, 53, 54, 58, 82, 83, 84, 85, 86)
    522 = @(1, 2, 3, 4, 5, 18, 82, 83, 84, 85, 86)
    521 = @(1, 2, 3, 4, 5, 82, 83, 84, 85, 86)
    520 = @(45, 54, 58, 83, 84, 85, 86)
    519 = @(1, 2, 3, 4, 5, 82, 86)
    518 = @(1, 2, 3, 4, 5, 23, 46, 59, 82, 83, 84, 85, 86, 87)
    513 = @(58, 83, 84, 85, 86)
    512 = @(58, 83, 84, 85, 86)
    508 = @(82, 83, 84, 86)
    488 = @(18, 66, 68, 88)
    484 = @(1, 23, 71, 74, 82, 83, 84, 85, 86, 87)
    483 = @(83, 84, 85, 86, 87)
    481 = @(47, 49, 54, 58, 84, 86, 87)
    480 = @(58, 83, 84, 86)
    479 = @(64, 66, 82, 84, 85)
    478 = @(71, 74, 84, 86, 87)
    477 = @(83, 84, 85, 86)
    476 = @(83, 84, 86)
    475 = @(47, 59, 85)
    474 = @(83, 84)
    473 = @(33, 51, 83)
}

# -----------------------------------------------------------------------------
# Resolve Selected Targets
# -----------------------------------------------------------------------------
$SelectedTargetIDs = [System.Collections.Generic.List[int]]::new()

if ($All) {
    $TargetCatalog.Keys | Sort-Object | ForEach-Object { $SelectedTargetIDs.Add($_) }
}
elseif ($Sprint -gt 0) {
    if ($SprintMapping.ContainsKey($Sprint)) {
        $SprintMapping[$Sprint] | ForEach-Object { $SelectedTargetIDs.Add($_) }
    } else {
        # Default to latest layer/model targets for recent sprints
        @(83, 84, 85, 86) | ForEach-Object { $SelectedTargetIDs.Add($_) }
    }
}
elseif ($Target -ne "") {
    $tokens = $Target -split "[, ]+"
    foreach ($tok in $tokens) {
        if ($tok -match '^\d+$') {
            $id = [int]$tok
            if ($TargetCatalog.ContainsKey($id)) {
                $SelectedTargetIDs.Add($id)
            }
        } else {
            # Search by keyword in name
            foreach ($entry in $TargetCatalog.GetEnumerator()) {
                if ($entry.Value.Name -like "*$tok*") {
                    if (-not $SelectedTargetIDs.Contains($entry.Key)) {
                        $SelectedTargetIDs.Add($entry.Key)
                    }
                }
            }
        }
    }
}
else {
    # Default: Automatic detection based on modified files (git status)
    $modifiedFiles = git diff --name-only HEAD 2>$null
    if (-not $modifiedFiles) {
        $modifiedFiles = git status --short 2>$null | ForEach-Object { ($_ -split '\s+')[-1] }
    }

    $hasTransformerOrChat = $false
    $hasTokenizer = $false
    $hasHebbian = $false
    $hasGeom = $false
    $hasCompilerCore = $false
    $hasHopfield = $false

    foreach ($file in $modifiedFiles) {
        if ($file -match 'Projects/geomind/Testing-scratch/test_(\w+)\.car') {
            # Direct edit to a test file
            foreach ($entry in $TargetCatalog.GetEnumerator()) {
                if ($entry.Value.File -eq $file) {
                    if (-not $SelectedTargetIDs.Contains($entry.Key)) {
                        $SelectedTargetIDs.Add($entry.Key)
                    }
                }
            }
        }
        if ($file -match 'wgpu|gpu|transformer|hub|chat|cartan_native_io|manifold|critic|train') { $hasTransformerOrChat = $true }
        if ($file -match 'tokenizer') { $hasTokenizer = $true }
        if ($file -match 'hebbian') { $hasHebbian = $true }
        if ($file -match 'geom|manifold|lie') { $hasGeom = $true }
        if ($file -match 'nses|veto|critic') { $hasNSES = $true }
        if ($file -match 'resonator|hopfield') { $hasHopfield = $true }
        if ($file -match 'algebra') { $hasAlgebra = $true }
        if ($file -match 'src/cartanc/') { $hasCompilerCore = $true }
    }

    if ($hasAlgebra) {
        @(91, 92, 93, 94) | ForEach-Object { if (-not $SelectedTargetIDs.Contains($_)) { $SelectedTargetIDs.Add($_) } }
    }
    if ($hasTransformerOrChat) {
        @(83, 84, 85, 86, 87) | ForEach-Object { if (-not $SelectedTargetIDs.Contains($_)) { $SelectedTargetIDs.Add($_) } }
    }
    if ($hasHopfield) {
        @(45, 54, 58) | ForEach-Object { if (-not $SelectedTargetIDs.Contains($_)) { $SelectedTargetIDs.Add($_) } }
    }
    if ($hasNSES) {
        @(71, 74, 87) | ForEach-Object { if (-not $SelectedTargetIDs.Contains($_)) { $SelectedTargetIDs.Add($_) } }
    }
    if ($hasTokenizer) {
        @(24, 86) | ForEach-Object { if (-not $SelectedTargetIDs.Contains($_)) { $SelectedTargetIDs.Add($_) } }
    }
    if ($hasHebbian) {
        @(47, 85) | ForEach-Object { if (-not $SelectedTargetIDs.Contains($_)) { $SelectedTargetIDs.Add($_) } }
    }
    if ($hasGeom) {
        @(23, 46, 59, 85) | ForEach-Object { if (-not $SelectedTargetIDs.Contains($_)) { $SelectedTargetIDs.Add($_) } }
    }
    if ($hasCompilerCore) {
        @(1, 2, 3, 4, 5, 82, 86) | ForEach-Object { if (-not $SelectedTargetIDs.Contains($_)) { $SelectedTargetIDs.Add($_) } }
    }

    # If no specific files detected, default to current sprint targets
    if ($SelectedTargetIDs.Count -eq 0) {
        @(84, 86, 87) | ForEach-Object { $SelectedTargetIDs.Add($_) }
    }
}

# Sort target IDs
$SortedIDs = $SelectedTargetIDs | Sort-Object

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  CARTAN Selective Regression Test Runner" -ForegroundColor Cyan
Write-Host "  Executing $($SortedIDs.Count) affected target(s): ($($SortedIDs -join ', '))" -ForegroundColor Cyan
Write-Host "================================================================================`n" -ForegroundColor Cyan

$FailedTargets = [System.Collections.Generic.List[string]]::new()
$PassedTargets = [System.Collections.Generic.List[string]]::new()
$TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($id in $SortedIDs) {
    $info = $TargetCatalog[$id]
    $name = $info.Name
    $file = $info.File
    $isNeg = $info.Negative
    $outExe = "build/$name.exe"

    Write-Host "[$id/$($TargetCatalog.Count)] Target: $name ($file)" -ForegroundColor Yellow
    $buildCmd = ".\cartanc.exe build $file -o $outExe"
    
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $buildRes = Invoke-Expression $buildCmd
    $buildCode = $LASTEXITCODE
    
    if ($isNeg) {
        if ($buildCode -eq 0) {
            Write-Host "  -> [FAILED] Negative test $name unexpectedly compiled with exit code 0!" -ForegroundColor Red
            $FailedTargets.Add("Target $id ($name)")
            continue
        } else {
            Write-Host "  -> [PASS] Compile-fail assertion confirmed ($($sw.ElapsedMilliseconds) ms)" -ForegroundColor Green
            $PassedTargets.Add("Target $id ($name)")
            continue
        }
    }

    if ($buildCode -ne 0) {
        Write-Host "  -> [FAILED] Compilation failed with status $buildCode" -ForegroundColor Red
        $FailedTargets.Add("Target $id ($name)")
        continue
    }

    # If run-pass, execute the binary
    if ($info.Run) {
        $runCmd = ".\$outExe"
        $runRes = Invoke-Expression $runCmd
        $runCode = $LASTEXITCODE
        $sw.Stop()
        if ($runCode -ne 0) {
            Write-Host "  -> [FAILED] Runtime execution failed with status $runCode" -ForegroundColor Red
            $FailedTargets.Add("Target $id ($name)")
            continue
        }
        Write-Host "  -> [PASS] Build & Runtime passed ($($sw.ElapsedMilliseconds) ms)" -ForegroundColor Green
        $PassedTargets.Add("Target $id ($name)")
    } else {
        $sw.Stop()
        Write-Host "  -> [PASS] Compilation passed ($($sw.ElapsedMilliseconds) ms)" -ForegroundColor Green
        $PassedTargets.Add("Target $id ($name)")
    }
}

$TotalStopwatch.Stop()
Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  REGRESSION RUN SUMMARY: $($PassedTargets.Count) Passed, $($FailedTargets.Count) Failed ($([math]::Round($TotalStopwatch.Elapsed.TotalSeconds, 2))s total)" -ForegroundColor $(if ($FailedTargets.Count -eq 0) { "Green" } else { "Red" })
Write-Host "================================================================================" -ForegroundColor Cyan

if ($FailedTargets.Count -gt 0) {
    Write-Host "Failed targets:" -ForegroundColor Red
    foreach ($f in $FailedTargets) {
        Write-Host "  - $f" -ForegroundColor Red
    }
    exit 1
}

exit 0
