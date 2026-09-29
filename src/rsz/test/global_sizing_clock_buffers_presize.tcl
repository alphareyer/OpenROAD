# global_sizing_clock_buffers.tcl with presize to the largest-leakage
# swappable cell before the LR loop: presize must keep a clock-net clock buffer
# in the clock-buffer family too.
source "helpers.tcl"
set gs_clock_buffers_presize max_size_min_vt
source "global_sizing_clock_buffers.tcl"
