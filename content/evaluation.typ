#import "/utils/todo.typ": TODO
#import "@preview/codly:1.3.0": *
#import "@preview/codly-languages:0.1.1": *
#show: codly-init.with()

= Описание практической части
В данной главе представлена имплементация идей и подходов к решению задачи
подъёма MIR кода архитектуры RISC-V в LLVM IR, описанных в @chapt-solution.
Построена модель инструкций этой архитектуры и описано применение её для
трансляции кода RISC-V в высокоуровневое представление LLVM IR.

== Модель инструкции RISC-V <chapt-instruction-model>
Начнём с построения модели инструкции архитектуры RISC-V, представленной в
@chapt-instr-model. Как уже было сказано, мы разделим все инструкции из
спецификации RISC-V на несколько классов, все инструкции внутри которых будут
обрабатываться одинаково. Опишем все выделенные в данной работе классы
инструкций.

=== Регулярные инструкции
Класс "регулярных" инструкций был описан в @chapt-instr-model, в этот класс
попадёт большинство инструкций из спецификации, в том числе `ADD`, `SLLI`, `MUL` и
т.д. В терминах предикатов из MIR инструкция принадлежит к этому классу если
выражение на @regular-class-code верно. Как уже было отмечено, инструкции этого
класса поднимаются простой итеративной заменой на вызовы соответствующих
функций.

#codly(zebra-fill: luma(240))
#figure(
  caption: [Условие принадлежности к классу регулярных инструкций],
)[
#set text(size: 1.2em)
```CPP
  bool is_regular_instruction(const MachineInstr &minst) {
    return !minst.isTerminator() && !minst.isCall() && !minst.isReturn();
  }
  ```
] <regular-class-code>

=== Инструкции безусловного перехода
Инструкции безусловного перехода -- операции, передающие управление другому
базовому блоку сразу по их достижению исполнителем. Условием принадлежности к
этому классу в MIR является удовлетворение предикату на @br-class-code.
#figure(
  caption: [Условие принадлежности к классу инструкций безусловного перехода],
)[
#set text(size: 1.2em)
```CPP
bool is_unconditional_branch(const MachineInstr &minst) {
  return minst.isUnconditionalBranch();
}
```
] <br-class-code>

Перевод инструкций из этого класса выполняется путём простой замены этой
инструкции на инструкцию безусловного перехода из LLVM IR #footnote[За подробной информации об инструкции `br` и других инструкциях LLVM IR можно
обратиться к @llvm-langref] с блоком назначения, полученным из соответствующего
операнда `MachineInstr`. Таким образом простой пример кода с инструкцией
безусловного перехода `J` из @br-mir-code переводится в LLVM IR, представленный
на @br-llvm-code.

#grid(columns: (50%, 50%), gutter: 5pt, [
#figure(caption: [Пример MIR кода с инструкцией `J`])[
```MIR
bb.0:
  ...
bb.1:
  ...
  J bb.0
```
] <br-mir-code>
], [
#figure(caption: [Пример MIR кода с инструкцией `J`])[
```LLVM
block0:
  ...
block1:
  ...
  br label %block0
```
] <br-llvm-code>
])

=== Инструкции условного перехода
Инструкциями условного перехода назовём инструкции, передающие управление другим
базовым блокам при соблюдении определённых условий. В терминах предикатов MIR
инструкция принадлежит этому классу если верен предикат описанный на
@cond-br-class-code.
#figure(
  caption: [Условие принадлежности к классу инструкций условного перехода],
)[
#set text(size: 1.2em)
```CPP
  bool is_conditional_branch(const MachineInstr &minst) {
    return minst.isConditionalBranch();
  }
```
] <cond-br-class-code>

