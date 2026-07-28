`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/01 07:48:33
// Design Name: 
// Module Name: udp_rx_engine
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: UDP接收引擎，解析UDP包，将解析到的数据以axi_stream形式送出，支持背压逻辑
// 
// 
//////////////////////////////////////////////////////////////////////////////////
module udp_rx_engine
#(
    parameter                           FPGA_MAC                    = 48'h020A_353C_4D5E   ,  // MAC 02-0A-35-3C-4D-5E 这是xilinx专用mac，可被wireshark识别到
    parameter                           UDP_VERC                    = 16'h0                 //UDP校验和，不做校验，空置为0
)
(
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,
    input                               rst_n                      ,
    input                               gmii_rx_dv_fall            ,
    input                [  47: 0]      recv_dst_mac               ,// 接受到的mac，用以辅助判断这包payload是否应该接受
    // ==================== 配置接口 ====================
    input                [  15: 0]      local_port                 ,// 本地port  

    // ==================== IP层输入 ====================
    input                [   7: 0]      udp_rx_data                ,
    input                               udp_rx_valid               ,
    input                               udp_rx_start               ,// UDP包开始
    input                [  15: 0]      udp_byte_cnt               ,
    input                               packet_is_udp              ,
    

    // ==================== 状态输出 ====================
    output reg                          udp_rx_error              ,// 协议错误

    // ====================写fifo信号，及写入的数据量  ====================
    output reg                          fifo_wr_en                 ,
    output reg           [   7: 0]      fifo_din                   ,
    input                               udp_rx_fifo_full           ,//谁写fifo，谁就要管full
    input                               fifo_wr_rst_busy           ,
    output reg           [  10: 0]      udp_wr_data_cnt             
    );

// ==================== 本地参数定义 ====================
reg [2:0]   current_state, next_state;

localparam  IDLE              = 3'b001,
            S_PARSE_UDP_HDR   = 3'b010,    // 解析UDP头  
            S_PAYLOAD         = 3'b100;    // 解析UDP负载的数据

    localparam                          UDP_HEADER_BYTES            = 8                    ;
    localparam                          IP_HEADER_BYTES             = 20                   ;
    localparam                          PREAMBLE_BYTES              = 8                    ;
    localparam                          FCS_BYTES                   = 4                    ;
//本地寄存器定义

    reg                  [  15: 0]      src_port_recv              ;
    reg                  [  15: 0]      dst_port_recv              ;
    reg                  [  15: 0]      udp_len_recv               ;//这个值与ip头里解析的长度相差20（IVP4,无特殊情况！，可用以状态机）


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
            if(udp_rx_start&&udp_rx_valid)
                next_state=S_PARSE_UDP_HDR;
            else    
                next_state = IDLE;
        end
        S_PARSE_UDP_HDR:begin
            if(udp_rx_valid)begin
                if(udp_byte_cnt==IP_HEADER_BYTES+UDP_HEADER_BYTES-1)//头的内容解析完成，跳转到计算校验和状态
                    next_state = S_PAYLOAD ;
                else
                    next_state=S_PARSE_UDP_HDR;
            end
            else
                next_state = IDLE;
        end
        S_PAYLOAD     :begin
            if(udp_rx_valid)begin
                if(udp_byte_cnt==(udp_len_recv+IP_HEADER_BYTES-1))//为什么敢用udp_len_recv,如果错了，最后一步的crc校验就是错的，丢弃数据！
                    next_state = IDLE ;
                else
                    next_state=S_PAYLOAD;
            end
            else
                next_state = IDLE;
        end
            default: next_state = IDLE;
        endcase
    end

// ==================== 第三段：输出逻辑 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        src_port_recv      <=0;
        dst_port_recv      <=0;
        udp_len_recv       <=0;
        fifo_wr_en         <=0;
        fifo_din           <=0;
    end 
    else begin    
        case (current_state)
        IDLE          :begin
        fifo_wr_en <=0;
        fifo_din   <=0;
        end
        S_PARSE_UDP_HDR:begin
            case (udp_byte_cnt)
                20: src_port_recv[15:8] <= udp_rx_data;  // 源端口
                21: src_port_recv[7:0]  <= udp_rx_data;
                22: dst_port_recv[15:8] <= udp_rx_data;  // 目的端口
                23: dst_port_recv[7:0]  <= udp_rx_data;
                24: udp_len_recv[15:8]  <= udp_rx_data;  // UDP长度
                25: udp_len_recv[7:0]   <= udp_rx_data;

                default: begin
                    src_port_recv      <=src_port_recv ;
                    dst_port_recv      <=dst_port_recv ;
                    udp_len_recv       <=udp_len_recv  ;                    
                end
            endcase
        end
        S_PAYLOAD : begin
            if (udp_rx_valid
                    &&(recv_dst_mac==FPGA_MAC)
                        &&~udp_rx_fifo_full                    //这个条件仿真时需注释掉
                            &&~fifo_wr_rst_busy) begin
                fifo_wr_en <= 1;
                fifo_din   <= udp_rx_data;
                end
             else begin
                fifo_wr_en <= 0;
                fifo_din   <= 8'd0;
            end  

end
            default: begin
    //保持，什么都不做
            end
        endcase
    end
end


//=================================================
//产生fifo写入计数器计数，等读的时候靠着这个值来读
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n)
        udp_wr_data_cnt <= 0;
    else if(current_state == S_PARSE_UDP_HDR)
        udp_wr_data_cnt <= 0;
    else if (current_state == S_PAYLOAD &&
             udp_rx_valid)
        udp_wr_data_cnt <= udp_wr_data_cnt+1;
    else
        udp_wr_data_cnt <= udp_wr_data_cnt;
end

//=================================================
//处理错误信号
always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n)
        udp_rx_error<=0;
        else  if(gmii_rx_dv_fall&&packet_is_udp)begin
                 if (( dst_port_recv != local_port))
                         udp_rx_error <= 1;
                
                else
                    udp_rx_error<=0;
            end
            else
                udp_rx_error<=0;
end
endmodule
