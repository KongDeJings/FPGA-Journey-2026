# ========================== 未用引脚设置 ==========================
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]

# ========================== 系统时钟（50MHz） ==========================
set_property PACKAGE_PIN Y18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

# ========================== 低有效复位按键 ==========================
set_property PACKAGE_PIN B21 [get_ports key_in]
set_property IOSTANDARD LVCMOS33 [get_ports key_in]

# ========================== PHY 复位输出 ==========================
set_property PACKAGE_PIN V22 [get_ports phy_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports phy_rst_n]

# ==========================LED 状态指示 ==========================
set_property PACKAGE_PIN M22 [get_ports led[0]]
set_property PACKAGE_PIN N22 [get_ports led[1]]
set_property PACKAGE_PIN L21 [get_ports led[2]]
set_property PACKAGE_PIN K21 [get_ports led[3]]
set_property PACKAGE_PIN K22 [get_ports led[4]]
set_property PACKAGE_PIN J22 [get_ports led[5]]
set_property PACKAGE_PIN H22 [get_ports led[6]]
set_property PACKAGE_PIN M21 [get_ports led[7]]


set_property IOSTANDARD LVCMOS33 [get_ports led[0]]
set_property IOSTANDARD LVCMOS33 [get_ports led[1]]
set_property IOSTANDARD LVCMOS33 [get_ports led[2]]
set_property IOSTANDARD LVCMOS33 [get_ports led[3]]
set_property IOSTANDARD LVCMOS33 [get_ports led[4]]
set_property IOSTANDARD LVCMOS33 [get_ports led[5]]
set_property IOSTANDARD LVCMOS33 [get_ports led[6]]
set_property IOSTANDARD LVCMOS33 [get_ports led[7]]
# ========================== RGMII 发送接口 ==========================
set_property PACKAGE_PIN U22 [get_ports rgmii_tx_clk]
set_property PACKAGE_PIN AA19 [get_ports rgmii_tx_en]
set_property PACKAGE_PIN U21 [get_ports {rgmii_txd[0]}]
set_property PACKAGE_PIN W22 [get_ports {rgmii_txd[1]}]
set_property PACKAGE_PIN W21 [get_ports {rgmii_txd[2]}]
set_property PACKAGE_PIN Y22 [get_ports {rgmii_txd[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports rgmii_tx_clk]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_tx_en]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_txd[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_txd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_txd[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_txd[3]}]

# ========================== RGMII 接收接口 ==========================
set_property PACKAGE_PIN T21 [get_ports rgmii_rx_clk]
set_property PACKAGE_PIN AB18 [get_ports rgmii_rxdv]
set_property PACKAGE_PIN V17 [get_ports {rgmii_rxd[0]}]
set_property PACKAGE_PIN V18 [get_ports {rgmii_rxd[1]}]
set_property PACKAGE_PIN P19 [get_ports {rgmii_rxd[2]}]
set_property PACKAGE_PIN R19 [get_ports {rgmii_rxd[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rx_clk]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rxdv]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_rxd[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_rxd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_rxd[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_rxd[3]}]

# 允许将 gmii_rx_clk_i 从普通 IO 直接连入 BUFG（已用 BUFG 处理）

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets u_ethernet_top_rgmii/ETHERNET_CLK_PLL/inst/gmii_rx_clk_i_gmii_rx_clk_125m_pll_add_90_phase] 


