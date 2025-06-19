graph LR
  rand_code(Random RISC-V Code) --> bleach(llvm-bleach)
  style rand_code fill:#fffb6b
  bleach --> |Lifted LLVM IR| clang3(clang -O3)
  clang3 --> opt_code(Optimized RISC-V Code)
  style opt_code fill:#fffb6b
  opt_code --> comparator(Comparator)
  rand_code --> comparator
