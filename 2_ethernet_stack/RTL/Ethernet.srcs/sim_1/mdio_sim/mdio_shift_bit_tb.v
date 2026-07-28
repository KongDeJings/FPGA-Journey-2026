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
// File name:              mdio_shift_bit_tb.v
// Last modified Date:     2026/05/11 17:32:08
// Last Version:           V1.0
// Descriptions:           
//----------------------------------------------------------------------------------------
// Created by:             Please Write You Name 
// Created date:           2026/05/11 17:32:08
// Version:                V1.0
// Descriptions:           
//                         
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module    mdio_shift_bit_tb();
    reg                                        clk                        ;
    reg                                        rst_n                      ;
    reg                                        mdio_start                 ;
    reg                                        rnw                        ;
    reg                       [   4: 0]        phy_addr                   ;
    reg                       [   4: 0]        reg_addr                   ;
    reg                       [  15: 0]        wr_data                    ;
    reg                                        mdio_i                     ;


    wire                      [  15: 0]        rd_data                    ;
    wire                                       mdc                        ;
    wire                                       mdio_o                     ;
    wire                                       mdio_busy                  ;
    wire                                       mdio_done                  ;
    wire                                       mdio_ack                   ;
    wire                                       mdio_timeout               ;
    wire                                       mdio_t                     ;

     initial
        begin
            clk             =0;
            rst_n           =1;
//=================================================       
// 初始化预期的mac/ip/port值
            mdio_start=0;
            rnw       =1;
            phy_addr  =5'b00001;
            reg_addr  =5'b001_01;
            wr_data   =16'hf101;
            mdio_i    = 0;           
        end    

//=================================================       
// 产生时钟                                           
always #10 clk=~clk;

//开始测试系统模块
        initial 
        begin
            #20 rst_n=0;
            #505 rst_n=1; 
            mdio_start=1;
            @(posedge clk);#3;
                mdio_start=0;
                                                           
#59000;
$stop;
        end



mdio_shift_bit#(
   .MDC_CLOCK      (1250_000       ),
   .SYS_CLOCK      (50_000_000     )
)
 u_mdio_shift_bit(
// 系统接口
    .clk                                (clk                       ),
    .rst_n                              (rst_n                     ),
// 控制接口
    .mdio_start                         (mdio_start                ),// 启动信号，脉冲
    .mdio_busy                          (mdio_busy                 ),// 模块忙
    .mdio_done                          (mdio_done                 ),// 操作完成，脉冲
    .mdio_ack                           (mdio_ack                  ),// PHY应答成功
    .mdio_timeout                       (mdio_timeout              ),// 超时错误
// 操作参数
    .rnw                                (rnw                       ),// 1=读，0=写
    .phy_addr                           (phy_addr                  ),
    .reg_addr                           (reg_addr                  ),
    .wr_data                            (wr_data                   ),
    .rd_data                            (rd_data                   ),
// MDIO物理接口
    .mdc                                (mdc                       ),// MDC时钟输出
    .mdio_o                             (mdio_o                    ),// 数据输出
    .mdio_i                             (mdio_i                    ),// 数据输入
    .mdio_t                             (mdio_t                    )// 三态控制，0可输出，1为高阻，释放总线
);




endmodule                                                  
