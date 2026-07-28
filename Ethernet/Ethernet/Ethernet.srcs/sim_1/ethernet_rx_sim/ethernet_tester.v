`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/05 15:37:37
// Design Name: 
// Module Name: ethernet_tester
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
//////////////////////////////////////////////////////////////////////////////////
/*
ICMP request包：
 00   1a   2b   3c   4d   5e   00   e2   69   69   ec   7d   08   00   45   00  
 00   3c   00   00   00   00   40   01   f9   63   c0   a8   00   03   c0   a8  
 00   0a   08   00   44   5c   04   00   05   00   61   62   63   64   65   66  
 67   68   69   6a   6b   6c   6d   6e   6f   70   71   72   73   74   75   76  
 77   61   62   63   64   65   66   67   68   69   826D1387（原始FCS大端：82 6D 13 87，小端：87 13 6D 82）

电脑发给fpga的udp包
  00   1a   2b   3c   4d   5e   00   e2   69   69   ec   7d   08   00   45   00 
  00   36   00   00   00   00   40   11   f9   59   c0   a8   00   03   c0   a8 
  00   0a   d4   31   d4   32   00   22   00   00   31   41   32   42   33   43 
  34   44   35   45   36   46   37   47   38   48   39   4a   31   41   32   42 
  33   43   34   44  B59B94B2（原始FCS大端：B5 9B 94 B2，小端：B2 94 9B B5）

ARP request包：
 ff  ff  ff  ff  ff  ff  00  e2  69  69  ec  7d  08  06  00  01 
 08  00  06  04  00  01  00  e2  69  69  ec  7d  c0  a8  00  03 
 00  00  00  00  00  00  c0  a8  00  0a  30  30  30  30  30  30 
 30  30  30  30  30  30  30  30  30  30  30  30 691A45A4（原始FCS大端：69 1A 45 A4，小端：A4 45 1A 69）

ARP reply包
 00  1a  2b  3c  4d  5e  00  e2  69  69  ec  7d  08  06  00  01 
 08  00  06  04  00  02  00  e2  69  69  ec  7d  c0  a8  00  03 
 00  1a  2b  3c  4d  5e  c0  a8  00  0a  30  30  30  30  30  30 
 30  30  30  30  30  30  30  30  30  30  30  30  24ECF919（原始FCS大端：24 EC F9 19，小端：19 F9 EC 24）
*/

module ethernet_tester();
//===============================================================================================================   
//本地参数定义

// 电脑信息（来自 ipconfig）
localparam PC_MAC  = 48'h00E2_6969_EC7D;  // MAC: 00-E2-69-69-EC-7D
localparam PC_IP   = 32'hC0A8_0003;       // IP: 192.168.0.3 

// FPGA 信息（自定义，同一网段）
localparam FPGA_MAC = 48'h001A_2B3C_4D5E;  // 自定义 MAC 00-1A-2B-3C-4D-5E
localparam FPGA_IP  = 32'hC0A8_000A;       // 192.168.0.10


// 高位动态端口
localparam DST_PORT = 16'd54321;  // PC   端口
localparam SRC_PORT = 16'd54322;  // FPGA 端口

//===============================================================================================================   
//接口定义、连线

    reg                                 clk_125m                   ;
    reg                                 rst_n                      ;
    reg                  [   7: 0]      gmii_rxd                   ;
    reg                                 gmii_rx_dv                 ;
    reg                  [  47: 0]      local_mac                  ;
    reg                  [  31: 0]      local_ip                   ;
    reg                  [  15: 0]      local_port                 ;

//===============================================================================================================
//产生
//===============================================================================================================
// 产生时钟
always #10 clk_125m = ~clk_125m;

//===============================================================================================================
// 初始信号
initial begin
    clk_125m   = 0;
    rst_n      = 1;
    gmii_rxd   = 8'h00;
    gmii_rx_dv = 0;

    local_mac  = FPGA_MAC;
    local_ip   = FPGA_IP;
    local_port =SRC_PORT;

    #20 rst_n = 0;
    #505 rst_n = 1;

    // 依次发送 4 种以太网帧
   send_icmp_request;
   #2000;

   send_icmp_request;
   #2000;

   send_icmp_request;
   #2000;

   send_icmp_request;
   #2000;

   
    send_udp_packet;
    #2000;

   send_arp_request;
   #2000;

   send_arp_reply;
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
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h1a; #20;
    gmii_rxd = 8'h2b; #20; gmii_rxd = 8'h3c; #20;
    gmii_rxd = 8'h4d; #20; gmii_rxd = 8'h5e; #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'he2; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h69; #20;
    gmii_rxd = 8'hec; #20; gmii_rxd = 8'h7d; #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;

    // IPv4 Header
    gmii_rxd = 8'h45; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h3c; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h40; #20; gmii_rxd = 8'h01; #20;
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

    // FCS (小端序：0x87136D82)
    gmii_rxd = 8'h87; #20;  // 低字节先发
    gmii_rxd = 8'h13; #20;
    gmii_rxd = 8'h6d; #20;
    gmii_rxd = 8'h82; #20;

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
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h1a; #20;
    gmii_rxd = 8'h2b; #20; gmii_rxd = 8'h3c; #20;
    gmii_rxd = 8'h4d; #20; gmii_rxd = 8'h5e; #20;

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'he2; #20;
    gmii_rxd = 8'h69; #20; gmii_rxd = 8'h69; #20;
    gmii_rxd = 8'hec; #20; gmii_rxd = 8'h7d; #20;

    gmii_rxd = 8'h08; #20; gmii_rxd = 8'h00; #20;

    // IPv4
    gmii_rxd = 8'h45; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h36; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h00; #20;
    gmii_rxd = 8'h40; #20; gmii_rxd = 8'h11; #20;
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

    // FCS (小端序：0xB2949BB5)
    gmii_rxd = 8'hb2; #20;  // 低字节先发
    gmii_rxd = 8'h94; #20;
    gmii_rxd = 8'h9b; #20;
    gmii_rxd = 8'hb5; #20;

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

    // FCS (小端序：0xA4451A69)
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

    gmii_rxd = 8'h00; #20; gmii_rxd = 8'h1a; #20;
    gmii_rxd = 8'h2b; #20; gmii_rxd = 8'h3c; #20;
    gmii_rxd = 8'h4d; #20; gmii_rxd = 8'h5e; #20;

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

    // FCS (小端序：0x19F9EC24)
    gmii_rxd = 8'h19; #20;  // 低字节先发
    gmii_rxd = 8'hf9; #20;
    gmii_rxd = 8'hec; #20;
    gmii_rxd = 8'h24; #20;

    gmii_rx_dv = 0;
    gmii_rxd = 8'h00;
end
endtask


//===============================================================================================================
//调用底层模块
    ethernet_rx_top#(
    .PC_MAC                             (PC_MAC                    ),
    .PC_IP                              (PC_IP                     ),
    .FPGA_MAC                           (FPGA_MAC                  ),
    .FPGA_IP                            (FPGA_IP                   ),
    .DST_PORT                           (DST_PORT                  ),
    .SRC_PORT                           (SRC_PORT                  ),
    .PREAMBLE                           (8'h55                     ),
    .SFD                                (8'hD5                     ),
    .ETH_TYPE_IPV4                      (16'h0800                  ),
    .ETH_TYPE_ARP                       (16'h0806                  )
    )
    u_ether_rx_top(
    //=========================协议参数定义========================
    // ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
    // ==================== GMII接口 ====================
    .gmii_rxd                           (gmii_rxd                  ),// (input)
    .gmii_rx_dv                         (gmii_rx_dv                )
    );

    endmodule