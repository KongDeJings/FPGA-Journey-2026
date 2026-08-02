`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/22 20:19:14
// Design Name: 
// Module Name: r_module_ctrl
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
// 
//////////////////////////////////////////////////////////////////////////////////


module r_module_ctrl
#(
    // ==================== FIFO相关参数 ====================
    parameter                           FIFO_USER_DATA_WIDTH         = 16                   ,  //fifo din/dout的位宽，异步FIFO内部完成 16bit → 128bit 位宽拼接，转到AXI4时为128bit
    parameter                           R_HDMI_FIFO_RD_DATA_CNT_WIDTH= 10                   ,
    parameter                           R_HDMI_FIFO_WR_DATA_CNT_WIDTH= 7                    ,
    // ==================== 地址与数据参数 ====================
    parameter                           PROC_BUF_0                  = 32'h0100_0000        ,//缓存A基地址
    parameter                           PROC_BUF_1                  = 32'h0180_0000        ,//缓存B基地址
    parameter                           AXI_DATA_WIDTH              = 128                  ,
    parameter                           AXI_ADDR_WIDTH              = 32                   ,
    parameter                           AXI_BURST_LEN               = 31                   ,

    parameter                           AXI_ID_WIDTH                = 4                    ,
    parameter                           HDMI_AXI_ID                 = 4'b0100              ,
    // ==================== AXI 固定协议参数 ====================
    parameter                           AXI_ARBURST_INCR            = 2'b01                ,
    parameter                           AXI_ARLOCK_NORMAL           = 1'b0                 ,
    parameter                           AXI_ARCACHE_DEVICE_NON_BUF  = 4'b0000              ,
    parameter                           AXI_ARPROT_UNPRIV_SECURE    = 3'b000               ,
    parameter                           AXI_ARQOS_DEFAULT           = 4'b0000              ,
    parameter                           AXI_ARREGION_DEFAULT        = 4'b0000              ,
    parameter                           AXI_RRESP_OKAY              = 2'b00                ,
    parameter                           AXI_RESET_POLARITY          = 1'b1                 ,

    // ==================== 有关输出的图像信息 ====================
    parameter                           IMAGE_WIDTH                 = 1280                 ,//图片宽度
    parameter                           IMAGE_HEIGHT                = 720                  

)
(
    // ==================== 全局信号 ====================
    input                               clk                        ,
    input                               reset                      ,

    // ==================== 读FIFO用户读取侧接口 ==========
    input                               rst_hdmi_r_fifo            ,
    input                               rdfifo_clk                 ,
    input                               rd_en_hdmi_r_fifo          ,
    output   [FIFO_USER_DATA_WIDTH-1: 0]dout_hdmi_r_fifo           ,
    output                              empty_hdmi_r_fifo          ,
    output  [R_HDMI_FIFO_RD_DATA_CNT_WIDTH-1: 0]rd_data_count_hdmi_r_fifo  ,
    output                              rd_rst_busy_hdmi_r_fifo    ,

    // ==================== 读地址通道 ====================  
    output               [AXI_ID_WIDTH-1: 0]m_axi_hdmi_arid        ,
    output               [AXI_ADDR_WIDTH-1: 0]m_axi_hdmi_araddr    ,
    output               [   7: 0]      m_axi_hdmi_arlen           ,
    output               [   2: 0]      m_axi_hdmi_arsize          ,
    output               [   1: 0]      m_axi_hdmi_arburst         ,
    output               [   0: 0]      m_axi_hdmi_arlock          ,
    output               [   3: 0]      m_axi_hdmi_arcache         ,
    output               [   2: 0]      m_axi_hdmi_arprot          ,
    output               [   3: 0]      m_axi_hdmi_arqos           ,
    output               [   3: 0]      m_axi_hdmi_arregion        ,
    output                              m_axi_hdmi_arvalid         ,
    input                               m_axi_hdmi_arready         ,

    // ==================== 读数据通道 ==================== 
    input                [AXI_ID_WIDTH-1: 0]m_axi_hdmi_rid             ,
    input                [AXI_DATA_WIDTH-1: 0]m_axi_hdmi_rdata           ,
    input                [   1: 0]      m_axi_hdmi_rresp           ,
    input                               m_axi_hdmi_rlast           ,
    input                               m_axi_hdmi_rvalid          ,
    output                              m_axi_hdmi_rready          ,
    //==================== 实验接口 ====================
    output                              r_done                     ,
    input                               hdmi_rd_enable             ,
    output                              r_module_ddr3_r_req        ,
    input                               hdmi_r_start_pulse         ,
    output                              hdmi_burst_done            ,
    // ==================== 缓存切换逻辑信号 ====================
    input                               r_buf                      ,// 0=读帧A, 1=读帧B,默认读B
    input                               r_addr_switch_pulse         //地址切换脉冲，与指针一同出现              
    );


//===============================================================================================================   
//本地参数及接口定义、连线
//hdmi fifo侧写入接口

    wire                                wr_en_hdmi_r_fifo          ;
    wire                 [AXI_DATA_WIDTH-1: 0]din_hdmi_r_fifo            ;
    wire                                full_hdmi_r_fifo           ;
    wire                 [R_HDMI_FIFO_WR_DATA_CNT_WIDTH-1: 0]wr_data_count_hdmi_r_fifo  ;
    wire                                wr_rst_busy_hdmi_r_fifo    ;

//===============================================================================================================
//逻辑输出

//===============================================================================================================
//调用底层模块
////////////////////////////////////////// hdmi_r_module_fifo //////////////////////////////////////////////
hdmi_r_module_fifo hdmi_r_module_fifo (
    .rst                                (rst_hdmi_r_fifo           ),// input wire rst

    .wr_clk                             (clk                       ),// input wire wr_clk
    .din                                (din_hdmi_r_fifo           ),// input wire [127 : 0] din
    .wr_en                              (wr_en_hdmi_r_fifo         ),// input wire wr_en
    .full                               (full_hdmi_r_fifo          ),// output wire full
    .wr_data_count                      (wr_data_count_hdmi_r_fifo ),// output wire [6 : 0] wr_data_count
    .wr_rst_busy                        (wr_rst_busy_hdmi_r_fifo   ),// output wire wr_rst_busy

    .rd_clk                             (rdfifo_clk                ),// input wire rd_clk
    .dout                               (dout_hdmi_r_fifo          ),// output wire [15 : 0] dout
    .rd_en                              (rd_en_hdmi_r_fifo         ),// input wire rd_en
    .empty                              (empty_hdmi_r_fifo         ),// output wire empty
    .rd_data_count                      (rd_data_count_hdmi_r_fifo ),// output wire [9 : 0] rd_data_count
    .rd_rst_busy                        (rd_rst_busy_hdmi_r_fifo   ) // output wire rd_rst_busy
);

////////////////////////////////////////// hdmi_r_axi4_to_fifo //////////////////////////////////////////////

hdmi_r_axi4_to_fifo#(
    .BUF_A_BEGIN                        (PROC_BUF_0                ),
    .BUF_B_BEGIN                        (PROC_BUF_1                ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH            ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH            ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH              ),
    .AXI_ID                             (HDMI_AXI_ID               ),
    .AXI_BURST_LEN                      (AXI_BURST_LEN             ),
    .FIFO_ADDR_WIDTH                    (R_HDMI_FIFO_WR_DATA_CNT_WIDTH),
    .AXI_ARBURST_INCR                   (AXI_ARBURST_INCR          ),
    .AXI_ARLOCK_NORMAL                  (AXI_ARLOCK_NORMAL         ),
    .AXI_ARCACHE_DEVICE_NON_BUF         (AXI_ARCACHE_DEVICE_NON_BUF),
    .AXI_ARPROT_UNPRIV_SECURE           (AXI_ARPROT_UNPRIV_SECURE  ),
    .AXI_ARQOS_DEFAULT                  (AXI_ARQOS_DEFAULT         ),
    .AXI_ARREGION_DEFAULT               (AXI_ARREGION_DEFAULT      ),
    .AXI_RRESP_OKAY                     (AXI_RRESP_OKAY            ),
    .AXI_RESET_POLARITY                 (AXI_RESET_POLARITY        ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ) 
)
 u_hdmi_r_axi4_to_fifo(

    .clk                                (clk                       ),// (input)
    .reset                              (reset                     ),// (input)
// ==================== 读FIFO写入侧接口 ====================
    .fifo_wrreq                         (wr_en_hdmi_r_fifo         ),// (output)
    .fifo_wrdata                        (din_hdmi_r_fifo           ),// (output)
    .fifo_alfull                        (full_hdmi_r_fifo          ),// (input)
    .fifo_wr_cnt                        (wr_data_count_hdmi_r_fifo ),// (input)
    .fifo_rst_busy                      (wr_rst_busy_hdmi_r_fifo   ),// (input)
// ==================== 读地址通道 ====================
    .m_axi_arid                         (m_axi_hdmi_arid           ),// (output)
    .m_axi_araddr                       (m_axi_hdmi_araddr         ),// (output)
    .m_axi_arlen                        (m_axi_hdmi_arlen          ),// (output)
    .m_axi_arsize                       (m_axi_hdmi_arsize         ),// (output)
    .m_axi_arburst                      (m_axi_hdmi_arburst        ),// (output)
    .m_axi_arlock                       (m_axi_hdmi_arlock         ),// (output)
    .m_axi_arcache                      (m_axi_hdmi_arcache        ),// (output)
    .m_axi_arprot                       (m_axi_hdmi_arprot         ),// (output)
    .m_axi_arqos                        (m_axi_hdmi_arqos          ),// (output)
    .m_axi_arregion                     (m_axi_hdmi_arregion       ),// (output)
    .m_axi_arvalid                      (m_axi_hdmi_arvalid        ),// (output)
    .m_axi_arready                      (m_axi_hdmi_arready        ),// (input)
// ==================== 读数据通道 ====================
    .m_axi_rid                          (m_axi_hdmi_rid            ),// (input)
    .m_axi_rdata                        (m_axi_hdmi_rdata          ),// (input)
    .m_axi_rresp                        (m_axi_hdmi_rresp          ),// (input)
    .m_axi_rlast                        (m_axi_hdmi_rlast          ),// (input)
    .m_axi_rvalid                       (m_axi_hdmi_rvalid         ),// (input)
    .m_axi_rready                       (m_axi_hdmi_rready         ),// (output)
//==================== 实验接口 ====================
    .r_done                             (r_done                    ),// (output)//内建的一帧读完信号，可靠的前提是，读取也必须精准申请数据
    .rd_enable                          (hdmi_rd_enable            ),// (input)
    .r_module_ddr3_r_req                (r_module_ddr3_r_req       ),// (output)
    .hdmi_r_start_pulse                 (hdmi_r_start_pulse        ),// (input)
    .hdmi_burst_done                    (hdmi_burst_done           ),// (output)
// ==================== 缓存切换逻辑信号 ====================
    .r_buf                              (r_buf                     ),// (input)// 0=读帧A, 1=读帧B,默认读B
    .r_addr_switch_pulse                (r_addr_switch_pulse       ) // (input)// 地址切换脉冲，与指针一同出现
);

endmodule
