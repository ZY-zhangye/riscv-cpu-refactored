# Invoked by run_board.ps1; one isolated project per generated build directory.
# Usage: vivado -mode batch -source scripts/vivado_board.tcl -tclargs build|finish|program config.tcl ?exact_target?
proc board_json_escape {value} {
    return [string map [list \\ \\\\ \" \\\" \n \\n \r \\r \t \\t] $value]
}
proc board_write_result {path values} {
    set numeric {cpu_hz actual_cpu_hz vivado_clock_hz setup_slack_ns hold_slack_ns timing_met drc_met serious_drc_count bitstream_written}
    set fh [open $path w]
    puts $fh "\{"
    set sep ""
    dict for {key value} $values {
        if {$key in $numeric && $value ne ""} {
            puts -nonewline $fh "$sep  \"$key\": $value"
        } else {
            puts -nonewline $fh "$sep  \"$key\": \"[board_json_escape $value]\""
        }
        set sep ",\n"
    }
    puts $fh "\n\}"
    close $fh
}
proc board_main {} {
    global argv
    set mode [lindex $argv 0]
    if {$mode ni {build finish program}} {error "Expected build, finish or program mode"}
    set configuration [file normalize [lindex $argv 1]]
    if {![file isfile $configuration]} {error "Missing generated configuration: $configuration"}
    source $configuration
    if {$part ne "xc7z020clg484-2"} {error "Unexpected candidate part $part; review board identity before changing it"}
    if {$mode eq "program"} {
        set bitfile [file join $build_dir hellozynq.bit]
        if {![file isfile $bitfile]} {error "Missing bitstream: $bitfile"}
        open_hw_manager
        connect_hw_server
        set targets [get_hw_targets]
        set requested_target [lindex $argv 2]
        if {$requested_target ne ""} {
            set targets [get_hw_targets -quiet $requested_target]
            set exact_targets {}
            foreach candidate $targets {
                if {[string equal $candidate $requested_target]} {lappend exact_targets $candidate}
            }
            set targets $exact_targets
        }
        if {[llength $targets] != 1} {error "Expected exactly one JTAG target; found [llength $targets]"}
        current_hw_target [lindex $targets 0]
        open_hw_target
        set devices [get_hw_devices -quiet -filter {PART == "xc7z020"}]
        if {[llength $devices] != 1} {error "Expected exactly one xc7z020 on selected target"}
        current_hw_device [lindex $devices 0]
        refresh_hw_device [current_hw_device]
        if {[get_property PART [current_hw_device]] ne "xc7z020"} {error "Hardware part is not xc7z020"}
        puts "BOARD_DEVICE_CHECK family=xc7z020 package=CLG484_user_report speed_grade=unverified candidate=$part"
        set_property PROGRAM.FILE $bitfile [current_hw_device]
        program_hw_devices [current_hw_device]
        refresh_hw_device [current_hw_device]
        # Zynq-7000 exposes the status field with its full Labtools property
        # name; the shorter BIT13_DONE alias is not present on xc7z020.
        set done_status [get_property REGISTER.CONFIG_STATUS.BIT13_DONE_INTERNAL_SIGNAL_STATUS [current_hw_device]]
        set done_pin [get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN [current_hw_device]]
        if {$done_status ne "1" || $done_pin ne "1"} {
            error "Configuration DONE is not asserted after programming: internal=$done_status pin=$done_pin"
        }
        puts "BOARD_PROGRAM_SUCCESS bitstream=$bitfile target=[current_hw_target]"
        close_hw_manager
        return
    }

    set result [dict create status FAILED part $part cpu_hz $cpu_hz actual_cpu_hz $cpu_hz vivado [version -short] timing_met false drc_met false bitstream_written false]
    set result_file [file join $build_dir vivado_result.json]
    board_write_result $result_file $result
    set build_failed [catch {
        if {$mode eq "finish"} {
            set project_file [file join $build_dir project hellozynq.xpr]
            set routed_file [file join $build_dir project hellozynq.runs impl_1 hellozynq_top_routed.dcp]
            if {![file isfile $project_file] || ![file isfile $routed_file]} {error "Finish requires the existing project and routed checkpoint"}
            open_project $project_file
            if {[get_property PART [current_project]] ne $part} {error "Existing project part differs from build config"}
            if {[get_property PROGRESS [get_runs impl_1]] ne "100%" || ![string match {*route_design Complete*} [get_property STATUS [get_runs impl_1]]]} {
                error "Finish requires a completed route_design run; no synthesis/implementation is launched"
            }
            puts "BOARD_FINISH_REUSE checkpoint=$routed_file"
        } else {
        if {[file exists [file join $build_dir project]]} {error "Refusing to replace an existing board project"}
        if {[llength [get_parts -quiet $part]] != 1} {error "Candidate part is not installed: $part"}
        foreach image [list $inst_init_file $data_init_file] {
            if {![file isfile $image]} {error "Missing initialized firmware memory: $image"}
        }
        create_project hellozynq [file join $build_dir project] -part $part
        set_property target_language Verilog [current_project]
        set_property simulator_language Mixed [current_project]
        # Do not compile simulation divider or board_reference's duplicate my_cpu.
        set sources {}
        foreach item [lsort [glob [file join $root rtl cpu_top *.sv]]] {
            if {[file tail $item] ne "divider.sv"} {lappend sources $item}
        }
        foreach item [lsort [glob [file join $root rtl my_cpu *.sv]]] {lappend sources $item}
        foreach item [lsort [glob [file join $root rtl board *.sv]]] {lappend sources $item}
        if {![file isfile [file join $root rtl board rv32_divider_hw.sv]]} {error "Missing hardware divider"}
        add_files -norecurse $sources
        set core_header [file join $root rtl cpu_top defines.svh]
        add_files -norecurse $core_header
        set_property is_global_include true [get_files $core_header]
        set_property include_dirs [list [file join $root rtl cpu_top] [file join $root rtl my_cpu]] [get_filesets sources_1]
        # All includes use one core defines.svh. The legacy SoC copy has the same
        # guard but is not added to the project or treated as a compilation unit.
        set_property top hellozynq_top [get_filesets sources_1]
        set generic_values [list "CPU_HZ=$cpu_hz" "MMCM_DIVCLK=$mmcm_divclk" "MMCM_MULT=$mmcm_mult" "MMCM_OUT_DIV=$mmcm_out_div" "INST_INIT_FILE=\"$inst_init_file\"" "DATA_INIT_FILE=\"$data_init_file\""]
        set_property generic $generic_values [get_filesets sources_1]
        add_files -fileset constrs_1 -norecurse [file join $root board hellozynq hellozynq.xdc]
        # Explicitly track init files so project reopening retains the dependency.
        add_files -norecurse [list $inst_init_file $data_init_file]
        update_compile_order -fileset sources_1
        set fh [open [file join $build_dir sources.txt] w]
        foreach item [get_files -compile_order sources -used_in synthesis] {puts $fh $item}
        close $fh
        launch_runs synth_1 -jobs $jobs
        wait_on_run synth_1
        if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis did not complete"}
        open_run synth_1
        report_utilization -file [file join $build_dir synthesis_utilization.rpt]
        report_timing_summary -delay_type min_max -file [file join $build_dir synthesis_timing.rpt]
        close_design
        launch_runs impl_1 -to_step route_design -jobs $jobs
        wait_on_run impl_1
        if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation did not complete"}
        }
        open_run impl_1
        # The report command set differs between Vivado releases; remove only
        # regenerable reports rather than relying on optional report -force.
        foreach report {timing_summary utilization drc cdc methodology clocks check_timing} {
            file delete -force [file join $build_dir ${report}.rpt]
        }
        report_timing_summary -delay_type min_max -report_unconstrained -file [file join $build_dir timing_summary.rpt]
        report_utilization -file [file join $build_dir utilization.rpt]
        report_drc -file [file join $build_dir drc.rpt]
        report_cdc -details -file [file join $build_dir cdc.rpt]
        report_methodology -file [file join $build_dir methodology.rpt]
        report_clocks -file [file join $build_dir clocks.rpt]
        check_timing -verbose -file [file join $build_dir check_timing.rpt]
        set setup [get_timing_paths -quiet -delay_type max -max_paths 1]
        set hold [get_timing_paths -quiet -delay_type min -max_paths 1]
        if {[llength $setup] != 1 || [llength $hold] != 1} {error "Missing setup/hold paths"}
        set wns [get_property SLACK [lindex $setup 0]]
        set whs [get_property SLACK [lindex $hold 0]]
        set cpu_clock [get_clocks -quiet -of_objects [get_pins u_cpu_clock_buffer/O]]
        if {[llength $cpu_clock] != 1} {error "Expected one generated CPU clock"}
        set actual_hz [expr {50000000.0 * $mmcm_mult / ($mmcm_divclk * $mmcm_out_div)}]
        if {abs($actual_hz - $cpu_hz) > 0.01} {error "MMCM frequency $actual_hz Hz does not match firmware $cpu_hz Hz"}
        set tool_period [get_property PERIOD $cpu_clock]
        # Vivado may format PERIOD to 0.001 ns; compare periods at that precision.
        if {abs($tool_period - 1000000000.0 / $cpu_hz) > 0.0011} {error "Generated clock period $tool_period ns does not match requested CPU clock"}
        dict set result actual_cpu_hz $actual_hz
        dict set result vivado_clock_hz [expr {1000000000.0 / $tool_period}]
        dict set result setup_slack_ns $wns
        dict set result hold_slack_ns $whs
        dict set result timing_met [expr {$wns >= 0 && $whs >= 0 ? "true" : "false"}]
        set serious [get_drc_violations -quiet -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]
        dict set result serious_drc_count [llength $serious]
        dict set result drc_met [expr {[llength $serious] == 0 ? "true" : "false"}]
        board_write_result $result_file $result
        if {[llength $serious] != 0} {error "Serious DRC violations; no severity is downgraded: $serious"}
        # Negative timing is retained as an explicitly marked frequency experiment.
        # Vivado still performs its normal write_bitstream DRC checks.
        write_bitstream -force [file join $build_dir hellozynq.bit]
        dict set result bitstream_written true
        if {[dict get $result timing_met] eq "true"} {
            dict set result status PASS
            puts "BOARD_BUILD_SUCCESS cpu_hz=$cpu_hz setup=$wns hold=$whs"
        } elseif {$cpu_hz > 50000000} {
            dict set result status EXPERIMENTAL_TIMING_FAIL
            puts "BOARD_BUILD_EXPERIMENTAL cpu_hz=$cpu_hz timing_met=false setup=$wns hold=$whs"
        } else {
            dict set result status BASE_TIMING_FAIL
        }
        board_write_result $result_file $result
        close_project
        if {[dict get $result status] eq "BASE_TIMING_FAIL"} {error "50 MHz baseline failed timing; inspect retained experiment and reports"}
    } message options]
    if {$build_failed} {
        dict set result error $message
        board_write_result $result_file $result
        return -options $options $message
    }
}
if {[catch {board_main} message options]} {
    puts stderr "BOARD_FAILURE: $message"
    if {[dict exists $options -errorinfo]} {puts stderr [dict get $options -errorinfo]}
    exit 1
}
exit 0
