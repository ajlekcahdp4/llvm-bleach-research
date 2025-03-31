---

title: Гибкий подход к подъёму LLVM MIR кода в SSA форму LLVM IR
sub_title: (https://github.com/ajlekcahdp4/llvm-bleach)
authors:

- Романов Александр

---

Бинарные трансляторы
===

<!-- column_layout: [1, 1] -->

<!-- column: 0 -->

# Обычные
+ Специализированное низкоуровневое представление
+ Сложная поддержка новых целевых архитектур
+ Cопостовление регистров
+ Cопоставление инструкций

<!-- column: 1 -->
# LLVM-based
+ Подъём в LLVM IR
+ Развитая инфраструктура анализа и инструментации
<!-- end_slide -->

Трансляторы в LLVM
===

# Существующие решение
+ mcsema
+ mctoll
+ instrew

# Недостатки
+ Алгоритм трансляции специфичен для архитектуры
+ Сложная поддержка новых исходных архитектур
<!-- end_slide -->

Компилятор LLVM
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

llvm-bleach
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

# Нововведения
+ Описание исходной архитектуры - конфигурация
+ Не пытаемся восстановить сигнатуру функций
+ Обобщённые алгоритмы трансляции
+ Не используется LLVM backend

<!-- end_slide -->

llvm-bleach
===

# Преимущества
+ Легко поддержкать новую исходную архитектуру
+ Настраиваемый процесс подъёма
+ Упрощённая сборка проекта

<!-- end_slide -->

Общие принципы
===

# Каждой инструкции сопоставляется функция
+ Входной операнд -> аргумент
+ Результат -> возвращаемое значение
<!-- column_layout: [1, 1] -->

<!-- column: 0 -->
## Инструкция
```bash
$x1 = ADD $x2, $x3
```
<!-- column: 1 -->
## Функция
```c
define i64 @ADD(i64 %0, i64 %1) {
    %3 = add i64 %1, %0
    ret i64 %3
}
```
<!-- end_slide -->

Преобразование кода
===

<!-- column_layout: [1, 1] -->

<!-- column: 0 -->
# Блок MIR (RISC-V)
```bash
bb.1:
  $x19 = MUL $x7, $x2
  $x28 = ADD $x21, $x19
  $x13 = ADD $x13, $x1
  BNE $x13, $x3, %bb.1
```
<!-- column: 1 -->
# Получившийся LLVM IR
```c
bb1:
%19 = call i64 @MUL(i64 %x7, i64 %x2)
%x28 = call i64 @ADD(i64 %x21, i64 %19)
%13 = call i64 @ADD(i64 %x13, i64 %x1)
%cmp = icmp ne i64 %13, %x3
br i1 %cmp, label %bb1, label %bb2
```
<!-- reset_layout -->
# LLVM IR после подстановки
```c
bb1:
  %19 = mul i64 %x7, %x2
  %x28 = add i64 %x21, %19
  %13 = add i64 %x13, %x1
  %cmp = icmp ne i64 %13, %x3
  br i1 %cmp, label %bb1, label %bb2
```

<!-- end_slide -->

Преобразование функций
===

# Своё соглашение о вызовах
Cтруктура состояния - единственный аргумент
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

Алгоритм
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

Что дальше
===
+ Генерация конфигурации из формальной спецификации
+ Трансляция системных вызовов
+ Динамическая и статическая бинарная трансляция
+ Тестирование компилятора clang
+ Использование в бинарной инструментации


<!-- end_slide -->

<!-- jump_to_middle -->

Спасибо за внимание!
---
