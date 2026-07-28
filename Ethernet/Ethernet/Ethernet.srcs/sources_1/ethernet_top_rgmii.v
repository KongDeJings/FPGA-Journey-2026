`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/18 11:14:35
// Design Name: 
// Module Name: ethernet_top_rgmii
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ethernet_top_rgmii
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


    parameter                           IP_MARK                     = 16'h0                ,//标识，PC发的包，这个字段不为0，这个字段取消检查
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
    parameter                           UDP_PACKET_BYTE_SIZE        = 512                  ,//UDP单次发送512字节
//IFG
    parameter                           IFG_COUNT                   = 15                   ,//帧间间隔的周期数，96bit时间，要求12个字节，我多留了裕量，15个字节
//=========================协议参数定义:接收部分，arp——cache========================

    parameter                           ARP_LENGTH                  = 52                   ,
    parameter                           CACHE_SIZE                  = 16                   ,
    parameter                           AGING_SEC                   = 60                   ,// 老化时间（秒）
    parameter                           ICMP_ECHO_REQUEST           = 8'h08                ,//收到别人的请求是0x08
    parameter                           ICMP_ECHO_REPLY             = 8'h00                ,//回复别人的请求是00

//PHY上电初始化
    parameter                           SYS_CLK_FREQ                = 50_000_000           ,// 系统时钟频率
    parameter                           PHY_RST_HOLD_MS             = 25                   ,// PHY硬复位保持时间     25ms
    parameter                           PHY_INIT_WAIT_MS            = 100                  ,// PHY复位释放后等待初始化完成时间，模拟校准+RXC锁定   100ms
    parameter                           IP_CHECKSUM_CHECK_VALID     = 0                    ,//UDP和ICMP校验和是否开启信号，0为关闭，1为开启，PC发的包默认关闭，故此参数为0
//UDP回环测试使能
    parameter                           UDP_LOOKBACK_TEST_ENABLE     = 0                   //这个参数决定是否进行UDP回环实验，它改变的是udp_payload的长度  ,默认为0，等于1则为回环逻辑      
)

(
    // ==================== 系统时钟与复位 ====================
    input                               sys_clk                    ,// 板载50Mhz主时钟
    input                               key_in                     ,// 低有效复位
    output                              clk125m                    ,//用于同步信号，使用可忽略
    // ==================== PHY 接口 ====================
    // RGMII 发送接口
    output                              rgmii_tx_clk               ,
    output               [   3: 0]      rgmii_txd                  ,
    output                              rgmii_tx_en                ,

    // RGMII 接收接口
    input                               rgmii_rx_clk               ,//PHY恢复的最原始的时钟信号
    input                [   3: 0]      rgmii_rxd                  ,
    input                               rgmii_rxdv                 ,
    output                              phy_rst_n                  ,
    output               [   7: 0]      led                        ,//观察端口，快速查看是否正常通讯

    // ==================== UDP数据流接口 ====================   
    //以太网接收到的payload,这个fifo在接收模块中，给消费者读接口
    output                              udp_frame_rx_done_valid    ,
    output               [  10: 0]      udp_rx_payload_count_gray_sync,//接收到了多少个payload数据，到时候原样读出
    output                              rd_rst_busy_udp_rx_fifo    ,
    output               [   7: 0]      dout_udp_rx_fifo           ,
    output                              empty_udp_rx_fifo          ,
    input                               rd_en_udp_rx_fifo          ,
    input                               rd_clk_udp_rx_fifo         ,//读取fifo的读时钟

    //应用端写接口，写入fifo，udp发送端通过读fifo，获取payload数据
    input                               wr_clk_udp_tx_fifo         ,//udp发送fifo的写时钟
//    input                [  15: 0]      din_udp_tx_fifo            ,
    input                [  7: 0]      din_udp_tx_fifo            ,
    input                               wr_en_udp_tx_fifo          ,
    output                              full_udp_tx_fifo           ,
//    output               [   9: 0]      wr_data_count_udp_tx_fifo  ,
    output               [  10: 0]      wr_data_count_udp_tx_fifo  ,
    output                              wr_rst_busy_udp_tx_fifo    ,
//发送UDP数据时需要的payload长度及参数
    input                               udp_payload_count_valid    ,//注意！！这是125M时钟域，必须CDC!!!!!//这是一个电平信号，拉高使用外部的payload字节数，为低时，使用参数化的字节数
    input                [  10: 0]      udp_payload_count           //注意！！这是125M时钟域，必须CDC!!!!!

    );

//===============================================================================================================   
//本地参数及接口定义、连线
    wire                                clk_125m                   ;
    assign        clk125m                   = clk_125m             ;
    wire                                rst_n                      ;
    assign       rst_n                = key_in                     ;//外部复位，直连，不经过消抖
        //////////////////   rgmii_gmii   ///////////////////供给接收模块使用

    wire                 [   7: 0]      gmii_rxd                   ;
    wire                                gmii_rxdv                  ;
    wire                                gmii_rxer                  ;//这个信号暂未被使用

        //////////////////   gmii_rgmii      ///////////////////发送模块完成发送后，要转为rgmii的信号

    wire                 [   7: 0]      gmii_txd                   ;
    wire                                gmii_tx_en                 ;
    wire                                gmii_tx_err                ;
    assign                              gmii_tx_err                 = 0      ;

        //////////////////    以太网PLL 和  BUFG      ///////////////////
    wire                                ethernet_pll_locked        ;
    wire                                gmii_rx_clk                ;
    wire                                rgmii_rx_clk_pll           ;// PLL 输出的移相时钟
    wire                                gmii_rx_clk_i              ;//非常重要的时钟信号，clk_125m的来源，整个以太网协议栈时钟的心脏


//===============================================================================================================
//逻辑输出
//=================================================================================
//PHY时钟引入BUFG，驱动所有逻辑 
  gmii_rx_clk_125m_pll_add_90_phase ETHERNET_CLK_PLL
   (
    // Clock out ports                                               //该PLL添加了90度相移
    .gmii_rx_clk                        (rgmii_rx_clk_pll          ),// output gmii_rx_clk
    // Status and control signals
    .resetn                             (rst_n                     ),// input resetn
    .locked                             (ethernet_pll_locked       ),// output locked
   // Clock in ports
    .gmii_rx_clk_i                      (rgmii_rx_clk              ) // input gmii_rx_clk_i
 );

BUFG BUFG_gmii_rx (
    .O                                  (clk_125m                  ),
    .I                                  (gmii_rx_clk_i             ) 
);

//===============================================================================================================
//调用底层模块

//////////////////////////////////////////    gmii_rgmii       //////////////////////////////////////////////

gmii_to_rgmii u_gmii_to_rgmii(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)// 主时钟 (125MHz, GMII时钟域)
    .rst_n                              (rst_n                     ),// (input)// 异步低有效复位，同步化后使用
// ==================== 内部gmii数据输入接口 ====================
    .gmii_txd                           (gmii_txd                  ),// (input)// gmii逻辑的8位并行
    .tx_en                              (gmii_tx_en                ),// (input)
    .tx_err                             (gmii_tx_err               ),// (input)
// ==================== 传递给phy的rgmii信号 ====================
    .rgmii_txd                          (rgmii_txd                 ),// (output)// 125Mhz双边沿ODDR传输信号
    .rgmii_txen                         (rgmii_tx_en               ),// (output)
    .rgmii_tx_clk                       (rgmii_tx_clk              ) // (output)
);

//////////////////////////////////////////    rgmii_gmii    //////////////////////////////////////////////

rgmii_to_gmii u_rgmii_to_gmii(
// ==================== 全局信号 ====================
    .rst_n                              (rst_n                     ),// (input)// 异步低有效复位，同步化后使用
// ==================== phy传递过来的rgmii信号 ====================
    .rgmii_rx_clk                       (rgmii_rx_clk_pll          ),// (input)
    .rgmii_rxd                          (rgmii_rxd                 ),// (input)
    .rgmii_rxdv                         (rgmii_rxdv                ),// (input)
// ==================== 内部gmii数据输入接口 ====================
    .gmii_rx_clk                        (gmii_rx_clk_i             ),// (output)
    .gmii_rxd                           (gmii_rxd                  ),// (output)
    .gmii_rxdv                          (gmii_rxdv                 ),// (output)
    .gmii_rxer                          (gmii_rxer                 ) // (output)
);

//////////////////////////////////////////   gmii版本的ethernet_top    //////////////////////////////////////////////

ethernet_top#(
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
    .UDP_LOOKBACK_TEST_ENABLE           (UDP_LOOKBACK_TEST_ENABLE  ) 
)
 u_ethernet_top(
// ==================== 系统时钟与复位 ====================
    .clk_125m                           (clk_125m                  ), // (input)// 以太网125MHz时钟
    .rst_n                              (rst_n                     ), // (input)// 低有效复位
// ==================== PHY 接口 ====================
// GMII 发送接口
    .gmii_txd                           (gmii_txd                  ), // (output)
    .gmii_tx_en                         (gmii_tx_en                ), // (output)
// GMII 接收接口
    .gmii_rxd                           (gmii_rxd                  ), // (input)
    .gmii_rxdv                          (gmii_rxdv                 ), // (input)
    .phy_rst_n                          (phy_rst_n                 ), // (output)
    .led                                (led                       ), // (output)// 观察端口，快速查看是否正常通讯
// ==================== UDP数据流接口 ====================
//以太网接收到的payload,这个fifo在接收模块中，给消费者读接口
    .udp_frame_rx_done_valid            (udp_frame_rx_done_valid   ), // (output)
    .udp_rx_payload_count_gray_sync     (udp_rx_payload_count_gray_sync), // (output)// 接收到了多少个payload数据，到时候原样读出
    .rd_rst_busy_udp_rx_fifo            (rd_rst_busy_udp_rx_fifo   ), // (output)
    .dout_udp_rx_fifo                   (dout_udp_rx_fifo          ), // (output)
    .empty_udp_rx_fifo                  (empty_udp_rx_fifo         ), // (output)
    .rd_en_udp_rx_fifo                  (rd_en_udp_rx_fifo         ), // (input)
    .rd_clk_udp_rx_fifo                 (rd_clk_udp_rx_fifo        ), // (input)// 读取fifo的读时钟
//应用端写接口，写入fifo，udp发送端通过读fifo，获取payload数据
    .wr_clk_udp_tx_fifo                 (wr_clk_udp_tx_fifo        ), // (input)// udp发送fifo的写时钟
    .din_udp_tx_fifo                    (din_udp_tx_fifo           ), // (input)
    .wr_en_udp_tx_fifo                  (wr_en_udp_tx_fifo         ), // (input)
    .full_udp_tx_fifo                   (full_udp_tx_fifo          ), // (output)
    .wr_data_count_udp_tx_fifo          (wr_data_count_udp_tx_fifo ), // (output)
    .wr_rst_busy_udp_tx_fifo            (wr_rst_busy_udp_tx_fifo   ),// (output)
    .udp_payload_count_valid            (udp_payload_count_valid   ),// (input)这是一个电平信号，拉高使用外部的payload字节数，为低时，使用参数化的字节数
    .udp_payload_count                  (udp_payload_count         )// (input)
);

endmodule
