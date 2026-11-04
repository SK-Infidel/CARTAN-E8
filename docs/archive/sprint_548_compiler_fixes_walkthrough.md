# Sprint 548 Walkthrough: Compiler Core Fixes ([ISSUE-406], [ISSUE-407], [ISSUE-408])

## Summary
Resolved all three compiler issues identified during the startup code review (`[ISSUE-406]`, `[ISSUE-407]`, `[ISSUE-408]`), verified 3-stage self-hosting fixpoint convergence (`Stage 2 == Stage 3`), and validated the regression test suite.

## Completed Changes

### 1. `[ISSUE-406]` AST Optimizer Constant Folding & Statement Traversal ([`src/cartanc/optimizer.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/optimizer.car), [`src/cartanc/llvm_codegen.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/llvm_codegen.car))
- Updated [`optimize_expr`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/optimizer.car#L6-L176) to match canonical `ast.ch` 0-indexed discriminants: `StructInit` (`14.0`), `UnaryOp` (`15.0`), `BinaryOp` (`16.0`), `FunctionCall` (`17.0`), `MethodCall` (`18.0`), `PropertyAccess` (`20.0`), `IndexAccess` (`21.0`), `Assignment` (`22.0`), `BroadcastOp` (`23.0`), and `ArrayDecl` (`24.0`).
- Replaced `cartan_tree_get_f32` on literal values with direct 64-bit IEEE 754 `double` slot indexing (`left[1]`, `right[1]`), preserving fractional float precision (`0.25 + 0.5 == 0.75`) and `Expr::Integer` vs `Expr::Float` variants during constant folding, plus identity folding (`x + 0.0`, `x - 0.0`, `x * 1.0`, `x / 1.0`, `0.0 + x`, `1.0 * x`).
- Implemented [`optimize_block`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/optimizer.car#L178-L190) and [`optimize_stmt`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/optimizer.car#L192-L283) traversing all statement nodes and wired them into [`optimize_ast`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/optimizer.car#L285-L297).
- Updated `TensorDecl`, `VectorDecl`, and `ParameterDecl` in [`src/cartanc/llvm_codegen.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/llvm_codegen.car#L1849-L2043) to read folded dimension slots via `dim[1]` and format allocation sizes via `cartan_float_to_string`.

### 2. `[ISSUE-407]` Native CLI Flag Loop, TOML Package Manager, REPL & Dynamic LSP Server ([`src/cartanc/main.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car))
- Implemented [`toml_trim_quotes`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L207-L234), [`toml_extract_package_field`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L236-L296), and [`toml_format_dependencies_lock`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L298-L370) for `cartanc pkg`, parsing `[package]` (`name`, `version`) and `[dependencies]` from `cartan.toml` into `cartan.lock`.
- Implemented [`lsp_analyze_file`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L372-L395), [`lsp_format_hover_json`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L397-L448), and [`lsp_format_completion_json`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L450-L497) for `cartanc lsp`, serving live symbol counts and completion items from `TypeChecker`.
- Wired `ast_expansion_pass` and `typechecker_check` into `cartanc repl`.
- Implemented a full `2.0 .. argc` flag loop in `cartanc build` supporting `-o <file>`, `-I <dir>` (via [`ast_expansion_pass_with_dirs`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L49-L201)), `-L <dir>`, `-l<lib>`, `--release`/`-O3`, `-O2`, `-O0`, `-c`/`--emit-llvm`, and `-v`/`--verbose`.

### 3. `[ISSUE-408]` TypeChecker Discriminant Alignment & Typed Parameter Resolution ([`src/cartanc/type_checker.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/type_checker.car))
- Removed `disc == 7.0` (`ParameterDecl`) and `disc == 8.0` (`VectorDecl`) from function registration in [`typechecker_check`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/type_checker.car#L97-L133) and unshadowed `FunctionDecl` (`14.0`) in [`tc_visit_stmt`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/type_checker.car#L254-L280).
- Resolved function parameter type annotations via `parse_type_annotation(self_ptr, p_type_str)` instead of hardcoding `CartanType::Float`, enabling struct field access on typed function parameters.

## Verification
- **Self-Hosting Fixpoint**: Stage 2 (`scratch/cartanc_stage2.ll`) and Stage 3 (`scratch/cartanc_stage3.ll`) converged to bit-for-bit identical LLVM IR (`SHA256: AFF8C8CDA4769CB1019BE34586704FAA162DF47703A2DC2B8F0DA8F22D34BFC7`, 60,109 IR lines). Installed to `cartanc.exe` and `bin/cartanc.exe`.
- **Target 95 Regression Test** ([`Projects/geomind/Testing-scratch/test_compiler_issues_406_407_408.car`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/Testing-scratch/test_compiler_issues_406_407_408.car)): Passed (`acc: 6.00`, `res: 15.75`, `PASS: ISSUE-406 & ISSUE-408 VERIFIED`).
- **CLI / Package Manager / LSP Verification**: Confirmed `cartanc pkg` parses `[package]` and `[[dependencies]]` into `cartan.lock`, `cartanc lsp` returns live `TypeChecker` hover and completion items (`compute_scaled`, `LayerConfig`, etc.), and `cartanc build -c` emits LLVM IR without linking.
- **Compiler Regression Suite**: `tools/run_affected_tests.ps1` passed all affected targets with 0 failures.
