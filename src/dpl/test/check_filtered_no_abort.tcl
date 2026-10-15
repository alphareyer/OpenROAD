# Cell filtering and explicit recovery must compose without hiding failures.
source "helpers.tcl"
read_lef Nangate45/Nangate45.lef
read_lef extra.lef
read_def check_fixed_only.def

if { [check_placement -fixed -no_abort] != 0 } {
  error "fixed-only recovery included the stale movable cell"
}
if { [check_placement -placeable -no_abort] <= 0 } {
  error "placeable-only recovery hid an illegal movable cell"
}

set block [ord::get_db_block]
set tap [$block findInst tap1]
$tap setPlacementStatus PLACED
$tap setLocation 3990 2800
$tap setPlacementStatus FIRM
set buf [$block findInst _277_]
$buf setLocation 11400 2800
if { [check_placement -placeable -no_abort] != 0 } {
  error "placeable-only recovery included the fixed-cell violation"
}
if { [check_placement -fixed -no_abort] <= 0 } {
  error "fixed-only recovery hid a fixed-cell violation"
}
if { ![catch {check_placement -fixed} message] || $message != "DPL-0041" } {
  error "fixed-only failure lost its upstream fatal diagnostic: $message"
}
# The legacy three-argument binding retains its no_abort interpretation.
if { [dpl::check_placement_cmd 0 "" 1] <= 0 } {
  error "legacy recovery entry point hid the fixed-cell violation"
}
puts "pass"
