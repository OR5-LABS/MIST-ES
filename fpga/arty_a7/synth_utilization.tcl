# =============================================================================
# synth_utilization.tcl — Comprehensive Vivado batch synthesis script for MIST-ES.
#
# Usage:
#   vivado -mode batch -source synth_utilization.tcl -tclargs <TARGET> <SECURE_VAL> <OUT_DIR>
#
# Parameters:
#   TARGET     : 'core' (mist_es_core OOC) or 'soc' (mist_es_arty_a7 top)
#   SECURE_VAL : 0 (Default config: M-mode) or 1 (SECURE config: M+U, PMP/ePMP, ECC)
#   OUT_DIR    : Directory to store reports and logs
# =============================================================================

set target_type [lindex $argv 0]
set secure_val  [lindex $argv 1]
set out_dir     [lindex $argv 2]

set fpga_dir    [file normalize [file dirname [info script]]]
set mist_es_dir [file normalize "$fpga_dir/../.."]
set part        "xc7a100tcsg324-1"

file mkdir $out_dir
cd $out_dir

puts "================================================================="
puts "  Synthesizing MIST-ES Target: $target_type | SECURE=$secure_val"
puts "  Part: $part"
puts "  Output Dir: $out_dir"
puts "================================================================="

# Read SystemVerilog RTL files
read_verilog -sv [list \
  "$mist_es_dir/rtl/common/mist_es_pkg.sv" \
  "$mist_es_dir/rtl/common/mist_es_alu.sv" \
  "$mist_es_dir/rtl/common/mist_es_regfile.sv" \
  "$mist_es_dir/rtl/common/mist_es_regfile_ecc.sv" \
  "$mist_es_dir/rtl/common/mist_es_muldiv.sv" \
  "$mist_es_dir/rtl/common/mist_es_csr.sv" \
  "$mist_es_dir/rtl/common/mist_es_rvc.sv" \
  "$mist_es_dir/rtl/common/mist_es_immgen.sv" \
  "$mist_es_dir/rtl/common/mist_es_branch.sv" \
  "$mist_es_dir/rtl/common/mist_es_decode.sv" \
  "$mist_es_dir/rtl/common/mist_es_pmp.sv" \
  "$mist_es_dir/rtl/mist_es_core.sv" \
]

if {$target_type eq "soc"} {
  read_verilog -sv [list \
    "$mist_es_dir/rtl/mist_es_debug.sv" \
    "$mist_es_dir/fpga/common/mist_es_uart.sv" \
    "$mist_es_dir/fpga/common/common_reset_sync.sv" \
    "$mist_es_dir/fpga/mist_es_fpga.sv" \
    "$mist_es_dir/fpga/arty_a7/mist_es_arty_a7.sv" \
  ]
  read_xdc [list "$mist_es_dir/fpga/arty_a7/mist_es_arty_a7.xdc"]
  add_files -norecurse [list "$mist_es_dir/sw/firmware.mem"]
  set_property file_type {Memory Initialization Files} [get_files firmware.mem]
}

set_property part $part [current_project]
set_property include_dirs [list [file normalize "$mist_es_dir/rtl/common"]] [current_fileset]

if {$target_type eq "core"} {
  set_property top mist_es_core [current_fileset]
  # Synthesize out-of-context for core-only evaluation
  synth_design -top mist_es_core -part $part -generic SECURE=$secure_val -mode out_of_context -directive PerformanceOptimized
} else {
  set_property top mist_es_arty_a7 [current_fileset]
  synth_design -top mist_es_arty_a7 -part $part -generic SECURE=$secure_val -directive PerformanceOptimized -retiming
  opt_design -directive Explore
  place_design -directive Explore
  phys_opt_design -directive Explore
  route_design -directive Explore
}

# Generate Reports
report_utilization -hierarchical -file "$out_dir/utilization_hierarchical.rpt"
report_utilization -file "$out_dir/utilization.rpt"
report_timing_summary -file "$out_dir/timing.rpt"
report_power -file "$out_dir/power.rpt"

puts "================================================================="
puts "  Synthesis completed for $target_type (SECURE=$secure_val)"
puts "  Reports saved in $out_dir"
puts "================================================================="
