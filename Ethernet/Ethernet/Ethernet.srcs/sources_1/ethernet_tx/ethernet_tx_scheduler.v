`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/07/09 11:15:51
// Design Name: 
// Module Name: ethernet_tx_scheduler
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 = File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ethernet_tx_scheduler(
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,
    input                               rst_n                      ,

    // ==================== arp发送所需信号 ====================    
    input                               arp_tx_reply_req           ,// 电平req，外部保持到start产生后下一拍
    input                               arp_tx_request_req         ,// 电平req，外部保持到start产生后下一拍
    input                               arp_tx_busy                ,// 发送模块忙指示
    input                               arp_tx_done                ,// 未使用，保留端口兼容
    // ==================== icmp发送所需信号 ====================  
    input                               icmp_tx_reply_req          ,// 电平req，外部保持到start产生后下一拍
    input                               icmp_tx_busy               ,// 发送模块忙指示
    input                               icmp_tx_done               ,// 未使用，保留端口兼容
    // ===================  UDP发送所需信号 ====================   
    input                               udp_tx_req                 ,// 电平req，外部保持到start产生后下一拍
    input                               udp_tx_busy                ,// 发送模块忙指示
    input                               udp_tx_done                ,// 未使用，保留端口兼容
    // ===================  最终仲裁逻辑信号输出 ====================   
    output reg                          arp_request_start_pulse    ,
    output reg                          arp_reply_start_pulse      ,
    output reg                          icmp_start_pulse_primitive ,
    output reg                          udp_start_pulse_primitive  

             
    );
//===============================================================================================================   
// 内部信号定义
wire                                arb_enable;// 仲裁使能：所有发送通道都不忙时才允许发起新包
// 独热码仲裁结果：   // 4'b0000:idle         
// bit0=ARP Reply   // 4'b0001:ARP Reply       
// bit1=ARP Request // 4'b0010:ARP Request       
// bit2=ICMP        // 4'b0100:ICMP      
// bit3=UDP         // 4'b1000:UDP     
reg  [3:0]                          grant;
reg  [3:0]                          grant_dly;
 reg           [   3: 0]      current_grant  ;

//===================================================
assign arb_enable = ~(arp_tx_busy || icmp_tx_busy || udp_tx_busy);

//===================================================
// 组合逻辑仲裁：按优先级顺序扫描req,   arp_reply-》arp_request -》icmp-》udp
always @(*) begin
    grant = 4'b0000;  // 默认无授权
    if (arb_enable) begin
        if (arp_tx_reply_req) begin
            grant = 4'b0001;
        end
        else if (arp_tx_request_req) begin
            grant = 4'b0010;
        end
        else if (icmp_tx_reply_req) begin
            grant = 4'b0100;
        end
        else if (udp_tx_req) begin
            grant = 4'b1000;
        end
    end
end

//===================================================
// 仲裁结果打一拍，用于生成单周期start脉冲
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        grant_dly <= 0;
    end else begin
        grant_dly <= grant;
    end
end

//===================================================
// 生成单周期start脉冲：上升沿检测逻辑
    always @(posedge clk_125m or negedge rst_n)           
        begin                                        
            if(!rst_n) begin
                arp_reply_start_pulse      <= 0;
                arp_request_start_pulse    <= 0;
                icmp_start_pulse_primitive <= 0;
                udp_start_pulse_primitive  <= 0;
            end                                                                          
            else begin
                arp_reply_start_pulse      <= grant[0] && ~grant_dly[0];
                arp_request_start_pulse    <= grant[1] && ~grant_dly[1];
                icmp_start_pulse_primitive <= grant[2] && ~grant_dly[2];
                udp_start_pulse_primitive  <= grant[3] && ~grant_dly[3];
            end                                          
        end       
//===================================================
// 调试信号：锁存当前授权通道，仿真时直接观察
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        current_grant <= 4'b0000;
    end else begin
        current_grant <= grant;
    end
end

endmodule

