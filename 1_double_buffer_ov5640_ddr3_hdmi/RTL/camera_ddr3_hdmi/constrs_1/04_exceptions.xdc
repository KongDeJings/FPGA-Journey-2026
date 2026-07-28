# 系统复位
set_false_path -from [get_ports rst_n]

# 摄像头复位输出
set_false_path -to [get_ports camera_rst_n]

# LED 状态指示
set_false_path -to [get_ports {state_led[*]}]

# SCCB 配置总线（低速控制信号，不需要时序分析）
set_false_path -to [get_ports {sccb_sclk sccb_sdat}]

# DDR3 复位（通常由 MIG 内部处理）
set_false_path -to [get_ports ddr3_reset_n]

#摄像头输入
set_false_path -from [get_ports {camera_data[*] camera_href camera_vsync}]

#HDMI输出
set_false_path -to [get_ports {TMDS_Data_p[*] tmds_clk_p}]