# Absolute hold ceilings bound physical insertions, including zero; omission
# preserves legacy repair and invalid counts are rejected.
source helpers.tcl

if { ![info exists ::env(VIBEIC_HOLD_COUNT_TEST_CASE)] } {
  foreach case {0 1 2 10 2147483647 omitted reset per_pin invalid} {
    set ::env(VIBEIC_HOLD_COUNT_TEST_CASE) $case
    if { [catch {exec [info nameofexecutable] -no_splash -no_init -exit \
                     [file normalize [info script]]} output] } {
      error "absolute hold count case $case failed: $output"
    }
    puts $output
  }
  unset ::env(VIBEIC_HOLD_COUNT_TEST_CASE)
  puts "pass"
  return
}

read_liberty Nangate45/Nangate45_typ.lib
read_lef Nangate45/Nangate45.lef
read_def repair_hold3.def
create_clock -period 2 clk
set_propagated_clock clk
source Nangate45/Nangate45.rc
set_wire_rc -layer metal1
estimate_parasitics -placement

set block [ord::get_db_block]
set before [llength [$block getInsts]]
set case $::env(VIBEIC_HOLD_COUNT_TEST_CASE)
if { $case in {reset per_pin} } {
  repair_timing -hold -max_buffer_count 0
  if { [llength [$block getInsts]] != $before } {
    error "zero ceiling changed the instance population"
  }
  if { $case == "reset" } {
    repair_timing -hold -allow_setup_violations
  } else {
    rsz::repair_hold_pin [get_pins r3/D] 0.0 0.0 1 1.0 100
  }
  if { [llength [$block getInsts]] <= $before } {
    error "absolute mode leaked into subsequent legacy $case repair"
  }
} elseif { $case == "invalid" } {
  foreach count {-1 2147483648 1.5 nonsense} {
    if { ![catch {repair_timing -hold -max_buffer_count $count} message] } {
      error "accepted invalid absolute count $count"
    }
    if { [string first "non-negative int32" $message] < 0 } {
      error "wrong rejection for $count: $message"
    }
  }
  if { ![catch {repair_timing -setup -max_buffer_count 1} message] } {
    error "accepted a hold count on setup repair"
  }
  if { [llength [$block getInsts]] != $before } {
    error "invalid count changed the design"
  }
} else {
  set args [list -hold -allow_setup_violations]
  if { $case != "omitted" } {
    lappend args -max_buffer_count $case
  }
  repair_timing {*}$args
  set inserted [expr {[llength [$block getInsts]] - $before}]
  if { $case == "omitted" } {
    if { $inserted <= 0 } { error "legacy positive control did not insert" }
  } elseif { $inserted < 0 || $inserted > $case } {
    error "absolute count $case allowed $inserted physical insertions"
  }
  puts "case=$case physical_insertions=$inserted"
}
puts "pass"