Определить базовый блок, которому возможна пердача управления, легко обратившись
к операндам `MachineInstr`. Условие перехода, однако, определить из описания
LLVM невозможно. Воспользуемся тем, что условием всех условных переходов в
архитектуре RISC-V является результат сравнения двух регистров #footnote[Некоторые инструкции из расширения C (например `C_BEQZ`) имеют один входной
регистр, который они сравнивают с нулём, однако они не требуют специальной
обработки и являются частным случаем инструкций условного перехода в нашей
классификации]. Будем получать условие перехода для инструкций через
сопоставление каждой из этих функций булевой функции на LLVM IR. Сопоставлять
предлагается по следующему принципу: Значение всех входных операндов-регистров
инструкции (выходных операндов нет) передаются в функцию как аргументы. Функция
выполняет соответствующую инструкции проверку над этими операндами и возвращает
результат в виде булевого значения. Далее вставляется инструкция условного
перехода LLVM IR , условием которой является значение, полученное из вызова
описанной выше функции. Назначением перехода будет соответствовать базовый блок,
полученный из последнего операнда инструкции. В отличии от инструкций условного
перехода, инструкция условного перехода `br` в LLVM IR имеет ещё один операнд --
базовый блок, в который она передаст управление если условие не выполнено.
Значение данного операнда будем выставлять в следующий за этой инструкцией
базовый блок/инструкцию.

Приведём пример такого сопоставления для инструкции `BLT` (Branch if Less Then
-- Переход если меньше). Данная инструкция принимает на вход два регистра и
совершает переход, если значение в первом регистре меньше чем во втором.
Соответствующая данной инструкции функция в LLVM IR будет иметь вид:
#figure(caption: [Функция-условие перехода, соответствующая инструкции `BLT`])[
#set text(size: 1.2em)
```LLVM
define i1 @BLT(i64 %0, i64 %1) {
  %3 = icmp slt i64 %0, %1
  ret i1 %3
}

```
] <blt-code>

Тогда при переводе кода, представленного на @blt-mir-code, получим LLVM IR
представленный на @blt-llvm-code.
#figure(caption: [Пример MIR кода с инструкцией `BLT` для перевода в LLVM IR])[
#set text(size: 1.2em)
```MIR
bb.0:
  ...
  BLT $x10, $X11, bb.0
bb.1:
  ...

```
] <blt-mir-code>

#figure(caption: [Полученный при переводе инструкции `BLT` LLVM IR])[
#set text(size: 1.2em)
```LLVM
block0:
  ...
  %cond = i1 call @BLT(i64 %x10, i64 %x11)
  br i1 %cond, label %block0, label %block1
block1:
  ...
```
] <blt-llvm-code>

=== Инструкции вызова функций
Вызов функции -- передача управления определённой функции с последующим
возвратом управления в точку вызова. В отличии от инструкций условного и
безусловного перехода, инструкции вызова не прерывают базовые блоки и могут
находиться внутри них. С точки зрения MIR инструкция принадлежит этому классу
если выполняется предикат, представленный на @call-class-code:
#figure(caption: [Условие принадлежности к классу инструкций вызова])[
#set text(size: 1.2em)
```CPP
bool is_call(const MachineInstr &minst) {
  return minst.isCall();
}

```
] <call-class-code>

Работа с вызовами функций в нашем трансляторе намного интереснее работы с
другими классами инструкций. Как было отмечено в @chapt-abi-concept, вместо
попыток воспроизвести изначальную сигнатуру функции мы будем пользоваться
собственным соглашением о вызовах, в котором функции общаются друг с другом,
передавая единственный аргумент -- ссылку на текущий контекст исполнения.

Работа с контекстом исполнения означает, что на момент вызова и возврата из
функций в этом контексте должно храниться актуальное состояние регистров. Таким
образом, необходимо записывать обновлённые значения каждого из регистров в
контекст. При переводе инструкции вызова `JAL` в RISC-V мы будем заменять её
вызовом соотвтетсвующей функции в LLVM IR (см. @call-mir-code и
@call-llvm-code).
#figure(caption: [Пример MIR кода с инструкцией `JAL` для перевода в LLVM IR])[
#codly(zebra-fill: none)
#set text(size: 1.2em)
```MIR
  JAL bar

```
] <call-mir-code>

#figure(caption: [Полученный при переводе инструкции `JAL` LLVM IR])[
#set text(size: 1.2em)
```LLVM
  call void @bar(ptr %state)
```
] <call-llvm-code>

#codly(zebra-fill: luma(240))

== Имплементация транслятора
Наконец опишем полный алгоритм работы транслятора из RISC-V MIR кода в LLVM IR,
основанного на описанных выше принципах (код доступен на @bleach-github).

