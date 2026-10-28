# Creates the two ILA IPs used by the cache performance counters.
# The script is idempotent and may be sourced from an already open Vivado
# project or executed in batch mode from this directory.

set cache_ila_script_dir [file dirname [file normalize [info script]]]
set cache_ila_opened_project 0

if {[string equal [current_project -quiet] ""]} {
  open_project [file join $cache_ila_script_dir nexys4ddr_scr1.xpr]
  set cache_ila_opened_project 1
}

proc create_cache_perf_ila {module_name probe_count} {
  if {[llength [get_ips -quiet $module_name]] != 0} {
    puts "Cache performance ILA '$module_name' already exists"
    return
  }

  create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
    -module_name $module_name

  set ila_config [list \
    CONFIG.C_ADV_TRIGGER true \
    CONFIG.C_DATA_DEPTH 1024 \
    CONFIG.C_EN_STRG_QUAL 1 \
    CONFIG.C_NUM_OF_PROBES $probe_count]

  for {set probe 0} {$probe < $probe_count} {incr probe} {
    lappend ila_config CONFIG.C_PROBE${probe}_WIDTH 32
  }

  set_property -dict $ila_config [get_ips $module_name]
}

create_cache_perf_ila ila_icache_perf 11
create_cache_perf_ila ila_dcache_perf 15

update_compile_order -fileset sources_1

if {$cache_ila_opened_project} {
  close_project
}
