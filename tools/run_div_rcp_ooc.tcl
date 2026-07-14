set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
if {[llength $argv] > 0} {
    set out_dir [file normalize [lindex $argv 0]]
} else {
    set out_dir [file normalize {F:/Tools/vivado-ooc/rv32-div-rcp}]
}

file mkdir $out_dir
cd $repo_root

read_verilog -sv rtl/cpu_top/rv32_recip_rom.sv rtl/cpu_top/rv32_div_rcp.sv
read_mem rtl/cpu_top/rv32_recip_lut_f40.mem
read_xdc tools/div_rcp_ooc.xdc

synth_design -top rv32_div_rcp -part xc7k325tffg900-2 \
    -mode out_of_context -flatten_hierarchy rebuilt -resource_sharing off
write_checkpoint -force [file join $out_dir post_synth.dcp]
report_utilization -hierarchical -file [file join $out_dir post_synth_utilization.rpt]
report_ram_utilization -include_path_info -file [file join $out_dir post_synth_ram.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $out_dir post_synth_timing.rpt]

opt_design
place_design
route_design
write_checkpoint -force [file join $out_dir post_route.dcp]
report_route_status -file [file join $out_dir post_route_status.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -nworst 5 \
    -report_unconstrained -check_timing_verbose \
    -file [file join $out_dir post_route_timing.rpt]
report_utilization -hierarchical -file [file join $out_dir post_route_utilization.rpt]
report_ram_utilization -include_path_info -file [file join $out_dir post_route_ram.rpt]
report_design_analysis -timing -setup -max_paths 20 \
    -file [file join $out_dir post_route_path_analysis.rpt]
report_methodology -file [file join $out_dir methodology.rpt]
report_drc -file [file join $out_dir drc.rpt]

set setup_path [get_timing_paths -setup -max_paths 1]
set hold_path [get_timing_paths -hold -max_paths 1]
set setup_slack [get_property SLACK $setup_path]
set hold_slack [get_property SLACK $hold_path]
set dsp_count [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
set bram36_count [llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]]
set bram18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]

puts "DIV_RCP_OOC_RESULT setup_slack=$setup_slack hold_slack=$hold_slack dsp48=$dsp_count ramb36=$bram36_count ramb18=$bram18_count out_dir=$out_dir"
