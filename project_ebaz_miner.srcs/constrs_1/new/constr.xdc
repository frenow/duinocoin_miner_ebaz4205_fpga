# Clock de 50.000 MHz (Verifique se sua placa usa o pino N18)
set_property PACKAGE_PIN N18 [get_ports FCLK_CLK0_0]
set_property IOSTANDARD LVCMOS33 [get_ports FCLK_CLK0_0]

# LED Vermelho (Red)
set_property PACKAGE_PIN W13 [get_ports led_red_0]
set_property IOSTANDARD LVCMOS33 [get_ports led_red_0]

# LED Verde (Green)
set_property PACKAGE_PIN W14 [get_ports led_green_0]
set_property IOSTANDARD LVCMOS33 [get_ports led_green_0]

set_property PACKAGE_PIN G20 [get_ports uart_tx_0]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_0]

set_property PACKAGE_PIN J18 [get_ports uart_rx_0]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_0]

#RX J18 e TX G20 -> data2
#RX J14 e TX J15
# Pino 2 do J7 - TX (Data_5 / B19)
# Pino 3 do J7 - RX (Data_6 / D18)
#RX D18 e TX B19 -> UART (Conector J7)