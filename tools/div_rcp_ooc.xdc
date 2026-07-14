create_clock -name div_clk -period 6.250 [get_ports clk]
set_clock_uncertainty -setup 0.200 [get_clocks div_clk]
set_clock_uncertainty -hold 0.100 [get_clocks div_clk]

set data_inputs [get_ports {req_valid cancel dividend[*] divisor[*] signed_div want_remainder}]
set_input_delay -clock div_clk -max 0.750 $data_inputs
set_input_delay -clock div_clk -min 0.000 $data_inputs
set_output_delay -clock div_clk -max 0.750 [all_outputs]
set_output_delay -clock div_clk -min 0.000 [all_outputs]
set_false_path -from [get_ports rst_n]
