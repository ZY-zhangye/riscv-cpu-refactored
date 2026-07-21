if {$argc != 3} {
    error "usage: vivado -mode batch -source cloud_full_build_to_bit.tcl -tclargs <project-root> <frequency-mhz> <jobs>"
}

set root [file normalize [lindex $argv 0]]
set expected_freq [lindex $argv 1]
set jobs [lindex $argv 2]
set project_file [file join $root JYD2026_Contest_Bitstream.xpr]

if {![file exists $project_file]} {
    error "Vivado project not found: $project_file"
}

set_param general.maxThreads $jobs
open_project $project_file

set pll_ip [get_ips pll]
if {[llength $pll_ip] != 1} {
    error "Expected exactly one pll IP, found [llength $pll_ip]"
}
set actual_freq [get_property CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $pll_ip]
if {[expr {abs(double($actual_freq) - double($expected_freq))}] > 0.01} {
    error "Frequency mismatch: requested ${expected_freq} MHz, project pll is ${actual_freq} MHz"
}

# Make physical optimization explicit instead of relying on settings saved in
# a particular XPR copy.  This preserves the verified flow after migration.
set impl_run [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore $impl_run
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore $impl_run

set out_dir [file join $root cloud_build_results]
file mkdir $out_dir

puts "CLOUD_BUILD_ROOT=$root"
puts "CLOUD_BUILD_FREQ_MHZ=$actual_freq"
puts "CLOUD_BUILD_JOBS=$jobs"
puts "CLOUD_BUILD_PHYS_OPT=[get_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED $impl_run]"
puts "CLOUD_BUILD_POST_ROUTE_PHYS_OPT=[get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED $impl_run]"
puts "CLOUD_BUILD_POST_ROUTE_PHYS_OPT_DIRECTIVE=[get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE $impl_run]"

update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "CLOUD_BUILD_SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis failed: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "CLOUD_BUILD_IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "Implementation failed: $impl_status"
}

open_run impl_1
set core_clock [get_clocks -quiet clk_out2_pll]
if {[llength $core_clock] != 1} {
    error "Expected exactly one clk_out2_pll clock, found [llength $core_clock]"
}
set actual_period [get_property PERIOD $core_clock]
set expected_period [expr {1000.0 / double($expected_freq)}]
puts "CLOUD_BUILD_CLOCK_PERIOD_NS=$actual_period"
puts "CLOUD_BUILD_CLOCK_EXPECTED_PERIOD_NS=$expected_period"
if {[expr {abs(double($actual_period) - $expected_period)}] > 0.005} {
    puts "CLOUD_BUILD_CLOCK_PERIOD_MISMATCH=1"
    error "Clock period mismatch: expected $expected_period ns for ${expected_freq} MHz, got $actual_period ns"
}
puts "CLOUD_BUILD_CLOCK_VALID=1"

report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 -input_pins \
    -file [file join $out_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 50 -path_type full_clock_expanded \
    -file [file join $out_dir critical_paths.rpt]
report_utilization -hierarchical -file [file join $out_dir utilization.rpt]
report_route_status -file [file join $out_dir route_status.rpt]
report_drc -file [file join $out_dir drc.rpt]

write_checkpoint -force [file join $out_dir postroute_cloud.dcp]
write_mem_info -force [file join $out_dir design.mmi]

set bit_src [file join $root JYD2026_Contest_Bitstream.runs impl_1 top.bit]
set bit_dst [file join $out_dir cpu_base_${expected_freq}MHz_cloud.bit]
if {![file exists $bit_src]} {
    error "Expected bitstream not found: $bit_src"
}
file copy -force $bit_src $bit_dst

set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1]
set wns "NA"
set whs "NA"
if {[llength $setup_paths] > 0} {
    set wns [get_property SLACK [lindex $setup_paths 0]]
}
if {[llength $hold_paths] > 0} {
    set whs [get_property SLACK [lindex $hold_paths 0]]
}

puts "CLOUD_BUILD_WNS=$wns"
puts "CLOUD_BUILD_WHS=$whs"
puts "CLOUD_BUILD_BIT=$bit_dst"
puts "CLOUD_BUILD_DCP=[file join $out_dir postroute_cloud.dcp]"
puts "CLOUD_BUILD_MMI=[file join $out_dir design.mmi]"
puts "CLOUD_BUILD_COMPLETE=1"

close_project
exit
