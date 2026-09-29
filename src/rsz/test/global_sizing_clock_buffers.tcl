# GLOBAL_SIZING with -include_clock_network may resize a clock buffer that
# drives a clock net, but it must keep it in the clock-buffer family (never
# re-master it into a data buffer of the same function), both in the LR loop
# and in presize. A clock-buffer master on a data path is not restricted.
# global_sizing_clock_buffers_presize.tcl runs this flow with presize enabled.
source "helpers.tcl"

if { ![info exists gs_clock_buffers_presize] } {
  set gs_clock_buffers_presize disabled
}

read_liberty Nangate45/Nangate45_typ.lib
read_lef Nangate45/Nangate45.lef
read_def gcd_nangate45_placed.def

create_clock [get_ports clk] -name core_clock -period 0.5
set_max_fanout 100 [current_design]

source Nangate45/Nangate45.rc
set_wire_rc -signal -layer metal3
set_wire_rc -clock -layer metal5

set_cts_config -root_buf CLKBUF_X3 -buf_list CLKBUF_X3
clock_tree_synthesis
set_propagated_clock [all_clocks]

# Put a clock-buffer master on 40 data-path buffers.
set data_clkbufs {}
foreach inst [get_cells *] {
  if { [llength $data_clkbufs] == 40 } {
    break
  }
  if { [get_name [$inst liberty_cell]] == "BUF_X1" } {
    replace_cell $inst CLKBUF_X1
    lappend data_clkbufs $inst
  }
}
estimate_parasitics -placement

proc drives_clock_net { inst } {
  foreach pin [get_pins -of_objects $inst -filter "direction == output"] {
    if { [sta::is_clock $pin] } {
      return 1
    }
  }
  return 0
}

proc report_clock_net_buffers { title } {
  set total 0
  set bad 0
  foreach inst [get_cells *] {
    set cell [$inst liberty_cell]
    if { $cell == "NULL" || ![$cell is_buffer] || ![drives_clock_net $inst] } {
      continue
    }
    incr total
    if { ![string match "CLKBUF_*" [get_name $cell]] } {
      incr bad
      puts "  [get_full_name $inst] -> [get_name $cell]"
    }
  }
  puts "$title: $total clock-net buffers, $bad with a data-buffer master"
}

proc report_data_path_clkbufs { } {
  global data_clkbufs
  set clock_net 0
  set left_family 0
  foreach inst $data_clkbufs {
    incr clock_net [drives_clock_net $inst]
    if { ![string match "CLKBUF_*" [get_name [$inst liberty_cell]]] } {
      incr left_family
    }
  }
  puts "data-path CLKBUF_X1 instances: [llength $data_clkbufs],\
    $clock_net on a clock net, $left_family re-mastered to a data buffer"
}

report_clock_net_buffers "after CTS"

set_global_sizing_config -include_clock_network true \
  -presize_mode $gs_clock_buffers_presize
repair_timing -setup -phases GLOBAL_SIZING
report_clock_net_buffers "after GLOBAL_SIZING"
report_data_path_clkbufs
