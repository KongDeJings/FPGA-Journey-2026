`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/06/01 15:54:56
// Design Name: 
// Module Name: arp_rx_engine
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: ARP接收引擎，解析ARP包，错误检查在帧结束时独立完成
// 
// Dependencies: 
// 
// 代码中严禁出现魔数
//////////////////////////////////////////////////////////////////////////////////

module arp_rx_engine
#(
    parameter                           ARP_LENGTH                  = 52                   
)
(
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,
    input                               rst_n                      ,
    
    // ==================== MAC层输入 ====================
    input                [   7: 0]      arp_rx_data                ,
    input                               arp_rx_valid               ,
    input                               arp_rx_start               ,// ARP包开始
    input                [  15: 0]      arp_byte_cnt               ,
    input                               packet_is_arp              ,

    // ==================== 配置接口 ====================
    input                [  31: 0]      local_ip                   ,// 本地IP
    input                [  47: 0]      local_mac                  ,// 本地mac
    
    // ==================== 解析的ARP信息，输出给外面 ====================
    output reg           [  47: 0]      arp_src_mac                ,// 发送方MAC（来自以太网头部）
    output reg           [  31: 0]      arp_src_ip                 ,// 发送方IP
    output reg           [  47: 0]      arp_dst_mac                ,// 发送方MAC（来自ARP字段）
    output reg           [  31: 0]      arp_dst_ip                 ,// 目标IP
    output reg           [  15: 0]      arp_opcode                 ,// 1:请求, 2:响应

    // ===================== 状态输出 ===================
    output reg                          arp_rx_error               // ARP协议错误标志

);

// ==================== 本地参数定义 ====================
reg [1:0]   current_state, next_state;

localparam  IDLE               = 2'b01,
            S_PARSE_ARP        = 2'b10;    // 解析ARP头  

localparam ARP_HW_TYPE_ETHERNET     = 16'h0001;
localparam ARP_PROTO_TYPE_IPV4      = 16'h0800;

localparam ARP_HW_ADDR_LEN_ETH      = 8'd6;
localparam ARP_PROTO_ADDR_LEN_IPV4  = 8'd4;

localparam ARP_OPCODE_REQUEST       = 16'h0001;
localparam ARP_OPCODE_REPLY         = 16'h0002;

localparam ARP_NULL_MAC             = 48'h0;      // 请求时目的端MAC全填0

// 内部寄存器定义
    reg                  [  15: 0]      arp_hw_type                ;// 硬件类型
    reg                  [  15: 0]      arp_proto_type             ;// 协议类型
    reg                  [   7: 0]      arp_hw_len                 ;// 硬件地址长度
    reg                  [   7: 0]      arp_proto_len              ;// 协议地址长度
    reg                                 arp_ip_filter_match        ;// IP匹配标志（调试用）
    reg                                 arp_mac_filter_match       ;// MAC匹配标志（调试用）


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
        IDLE: begin
            if(arp_rx_start && arp_rx_valid)
                next_state = S_PARSE_ARP;
            else    
                next_state = IDLE;
        end
        S_PARSE_ARP: begin
            if(packet_is_arp && arp_rx_valid) begin
                if(arp_byte_cnt == ARP_LENGTH - 1) // 解析完则结束
                    next_state = IDLE;
                else
                    next_state = S_PARSE_ARP;
            end else begin // 不是ARP包，回到最初位置
                next_state = IDLE;
            end
        end
        default: next_state = IDLE;
    endcase
end

// ==================== 第三段：数据解析与输出 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        arp_src_mac        <= 48'h0;
        arp_src_ip         <= 32'h0;
        arp_dst_mac        <= 48'h0;
        arp_dst_ip         <= 32'h0;
        arp_opcode         <= 16'h0;
        arp_hw_type        <= 16'h0;
        arp_proto_type     <= 16'h0;
        arp_hw_len         <= 8'h0;
        arp_proto_len      <= 8'h0;
    end else begin
        case (current_state)
            IDLE: begin
                // 显式保持所有数据寄存器的值，避免隐式保持引发歧义
                arp_src_mac        <= arp_src_mac;
                arp_src_ip         <= arp_src_ip;
                arp_dst_mac        <= arp_dst_mac;
                arp_dst_ip         <= arp_dst_ip;
                arp_opcode         <= arp_opcode;
                arp_hw_type        <= arp_hw_type   ;
                arp_proto_type     <= arp_proto_type;
                arp_hw_len         <= arp_hw_len    ;
                arp_proto_len      <= arp_proto_len ;
            end

            S_PARSE_ARP: begin
                if(packet_is_arp && arp_rx_valid) begin
                    case (arp_byte_cnt)
                        0 : arp_hw_type[15:8]        <= arp_rx_data;
                        1 : arp_hw_type[7:0]         <= arp_rx_data;
                        2 : arp_proto_type[15:8]     <= arp_rx_data;
                        3 : arp_proto_type[7:0]      <= arp_rx_data;
                        4 : arp_hw_len               <= arp_rx_data;
                        5 : arp_proto_len            <= arp_rx_data;
                        6 : arp_opcode[15:8]         <= arp_rx_data;
                        7 : arp_opcode[7:0]          <= arp_rx_data;
                        8 : arp_src_mac[47:40]       <= arp_rx_data;
                        9 : arp_src_mac[39:32]       <= arp_rx_data;
                        10: arp_src_mac[31:24]       <= arp_rx_data;
                        11: arp_src_mac[23:16]       <= arp_rx_data;
                        12: arp_src_mac[15:8]        <= arp_rx_data;
                        13: arp_src_mac[7:0]         <= arp_rx_data;
                        14: arp_src_ip[31:24]        <= arp_rx_data;
                        15: arp_src_ip[23:16]        <= arp_rx_data;
                        16: arp_src_ip[15:8]         <= arp_rx_data;
                        17: arp_src_ip[7:0]          <= arp_rx_data;
                        18: arp_dst_mac[47:40]       <= arp_rx_data;
                        19: arp_dst_mac[39:32]       <= arp_rx_data;
                        20: arp_dst_mac[31:24]       <= arp_rx_data;
                        21: arp_dst_mac[23:16]       <= arp_rx_data;
                        22: arp_dst_mac[15:8]        <= arp_rx_data;
                        23: arp_dst_mac[7:0]         <= arp_rx_data;
                        24: arp_dst_ip[31:24]        <= arp_rx_data;
                        25: arp_dst_ip[23:16]        <= arp_rx_data;
                        26: arp_dst_ip[15:8]         <= arp_rx_data;
                        27: arp_dst_ip[7:0]          <= arp_rx_data;
                        // 对于未列出的字节，显式保持所有数据寄存器
                        default: begin
                            arp_src_mac    <= arp_src_mac;
                            arp_src_ip     <= arp_src_ip;
                            arp_dst_mac    <= arp_dst_mac;
                            arp_dst_ip     <= arp_dst_ip;
                            arp_opcode     <= arp_opcode;
                            arp_hw_type    <= arp_hw_type;
                            arp_proto_type <= arp_proto_type;
                            arp_hw_len     <= arp_hw_len;
                            arp_proto_len  <= arp_proto_len;
                        end
                    endcase
                end else begin
                    // 当条件不满足时，也显式保持
                    arp_src_mac        <= arp_src_mac;
                    arp_src_ip         <= arp_src_ip;
                    arp_dst_mac        <= arp_dst_mac;
                    arp_dst_ip         <= arp_dst_ip;
                    arp_opcode         <= arp_opcode;
                    arp_hw_type        <= arp_hw_type;
                    arp_proto_type     <= arp_proto_type;
                    arp_hw_len         <= arp_hw_len;
                    arp_proto_len      <= arp_proto_len;
                end
            end

            default: begin
                // 未定义状态，显式保持
                arp_src_mac        <= arp_src_mac;
                arp_src_ip         <= arp_src_ip;
                arp_dst_mac        <= arp_dst_mac;
                arp_dst_ip         <= arp_dst_ip;
                arp_opcode         <= arp_opcode;
                arp_hw_type        <= arp_hw_type;
                arp_proto_type     <= arp_proto_type;
                arp_hw_len         <= arp_hw_len;
                arp_proto_len      <= arp_proto_len;
            end
        endcase
    end
end

// ========================================
//错误检测
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        arp_rx_error         <= 1'b0;
        arp_ip_filter_match  <= 1'b0;
        arp_mac_filter_match <= 1'b0;
    end else if (packet_is_arp && arp_rx_valid && (arp_byte_cnt == 32)) begin
        // 帧结束时执行一次完整校验，先假设无错误
        arp_rx_error <= 1'b0;

        // 协议字段检查
        if (arp_hw_type != ARP_HW_TYPE_ETHERNET)
            arp_rx_error <= 1'b1;
        if (arp_proto_type != ARP_PROTO_TYPE_IPV4)
            arp_rx_error <= 1'b1;
        if (arp_hw_len != ARP_HW_ADDR_LEN_ETH)
            arp_rx_error <= 1'b1;
        if (arp_proto_len != ARP_PROTO_ADDR_LEN_IPV4)
            arp_rx_error <= 1'b1;
        if ((arp_opcode != ARP_OPCODE_REQUEST) && (arp_opcode != ARP_OPCODE_REPLY))
            arp_rx_error <= 1'b1;

        // IP 过滤
        if (arp_dst_ip != local_ip)
            arp_rx_error <= 1'b1;

        arp_ip_filter_match <= (arp_dst_ip == local_ip);

        // MAC 过滤
        if ((arp_dst_mac != local_mac)&&((arp_opcode==ARP_OPCODE_REPLY)))begin
            arp_rx_error <= 1'b1;
        arp_mac_filter_match <= (arp_dst_mac == local_mac);
        end
    end else begin
        // 非判断周期保持原有值不变，避免误清零
        arp_rx_error         <= arp_rx_error;
        arp_ip_filter_match  <= arp_ip_filter_match;
        arp_mac_filter_match <= arp_mac_filter_match;
    end
end

/*
// ==================== ILA 调试核心 ====================无法使用，clk_125m不能在上电很短时间内有效，无法加载dbg_hub
ila u_ila (
    .clk                                (clk_125m                  ),
    .probe0                             (current_state             ),// input wire [1:0]  probe0  
    .probe1                             (arp_rx_error              ),// input wire [0:0]  probe1 
    .probe2                             (arp_ip_filter_match       ),// input wire [0:0]  probe2 
    .probe3                             (arp_mac_filter_match      ),// input wire [0:0]  probe3 
    .probe4                             (arp_opcode                ),// input wire [15:0]  probe4 
    .probe5                             (arp_dst_ip                ),// input wire [31:0]  probe5 
    .probe6                             (arp_byte_cnt              ),// input wire [15:0]  probe6 
    .probe7                             (arp_rx_valid              ),// input wire [0:0]  probe7 
    .probe8                             (arp_rx_start              ),// input wire [0:0]  probe8 
    .probe9                             (packet_is_arp             ) // input wire [0:0]  probe9
);
*/


endmodule