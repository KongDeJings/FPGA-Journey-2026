##摄像头输入
#set_input_delay -clock cam_pclk -max 5.0 [get_ports {camera_data[*] camera_href camera_vsync}]
#set_input_delay -clock cam_pclk -min 1.0 [get_ports {camera_data[*] camera_href camera_vsync}]


## HDMI 输出
#set_output_delay -clock pixel_clk_74m -max 0.1 [get_ports {TMDS_Data_p[*] tmds_clk_p}]
#set_output_delay -clock pixel_clk_74m -min 0.05 [get_ports {TMDS_Data_p[*] tmds_clk_p}]

#为什么要注释掉？因为加了画面反而闪烁的厉害，全部set_false_path