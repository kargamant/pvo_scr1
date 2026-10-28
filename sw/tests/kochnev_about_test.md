В данной папке находятся файлы для сборки тестов dhrystone21 и coremark

По умолчанию в тестах считается, что процессор работает только с памятью ddr. Если вы хотите работать с TCM, то вам необходимо заменить параметр MEM ?= ddr на MEM ?= tcm в src1-sdk/sw/tests/tests_common/tests_common.mk

Данный параметр отвечает за то, с помощью какого линкера будет собираться тест.

Сборка теста:

Для сборки теста dhrystone21 выполните в bash

make clean
make dhrystone21_fpga_nexys

Для сборки теста coremark выполните в bash:

make clean
make coremark_fpga_nexys

Полученные файлы будут находится в папке scr1-sdk/images/nexys4ddr/scr1