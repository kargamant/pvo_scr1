# Открывает захват предсказателя переходов в осциллограмме Vivado.
# Плата не нужна: файл самодостаточен.
#   vivado -mode gui -source open_bpred_ila.tcl

# _view — та же выборка, но с раскладкой осциллограммы, где выведены сигналы
# предсказателя. В исходном файле лежала устаревшая раскладка от сессии по TCM
# (uart_*, tcm_dmem_*), из-за чего bp_dbg_* не показывались.
set cap [file join [file dirname [info script]] bpred_test_20260728_view.ila]

# labtools нужно инициализировать даже для offline-просмотра.
# В 2019.1 это open_hw; в 2020.1+ команда называется open_hw_manager.
if {[llength [info commands open_hw_manager]]} { open_hw_manager } else { open_hw }

set data [read_hw_ila_data $cap]
display_hw_ila_data $data

puts "=========================================================="
puts " Захват открыт: $cap"
puts " 4096 отсчётов, один отсчёт = один ретайрнутый переход."
puts " Триггер (отсчёт 2048) = первый промах предсказателя."
puts ""
puts " Смотреть сигналы:"
puts "   bp_dbg_pred     - что предсказали"
puts "   bp_dbg_actual   - что произошло"
puts "   bp_dbg_mispred  - промах (pred XOR actual)"
puts "   bp_dbg_pc       - адрес перехода (13 фрагментов, см. ниже)"
puts ""
puts " Отсчёты 0..2047   - холостой цикл бутлоадера, промахов нет."
puts " Отсчёт  2048      - триггер, PC 0xffffdab4, pred=1/actual=0."
puts " Отсчёты 2060..2069- пачка промахов на старте теста."
puts "=========================================================="
