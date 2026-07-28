`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/26 20:02:36
// Design Name: 
// Module Name: gmii_to_rgmii
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 内部8位gmi逻辑转为rgmii
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module gmii_to_rgmii(

    // ==================== 全局信号 ====================
    input                               clk_125m                   ,// 主时钟 (125MHz, GMII时钟域)
    input                               rst_n                      ,// 异步低有效复位，同步化后使用
    
    // ==================== 内部gmii数据输入接口 ====================
    input                [   7: 0]      gmii_txd                   ,//gmii逻辑的8位并行
    input                               tx_en                      ,
    input                               tx_err                     ,

    // ==================== 传递给phy的rgmii信号 ====================
    output               [   3: 0]      rgmii_txd                  ,//125Mhz双边沿ODDR传输信号
    output                              rgmii_txen                 ,
    output                              rgmii_tx_clk                

);

//////////////////////////////////////////////////////////////////////////////////
/*
gmii转rgmii需要6个ODDR,

***4个用来将8位并行转为4位并行***
=====data[3]--->ODDR 0   D1
=====data[7]--->ODDR 0   D2

=====data[2]--->ODDR 1   D1
=====data[6]--->ODDR 1   D2

=====data[1]--->ODDR 2   D1
=====data[5]--->ODDR 2   D2

=====data[0]--->ODDR 3   D1
=====data[4]--->ODDR 3   D2

***1个用来输出125mhz时钟，保证时钟、数据、控制信号延迟一致***
======D1进0，D2进1

***1个用来输出控制信号***
======D1进tx_en，D2进tx_en^tx_err

注意ODDR为高电平复位，全部使用same_edge模式
*/



//=================================================
//处理数据
      ODDR #(
    .DDR_CLK_EDGE                       ("SAME_EDGE"               ),// "OPPOSITE_EDGE" or "SAME_EDGE" 
    .INIT                               (1'b0                      ),// Initial value of Q: 1'b0 or 1'b1
    .SRTYPE                             ("SYNC"                    ) // Set/Reset type: "SYNC" or "ASYNC" 
      ) ODDR_0 (
    .Q                                  (rgmii_txd[0]              ),// 1-bit DDR output
    .C                                  (clk_125m                  ),// 1-bit clock input
    .CE                                 (1'b1                      ),// 1-bit clock enable input
    .D1                                 (gmii_txd[0]               ),// 1-bit data input (positive edge)
    .D2                                 (gmii_txd[4]               ),// 1-bit data input (negative edge)
    .R                                  (~rst_n                    ),// 1-bit reset
    .S                                  (1'b0                      ) // 1-bit set
      );


      ODDR #(
    .DDR_CLK_EDGE  ("SAME_EDGE" ),    .INIT  (1'b0  ), .SRTYPE  ("SYNC"  ) ) ODDR_1 (
    .Q                                  (rgmii_txd[1]              ),
    .C                                  (clk_125m                  ),
    .CE                                 (1'b1                      ),
    .D1                                 (gmii_txd[1]               ),
    .D2                                 (gmii_txd[5]               ),
    .R                                  (~rst_n                    ),
    .S                                  (1'b0                      ) 
      );

      ODDR #(
    .DDR_CLK_EDGE  ("SAME_EDGE" ),    .INIT  (1'b0  ), .SRTYPE  ("SYNC"  ) ) ODDR_2 (
    .Q                                  (rgmii_txd[2]              ),
    .C                                  (clk_125m                  ),
    .CE                                 (1'b1                      ),
    .D1                                 (gmii_txd[2]               ),
    .D2                                 (gmii_txd[6]               ),
    .R                                  (~rst_n                    ),
    .S                                  (1'b0                      ) 
      );

      ODDR #(
    .DDR_CLK_EDGE  ("SAME_EDGE" ),    .INIT  (1'b0  ), .SRTYPE  ("SYNC"  ) ) ODDR_3 (
    .Q                                  (rgmii_txd[3]              ),
    .C                                  (clk_125m                  ),
    .CE                                 (1'b1                      ),
    .D1                                 (gmii_txd[3]               ),
    .D2                                 (gmii_txd[7]               ),
    .R                                  (~rst_n                    ),
    .S                                  (1'b0                      ) 
      );


//=================================================
//处理时钟

      ODDR #(
    .DDR_CLK_EDGE  ("SAME_EDGE" ),    .INIT  (1'b0  ), .SRTYPE  ("SYNC"  ) ) ODDR_4 (
    .Q                                  (rgmii_tx_clk              ),
    .C                                  (clk_125m                  ),
    .CE                                 (1'b1                      ),
//    .D1                                 (1'b0                      ),
//    .D2                                 (1'b1                      ),
    .D1                                 (1'b1                      ),
    .D2                                 (1'b0                      ),
    .R                                  (~rst_n                    ),
    .S                                  (1'b0                      ) 
      );

//=================================================
//处理使能

      ODDR #(
    .DDR_CLK_EDGE  ("SAME_EDGE" ),    .INIT  (1'b0  ), .SRTYPE  ("SYNC"  ) ) ODDR_5 (
    .Q                                  (rgmii_txen                ),
    .C                                  (clk_125m                  ),
    .CE                                 (1'b1                      ),
    .D1                                 (tx_en                     ),
    .D2                                 (tx_en^tx_err              ),
    .R                                  (~rst_n                    ),
    .S                                  (1'b0                      ) 
      );


endmodule
