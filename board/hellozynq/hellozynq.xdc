# Common HelloZynq V1/V2 interface, also exercised by the separate UART baseline.
# Board PCB revision and fitted speed/temperature grade are not yet confirmed.
# Use ball locations: V1 KEY labels and expansion-header silk have vendor errata.
set_property PACKAGE_PIN M19 [get_ports clk]
set_property PACKAGE_PIN J20 [get_ports rst_n]
set_property PACKAGE_PIN M17 [get_ports uart_rx]
set_property PACKAGE_PIN L17 [get_ports uart_tx]
set_property PACKAGE_PIN P20 [get_ports {led[0]}]
set_property PACKAGE_PIN P21 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk rst_n uart_rx uart_tx led[*]}]
create_clock -name board_clk -period 20.000 [get_ports clk]

# External UART is asynchronous; the UART RTL synchronizes RX. The board button
# asserts reset asynchronously and the top synchronizes release after MMCM lock.
# These exceptions end at the external interface; internal paths stay timed.
set_false_path -from [get_ports {rst_n uart_rx}]
set_false_path -to [get_ports {uart_tx led[*]}]
