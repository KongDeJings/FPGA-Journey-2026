`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/27
// Design Name: 
// Module Name: tb_p_module_ctrl_test
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 测试 p_module_ctrl_test 最小模块（FIFO->算法链->FIFO）
//              图像尺寸 32x24，纯红测试，加速仿真
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_p_module_ctrl_test;

    // 时钟与复位
    reg clk;
    reg reset;

    // 写入 FIFO 激励
    reg  [127:0] din_proc_r_fifo;
    reg          wr_en_proc_r_fifo;
    wire         full_proc_r_fifo;
    wire [7:0]   wr_data_count_proc_r_fifo;

    // 帧启动脉冲
    reg          p_switch_pulse;

    // 内部观测信号（通过 DUT 内部层次引用，如需可加）
    // 实际 DUT 端口只有上面那些，其他内部信号可通过波形查看

    // 时钟生成
    initial clk = 0;
    always #5 clk = ~clk;  // 100MHz

    // DUT 例化，参数覆写为小图像
    p_module_ctrl_test #(
        .IMAGE_WIDTH (32),
        .IMAGE_HEIGHT(24),
        .LINE_LEN    (32)
    ) uut (
    .clk                                (clk                       ),
    .reset                              (reset                     ),
    .din_proc_r_fifo                    (din_proc_r_fifo           ),
    .wr_en_proc_r_fifo                  (wr_en_proc_r_fifo         ),
    .full_proc_r_fifo                   (full_proc_r_fifo          ),
    .wr_data_count_proc_r_fifo          (wr_data_count_proc_r_fifo ),
    .p_switch_pulse                     (p_switch_pulse            ) 
    );

    // 测试激励
    reg [15:0] test_pixel;

    initial begin
        // 初始化
        reset             = 1'b1;
        wr_en_proc_r_fifo = 1'b0;
        din_proc_r_fifo   = 128'd0;
        p_switch_pulse    = 1'b0;
        test_pixel        = 16'hF800;  // 纯红 RGB565

        // 复位释放
        #100;
        @(posedge clk);
        reset = 1'b0;

        // 写满一帧数据（32x24）
        // 每行 32 像素 * 16bit = 512bit，需 4 个 128bit 块
        // 一帧共 24 * 4 = 96 块
        repeat(24) begin  // 24行
            repeat(4) begin  // 每行4块
                @(posedge clk);
                // 背压等待
                while (full_proc_r_fifo) @(posedge clk);
                // 一个128bit块包8个像素
                din_proc_r_fifo <= {
                    test_pixel, test_pixel, test_pixel, test_pixel,
                    test_pixel, test_pixel, test_pixel, test_pixel
                };
                wr_en_proc_r_fifo <= 1'b1;
                @(posedge clk);
                wr_en_proc_r_fifo <= 1'b0;
            end
        end

        // 发出帧启动脉冲（与四缓冲控制器的 p_switch_pulse 一致）
        @(posedge clk);
        p_switch_pulse <= 1'b1;
        @(posedge clk);
        p_switch_pulse <= 1'b0;

        // 等待流水线处理完毕（观察 p_r_done 和 p_w_done）
        // 它们可以从 DUT 内部层级查看，例如：
        // uut.u_pixel_count_request_ctrl.p_r_done
        // uut.u_pixel_count_write_ctrl.p_w_done
        // 这里只是给足够的时间让仿真跑完
        repeat(2000) @(posedge clk);

        $stop;
    end

endmodule