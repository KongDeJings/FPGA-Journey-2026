//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/05/26 20:02:36
// Design Name: 
// Module Name: rgmii_to_gmii
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: udp_rx_engine,PHY是rgmii，需要转为内部8位gmii逻辑
// 
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//////////////////////////////////////////////////////////////////////////////////

module rgmii_to_gmii(

    // ==================== 全局信号 ====================
    input                               rst_n                      ,// 异步低有效复位，同步化后使用
    
    // ==================== phy传递过来的rgmii信号 ====================
    input                               rgmii_rx_clk               ,
    input                [   3: 0]      rgmii_rxd                  ,
    input                               rgmii_rxdv                 ,

    // ==================== 内部gmii数据输入接口 ====================
    output                              gmii_rx_clk                ,
    output               [   7: 0]      gmii_rxd                   ,
    output                              gmii_rxdv                  ,
    output                              gmii_rxer                  

);
//////////////////////////////////////////////////////////////////////////////////
/*
rgmii转gmii需要5个IDDR,

***4个用来将4位并行转为8位并行***

***1个用来输出控制信号***

注意IDDR为高电平复位，全部使用SAME_EDGE_PIPELINED模式
*/

//=================================================
//处理数据
  assign gmii_rx_clk = rgmii_rx_clk;
  genvar i;
  generate
    for(i=0;i<4;i=i+1)
    begin: rgmii_rxd_i
      IDDR #(
    .DDR_CLK_EDGE                       ("SAME_EDGE_PIPELINED"     ),// "OPPOSITE_EDGE", "SAME_EDGE" 
                                                                        // or "SAME_EDGE_PIPELINED" 

    .INIT_Q1                            (1'b0                      ),// Initial value of Q1: 1'b0 or 1'b1
    .INIT_Q2                            (1'b0                      ),// Initial value of Q2: 1'b0 or 1'b1
    .SRTYPE                             ("SYNC"                    ) // Set/Reset type: "SYNC" or "ASYNC" 
      ) IDDR_rxd (
    .Q1                                 (gmii_rxd[i]               ),// 1-bit output for positive edge of clock
    .Q2                                 (gmii_rxd[i+4]             ),// 1-bit output for negative edge of clock
    .C                                  (rgmii_rx_clk              ),// 1-bit clock input
    .CE                                 (1'b1                      ),// 1-breset_nit clock enable input
    .D                                  (rgmii_rxd[i]              ),// 1-bit DDR data input
    .R                                  (~rst_n                    ),// 1-bit reset
    .S                                  (1'b0                      ) // 1-bit set
      );
    end
  endgenerate


//=================================================
//处理使能
    wire                                gmii_rxer_r                ;

  IDDR #(
    .DDR_CLK_EDGE                       ("SAME_EDGE_PIPELINED"     ),
    .INIT_Q1                            (1'b0   ),    .INIT_Q2     (1'b0   ),    .SRTYPE      ("SYNC" )) IDDR_rx_dv(
    .Q1                                 (gmii_rxdv                 ),
    .Q2                                 (gmii_rxer_r               ),
    .C                                  (rgmii_rx_clk              ),
    .CE                                 (1'b1                      ),
    .D                                  (rgmii_rxdv                ),
    .R                                  (~rst_n                    ),
    .S                                  (1'b0                      ) 
  );

    assign gmii_rxer = gmii_rxer_r^gmii_rxdv;//生成错误信号
endmodule