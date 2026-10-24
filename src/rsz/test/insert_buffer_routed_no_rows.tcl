# Routed direct insertion must reject a block without placement rows by name,
# rather than reaching legalCellPos with an uninitialized zero site width.
source "helpers.tcl"

read_liberty Nangate45/Nangate45_typ.lib
read_lef Nangate45/Nangate45.lef
read_verilog rebuffer1.v
link_design top
read_def -floorplan_initialize rebuffer1.def
source Nangate45/Nangate45.rc
set_wire_rc -layer metal3
estimate_parasitics -placement
estimate_parasitics -detailed_routing

set block [ord::get_db_block]
set rows [$block getRows]
foreach row $rows {
  odb::dbRow_destroy $row
}
check "all placement rows removed" {
  llength [$block getRows]
} 0

check_error "routed direct insertion without rows is refused" {
  insert_buffer \
    -net [get_nets u_mid1/u_leaf1/n1] \
    -buffer_cell BUF_X1 \
    -buffer_name no_row_buffer \
    -net_name no_row_net
} DPL-0012

exit_summary
