`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/06/26
// Design Name: 
// Module Name: quad_buffer_ctrl
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 四缓冲分两组管理，in_buf[1:0]为Cam写P读，proc_buf[1:0]为P写HDMI读
//              覆盖策略：生产者无空闲时覆盖就绪buffer，锁定buffer不可被覆盖
//              P开始处理时同时锁定读buffer和写buffer，当p模块整体完成时才释放（读、处理、写全部完成）
//                **输出指针和脉冲均打一拍对齐下游时序**
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 代码中禁止出现魔数！
//////////////////////////////////////////////////////////////////////////////////


module quad_buffer_ctrl
(
    // ==================== 全局信号 ====================
    input                               clk                        ,// ui_clk
    input                               reset                      ,// ui_clk_sync_rst

    // ==================== 完成信号输入 ====================
    input                               w_done                     ,// 摄像头写完一帧
    input                               p_idle                     ,// P空闲，可接收新任务
    input                               p_done                     ,// Sobel处理完一帧
    input                               r_done                     ,// HDMI读完一帧

    // ==================== 指针输出 ====================
    output                              w_buf                      ,// 当前写哪个in_buf(0~1)
    output                              p_rd_buf                   ,// 当前从哪个in_buf读
    output                              p_wr_buf                   ,// 当前往哪个proc_buf写
    output                              r_buf                      ,// 当前从哪个proc_buf读

    // ==================== 切换脉冲输出 ====================
    output                              w_switch_pulse             ,// 与w_buf同拍变化，持续1个clk
    output                              p_switch_pulse             ,// 与p_rd/p_wr同拍变化
    output                              r_switch_pulse              // 与r_buf同拍变化
);

//===============================================================================================================   
// 本地参数及状态定义
    localparam  STAT_IDLE   =   2'd0    ; // 空闲，生产者可写
    localparam  STAT_FULL   =   2'd1    ; // 就绪，等待消费者取走
    localparam  STAT_LOCK   =   2'd2    ; // 锁定，消费者正在使用

//===================================
// 内部状态寄存器
    reg     [   1: 0]       in_buf_state_0;
    reg     [   1: 0]       in_buf_state_1;
    reg     [   1: 0]       proc_buf_state_0;
    reg     [   1: 0]       proc_buf_state_1;

    reg                     latest_full_in_buf;//最新就绪的in_buf
    reg                     latest_full_proc_buf;//最新就绪的proc_buf

    reg     [   1: 0]       w_buf_int;     //定义初始时各个master占用哪个buf  
    reg     [   1: 0]       p_rd_buf_int;  //定义初始时各个master占用哪个buf
    reg     [   1: 0]       p_wr_buf_int;  //定义初始时各个master占用哪个buf
    reg     [   1: 0]       r_buf_int;     //定义初始时各个master占用哪个buf

    reg                     w_switch_int;
    reg                     p_switch_int;
    reg                     r_switch_int;

//====================================
// 状态标志
    wire                    any_in_buf_full;         
    wire                    any_proc_buf_full;
    wire                    any_proc_buf_idle;

    assign any_in_buf_full      =   (in_buf_state_0 == STAT_FULL) || (in_buf_state_1 == STAT_FULL);
    assign any_proc_buf_full    =   (proc_buf_state_0 == STAT_FULL) || (proc_buf_state_1 == STAT_FULL);
    assign any_proc_buf_idle    =   (proc_buf_state_0 == STAT_IDLE) || (proc_buf_state_1 == STAT_IDLE);

//===============================================================================================================   
// 主状态机
always @(posedge clk or posedge reset) begin
    if (reset) begin
        in_buf_state_0      <= STAT_IDLE;
        in_buf_state_1      <= STAT_IDLE;
        proc_buf_state_0    <= STAT_IDLE;
        proc_buf_state_1    <= STAT_IDLE;

        w_buf_int           <= 2'd0;
        p_rd_buf_int        <= 2'd1;
        p_wr_buf_int        <= 2'd0;
        r_buf_int           <= 2'd1;

        latest_full_in_buf   <= 1'b0;
        latest_full_proc_buf <= 1'b0;

        w_switch_int <= 1'b0;
        p_switch_int <= 1'b0;
        r_switch_int <= 1'b0;
    end else begin
        // 默认脉冲清零,保证为1个周期
        w_switch_int <= 1'b0;
        p_switch_int <= 1'b0;
        r_switch_int <= 1'b0;

        // Cam写完成
        if (w_done) begin
            // 刚写完的buffer标记为FULL
            case (w_buf_int)
                2'd0: in_buf_state_0 <= STAT_FULL;
                2'd1: in_buf_state_1 <= STAT_FULL;
            endcase
            latest_full_in_buf <= w_buf_int[0];

            // 直接计算下一个写buffer（不依赖组合next_w_buf，避免滞后）
            // 规则：尝试切换到另一个in_buf，只要它没被LOCK就行。
            // 如果另一个是FULL则同时覆盖（改为IDLE），如果LOCK则保持当前（异常，但留作保护）
            if (w_buf_int == 2'd0) begin
                if (in_buf_state_1 != STAT_LOCK) begin
                    w_buf_int <= 2'd1;
                    if (in_buf_state_1 == STAT_FULL)
                        in_buf_state_1 <= STAT_IDLE;   // 覆盖旧帧
                end else begin
                    w_buf_int <= 2'd0;   // 另一个被锁，只能覆盖当前刚写完的（丢弃）
                    // 当前刚变成FULL，直接改回IDLE表示丢弃
                    in_buf_state_0 <= STAT_IDLE;
                end
            end else begin // w_buf_int == 1
                if (in_buf_state_0 != STAT_LOCK) begin
                    w_buf_int <= 2'd0;
                    if (in_buf_state_0 == STAT_FULL)
                        in_buf_state_0 <= STAT_IDLE;
                end else begin
                    w_buf_int <= 2'd1;
                    in_buf_state_1 <= STAT_IDLE;
                end
            end

            w_switch_int <= 1'b1;
        end

        //2. P处理完成
        if (p_done) begin
            // 释放读buffer
            case (p_rd_buf_int)
                2'd0: in_buf_state_0 <= STAT_IDLE;
                2'd1: in_buf_state_1 <= STAT_IDLE;
            endcase

            // 写buffer变为FULL
            case (p_wr_buf_int)
                2'd0: proc_buf_state_0 <= STAT_FULL;
                2'd1: proc_buf_state_1 <= STAT_FULL;
            endcase
            latest_full_proc_buf <= p_wr_buf_int[0];
        end

        //3. P开始新帧
        if (p_idle && any_in_buf_full && (any_proc_buf_idle || any_proc_buf_full)) begin
            // 读buffer分配
            p_rd_buf_int <= {1'b0, latest_full_in_buf};
            case (latest_full_in_buf)
                1'b0: in_buf_state_0 <= STAT_LOCK;
                1'b1: in_buf_state_1 <= STAT_LOCK;
            endcase

            // 写buffer分配：直接优先级选择，不依赖组合next
            if (proc_buf_state_0 == STAT_IDLE) begin
                p_wr_buf_int <= 2'd0;
                proc_buf_state_0 <= STAT_LOCK;
            end else if (proc_buf_state_1 == STAT_IDLE) begin
                p_wr_buf_int <= 2'd1;
                proc_buf_state_1 <= STAT_LOCK;
            end else if (proc_buf_state_0 == STAT_FULL) begin
                p_wr_buf_int <= 2'd0;          // 覆盖0
                proc_buf_state_0 <= STAT_LOCK;
            end else begin
                p_wr_buf_int <= 2'd1;          // 覆盖1
                proc_buf_state_1 <= STAT_LOCK;
            end

            p_switch_int <= 1'b1;
        end

        //4. HDMI读完成
        if (r_done) begin
            if (any_proc_buf_full) begin
                // 释放旧buffer
                case (r_buf_int)
                    2'd0: proc_buf_state_0 <= STAT_IDLE;
                    2'd1: proc_buf_state_1 <= STAT_IDLE;
                endcase

                // 锁定新buffer
                r_buf_int <= {1'b0, latest_full_proc_buf};
                case (latest_full_proc_buf)
                    1'b0: proc_buf_state_0 <= STAT_LOCK;
                    1'b1: proc_buf_state_1 <= STAT_LOCK;
                endcase

                r_switch_int <= 1'b1;
            end
            // 无就绪则保持r_buf不变
        end
    end
end

//===============================================================================================================   
// 输出打拍一级，保证下游拿到的指针和脉冲完全对齐
reg  [1:0] w_buf_out, p_rd_buf_out, p_wr_buf_out, r_buf_out;
reg        w_switch_out, p_switch_out, r_switch_out;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        w_buf_out   <= 2'd0;
        p_rd_buf_out<= 2'd1;
        p_wr_buf_out<= 2'd0;
        r_buf_out   <= 2'd1;
        w_switch_out<= 1'b0;
        p_switch_out<= 1'b0;
        r_switch_out<= 1'b0;
    end else begin
        w_buf_out    <= w_buf_int;
        p_rd_buf_out <= p_rd_buf_int;
        p_wr_buf_out <= p_wr_buf_int;
        r_buf_out    <= r_buf_int;
        w_switch_out <= w_switch_int;
        p_switch_out <= p_switch_int;
        r_switch_out <= r_switch_int;
    end
end

assign w_buf          = w_buf_out[0];
assign p_rd_buf       = p_rd_buf_out[0];
assign p_wr_buf       = p_wr_buf_out[0];
assign r_buf          = r_buf_out[0];
assign w_switch_pulse = w_switch_out;
assign p_switch_pulse = p_switch_out;
assign r_switch_pulse = r_switch_out;

endmodule