=== Конфигурация целевой архитектуры <chapt-configuration-format>
Опишем конкретный использованный формат описания инструкций, о котором
говорилось в @chapt-instruction-model. Как было сказано выше, большинству
инструкций из спецификации RISC-V сопоставляются функции из LLVM IR. В ходе
работы было принято решение вынести данное описание за пределы исходного кода
инструмента. Таким образом пользователь сможет настраивать инструмент для
подъёма необходимой ему конфигурации RISC-V процессора без необходимости
перекомпиляции проекта из исходного кода.

В качестве языка для описания инструкций выбран язык разметки YAML (см.
@yaml-spec). Такой выбор был сделан из-за распространённости инструментов для
работы с этим представлением и его простоты к написанию. YAML (рекурсивный
акроним для YAML Ain't Markup Language) -- Человекочитаемый язык сериализации
данных, разработанный в 2001 году. YAML используется для написания
конфигурационных файлов, а так же для хранения и передачи данных. Перечислим
главные концепции YAML, которыми далее будем пользоваться:
- *Скаляры* -- самый примитивный из типов данных, используемых в YAML. Скалярами
  могут являться целый числа, числа с плавающей точкой или строки. Строки могут
  содержать символы перехода на новую строку, а ковычки являются опциональными.
  Особым видом скаляров является `null`, обозначающий отсутствие значения.
- *Сопоставления (словари)* -- тип данных, представляющий собой неупорядоченный
  набор, ассоциирующий ключи со значениями. Сопоставления задаются в YAML через
  значение, отделённое от своего ключа двоеточием. Ключи обязаны быть уникальными,
  а значения могут иметь любой из доступных типов: скаляры, другие словари или
  списки.
- *Списки (коллекции)* -- объекты, представляющие собой упорядоченный набор из
  любых данных. YAML предоставляет два формата задания списков: блочный и
  однострочный. В блочном формате элементы списка задаются на новой строке,
  начинающейся с символа `-`, а в однострочном пишутся внутри квадратных скобок и
  разделяются запятыми (см. @yaml-seq-example).
#figure(
  caption: [Пример списков в YAML (Здесь и `foo`, и `bar` хранят последовательность чисел от
  1 до 3)],
)[
#set text(size: 1.2em)
```yaml
foo:
- 1
- 2
- 3
bar: [1, 2, 3]
```
] <yaml-seq-example>

Формат YAML конфигурации был выбран следующим:
- Верхнеуровневый ключ `instructions` начинает перечисление описаний для каждой из
  необходимых инструкций
- Каждая из инструкций в свою очередь хранит текстовое представление
  соответствующей ей функции LLVM IR под ключём `func`.

Таким образом, пример входной конфигурации архитектуры можно увидеть на
@yaml-config-example. Конфигурационный файл в заданном формате считывается
транслятором и описанные в нём функции используются для подъёма MIR кода RISC-V.
Функции для инструкций условного перхода задаются в том же формате, пример для
инструкции `BLT` представлен на @yaml-cond-br-example.
#figure(
  caption: [Пример конфигурации архитектуры в формате YAML для инструкций `OR` и `XOR`],
)[
#set text(size: 1.2em)
```yaml
instructions:
  - OR:
      func: |
        define i64 @OR(i64 %0, i64 %1) {
          %3 = or i64 %1, %0
          ret i64 %3
        }
  - XOR:
      func: |
        define i64 @XOR(i64 %0, i64 %1) {
          %3 = xor i64 %1, %0
          ret i64 %3
        }
```
] <yaml-config-example>

#figure(
  caption: [Пример конфигурации архитектуры в формате YAML для инструкции `BLT`],
)[
#set text(size: 1.2em)
```yaml
instructions:
  - BLT:
      func: |
        define i1 @BLT(i64 %0, i64 %1) {
          %3 = icmp slt i64 %0, %1
          ret i1 %3
        }
```
] <yaml-cond-br-example>

=== Алгоритм трансляции
Наконец, последовательно опишем алгоритм трансляции модуля LLVM MIR.

