# Cartan Language

> Named in honor of French mathematician **Élie Cartan** (1869–1951)—pioneer of differential forms, the method of moving frames, and Lie group theory, providing the geometric foundation for Cartan's manifold and tensor architecture.

![Cartan Logo](https://via.placeholder.com/150?text=Cartan)

**Cartan** is a statically typed, natively tensor-first programming language designed from the ground up for bare-metal AI development.

By bringing Riemannian geometry, automatic differentiation, and zero-copy memory allocation directly into the language syntax and compiler, Cartan eliminates the overhead of Python abstractions, massive C++ frameworks, and unpredictable heap allocations.

## Key Features

- **Natively Tensor-First**: Tensors are primitive types in Cartan (e.g., `tensor[512, 128] under fp16`). They compile directly into raw memory addresses mapped across physical memory buses.
- **Standard Library Modules (`src/std/`)**:
  - Implementation files carry the `.cl` extension while header files carry `.ch`.
  - `std::math` / `std::string` / `std::collections` / `std::io` / `std::fs` / `std::net` / `std::http` / `std::xml` / `std::env`
  - `std::async` (Pure CARTAN Coroutines: `spawn`, `yield`, `await`) & `std::security` (VRAM Write-Locks & SWMR Sandboxing)
  - `std::geom` / `std::calculus` / `std::physics` / `std::tokenizer` / `std::semantics` / `std::ingest` / `std::dist` / `std::autotune`
  - `std::evolution` (Master Evolutionary Suite: ES + WANN + AZR + M2N2) & `std::es_opt` (Mirrored Evolution Strategies)
  - `std::elm` (Extreme Learning Machines & Closed-Form Zero-Shot LM-Head Readout Solves: $W_{\text{head}}^* = (H^T H + \lambda I)^{-1} H^T Y$)
  - `std::wann` (Weight-Agnostic Neural Networks) & `std::esn` (Echo State Networks / Reservoir Computing)
  - `std::dip` (Deep Image Prior) & `std::reasoning` (Absolute Zero Reasoning Compiler Rewards)
  - `std::optim` (Finsler-Randers Riemannian Natural Gradients) & `std::resonator` (Continuous Hopfield Resonators)
  - `std::hub` (Native HuggingFace AutoModel, AutoTokenizer & Safetensors loader)
  - `std::vision` (Native Computer Vision, Bilinear Resize, RGB Tensors & Normalization)
  - `std::fusion` & `std::distill` (Model Fusion SLERP/TIES/DARE/M2N2 & Teacher-Student Distillation).

- **Shape-Safe Compile Time Verification**: Matrix multiplication shapes ($N \times K \cdot K \times M$) are mathematically proven at compile-time. Shape mismatch crashes are caught during compilation, not hours into training.
- **Riemannian Geometry Types**: Tensors can inhabit specific topological spaces (`in Minkowski`, `in PoincareDisk`). The compiler automatically overrides algebraic operators (like `@`) and applies the inverse metric tensor $g^{-1}$ during reverse-mode autograd to warp gradients back into curved spaces.
- **Zero-Copy Memory**: Cartan enforces absolute zero-allocation runtime mutations. Data paths flow seamlessly from disk/network directly to the GPU/NPU memory controller.
- **Pure CARTAN Core Runtime**: Core language runtime primitives are written directly in pure CARTAN (`src/cartanc/core_runtime.car`), auto-injected during compilation for maximum self-hosting autonomy.
- **Native LLVM Backend**: Cartan emits textual `.ll` (LLVM IR) without external dependencies, allowing your AI models to be compiled directly into standalone `.exe` binaries or linked via standard LLVM tools.

## The Architecture

Cartan compiles via a 100% self-hosted systems pipeline:
1. **Self-Hosted Compiler (`cartanc`)**: Written entirely in native CARTAN (`src/cartanc/`), comprising a modular Lexer (`lexer.car`), Parser (`parser.car`), Semantic Type Checker (`type_checker.car`), AST Optimizer (`optimizer.car`), and LLVM IR Generator (`llvm_codegen.car`).
2. **Pure CARTAN Runtime & Standard Library (`src/cartanc/core_runtime.car`, `src/std/`)**: Canonical runtime operations, async task dispatch, tensor calculus, and neural architectures written natively in CARTAN.
3. **Pure Freestanding Hardware Runtime**: Pure LLVM IR emitted runtime (100% decoupled from C source files) providing zero-allocation dynamic trees, continuous Hopfield memory banks, and WebGPU compute shaders (`gpu_runtime/`).

## Quick Start

### 1. Self-Hosted Compiler Rebuild
CARTAN is completely self-hosting. To rebuild the compiler from source:

```bash
.\cartanc.exe build src/cartanc/main.car -o cartanc.exe
```

### 2. CLI Toolchain Commands
The `cartanc.exe` CLI provides built-in tools for compilation, execution, analysis, and packaging:

- **Build to Native Executable**:
  ```bash
  cartanc.exe build my_model.car -o my_model.exe
  ```
- **In-Memory JIT Execution**:
  ```bash
  cartanc.exe run my_model.car
  ```
- **Interactive REPL**:
  ```bash
  cartanc.exe repl
  ```
- **Package Manager**:
  ```bash
  cartanc.exe pkg
  ```
- **Automated C/C++ FFI Header Generation**:
  ```bash
  cartanc.exe bindgen my_module.car
  ```
- **Language Server Protocol (JSON-RPC 2.0)**:
  ```bash
  cartanc.exe lsp
  ```
- **API Documentation Generator**:
  ```bash
  cartanc.exe doc my_module.car
  ```

### 3. Compile an AI Workflow
You can compile Cartan `.car` files into standalone executables. The test suite and reference AI model engine reside in `test/geomind/`.

```bash
cartanc.exe build test/geomind/chat.car -o build/geomind.exe
```

This produces a fast, standalone native binary `build/geomind.exe`.

### 4. Run GeoMind
GeoMind acts as the universal entry point for training and interacting with neural networks in Cartan.

```bash
# Interactive Lie Group E8 Hopfield Multimodal REPL chat interface:
./build/geomind.exe --chat

# Instant real-time Hopfield memory loading (<0.001 ms) without backpropagation:
./build/geomind.exe --ingest test/geomind/trainingdata/gutenberg_classics.txt

# E8 WordNet & SlangNet taxonomy-aligned Supervised Fine-Tuning pass:
./build/geomind.exe --train-sft
```

## Language Overview
A quick look at modern Cartan syntax:

```cartan
include "src/std/io.cl";
include "src/std/collections.cl";

// Standard main entry point
fn main() -> float {
    printf("Initialized Cartan AI model.\n");
    
    // Dynamic tree data structures and memory collections
    let tree = cartan_tree_create();
    cartan_tree_push(tree, "tensor_node_0");
    
    // Statically sized sequences and blocks
    sequence CausalSeq [ 256 ];
    block AgentBlock [ 16 ];
    
    return 0.0;
}
```

## Documentation
Check out the `docs/` directory for full specifications:
- [Language Reference](docs/LANGUAGE_REFERENCE.md)
- [Language Specification](docs/spec.md)
- [Roadmap](docs/ROADMAP.md)

## License
MIT License
