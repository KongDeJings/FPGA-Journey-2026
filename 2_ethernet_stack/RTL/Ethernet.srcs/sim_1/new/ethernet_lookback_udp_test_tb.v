`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/18 21:32:07
// Design Name: 
// Module Name: ethernet_lookback_udp_test_tb
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
/*
020a353c4d5e 00e26969ec7d 0800 4500 003c 5cb9 4000 8011 0000 c0a80003 c0a8000a d431 d432 0028 8197 (协议字段)
6162636465663132333435363761626364656631323334353637616263646566      (payload)
17B9F5C8（CRC）

020a353c4d5e 00e26969ec7d 0800 4500 0029 5cba 4000 8011 0000 c0a80003 c0a8000a d431 d432 0015 8184 
61626364656631323334353637
204D0AAA

*/
//////////////////////////////////////////////////////////////////////////////////


module ethernet_lookback_udp_test_tb
#(

//=========================协议重要参数配置=====================
    parameter                           ETH_CLOCK_FREQUENCY             = 125_000_000          ,  // 计数1s所需周期数(时钟频率)  

    parameter                           PC_MAC                      = 48'h00E2_6969_EC7D   ,  // MAC: 00-E2-69-69-EC-7D
    parameter                           PC_IP                       = 32'hC0A8_0003        ,  // IP: 192.168.0.3
//  parameter                           FPGA_MAC                    = 48'h001A_2B3C_4D5E   ,  // MAC 00-1A-2B-3C-4D-5E 自定义
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
    parameter                           UDP_PACKET_BYTE_SIZE        = 512                  ,//UDP单次发送512字节
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
)( );
//===============================================================================================================   
//本地参数及接口定义、连线
    // ==================== 系统时钟与复位 ====================
    reg                                 clk_125m                   ;//以太网125MHz时钟
    reg                                 rst_n                      ;// 低有效复位
    reg                                 clk_udp                    ;//UDP应用侧时钟
    // ==================== PHY 接口 ====================
    // GMII 发送接口
    wire                 [   7: 0]      gmii_txd                   ;
    wire                                gmii_tx_en                 ;

    // GMII 接收接口
    reg                  [   7: 0]      gmii_rxd                   ;
    reg                                 gmii_rx_dv                 ;
    wire                                phy_rst_n                  ;
    assign                              phy_rst_n                   = 1                    ;
    wire                 [   7: 0]      led                        ;//观察端口，快速查看是否正常通讯

    // ==================== UDP数据流接口 ====================   
    //以太网接收到的payload;这个fifo在接收模块中，给消费者读接口
    wire                                udp_frame_rx_done_valid    ;
    wire                 [  10: 0]      udp_rx_payload_count_gray_sync  ;//接收到了多少个payload数据，到时候原样读出
    wire                                rd_rst_busy_udp_rx_fifo    ;
    wire                 [   7: 0]      dout_udp_rx_fifo           ;
    wire                                empty_udp_rx_fifo          ;
    wire                                rd_en_udp_rx_fifo          ;

    //应用端写接口，写入fifo，udp发送端通过读fifo，获取payload数据

    wire                 [  7: 0]      din_udp_tx_fifo            ;
    wire                                wr_en_udp_tx_fifo          ;
    wire                                full_udp_tx_fifo           ;
    wire                 [  10: 0]      wr_data_count_udp_tx_fifo  ;
    wire                                wr_rst_busy_udp_tx_fifo    ;


//用不上的自定义长度信号
    reg                                 udp_payload_count_valid    ;
    reg                  [  10: 0]      udp_payload_count          ;
    // 发送参数定义
    reg                  [  47: 0]      local_mac                  ;
    reg                  [  31: 0]      local_ip                   ;
    reg                  [  15: 0]      local_port                 ;
    reg                  [  47: 0]      target_mac                 ;
    reg                  [  31: 0]      target_ip                  ;
    reg                  [  15: 0]      target_port                ;




wire udp_frame_rx_done_valid_synced    ;
//[47:40]
//[39:32]
//[31:24]
//[23:16]
//[15:8] 
//[7:0]  
//===============================================================================================================
//逻辑输出


   xpm_cdc_pulse #(
    .DEST_SYNC_FF                       (3                         ),// DECIMAL; range: 2-10
    .INIT_SYNC_FF                       (0                         ),// DECIMAL; 0=disable simulation init values, 1=enable simulation init values
    .REG_OUTPUT                         (0                         ),// DECIMAL; 0=disable registered output, 1=enable registered output
    .RST_USED                           (1                         ),// DECIMAL; 0=no reset, 1=implement reset
    .SIM_ASSERT_CHK                     (0                         ) // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
   )
   xpm_cdc_pulse_inst (
    .dest_pulse                         (udp_frame_rx_done_valid_synced),// 1-bit output: Outputs a pulse the size of one dest_clk period when a pulse
    .dest_clk                           (clk_udp                       ),// 1-bit input: Destination clock.
    .dest_rst                           (~rst_n                        ),// 1-bit input: optional; required when RST_USED = 1
    .src_clk                            (clk_125m                      ),// 1-bit input: Source clock.
    .src_pulse                          (udp_frame_rx_done_valid       ),// 1-bit input: Rising edge of this signal initiates a pulse transfer to the
    .src_rst                            (~rst_n                        ) // 1-bit input: optional; required when RST_USED = 1
   );



//======================================================================
// 产生时钟
always #10 clk_125m = ~clk_125m;

always #25 clk_udp = ~clk_udp;//UDP应用侧时钟
//======================================================================




//======================================================================
// 初始信号
initial begin
    clk_125m   = 0;
    clk_udp    = 0;
    rst_n      = 1;
    gmii_rxd   = 8'h00;
    gmii_rx_dv = 0;

    udp_payload_count_valid =  1 ;
    udp_payload_count       =  11'd44 ;

    local_mac  = FPGA_MAC ;
    local_ip   = FPGA_IP  ;
    local_port = SRC_PORT ;

    target_mac = PC_MAC ;
    target_ip  = PC_IP  ;
    target_port= DST_PORT ;
    #20 rst_n = 0;
    # 515  rst_n=1;
    #2505 ;

    // 依次发送 4 种以太网帧
//   send_icmp_request;
//   #2000;
//
//   send_icmp_request;
//   #2000;
//
//   send_icmp_request;
//   #2000;
//
//   send_icmp_request;
//   #2000;

   
    send_udp_packet;
    #8000;

send_udp_packet_40bytes;
    #8000;

send_udp_packet_21bytes;
    #8000;

    send_udp_packet;
    #8000;
send_udp_packet_6bytes;
    #8000;
send_udp_packet_5bytes;
    #8000;

//   send_arp_request;
//   #2000;
//
//   send_arp_reply;
//   #2000;
    #2000;
$stop;  
end

//============================================================
// ICMP Echo Request（Ping）  
//===================================================
task send_icmp_request;
begin
    @(posedge clk_125m); #5;
    gmii_rx_dv = 1;

    // Preamble + SFD
    repeat(7) begin gmii_rxd = 8'h55; #20; end
    gmii_rxd = 8'hD5; #20;

    // MAC Header
    gmii_rxd = local_mac[47:40]; #20;
    gmii_rxd = local_mac[39:32]; #20;
    gmii_rxd = local_mac[31:24]; #20;
    gmii_rxd = local_mac[23:16]; #20;
    gmii_rxd = local_mac[15:8] ; #20;
    gmii_rxd = local_mac[7:0]  ; #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'he2; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h69; #20;
    gmii_rxd = 8'hec; #20; gmii_rxd = 8'h7d; #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;

    // IPv4 Header
    gmii_rxd = 8'h45; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h3c; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h80; #20; gmii_rxd = 8'h01; #20;
    gmii_rxd = 8'hf9; #20; gmii_rxd = 8'h63; #20;
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h03; #20;
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h0a; #20;

    // ICMP
    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h44; #20; gmii_rxd = 8'h5c; #20;
    gmii_rxd = 8'h04; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h05; #20; gmii_rxd = 8'h00; #20;

    // Payload
    gmii_rxd = 8'h61; #20; gmii_rxd = 8'h62; #20;
    gmii_rxd = 8'h63; #20; gmii_rxd = 8'h64; #20;
    gmii_rxd = 8'h65; #20; gmii_rxd = 8'h66; #20;
    gmii_rxd = 8'h67; #20; gmii_rxd = 8'h68; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h6a; #20;
    gmii_rxd = 8'h6b; #20; gmii_rxd = 8'h6c; #20;
    gmii_rxd = 8'h6d; #20; gmii_rxd = 8'h6e; #20;
    gmii_rxd = 8'h6f; #20; gmii_rxd = 8'h70; #20;
    gmii_rxd = 8'h71; #20; gmii_rxd = 8'h72; #20;
    gmii_rxd = 8'h73; #20; gmii_rxd = 8'h74; #20;
    gmii_rxd = 8'h75; #20; gmii_rxd = 8'h76; #20;
    gmii_rxd = 8'h77; #20; gmii_rxd = 8'h61; #20;
    gmii_rxd = 8'h62; #20; gmii_rxd = 8'h63; #20;
    gmii_rxd = 8'h64; #20; gmii_rxd = 8'h65; #20;
    gmii_rxd = 8'h66; #20; gmii_rxd = 8'h67; #20;
    gmii_rxd = 8'h68; #20; gmii_rxd = 8'h69; #20;

    gmii_rxd = 8'h37; #20;  // 低字节先发
    gmii_rxd = 8'hd3; #20;
    gmii_rxd = 8'h3c; #20;
    gmii_rxd = 8'h08; #20;

    gmii_rx_dv = 0;
    gmii_rxd = 8'h00;
end
endtask

//===============================================================================================================
// UDP Packet
task send_udp_packet;
begin
    @(posedge clk_125m); #5;
    gmii_rx_dv = 1;

    repeat(7) begin gmii_rxd = 8'h55; #20; end
    gmii_rxd = 8'hD5; #20;

    // MAC
    gmii_rxd = local_mac[47:40]; #20;
    gmii_rxd = local_mac[39:32]; #20;
    gmii_rxd = local_mac[31:24]; #20;
    gmii_rxd = local_mac[23:16]; #20;
    gmii_rxd = local_mac[15:8] ; #20;
    gmii_rxd = local_mac[7:0]  ; #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'he2; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h69; #20;
    gmii_rxd = 8'hec; #20; gmii_rxd = 8'h7d; #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;

    // IPv4
    gmii_rxd = 8'h45; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h36; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h80; #20; gmii_rxd = 8'h11; #20;
    gmii_rxd = 8'hf9; #20; gmii_rxd = 8'h59; #20;
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h03; #20;
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h0a; #20;

    // UDP
    gmii_rxd = 8'hd4; #20; gmii_rxd = 8'h31; #20;
    gmii_rxd = 8'hd4; #20; gmii_rxd = 8'h32; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h22; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;

    // Payload
    gmii_rxd = 8'h31; #20; gmii_rxd = 8'h41; #20;
    gmii_rxd = 8'h32; #20; gmii_rxd = 8'h42; #20;
    gmii_rxd = 8'h33; #20; gmii_rxd = 8'h43; #20;
    gmii_rxd = 8'h34; #20; gmii_rxd = 8'h44; #20;
    gmii_rxd = 8'h35; #20; gmii_rxd = 8'h45; #20;
    gmii_rxd = 8'h36; #20; gmii_rxd = 8'h46; #20;
    gmii_rxd = 8'h37; #20; gmii_rxd = 8'h47; #20;
    gmii_rxd = 8'h38; #20; gmii_rxd = 8'h48; #20;
    gmii_rxd = 8'h39; #20; gmii_rxd = 8'h4a; #20;
    gmii_rxd = 8'h31; #20; gmii_rxd = 8'h41; #20;
    gmii_rxd = 8'h32; #20; gmii_rxd = 8'h42; #20;
    gmii_rxd = 8'h33; #20; gmii_rxd = 8'h43; #20;
    gmii_rxd = 8'h34; #20; gmii_rxd = 8'h44; #20;

    // FCS 小端序：
    gmii_rxd = 8'h40; #20;  // 低字节先发
    gmii_rxd = 8'h1c; #20;
    gmii_rxd = 8'h8b; #20;
    gmii_rxd = 8'hb7; #20;

    gmii_rx_dv = 0;
    gmii_rxd = 8'h00;
end
endtask
// ===============================================================
// UDP 包1：偶数长度 40 字节
// 020a353c4d5e 00e26969ec7d 0800 4500 003c 5cb9 4000 8011 0000 c0a80003 c0a8000a d431 d432 0028 8197
// payload: 6162636465663132333435363761626364656631323334353637616263646566
// FCS: 17B9F5C8
task send_udp_packet_40bytes;
begin
    @(posedge clk_125m); #5;
    gmii_rx_dv = 1;

    // Preamble + SFD
    repeat(7) begin gmii_rxd = 8'h55; #20; end
    gmii_rxd = 8'hD5; #20;

    // MAC Header (dst: FPGA_MAC, src: PC_MAC)
    gmii_rxd = local_mac[47:40]; #20;
    gmii_rxd = local_mac[39:32]; #20;
    gmii_rxd = local_mac[31:24]; #20;
    gmii_rxd = local_mac[23:16]; #20;
    gmii_rxd = local_mac[15:8];  #20;
    gmii_rxd = local_mac[7:0];   #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'he2; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h69; #20;
    gmii_rxd = 8'hec; #20; gmii_rxd = 8'h7d; #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;

    // IPv4 Header
    gmii_rxd = 8'h45; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h3c; #20;    // total length = 60 (0x003C)
    gmii_rxd = 8'h5c; #20; gmii_rxd = 8'hb9; #20;    // ID = 0x5CB9
    gmii_rxd = 8'h40; #20; gmii_rxd = 8'h00; #20;    // flags + frag
    gmii_rxd = 8'h80; #20; gmii_rxd = 8'h11; #20;    // TTL, protocol UDP
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;    // checksum 0
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;    // src IP 192.168.0.3
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h03; #20;
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;    // dst IP 192.168.0.10
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h0a; #20;

    // UDP Header
    gmii_rxd = 8'hd4; #20; gmii_rxd = 8'h31; #20;    // src port 54321
    gmii_rxd = 8'hd4; #20; gmii_rxd = 8'h32; #20;    // dst port 54322
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h28; #20;    // length = 40 (0x0028)
    gmii_rxd = 8'h81; #20; gmii_rxd = 8'h97; #20;    // checksum 0x8197

    // Payload: 40 bytes
    gmii_rxd = 8'h61; #20; gmii_rxd = 8'h62; #20;
    gmii_rxd = 8'h63; #20; gmii_rxd = 8'h64; #20;
    gmii_rxd = 8'h65; #20; gmii_rxd = 8'h66; #20;
    gmii_rxd = 8'h31; #20; gmii_rxd = 8'h32; #20;
    gmii_rxd = 8'h33; #20; gmii_rxd = 8'h34; #20;
    gmii_rxd = 8'h35; #20; gmii_rxd = 8'h36; #20;
    gmii_rxd = 8'h37; #20; gmii_rxd = 8'h61; #20;
    gmii_rxd = 8'h62; #20; gmii_rxd = 8'h63; #20;
    gmii_rxd = 8'h64; #20; gmii_rxd = 8'h65; #20;
    gmii_rxd = 8'h66; #20; gmii_rxd = 8'h31; #20;
    gmii_rxd = 8'h32; #20; gmii_rxd = 8'h33; #20;
    gmii_rxd = 8'h34; #20; gmii_rxd = 8'h35; #20;
    gmii_rxd = 8'h36; #20; gmii_rxd = 8'h37; #20;
    gmii_rxd = 8'h61; #20; gmii_rxd = 8'h62; #20;
    gmii_rxd = 8'h63; #20; gmii_rxd = 8'h64; #20;
    gmii_rxd = 8'h65; #20; gmii_rxd = 8'h66; #20;

    // FCS (little-endian)
    gmii_rxd = 8'hc8; #20;  // 0x17B9F5C8 -> C8, F5, B9, 17
    gmii_rxd = 8'hf5; #20;
    gmii_rxd = 8'hb9; #20;
    gmii_rxd = 8'h17; #20;

    gmii_rx_dv = 0;
    gmii_rxd = 8'h00;
end
endtask

// ===============================================================
// UDP 包2：奇数长度 21 字节
// 020a353c4d5e 00e26969ec7d 0800 4500 0029 5cba 4000 8011 0000 c0a80003 c0a8000a d431 d432 0015 8184 
// payload: 61626364656631323334353637
// FCS: 204D0AAA
task send_udp_packet_21bytes;
begin
    @(posedge clk_125m); #5;
    gmii_rx_dv = 1;

    // Preamble + SFD
    repeat(7) begin gmii_rxd = 8'h55; #20; end
    gmii_rxd = 8'hD5; #20;

    // MAC Header
    gmii_rxd = local_mac[47:40]; #20;
    gmii_rxd = local_mac[39:32]; #20;
    gmii_rxd = local_mac[31:24]; #20;
    gmii_rxd = local_mac[23:16]; #20;
    gmii_rxd = local_mac[15:8];  #20;
    gmii_rxd = local_mac[7:0];   #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'he2; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h69; #20;
    gmii_rxd = 8'hec; #20; gmii_rxd = 8'h7d; #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;

    // IPv4 Header
    gmii_rxd = 8'h45; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h29; #20;   // total length = 41 (0x0029)
    gmii_rxd = 8'h5c; #20; gmii_rxd = 8'hba; #20;   // ID = 0x5CBA
    gmii_rxd = 8'h40; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h80; #20; gmii_rxd = 8'h11; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;   // checksum 0
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h03; #20;
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h0a; #20;

    // UDP Header
    gmii_rxd = 8'hd4; #20; gmii_rxd = 8'h31; #20;
    gmii_rxd = 8'hd4; #20; gmii_rxd = 8'h32; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h15; #20;   // length = 21 (0x0015)
    gmii_rxd = 8'h81; #20; gmii_rxd = 8'h84; #20;   // checksum 0x8184

    // Payload: 21 bytes
    gmii_rxd = 8'h61; #20; gmii_rxd = 8'h62; #20;
    gmii_rxd = 8'h63; #20; gmii_rxd = 8'h64; #20;
    gmii_rxd = 8'h65; #20; gmii_rxd = 8'h66; #20;
    gmii_rxd = 8'h31; #20; gmii_rxd = 8'h32; #20;
    gmii_rxd = 8'h33; #20; gmii_rxd = 8'h34; #20;
    gmii_rxd = 8'h35; #20; gmii_rxd = 8'h36; #20;
    gmii_rxd = 8'h37; #20;

    // FCS (little-endian)
    gmii_rxd = 8'haa; #20;  // 0x204D0AAA -> AA, 0A, 4D, 20
    gmii_rxd = 8'h0a; #20;
    gmii_rxd = 8'h4d; #20;
    gmii_rxd = 8'h20; #20;

    gmii_rx_dv = 0;
    gmii_rxd = 8'h00;
end
endtask


task send_udp_packet_5bytes;
begin
    @(posedge clk_125m); #5;
    gmii_rx_dv = 1;

    // Preamble + SFD
    repeat(7) begin gmii_rxd = 8'h55; #20; end
    gmii_rxd = 8'hD5; #20;

    // MAC (dst = FPGA, src = PC)
    gmii_rxd = local_mac[47:40]; #20;
    gmii_rxd = local_mac[39:32]; #20;
    gmii_rxd = local_mac[31:24]; #20;
    gmii_rxd = local_mac[23:16]; #20;
    gmii_rxd = local_mac[15:8];  #20;
    gmii_rxd = local_mac[7:0];   #20;

    gmii_rxd = target_mac[47:40]; #20;
    gmii_rxd = target_mac[39:32]; #20;
    gmii_rxd = target_mac[31:24]; #20;
    gmii_rxd = target_mac[23:16]; #20;
    gmii_rxd = target_mac[15:8];  #20;
    gmii_rxd = target_mac[7:0];   #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;

    // IPv4 (total length = 33)
    gmii_rxd = 8'h45; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h21; #20;
    gmii_rxd = 8'h5c; #20; gmii_rxd = 8'hbb; #20;
    gmii_rxd = 8'h40; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h80; #20; gmii_rxd = 8'h11; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h03; #20;
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h0a; #20;

    // UDP
    gmii_rxd = 8'hd4; #20; gmii_rxd = 8'h31; #20;
    gmii_rxd = 8'hd4; #20; gmii_rxd = 8'h32; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h0d; #20;   // length = 13
    gmii_rxd = 8'h81; #20; gmii_rxd = 8'h7c; #20;

    // payload: 5 bytes
    gmii_rxd = 8'h61; #20;
    gmii_rxd = 8'h62; #20;
    gmii_rxd = 8'h63; #20;
    gmii_rxd = 8'h64; #20;
    gmii_rxd = 8'h65; #20;

    // FCS (little-endian) : B70B64B5
    gmii_rxd = 8'hB5; #20;
    gmii_rxd = 8'h64; #20;
    gmii_rxd = 8'h0B; #20;
    gmii_rxd = 8'hB7; #20;

    gmii_rx_dv = 0;
    gmii_rxd = 8'h00;
end
endtask



task send_udp_packet_6bytes;
begin
    @(posedge clk_125m); #5;
    gmii_rx_dv = 1;

    repeat(7) begin gmii_rxd = 8'h55; #20; end
    gmii_rxd = 8'hD5; #20;

    gmii_rxd = local_mac[47:40]; #20;
    gmii_rxd = local_mac[39:32]; #20;
    gmii_rxd = local_mac[31:24]; #20;
    gmii_rxd = local_mac[23:16]; #20;
    gmii_rxd = local_mac[15:8];  #20;
    gmii_rxd = local_mac[7:0];   #20;

    gmii_rxd = target_mac[47:40]; #20;
    gmii_rxd = target_mac[39:32]; #20;
    gmii_rxd = target_mac[31:24]; #20;
    gmii_rxd = target_mac[23:16]; #20;
    gmii_rxd = target_mac[15:8];  #20;
    gmii_rxd = target_mac[7:0];   #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;

    // IPv4 (total length = 34)
    gmii_rxd = 8'h45; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h22; #20;
    gmii_rxd = 8'h5c; #20; gmii_rxd = 8'hbc; #20;
    gmii_rxd = 8'h40; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h80; #20; gmii_rxd = 8'h11; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h03; #20;
    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h0a; #20;

    // UDP
    gmii_rxd = 8'hd4; #20; gmii_rxd = 8'h31; #20;
    gmii_rxd = 8'hd4; #20; gmii_rxd = 8'h32; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h0e; #20;   // length = 14
    gmii_rxd = 8'h81; #20; gmii_rxd = 8'h7d; #20;

    // payload: 6 bytes
    gmii_rxd = 8'h61; #20; gmii_rxd = 8'h62; #20;
    gmii_rxd = 8'h63; #20; gmii_rxd = 8'h64; #20;
    gmii_rxd = 8'h65; #20; gmii_rxd = 8'h66; #20;

    // FCS: B3DB6038
    gmii_rxd = 8'h38; #20;
    gmii_rxd = 8'h60; #20;
    gmii_rxd = 8'hDB; #20;
    gmii_rxd = 8'hB3; #20;

    gmii_rx_dv = 0;
    gmii_rxd = 8'h00;
end
endtask

//===============================================================================================================
// ARP Request
task send_arp_request;
begin
    @(posedge clk_125m); #5;
    gmii_rx_dv = 1;

    repeat(7) begin gmii_rxd = 8'h55; #20; end
    gmii_rxd = 8'hD5; #20;

    // MAC
    gmii_rxd = 8'hff; #20; gmii_rxd = 8'hff; #20;
    gmii_rxd = 8'hff; #20; gmii_rxd = 8'hff; #20;
    gmii_rxd = 8'hff; #20; gmii_rxd = 8'hff; #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'he2; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h69; #20;
    gmii_rxd = 8'hec; #20; gmii_rxd = 8'h7d; #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h06; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h01; #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h06; #20; gmii_rxd = 8'h04; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h01; #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'he2; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h69; #20;
    gmii_rxd = 8'hec; #20; gmii_rxd = 8'h7d; #20;

    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h03; #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;

    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h0a; #20;

    // Padding
    repeat(18) begin gmii_rxd = 8'h30; #20; end

    // FCS 小端序
    gmii_rxd = 8'ha4; #20;  // 低字节先发
    gmii_rxd = 8'h45; #20;
    gmii_rxd = 8'h1a; #20;
    gmii_rxd = 8'h69; #20;

    gmii_rx_dv = 0;
    gmii_rxd = 8'h00;
end
endtask

//===============================================================================================================
// ARP Reply
task send_arp_reply;
begin
    @(posedge clk_125m); #5;
    gmii_rx_dv = 1;

    repeat(7) begin gmii_rxd = 8'h55; #20; end
    gmii_rxd = 8'hD5; #20;

    gmii_rxd = local_mac[47:40]; #20;
    gmii_rxd = local_mac[39:32]; #20;
    gmii_rxd = local_mac[31:24]; #20;
    gmii_rxd = local_mac[23:16]; #20;
    gmii_rxd = local_mac[15:8] ; #20;
    gmii_rxd = local_mac[7:0]  ; #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'he2; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h69; #20;
    gmii_rxd = 8'hec; #20; gmii_rxd = 8'h7d; #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h06; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h01; #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h06; #20; gmii_rxd = 8'h04; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h02; #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'he2; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h69; #20;
    gmii_rxd = 8'hec; #20; gmii_rxd = 8'h7d; #20;

    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h03; #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h1a; #20;
    gmii_rxd = 8'h2b; #20; gmii_rxd = 8'h3c; #20;
    gmii_rxd = 8'h4d; #20; gmii_rxd = 8'h5e; #20;

    gmii_rxd = 8'hc0; #20; gmii_rxd = 8'ha8; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h0a; #20;

    repeat(18) begin gmii_rxd = 8'h30; #20; end

    // FCS 小端序
    gmii_rxd = 8'hd5; #20;  // 低字节先发
    gmii_rxd = 8'h1f; #20;
    gmii_rxd = 8'h51; #20;
    gmii_rxd = 8'h61; #20;

    gmii_rx_dv = 0;
    gmii_rxd = 8'h00;
end
endtask




//===============================================================================================================
// 例化以太网协议栈


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
    .UDP_LOOKBACK_TEST_ENABLE           (1                         ) 
)
 u_ethernet_top(

// ==================== 系统时钟与复位 ====================
    .clk_125m                           (clk_125m                  ),// (input)// 以太网125MHz时钟
    .rst_n                              (rst_n                     ),// (input)// 低有效复位
// ==================== PHY 接口 ====================
// GMII 发送接口
    .gmii_txd                           (gmii_txd                  ),// (output)
    .gmii_tx_en                         (gmii_tx_en                ),// (output)
// GMII 接收接口
    .gmii_rxd                           (gmii_rxd                  ),// (input)
    .gmii_rxdv                          (gmii_rx_dv                ),// (input)
    .phy_rst_n                          (phy_rst_n                 ),// (output)
    .led                                (led                       ),// (output)// 观察端口，快速查看是否正常通讯
// ==================== UDP数据流接口 ====================
//以太网接收到的payload,这个fifo在接收模块中，给消费者读接口
    .udp_frame_rx_done_valid            (udp_frame_rx_done_valid   ),// (output)
    .udp_rx_payload_count_gray_sync     (udp_rx_payload_count_gray_sync),// (output)// 已同步到消费者时钟域，接收到了多少个payload数据，到时候原样读出
    .rd_rst_busy_udp_rx_fifo            (rd_rst_busy_udp_rx_fifo   ),// (output)
    .dout_udp_rx_fifo                   (dout_udp_rx_fifo          ),// (output)
    .empty_udp_rx_fifo                  (empty_udp_rx_fifo         ),// (output)
    .rd_en_udp_rx_fifo                  (rd_en_udp_rx_fifo         ),// (input)
    .rd_clk_udp_rx_fifo                 (clk_udp                   ),// (input)// 读取fifo的读时钟
//应用端写接口，写入fifo，udp发送端通过读fifo，获取payload数据
    .wr_clk_udp_tx_fifo                 (clk_udp                   ),// (input)// udp发送fifo的写时钟
    .din_udp_tx_fifo                    (din_udp_tx_fifo           ),// (input)
    .wr_en_udp_tx_fifo                  (wr_en_udp_tx_fifo         ),// (input)
    .full_udp_tx_fifo                   (full_udp_tx_fifo          ),// (output)
    .wr_data_count_udp_tx_fifo          (wr_data_count_udp_tx_fifo ),// (output)
    .wr_rst_busy_udp_tx_fifo            (wr_rst_busy_udp_tx_fifo   ),// (output)
//发送UDP数据时需要的payload长度及参数
    .udp_payload_count_valid            (udp_payload_count_valid   ),// (input)// 这是一个电平信号，拉高使用外部的payload字节数，为低时，使用参数化的字节数
    .udp_payload_count                  (udp_payload_count         ) // (input)
);

udp_lookback u_udp_lookback(
// ==================== 系统时钟与复位 ====================
    .clk                                (clk_udp                   ),// (input)
    .rst_n                              (rst_n                     ),// (input)
// ==================== UDP数据流接口 ====================
//以太网接收到的payload,这个fifo在接收模块中，给消费者读接口
    .udp_frame_rx_done_valid        (udp_frame_rx_done_valid_synced),// (input)
    .udp_rx_payload_count_gray_sync (udp_rx_payload_count_gray_sync),// (input)// 接收到了多少个payload数据，到时候原样读出
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
