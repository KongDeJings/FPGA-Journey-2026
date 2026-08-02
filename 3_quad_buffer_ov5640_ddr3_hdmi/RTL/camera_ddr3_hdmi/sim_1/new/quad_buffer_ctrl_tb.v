
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/26
// Design Name: 
// Module Name: quad_buffer_ctrl_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 四缓冲控制器仿真测试
//              模拟Cam(30fps)、P(慢处理)、HDMI(60fps)三种速率
//              所有激励信号均在clk同步下产生，避免竞态
// 
//////////////////////////////////////////////////////////////////////////////////

module quad_buffer_ctrl_tb;

    // ==================== 信号定义 ====================
    reg                         clk;
    reg                         reset;
    reg                         w_done;
    reg                         p_idle;
    reg                         p_done;
    reg                         r_done;

    wire        [   1: 0]       w_buf;
    wire        [   1: 0]       p_rd_buf;
    wire        [   1: 0]       p_wr_buf;
    wire        [   1: 0]       r_buf;

    wire                        w_switch_pulse;
    wire                        p_switch_pulse;
    wire                        r_switch_pulse;



    // ==================== 时钟生成 (100MHz) ====================
    initial clk = 0;
    always #5 clk = ~clk;

    // ==================== 复位与初始信号 ====================
    initial begin
        reset   = 1'b1;
        w_done  = 1'b0;
        p_idle  = 1'b1;
        p_done  = 1'b0;
        r_done  = 1'b0;
        #100;
        @(posedge clk);
        reset   = 1'b0;
    end
/*
    initial begin
        #400
            // 产生一个周期的写完成脉冲
            w_done <= 1'b1;
            @(posedge clk);
            #3 w_done <= 1'b0;    

        #600
            // 产生一个周期的写完成脉冲
            p_done <= 1'b1;
            @(posedge clk);
            #3 p_done <= 1'b0;    

        #2000
            // 产生一个周期的写完成脉冲
            r_done <= 1'b1;
            @(posedge clk);
            #3 r_done <= 1'b0;    



    #1000
    $stop;
    end
*/

    // ==================== Cam线程 (30fps模拟) ====================
    reg [15:0] cam_interval;   // 帧间隔计数器
    initial begin
        cam_interval = 0;
        w_done  = 1'b0;
        @(negedge reset);
        @(posedge clk);
        repeat(20) begin   // 模拟20帧
            // 产生一个周期的写完成脉冲
            w_done <= 1'b1;
            @(posedge clk);
            w_done <= 1'b0;
            // 帧间隔（30fps ≈ 33333333ns = 3333333 clocks，加速用50个clk）
            repeat(50) @(posedge clk);
        end
    end

    // ==================== HDMI线程 (60fps模拟) ====================
    initial begin
        r_done = 1'b0;
        @(negedge reset);
        @(posedge clk);
        repeat(40) begin   // 模拟40帧
            r_done <= 1'b1;
            @(posedge clk);
            r_done <= 1'b0;
            repeat(25) @(posedge clk); // 加速间隔
        end
    end

    // ==================== P线程 (处理慢) ====================
    reg [15:0] p_timer;   // 处理剩余周期
    reg        p_busy;
    initial begin
        p_idle  = 1'b1;
        p_done  = 1'b0;
        p_busy  = 1'b0;
        p_timer = 0;
        @(negedge reset);
        @(posedge clk);
        forever begin
            @(posedge clk);
            // 如果空闲且收到开始脉冲，启动处理
            if (p_idle && p_switch_pulse) begin
                p_idle <= 1'b0;
                p_busy <= 1'b1;
                p_timer <= 300;   // 处理延时300个clk（大于Cam帧间隔50）
            end
            // 处理过程中递减计数器
            if (p_busy) begin
                if (p_timer > 0) begin
                    p_timer <= p_timer - 1;
                end else begin
                    // 处理完成，产生p_done脉冲
                    p_done <= 1'b1;
                    p_busy <= 1'b0;
                    p_idle <= 1'b1;
                    // 下一个clk清除p_done (在另一个always里处理)
                end
            end else begin
                p_done <= 1'b0;   // 空闲时清除
            end
        end
    end

    // 清除p_done脉冲：只在p_done为1时，下一个clk将其清零
    reg p_done_d1;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            p_done_d1 <= 1'b0;
        end else begin
            p_done_d1 <= p_done;
            if (p_done_d1)
                p_done <= 1'b0;   // 脉冲持续一个clk后清除
        end
    end

    // ==================== 仿真超时 ====================
    initial begin
        #20000;
        $stop;
    end
    // ==================== DUT例化 ====================
    quad_buffer_ctrl quad_buffer_ctrl (
    .clk                                (clk                       ),
    .reset                              (reset                     ),
    .w_done                             (w_done                    ),
    .p_idle                             (p_idle                    ),
    .p_done                             (p_done                    ),
    .r_done                             (r_done                    ),
    .w_buf                              (w_buf                     ),
    .p_rd_buf                           (p_rd_buf                  ),
    .p_wr_buf                           (p_wr_buf                  ),
    .r_buf                              (r_buf                     ),
    .w_switch_pulse                     (w_switch_pulse            ),
    .p_switch_pulse                     (p_switch_pulse            ),
    .r_switch_pulse                     (r_switch_pulse            ) 
    );
endmodule
