# The post-route min-area repair must judge a routing pad by the WHOLE metal it
# is connected to, however far that metal reaches.
#
# n1's only routing is a 0.23 x 0.23 um met1 pad (0.0529 um^2, below met1's
# AREA 0.083). It overlaps the short vertical leg of u1/Z, an L-shaped pin
# whose long horizontal leg starts 25 dbu above the pad. Pad plus short leg is
# 0.0564 um^2; with the long leg the connected metal is 0.33 um^2, so the pad is
# DRC-clean and must be left alone: before=0 patched=0 after=0.
#
# The repair used to query cell metal in ONE window, the net's own routing
# extent plus one manufacturing-grid step, so the long leg (outside it) was
# never merged. It read 0.069 um^2, "repaired" the clean pad, and on gf180mcuD
# (subservient, the same shape: a Via1 pad that is the net's topmost Metal1
# under an L-shaped output pin) left a 0.01 um same-net notch -- 3 Metal
# Spacing markers on a route that was otherwise verified clean.
source "helpers.tcl"
read_lef sky130hd/sky130hd.tlef
read_lef min_area_pad_on_l_pin.lef
read_def min_area_pad_on_l_pin.def
set drc_file [make_result_file min_area_pad_on_l_pin.drc]
drt::repair_min_area -output_file $drc_file
diff_files $drc_file min_area_pad_on_l_pin.drcok
