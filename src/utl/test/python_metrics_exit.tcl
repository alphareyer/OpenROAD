# openroad -metrics writes the metrics file exactly once when the run ends:
# after a python script ends, after sys.exit(n) (keeping n), after an
# uncaught python exception, and after a tcl script. Each run records
# probe__count = 7 and the file must hold it once, next to one
# flow__warnings__count written when the metrics are finalized.
source "helpers.tcl"

if { [info exists ::env(OPENROAD_EXE)] } {
  set openroad $::env(OPENROAD_EXE)
} else {
  set openroad [info nameofexecutable]
}

proc run_openroad_exit_code { log args } {
  global openroad
  if { [catch { exec $openroad {*}$args >& $log }] } {
    lassign $::errorCode kind pid code
    if { $kind != "CHILDSTATUS" } {
      error "running $openroad failed: $::errorCode"
    }
    return $code
  }
  return 0
}

proc count_matches { pattern text } {
  return [regexp -all -- $pattern $text]
}

proc check_run { name ext body expected_exit } {
  set script [make_result_file "python_metrics_exit_$name.$ext"]
  set json [make_result_file "python_metrics_exit_$name.json"]
  set log [make_result_file "python_metrics_exit_$name.log"]
  set f [open $script w]
  puts $f $body
  close $f
  file delete -force $json

  set args [list -no_splash -no_init -exit -metrics $json]
  if { $ext == "py" } {
    lappend args -python
  }
  lappend args $script
  set code [run_openroad_exit_code $log {*}$args]

  if { [file exists $json] } {
    set f [open $json r]
    set text [read $f]
    close $f
    set probes [count_matches {"probe__count": 7} $text]
    set finals [count_matches {"flow__warnings__count":} $text]
  } else {
    set probes "no file"
    set finals "no file"
  }
  puts "$name: exit $code, probe__count $probes, flow__warnings__count $finals"
  return [expr { $code == $expected_exit && $probes == 1 && $finals == 1 }]
}

set ok 1
catch { exec $openroad -help 2>@1 } help
if { [string first "-python" $help] < 0 } {
  puts "skip: $openroad is built without -python"
} else {
  set probe "import utl\nutl.metric_integer(\"probe__count\", 7)"
  if { ![check_run python_end py $probe 0] } {
    set ok 0
  }
  if { ![check_run python_sys_exit py "$probe\nimport sys\nsys.exit(3)" 3] } {
    set ok 0
  }
  if { ![check_run python_raise py "$probe\nraise RuntimeError(\"probe\")" 1] } {
    set ok 0
  }
  # A script that builds its own openroad.Tech() makes it the current
  # OpenRoad, and Python frees it before the exit handler runs; the metrics
  # of the OpenRoad main() created must still be written, without a crash.
  if { ![check_run python_own_tech py "$probe\nimport openroad\nt = openroad.Tech()\ndel t" 0] } {
    set ok 0
  }
  if { ![check_run python_own_tech_kept py "$probe\nimport openroad\nt = openroad.Tech()" 0] } {
    set ok 0
  }
  if { ![check_run tcl_end tcl "utl::metric_integer \"probe__count\" 7" 0] } {
    set ok 0
  }
}

if { $ok } {
  puts "pass"
} else {
  puts "fail"
}
