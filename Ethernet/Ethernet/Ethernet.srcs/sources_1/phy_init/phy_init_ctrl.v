`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/07/13 15:12:55
// Design Name: 
// Module Name: phy_init_ctrl
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 产生系统级FIFO复位请求，由上层逻辑同步到各FIFO写时钟域
//输出PHY初始化完成标志，协调上层逻辑启动
//不允许出现魔数
//////////////////////////////////////////////////////////////////////////////////
module phy_init_ctrl
#(
    // ==================== 系统时钟参数 ====================
    parameter                           SYS_CLK_FREQ                = 50_000_000           ,// 系统时钟频率
    // ==================== PHY复位时序参数 ====================
    parameter                           PHY_RST_HOLD_MS             = 25                   ,// PHY硬复位保持时间     25ms
    parameter                           PHY_INIT_WAIT_MS            = 100                  // PHY复位释放后等待初始化完成时间，模拟校准+RXC锁定   100ms

)(
    // ==================== 系统接口 ====================
    input                               sys_clk                    ,// 系统时钟，50MHz
    input                               rst_n                      ,
    // ==================== PHY硬件接口 ====================
    output reg                          phy_rst_n                  ,//
    // ==================== 初始化状态输出 ====================
    output reg                          phy_init_done              ,// PHY初始化完成标志，高有效
    output reg                          fifo_rst_req                // FIFO复位请求，高有效,sys_clk时钟域

);
// ========================================
//本地参数定义

    localparam                          PHY_RST_HOLD_CNT            = SYS_CLK_FREQ * PHY_RST_HOLD_MS  / 1_000; // 硬复位计数
    localparam                          PHY_INIT_WAIT_CNT           = SYS_CLK_FREQ * PHY_INIT_WAIT_MS / 1_000; // 初始化等待计数
    localparam                          TOTAL_CNT                   = PHY_RST_HOLD_CNT + PHY_INIT_WAIT_CNT;        // 总计数
    localparam                          CNT_WIDTH                   = $clog2(TOTAL_CNT + 1);            
    reg                  [CNT_WIDTH-1: 0]init_cnt                   ;

// ========================================
//初始化逻辑 
always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        phy_rst_n     <= 1'b0;
        fifo_rst_req  <= 1'b1;
        phy_init_done <= 1'b0;
        init_cnt      <= {CNT_WIDTH{1'b0}};
    end
     else begin
        if (init_cnt < TOTAL_CNT) begin
            init_cnt <= init_cnt + 1'b1;
            
            
            if (init_cnt < PHY_RST_HOLD_CNT) begin   // 阶段1：PHY硬复位阶段（0 ~ PHY_RST_HOLD_CNT）
                phy_rst_n    <= 1'b0;                // 保持PHY复位
                fifo_rst_req <= 1'b1;                // 保持FIFO复位
            end
            
            else begin                               // 阶段2：PHY初始化等待阶段（PHY_RST_HOLD_CNT ~ TOTAL_CNT）
                phy_rst_n    <= 1'b1;                // 释放PHY复位，PHY开始内部初始化
                fifo_rst_req <= 1'b1;                // 继续维持FIFO复位，等PHY完全稳定
            end
            phy_init_done <= 1'b0;                   // 未完成初始化
        end
        
        else begin                                   // 计数器计满，初始化完成
            phy_rst_n     <= 1'b1;
            fifo_rst_req  <= 1'b0;                   // 释放FIFO复位
            phy_init_done <= 1'b1;                   // 标记初始化完成
            init_cnt      <= init_cnt;               // 防止重复初始化
        end
    end
end

endmodule