==== Создание объектов функции и типа контекста
Начнём с построения класса контекста исполнения `state`. На данный момент данный
класс будет хранить в себе исключительно состояний регистров. Таким образом
создаётся структура (`struct`) в LLVM IR, хранящая в себе массив значений
регистров. Массив используется вместо контейнера, потому что все регистры общего
назначения архитектуры RISC-V пронумерованы (От `X0` до `X31` в случае `rv32i`/`rv64i` и
от `X0` до `X15` в случае `rv32e`/`rv64e`). Ширина, необходимая для хранения
значения регистров выбирается в зависимости от того, поднимается ли код
32-битного или с 64-битного варианта архитектуры RISC-V #footnote[Аналогично возможна поддежрка 128-битной архитектуры RISC-V].
Таким образом структура контекста в LLVM IR будет иметь вид:
#figure(caption: [Структура контекста для архитектуры `rv64i`])[
#set text(size: 1.2em)
```LLVM
%state = type { [32 x i64] }
```
]

Как было описано в @chapt-intro-mir, Модули в MIR состоят из машинных функций
(класс `MachineFunction` в библиотеке LLVM). Прежде всего для каждой машинной
функции необходимо создать соответствующую функцию LLVM IR, с сигнатурой,
описанной в @chapt-abi-concept. Т.е. создаётся функция с тем же именем, что и у
машинной, которая имеет пустое возвращаемое значение `void` и единственный
аргумент `%regstate` типа `ptr`.

Далее для всех базовых блоков изначальной MIR функции необходимо создать новый
базовые блоки в LLVM IR. В дальнейшей работе возможно добавление новых базовых
блоков для работы с особенностями LLVM IR, но функция будет иметь как минимум
столько же блоков, сколько исходная `MachineFunction`. В процессе создания
базовых блоков необходимо строить отображение из старых машинных блоков в новые
блоки LLVM IR. Данная информация будет необходима при дальнейшей работе с
потоком управления.

==== Выгрузка регистров из контекста
Перед началом итеративного подъёма инструкций в MIR функции необходимо выгрузить
значения регистров из контекста. Для этого в LLVM необходимо сначала получить
адресс массива регистров (назовём его `%GPRS`) из контекста. Это делается через
инструкцию `getelementptr`, принимающей в нашем случае два индекса. Первый
индекс -- индекс структуры контекста в возможном массиве этих контекстов,
скрывающимся под указателем `%regstate`, полученным как аргумент функции. В
нашем случае этот индекс всегда равен нулю. Второй индекс обозначает номер
элемента в структуре `state`. В нашем случае массив регистров -- первый элемент
структуры, поэтому данный индекс также будет равен нулю. Теперь необходимо
получить адрес каждого из регистров (назовём его `%x_i_ptr`, где `i` -- номер
регистра), хранимых в массиве, указатель на который был только что получен. Для
этого снова используется инструкция `getelementptr` первый индекс которой равен
нулю как индекс единственного массива в возможном массиве массивов `%GPRS`, а
второй равен номеру регистра. После этого загружается значение регистра `%x_i` из
указателя `%x_i_ptr`. Загрузка производится при помощи инструкции `load`,
загружаемый тип которой выставлен в целочисленной число с размером в ширину
регистра (т.е. `i64` для `rv64`).

Теперь полученные из контекста значения регистров складываются на стек. Для
этого необходимо выделить для них стековую ячейку `%x_i_stack`. Сделаем это при
помощи инструкции `alloca` с соответствующим регистру типом. Теперь можно
записать выгруженное ранее значение регистра в подготовленную стековую ячейку
при помощи инструкции `store`. Описанные операции выгрузки значений из
контекста, выделения места на стеке и сохранение на стек необходимо повторить
для всех используемых регистров (см. @reg-mat-algo). Полученный LLVM IR код
представлен на @reg-mat-code.

#figure(
  caption: [Алгоритм выгрузки регистров из контекста],
)[
#set text(size: 1.3em)
```CPP
void load_registers_from_state(IRBuilder &builder,
                          std::map<unsigned, Value *> &stack_frame) {
  auto *zero = ConstantInt::zero();
  auto *regs_array = builder.CreateGEP(state_type, state_arg, {zero, zero});
  for (unsigned i = 0; i < num_regs; ++i) {
    auto *idx = ConstantInt::Create(i);
    auto *reg_addr = builder.CreateGEP(array_type, regs_array, {zero, idx});
    auto *val = builder.CreateLoad(reg_type, reg_addr);
    if (!stack_frame.contains(i))
      stack_frame[i] = builder.CreateAlloca(reg_type);
    builder.CreateStore(reg_type, reg_value, stack_frame[i]);
  }
}
```
] <reg-mat-algo>

