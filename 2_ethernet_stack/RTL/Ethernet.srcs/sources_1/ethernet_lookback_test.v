`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/13 20:54:55
// Design Name: 
// Module Name: ethernet_loopback_test
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: UDP 回环测试顶层
// 
// Dependencies: ethernet_top
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module ethernet_loopback_test

#(

//=========================协议重要参数配置=====================
    parameter                           ETH_CLOCK_FREQUENCY             = 125_000_000          ,  // 计数1s所需周期数(时钟频率)  

    parameter                           PC_MAC                      = 48'h00E2_6969_EC7D   ,  // MAC: 00-E2-69-69-EC-7D
    parameter                           PC_IP                       = 32'hC0A8_0003        ,  // IP: 192.168.0.3
//    parameter                           FPGA_MAC                    = 48'h001A_2B3C_4D5E   ,  // MAC 00-1A-2B-3C-4D-5E 自定义
    parameter                           FPGA_MAC                    = 48'h020A_353C_4D5E   ,  // MAC 02-0A-35-3C-4D-5E 这是xilinx专用mac，可被wireshark识别到
    parameter                           FPGA_IP                     = 32'hC0A8_000A        ,  // 192.168.0.10
    parameter                           DST_PORT                    = 16'd54321            ,  // PC   端口
    parameter                           SRC_PORT                    = 16'd54322            ,  // FPGA 端口
    parameter                           PREAMBLE                    = 8'h55                ,
    parameter                           SFD                         = 8'hD5                ,

    parameter                           ETH_TYPE_IPV4               = 16'h0800             ,
    parameter                           ETH_TYPE_ARP                = 16'h0806             ,


    parameter                           IP_MARK                     = 16'h0                ,//标识
    parameter                           IP_FRAG_OFFSET              = 16'h0                ,//标志+片偏移
    parameter                           IP_VER                      = 8'h45                ,// 版本+首部长度
    parameter                           IP_SERVICE                  = 8'h00                ,// 服务类型
    parameter                           IP_TTL                      = 8'h80                ,// TTL生存时间

//=========================协议参数定义:发送部分========================

//ARP
    parameter                           ARP_PROTO_TYPE_IPV4         = 16'h0800             ,// IPv4，arp报文独有
    parameter                           ARP_HW_TYPE_ETHERNET        = 16'h0001             ,// 以太网
    parameter                           ARP_HW_SIZE                 = 8'h06                ,// MAC地址长度
    parameter                           ARP_PROTO_SIZE              = 8'h04                ,// IP地址长度
    parameter                           ARP_OPCODE_REQUEST          = 16'h0001             ,// ARP请求
    parameter                           ARP_OPCODE_REPLY            = 16'h0002             ,// ARP响应
//ICMP
    parameter                           ICMP_IP_PROTOCOL            = 8'h01                ,// 上层协议，ICMP固定1
    parameter                           ICMP_TYPE                   = 8'h00                ,// ICMP类型，0-回显应答
    parameter                           ICMP_CODE                   = 8'h00                ,// ICMP代码

//UDP
    parameter                           UDP_IP_PROTOCOL             = 8'h11                ,//上层协议，UDP固定17
    parameter                           UDP_VERC                    = 16'h0                ,//UDP校验和，不做校验，空置为0
    parameter                           UDP_PACKET_BYTE_SIZE        = 32                  ,//UDP单次发送512字节
//IFG
    parameter                           IFG_COUNT                   = 15                   ,//帧间间隔的周期数，96bit时间，要求12个字节，我多留了裕量，15个字节
//=========================协议参数定义:接收部分，arp——cache========================

    parameter                           ARP_LENGTH                  = 52                   ,
    parameter                           CACHE_SIZE                  = 16                   ,
    parameter                           AGING_SEC                   = 60                   ,// 老化时间（秒）
    parameter                           ICMP_ECHO_REQUEST           = 8'h08                ,//收到别人的请求是0x08
    parameter                           ICMP_ECHO_REPLY             = 8'h00                ,//回复别人的请求是00
    parameter                           IP_CHECKSUM_CHECK_VALID     = 0                    ,//UDP和ICMP校验和是否开启信号，0为关闭，1为开启，PC发的包默认关闭，故此参数为0

//PHY上电初始化
    parameter                           SYS_CLK_FREQ                = 50_000_000           ,// 系统时钟频率
    parameter                           PHY_RST_HOLD_MS             = 25                   ,// PHY硬复位保持时间     25ms
    parameter                           PHY_INIT_WAIT_MS            = 100                   // PHY复位释放后等待初始化完成时间，模拟校准+RXC锁定   100ms
)
(
    // ==================== 系统时钟与复位 ====================
    input                               sys_clk                    ,// 板载50Mhz主时钟
    input                               key_in                     ,// 低有效复位
    
    // ==================== PHY 接口 ====================
    // RGMII 发送接口
    output                              rgmii_tx_clk               ,
    output               [   3: 0]      rgmii_txd                  ,
    output                              rgmii_tx_en                ,

    // RGMII 接收接口
    input                               rgmii_rx_clk               ,
    input                [   3: 0]      rgmii_rxd                  ,
    input                               rgmii_rxdv                 ,

    output                              phy_rst_n                  ,
    output               [   7: 0]      led                        //观察端口，快速查看是否正常通讯
    );

//===============================================================================================================   
//内部连线与寄存器
    wire                                udp_frame_rx_done_valid    ;
    wire                 [  10: 0]      udp_rx_payload_count_gray_sync  ;
    wire                                rd_rst_busy_udp_rx_fifo    ;
    wire                 [   7: 0]      dout_udp_rx_fifo           ;
    wire                                empty_udp_rx_fifo          ;
    wire                                 rd_en_udp_rx_fifo          ;

    wire                 [  7: 0]      din_udp_tx_fifo            ;
    wire                                wr_en_udp_tx_fifo          ;
    wire                                full_udp_tx_fifo           ;
    wire                 [   10: 0]      wr_data_count_udp_tx_fifo  ;
    wire                                wr_rst_busy_udp_tx_fifo    ;

    wire                                udp_payload_count_valid    ;//这是一个电平信号，拉高使用外部的payload字节数，为低时，使用参数化的字节数
    assign                              udp_payload_count_valid     = 1                    ;
    wire                 [  10: 0]      udp_payload_count          ;

    wire                                udp_frame_rx_done_valid_synced  ;
    wire                                clk_125m                   ;
//===============================================================================================================
//逻辑输出
//==========================================================
//125MHz 域：脉冲展宽为电平
    reg                                 udp_rx_done_level_125      ;
    reg                  [   4: 0]      stretch_cnt                ;// 5位计数器，最大31

always @(posedge clk_125m or negedge key_in) begin
    if (!key_in) begin
        udp_rx_done_level_125 <= 1'b0;
        stretch_cnt           <= 5'd0;
    end else begin
        if (udp_frame_rx_done_valid) begin                      
            udp_rx_done_level_125 <= 1'b1;
            stretch_cnt           <= 5'd20;                         // 展宽 20*8ns = 160ns，确保50MHz能采到
        end 
        else if (stretch_cnt > 0) begin
            stretch_cnt <= stretch_cnt - 1'b1;
        end
         else begin
            udp_rx_done_level_125 <= 1'b0;                        
        end
    end
end

//xpm_cdc_single：将展宽电平同步到50MHz
    wire                                udp_rx_done_level_synced   ;

xpm_cdc_single #(
    .DEST_SYNC_FF                       (3                         ),// 同步深度，建议≥2
    .INIT_SYNC_FF                       (0                         ),
    .SIM_ASSERT_CHK                     (0                         ),
    .SRC_INPUT_REG                      (0                         ) // 不额外打拍，直接送
) u_udp_rx_done_level_cdc (
    .dest_out                           (udp_frame_rx_done_valid_synced),
    .dest_clk                           (sys_clk                   ),
    .src_clk                            (clk_125m                  ),
    .src_in                             (udp_rx_done_level_125     ) 
);

//==========================================================
//异步复位同步释放

wire rst_n_50m;      // 同步到 sys_clk 
wire rst_n_125m;     // 同步到 clk_125m

// 50MHz 域同步
xpm_cdc_async_rst #(
    .DEST_SYNC_FF                       (4                         ),// 同步级数，一般≥2，这里用4更保守
    .INIT_SYNC_FF                       (0                         ),// 仿真时不初始化同步器
    .RST_ACTIVE_HIGH                    (0                         ) // 复位信号为低有效
) u_rst_sync_50m (
    .dest_arst                          (rst_n_50m                 ),// 输出：同步释放后的复位（低有效）
    .dest_clk                           (sys_clk                   ),// 目标时钟
    .src_arst                           (key_in                    ) // 输入：异步复位（低有效）
);

// 125MHz 域同步
xpm_cdc_async_rst #(
    .DEST_SYNC_FF                       (4                         ),
    .INIT_SYNC_FF                       (0                         ),
    .RST_ACTIVE_HIGH                    (0                         ) 
) u_rst_sync_125m (
    .dest_arst                          (rst_n_125m                ),
    .dest_clk                           (clk_125m                  ),
    .src_arst                           (key_in                    ) 
);
//===============================================================================================================
// 例化以太网协议栈


ethernet_top_rgmii#(
    .ETH_CLOCK_FREQUENCY                (ETH_CLOCK_FREQUENCY       ),
    .PC_MAC                             (PC_MAC                    ),
    .PC_IP                              (PC_IP                     ),
    .FPGA_MAC                           (FPGA_MAC                  ),
    .FPGA_IP                            (FPGA_IP                   ),
    .DST_PORT                           (DST_PORT                  ),
    .SRC_PORT                           (SRC_PORT                  ),
    .PREAMBLE                           (PREAMBLE                  ),
    .SFD                                (SFD                       ),
    .ETH_TYPE_IPV4                      (ETH_TYPE_IPV4             ),
    .ETH_TYPE_ARP                       (ETH_TYPE_ARP              ),
    .IP_MARK                            (IP_MARK                   ),
    .IP_FRAG_OFFSET                     (IP_FRAG_OFFSET            ),
    .IP_VER                             (IP_VER                    ),
    .IP_SERVICE                         (IP_SERVICE                ),
    .IP_TTL                             (IP_TTL                    ),
    .ARP_PROTO_TYPE_IPV4                (ARP_PROTO_TYPE_IPV4       ),
    .ARP_HW_TYPE_ETHERNET               (ARP_HW_TYPE_ETHERNET      ),
    .ARP_HW_SIZE                        (ARP_HW_SIZE               ),
    .ARP_PROTO_SIZE                     (ARP_PROTO_SIZE            ),
    .ARP_OPCODE_REQUEST                 (ARP_OPCODE_REQUEST        ),
    .ARP_OPCODE_REPLY                   (ARP_OPCODE_REPLY          ),
    .ICMP_IP_PROTOCOL                   (ICMP_IP_PROTOCOL          ),
    .ICMP_TYPE                          (ICMP_TYPE                 ),
    .ICMP_CODE                          (ICMP_CODE                 ),
    .UDP_IP_PROTOCOL                    (UDP_IP_PROTOCOL           ),
    .UDP_VERC                           (UDP_VERC                  ),
    .UDP_PACKET_BYTE_SIZE               (UDP_PACKET_BYTE_SIZE      ),
    .IFG_COUNT                          (IFG_COUNT                 ),
    .ARP_LENGTH                         (ARP_LENGTH                ),
    .CACHE_SIZE                         (CACHE_SIZE                ),
    .AGING_SEC                          (AGING_SEC                 ),
    .ICMP_ECHO_REQUEST                  (ICMP_ECHO_REQUEST         ),
    .ICMP_ECHO_REPLY                    (ICMP_ECHO_REPLY           ),
    .SYS_CLK_FREQ                       (SYS_CLK_FREQ              ),
    .PHY_RST_HOLD_MS                    (PHY_RST_HOLD_MS           ),
    .PHY_INIT_WAIT_MS                   (PHY_INIT_WAIT_MS          ),
    .IP_CHECKSUM_CHECK_VALID            (IP_CHECKSUM_CHECK_VALID   ),
    .UDP_LOOKBACK_TEST_ENABLE           (1 ) //这个参数决定是否进行UDP回环实验，它改变的是udp_payload的长度  ,默认为0，等于1则为回环逻辑      

)
 u_ethernet_top_rgmii(

// ==================== 系统时钟与复位 ====================
    .sys_clk                            (sys_clk                   ),// (input)// 板载50Mhz主时钟
    .key_in                             (rst_n_125m                ),// (input)// 低有效复位
    .clk125m                            (clk_125m                  ),// (output)用于同步信号，使用可忽略
// ==================== PHY 接口 ====================
// RGMII 发送接口
    .rgmii_tx_clk                       (rgmii_tx_clk              ),// (output)
    .rgmii_txd                          (rgmii_txd                 ),// (output)
    .rgmii_tx_en                        (rgmii_tx_en               ),// (output)
// RGMII 接收接口
    .rgmii_rx_clk                       (rgmii_rx_clk              ),// (input)// PHY恢复的最原始的时钟信号
    .rgmii_rxd                          (rgmii_rxd                 ), // (input)
    .rgmii_rxdv                         (rgmii_rxdv                ), // (input)
    .phy_rst_n                          (phy_rst_n                 ), // (output)
    .led                                (led                       ), // (output)// 观察端口，快速查看是否正常通讯
// ==================== UDP数据流接口 ====================
//以太网接收到的payload,这个fifo在接收模块中，给消费者读接口
    .udp_frame_rx_done_valid            (udp_frame_rx_done_valid   ),// (output)
    .udp_rx_payload_count_gray_sync     (udp_rx_payload_count_gray_sync),// (output)// 接收到了多少个payload数据，到时候原样读出
    .rd_rst_busy_udp_rx_fifo            (rd_rst_busy_udp_rx_fifo   ),// (output)
    .dout_udp_rx_fifo                   (dout_udp_rx_fifo          ),// (output)
    .empty_udp_rx_fifo                  (empty_udp_rx_fifo         ),// (output)
    .rd_en_udp_rx_fifo                  (rd_en_udp_rx_fifo         ),// (input)
    .rd_clk_udp_rx_fifo                 (sys_clk                   ),// (input)// 读取fifo的读时钟
//应用端写接口，写入fifo，udp发送端通过读fifo，获取payload数据
    .wr_clk_udp_tx_fifo                 (sys_clk                   ),// (input)// udp发送fifo的写时钟
    .din_udp_tx_fifo                    (din_udp_tx_fifo           ),// (input)
    .wr_en_udp_tx_fifo                  (wr_en_udp_tx_fifo         ),// (input)
    .full_udp_tx_fifo                   (full_udp_tx_fifo          ),// (output)
    .wr_data_count_udp_tx_fifo          (wr_data_count_udp_tx_fifo ),// (output)
    .wr_rst_busy_udp_tx_fifo            (wr_rst_busy_udp_tx_fifo   ),// (output)
//发送UDP数据时需要的payload长度及参数    
    .udp_payload_count_valid            (udp_payload_count_valid   ),// (input)//注意！！这是125M时钟域，必须CDC!!!!!//这是一个电平信号，拉高使用外部的payload字节数，为低时，使用参数化的字节数
    .udp_payload_count                  (udp_payload_count         )// (input)///注意！！这是125M时钟域，必须CDC!!!!!
);




udp_lookback u_udp_lookback(
// ==================== 系统时钟与复位 ====================
    .clk                                (sys_clk                   ),// (input)
    .rst_n                              (rst_n_50m                 ),// (input)
// ==================== UDP数据流接口 ====================
//以太网接收到的payload,这个fifo在接收模块中，给消费者读接口
    .udp_frame_rx_done_valid            (udp_frame_rx_done_valid_synced),// (input)
    .udp_rx_payload_count_gray_sync     (udp_rx_payload_count_gray_sync),// (input)// 接收到了多少个payload数据，到时候原样读出
    .rd_rst_busy_udp_rx_fifo            (rd_rst_busy_udp_rx_fifo   ),// (input)
    .dout_udp_rx_fifo                   (dout_udp_rx_fifo          ),// (input)
    .empty_udp_rx_fifo                  (empty_udp_rx_fifo         ),// (input)
    .rd_en_udp_rx_fifo                  (rd_en_udp_rx_fifo         ),// (output)
//应用端写接口，写入fifo，udp发送端通过读fifo，获取payload数据
    .din_udp_tx_fifo                    (din_udp_tx_fifo           ),// (output)
    .wr_en_udp_tx_fifo                  (wr_en_udp_tx_fifo         ),// (output)
    .full_udp_tx_fifo                   (full_udp_tx_fifo          ),// (input)
    .wr_data_count_udp_tx_fifo          (wr_data_count_udp_tx_fifo ),// (input)
    .wr_rst_busy_udp_tx_fifo            (wr_rst_busy_udp_tx_fifo   ) // (input)
);

endmodule