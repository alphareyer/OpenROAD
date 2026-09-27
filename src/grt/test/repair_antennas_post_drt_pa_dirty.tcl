# Post-detailed-route repair_antennas reports every net whose detailed wire it
# destroyed. Placed diodes abut their neighbours (no placement padding), so the
# pin access update inside the incremental reroute rewrites the neighbours'
# access points, which marks their nets dirty; updateDirtyNets() then drops
# those nets' wires without rerouting them. grt::repaired_net_names must name
# them, so that a scoped detailed_route of exactly that set leaves no signal
# net unrouted.
source "helpers.tcl"
suppress_message DRT 33
suppress_message DRT 36
suppress_message DRT 167
suppress_message DRT 168
suppress_message DRT 178
suppress_message DRT 179
suppress_message DRT 349
read_liberty "sky130hs/sky130hs_tt.lib"
read_lef "sky130hs/sky130hs.tlef"
read_lef "sky130hs/sky130hs_std_cell.lef"
read_def "gcd_sky130.def"

set_global_routing_layer_adjustment met2-met3 0.15
set_routing_layers -signal met1-met3
global_route

detailed_route -verbose 0

proc unwired_nets { } {
  set unwired {}
  foreach net [[ord::get_db_block] getNets] {
    if { [$net isSpecial] || [$net getSigType] == "POWER"
         || [$net getSigType] == "GROUND" } {
      continue
    }
    if { [llength [$net getITerms]] + [llength [$net getBTerms]] < 2 } {
      continue
    }
    if { [$net isConnectedByAbutment] } {
      continue
    }
    if { [$net getWire] == "NULL" } {
      lappend unwired [$net getName]
    }
  }
  return [lsort $unwired]
}

puts "unwired before repair: [llength [unwired_nets]]"
repair_antennas
set unwired [unwired_nets]
set reported [lsort [grt::repaired_net_names]]
set unreported {}
foreach net $unwired {
  if { [lsearch -exact $reported $net] < 0 } {
    lappend unreported $net
  }
}
puts "unwired after repair: [llength $unwired]"
puts "reported for re-route: [llength $reported]"
puts "unwired and not reported: [llength $unreported] $unreported"

detailed_route -verbose 0 -nets $reported
puts "unwired after the scoped re-route: [llength [unwired_nets]]"
