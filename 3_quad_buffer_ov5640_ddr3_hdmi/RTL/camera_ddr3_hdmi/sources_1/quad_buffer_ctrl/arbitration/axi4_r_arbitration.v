`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongdeJing
// 
// Create Date: 2026/08/01 09:04:08
// Design Name: 
// Module Name: axi4_r_arbitration
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:Hdmi读取的优先级大于P
// 
//////////////////////////////////////////////////////////////////////////////////


module axi4_r_arbitration(
    // ==================== 全局信号 ====================
    input                               ui_clk                     ,
    input                               reset                      ,
    // ==================== P模块读 ====================    
    input                               p_r_req                    ,// 电平req，外部保持到start产生后下一拍
    input                               p_r_busy                   ,// 发送模块忙指示
    // ==================== HDMI模块读 ====================  
    input                               hdmi_r_req                 ,// 电平req，外部保持到start产生后下一拍
    input                               hdmi_r_busy                ,// 发送模块忙指示
    // ===================  最终仲裁逻辑信号输出 ====================   
    output reg                          p_r_start_pulse            ,
    output reg                          hdmi_r_start_pulse          

    );
//===============================================================================================================   
// 内部信号定义
wire                                arb_enable;      // 仲裁使能：所有读通道都不忙时才允许发起新事务
// 独热码仲裁结果：  
// 2'b00:idle         
// 2'b01:P 读       
// 2'b10:HDMI 读      
reg  [1:0]                          grant;
reg  [1:0]                          grant_dly;
reg  [1:0]                          current_grant;

//===================================================
assign arb_enable = ~(p_r_busy || hdmi_r_busy);

//===================================================
// 组合逻辑仲裁：按优先级顺序扫描req,   hdmi -> p
always @(*) begin
    grant = 2'b00;  // 默认无授权
    if (arb_enable) begin
        if (hdmi_r_req) begin
            grant = 2'b10;
        end
        else if (p_r_req) begin
            grant = 2'b01;
        end
    end
end

//===================================================
// 仲裁结果打一拍，用于生成单周期start脉冲
always @(posedge ui_clk or posedge reset) begin
    if (reset) begin
        grant_dly <= 2'b00;
    end
    else begin
        grant_dly <= grant;
    end
end

//===================================================
// 生成单周期start脉冲：上升沿检测逻辑
always @(posedge ui_clk or posedge reset) begin                                        
    if (reset) begin
        p_r_start_pulse    <= 1'b0;
        hdmi_r_start_pulse <= 1'b0;
    end                                                                          
    else begin
        p_r_start_pulse    <= grant[0] && ~grant_dly[0];
        hdmi_r_start_pulse <= grant[1] && ~grant_dly[1];
    end                                          
end       
//===================================================
// 调试信号：锁存当前授权通道，仿真时直接观察
always @(posedge ui_clk or posedge reset) begin
    if (reset) begin
        current_grant <= 2'b00;
    end else begin
        current_grant <= grant;
    end
end

endmodule

