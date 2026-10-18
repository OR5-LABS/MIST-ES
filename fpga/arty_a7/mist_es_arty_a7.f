# MIST-ES-on-Arty-A7-100T source list (Vivado read_verilog -sv / iverilog).
# Order: shared leaf cells, core, debug module, UART, FPGA SoC, reset sync, top.
# -I include dir: ../../rtl/common  (mist_es_pkg.sv)
../../rtl/common/mist_es_pkg.sv
../../rtl/common/mist_es_alu.sv
../../rtl/common/mist_es_regfile.sv
../../rtl/common/mist_es_muldiv.sv
../../rtl/common/mist_es_csr.sv
../../rtl/common/mist_es_rvc.sv
../../rtl/common/mist_es_immgen.sv
../../rtl/common/mist_es_branch.sv
../../rtl/common/mist_es_decode.sv
../../rtl/common/mist_es_pmp.sv
../../rtl/mist_es_core.sv
../../rtl/mist_es_debug.sv
../common/mist_es_uart.sv
../mist_es_fpga.sv
../common/common_reset_sync.sv
mist_es_arty_a7.sv
