# Scoped detailed routing (vibeic fork): `detailed_route -nets {...}` routes
# ONLY the named nets and leaves every other net's dbWire BYTE-IDENTICAL.
#
# The measurement is bytes, not geometry and not a net count. A whole-design
# route that happened to re-lay an identical path would still destroy and
# re-encode the wire, and "the DEF looks the same" would hide it. So every
# non-special net's (opcode, data) stream is read back through dbWire's own
# raw accessors before and after, and compared by MEMBERSHIP: which names
# changed, not how many.
#
# Negative control for this test: drop the `-nets` argument from the second
# detailed_route below. It is the same command this fork changed, so the check
# is proven in both directions by a one-word edit.
source "helpers.tcl"

proc wire_signature { net } {
  set wire [$net getWire]
  if { $wire == "NULL" } {
    return "NOWIRE"
  }
  set n [$wire length]
  set sig "len=$n"
  for { set i 0 } { $i < $n } { incr i } {
    append sig " [$wire getOpcode $i]:[$wire getData $i]"
  }
  return $sig
}

proc all_signatures { block } {
  set sigs [dict create]
  foreach net [$block getNets] {
    if { [$net isSpecial] } {
      continue
    }
    dict set sigs [$net getName] [wire_signature $net]
  }
  return $sigs
}

read_lef testcase/ispd18_sample/ispd18_sample.input.lef
read_def testcase/ispd18_sample/ispd18_sample.input.def
read_guides testcase/ispd18_sample/ispd18_sample.input.guide
set_routing_layers -signal Metal1-Metal9
detailed_route -verbose 0

set block [ord::get_db_block]
set before [all_signatures $block]

# TWO nets lose their detailed wire, exactly as a post-route antenna repair
# leaves the nets it put diodes on -- and then only ONE of them is named.
#
# The second one is what makes this test able to fail. On a design this small
# every net comes back byte-identical from a whole-design route anyway (11
# nets, no congestion, and the wire encoder is deterministic), so byte-identity
# alone would be green with or without the fix. An unrouted net that was not
# named must still be unrouted afterwards: that is the half of the contract
# only -nets can keep, and a whole-design route breaks it every time.
set target "net1231"
set target_net [$block findNet $target]
odb::dbWire_destroy [$target_net getWire]

# Deterministic and not hand-picked: the first routable, wired net in name
# order that is not the target.
set bystander ""
foreach name [lsort [dict keys $before]] {
  if { $name eq $target } {
    continue
  }
  set n [$block findNet $name]
  if { [$n getWire] eq "NULL" } {
    continue
  }
  if { [llength [$n getITerms]] + [llength [$n getBTerms]] < 2 } {
    continue
  }
  set bystander $name
  break
}
if { $bystander eq "" } {
  puts "SCOPED_SETUP_FAILED: no bystander net found"
  exit 1
}
set bystander_net [$block findNet $bystander]
odb::dbWire_destroy [$bystander_net getWire]
puts "SCOPED_TARGET_BEFORE: [wire_signature $target_net]"
puts "SCOPED_BYSTANDER: $bystander"
puts "SCOPED_BYSTANDER_BEFORE: [wire_signature $bystander_net]"

detailed_route -verbose 0 -nets [list $target]

set after [all_signatures $block]

set identical 0
set changed {}
foreach name [lsort [dict keys $before]] {
  if { $name eq $target || $name eq $bystander } {
    continue
  }
  if { [dict get $before $name] eq [dict get $after $name] } {
    incr identical
  } else {
    lappend changed $name
  }
}

puts "SCOPED_NETS_TOTAL: [dict size $before]"
puts "SCOPED_TARGET_REWIRED: [expr { [dict get $after $target] ne "NOWIRE" }]"
# The load-bearing line. 0 here means the router honoured the scope; 1 means it
# routed a net it was not given.
puts "SCOPED_BYSTANDER_REWIRED: [expr { [dict get $after $bystander] ne "NOWIRE" }]"
puts "SCOPED_OTHERS_IDENTICAL: $identical"
puts "SCOPED_OTHERS_CHANGED: [llength $changed] -- [join $changed {, }]"
