# Common setup for direct insert_buffer commands with routed parasitics.
# Each caller is a separate regression so one command cannot initialize OpenDP
# on behalf of another command form.
source "helpers.tcl"

if { ![info exists route_source] || ![info exists insert_form] } {
  error "route_source and insert_form must be set by the calling regression"
}

define_corners fast slow
read_liberty -corner slow Nangate45/Nangate45_slow.lib
read_liberty -corner fast Nangate45/Nangate45_fast.lib
read_lef Nangate45/Nangate45.lef
read_verilog rebuffer1.v
link_design top
read_def -floorplan_initialize rebuffer1.def

source Nangate45/Nangate45.vars
source Nangate45/Nangate45.rc
source $tracks_file
set_wire_rc -layer metal3

if { $route_source == "global" } {
  # rebuffer1.def intentionally leaves top-level pin geometry unspecified.
  # Give the global-router fixture legal pin shapes before routing.
  place_pins -hor_layers metal3 -ver_layers metal2 \
    -corner_avoidance 0 -min_distance 0.12
  set_routing_layers -signal $global_routing_layers
  global_route
  estimate_parasitics -global_routing
  check "global-routing parasitics selected" {
    est::parasitics_source
  } global_routing
} elseif { $route_source == "detailed" } {
  # The direct-insert behavior depends on the selected parasitics source.  Use
  # annotated RC, then select the fork's post-detailed-route source exactly as
  # a read_spef/extract_parasitics flow does.
  estimate_parasitics -placement
  estimate_parasitics -detailed_routing
  check "detailed-routing parasitics selected" {
    est::parasitics_source
  } detailed_routing
} else {
  error "unsupported route_source $route_source"
}

set block [ord::get_db_block]
switch $insert_form {
  after_driver {
    set inserted [insert_buffer \
      -net [get_nets u_mid1/u_leaf1/n1] \
      -buffer_cell BUF_X1 \
      -buffer_name routed_after \
      -net_name routed_after_net]
    check "after-driver buffer name" {
      get_name $inserted
    } u_mid1/u_leaf1/routed_after1
    check "after-driver input net name" {
      get_full_name [get_nets -of_objects \
        [get_pins u_mid1/u_leaf1/routed_after1/A]]
    } u_mid1/u_leaf1/routed_after_net1
    check "after-driver output retains load net" {
      get_full_name [get_nets -of_objects \
        [get_pins u_mid1/u_leaf1/routed_after1/Z]]
    } u_mid1/u_leaf1/n1
  }
  before_load {
    set inserted [insert_buffer \
      -load_pins [get_pins u_mid1/u_leaf1/buf2/A] \
      -buffer_cell BUF_X1 \
      -buffer_name routed_before \
      -net_name routed_before_net]
    check "before-load buffer name" {
      get_name $inserted
    } u_mid1/u_leaf1/routed_before1
    check "before-load output net name" {
      get_full_name [get_nets -of_objects \
        [get_pins u_mid1/u_leaf1/routed_before1/Z]]
    } u_mid1/u_leaf1/routed_before_net1
    check "selected load moved to buffer output" {
      get_full_name [get_nets -of_objects \
        [get_pins u_mid1/u_leaf1/buf2/A]]
    } u_mid1/u_leaf1/routed_before_net1
  }
  before_loads {
    set selected_loads \
      [get_pins {u_mid1/dff_load1/D u_mid1/dff_load2/D}]
    set inserted [insert_buffer \
      -net [get_nets u_mid1/l2_out1] \
      -load_pins $selected_loads \
      -buffer_cell BUF_X1 \
      -buffer_name routed_loads \
      -net_name routed_loads_net]
    check "multiple-load buffer name" {
      get_name $inserted
    } u_mid1/routed_loads1
    check "first selected load moved" {
      get_full_name [get_nets -of_objects [get_pins u_mid1/dff_load1/D]]
    } u_mid1/routed_loads_net1
    check "second selected load moved" {
      get_full_name [get_nets -of_objects [get_pins u_mid1/dff_load2/D]]
    } u_mid1/routed_loads_net1
    check "unselected load remains on original net" {
      get_full_name [get_nets -of_objects [get_pins u_mid1/dff_load3/D]]
    } u_mid1/l2_out1
  }
  default {
    error "unsupported insert_form $insert_form"
  }
}

exit_summary
