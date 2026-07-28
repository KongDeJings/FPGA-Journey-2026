# 1. 主时钟
create_clock -period 20.000 -name sys_clk [get_ports clk]        
create_clock -period 47.619 -name cam_pclk [get_ports camera_pclk]

# 生成时钟
# Main_PLL 的输出
create_generated_clock -name main_sys_clk \
    -source [get_pins Main_PLL/inst/plle2_adv_inst/CLKIN1] \
    -divide_by 1 \
    [get_pins Main_PLL/inst/plle2_adv_inst/CLKOUT0]

create_generated_clock -name dvi_clk_100m \
    -source [get_pins Main_PLL/inst/plle2_adv_inst/CLKIN1] \
    -multiply_by 2 \
    [get_pins Main_PLL/inst/plle2_adv_inst/CLKOUT1]

create_generated_clock -name ddr3_clk_200m \
    -source [get_pins Main_PLL/inst/plle2_adv_inst/CLKIN1] \
    -multiply_by 4 \
    [get_pins Main_PLL/inst/plle2_adv_inst/CLKOUT2]

# hdmi_PLL 的输出（决定用 74.25MHz）
create_generated_clock -name pixel_clk_74m \
    -source [get_pins hdmi_PLL/inst/mmcm_adv_inst/CLKIN1] \
    -divide_by 1 \
    [get_pins hdmi_PLL/inst/mmcm_adv_inst/CLKOUT0]

create_generated_clock -name pixel_clk_5x \
    -source [get_pins hdmi_PLL/inst/mmcm_adv_inst/CLKIN1] \
    -divide_by 1 \
    [get_pins hdmi_PLL/inst/mmcm_adv_inst/CLKOUT1]

# 3. 异步时钟组
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks sys_clk] \
    -group [get_clocks -include_generated_clocks cam_pclk]