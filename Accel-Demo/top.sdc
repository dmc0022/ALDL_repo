create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
set_false_path -from [get_ports {GSENSOR_SDI GSENSOR_SCLK GSENSOR_SDO GSENSOR_CS_n}]
set_false_path -from [get_ports SW[*]]
set_false_path -to   [get_ports {HEX5[*] HEX4[*] HEX3[*] HEX2[*] HEX1[*] HEX0[*]}]