#figure(
  caption: [Код аллокации стекового окна и выгрузки 64-битных регистров для функции `foo`],
)[
#set text(size: 1.3em)
```LLVM
define void @foo(ptr %regstate) {
  %GPRS = getelementptr %state, ptr %regstate, i32 0, i32 0
  %x_0_ptr = getelementptr inbounds [32 x i64], ptr %GPRS, i32 0, i32 0
  %x_0_stack = alloca i64, align 8
  %x_0 = load i64, ptr %x_0_ptr, align 8
  store i64 %x_0, ptr %x_0_stack, align 8
  %x_1_ptr = getelementptr inbounds [32 x i64], ptr %GPRS, i32 0, i32 1
  %x_1_stack = alloca i64, align 8
  %x_1 = load i64, ptr %x_1_ptr, align 8
  store i64 %x_1, ptr %x_1_stack, align 8
  ...
  ret void
}
```
] <reg-mat-code>

==== Сохранение регистров в контекст
Перед возвратом из функции и перед вызовом других функций необходимо сохранить
обновлённые значения регистров в контекст. Опишем алгоритм такого сохранения:
+ Зная значения стековых слотов для регистров `%x_i_stack` и адресс их массива в
  контексте `%GPRS`, будем загружать значения со стека при помощи инструкции `load` и
  сохранять их в соответствующие ячейки контекста `%x_i_ptr` (см. псевдокод на
  @reg-save-algo). Пример получившегося LLVM IR кода представлен на
  @reg-save-code.

#figure(
  caption: [Алгоритм сохранения регистров в контекст], placement: auto,
)[
#set text(size: 1.3em)
```CPP
void load_registers_from_state(IRBuilder &builder,
                               std::map<unsigned, Value *> &stack_frame) {
  auto *zero = ConstantInt::zero();
  auto *regs_array = builder.CreateGEP(state_type, state_arg, {zero, zero});
  for (unsigned i = 0; i < num_regs; ++i) {
    auto *idx = ConstantInt::Create(i);
    auto *reg_addr = builder.CreateGEP(array_type, regs_array, {zero, idx});
    auto *val = builder.CreateLoad(reg_type, reg_addr);
    if (!stack_frame.contains(i))
      stack_frame[i] = builder.CreateAlloca(reg_type);
    builder.CreateStore(reg_type, reg_value, stack_frame[i]);
  }
}
```
] <reg-save-algo>

#figure(
  caption: [Код сохранения 64-битных регистров в контекст], placement: auto,
)[
#set text(size: 1.3em)
```LLVM
define void @foo(ptr %regstate) {
  ...
  %x_30 = load i64, ptr %x_30_stack, align 8
  store i64 %x_30, ptr %x_30_ptr, align 8
  %x_31 = load i64, ptr %x_31_stack, align 8
  store i64 %x_31, ptr %x_31_ptr, align 8
  ret void
}
```
] <reg-save-code>

==== Замена инструкций
Теперь, сохранив значения всех регистров, можно начать заполнять LLVM IR
переведёнными машинными инструкциями. Для этого пройдёмся по всем базовым блокам
в машинной функции и будем вставлять их поднятое представление в соответствующие
блоки LLVM IR. Итого для каждой инструкции применяется следующая операция:
+ Если инструкция является регулярной -- вставить вызов соответствующей ей функции
  LLVM IR.
+ Если инструкция является безусловным переходом -- вставить инструкцию
  безусловного кода LLVM IR с назначением равным блоку, соответствующему текущему
  MIR блоку.
+ Если инструкция является условным переходом -- вставить вызов соответствующей ей
  функции-условия, после чего вставить инструкцию условного перехода `br i1` в
  LLVM IR. При соблюдении условия назначением перехода является блок,
  соответствующий блоку-назначению из MIR. В противном случае блоком назначения
  является следующий за текущим базовый блок.
+ Если инструкция является вызовом функции -- сохранить значения всех регистров в
  контекст, вставить вызов соответствующей LLVM IR функции, передав ей указатель
  на контекст, после чего снова выгрузить обновлённые значения регистров на стек.
+ Если инструкция является инструкцией возврата -- сохранить значения всех
  регистров в контекст и вставить инструкцию `ret`
Псевдокод данной операции представлен на @lift-instr-pseudocode

