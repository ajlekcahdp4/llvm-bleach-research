---

title: Agile approach to lifting LLVM MIR code into LLVM IR
sub_title: (https://github.com/ajlekcahdp4/llvm-bleach)
authors:

- Romanov Alexander

---

Binary translators
===

<!-- column_layout: [1, 1] -->

<!-- column: 0 -->

# Generic
+ Specialized low-level representation
+ Difficult to support new architectures
+ Register mapping
+ Instruction mapping

<!-- column: 1 -->
# LLVM-based
+ Lifting to LLVM IR
+ Practically unlimited target architecture set
+ Well-developed compiler and tooling infrastructure
<!-- end_slide -->

LLVM-based lifters
===

# Existing solutions
+ mcsema (2014)
+ mctoll (2019)
+ instrew (2020)
+ biotite (2025)

# Flaws
+ Target-specific lifting algorithm
+ Difficult to support new source architectures
<!-- end_slide -->

LLVM compiler
===

```mermaid +render
graph TD
    cpp_front(C++ Frontend) -->|LLVM IR| optimizer(Common Optimizer)
    c_front(C Frontend) -->|LLVM IR| optimizer
    fortran_front(Fortran Frontend) -->|LLVM IR| optimizer
    optimizer -->|Optimized LLVM IR| x86
    optimizer -->|Optimized LLVM IR| arm
    optimizer -->|Optimized LLVM IR| riscv
    subgraph riscv[RISC-V]
      riscv_isel[ISel]
      riscv_isel  -->|RISC-V MIR| riscv_codegen[CodeGen]
      riscv_codegen -->|RISC-V machine code| riscv_code[ELF]
    end
    subgraph arm[ARM]
      arm_isel[ISel]
      arm_isel  -->|ARM MIR| arm_codegen[CodeGen]
      arm_codegen -->|ARM machine code| arm_code[ELF]
    end
    subgraph x86[X86]
      x86_isel[ISel]
      x86_isel  -->|X86 MIR| x86_codegen[CodeGen]
      x86_codegen -->|X86 machine code| x86_code[ELF]
    end
```

<!-- end_slide -->
LLVM-based lifters
===

```mermaid +render
flowchart TD
    subgraph LLVM
        direction TB
        c_front(C Frontend) -->|LLVM IR| optimizer
        optimizer -->|Optimized LLVM IR| arm[ARM backend]
        arm --> |ARM code| arm_elf[ELF]
    end
    arm_elf --> mctomir
    arm --> mctoll
    mctomir -->|ARM MIR| mctoll
    mctoll -->|Lifted LLVM IR| optimizer
    linkStyle 4 stroke:red,stroke-dasharray:3
```

<!-- end_slide -->

solution - llvm-bleach
===
```mermaid +render
flowchart TD
    subgraph LLVM
        direction TB
        c_front(C Frontend) -->|LLVM IR| optimizer
        optimizer -->|Optimized LLVM IR| arm[ARM backend]
        arm --> |ARM code| arm_elf[ELF]
    end
    arm_elf --> mctomir
    config[Target Configuration] --> bleach
    mctomir -->|MIR| bleach
    bleach -->|Lifted LLVM IR| optimizer
    linkStyle 4 stroke-dasharray:3
```

<!-- end_slide -->

llvm-bleach
===

# Innovations
+ Source target description - configuration file
+ Do NOT attempt to lift target signature
+ Generic (target-independent) translation algorithm
+ Does not use LLVM backend during lifting

<!-- end_slide -->

llvm-bleach
===

# Advantages
+ Easy to support new source architectures
+ Configurable lifting process
+ Simplified build system

<!-- end_slide -->

Generic Approach
===

# Each MIR instruction is mapped to LLVM function
+ Source operand -> argument
+ Destination operand -> return value
<!-- column_layout: [1, 1] -->

<!-- column: 0 -->
## MIR Instruction
```bash
$x1 = ADD $x2, $x3
```
<!-- column: 1 -->
## LLVM Function
```c
define i64 @ADD(i64 %0, i64 %1) {
    %3 = add i64 %1, %0
    ret i64 %3
}
```
<!-- end_slide -->

Code translation
===

<!-- column_layout: [1, 1] -->

<!-- column: 0 -->
# MIR Block (RISC-V)
```bash
bb.1:
  $x19 = MUL $x7, $x2
  $x28 = ADD $x21, $x19
  $x13 = ADD $x13, $x1
  BNE $x13, $x3, %bb.1
```
<!-- column: 1 -->
# Output LLVM IR
```c
bb1:
%19 = call i64 @MUL(i64 %x7, i64 %x2)
%x28 = call i64 @ADD(i64 %x21, i64 %19)
%13 = call i64 @ADD(i64 %x13, i64 %x1)
%cmp = icmp ne i64 %13, %x3
br i1 %cmp, label %bb1, label %bb2
```
<!-- reset_layout -->
# Output LLVM IR after inlining
```c
bb1:
  %19 = mul i64 %x7, %x2
  %x28 = add i64 %x21, %19
  %13 = add i64 %x13, %x1
  %cmp = icmp ne i64 %13, %x3
  br i1 %cmp, label %bb1, label %bb2
```

<!-- end_slide -->

Function Calls
===

# Custom calling convention
State struct - the only argument
```ruby +line_numbers
define void @foo(ptr %0) {
  %GPR = getelementptr %register_state, ptr %0, i32 0, i32 0
  ... # loading registers from state
  %x2_upd = add i64 %x2, -1
  ... # save updated registers to state
  call void @bar(ptr %0)
  ... # reloading registers from state
  %x23_upd = mul i64 %x16, %x14
  ... # save updated registers to state
  ret void
}
```

<!-- end_slide -->

Algorithm
===

```python {1-14|13|9-11|5-8} +line_numbers
def lift(F: function):
  loadRegsFromState(F.StateArgument)
  for MBB in F:
    for I in MBB:
      if I.isCall():
        saveRegsToState(F.StateArgument)
        BB.insertCall(I.Callee, F.StateArgument)
        reloadRegs(F.StateArgument)
      else if I.isCondBranch():
        Cond = BB.insertCall(I.function, I.Src1, I.Src2)
        BB.insertBranch(Cond, I.ifTrue, I.ifFalse);
      else:
        Regs[I.Dst] = BB.insertCall(I.func, I.Src1, I.Src2)
  saveRegsToState(F.StateArgument)
```
<!-- end_slide -->

Peering forward
===
+ Target configuration generation from formal specification (sail-riscv for RISC-V)
+ Syscall translation
+ Support both Dynamic and Static binary translation
+ Testing of clang compiler
+ Using llvm-bleach in binary instrumentation


<!-- end_slide -->

<!-- jump_to_middle -->

Thank you for your attention!
---
