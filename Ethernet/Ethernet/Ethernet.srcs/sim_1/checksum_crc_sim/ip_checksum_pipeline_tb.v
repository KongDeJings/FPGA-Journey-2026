`timescale 1ns / 1ps
//****************************************VSCODE PLUG-IN**********************************//
//----------------------------------------------------------------------------------------
// IDE :                   VSCODE plug-in 
// VSCODE plug-in version: Verilog-Hdl-Format-4.3.20260413
// VSCODE plug-in author : Jiang Percy
//----------------------------------------------------------------------------------------
//****************************************Copyright (c)***********************************//
// Copyright(C)            Please Write Company name
// All rights reserved     
// File name:              ip_checksum_pipeline_tb.v
// Last modified Date:     2026/05/27 12:07:14
// Last Version:           V1.0
// Descriptions:           
//----------------------------------------------------------------------------------------
// Created by:             Please Write You Name 
// Created date:           2026/05/27 12:07:14
// Version:                V1.0
// Descriptions:           
//                         
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module    ip_checksum_pipeline_tb();
    reg                                        clk                        ;
    reg                                        rst_n                      ;

    reg                                        calc_start                 ;
    wire                      [  15: 0]        checksum                   ;
    wire                                       checksum_valid             ;
    reg                  [  15: 0]      pkt_len                    ;


    initial
        begin                    
            rst_n = 0   ;     
          calc_start=0;  
          pkt_len=16'h003c;                              
                    clk = 0     ;  
            #2                                             
                    rst_n = 0   ;                          
                    clk = 0     ;                          
            #1000                                            
                    rst_n = 1   ;

        calc_start=1;  
        @(posedge clk)#3;
                 calc_start=0;        
        @(posedge checksum_valid) #3              pkt_len=16'h0046;        calc_start=1;
                 #900
        

        
                 $stop;                
        end                                                
                                                           
    parameter   CLK_FREQ = 100;//Mhz                       
    always # ( 1000/CLK_FREQ/2 ) clk = ~clk ;              
                                                           
                                                           
ip_checksum_pipeline u_ip_checksum_pipeline(
// ==================== 全局信号 ====================
    .clk                                (clk                       ),
    .rst_n                              (rst_n                     ),
// ==================== 并行输入接口 ====================
// 整个IP头
    .ip_hdr_0                           (8'h45                     ),// 字节0: 版本+IHL
    .ip_hdr_1                           (8'h00                     ),// 字节1: 服务类型
    .ip_hdr_2                           (pkt_len[15:8]             ),// 字节2: 总长度高8位
    .ip_hdr_3                           (pkt_len[7:0]              ),// 字节3: 总长度低8位
    .ip_hdr_4                           (8'h00                     ),// 字节4: 标识高8位
    .ip_hdr_5                           (8'h00                     ),// 字节5: 标识低8位
    .ip_hdr_6                           (8'h00                     ),// 字节6: 标志+片偏移高8位
    .ip_hdr_7                           (8'h00                     ),// 字节7: 标志+片偏移低8位
    .ip_hdr_8                           (8'h80                     ),// 字节8: TTL
    .ip_hdr_9                           (8'h11                     ),// 字节9: 协议
// 字节10-11: 校验和字段（计算时视为0，不输入）
    .ip_hdr_12                          (8'hc0                     ),// 字节12: 源IP[31:24]
    .ip_hdr_13                          (8'ha8                     ),// 字节13: 源IP[23:16]
    .ip_hdr_14                          (8'h01                     ),// 字节14: 源IP[15:8]
    .ip_hdr_15                          (8'h64                     ),// 字节15: 源IP[7:0]
    .ip_hdr_16                          (8'hde                     ),// 字节16: 目的IP[31:24]
    .ip_hdr_17                          (8'h49                     ),// 字节17: 目的IP[23:16]
    .ip_hdr_18                          (8'h1b                     ),// 字节18: 目的IP[15:8]
    .ip_hdr_19                          (8'h45                     ),// 字节19: 目的IP[7:0]
    .calc_start                         (calc_start                ),// 脉冲,启动计算
    .checksum                           (checksum                  ),// 校验和
    .checksum_valid                     (checksum_valid            ) // 校验和有效
);




endmodule                                                  