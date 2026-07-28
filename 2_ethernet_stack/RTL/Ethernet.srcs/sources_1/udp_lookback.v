`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/19 07:06:53
// Design Name: 
// Module Name: udp_lookback
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: UDP 回环控制模块，从接收 FIFO 读出字节，直接以 8bit 写入发送 FIFO
//              (已改为纯转发，无拼接，FWFT 时序适配)
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - 改为 8bit 直通，去掉字节拼接和 S_LAST_WORD 状态
// Additional Comments:
// 2026-07-20 修复：增加 rx_done_latched 锁存机制，避免因 FIFO 复位忙错过接收完成脉冲
// 
//////////////////////////////////////////////////////////////////////////////////

module udp_lookback(
    // ==================== 系统时钟与复位 ====================
    input                               clk                        ,
    input                               rst_n                      ,
    // ==================== UDP数据流接口 ====================   
    // 以太网接收到的payload, 这个fifo在接收模块中，给消费者读接口
    input                               udp_frame_rx_done_valid    ,
    input                [  10: 0]      udp_rx_payload_count_gray_sync, // 接收到的有效载荷字节数
    input                               rd_rst_busy_udp_rx_fifo    ,
    input                [   7: 0]      dout_udp_rx_fifo           ,
    input                               empty_udp_rx_fifo          ,
    output reg                          rd_en_udp_rx_fifo          ,

    // 应用端写接口，写入fifo，udp发送端通过读fifo，获取payload数据
    output           [   7: 0]      din_udp_tx_fifo            ,   
    output reg                          wr_en_udp_tx_fifo          ,
    input                               full_udp_tx_fifo           ,
    input                [  10: 0]      wr_data_count_udp_tx_fifo  ,
    input                               wr_rst_busy_udp_tx_fifo     
    );
    
//===============================================================================================================

    //状态机状态定义
    reg  [1:0]   current_state, next_state;

    localparam    S_IDLE              = 2'd0,    // 空闲，等待接收完成  锁存有效载荷总字节数，并清空内部计数器
                  S_READ_AND_WRITE    = 2'd1,    // 读取一个字节并立即写入（FWFT 直通）
                  S_DONE              = 2'd2;    // 操作完成，回到空闲

    //内部辅助寄存器
    reg  [10:0]  total_bytes_r;                  // 锁存的有效载荷字节数
    reg  [10:0]  byte_cnt;                       // 已处理的字节计数

    assign                              din_udp_tx_fifo             = dout_udp_rx_fifo     ;// 直连！


    // ==================== 第一段：状态转移 ====================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // ==================== 第二段：下一状态逻辑 ====================
    always @(*) begin
        case (current_state)
            S_IDLE: begin
                if (udp_frame_rx_done_valid && !rd_rst_busy_udp_rx_fifo && !wr_rst_busy_udp_tx_fifo)
                    next_state = S_READ_AND_WRITE;
                else
                    next_state = S_IDLE;
            end

            S_READ_AND_WRITE: begin
                if (byte_cnt == total_bytes_r)   // 全部字节已搬完
                    next_state = S_DONE;
                else
                    next_state = S_READ_AND_WRITE;
            end

            S_DONE: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ==================== 第三段：输出逻辑 ====================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_en_udp_rx_fifo   <= 1'b0;
            wr_en_udp_tx_fifo   <= 1'b0;
            total_bytes_r       <= 11'd0;
            byte_cnt            <= 11'd0;
        end else begin
            // 默认值（脉冲信号仅保持一个周期）
            rd_en_udp_rx_fifo <= 1'b0;
            wr_en_udp_tx_fifo <= 1'b0;

            case (current_state)
                S_IDLE: begin
                    // 条件满足时锁存有效载荷长度并初始化计数器
                    if (udp_frame_rx_done_valid && !rd_rst_busy_udp_rx_fifo && !wr_rst_busy_udp_tx_fifo) begin
                        total_bytes_r <= udp_rx_payload_count_gray_sync;
                        byte_cnt      <= 11'd0;
                    end
                end

                S_READ_AND_WRITE: begin
                    if (byte_cnt < total_bytes_r) begin
                        // FWFT: dout 已稳定，只要非空且目标 FIFO 未满就转发
                        if (!empty_udp_rx_fifo && !full_udp_tx_fifo) begin

                            wr_en_udp_tx_fifo <= 1'b1;               // 写使能
                            rd_en_udp_rx_fifo <= 1'b1;               // FWFT：加载下一个字节
                            byte_cnt          <= byte_cnt + 1'b1;
                        end
                    end
                end

                S_DONE: begin
                    // 已在默认值中清除 rd_en 和 wr_en
                end

                default: begin
                end
            endcase
        end
    end
endmodule