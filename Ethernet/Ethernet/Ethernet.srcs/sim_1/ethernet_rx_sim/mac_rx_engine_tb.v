`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/30 10:51:22
// Design Name: 
// Module Name: mac_rx_engine_tb
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



module    mac_rx_engine_tb();
    reg                                        clk                   ;
    reg                                        rst_n                      ;
    reg                       [   7: 0]        gmii_rxd                   ;
    reg                                        gmii_rx_dv                 ;
    reg                       [  47: 0]        local_mac                  ;
    wire                      [   7: 0]        ip_rx_data                 ;
    wire                                       ip_rx_valid                ;
    wire                                       ip_rx_start                ;
    wire                                       ip_byte_cnt                ;
    wire                      [   7: 0]        arp_rx_data                ;
    wire                                       arp_rx_valid               ;
    wire                                       arp_rx_start               ;
    wire                                       arp_byte_cnt               ;
    wire                      [  47: 0]        ip_src_mac                 ;
    wire                      [  47: 0]        ip_dst_mac                 ;
    wire                      [  47: 0]        arp_src_mac                ;
    wire                                       packet_is_ip               ;
    wire                                       packet_is_arp              ;
    wire                                       crc_match                  ;
    wire                                       mac_filter_match           ;
    wire                                       frame_too_short            ;
    wire                                       frame_too_long             ;



                                  
mac_rx_engine#(
   .PREAMBLE       (8'h55          ),
   .SFD            (8'hD5          ),
   .ETH_TYPE_IPV4  (16'h0800       ),
   .ETH_TYPE_ARP   (16'h0806       )
)
 u_mac_rx_engine(
// ==================== 全局信号 ====================
    .clk_125m                           (clk                  ),
    .rst_n                              (rst_n                     ),
// ==================== GMII接口 ====================
    .gmii_rxd                           (gmii_rxd                  ),
    .gmii_rx_dv                         (gmii_rx_dv                ),
// ==================== 配置接口 ====================
    .local_mac                          (local_mac                 ),// 本地MAC地址
// ==================== 输出到IP模块 ====================
    .ip_rx_data                         (ip_rx_data                ),
    .ip_rx_valid                        (ip_rx_valid               ),
    .ip_rx_start                        (ip_rx_start               ),// IP包开始
    .ip_byte_cnt                        (ip_byte_cnt               ),// handover_byte_cnt传递到下层模块，实现计数器的复用，同时对齐数据
// ==================== 输出到ARP模块 ====================
    .arp_rx_data                        (arp_rx_data               ),
    .arp_rx_valid                       (arp_rx_valid              ),
    .arp_rx_start                       (arp_rx_start              ),// ARP包开始
    .arp_byte_cnt                       (arp_byte_cnt              ),// handover_byte_cnt传递到下层模块，实现计数器的复用，同时对齐数据
// ==================== 解析到的MAC输出 ====================
    .ip_src_mac                         (ip_src_mac                ),// 源MAC
    .ip_dst_mac                         (ip_dst_mac                ),// 目的MAC
    .arp_src_mac                        (arp_src_mac               ),// 发送方MAC（只从以太网头部获取）
// ==================== 对外输出的状态信息 ====================
    .packet_is_ip                       (packet_is_ip              ),
    .packet_is_arp                      (packet_is_arp             ),
    .crc_match                          (crc_match                 ),
    .mac_filter_match                   (mac_filter_match          ),
    .frame_too_short                    (frame_too_short           ),// 帧过短标志
    .frame_too_long                     (frame_too_long            )// 帧过长标志
);




                                     
 /*
 前导码已省略   
 cc_11_22_33_44_55   dst_mac
 66_77_88_99_aa_bb   src_mac
 08_00  
 45 
 00  
 00_3c   ip_len
 00_00 
 00_00 
 80 
 11 
 b6_96 
 c0_a8_01_64     src_ip
 c0_a8_01_66     dst_ip
 04_7e    src port
 04_88    dst_port
 00_28    udp length
 6f_7a    udp_check_sum
 30_30_30_30_30_30  
 30_30_30_30_30_30 
 30_30_30_30_30_30
 30_30_30_30_30_30
 30_30_30_30_30_30
 30_30  
33_50_87_1C   crc
*/
    initial
        begin
            clk             =0;
            rst_n           =1;
//=================================================       
// 初始化预期的mac/ip/port值
            local_mac  =  48'hcc_11_22_33_44_55 ;
 //          cfg_dst_ip_filter   =  32'h c0_a8_01_66;
 //          cfg_dst_port_filter =  16'h 04_88 ;  
            gmii_rxd  =8'b0;
            gmii_rx_dv=0;
   //         cfg_enable_filter=1;
   //         m_axis_tready=1;
        end    

//=================================================       
// 产生时钟                                           
always #10 clk=~clk;

//开始测试系统模块
        initial 
        begin
            #20 rst_n=0;
            #505 rst_n=1; 

send_udp_packet;
#2000
send_udp_packet;

    #1000;
    $stop;
        end

//=================================================       
// 生成一个简单的UDP包

task send_udp_packet;
    begin
        // 1. 前导码 + SFD (7个0x55 + 1个0xD5)
                @(posedge  clk);#5;    
        gmii_rx_dv = 1;
        repeat(7) begin
            gmii_rxd = 8'h55;
            #20;
        end
        gmii_rxd = 8'hD5;  // 帧起始定界符
        #20
        
        // ==================== 2. MAC头 (14字节) ====================
        // 目的MAC: cc-11-22-33-44-55
        gmii_rxd = 8'hCC; #20  // byte 0
        gmii_rxd = 8'h11; #20  // byte 1
        gmii_rxd = 8'h22; #20  // byte 2
        gmii_rxd = 8'h33; #20  // byte 3
        gmii_rxd = 8'h44; #20  // byte 4
        gmii_rxd = 8'h55; #20  // byte 5
        
        // 源MAC: 66-77-88-99-AA-BB
        gmii_rxd = 8'h66; #20  // byte 6
        gmii_rxd = 8'h77; #20  // byte 7
        gmii_rxd = 8'h88; #20  // byte 8
        gmii_rxd = 8'h99; #20  // byte 9
        gmii_rxd = 8'hAA; #20  // byte 10
        gmii_rxd = 8'hBB; #20  // byte 11
        
        // 以太网类型: 0x0800 (IPv4)
        gmii_rxd = 8'h08; #20  // byte 12
        gmii_rxd = 8'h00; #20  // byte 13
        
        // ==================== 3. IP头 (20字节) ====================
        // IPv4版本(4) + 头部长度(5, 20字节) = 0x45
        gmii_rxd = 8'h45; #20  // byte 14
        
        // 服务类型(DSCP+ECN) = 0x00
        gmii_rxd = 8'h00; #20  // byte 15
        
        // 总长度: 0x003C = 60字节 (20 IP头 + 8 UDP头 + 32 数据)
        // 大端序: 先发高字节
        gmii_rxd = 8'h00; #20  // byte 16
        gmii_rxd = 8'h3C; #20  // byte 17
        
        // 标识: 0x0000
        gmii_rxd = 8'h00; #20  // byte 18
        gmii_rxd = 8'h00; #20  // byte 19
        
        // 标志(3位) + 片偏移(13位): 0x0000
        gmii_rxd = 8'h00; #20  // byte 20
        gmii_rxd = 8'h00; #20  // byte 21
        
        // 生存时间(TTL): 0x80 = 128 hops
        gmii_rxd = 8'h80; #20  // byte 22
        
        // 协议: 0x11 = UDP
        gmii_rxd = 8'h11; #20  // byte 23
        
        // 首部校验和: 0xB696
        gmii_rxd = 8'hB6; #20  // byte 24
        gmii_rxd = 8'h96; #20  // byte 25
        
        // 源IP地址: 192.168.1.100 (0xC0A80164)
        gmii_rxd = 8'hC0; #20  // byte 26
        gmii_rxd = 8'hA8; #20  // byte 27
        gmii_rxd = 8'h01; #20  // byte 28
        gmii_rxd = 8'h64; #20  // byte 29
        
        // 目的IP地址: 192.168.1.102 (0xC0A80166)
        gmii_rxd = 8'hC0; #20  // byte 30
        gmii_rxd = 8'hA8; #20  // byte 31
        gmii_rxd = 8'h01; #20  // byte 32
        gmii_rxd = 8'h66; #20  // byte 33
        
        // ==================== 4. UDP头 (8字节) ====================
        // 源端口: 0x047E = 1150
        gmii_rxd = 8'h04; #20  // byte 34
        gmii_rxd = 8'h7E; #20  // byte 35
        
        // 目的端口: 0x0488 = 1160
        gmii_rxd = 8'h04; #20  // byte 36
        gmii_rxd = 8'h88; #20  // byte 37
        
        // UDP长度: 0x0028 = 40字节 (8 UDP头 + 32 数据)
        gmii_rxd = 8'h00; #20  // byte 38
        gmii_rxd = 8'h28; #20  // byte 39
        
        // UDP校验和: 0x6F7A
        gmii_rxd = 8'h6F; #20  // byte 40
        gmii_rxd = 8'h7A; #20  // byte 41
        
        // ==================== 5. UDP数据负载 (32字节) ====================
        // 数据: 30_30_30_30_30_30 (6个字节) 重复5次 + 30_30 (2字节) = 32字节
        // 注意: 你的数据是"303030303030"重复5次+ "3030" = 32字节
        
        // 第1组: 30_30_30_30_30_30 (6字节)
        gmii_rxd = 8'h30; #20  // byte 42
        gmii_rxd = 8'h30; #20  // byte 43
        gmii_rxd = 8'h30; #20  // byte 44
        gmii_rxd = 8'h30; #20  // byte 45
        gmii_rxd = 8'h30; #20  // byte 46
        gmii_rxd = 8'h30; #20  // byte 47
        
        // 第2组: 30_30_30_30_30_30
        gmii_rxd = 8'h30; #20  // byte 48
        gmii_rxd = 8'h30; #20  // byte 49
        gmii_rxd = 8'h30; #20  // byte 50
        gmii_rxd = 8'h30; #20  // byte 51
        gmii_rxd = 8'h30; #20  // byte 52
        gmii_rxd = 8'h30; #20  // byte 53
        
        // 第3组: 30_30_30_30_30_30
        gmii_rxd = 8'h30; #20  // byte 54
        gmii_rxd = 8'h30; #20  // byte 55
        gmii_rxd = 8'h30; #20  // byte 56
        gmii_rxd = 8'h30; #20  // byte 57
        gmii_rxd = 8'h30; #20  // byte 58
        gmii_rxd = 8'h30; #20  // byte 59
        
        // 第4组: 30_30_30_30_30_30
        gmii_rxd = 8'h30; #20  // byte 60
        gmii_rxd = 8'h30; #20  // byte 61
        gmii_rxd = 8'h30; #20  // byte 62
        gmii_rxd = 8'h30; #20  // byte 63
        gmii_rxd = 8'h30; #20  // byte 64
        gmii_rxd = 8'h30; #20  // byte 65
        
        // 第5组: 30_30_30_30_30_30
        gmii_rxd = 8'h30; #20  // byte 66
        gmii_rxd = 8'h30; #20  // byte 67
        gmii_rxd = 8'h30; #20  // byte 68
        gmii_rxd = 8'h30; #20  // byte 69
        gmii_rxd = 8'h30; #20  // byte 70
        gmii_rxd = 8'h30; #20  // byte 71
        
        // 最后2字节: 30_30
        gmii_rxd = 8'h40; #20  // byte 72
        gmii_rxd = 8'h40; #20  // byte 73
        
        // ==================== 6. 帧校验序列FCS (4字节) ====================
        // 实际发送顺序：1C 87 50 33
        gmii_rxd = 8'h4c; #20  // byte 74
        gmii_rxd = 8'h6a; #20  // byte 75
        gmii_rxd = 8'h8f; #20  // byte 76
        gmii_rxd = 8'hd6; #20  // byte 77
        
        // 帧结束
        gmii_rx_dv = 0;
        gmii_rxd = 8'h00;
        
        // 等待几个周期
        repeat(10) #20;
    end
endtask
endmodule
