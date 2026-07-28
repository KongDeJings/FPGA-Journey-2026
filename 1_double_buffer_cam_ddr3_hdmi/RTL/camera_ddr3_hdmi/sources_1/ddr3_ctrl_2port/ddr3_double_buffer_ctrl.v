`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/05/21 17:03:24
// Design Name: 
// Module Name: ddr3_double_buffer_ctrl
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 乒乓操作控制模块，对外输出缓冲区切换信号，以及buf指针
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 代码中禁止出现魔数！！
//////////////////////////////////////////////////////////////////////////////////
module ddr3_double_buffer_ctrl

(
    // ==================== 全局信号 ====================
    input                               ui_clk                     ,// ui_clk时钟域时钟
    input                               reset                      ,


    // ==================== 读完、写完信号输入  ====================
    input                               w_done                     ,// Camera 写完
    input                               r_done                     ,// HDMI  读完
    
    // ==================== 帧切换信号输出  ====================
    output reg                          w_buf                      ,// 0=写帧A, 1=写帧B(camera侧)均为hdmi时钟域,默认写A
    output reg                          w_addr_switch_pulse        ,//地址切换脉冲，与指针一同出现
    output reg                          r_buf                      ,// 0=读帧A, 1=读帧B（hdmi侧）均为hdmi时钟域，默认读B
    output reg                          r_addr_switch_pulse         //地址切换脉冲，与指针一同出现

);
//===============================================================================================================   
//本地参数及接口定义、连线
    reg                                 last_completed_buf         ;// 最近写完的缓冲区（0: A, 1: B）
    reg                                 frame_ready                ;// 有新的完整帧可用（即last_completed_buf更新过）

/*
ILA your_instance_name (
	.clk(ui_clk), // input wire clk


    .probe0                             (w_buf                   ),// input wire [0:0]  probe0  
    .probe1                             (w_addr_switch_pulse     ),// input wire [0:0]  probe1 
    .probe2                             (r_buf                   ),// input wire [0:0]  probe2 
    .probe3                             (r_addr_switch_pulse     ),// input wire [0:0]  probe3 
    .probe4                             ( last_completed_buf        ),// input wire [0:0]  probe4 
    .probe5                             ( frame_ready               ) // input wire [0:0]  probe5
);
*/
//===============================================================================================================   
//内部逻辑
//=================================================
always @(posedge ui_clk or posedge reset) begin
    if (reset) begin
        last_completed_buf <= 0;
        frame_ready <= 0;
    end else if (w_done) begin
        last_completed_buf <= w_buf;   // 注意：w_buf 此时还是写之前的值（刚写完的那个）
        frame_ready <= 1;
    end else if (r_done && frame_ready) begin
        frame_ready <= 0;   // 读侧已消费完新帧，清除标志
    end
end

// 写侧逻辑不变（w_done时立即切换w_buf）
always @(posedge ui_clk or posedge reset) begin
    if (reset) begin
        w_buf <= 0;
        w_addr_switch_pulse <= 0;
    end else begin
        w_addr_switch_pulse <= 0;
        if (w_done) begin
            w_buf <= ~w_buf;
            w_addr_switch_pulse <= 1;
        end
    end
end

// 读侧：仅当有新完整帧且当前r_done时，切换到last_completed_buf
always @(posedge ui_clk or posedge reset) begin
    if (reset) begin
        r_buf <= 1;   // 初始读BUF_B（与写错开）
        r_addr_switch_pulse <= 0;
    end else begin
        r_addr_switch_pulse <= 0;
        if (r_done && frame_ready) begin
            r_buf <= last_completed_buf;   // 切换到最近写完的缓冲区
            r_addr_switch_pulse <= 1;
        end
    end
end

endmodule
/*
//=================================================
//跑仿真时的模拟测试逻辑
parameter BUF_A_BEGIN = 32'h0100_0000;//缓存A基地址
parameter BUF_B_BEGIN = 32'h0120_0000;//缓存B基地址

reg [31:0]w_addr;
reg [31:0]r_addr;
//模拟写入BUF切换
    always @(posedge ui_clk or posedge reset) begin  
        if(reset)
            w_addr<=0;
        else if(w_addr_switch_pulse)begin
            case (w_buf)
                1: w_addr<=BUF_B_BEGIN;
                0: w_addr<=BUF_A_BEGIN;
            endcase
        end
    end


//模拟读出BUF切换
    always @(posedge ui_clk or posedge reset) begin  
        if(reset)
            r_addr<=0;
        else if(r_addr_switch_pulse)begin
            case (r_buf)
                1: r_addr<=BUF_B_BEGIN;
                0: r_addr<=BUF_A_BEGIN;
            endcase
        end
    end
*/

//////////////////////////////////////////    调试过程中弃用的方案       //////////////////////////////////////////////
/*
//==================================================================================================
//通过翻转buf指针来切换buf
//弃用原因：无法解决双帧缓存问题

reg cam_frame_ready;

//=================================================
//写侧逻辑，w_done一出现立即切换缓存
    always @(posedge ui_clk or posedge reset) begin  
            if(reset)begin
            w_addr_switch_pulse<=0;
            w_buf<=0;
            end
            else if(w_done)begin
                w_addr_switch_pulse<=1;
                w_buf<=~w_buf;
            end
            else begin
                w_addr_switch_pulse<=0;   //脉冲信号，只保持一个周期
                w_buf<=w_buf;                
            end      
        end


    always @(posedge ui_clk or posedge reset)  begin
            if(reset)                               
                cam_frame_ready<=0;
            else if(cam_frame_ready&&r_done)
                cam_frame_ready<=0;
            else if(w_done) //满足条件则断言cam_frame_ready为1,等读完信号来时拉低
                cam_frame_ready<=1;
            else
                cam_frame_ready<=cam_frame_ready;
    end

    always @(posedge ui_clk or posedge reset) begin  
            if(reset)begin
            r_addr_switch_pulse<=0;
            r_buf<=1;
            end
            else if(cam_frame_ready&&r_done)begin    //当写完成后自动拉低
                r_addr_switch_pulse<=1;
                r_buf<=~r_buf;
            end
            else begin
                r_addr_switch_pulse<=0;   //脉冲信号，只保持一个周期
                r_buf<=r_buf;                
            end      
        end

*/