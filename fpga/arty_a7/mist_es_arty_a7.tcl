# =============================================================================
# mist_es_arty_a7.tcl — Vivado batch flow to a BITSTREAM for the Arty A7-100T.
#   vivado -mode batch -source mist_es_arty_a7.tcl -tclargs <BUILD_DIR>
#
# Before running, build the demo firmware and copy it into <BUILD_DIR> as
# firmware.mem (the RAM $readmemh init):
#   cd sw && ./build_fpga_hello.sh && cp firmware.mem <BUILD_DIR>/firmware.mem
# =============================================================================
set fpga_dir  [file normalize [file dirname [info script]]]
set build_dir [file normalize [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "$fpga_dir/build"}]]
set part      xc7a100tcsg324-1


file mkdir $build_dir
cd $build_dir

set fp [open "$fpga_dir/mist_es_arty_a7.f" r]
while {[gets $fp line] >= 0} {
  set line [string trim $line]
  if {$line eq "" || [string match "#*" $line]} { continue }
  set filepath [file normalize "$fpga_dir/$line"]
  read_verilog -sv [list $filepath]
}
close $fp

read_xdc [list "$fpga_dir/mist_es_arty_a7.xdc"]
set_property part $part [current_project]
set_property top mist_es_arty_a7 [current_fileset]
set_property include_dirs [list [file normalize "$fpga_dir/../../rtl/common"]] [current_fileset]

# firmware.mem must exist in the sw directory
add_files -norecurse [list "$fpga_dir/../../sw/firmware.mem"]
set_property file_type {Memory Initialization Files} [get_files firmware.mem]

synth_design -top mist_es_arty_a7 -part $part -directive PerformanceOptimized -retiming
opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore
report_utilization    -file "$build_dir/util.rpt"
report_timing_summary -file "$build_dir/timing.rpt"
report_power          -file "$build_dir/power.rpt"
write_bitstream -force "$build_dir/mist_es_arty_a7.bit"
puts "DONE: $build_dir/mist_es_arty_a7.bit"
# Program:  openFPGALoader -b arty_a7_100t mist_es_arty_a7.bit
