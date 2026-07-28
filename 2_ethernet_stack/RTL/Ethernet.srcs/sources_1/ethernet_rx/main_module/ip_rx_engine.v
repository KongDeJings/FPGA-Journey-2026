`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDejing
// 
// Create Date: 2026/05/31 09:52:27
// Design Name: 
// Module Name: ip_rx_engine
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: IP层接收引擎，解析IP包，分发到UDP或ICMP
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ip_rx_engine
#(
    parameter                           IP_VER                      = 8'h45                ,//版本+首部长度
    parameter                           IP_SERVICE                  = 8'h0                 ,//服务类型
    parameter                           IP_MARK                     = 16'h0                ,//标识
    parameter                           IP_FRAG_OFFSET              = 16'h0                ,//标志+片偏移
    parameter                           IP_TTL                      = 8'h80                ,//TTL生存时间
    parameter                           IP_PROTO_UDP                = 8'h11                ,
    parameter                           IP_PROTO_ICMP               = 8'h01                ,
    parameter                           IP_CHECKSUM_CHECK_VALID     = 0                    
)
(
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,
    input                               rst_n                      ,

    // ==================== MAC层输入 ====================

    input                [   7: 0]      ip_rx_data                 ,
    input                               ip_rx_valid                ,
    input                               ip_rx_start                ,
    input                               packet_is_ip               ,
    input                               packet_is_arp              ,
    input                [  15: 0]      ip_byte_cnt                ,
    input                               gmii_rx_dv_fall            ,

    // ==================== 配置接口 ====================
    input                [  31: 0]      local_ip                   ,// 本地IP地址    

    // ==================== 输出到UDP模块 ====================
    output               [   7: 0]      udp_rx_data                ,
    output                              udp_rx_valid               ,
    output reg                          udp_rx_start               ,// UDP包开始
    output               [  15: 0]      udp_byte_cnt               ,
    
    // ==================== 输出到ICMP模块 ====================
    output               [   7: 0]      icmp_rx_data               ,
    output                              icmp_rx_valid              ,
    output reg                          icmp_rx_start              ,// UDP包开始
    output               [  15: 0]      icmp_byte_cnt              ,
    output               [  15: 0]      icmp_length                ,

    // ==================== 解析出的IP头信息 ====================
    output reg                          packet_is_udp              ,
    output reg                          packet_is_icmp             ,
    output reg           [  31: 0]      src_ip                     ,
    output reg           [  31: 0]      dest_ip                    ,

    // ==================== 状态输出 ====================

    output reg                          ip_rx_error                //ip解析模块输出的唯一错误信号

    );

// ==================== 本地参数定义 ====================
reg [2:0]   current_state, next_state;

localparam  IDLE               = 3'b001,
            S_PARSE_IP_HDR     = 3'b010,    // 解析IP头  
            S_CHECKSUM         = 3'b100;    // 计算IP校验和状态

localparam  IP_HEADER_BYTES        = 20 ;

//本地寄存器定义
//以下全为ip头中的内容           
    reg                  [   3: 0]      ip_version                 ;// 版本号 (4)
    reg                  [   3: 0]      ip_ihl                     ;// 首部长度 (单位: 4B)
    reg                  [   5: 0]      ip_dscp                    ;// 差分服务码点
    reg                  [   1: 0]      ip_ecn                     ;// 显式拥塞通知
    reg                  [  15: 0]      ip_total_len               ;// 总长度（header + payload）
    reg                  [  15: 0]      ip_id                      ;// 标识
    reg                  [  15: 0]      ip_flags_frag_offset       ;// 片偏移
    reg                  [   7: 0]      ip_ttl                     ;// 生存时间
    reg                  [   7: 0]      ip_protocol                ;// 协议类型（1=ICMP, 6=TCP, 17=UDP）
    reg                  [  15: 0]      ip_checksum_recv            ;// 首部校验和
//checksum计算相关
    reg                                 calc_start                 ;

    wire                                calc_busy                  ;
    wire                 [  15: 0]      checksum_calc              ;//计算出来的checksum
    wire                                checksum_valid             ;

 reg                          ip_checksum_match          ;//接收的校验和与计算的校验和要能对上            
 reg                          ip_fillter_match           ;//接收的信息与本地IP对不上，这不是发给我的，对上了才拉高这个信号
 reg                          ip_message_error           ;//IP头里面有任何一个信号对不上，就拉高这个错误信号  
 reg                          ip_header_done             ;//ip_checksum_valid拉高后拉高，ip_rx_valid拉低后拉低

//传承
assign udp_byte_cnt   = ip_byte_cnt;
assign icmp_byte_cnt = ip_byte_cnt;

assign udp_rx_data =ip_rx_data ;
assign udp_rx_valid=ip_rx_valid;

assign icmp_rx_data  =ip_rx_data ;
assign icmp_rx_valid =ip_rx_valid;
assign icmp_length   =ip_total_len;
//////////////////////////////////////////////////////////////////////////////////

//=================================================
//产生ip_header_done
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                ip_header_done<=0;
            else if(!ip_rx_valid)//当以太网传输结束后，拉低此信号
                ip_header_done<=0;
            else if(checksum_valid)//校验和计算完成，代表IP头接收解析所有事已完成
                ip_header_done<=1;
            else
                ip_header_done<=ip_header_done;                   
        end  

//=================================================
//产生ip_checksum_match
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                ip_checksum_match<=0;
            else if(!ip_rx_valid)//当以太网传输结束后，拉低此信号
                ip_checksum_match<=0;
            else if(checksum_valid) begin//校验和计算完成，代表IP头接收解析所有事已完成
                if(ip_checksum_recv==checksum_calc)
                    ip_checksum_match<=1;
                else    
                    ip_checksum_match<=0;
            end
            else
                ip_checksum_match<=ip_checksum_match;
        end  
//=================================================
//产生ip_fillter_match
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                ip_fillter_match<=0;
            else if(!ip_rx_valid)//当以太网传输结束后，拉低此信号
                ip_fillter_match<=0;
            else if(dest_ip==local_ip)
                ip_fillter_match<=1;
            else
                ip_fillter_match<=ip_fillter_match;
        end  
//=================================================
//产生ip_message_error
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                ip_message_error<=0;
            else if(!ip_rx_valid)//当以太网传输结束后，拉低此信号
                ip_message_error<=0;
            else if((current_state==S_PARSE_IP_HDR)&&(ip_byte_cnt==18))begin
                if((ip_protocol!=IP_PROTO_UDP)&&(ip_protocol!=IP_PROTO_ICMP))
                    ip_message_error    <=1  ;                    
            end
            else if(current_state==S_CHECKSUM)begin
               if(     ({ip_version,ip_ihl} !=IP_VER        )||
                    ({ip_dscp,ip_ecn}       !=IP_SERVICE    )||
//                    (ip_id                  !=IP_MARK       )||           //PC发的包，这个字段不为0，这个字段取消检查
//                    (ip_flags_frag_offset   !=IP_FRAG_OFFSET)||           //PC发的包，这个字段不为0，这个字段取消检查
                    (ip_ttl                 !=IP_TTL        )      )
                                ip_message_error    <=1  ;

            end
            else
                    ip_message_error    <=ip_message_error  ;
        end  

//=================================================
//产生ip_rx_error
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n)                                                             
               ip_rx_error<=0;                                                  
            else if(gmii_rx_dv_fall&&packet_is_ip) begin
                if(((~ip_checksum_match)&&IP_CHECKSUM_CHECK_VALID)||(~ip_fillter_match))//增加了CHECKSUM使能，默认关闭
                    ip_rx_error<=1;
                else if(ip_message_error) 
                    ip_rx_error<=1;
                else
                    ip_rx_error<=0;                      

            end   
            else
                ip_rx_error<=0;                                              
        end    

// ==================== 第一段：状态转移 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
    end else begin
        current_state <= next_state;
    end
end

// ==================== 第二段：下一状态逻辑 ====================
    always @(*) begin
        case (current_state)
        IDLE          :begin
            if(ip_rx_start&&ip_rx_valid)
                next_state=S_PARSE_IP_HDR;
            else    
                next_state = IDLE;
        end
        S_PARSE_IP_HDR:begin
            if(packet_is_ip&&ip_rx_valid)begin
                if(ip_byte_cnt==IP_HEADER_BYTES-1)//头的内容解析完成，跳转到计算校验和状态
                    next_state = S_CHECKSUM ;
                else
                    next_state=S_PARSE_IP_HDR;
            end
            else //不是IP包，回到最初位置
                next_state = IDLE;
        end
        S_CHECKSUM    :begin
            if(!ip_rx_valid)
                next_state = IDLE;
            else
                next_state =S_CHECKSUM;
        end
            default: next_state = IDLE;
        endcase
    end

// ==================== 第三段：输出逻辑 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        ip_version          <=0  ;              calc_start          <=0  ;//ip_checksum的启动信号                       
        ip_ihl              <=0  ;              udp_rx_start        <=0  ;packet_is_udp <=0;// udp的启动信号以及标志信号                     
        ip_dscp             <=0  ;              icmp_rx_start       <=0  ;packet_is_icmp<=0;//icmp的启动信号以及标志信号                
        ip_ecn              <=0  ;            
        ip_total_len        <=0  ;                                
        ip_id               <=0  ;                                               
        ip_flags_frag_offset<=0  ;                                     
        ip_ttl              <=0  ;  // 生存时间                                  
        ip_protocol         <=0  ;  // 协议类型（1=ICMP, 6=TCP, 17=UDP）            
        ip_checksum_recv     <=0  ;  // 首部校验和                           
        src_ip              <=0  ;  // 解析出的源IP                        
        dest_ip             <=0  ;  // 解析出的目的IP                         
  
    end 
    else begin    
            if(ip_byte_cnt==22)begin
                 udp_rx_start        <=0  ;
                icmp_rx_start       <=0  ;
            end



        case (current_state)
        IDLE          :begin
            calc_start          <=0  ;//ip_checksum的启动信号                       
            udp_rx_start        <=0  ;packet_is_udp <=0;// udp的启动信号以及标志信号                     
            icmp_rx_start       <=0  ;packet_is_icmp<=0;//icmp的启动信号以及标志信号                                                     
        end
        S_PARSE_IP_HDR:begin
            if(packet_is_ip&&ip_rx_valid)begin
                case (ip_byte_cnt)
                    0 :{ip_version,ip_ihl}       <=ip_rx_data;
                    1 :{ip_dscp,ip_ecn}          <=ip_rx_data;
                    2 :ip_total_len[15:8]        <=ip_rx_data;
                    3 :ip_total_len[7:0]         <=ip_rx_data;
                    4 :ip_id[15:8]               <=ip_rx_data;
                    5 :ip_id[7:0]                <=ip_rx_data;
                    6 :ip_flags_frag_offset[15:8]<=ip_rx_data;
                    7 :ip_flags_frag_offset[7:0] <=ip_rx_data;
                    8 :ip_ttl                    <=ip_rx_data;
                    9 :ip_protocol               <=ip_rx_data;
                    10:ip_checksum_recv[15:8]    <=ip_rx_data;
                    11:ip_checksum_recv[7:0]     <=ip_rx_data;
                    12:src_ip[31:24]             <=ip_rx_data;
                    13:src_ip[23:16]             <=ip_rx_data;
                    14:src_ip[15:8]              <=ip_rx_data;
                    15:src_ip[7:0]               <=ip_rx_data;
                    16:dest_ip[31:24]            <=ip_rx_data;
                    17:dest_ip[23:16]            <=ip_rx_data;
                    18:begin 
                        dest_ip[15:8]<=ip_rx_data;
                        if(ip_protocol==IP_PROTO_UDP)begin
                            udp_rx_start<=1;
                            icmp_rx_start<=0;
                            packet_is_udp <=1;
                            packet_is_icmp<=0;
                        end

                        else if(ip_protocol==IP_PROTO_ICMP)begin
                            icmp_rx_start<=1;
                            udp_rx_start<=0;
                            packet_is_udp <=0;
                            packet_is_icmp<=1;
                        end
                        else begin//如果两个都不是，那么代表协议错误
                            icmp_rx_start<=0;
                            udp_rx_start<=0;
                            packet_is_udp <=packet_is_udp ;
                            packet_is_icmp<=packet_is_icmp;
                        end

                    end
                    19: dest_ip[7:0]<=ip_rx_data;
//                    default: 
                endcase
            end
        end
        S_CHECKSUM    :begin   //在这个状态下还要完成信息确认工作
            if(packet_is_ip&&ip_rx_valid&&ip_byte_cnt==20&&!calc_busy) //只产生一个周期的ip_checksum计算启动脉冲信号,只在所有信号有效，且不忙的那个时间窗口内
                calc_start<=1;
            else
                calc_start<=0;

        end

            default: begin
                    // 复位所有寄存器            
        ip_version          <=0  ;              calc_start          <=0  ;//ip_checksum的启动信号                       
        ip_ihl              <=0  ;              udp_rx_start        <=0  ;packet_is_udp <=0;// udp的启动信号以及标志信号                       
        ip_dscp             <=0  ;              icmp_rx_start       <=0  ;packet_is_icmp<=0;//icmp的启动信号以及标志信号                 
        ip_ecn              <=0  ;                                     
        ip_total_len        <=0  ;                             
        ip_id               <=0  ;                                                   
        ip_flags_frag_offset<=0  ;                                   
        ip_ttl              <=0  ;  // 生存时间                                  
        ip_protocol         <=0  ;  // 协议类型（1=ICMP, 6=TCP, 17=UDP）            
        ip_checksum_recv     <=0 ;  // 首部校验和                           
        src_ip              <=0  ;  // 解析出的源IP                        
        dest_ip             <=0  ;  // 解析出的目的IP   
            end
        endcase
    end
end

//////////////////////////////////////////////////////////////////////////////////
//连接checksum_pipeline计算

ip_checksum_pipeline u_ip_checksum_pipeline(
// ==================== 全局信号 ====================
    .clk                                (clk_125m                  ),
    .rst_n                              (rst_n                     ),
// ==================== 并行输入接口 ====================
// 整个IP头
    .ip_hdr_0                           ({ip_version,ip_ihl}       ),// 字节0: 版本+IHL
    .ip_hdr_1                           ({ip_dscp,ip_ecn}          ),// 字节1: 服务类型
    .ip_hdr_2                           (ip_total_len[15:8]        ),// 字节2: 总长度高8位
    .ip_hdr_3                           (ip_total_len[7:0]         ),// 字节3: 总长度低8位
    .ip_hdr_4                           (ip_id[15:8]               ),// 字节4: 标识高8位
    .ip_hdr_5                           (ip_id[7:0]                ),// 字节5: 标识低8位
    .ip_hdr_6                           (ip_flags_frag_offset[15:8]),// 字节6: 标志+片偏移高8位
    .ip_hdr_7                           (ip_flags_frag_offset[7:0] ),// 字节7: 标志+片偏移低8位
    .ip_hdr_8                           (ip_ttl                    ),// 字节8: TTL
    .ip_hdr_9                           (ip_protocol               ),// 字节9: 协议
// 字节10-11: 校验和字段（计算时视为0，不输入）
    .ip_hdr_12                          (src_ip[31:24]             ),// 字节12: 源IP[31:24]
    .ip_hdr_13                          (src_ip[23:16]             ),// 字节13: 源IP[23:16]
    .ip_hdr_14                          (src_ip[15:8]              ),// 字节14: 源IP[15:8]
    .ip_hdr_15                          (src_ip[7:0]               ),// 字节15: 源IP[7:0]
    .ip_hdr_16                          (dest_ip[31:24]            ),// 字节16: 目的IP[31:24]
    .ip_hdr_17                          (dest_ip[23:16]            ),// 字节17: 目的IP[23:16]
    .ip_hdr_18                          (dest_ip[15:8]             ),// 字节18: 目的IP[15:8]
    .ip_hdr_19                          (dest_ip[7:0]              ),// 字节19: 目的IP[7:0]
// ==================== 控制信号及输出结果 ====================
    .calc_start                         (calc_start                ),// 脉冲,启动计算
    .calc_busy                          (calc_busy                 ),// 计算忙，忙时忽略新的启动信号
    .checksum                           (checksum_calc             ),// 校验和
    .checksum_valid                     (checksum_valid            ) // 校验和有效
);

endmodule


