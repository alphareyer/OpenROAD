# Path-group repair must honor the absolute physical insertion ceiling.
source "helpers.tcl"
if { ![info exists ::env(VIBEIC_GROUP_COUNT_CASE)] } {
  foreach case {0 2 omitted} {
    set ::env(VIBEIC_GROUP_COUNT_CASE) $case
    if { [catch {exec [info nameofexecutable] -no_splash -no_init -exit \
                     [file normalize [info script]]} output] } {
      error "path-group hold count case $case failed: $output"
    }
    puts $output
  }
  unset ::env(VIBEIC_GROUP_COUNT_CASE)
  puts "pass"
  return
}
read_liberty Nangate45/Nangate45_typ.lib
read_lef Nangate45/Nangate45.lef
read_def gcd_nangate45_placed.def
create_clock -name core_clock -period 0.65 [get_ports clk]
set_input_delay -clock core_clock 0.05 [all_inputs -no_clocks]
set_input_delay -clock core_clock -min -0.15 [get_ports req_msg*]
set_output_delay -clock core_clock 0.1 [all_outputs]
source Nangate45/Nangate45.rc
set_wire_rc -layer metal3
estimate_parasitics -placement
rsz::resolve_path_group reg2reg

set block [ord::get_db_block]
set before [llength [$block getInsts]]
set case $::env(VIBEIC_GROUP_COUNT_CASE)
set args [list -hold -hold_margin 0.2 -path_group reg2reg]
if { $case != "omitted" } {
  lappend args -max_buffer_count $case
}
repair_timing {*}$args
set inserted [expr {[llength [$block getInsts]] - $before}]
if { $case == "omitted" } {
  if { $inserted <= 2 } { error "unbounded group repair did not exercise the ceiling" }
} elseif { $inserted < 0 || $inserted > $case } {
  error "path-group repair exceeded cap $case with $inserted insertions"
} elseif { $case == 2 && $inserted == 0 } {
  error "bounded group repair did not insert a buffer"
}
puts "case=$case physical_insertions=$inserted"
puts "pass"
