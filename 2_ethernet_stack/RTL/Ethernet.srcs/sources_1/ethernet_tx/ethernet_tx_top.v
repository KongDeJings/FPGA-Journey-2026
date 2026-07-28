`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/07/06 20:45:58
// Design Name: 
// Module Name: ethernet_tx_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies:，产生udp_tx/icmp_tx的ip_checksum（复用）
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 代码中禁止出现魔数
//////////////////////////////////////////////////////////////////////////////////


module ethernet_tx_top
#(

//=========================协议重要参数配置=====================

    parameter                           PC_MAC                      = 48'h00E2_6969_EC7D   ,  // MAC: 00-E2-69-69-EC-7D
    parameter                           PC_IP                       = 32'hC0A8_0003        ,  // IP: 192.168.0.3
//    parameter                           FPGA_MAC                    = 48'h001A_2B3C_4D5E   ,  // MAC 00-1A-2B-3C-4D-5E 自定义
    parameter                           FPGA_MAC                    = 48'h020A_353C_4D5E   ,  // MAC 02-0A-35-3C-4D-5E 这是xilinx专用mac，可被wireshark识别到
    parameter                           FPGA_IP                     = 32'hC0A8_000A        ,  // 192.168.0.10
    parameter                           DST_PORT                    = 16'd54321            ,  // PC   端口
    parameter                           SRC_PORT                    = 16'd54322            ,  // FPGA 端口

    parameter                           PREAMBLE                    = 8'h55                ,
    parameter                           SFD                         = 8'hD5                ,
    parameter                           ETH_TYPE                    = 16'h0800             ,// 类型、长度域，0800代表IPV4
    parameter                           IP_VER                      = 8'h45                ,// 版本+首部长度
    parameter                           IP_SERVICE                  = 8'h00                ,// 服务类型
    parameter                           IP_MARK                     = 16'h0                ,//标识
    parameter                           IP_FRAG_OFFSET              = 16'h0                ,//标志+片偏移
    parameter                           IP_TTL                      = 8'h80                ,// TTL生存时间
//ARP

    parameter                           ARP_ETH_TYPE                = 16'h0806             ,// ARP类型
    parameter                           ARP_HW_TYPE_ETHERNET        = 16'h0001             ,// 以太网
    parameter                           ARP_PROTO_TYPE_IPV4         = 16'h0800             ,// IPv4
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
    parameter                           IFG_COUNT                   = 50                   //帧间间隔的周期数，96bit时间，要求12个字节，我多留了裕量，50个字节
    
)
(
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,
    input                               rst_n                      ,
    output reg           [   7: 0]      gmii_txd                   ,
    output reg                          gmii_tx_en                 ,
    // ==================== arp发送所需信号 ====================
    input                               arp_gmii_tx_ready          ,//背压信号
        // 来自 ARP cache（Request）
    input                               arp_request_start_pulse    ,
    input                [  31: 0]      arp_tx_request_ip          ,
    input                [  47: 0]      arp_tx_request_dst_mac     ,
        //来自 ARP Cache（Reply）
    input                               arp_reply_start_pulse      ,
    input                [  47: 0]      arp_target_mac             ,
    input                [  31: 0]      arp_target_ip              ,
        //状态接口 
    output reg                          arp_tx_busy                ,
    output                              arp_tx_done                ,
    // ==================== icmp发送所需信号 ====================  
    input                               icmp_start_pulse_primitive ,
    input                               icmp_gmii_tx_ready         ,
    input                [  15: 0]      icmp_reply_checksum        ,
    input                               icmp_reply_checksum_valid  ,
    input                [  15: 0]      icmp_identifier            ,// 标识符
    input                [  15: 0]      icmp_sequence              ,// 序列号
        //ICMP PAYLOAD数据接口
    output                              rd_en_icmp_fifo            ,
    input                [   7: 0]      dout_icmp_fifo             ,
    input                               empty_icmp_fifo            ,
    input                [  10: 0]      icmp_payload_count         ,
        //状态接口 
    output reg                          icmp_tx_busy               ,
    output                              icmp_tx_done               ,
    // ===================  UDP发送所需信号 ====================
    input                               udp_start_pulse_primitive  ,
    input                               udp_gmii_tx_ready          ,//背压信号

    output                              rd_en_udp_tx_fifo          ,
    input                [   7: 0]      dout_udp_tx_fifo           ,
    input                               empty_udp_tx_fifo          ,
    input                               rd_rst_busy_udp_tx_fifo    ,
    // UDP payload字节数
    input                [  10: 0]      udp_payload_count          ,
        //状态接口 
    output reg                          udp_tx_busy                ,
    output                              udp_tx_done                ,
    // ===================  PC的IP和MAC ====================
    input                [  47: 0]      pc_mac                     ,
    input                [  31: 0]      pc_ip                       

    );

//===============================================================================================================   
//本地参数及接口定义、连线
localparam  PREAMBLE_BYTES         = 8,      // 各个发送状态的字节数
            MAC_HEADER_BYTES       = 14,
            IP_HEADER_BYTES        = 20,
            ICMP_HEADER_BYTES      = 8,
            UDP_HEADER_BYTES      = 8;     

    ////////////////// ip_checksum计算模块，udp与icmp共用    ///////////////////
    reg                                 ip_checksum_calc_start     ;//校验和计算启动信号
    wire                                ip_checksum_calc_busy      ;
    wire                 [  15: 0]      ip_checksum                ;
    wire                                ip_checksum_valid          ;

        //直接到 PHY 物理层接口(GMII)
    wire                 [   7: 0]      arp_gmii_txd               ;
    wire                                arp_gmii_tx_en             ;

        //直接到 PHY 物理层接口(GMII)
    wire                 [   7: 0]      icmp_gmii_txd              ;
    wire                                icmp_gmii_tx_en            ;

        //直接到 PHY 物理层接口(GMII)
    wire                 [   7: 0]      udp_gmii_txd               ;
    wire                                udp_gmii_tx_en             ;

    ////////////////// RC校验和计算模块，三个模块共用   ///////////////////
    reg                                 crc_en_dynamic             ;
    reg                                 crc_frame_end_dynamic      ;
    reg                  [   7: 0]      crc_data_in_dynamic        ;
    reg                                 crc_data_valid_dynamic     ;
    wire                 [  31: 0]      crc_out_dynamic            ;
    wire                                crc_valid_dynamic          ;

//arp
    wire                                crc_en_arp                 ;
    wire                                crc_frame_end_arp          ;
    wire                 [   7: 0]      crc_data_in_arp            ;
    wire                                crc_data_valid_arp         ;
//icmp
    wire                                crc_en_icmp                ;
    wire                                crc_frame_end_icmp         ;
    wire                 [   7: 0]      crc_data_in_icmp           ;
    wire                                crc_data_valid_icmp        ;
//udp
    wire                                crc_en_udp                 ;
    wire                                crc_frame_end_udp          ;
    wire                 [   7: 0]      crc_data_in_udp            ;
    wire                                crc_data_valid_udp         ;

//===============================================================================================================
//逻辑输出
//==================================================================
//利用busy信号分时输出gmii_txd,gmii_tx_en
    always @(posedge clk_125m or negedge rst_n)
        begin
            if(!rst_n) begin
                gmii_txd   <=0;
                gmii_tx_en <=0;
            end
            else if(arp_tx_busy) begin
                gmii_txd   <=arp_gmii_txd  ;
                gmii_tx_en <=arp_gmii_tx_en;
            end
            else if(icmp_tx_busy) begin
                gmii_txd   <=icmp_gmii_txd  ;
                gmii_tx_en <=icmp_gmii_tx_en;
            end
            else if(udp_tx_busy) begin
                gmii_txd   <=udp_gmii_txd  ;
                gmii_tx_en <=udp_gmii_tx_en;
            end
            else begin
                gmii_txd   <=0;
                gmii_tx_en <=0;
            end
        end

//===================================================
//icmp/udp的启动信号
    reg                  [   1: 0]      icmp_start                 ;
    reg                  [   1: 0]      udp_start                  ;

    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                icmp_start<=0;                                                                                    
            else begin
                icmp_start[0]<=icmp_start_pulse_primitive;    
                icmp_start[1]<=icmp_start[0];    
            end                                          
        end         
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                udp_start<=0;                                                                                    
            else begin
                udp_start[0]<=udp_start_pulse_primitive;    
                udp_start[1]<=udp_start[0];    
            end                                          
        end                                      
//===================================================
//锁存icmp的checksum
reg [15:0]icmp_checksum;
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                icmp_checksum<=0;                                           
            else if(icmp_reply_checksum_valid)                                
                icmp_checksum<=icmp_reply_checksum ;                                                                                    
        end   


//===================================================
//icmp和ip的动态参数的锁存逻辑
    reg                  [  15: 0]      ip_length_dynamic          ;//计算时根据传过来的长度判断
    reg                  [   7: 0]      ip_protocol_dynamic        ;//udp和ip的上层协议不同，需判断

    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)begin
                ip_length_dynamic  <=0; 
                ip_protocol_dynamic<=0;       
            end                                                   
            else if(icmp_start_pulse_primitive) begin
                ip_length_dynamic  <=icmp_payload_count+IP_HEADER_BYTES+ICMP_HEADER_BYTES; 
                ip_protocol_dynamic<=ICMP_IP_PROTOCOL;  
            end                               
            else if(udp_start_pulse_primitive) begin
                ip_protocol_dynamic<=UDP_IP_PROTOCOL;  
                ip_length_dynamic  <=udp_payload_count+IP_HEADER_BYTES+UDP_HEADER_BYTES; 
            end  
            else begin
                ip_length_dynamic  <=ip_length_dynamic  ; 
                ip_protocol_dynamic<=ip_protocol_dynamic;                    
            end                                                                                
        end      

//===================================================
//icmp和ip的ip校验和计算逻辑
//开始ip校验和计算(产生开始信号)
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                ip_checksum_calc_start<=0;                                                                                    
            else if((icmp_start[1]||udp_start[1])&&~ip_checksum_calc_busy)   
                ip_checksum_calc_start<=1; 
            else
                ip_checksum_calc_start<=0;                                               
        end  

//锁存ip_checksum,icmp和udp的输出结果
reg [15:0]icmp_ip_checksum;
reg [15:0]udp_ip_checksum ;
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)begin
                icmp_ip_checksum<=0; 
                udp_ip_checksum<=0;       
            end                               
                                       
            else if(ip_checksum_valid) begin
                icmp_ip_checksum<=  ip_checksum;   
                udp_ip_checksum <=  ip_checksum;   
            end                               
                                                                                 
        end   

//==================================================================
//arp、icmp、udp的busy信号产生逻辑（包含IFG(给了15个时钟周期的延迟)）

//产生15个时钟周期的延时计数器
//产生使能
reg ifg_cnt_enable;
reg [($clog2(IFG_COUNT)-1):0]ifg_cnt;
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                ifg_cnt_enable<=0; 
            else if(ifg_cnt==(IFG_COUNT-1)) 
                ifg_cnt_enable<=0;                                                                                                                  
            else if(arp_tx_done||icmp_tx_done||udp_tx_done)   
                ifg_cnt_enable<=1;                            
        end  

    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                ifg_cnt<=0;                                                                                    
            else if(ifg_cnt==(IFG_COUNT-1))   
                ifg_cnt<=0; 
            else if(ifg_cnt_enable)
                ifg_cnt<=ifg_cnt+1;  
            else
                ifg_cnt<=0;                                                             
        end  

//=================arp_tx_busy
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                arp_tx_busy<=0;                                                                                    
            else if(ifg_cnt==(IFG_COUNT-1))   
                arp_tx_busy<=0;
            else if(arp_reply_start_pulse
                        ||arp_request_start_pulse)
                arp_tx_busy<=1;                                                            
        end  

//=================icmp_tx_busy
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                icmp_tx_busy<=0;                                                                                    
            else if(ifg_cnt==(IFG_COUNT-1))   
                icmp_tx_busy<=0;
            else if(icmp_start_pulse_primitive)
                icmp_tx_busy<=1;                                                            
        end  

//=================udp_tx_busy
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                udp_tx_busy<=0;                                                                                    
            else if(ifg_cnt==(IFG_COUNT-1))   
                udp_tx_busy<=0;
            else if(udp_start_pulse_primitive)
                udp_tx_busy<=1;                                                            
        end  

//===================================================
//CRC计算的动态锁存逻辑
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)begin
                crc_en_dynamic         <=0; 
                crc_frame_end_dynamic  <=0; 
                crc_data_in_dynamic    <=0; 
                crc_data_valid_dynamic <=0;    
            end                                                   
            else if(arp_tx_busy) begin
                crc_en_dynamic         <=crc_en_arp        ; 
                crc_frame_end_dynamic  <=crc_frame_end_arp ; 
                crc_data_in_dynamic    <=crc_data_in_arp   ; 
                crc_data_valid_dynamic <=crc_data_valid_arp;   
            end                               
            else if(icmp_tx_busy) begin
                crc_en_dynamic         <=crc_en_icmp        ; 
                crc_frame_end_dynamic  <=crc_frame_end_icmp ; 
                crc_data_in_dynamic    <=crc_data_in_icmp   ; 
                crc_data_valid_dynamic <=crc_data_valid_icmp;  
            end  
            else if(udp_tx_busy) begin
                crc_en_dynamic         <=crc_en_udp        ; 
                crc_frame_end_dynamic  <=crc_frame_end_udp ; 
                crc_data_in_dynamic    <=crc_data_in_udp   ; 
                crc_data_valid_dynamic <=crc_data_valid_udp;  
            end  
            else begin
                crc_en_dynamic         <=crc_en_dynamic        ; 
                crc_frame_end_dynamic  <=crc_frame_end_dynamic ; 
                crc_data_in_dynamic    <=crc_data_in_dynamic   ; 
                crc_data_valid_dynamic <=crc_data_valid_dynamic;                
            end                                                                                
        end
//===============================================================================================================
//调用底层模块
//////////////////////////////////////////    arp发送模块       //////////////////////////////////////////////

arp_tx_engine#(
    .PREAMBLE                           (PREAMBLE                  ),
    .SFD                                (SFD                       ),
    .ETH_TYPE_ARP                       (ARP_ETH_TYPE              ),
    .HW_TYPE_ETHERNET                   (ARP_HW_TYPE_ETHERNET      ),
    .PROTO_TYPE_IPV4                    (ARP_PROTO_TYPE_IPV4       ),
    .HW_SIZE                            (ARP_HW_SIZE               ),
    .PROTO_SIZE                         (ARP_PROTO_SIZE            ),
    .OPCODE_REQUEST                     (ARP_OPCODE_REQUEST        ),
    .OPCODE_REPLY                       (ARP_OPCODE_REPLY          ) 
)
 u_arp_tx_engine(
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
// ==================== 来自 ARP Cache（Reply） ====================
    .arp_reply_req                      (arp_reply_start_pulse     ),// (input)// 需要回 Reply
    .arp_target_mac                     (arp_target_mac            ),// (input)// 对方 MAC
    .arp_target_ip                      (arp_target_ip             ),// (input)// 对方 IP
// ==================== 来自 ARP Requester（Request） ====================
    .arp_tx_req                         (arp_request_start_pulse   ),// (input)// 需要发 Request
    .arp_tx_dst_mac                     (arp_tx_request_dst_mac    ),// (input)// 目的 MAC（广播）
    .arp_tx_ip                          (arp_tx_request_ip         ),// (input)// 要解析的 IP
// ==================== 直接到 PHY ====================
    .gmii_txd                           (arp_gmii_txd              ),// (output)// GMII发送数据
    .gmii_tx_en                         (arp_gmii_tx_en            ),// (output)// GMII发送使能,高电平有效信号
    .gmii_tx_ready                      (arp_gmii_tx_ready         ),// (input)// PHY准备好接收(关键背压信号)
// ==================== 本地配置 ====================
    .local_mac                          (FPGA_MAC                  ),// (input)
    .local_ip                           (FPGA_IP                   ),// (input)
// ==================== 控制接口 ====================
    .arp_tx_done                        (arp_tx_done               ), // (output)// 脉冲信号，一次发送完成
// ==================== CRC 计算模块接口 ====================
    .crc_en_arp                         (crc_en_arp                ),// (output)
    .crc_frame_end_arp                  (crc_frame_end_arp         ),// (output)
    .crc_data_in_arp                    (crc_data_in_arp           ),// (output)
    .crc_data_valid_arp                 (crc_data_valid_arp        ),// (output)
    .crc_result_arp                     (crc_out_dynamic           ),// (input)
    .crc_valid_arp                      (crc_valid_dynamic         ) // (input)
);

//////////////////////////////////////////    icmp发送模块       //////////////////////////////////////////////

icmp_tx_engine#(
    .PREAMBLE                           (PREAMBLE                  ),
    .SFD                                (SFD                       ),
    .ETH_TYPE                           (ETH_TYPE                  ),
    .IP_MARK                            (IP_MARK                   ),
    .IP_FRAG_OFFSET                     (IP_FRAG_OFFSET            ),
    .IP_VER                             (IP_VER                    ),
    .IP_SERVICE                         (IP_SERVICE                ),
    .IP_TTL                             (IP_TTL                    ),
    .IP_PROTOCOL                        (ICMP_IP_PROTOCOL          ),
    .ICMP_TYPE                          (ICMP_TYPE                 ),
    .ICMP_CODE                          (ICMP_CODE                 ) 
)
 u_icmp_tx_engine(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)// 主时钟 (125MHz, GMII时钟域)
    .rst_n                              (rst_n                     ),// (input)// 异步低有效复位，同步化后使用
// ==================== 控制接口 ====================
    .tx_start                           (icmp_start[1]             ),// (input)// 脉冲信号，启动一次ICMP发送
    .tx_done                            (icmp_tx_done              ),// (output)// 脉冲信号，一次发送完成
// ==================== 协议参数接口 ====================
// 注意：这些参数在tx_start有效时被锁存，发送过程中保持不变
    .dst_mac                            (pc_mac                    ),// (input)// 目的MAC地址
    .src_mac                            (FPGA_MAC                  ),// (input)// 源MAC地址
    .dst_ip                             (pc_ip                     ),// (input)// 目的IP地址
    .src_ip                             (FPGA_IP                   ),// (input)// 源IP地址
    .icmp_identifier                    (icmp_identifier           ),// (input)// ICMP标识符
    .icmp_sequence                      (icmp_sequence             ),// (input)// ICMP序列号
    .data_length                        (icmp_payload_count        ),// (input)// ICMP数据部分长度（字节）
    .ip_checksum                        (icmp_ip_checksum          ),// (input)// IP头校验和(提前计算好的)
    .icmp_checksum                      (icmp_checksum             ),// (input)// ICMP校验和(提前计算好的)
// ==================== 数据源接口(FIFO读侧) ====================
    // 使用异步FIFO，读侧时钟为clk_125m，FIFO必需为FWFT!
    .fifo_data                          (dout_icmp_fifo            ),// (input)// FIFO读数据
    .fifo_empty                         (empty_icmp_fifo           ),// (input)// FIFO空标志(关键背压信号)
    .fifo_rd_en                         (rd_en_icmp_fifo           ),// (output)// FIFO读使能
// ==================== 物理层接口(GMII) ====================
    .gmii_txd                           (icmp_gmii_txd             ),// (output)// GMII发送数据
    .gmii_tx_en                         (icmp_gmii_tx_en           ),// (output)// GMII发送使能,高电平有效信号
    .gmii_tx_ready                      (icmp_gmii_tx_ready        ), // (input)// PHY准备好接收(关键背压信号)
// ==================== CRC 计算模块接口 ====================
    .crc_en_icmp                        (crc_en_icmp               ),// (output)
    .crc_frame_end_icmp                 (crc_frame_end_icmp        ),// (output)
    .crc_data_in_icmp                   (crc_data_in_icmp          ),// (output)
    .crc_data_valid_icmp                (crc_data_valid_icmp       ),// (output)
    .crc_result_icmp                    (crc_out_dynamic           ),// (input)
    .crc_valid_icmp                     (crc_valid_dynamic         ) // (input)
);

//////////////////////////////////////////    udp发送模块       //////////////////////////////////////////////

udp_tx_engine#(
    .PREAMBLE                           (PREAMBLE                  ),
    .SFD                                (SFD                       ),
    .ETH_TYPE                           (ETH_TYPE                  ),
    .IP_VER                             (IP_VER                    ),
    .IP_SERVICE                         (IP_SERVICE                ),
    .IP_MARK                            (IP_MARK                   ),
    .IP_FRAG_OFFSET                     (IP_FRAG_OFFSET            ),
    .IP_TTL                             (IP_TTL                    ),
    .IP_PROTOCOL                        (UDP_IP_PROTOCOL           ),
    .UDP_VERC                           (UDP_VERC                  ) 
)
 u_udp_tx_engine(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)// 主时钟 (125MHz, GMII时钟域)
    .rst_n                              (rst_n                     ),// (input)// 异步低有效复位，同步化后使用
// ==================== 控制接口 ====================
    .tx_start                           (udp_start[1]              ),// (input)// 脉冲信号，启动一次UDP发送
    .tx_done                            (udp_tx_done               ),// (output)// 脉冲信号，一次发送完成
// ==================== 协议参数接口 ====================
// 注意：这些参数在tx_start有效时被锁存，发送过程中保持不变
    .dst_mac                            (pc_mac                    ),// (input)// 目的MAC地址
    .src_mac                            (FPGA_MAC                  ),// (input)// 源MAC地址
    .dst_ip                             (pc_ip                     ),// (input)// 目的IP地址
    .src_ip                             (FPGA_IP                   ),// (input)// 源IP地址
    .dst_port                           (DST_PORT                  ),// (input)// 目的UDP端口
    .src_port                           (SRC_PORT                  ),// (input)// 源UDP端口
    .data_length                        ({5'b0,udp_payload_count} ),// (input)// 注意，这里指的是纯数据长度，不含IP头和UDP头
    .ip_checksum                        (udp_ip_checksum           ),// (input)// IP头校验和(提前计算好的)
// ==================== 数据源接口(FIFO读侧) ====================
// 使用同步FIFO，时钟为clk_125m，FIFO必需为FWFT!
    .fifo_data                          (dout_udp_tx_fifo          ),// (input)// FIFO读数据
    .fifo_empty                         (empty_udp_tx_fifo         ),// (input)// FIFO空标志(关键背压信号)
    .fifo_rd_en                         (rd_en_udp_tx_fifo         ),// (output)// FIFO读使能
    .rd_rst_busy_udp_tx_fifo            (rd_rst_busy_udp_tx_fifo   ),//(input)
// ==================== 物理层接口(GMII) ====================
    .gmii_txd                           (udp_gmii_txd              ),// (output)// GMII发送数据
    .gmii_tx_en                         (udp_gmii_tx_en            ),// (output)// GMII发送使能,高电平有效信号
    .gmii_tx_ready                      (udp_gmii_tx_ready         ),// (input)// PHY准备好接收(关键背压信号)
// ==================== CRC 计算模块接口 ====================
    .crc_en_udp                         (crc_en_udp                ),// (output)
    .crc_frame_end_udp                  (crc_frame_end_udp         ),// (output)
    .crc_data_in_udp                    (crc_data_in_udp           ),// (output)
    .crc_data_valid_udp                 (crc_data_valid_udp        ),// (output)
    .crc_result_udp                     (crc_out_dynamic           ),// (input)
    .crc_valid_udp                      (crc_valid_dynamic         ) // (input)
);

//////////////////////////////////////////   ip_checksum计算模块，udp与icmp共用      //////////////////////////////////////////////

ip_checksum_pipeline u_udp_icmp_checksum_union(
// ==================== 全局信号 ====================
    .clk                                (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
// ==================== 并行输入接口 ====================
// 整个IP头
    .ip_hdr_0                           (IP_VER                    ),// (input)// 字节0: 版本+IHL
    .ip_hdr_1                           (IP_SERVICE                ),// (input)// 字节1: 服务类型
    .ip_hdr_2                           (ip_length_dynamic[15:8]   ),// (input)// 字节2: 总长度高8位
    .ip_hdr_3                           (ip_length_dynamic[7:0]    ),// (input)// 字节3: 总长度低8位
    .ip_hdr_4                           (IP_MARK[15:8]             ),// (input)// 字节4: 标识高8位
    .ip_hdr_5                           (IP_MARK[7:0]              ),// (input)// 字节5: 标识低8位
    .ip_hdr_6                           (IP_FRAG_OFFSET[15:8]      ),// (input)// 字节6: 标志+片偏移高8位
    .ip_hdr_7                           (IP_FRAG_OFFSET [7:0]      ),// (input)// 字节7: 标志+片偏移低8位
    .ip_hdr_8                           (IP_TTL                    ),// (input)// 字节8: TTL
    .ip_hdr_9                           (ip_protocol_dynamic       ),// (input)// 字节9: 协议
// 字节10-11: 校验和字段（计算时视为0，不输入）
    .ip_hdr_12                          (FPGA_IP[31:24]            ),// (input)// 字节12: 源IP[31:24]
    .ip_hdr_13                          (FPGA_IP[23:16]            ),// (input)// 字节13: 源IP[23:16]
    .ip_hdr_14                          (FPGA_IP[15:8]             ),// (input)// 字节14: 源IP[15:8]
    .ip_hdr_15                          (FPGA_IP[7:0]              ),// (input)// 字节15: 源IP[7:0]
    .ip_hdr_16                          (pc_ip[31:24]              ),// (input)// 字节16: 目的IP[31:24]
    .ip_hdr_17                          (pc_ip[23:16]              ),// (input)// 字节17: 目的IP[23:16]
    .ip_hdr_18                          (pc_ip[15:8]               ),// (input)// 字节18: 目的IP[15:8]
    .ip_hdr_19                          (pc_ip[7:0]                ),// (input)// 字节19: 目的IP[7:0]
// ==================== 控制信号及输出结果 ====================
    .calc_start                         (ip_checksum_calc_start    ),// (input)// 脉冲,启动计算
    .calc_busy                          (ip_checksum_calc_busy     ),// (output)// 计算忙，忙时忽略新的启动信号
    .checksum                           (ip_checksum               ),// (output)// 校验和
    .checksum_valid                     (ip_checksum_valid         ) // (output)// 校验和有效
);

//////////////////////////////////////////  CRC校验和计算模块，三个模块共用     //////////////////////////////////////////////

//=================================================
//连接CRC计算
/*
空闲状态 → en=0 → CRC 寄存器保持不变
前导码(7字节) + SFD(1字节) → en=0 （不计算CRC）
目的MAC(6) + 源MAC(6) + 类型(2) + 数据(...) → en=1 （计算CRC）
CRC字段(4) → en=0 （不计算，这个位置放结果）
帧发送结束 → en=0 → 停止计算，输出最终的 CRC 结果
*/
eth_crc32_parallel eth_crc32_TX(
    .clk                                (clk_125m                  ),
    .rst_n                              (rst_n                     ),
    .crc_en                             (crc_en_dynamic            ),// 帧有效期间为1
    .frame_end                          (crc_frame_end_dynamic     ),// 最后一个数据字节时为1
    .data_in                            (crc_data_in_dynamic       ),// MSB-first输入
    .data_valid                         (crc_data_valid_dynamic    ),
    .crc_out                            (crc_out_dynamic           ),
    .crc_valid                          (crc_valid_dynamic         ) // CRC结果有效
);

endmodule
