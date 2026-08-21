# Открывает потактовый захват предсказателя и расставляет маркеры на четырёх
# показательных моментах.
#
#   vivado -mode gui -source open_bpred_marked.tcl
#
# Плата не нужна. Единицы: 1 отсчёт = 1 пс (timescale захвата), поэтому маркер
# на такте N ставится как "N ps".

set here [file dirname [info script]]
set cap  [file join $here bpred_testcode_20260728.ila]

if {![file exists $cap]} { error "Не найден файл захвата: $cap" }

# labtools нужен даже для offline-просмотра.
# 2019.1 = open_hw; 2020.1+ = open_hw_manager.
if {[llength [info commands open_hw_manager]]} { open_hw_manager } else { open_hw }

set data [read_hw_ila_data $cap]
display_hw_ila_data $data

# --- четыре момента ---------------------------------------------------------
# имя, такт, что показывать
set moments {
    {"1 popadanie"      8    "верное предсказание: цикл 0xf00002b8, redirect не поднимается"}
    {"2 promah A"       2048 "промах: ждали переход, его не было (pred=1, actual=0)"}
    {"3 promah B"       2289 "промах: ждали продолжение, был переход (pred=0, actual=1)"}
    {"4 obuchenie BHT"  2865 "BHT переучился: переход НАЗАД предсказан not-taken"}
}

foreach m $moments {
    lassign $m nm smp _
    if {[catch {add_wave_marker ${smp} ps} e]} {
        puts "  маркер '$nm' на такте $smp не поставлен: $e"
    }
}

puts "\n============================================================"
puts " Захват: [file tail $cap]"
puts " 4096 тактов, ПОТАКТОВЫЙ режим (1 отсчёт = 1 такт при 30 МГц)."
puts ""
puts " Вывести сигналы (кнопка + в окне Waveform, фильтр bp_dbg):"
puts "   bp_dbg_brretire  bp_dbg_pred  bp_dbg_actual"
puts "   bp_dbg_mispred   bp_dbg_redirect"
puts "   i_scr1/tcm_imem_req   u_ila_0_tcm_imem_addr   (конвейер)"
puts ""
puts " ЧЕТЫРЕ МОМЕНТА (маркеры; Ctrl+колесо для приближения):"
foreach m $moments {
    lassign $m nm smp txt
    puts [format "   такт %-5s %s" $smp $txt]
}
puts ""
puts " Окна для приближения:"
puts "   попадания        такты    3 .. 25    (период цикла 5 тактов)"
puts "   промах A         такты 2044 .. 2058"
puts "   промах B         такты 2285 .. 2295"
puts "   обучение BHT     такты 2331 и 2865, затем 2906.. (30 верных подряд)"
puts ""
puts " ВАЖНО: pred/actual/mispred достоверны ТОЛЬКО когда brretire=1."
puts " Вне тактов ретайра они держат старое значение (см. такты 4, 9, 14)."
puts " Адрес выборки пословный: байтовый = tcm_imem_addr * 4."
puts "============================================================"
