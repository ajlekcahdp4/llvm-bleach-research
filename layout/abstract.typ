#import "/layout/fonts.typ": *

#let abstract(title: "", author: "") = {
  set page(
    margin: (left: 30mm, right: 15mm, top: 20mm, bottom: 20mm), numbering: none, number-align: center, header: grid(columns: (1fr), align: (center), v(0.5mm), text(title, size: 12pt), v(1.6mm), grid.hline()),
  )

  set text(font: fonts.body, size: 10pt, lang: "ru")

  set par(leading: 0.5em)
  // Title and author
  v(10mm)
  align(center, text(font: fonts.sans, 1.5em, weight: 700, "Аннотация"))
  align(center, text(font: fonts.sans, 1.5em, weight: 100, title))
  align(
    center, text(font: fonts.sans, 1.5em, weight: 100, author, style: "italic"),
  )

  v(10mm)
  // Abstract text
  align(
    center, text(
      font: fonts.sans, 1.5em, weight: 100, [
        Проблема бинарной совместимости програм и их переносимости на разные архитектуры
        без возможности перекомпиляции часто решается при помощи бинарных трансляторов.
        Существует большое колличество статических и динамических бинарных трансляторов.
        Большинство из них работают либо за счёт прямого сопоставления инструкциям и
        регистрам исходной архитектуры инструкции и регистры целевой архитектуры, либо
        за счёт паттерн матчинга. Такие решения делают сложным поддержание новых
        исходных архитектур ввиду чего поддержка относительно молодой микропроцессорной
        архитектуры RISC-V в существующих трансляторах либо отсутсвует, либо сильно
        ограничена.

        В данной работе рассмотрен новый инструмент для подъёма машинно зависимого
        представления RISC-V кода LLVM MIR в высокоуровневое машинно-независимое
        представление LLVM IR и его применение для простой статической трансляции
        бинарного RISC-V кода на любую поддержанную LLVM архитектуру.
      ],
    ),
  )
}