#figure(
  caption: [Псевдокод операции подъёма одной инструкции], placement: auto,
)[
#set text(size: 1.2em)
```CPP
Value *lift_instruction(const MachineInstr &minst,
                        const blocks_map &blocks, IRBuilder &builder) {
  if (is_regular(minst))
    return builder.CreateCall(get_function_for(minst));
  if (is_unconditional_branch(minst))
    return builder.CreateBr(bb[get_destination_block(minst)]);
  if (is_conditional_branch(minst)) {
    auto *cond = builder.CreateCall(get_function_for(minst));
    return builder.CreateCondBr(cond, get_true_block(minst), get_false_block(minst));
  }
  if (is_call(minst)) {
    save_registers_to_state(builder);
    auto *call = builder.CreateCall(get_dest_function(minst));
    load_registers_from_state(builder);
    return call;
  }
  if (is_return(minst)) {
    save_registers_to_state(builder)
    builder.CreateRetVoid();
  }
  ...
}
```
] <lift-instr-pseudocode>

=== Оптимизация транслированного кода
Выше был описан алгоритм подъёма модуля MIR кода архитектуры RISC-V в LLVM IR.
Легко заметить усложнение транслируемого кода при его подъёме. В несколько раз
увеличено число вызовов функций (В среднем по одному на каждую инструкцию
исходного кода). Также на каждый регистр была выделена отдельная стековая
ячейка. При этом каждое чтение регистра заменено на загрузку элемента со стека,
а каждая запись в регистр заменена на запись в память. Такие изменения структуры
кода не только делают его более сложным для анализа, но и влекут за собой
потенциальные потери в производительности
#footnote[Эта работа не концентрируется на повышении производительности странслированного
  кода, но предпринимает базовые шаги к её улучшению]. В этом разделе будут
рассмотрены использованные меры по упрощению структуры и повышению
производительности странслированного кода. LLVM является развитой компиляторной
инфраструктурой и, как было описано ранее (см. @chapt-intro-llvm-opt), имеет
большое число встроенных оптимизаций как высокого, так и низкого, машинного
уровня. Мы будем использовать предосталвенные LLVM оптимизации в виде проходов.

==== Оптимизация стекового пространства
Прежде всего избавимся от лишних аллокаций стекового пространства.
Инфраструктура LLVM предоставляет оптимизацию SROA (Scalar Replacement of
Aggregates -- Замещение агрегатов скалярами). Данная оптимизация заменяет
аллокации агрегатных типов (Чаще всего аллокации массивов с помощью инструкции `alloca`)
на отдельные ячейки стека, полученные несколькими инструкциями `alloca`. Также
данная оптимизация способна полностью удалять выделение стека и строить
полноценную SSA форму кода. Мы применим этот оптимизационный проход к
полученному при трансляции LLVM IR для удаления ячеек стека и построения более
простой для анализа и дальнейших оптимизаций SSA форму LLVM IR. Пример кода до и
после такой оптимизации можно видеть на @llvm-ir-no-ssa и @llvm-ir-with-ssa,
важно обратить внимание на исчезновение инструкций загрузки и записи, а также на
появление характерных для SSA формы $phi$-функций.

#figure(caption: [Блок LLVM IR до оптимизации SROA], placement: top)[
#set text(size: 1.2em)
```LLVM
106: ; preds = %106, %1
  %107 = load i64, ptr %87, align 8
  %108 = load i64, ptr %75, align 8
  %109 = call i64 @ADD(i64 %107, i64 %108)
  store i64 %109, ptr %54, align 8
  %110 = load i64, ptr %48, align 8
  %111 = load i64, ptr %60, align 8
  %112 = call i64 @MULW(i64 %110, i64 %111)
  store i64 %112, ptr %33, align 8
  %113 = load i64, ptr %81, align 8
  %114 = call i64 @ADD(i64 %113, i64 0)
  store i64 %114, ptr %81, align 8
  %115 = load i64, ptr %81, align 8
  %116 = load i64, ptr %9, align 8
  %117 = call i64 @SRL(i64 %115, i64 %116)
  store i64 %117, ptr %60, align 8
  %118 = load i64, ptr %60, align 8
  %119 = call i1 @BEQ(i64 %118, i64 0)
  br i1 %119, label %106, label %120
```
] <llvm-ir-no-ssa>

