`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/06/04 08:42:53
// Design Name: 
// Module Name: icmp_checksum
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// 
//////////////////////////////////////////////////////////////////////////////////
module icmp_checksum (
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,
    input                               rst_n                      ,

    // ==================== 输入接口 ====================
    input                [   7: 0]      data_in                    ,
    input                               data_valid                 ,

    // ==================== 控制接口 ====================
    input                               calc_start                 ,// 开始计算,比送入的数据早一拍！
    input                               last_byte                  ,// 当前是否是最后一个字节

    // ==================== 输出接口 ====================
    output reg           [  15: 0]      checksum                   ,
    output reg                          checksum_valid              
);

// ==================== 状态定义 ====================
localparam  IDLE = 4'b0000,
            RECV = 4'b0010,
            FOLD = 4'b0100,
            DONE = 4'b1000;

    reg                  [   3: 0]      current_state,           next_state;

    reg                  [  31: 0]      accumulator                ;// 32bit 累加器
    reg                  [   7: 0]      high_byte_reg              ;// 暂存高8位
    reg                                 is_high_byte               ;// 1=下一个为高字节
    reg                                 odd_length                 ;// 是否为奇数长度

// ==================== 第一段：状态转移 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

// ==================== 第二段：下一状态逻辑 ====================
always @(*) begin
    case (current_state)
        IDLE: begin
            if (calc_start)
                next_state = RECV;
            else
                next_state = IDLE;
        end

        RECV: begin
            if (last_byte)
                next_state = FOLD;
            else
                next_state = RECV;
        end

        FOLD: begin
            if (accumulator[31:16] == 0)
                next_state = DONE;
            else
                next_state = FOLD;
        end

        DONE: begin
            next_state = IDLE;
        end

        default: next_state = IDLE;
    endcase
end

// ==================== 第三段：输出逻辑 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        accumulator     <= 32'h0;
        high_byte_reg   <= 8'h0;
        is_high_byte    <= 1'b1;
        odd_length      <= 1'b0;
        checksum        <= 16'h0;
        checksum_valid  <= 1'b0;
    end else begin
        checksum_valid <= 1'b0;

        case (current_state)
            IDLE: begin
                if (calc_start) begin
                    accumulator   <= 32'h0;
                    is_high_byte  <= 1'b1;
                    odd_length    <= 1'b0;
                end
            end

            RECV: begin
                if (data_valid) begin
                    if (is_high_byte) begin
                        high_byte_reg <= data_in;
                        is_high_byte  <= 1'b0;
                    end else begin
                        accumulator   <= accumulator + {high_byte_reg, data_in};
                        is_high_byte  <= 1'b1;
                    end

                    // 记录是否为奇数长度
                    if (last_byte && is_high_byte) begin
                        odd_length <= 1'b1;
                    end
                end
            end

            FOLD: begin
                // 奇数长度补 0（仅参与计算，不发送）
                if (odd_length) begin
                    accumulator <= accumulator + {high_byte_reg, 8'h00};
                end else begin
                    accumulator <= {16'h0, accumulator[31:16]} + accumulator[15:0];
                end
            end

            DONE: begin
                checksum       <= ~accumulator[15:0];
                checksum_valid <= 1'b1;
            end
        endcase
    end
end

endmodule
