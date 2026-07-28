`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/06/06 09:39:24
// Design Name: 
// Module Name: ethernet_rx_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 该模块集合了mac头、udp头、icmp头、arp接收等模块集合
// 代码中禁止出现魔数
//////////////////////////////////////////////////////////////////////////////////

module ethernet_rx_top
#(

    parameter                           PC_MAC                      = 48'h00E2_6969_EC7D   ,  // MAC: 00-E2-69-69-EC-7D
    parameter                           PC_IP                       = 32'hC0A8_0003        ,  // IP: 192.168.0.3
//    parameter                           FPGA_MAC                    = 48'h001A_2B3C_4D5E   ,  // MAC 00-1A-2B-3C-4D-5E 自定义
    parameter                           FPGA_MAC                    = 48'h020A_353C_4D5E   ,  // MAC 02-0A-35-3C-4D-5E 这是xilinx专用mac，可被wireshark识别到
    parameter                           FPGA_IP                     = 32'hC0A8_000A        ,  // 192.168.0.10
    parameter                           DST_PORT                    = 16'd54321            ,  // PC   端口
    parameter                           SRC_PORT                    = 16'd54322            ,  // FPGA 端口

    parameter                           CLOCK_FREQUENCY             = 125_000_000          ,  // 计数1s所需周期数(时钟频率)  
//=========================协议参数定义========================

    parameter                           PREAMBLE                    = 8'h55                ,
    parameter                           SFD                         = 8'hD5                ,
    parameter                           ETH_TYPE_IPV4               = 16'h0800             ,
    parameter                           ETH_TYPE_ARP                = 16'h0806             ,
    parameter                           ARP_LENGTH                  = 52                   ,
    parameter                           CACHE_SIZE                  = 16                   ,
    parameter                           AGING_SEC                   = 60                   ,// 老化时间（秒）
    parameter                           IP_VER                      = 8'h45                ,//版本+首部长度
    parameter                           IP_SERVICE                  = 8'h0                 ,//服务类型z
    parameter                           IP_MARK                     = 16'h0                ,//标识
    parameter                           IP_FRAG_OFFSET              = 16'h0                ,//标志+片偏移
    parameter                           IP_TTL                      = 8'h40                ,//TTL生存时间
    parameter                           IP_PROTO_UDP                = 8'h11                ,
    parameter                           IP_PROTO_ICMP               = 8'h01                ,
    parameter                           ICMP_ECHO_REQUEST           = 8'h08                ,//收到别人的请求是0x08
    parameter                           ICMP_ECHO_REPLY             = 8'h00                ,//回复别人的请求是00
    parameter                           ICMP_CODE                   = 8'h00                ,//回复别人的请求是00

    parameter                           UDP_VERC                    = 16'h0                ,//UDP校验和，不做校验，空置为0
    parameter                           IP_CHECKSUM_CHECK_VALID     = 0                    
    
)
(
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,
    input                               rst_n                      ,
    
    // ==================== GMII接口 ====================
    input                [   7: 0]      gmii_rxd                   ,
    input                               gmii_rx_dv                 ,
    
    // ==================== arp_cache接口 ====================

    //ARP 应答信息输出接口
    output                              arp_tx_reply_req_pulse     ,
    output               [  47: 0]      arp_target_mac             ,
    output               [  31: 0]      arp_target_ip              ,

    // ========= 解析出的 ICMP 数据,靠它来发送icmp_reply ==============
    output               [  15: 0]      icmp_reply_checksum        ,
    output                              icmp_reply_checksum_valid  ,
    output               [  15: 0]      icmp_identifier            ,// 标识符
    output               [  15: 0]      icmp_sequence              ,// 序列号

    // ===================  ICMP PAYLOAD数据接口====================
    input                               rd_en_icmp_fifo            ,
    output               [   7: 0]      dout_icmp_fifo             ,
    output                              empty_icmp_fifo            ,
    output               [  10: 0]      icmp_payload_count         ,


    input                               srst_icmp_fifo             ,

    // ===================  UDP PAYLOAD数据接口====================
    output               [  10: 0]      udp_payload_count_gray_sync,//已同步到消费者时钟域
    output               [  10: 0]      udp_rx_payload_count       ,//以太网时钟域，用以数据回环
    output                              rd_rst_busy_udp_fifo       ,
    output               [   7: 0]      dout_udp_fifo              ,
    output                              empty_udp_fifo             ,
    input                               rd_en_udp_fifo             ,

    input                               rd_clk_udp_fifo            ,
    input                               rst_udp_fifo               ,

    // =================== 以太网所有信息的最终裁决信号 ====================
    output reg                          arp_frame_rx_done_valid    ,
    output reg                          icmp_frame_rx_done_valid   ,
    output reg                          udp_frame_rx_done_valid    ,
    // ===================  临时调试数据接口====================
    output               [   5: 0]      error_led                   
);
//===============================================================================================================   
//本地参数及接口定义、连线

        //////////////////    mac头接收模块       ///////////////////
    wire                                gmii_rx_dv_fall            ;
    //输出到IP模块
    wire                 [   7: 0]      ip_rx_data                 ;
    wire                                ip_rx_valid                ;
    wire                                ip_rx_start                ;
    wire                 [  15: 0]      ip_byte_cnt                ;
    //输出到ARP模块
    wire                 [   7: 0]      arp_rx_data                ;
    wire                                arp_rx_valid               ;
    wire                                arp_rx_start               ;
    wire                 [  15: 0]      arp_byte_cnt               ;
    //解析到的MAC输出   
    wire                 [  47: 0]      ip_src_mac                 ;
    wire                 [  47: 0]      ip_dst_mac                 ;
    wire                 [  47: 0]      arp_src_mac                ;
    //状态信息输出  
    wire                                frame_rx_done              ;
    wire                                packet_is_ip               ;
    wire                                packet_is_arp              ;
    wire                                crc_match                  ;
    wire                                mac_rx_error               ;

        //////////////////    ARP接收模块       ///////////////////
    wire                 [  31: 0]      arp_src_ip                 ;
    wire                 [  47: 0]      arp_dst_mac                ;
    wire                 [  31: 0]      arp_dst_ip                 ;
    wire                 [  15: 0]      arp_opcode                 ;
    
    wire                                arp_rx_error               ;

        //////////////////    ARP_cache模块       ///////////////////

    wire                                arp_frame_rx_done          ;
    wire                                icmp_rx_frame_valid        ;
    wire                                udp_rx_frame_valid         ;

        //////////////////    IP头接收模块       ///////////////////
    //输出到UDP模块        
    wire                 [   7: 0]      udp_rx_data                ;
    wire                                udp_rx_valid               ;
    wire                                udp_rx_start               ;
    wire                 [  15: 0]      udp_byte_cnt               ;
    //输出到ICMP模块
    wire                 [   7: 0]      icmp_rx_data               ;
    wire                                icmp_rx_valid              ;
    wire                                icmp_rx_start              ;
    wire                 [  15: 0]      icmp_byte_cnt              ;
    wire                 [  15: 0]      icmp_length                ;
    //状态信息输出     
    wire                                packet_is_udp              ;
    wire                                packet_is_icmp             ;
    wire                 [  31: 0]      src_ip                     ;
    wire                 [  31: 0]      dest_ip                    ;
    wire                                ip_rx_error                ;

        //////////////////    ICMP接收模块       ///////////////////
    wire                                icmp_rx_error              ;

//icmp_fifo
    wire                 [   7: 0]      din_icmp_fifo              ;
    wire                                wr_en_icmp_fifo            ;
    wire                                full_icmp_fifo             ;

        //////////////////    UDP接收模块       ///////////////////
    wire                                udp_rx_error               ;
    wire                 [  10: 0]      udp_wr_data_cnt            ;//需要跨时钟域同步到读端
//udp_fifo

    wire                 [   7: 0]      din_udp_fifo               ;
    wire                                wr_en_udp_fifo             ;
    wire                                full_udp_fifo              ;
    wire                                wr_rst_busy_udp_fifo       ;

//===============================================================================================================
//逻辑输出
assign udp_rx_payload_count= udp_wr_data_cnt;

//===================================================
//产生arp、icmp、udp的包接收完成信号
    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                arp_frame_rx_done_valid<=0;
            else if(frame_rx_done)begin
                if(packet_is_arp
                        &&(~mac_rx_error)
                                &&crc_match
                                    &&(~arp_rx_error))
                    arp_frame_rx_done_valid<=1;
                else
                    arp_frame_rx_done_valid<=0;
            end  else
                     arp_frame_rx_done_valid<=0;    end
                                                                                  
    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                icmp_frame_rx_done_valid<=0;
            else if(frame_rx_done)begin
                if(packet_is_ip
                        &&(~ip_rx_error)
                            &&(~mac_rx_error)
                                    &&crc_match
                                        &&packet_is_icmp
                                            &&(~icmp_rx_error))
                    icmp_frame_rx_done_valid<=1;
                else
                    icmp_frame_rx_done_valid<=0;
            end  else
                     icmp_frame_rx_done_valid<=0;   end
           
    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                udp_frame_rx_done_valid<=0;
            else if(frame_rx_done)begin
                if(packet_is_ip
                        &&(~ip_rx_error)
                            &&(~mac_rx_error)
                                    &&crc_match
                                        &&packet_is_udp
                                            &&(~udp_rx_error))
                    udp_frame_rx_done_valid<=1;
                else
                    udp_frame_rx_done_valid<=0;
            end             else
                                udp_frame_rx_done_valid<=0;  end
         

//===============================================================================================================
//调用底层模块
//////////////////////////////////////////    mac头接收模块       //////////////////////////////////////////////


mac_rx_engine#(
    .PREAMBLE                           (PREAMBLE                  ),
    .SFD                                (SFD                       ),
    .ETH_TYPE_IPV4                      (ETH_TYPE_IPV4             ),
    .FPGA_MAC                           (FPGA_MAC                  ),
    .ETH_TYPE_ARP                       (ETH_TYPE_ARP              ) 
)
 u_mac_rx_engine(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
    .gmii_rx_dv_fall                    (gmii_rx_dv_fall           ),
// ==================== GMII接口 ====================
    .gmii_rxd                           (gmii_rxd                  ),// (input)
    .gmii_rx_dv                         (gmii_rx_dv                ),// (input)
// ==================== 配置接口 ====================
    .local_mac                          (FPGA_MAC                  ),// (input)// 本地MAC地址
// ==================== 输出到IP模块 ====================
    .ip_rx_data                         (ip_rx_data                ),// (output)
    .ip_rx_valid                        (ip_rx_valid               ),// (output)
    .ip_rx_start                        (ip_rx_start               ),// (output)// IP包开始
    .ip_byte_cnt                        (ip_byte_cnt               ),// (output)// handover_byte_cnt传递到下层模块，实现计数器的复用，同时对齐数据
// ==================== 输出到ARP模块 ====================
    .arp_rx_data                        (arp_rx_data               ),// (output)
    .arp_rx_valid                       (arp_rx_valid              ),// (output)
    .arp_rx_start                       (arp_rx_start              ),// (output)// ARP包开始
    .arp_byte_cnt                       (arp_byte_cnt              ),// (output)// handover_byte_cnt传递到下层模块，实现计数器的复用，同时对齐数据
// ==================== 解析到的MAC输出 ====================
    .ip_src_mac                         (ip_src_mac                ),// (output)// 源MAC
    .ip_dst_mac                         (ip_dst_mac                ),// (output)// 目的MAC
// ==================== 对外输出的状态信息 ====================
    .frame_rx_done                      (frame_rx_done             ),// (output)
    .packet_is_ip                       (packet_is_ip              ),// (output)
    .packet_is_arp                      (packet_is_arp             ),// (output)
    .crc_match                          (crc_match                 ),// (output)
    .mac_rx_error                       (mac_rx_error              ) // (output)

);
//////////////////////////////////////////    arp接收模块       //////////////////////////////////////////////

arp_rx_engine#(
    .ARP_LENGTH                         (ARP_LENGTH                ) 
)
 u_arp_rx_engine(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
// ==================== MAC层输入 ====================
    .arp_rx_data                        (arp_rx_data               ),// (input)
    .arp_rx_valid                       (arp_rx_valid              ),// (input)
    .arp_rx_start                       (arp_rx_start              ),// (input)// ARP包开始
    .arp_byte_cnt                       (arp_byte_cnt              ),// (input)
    .packet_is_arp                      (packet_is_arp             ),// (input)
// ==================== 配置接口 ====================
    .local_ip                           (FPGA_IP                   ),// (input)// 本地IP
    .local_mac                          (FPGA_MAC                  ),// (input)// 本地mac
// ==================== 解析的ARP信息，输出给外面 ====================
    .arp_src_mac                        (arp_src_mac               ),// (output)// 发送方MAC（来自以太网头部）
    .arp_src_ip                         (arp_src_ip                ),// (output)// 发送方IP
    .arp_dst_mac                        (arp_dst_mac               ),// (output)// 发送方MAC（来自ARP字段）
    .arp_dst_ip                         (arp_dst_ip                ),// (output)// 目标IP
    .arp_opcode                         (arp_opcode                ),// (output)// 1:请求, 2:响应
// ===================== 状态输出 ===================
    .arp_rx_error                       (arp_rx_error              ) // (output)// arp中任意一个协议对不上则拉高此信号
);

//////////////////////////////////////////    arp缓存与老化控制模块       //////////////////////////////////////////////

arp_cache#(
    .CACHE_SIZE                         (CACHE_SIZE                ),
    .AGING_SEC                          (AGING_SEC                 ),
    .CLOCK_FREQUENCY                    (CLOCK_FREQUENCY           ),
    .BROADCAST_MAC                      (48'hFF_FF_FF_FF_FF_FF     ),
    .PC_MAC                             (PC_MAC                    ),
    .PC_IP                              (PC_IP                     ) 
)
 u_arp_cache(
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
// ==================== ARP 接收 ====================
    .arp_frame_rx_done                  (arp_frame_rx_done_valid   ),// (input)arp包接收完成的脉冲，
    .arp_src_mac                        (arp_src_mac               ),// (input)
    .arp_src_ip                         (arp_src_ip                ),// (input)
    .arp_dst_mac                        (arp_dst_mac               ),// (input)
    .arp_dst_ip                         (arp_dst_ip                ),// (input)
    .arp_opcode                         (arp_opcode                ),// (input)// 1:请求 2:回复

// ==================== ARP 应答 ====================
    .arp_tx_reply_req_pulse             (arp_tx_reply_req_pulse    ),// (output)
    .arp_target_mac                     (arp_target_mac            ),// (output)
    .arp_target_ip                      (arp_target_ip             ),// (output)
// ==================== 本地配置 ====================
    .local_ip                           (FPGA_IP                   ) // (input)
// ==================== 查询接口 ====================该逻辑已弃用，保留接口
//    .query_ip                           (query_ip                  ),// (input)// 查询的ip,为0时代表撤销查询
//    .query_mac                          (query_mac                 ),// (output)// 查询的mac
//    .query_hit                          (query_hit                 ),// (output)// 查询命中
// ==================== ARP 主动请求====================该逻辑已弃用，保留接口
//    .arp_tx_request_req_pulse           (arp_tx_request_req_pulse  ),// (output)
//    .arp_tx_request_ip                  (arp_tx_request_ip         ),// (output)
//    .arp_tx_request_dst_mac             (arp_tx_request_dst_mac    ),// (output)// 广播 FF:FF:FF:FF:FF:FF
//    .arp_request_done                   (arp_request_done          ),// (output)// 请求完成，这个时候可以取用query_mac，同时告诉arp_requester可不必等待了
);

//////////////////////////////////////////    IP头接收模块       //////////////////////////////////////////////

ip_rx_engine#(
    .IP_VER                             (IP_VER                    ),
    .IP_SERVICE                         (IP_SERVICE                ),
    .IP_MARK                            (IP_MARK                   ),
    .IP_FRAG_OFFSET                     (IP_FRAG_OFFSET            ),
    .IP_TTL                             (IP_TTL                    ),
    .IP_PROTO_UDP                       (IP_PROTO_UDP              ),
    .IP_PROTO_ICMP                      (IP_PROTO_ICMP             ),
    .IP_CHECKSUM_CHECK_VALID            (IP_CHECKSUM_CHECK_VALID   ) 
)
 u_ip_rx_engine(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
// ==================== MAC层输入 ====================
    .ip_rx_data                         (ip_rx_data                ),// (input)
    .ip_rx_valid                        (ip_rx_valid               ),// (input)
    .ip_rx_start                        (ip_rx_start               ),// (input)
    .packet_is_ip                       (packet_is_ip              ),// (input)
    .packet_is_arp                      (packet_is_arp             ),// (input)
    .ip_byte_cnt                        (ip_byte_cnt               ),// (input)
    .gmii_rx_dv_fall                    (gmii_rx_dv_fall           ),// (input)
// ==================== 配置接口 ====================
    .local_ip                           (FPGA_IP                   ),// (input)// 本地IP地址
// ==================== 输出到UDP模块 ====================
    .udp_rx_data                        (udp_rx_data               ),// (output)
    .udp_rx_valid                       (udp_rx_valid              ),// (output)
    .udp_rx_start                       (udp_rx_start              ),// (output)// UDP包开始
    .udp_byte_cnt                       (udp_byte_cnt              ),// (output)
// ==================== 输出到ICMP模块 ====================
    .icmp_rx_data                       (icmp_rx_data              ),// (output)
    .icmp_rx_valid                      (icmp_rx_valid             ),// (output)
    .icmp_rx_start                      (icmp_rx_start             ),// (output)// UDP包开始
    .icmp_byte_cnt                      (icmp_byte_cnt             ),// (output)
    .icmp_length                        (icmp_length               ),// (output)
// ==================== 解析出的IP头信息 ====================
    .packet_is_udp                      (packet_is_udp             ),// (output)
    .packet_is_icmp                     (packet_is_icmp            ),// (output)
    .src_ip                             (src_ip                    ),// (output)
    .dest_ip                            (dest_ip                   ),// (output)
// ==================== 状态输出 ====================

    .ip_rx_error                        (ip_rx_error               ) // (output)
);

//////////////////////////////////////////    ICMP接收模块       //////////////////////////////////////////////


icmp_rx_engine#(
    .ICMP_ECHO_REQUEST                  (ICMP_ECHO_REQUEST         ),
    .ICMP_ECHO_REPLY                    (ICMP_ECHO_REPLY           ),
    .FPGA_MAC                           (FPGA_MAC                  ),
    .ICMP_CODE                          (ICMP_CODE                 ) 
)
 u_icmp_rx_engine(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
    .gmii_rx_dv_fall                    (gmii_rx_dv_fall           ),// (input)
    .recv_dst_mac                       (ip_dst_mac                ),// (input)
// ==================== IP层输入 ====================
    .icmp_rx_data                       (icmp_rx_data              ),// (input)
    .icmp_rx_valid                      (icmp_rx_valid             ),// (input)
    .icmp_rx_start                      (icmp_rx_start             ),// (input)// ICMP包开始
    .icmp_byte_cnt                      (icmp_byte_cnt             ),// (input)
    .icmp_length                        (icmp_length               ),// (input)// IP层开的小灶
    .packet_is_icmp                     (packet_is_icmp            ),// (input)// 辅助判断icmp的chencksum是否应该启动
// ==================== 解析出的 ICMP 数据 ====================
    .echo_reply_checksum                (icmp_reply_checksum       ),// (output)
    .echo_reply_checksum_valid          (icmp_reply_checksum_valid ),// (output)
    .icmp_identifier                    (icmp_identifier           ),// (output)// 标识符
    .icmp_sequence                      (icmp_sequence             ),// (output)// 序列号
// ==================== 状态输出 ====================
    .icmp_rx_error                      (icmp_rx_error             ),// (output)// 协议错误
// ====================写fifo信号，及写入的数据量  ====================
    .fifo_wr_en                         (wr_en_icmp_fifo           ),// (output)
    .fifo_din                           (din_icmp_fifo             ),// (output)
    .icmp_rx_fifo_full                  (full_icmp_fifo            ),// (input)// 谁写fifo，谁就要管full
    .icmp_wr_data_cnt                   (icmp_payload_count        ) // (output)// 读端靠着这个信号来读取多少数据
);

//===========================
//配套的icmp_payload_fifo,FWFT
icmp_payload_fifo icmp_payload_fifo (
    .clk                                (clk_125m                  ),// input wire clk
    .srst                               (srst_icmp_fifo            ),// input wire srst
    .din                                (din_icmp_fifo             ),// input wire [7 : 0] din
    .wr_en                              (wr_en_icmp_fifo           ),// input wire wr_en
    .full                               (full_icmp_fifo            ),// output wire full

    .dout                               (dout_icmp_fifo            ),// output wire [7 : 0] dout
    .rd_en                              (rd_en_icmp_fifo           ),// input wire rd_en
    .empty                              (empty_icmp_fifo           ),// output wire empty
    .data_count                         (                          ) // output wire [9 : 0] data_count   //调试用，实际不使用
);

//////////////////////////////////////////    UDP接收模块       //////////////////////////////////////////////


udp_rx_engine#(
    .FPGA_MAC                           (FPGA_MAC                  ),
    .UDP_VERC                           (UDP_VERC                  ) 
)
 u_udp_rx_engine(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
    .gmii_rx_dv_fall                    (gmii_rx_dv_fall           ),// (input)
    .recv_dst_mac                       (ip_dst_mac                ),// (input)
// ==================== 配置接口 ====================
    .local_port                         (SRC_PORT                  ),// (input)// 本地port
// ==================== IP层输入 ====================
    .udp_rx_data                        (udp_rx_data               ),// (input)
    .udp_rx_valid                       (udp_rx_valid              ),// (input)
    .udp_rx_start                       (udp_rx_start              ),// (input)// UDP包开始
    .udp_byte_cnt                       (udp_byte_cnt              ),// (input)
    .packet_is_udp                      (packet_is_udp             ),// (output)
// ==================== 状态输出 ====================
    .udp_rx_error                       (udp_rx_error              ),// (output)// 协议错误
// ====================写fifo信号，及写入的数据量  ====================
    .fifo_wr_en                         (wr_en_udp_fifo            ),// (output)
    .fifo_din                           (din_udp_fifo              ),// (output)
    .udp_rx_fifo_full                   (full_udp_fifo             ),// (input)// 谁写fifo，谁就要管full
    .udp_wr_data_cnt                    (udp_wr_data_cnt           ),// (output)
    .fifo_wr_rst_busy                   (wr_rst_busy_udp_fifo      ) //(input)// 谁写fifo，fifo复位忙
);

//===========================
//配套的udp_payload_fifo,FWFT
udp_payload_fifo udp_payload_fifo (
    .rst                                (rst_udp_fifo              ),// input wire rst
    .wr_clk                             (clk_125m                  ),// input wire wr_clk
    .din                                (din_udp_fifo              ),// input wire [7 : 0] din
    .wr_en                              (wr_en_udp_fifo            ),// input wire wr_en
    .full                               (full_udp_fifo             ),// output wire full
    .wr_data_count                      (                          ),// output wire [10 : 0] wr_data_count
    .wr_rst_busy                        (wr_rst_busy_udp_fifo      ),// output wire wr_rst_busy

    .rd_clk                             (rd_clk_udp_fifo           ),// input wire rd_clk
    .dout                               (dout_udp_fifo             ),// output wire [7 : 0] dout
    .rd_en                              (rd_en_udp_fifo            ),// input wire rd_en
    .empty                              (empty_udp_fifo            ),// output wire empty
    .rd_data_count                      (                          ),// output wire [10 : 0] rd_data_count
    .rd_rst_busy                        (rd_rst_busy_udp_fifo      ) // output wire rd_rst_busy
);
//===========================
//配套的xpm格雷码，同步计数器到目的时钟域，告知应用层，传来了多少数据
   xpm_cdc_gray #(
    .DEST_SYNC_FF                       (4                         ),// DECIMAL; range: 2-10
    .INIT_SYNC_FF                       (0                         ),// DECIMAL; 0=disable simulation init values, 1=enable simulation init values
    .REG_OUTPUT                         (1                         ),// DECIMAL; 0=disable registered output, 1=enable registered output
    .SIM_ASSERT_CHK                     (0                         ),// DECIMAL; 0=disable simulation messages, 1=enable simulation messages
    .SIM_LOSSLESS_GRAY_CHK              (0                         ),// DECIMAL; 0=disable lossless check, 1=enable lossless check
    .WIDTH                              (11                        ) // DECIMAL; range: 2-32
   )
   xpm_cdc_gray_inst (
    .dest_out_bin                       (udp_payload_count_gray_sync),// WIDTH-bit output: Binary input bus (src_in_bin) synchronized to
                                                                     // destination clock domain. This output is combinatorial unless REG_OUTPUT
                                                                     // is set to 1.
    .dest_clk                           (rd_clk_udp_fifo           ),// 1-bit input: Destination clock.
    .src_clk                            (clk_125m                  ),// 1-bit input: Source clock.
    .src_in_bin                         (udp_wr_data_cnt           ) // WIDTH-bit input: Binary input bus that will be synchronized to the
                                                                     // destination clock domain.
   );


//===================================================
//调试信息
reg pulse_single_1;
reg pulse_single_2;
reg pulse_single_3;
reg pulse_single_4;
reg pulse_single_5;
reg pulse_single_6;

    assign                              error_led[5]                = pulse_single_1;
    assign                              error_led[4]                = pulse_single_2;
    assign                              error_led[3]                = pulse_single_3;
    assign                              error_led[2]                = pulse_single_4;
    assign                              error_led[1]                = pulse_single_5;
    assign                              error_led[0]                = pulse_single_6;

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_1<=0;
                                                               else if(packet_is_ip)        //要观测的第一个脉冲
                pulse_single_1<=1;end

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_2<=0;
                                                               else if(ip_rx_error)//要观测的第二个脉冲
                pulse_single_2<=1;end

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_3<=0;
                                                              else if(mac_rx_error)//要观测的第二个脉冲
                pulse_single_3<=1;end

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_4<=0;
                                                             else if(crc_match)//要观测的第二个脉冲
                pulse_single_4<=1;end

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_5<=0;
                                                             else if(packet_is_udp)//要观测的第二个脉冲
                pulse_single_5<=1;end

    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n)
                pulse_single_6<=0;
                                                             else if(udp_rx_error)//要观测的第二个脉冲
                pulse_single_6<=1;end
endmodule
