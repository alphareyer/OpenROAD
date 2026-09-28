# Running pdngen twice in one session leaves ONE top port per supply net.
#
# Each pdngen creates a temporary BTerm for a supply net that has none and
# destroys it again when no pin was made on it. dbStaCbk::inDbBTermCreate made
# a new STA top port every time, and inDbBTermDestroy cannot remove one
# (sta::NetworkEdit has no port removal), so every pdngen call added another
# VDD/VSS port: write_verilog then declared them once per call (vibe-ic
# subservient: 5 copies, a netlist no reader accepts). dbNetwork::makeTopPort
# now reuses the port of that name.
source "helpers.tcl"

read_lef Nangate45/Nangate45_tech.lef
read_lef Nangate45/Nangate45_stdcell.lef
read_def nangate_gcd/floorplan.def

add_global_connection -net VDD -pin_pattern VDD -power
add_global_connection -net VSS -pin_pattern VSS -ground

set_voltage_domain -power VDD -ground VSS

define_pdn_grid -name "Core"
add_pdn_stripe -followpins -layer metal1

pdngen
pdngen

set verilog_file [make_result_file pdngen_twice_one_top_port.v]
write_verilog -include_pwr_gnd $verilog_file
set stream [open $verilog_file]
set text [read $stream]
close $stream
foreach net {VDD VSS} {
  puts "$net inout declarations: [regexp -all "\\minout $net\\M" $text]"
}
