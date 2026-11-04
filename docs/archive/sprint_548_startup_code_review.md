# Startup Code Review & Logical Dependency Tree

## 1. Logical Dependency Tree

```mermaid
flowchart TD
    subgraph Compiler["Self-Hosted Compiler (src/cartanc/ -> cartanc.exe)"]
        RT["core_runtime.car\n(Freestanding runtime primitives, trees, vectors, mmap, JIT)"]
        AST["ast.ch & types.ch\n(TokenType, Expr, Stmt, CartanType)"]
        LEX["lexer.car\n(Source -> Token stream)"]
        PAR["parser.car\n(Token stream -> AST)"]
        TC["type_checker.car\n(Static symbol & shape verification)"]
        OPT["optimizer.car\n(AST constant folding pass)"]
        CG["llvm_codegen.car & wgsl_codegen.car\n(LLVM IR + AVX2 SIMD & WGSL emission)"]
        MAIN["main.car\n(CLI driver, ast_expansion_pass, Clang/LLD linker)"]
    end

    subgraph StdLib["CARTAN Standard Library (src/std/)"]
        CORE_STD["math.cl, string.cl, memory.cl, io.cl, fs.cl, terminal.cl, process.cl"]
        DATA_STD["collections.cl, json.cl, xml.cl, html.cl, sqlite_vec.cl"]
        ALG_STD["algebra.cl\n(Pillar 1: tensor.cl, Pillar 2: geometric.cl,\nPillar 3: lie.cl, Pillar 4: abstract.cl)"]
        AI_STD["tensor.cl, wgpu.cl, transformer.cl, tokenizer.cl, autotune.cl"]
        COG_STD["cargraph.cl, nses_pipeline.cl, veto_gate.cl, resonator.cl,\nhebbian.cl, sleep.cl, prompt_scaffold.cl"]
    end

    subgraph GeoMind["Verification Model (Projects/geomind/ -> bin/geomind.exe)"]
        GM_MAIN["main.car\n(CLI & Interactive REPL)"]
        GM_CHAT["chat.cl\n(42-Layer INT4 Manifold, Sasaki MoE, Tangent Debias, Agentic Tools)"]
        GM_TRAIN["train.cl, sft_train.cl, cloze_engine.cl, azr_engine.cl, sleep.car"]
        GM_SUITE["Projects/geomind/Testing-scratch/\n(94 Compiler & StdLib Regression Targets)"]
    end

    RT --> AST --> LEX --> PAR --> TC --> OPT --> CG --> MAIN
    RT --> CORE_STD --> DATA_STD
    CORE_STD --> ALG_STD
    CORE_STD --> AI_STD --> COG_STD
    AI_STD --> GM_CHAT
    COG_STD --> GM_CHAT
    DATA_STD --> GM_CHAT
    GM_CHAT --> GM_MAIN
    GM_TRAIN --> GM_MAIN
```

---

## 2. Where We Left Off (Recent Context)

- **CARTAN Core & Standard Library (Sprints 540–547, v8.521)**:
  - **Workspace & Log Decoupling**: Separated model logs into [`Projects/geomind/CHANGELOG.md`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/CHANGELOG.md) and [`Projects/geomind/ISSUES.md`](file:///C:/Users/rich-/source/repos/CARTAN/Projects/geomind/ISSUES.md); moved `test/` to `Projects/`.
  - **StdLib Promotions**: Promoted O(N) string utilities ([`src/std/string.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/string.cl)), ANSI terminal/keyboard polling ([`src/std/terminal.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/terminal.cl)), HTML/URL parser ([`src/std/html.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/html.cl)), JSON engine ([`src/std/json.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/json.cl)), sandboxed process runner ([`src/std/process.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/process.cl)), and XML extractors ([`src/std/xml.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/xml.cl)).
  - **Unified 4-Pillar Algebraic Taxonomy ([`src/std/algebra.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/algebra.cl))**: Completed all 4 pillars:
    1. [`src/std/algebra/tensor.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/algebra/tensor.cl): Strided N-D tensors, Einsum, LU, Gauss-Jordan inverse, Householder QR, Jacobi eigensolver, Padé matrix exponential, Sylvester signature.
    2. [`src/std/algebra/geometric.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/algebra/geometric.cl): Clifford $Cl(p,q,r)$ multivectors, rotors, Cayley-Dickson ($\mathbb{C}, \mathbb{D}, \mathbb{H}, \mathbb{O}$), Weyl differential algebra $W_n$.
    3. [`src/std/algebra/lie.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/algebra/lie.cl): Structure constants, Jacobi verifier, Killing form, Cartan semisimplicity, BCH series, Pre-Lie, Lie superalgebras, Poisson brackets.
    4. [`src/std/algebra/abstract.cl`](file:///C:/Users/rich-/source/repos/CARTAN/src/std/algebra/abstract.cl): Jordan algebras, Tropical Min-Plus/Max-Plus semirings & Floyd-Warshall Kleene closure, Stone Boolean rings & bitvectors, Universal Algebra property verifiers.
- **GeoMind Verification Model (Sprints 548–556, v8.528.0)**:
  - Multi-format document reader (`.docx`, `.xlsx`, `.pdf`), Rank-5 orthonormal alignment subspace debiasing at Layer 32 (orthogonal to the 3D English technical centroid), and complete removal of synthetic prompt injections and post-processing string overrides (100% zero-mock neural generation).

---

## 3. Startup Code Review Findings (Logged in [`ISSUES.md`](file:///C:/Users/rich-/source/repos/CARTAN/ISSUES.md))

1. **`[ISSUE-406]` Disconnected AST Optimizer Pass & Stale BinaryOp Discriminant ([`src/cartanc/optimizer.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/optimizer.car))**:
   - [`optimize_ast`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/optimizer.car#L60-L71) copies top-level statements into `opt_tree` without traversing statements or calling [`optimize_expr`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/optimizer.car#L6-L58).
   - [`optimize_expr`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/optimizer.car#L11) checks `disc == 24.0` for `BinaryOp`, whereas [`ast.ch`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/ast.ch#L80) defines `Expr::BinaryOp` at index `16.0` (line `80.0`).
2. **`[ISSUE-407]` Stubbed LSP Server, Package Manager, & Incomplete CLI/REPL Pipeline ([`src/cartanc/main.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car))**:
   - `cartanc lsp` ([`main.car:L355-L384`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L355-L384)) returns hardcoded JSON-RPC hover/completion strings instead of querying the parsed AST and `TypeChecker`.
   - `cartanc pkg` ([`main.car:L255-L278`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L255-L278)) writes a static `"cartan_app"` entry to `cartan.lock` without parsing `cartan.toml`.
   - `cartanc repl` ([`main.car:L280-L313`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L280-L313)) bypasses `ast_expansion_pass` and `typechecker_check`.
   - `cartanc build` ([`main.car:L450-L455`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/main.car#L450-L455)) only checks `arg 3` for `-o`, ignoring `--release`, `-c`, `-v`, `-O2`, `-I`, and `-L`.
3. **`[ISSUE-408]` Shadowed `FunctionDecl` Discriminant & Mixed Indexing in Type Checker ([`src/cartanc/type_checker.car`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/type_checker.car))**:
   - In [`tc_visit_stmt`](file:///C:/Users/rich-/source/repos/CARTAN/src/cartanc/type_checker.car#L115-L250), `disc == 7.0` is matched at line 179 (`ParameterDecl`), shadowing `7.0` at line 244 (`FunctionDecl`), and statement discriminants mix 0-indexed enum offsets with source line numbers.
