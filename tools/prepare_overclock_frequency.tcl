if {$argc != 2} {
    error "usage: vivado -mode batch -source prepare_overclock_frequency.tcl -tclargs <project-root> <frequency-mhz>"
}

set root [file normalize [lindex $argv 0]]
set requested_freq [lindex $argv 1]
set project_file [file join $root JYD2026_Contest_Bitstream.xpr]

if {![file exists $project_file]} {
    error "Vivado project not found: $project_file"
}

open_project $project_file
set pll_ip [get_ips pll]
if {[llength $pll_ip] != 1} {
    error "Expected exactly one pll IP, found [llength $pll_ip]"
}

set_property CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $requested_freq $pll_ip
generate_target all $pll_ip
export_ip_user_files -of_objects $pll_ip -no_script -sync -force -quiet

# The OOC PLL checkpoint is otherwise reused even after changing the XCI.
# Re-synthesizing it is required for both the bitstream frequency and the
# generated-clock period used by implementation to change.
set pll_run [get_runs pll_synth_1]
if {[llength $pll_run] != 1} {
    error "Expected exactly one pll_synth_1 run, found [llength $pll_run]"
}
reset_run $pll_run
launch_runs $pll_run -jobs 2
wait_on_run $pll_run
set pll_status [get_property STATUS $pll_run]
if {![string match "*Complete*" $pll_status]} {
    error "PLL synthesis failed: $pll_status"
}

update_compile_order -fileset sources_1

set actual_freq [get_property CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $pll_ip]
puts "OVERCLOCK_PLL_REQUESTED_FREQ=$actual_freq"
puts "OVERCLOCK_PLL_SYNTH_STATUS=$pll_status"
puts "OVERCLOCK_PLL_GENERATION_COMPLETE=1"

close_project
exit
