# SPDX-License-Identifier: BSD-3-Clause
# Cell-scoped SDC limits in OpenROAD's physical/Liberty network adapter.
# Neutral fixture: CORE_BUF slews at 0.5 ns, IO_BUF at 2 ns. NATIVE_BUF
# intentionally violates its native 0.25 ns bound before any SDC is applied.
# No golden log or pointer-address output: the final success marker is pass.
set here [file dirname [file normalize [info script]]]
read_lef $here/cell_slew_scope.lef
read_liberty $here/cell_slew_scope.lib
read_verilog $here/cell_slew_scope.v
link_design top
set_input_transition 0.1 [get_ports i]
set_load 0.1 [get_ports {o p}]

set failures {}
proc fail { label detail } {
  global failures
  lappend failures $label
  puts "FAIL $label: $detail"
}
proc violators { { kind -max_slew } } {
  sta::redirect_string_begin
  report_check_types $kind -violators -digits 6
  set report [sta::redirect_string_end]
  set pins {}
  foreach line [split $report "\n"] {
    if { [string first "(VIOLATED)" $line] >= 0 } {
      lappend pins [lindex $line 0]
    }
  }
  return [lsort -unique $pins]
}
proc expect { label wanted { kind -max_slew } } {
  set got [violators $kind]
  set wanted [lsort $wanted]
  if { $got ne $wanted } {
    fail $label "got {$got}, expected {$wanted}"
  }
}
proc expect_includes { label wanted } {
  set got [violators]
  foreach pin $wanted {
    if { $pin ni $got } {
      fail $label "missing {$pin} in {$got}"
    }
  }
}

set core_lib [[lindex [get_lib_cells */CORE_BUF] 0] cell]
set core_db [[lindex [get_cells u_core] 0] cell]
set native_lib [[lindex [get_lib_cells */NATIVE_BUF] 0] cell]
set native_db [[lindex [get_cells u_native] 0] cell]
if { $core_lib eq $core_db || $native_lib eq $native_db } {
  fail distinct_keys "test did not exercise the physical/Liberty cell distinction"
}

# Baseline and a benign core restriction leave the native and IO behavior alone.
expect native_no_sdc {u_native/Y}
set_max_transition 0.75 $core_lib
expect library_key_good {u_native/Y}
set_max_transition 0.25 $core_lib
expect library_key_bad {u_core/Y u_native/Y}
set_max_transition 0.75 $core_lib
expect library_key_restored {u_native/Y}

# Keep the other key loose so neither test can borrow its result from the other.
set_max_transition 0.75 $core_db
expect network_key_good {u_native/Y}
set_max_transition 0.25 $core_db
expect network_key_bad {u_core/Y u_native/Y}
set_max_transition 0.75 $core_db
expect network_key_restored {u_native/Y}

# The core output drives one 0.01 pF IO input. Either cell identity's
# tighter limit must win, and restoring it must remove the violation.
# Exact violation sets also reject constraint leakage into IO/native cells.
expect capacitance_native_no_sdc {} -max_capacitance
set_max_capacitance 0.1 $core_lib
set_max_capacitance 0.005 $core_db
expect capacitance_network_tighter {u_core/Y} -max_capacitance
set_max_capacitance 0.1 $core_db
expect capacitance_network_restored {} -max_capacitance
set_max_capacitance 0.005 $core_lib
expect capacitance_library_tighter {u_core/Y} -max_capacitance
set_max_capacitance 0.1 $core_lib
expect capacitance_library_restored {} -max_capacitance

# The same output has fanout load 1 from the explicit Liberty default.
expect fanout_native_no_sdc {} -max_fanout
set_max_fanout 2 $core_lib
set_max_fanout 0.5 $core_db
expect fanout_network_tighter {u_core/Y} -max_fanout
set_max_fanout 2 $core_db
expect fanout_network_restored {} -max_fanout
set_max_fanout 0.5 $core_lib
expect fanout_library_tighter {u_core/Y} -max_fanout
set_max_fanout 2 $core_lib
expect fanout_library_restored {} -max_fanout

# A 10 ns cell restriction must not erase a stricter native Liberty restriction.
set_max_transition 10 $native_lib
set_max_transition 10 $native_db
expect native_bound_not_relaxed {u_native/Y}

# A top-level port's own restriction still works and remains independent.
set_max_transition 0.05 [get_ports i]
expect top_port_bad {i u_native/Y}
set_max_transition 0.75 [get_ports i]
expect top_port_restored {u_native/Y}

# A stricter clock restriction must win over the loose cell restrictions.
# Propagation avoids testing ideal-clock exemptions instead of slew limits.
create_clock -name scope_clk -period 10 [get_ports i]
set_propagated_clock [get_clocks scope_clk]
set_max_transition 0.25 [get_clocks scope_clk]
expect_includes clock_bound_not_relaxed {u_core/Y u_io/Y u_native/Y}
delete_clock [get_clocks scope_clk]
expect clock_removed {u_native/Y}

# Current-design constraints also win. IO remains untouched until this
# deliberately global constraint, at which point its 2 ns output must violate.
set_max_transition 0.25 [current_design]
expect_includes design_bound_not_relaxed {u_core/Y u_io/Y u_native/Y}
set_max_transition 10 [current_design]
expect design_restored {u_native/Y}

if { [llength $failures] } {
  puts "FAIL cell_slew_scope: [llength $failures] checks failed"
  exit 1
}
puts "pass"