==== Подстановка тела функций
Для уменьшения числа лишних вызовов и дальнейшей оптимизации построенной SSA
формы кода применим оптимизацию подстановки тела функций. Данная оптимизация
заменяет вызов функции подстановкой кода этой самой функции. При этом значения
параметров функции заменятся значениями поданных аргументов, которые напрямую
подставляются в операции из тела этой самой функции. Далее оптимизация может
обнаружить и убрать лишние SSA значения в LLVM IR. Таким образом, применив
подстановку функций к LLVM IR коду, представленному на @llvm-ir-with-ssa,
получим ещё более оптимизированный код, приведённый на @llvm-ir-after-inline.

#grid(
  columns: (50%, 50%), gutter: 5pt, [
  #figure(caption: [Блок LLVM IR после оптимизации SROA], placement: top)[
  #set text(size: 1.2em)
  ```LLVM
              70: ; preds = %70, %1
                %.079 = phi i64 [ %69, %1 ], [ %74, %70 ]
                %.077 = phi i64 [ %68, %1 ], [ %73, %70 ]
                %71 = call i64 @ADD(i64 %59, i64 %51)
                %72 = call i64 @MULW(i64 %66, i64 %.079)
                %73 = call i64 @ADD(i64 %.077, i64 0)
                %74 = call i64 @SRL(i64 %73, i64 %7)
                %75 = call i1 @BEQ(i64 %74, i64 0)
                br i1 %75, label %70, label %76
              ```
  ] <llvm-ir-with-ssa>
  ], [
  #figure(
    caption: [Блок LLVM IR после подстановки тела функции], placement: top,
  )[
  #set text(size: 1.2em)
  ```LLVM
              68 ; preds = %68, %1
                %.079 = phi i64 [ 0, %1 ], [ %72, %68 ]
                %69 = add i64 %51, %59
                %70 = mul i64 %66, %.079
                %71 = and i64 %7, 63
                %72 = lshr i64 0, %71
                %73 = icmp eq i64 %72, 0
                br i1 %73, label %68, label %74
              ```
  ] <llvm-ir-after-inline>

  ],
)

== Применение инструмента к тестированию clang
Полученный транслятор из RISC-V машинного и MIR кода был использован для
тестирования компилятора `clang`. Тестирование производилось путём генерации
случайного тестового RISC-V MIR кода, которые после этого компилировался до
машинного кода RISC-V с минимальным уровнем оптимизаций `-O0`, после чего
поднимался в LLVM IR через представленный в этой работе инструмент llvm-bleach и
снова компилировался до RISC-V машинного кода с максимальным уровнем
компиляторных оптимизаций `-O3`. Обе полученный программы далее исполнялись на
функциональном симуляторе архитектуры RISC-V (см. @spike), и сравнивались
значения регистров. Схематически процесс тестирования описан на @clang-checker.

В результате такого тестирования была обнаружена проблема, при которой
компилятор `clang` переставлял местами инструкции выставления режима округления
для чисел с плавающей точкой и арифметические операции с плавающей точкой, что
приводило к расхождению в результатах. Подробное описание ошибки можно найти в
@llvm-float-bug.
#figure(
  caption: [Схема эксперимента по тестированию компилятора `clang`], placement: auto,
)[
  #image("../images/clang-checker.png")
] <clang-checker>
== Результаты
При описании инструкций архитектуры RISC-V в предложеном формате (см.
@chapt-configuration-format) было реализовано 50 инструкций из базового набора
команд `rv64i/e` (94%), 50 инструкций для `rv32i/e` (93%), также полностью
поддержаны все 12 инструкции из расширения `M`. Дополнительно были поддержаны
некоторые инструкции из расширений для чисел с плавающей точкой разной точности `F` и `D`.
Визуализация поддежанных инструкций представлена на @support-percent.

Был разработан инструмент, названный `llvm-bleach` и способный к подъёму
машинного и MIR кода RISC-V в высокоуровневое промежуточное представление LLVM
IR. Данный инструмент был применён в статической бинарной трансляции кода с `rv64im` на `X86`,
а так же тестирования компилятора `clang`.

#figure(
  caption: [Поддержка расширений RISC-V в разработанном инструменте llvm-bleach], placement: auto,
)[
  #image("../images/support.svg")
] <support-percent>

