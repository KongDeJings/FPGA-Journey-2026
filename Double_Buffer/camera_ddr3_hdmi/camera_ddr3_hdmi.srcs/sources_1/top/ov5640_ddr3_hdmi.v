`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/05/15 16:41:51
// Design Name: 
// Module Name: ov5640_ddr3_hdmi
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 代码禁止出现魔数，全部参数化！
//////////////////////////////////////////////////////////////////////////////////

module ov5640_ddr3_hdmi
#(
    // ==================== 有关输出的图像信息 ====================
    parameter                           IMAGE_TYPE                  = 0                    ,//0:RGB   1：JPEG
    parameter                           IMAGE_WIDTH                 = 1280                 ,//图片宽度
    parameter                           IMAGE_HEIGHT                = 720                  ,//图片高度(≤720)
    parameter                           IMAGE_FLIP                  = 0                    ,//0:不翻转,1:上下翻转
    parameter                           IMAGE_MIRROR                = 0                    ,//0:不镜像,1:左右镜像 
    // ==================== 摄像头初始化 ====================    
    parameter                           SYS_CLOCK                   = 50_000_000           ,//系统时钟频率
    parameter                           SCL_CLOCK                   = 80_000               ,//希望SCCB跑多少频率。SCCB 时钟频率是否在 100kHz 以内（OV5640 要求）
    parameter                           FPS_MAX                     = 120                  ,//帧率最大值
    parameter                           FIFO_ADDR_DEPTH             = 64                   ,
    parameter                           FIFO_DW                     = 16                   ,  //fifo din/dout的位宽，异步FIFO内部完成 16bit → 128bit 位宽拼接，转到AXI4时为128bit
    parameter                           FIFO_ADDR_WIDTH             = $clog2(FIFO_ADDR_DEPTH),
    // ==================== 地址与数据参数 ====================
    parameter                           RD_AXI_BYTE_ADDR_BEGIN      = 0                    ,//暂时不用的信息
    parameter                           RD_AXI_BYTE_ADDR_END        = 0                    ,//暂时不用的信息

    parameter                           BUF_A_BEGIN                 = 32'h0100_0000        ,//缓存A基地址
    parameter                           BUF_B_BEGIN                 = 32'h0120_0000        ,//缓存B基地址
    parameter                           AXI_DATA_WIDTH              = 128                  ,
    parameter                           AXI_ADDR_WIDTH              = 32                   ,
    parameter                           AXI_ID_WIDTH                = 4                    ,
    parameter                           CAMERA_AXI_ID               = 0                    ,
    parameter                           AXI_BURST_LEN               = 31                   ,


    // ==================== AXI 固定协议参数 ====================
    parameter                           AXI_ARBURST_INCR            = 2'b01                ,
    parameter                           AXI_ARLOCK_NORMAL           = 1'b0                 ,
    parameter                           AXI_ARCACHE_DEVICE_NON_BUF  = 4'b0000              ,
    parameter                           AXI_ARPROT_UNPRIV_SECURE    = 3'b000               ,
    parameter                           AXI_ARQOS_DEFAULT           = 4'b0000              ,
    parameter                           AXI_ARREGION_DEFAULT        = 4'b0000              ,
    parameter                           AXI_RRESP_OKAY              = 2'b00                ,

    parameter                           AXI_AWBURST_INCR            = 2'b01                ,
    parameter                           AXI_AWLOCK_NORMAL           = 1'b0                 ,
    parameter                           AXI_AWCACHE_DEVICE_NON_BUF  = 4'b0000              ,
    parameter                           AXI_AWPROT_UNPRIV_SECURE    = 3'b000               ,
    parameter                           AXI_AWQOS_DEFAULT           = 4'b0000              ,
    parameter                           AXI_AWREGION_DEFAULT        = 4'b0000              ,
    parameter                           AXI_BRESP_OKAY              = 2'b00                ,
    parameter                           AXI_WSTRB_ALL_VALID         = 1'b1                 ,
    parameter                           AXI_RESET_POLARITY          = 1'b1                 

)
(
    // ==================== 全局信号 ====================
    input                               clk                        ,//系统时钟输入，50MHz
    input                               rst_n                      ,//绑定按键，系统复位按键

    // ==================== ov5640接口(sccb_master) ====================
    input                               camera_vsync               ,//DVP信号输入
    input                               camera_href                ,
    input                               camera_pclk                ,
    input                [   7: 0]      camera_data                ,

    output                              sccb_sclk                  ,//初始化时的sccb时钟，设置为80kHz
    inout                               sccb_sdat                  ,//SCCB数据线

    output                              camera_xclk                ,//外部主时钟输入	24MHz
    output                              camera_rst_n               ,// 给摄像头的复位信号
    output                              camera_pwdn                ,// 摄像头省电模式（这里直接关掉，为0）

    // ==================== HDMI驱动输出接口 ====================
    output                              tmds_clk_p                 ,
    output                              tmds_clk_n                ,
    output               [   2: 0]      TMDS_Data_p                ,
    output               [   2: 0]      TMDS_Data_n                ,
    output                              hdmi1_oe                   ,//该信号必须置1，控制HMDI输出5V信号给显示器

    // ==================== DDR3接口 ====================

    inout                [  15: 0]      ddr3_dq                    ,
    inout                [   1: 0]      ddr3_dqs_n                 ,
    inout                [   1: 0]      ddr3_dqs_p                 ,
     
    output               [  13: 0]      ddr3_addr                  ,
    output               [   2: 0]      ddr3_ba                    ,
    output                              ddr3_ras_n                 ,
    output                              ddr3_cas_n                 ,
    output                              ddr3_we_n                  ,
    output                              ddr3_reset_n               ,
    output               [   0: 0]      ddr3_ck_p                  ,
    output               [   0: 0]      ddr3_ck_n                  ,
    output               [   0: 0]      ddr3_cke                   ,
    output               [   0: 0]      ddr3_cs_n                  ,
    output               [   1: 0]      ddr3_dm                    ,
    output               [   0: 0]      ddr3_odt                   ,

    // ==================== 复位及关键信号 ====================

    output               [   4: 0]      state_led                   //指示系统复位状态
    
    );


//===============================================================================================================   
//本地参数及接口定义、连线


   // ==================== ov5640接口

    wire                                       camera_init_done           ;
    wire                                       camera_init_fail           ;

   // ==================== DVP信号处理

    wire                                       frame_rst_state            ;// 复位时为1，需清空fifo中残留的图像数据
    wire                                       pixel_data_valid           ;// 图像数据有效（丢弃前10帧信号后），可直接当作fifo的写入信号用
    wire                                       pixel_data_vs              ;// 行同步
    wire                                       pixel_data_hs              ;// 场同步
    wire                      [  15: 0]        pixel_data                 ;// RGB_565信号
    wire                      [($clog2(IMAGE_WIDTH))-1: 0]haddr           ;// 标定像素在行的位置,从1开始算起
    wire                      [($clog2(IMAGE_HEIGHT))-1: 0]vaddr          ;// 标定像素在列的位置,从1开始算起
    wire     [$clog2(IMAGE_WIDTH * IMAGE_HEIGHT)-1:0] wr_pixel_cnt        ;//写像素计数器（用于 FIFO / DDR 帧结束判断）


   // ==================== 摄像头帧率频率监控

    wire                      [($clog2(FPS_MAX))-1:0]fps                  ;
    wire                      [($clog2(SYS_CLOCK))-1:0]PCLK_measure       ;//PCLK频率监控

   // ==================== hdmi模块驱动

    wire                 [  11: 0]      h_counter                  ;//hdmi行计数器
    wire                 [  10: 0]      v_counter                  ;//hdmi列计数器
    wire                 [  23: 0]      hdmi_data                  ;//hdmi输入数据
    wire                                disp_data_req              ;//ddr3 读侧fifo读使能
    wire                                frame_begin                ;//ddr3 读侧fifo清零信号
    wire                                DE                         ;

   // ==================== ddr3双帧缓存切换



   // ==================== ddr3顶层模块

   wire                                       ddr3_init_done             ;//ddr3初始化完成信号
   wire                      [FIFO_DW-1: 0]   wrfifo_din                 ;
   wire                      [FIFO_DW-1: 0]   rdfifo_dout                ;

    //需跨时钟域同步的信号
        wire                                ddr3_init_done_sync_sys_clk  ;

    //  悬空暂未使用
       wire                                       wrfifo_full                ;
       wire                      [  15: 0]        wrfifo_wr_cnt              ;
       wire                                       rdfifo_empty               ;
       wire                      [  15: 0]        rdfifo_rd_cnt              ;
       wire                                         camera_w_done            ;


   // ==================== 全局时钟及模块时钟

    wire                                sys_clk                    ;//大部分模块用的50M时钟
    wire                                dvi_clk_100m               ;//用以产生像素时钟
    wire                                pixel_clk_5x               ;//hdmi驱动时钟
    wire                                camera_xclk_24M            ;//摄像头xclk输入

    wire                                ddr3_clk_200m              ;//mig输入时钟
    wire                                mig_ui_clk                 ;//ddr3输出的用户侧时钟 
    wire                                pixel_clk_74m              ;//hdmi驱动时钟
    wire                                PCLK_bufg                  ;//摄像头DVP接口输出的PCLK时钟

    
   // ==================== 全局复位及各个模块的异步复位同步释放
    wire                                sys_rst_n                  ;//消抖后的系统按键复位输出，仅作用于PLL、产生global_rst_n
    wire                                global_rst_n               ;//全局复位信号，低电平有效

    wire                                main_pll_locked            ;//主pll输出的locked信号
    wire                                dvi_pll_locked             ;//显示驱动pll输出的locked信号


    wire                                dvp_pclk_sync_rst_n        ;
    wire                                pixel_clk_sync_rst_n       ;
    wire                                 sys_clk_sync_rst_n        ;// sys_clk时钟域的同步复位
    wire                                ui_clk_sync_rst            ;//mig侧输出的复位ui_clk_sync_rst

    assign                              sys_rst_n                   = rst_n                ;//暂时弃用复位按键输入消抖
assign global_rst_n   =      sys_rst_n & main_pll_locked & dvi_pll_locked & ddr3_init_done_sync_sys_clk;




//===============================================================================================================
//逻辑输出
//////////////////////////////////////////////////////////////////////////////////
//=================================================
//指示系统状态
assign state_led={camera_init_done,camera_init_fail,ddr3_init_done,main_pll_locked,dvi_pll_locked};

//=================================================
//将读fifo中读出的RGB565数据转化为rgb888数据，送入显示模块
wire [23:0]disp_data;//待显示的拼接RGB88信号
assign disp_data = {rdfifo_dout[15:11],3'd0,rdfifo_dout[10:5],2'd0,rdfifo_dout[4:0],3'd0};
//assign disp_data =rd_frame_sel?24'hff0000:24'h0000ff;
//=================================================
//打开hdmi开关
assign hdmi1_oe = 1'b1;

//=================================================
//将pll输出的24m时钟与xclk连接
assign camera_xclk = camera_xclk_24M;





//===============================================================================================================
//监控探头ILA

//===============================================================================================================   
//处理CDC问题,说明源时钟域和目的时钟域
//=================================================
// 将ddr3的ddr3_init_done 同步到sys_clk时钟域

xpm_cdc_single #(
    .DEST_SYNC_FF                       (3                         ),
    .SRC_INPUT_REG                      (0                         ),
    .INIT_SYNC_FF                       (0                         ) 
) u_vsync_ddr3_init_done_sync (
    .src_clk                            (mig_ui_clk                ),
    .dest_clk                           (sys_clk                   ),
    .src_in                             (ddr3_init_done            ),
    .dest_out                           (ddr3_init_done_sync_sys_clk) 
);

//=================================================
// 将camera的写完一帧信号同步到hdmi时钟域

wire camera_w_done_hdmi_clk;

xpm_cdc_single #(
    .DEST_SYNC_FF                       (3                         ),
    .SRC_INPUT_REG                      (0                         ),
    .INIT_SYNC_FF                       (0                         ) 
) cam_w_done_hdmi_clk (
    .src_clk                            (mig_ui_clk                ),
    .dest_clk                           (pixel_clk_74m             ),
    .src_in                             (camera_w_done             ),
    .dest_out                           (camera_w_done_hdmi_clk    ) 
);
//===============================================================================================================   
//处理异步复位同步释放问题,根据时钟域划分，同一个时钟域使用同一种复位

//=================================================
// PCLK时钟域复位

   xpm_cdc_async_rst #(
    .DEST_SYNC_FF                       (3                         ),// DECIMAL; range: 2-10
    .INIT_SYNC_FF                       (0                         ),// DECIMAL; 0=disable simulation init values, 1=enable simulation init values
    .RST_ACTIVE_HIGH                    (0                         ) // DECIMAL; 0=active low reset, 1=active high reset
   )
   xpm_cdc_async_rst_pclk (
    .dest_arst                          (dvp_pclk_sync_rst_n       ),//PCLK时钟域
    .dest_clk                           (PCLK_bufg                 ),// 1-bit input: Destination clock.
    .src_arst                           (global_rst_n              ) // 1-bit input: Source asynchronous reset signal.
   );

//=================================================
// hdmi_pixel_clk时钟域复位

  xpm_cdc_async_rst #(
    .DEST_SYNC_FF                       (3                         ),// DECIMAL; range: 2-10
    .INIT_SYNC_FF                       (0                         ),// DECIMAL; 0=disable simulation init values, 1=enable simulation init values
    .RST_ACTIVE_HIGH                    (0                         ) // DECIMAL; 0=active low reset, 1=active high reset
   )
   xpm_cdc_async_rst_pixel_clk (
    .dest_arst                          (pixel_clk_sync_rst_n      ),
    .dest_clk                           (pixel_clk_74m             ),// 1-bit input: Destination clock.
    .src_arst                           (global_rst_n              ) // 1-bit input: Source asynchronous reset signal.
   );

//=================================================
// sys_clk时钟域复位

  xpm_cdc_async_rst #(
    .DEST_SYNC_FF                       (3                         ),// DECIMAL; range: 2-10
    .INIT_SYNC_FF                       (0                         ),// DECIMAL; 0=disable simulation init values, 1=enable simulation init values
    .RST_ACTIVE_HIGH                    (0                         ) // DECIMAL; 0=active low reset, 1=active high reset
   )
   xpm_cdc_async_rst_sys_clk (
    .dest_arst                          (sys_clk_sync_rst_n        ),
    .dest_clk                           (sys_clk                   ),// 1-bit input: Destination clock.
    .src_arst                           (global_rst_n              ) // 1-bit input: Source asynchronous reset signal.
   );



//===============================================================================================================
//调用底层模块
//////////////////////////////////////////    PLL       //////////////////////////////////////////////
  Main_PLL Main_PLL
   (
    // Clock out ports
    .sys_clk                            (sys_clk                   ),// output sys_clk，这个时钟是系统主时钟
    .dvi_clk_100m                       (dvi_clk_100m              ),// output dvi_clk_100m
    .ddr3_clk_200m                      (ddr3_clk_200m             ),// output ddr3_clk_200m
    .camera_xclk_24M                    (camera_xclk_24M           ),// output camera_xclk_24M
    // Status and control signals
    .resetn                             (sys_rst_n                 ),// input resetn
    .locked                             (main_pll_locked           ),// output locked
   // Clock in ports
    .clk                                (clk)                      );// 板子上的系统时钟输入

// ====================产生像素时钟的PLL
  hdmi_PLL hdmi_PLL
   (
    // Clock out ports
    .pixel_clk_74m                      (pixel_clk_74m             ),// output pixel_clk_74m
    .pixel_clk_5x                       (pixel_clk_5x              ),// output pixel_clk_5x_370Mhz
    // Status and control signals
    .resetn                             (sys_rst_n                 ),// input resetn
    .locked                             (dvi_pll_locked            ),// output locked
   // Clock in ports
    .dvi_clk_100m                       (dvi_clk_100m)             );// input dvi_clk_100m

//将摄像头的PLCK过一遍BUFG(导致[Place 30-574] Poor placement for routing between an IO pin and BUFG. ）

   BUFG BUFG_inst (
    .O                                  (PCLK_bufg                 ),// 1-bit output: Clock output
    .I                                  (camera_pclk               ) // 1-bit input: Clock input
   );

//////////////////////////////////////////    DDR3双源图像切换       //////////////////////////////////////////////


//////////////////////////////////////////    DVP信号处理模块       //////////////////////////////////////////////

dvp_capture#(
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
    .DUMP_FRAMES                        (4'd10                     ) 
)
 u_dvp_capture(
// ==================== 全局信号  ====================
    .rst_n                              (dvp_pclk_sync_rst_n       ),
// ==================== DVP信号输入  ====================
    .vsync                              (camera_vsync              ),// 场同步信号
    .href                               (camera_href               ),// 行有效信号
    .DVP_data                           (camera_data               ),
    .PCLK                               (PCLK_bufg                 ),
// ==================== 对外控制接口 ====================
    .frame_rst_state                    (frame_rst_state           ),// 复位时为1，需清空fifo中残留的图像数据
    .pixel_data_valid                   (pixel_data_valid          ),// 图像数据有效（丢弃前10帧信号后），可直接当作fifo的写入信号用
    .pixel_data_vs                      (pixel_data_vs             ),// 行同步
    .pixel_data_hs                      (pixel_data_hs             ),// 场同步
// ==================== 数据输出    ====================
    .pixel_data                         (pixel_data                ),// RGB_565信号
    .haddr                              (haddr                     ),// 标定像素在行的位置,从1开始算起
    .vaddr                              (vaddr                     )// 标定像素在列的位置,从1开始算起
);


//////////////////////////////////////////    摄像头帧率频率监控模块       //////////////////////////////////////////////
camera_monitor
 u_camera_monitor(
    .clk                                (sys_clk                   ),
    .rst_n                              (sys_clk_sync_rst_n        ),
    .PCLK                               (PCLK_bufg                 ),
    .vsync                              (camera_vsync              ),
    .fps                                (fps                       ),
    .PCLK_measure                       (PCLK_measure              ) 
);
// ====================配套的vio

vio_camera_monitor vio_camera_monitor (
    .clk                                (sys_clk                   ),// input wire clk
    .probe_in0                          (fps                       ),// input wire [7 : 0] probe_in0
    .probe_in1                          (PCLK_measure              ) // input wire [31 : 0] probe_in1
);


//////////////////////////////////////////    HDMI驱动输出       //////////////////////////////////////////////

hdmi_driver u_hdmi_driver(
    .clk                                (pixel_clk_74m             ),
    .clk_5x                             (pixel_clk_5x              ),
    .rst_n                              (pixel_clk_sync_rst_n      ),
    .Data_i                             (disp_data                 ),//ddr3读fifo中的数据，经过加0拼接后通过hdmi输出
    .h_counter                          (h_counter                 ),
    .v_counter                          (v_counter                 ),
    .TMDS_Data_p                        (TMDS_Data_p               ),
    .TMDS_Data_n                        (TMDS_Data_n               ),
    .tmds_clk_p                         (tmds_clk_p                ),
    .tmds_clk_n                         (tmds_clk_n                ),
    .disp_data_req                      (disp_data_req             ),// 显示数据请求信号，用以fifo侧读使能
    .frame_begin                        (frame_begin               ),// 用以读fifo清零 
    .VSYNC                              (vsync_hdmi                ),
    .DE                                 (DE                        ),
    .raw_data                           (rdfifo_dout                ),
    .r_hdmi_done                        (hdmi_r_done              ),



    .camera_w_done                      (camera_w_done_hdmi_clk)
);


//////////////////////////////////////////    ddr3顶层模块       //////////////////////////////////////////////

ddr3_ctrl_2port#(

    .FIFO_ADDR_DEPTH                    (FIFO_ADDR_DEPTH           ),
    .FIFO_DW                            (FIFO_DW                   ),
    .FIFO_ADDR_WIDTH                    (FIFO_ADDR_WIDTH           ),
    .RD_AXI_BYTE_ADDR_BEGIN             (RD_AXI_BYTE_ADDR_BEGIN    ),
    .RD_AXI_BYTE_ADDR_END               (RD_AXI_BYTE_ADDR_END      ),
    .BUF_A_BEGIN                        (BUF_A_BEGIN               ),
    .BUF_B_BEGIN                        (BUF_B_BEGIN               ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH            ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH            ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH              ),
    .CAMERA_AXI_ID                      (CAMERA_AXI_ID             ),
    .AXI_BURST_LEN                      (AXI_BURST_LEN             ),
    .AXI_ARBURST_INCR                   (AXI_ARBURST_INCR          ),
    .AXI_ARLOCK_NORMAL                  (AXI_ARLOCK_NORMAL         ),
    .AXI_ARCACHE_DEVICE_NON_BUF         (AXI_ARCACHE_DEVICE_NON_BUF),
    .AXI_ARPROT_UNPRIV_SECURE           (AXI_ARPROT_UNPRIV_SECURE  ),
    .AXI_ARQOS_DEFAULT                  (AXI_ARQOS_DEFAULT         ),
    .AXI_ARREGION_DEFAULT               (AXI_ARREGION_DEFAULT      ),
    .AXI_RRESP_OKAY                     (AXI_RRESP_OKAY            ),
    .AXI_AWBURST_INCR                   (AXI_AWBURST_INCR          ),
    .AXI_AWLOCK_NORMAL                  (AXI_AWLOCK_NORMAL         ),
    .AXI_AWCACHE_DEVICE_NON_BUF         (AXI_AWCACHE_DEVICE_NON_BUF),
    .AXI_AWPROT_UNPRIV_SECURE           (AXI_AWPROT_UNPRIV_SECURE  ),
    .AXI_AWQOS_DEFAULT                  (AXI_AWQOS_DEFAULT         ),
    .AXI_AWREGION_DEFAULT               (AXI_AWREGION_DEFAULT      ),
    .AXI_BRESP_OKAY                     (AXI_BRESP_OKAY            ),
    .AXI_WSTRB_ALL_VALID                (AXI_WSTRB_ALL_VALID       ),
    .AXI_RESET_POLARITY                 (AXI_RESET_POLARITY        ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ) 

)
 u_ddr3_ctrl_2port(
    // ==================== 全局信号 ====================
    .ddr3_clk200m                       (ddr3_clk_200m             ),
    .ddr3_rst                           (main_pll_locked           ),
    .ddr3_init_done                     (ddr3_init_done            ),

    // ==================== 写FIFO用户写入侧接口 ====================
    .wrfifo_clr                         (frame_rst_state           ),//DVP——capture输出的同步信号
    .wrfifo_clk                         (PCLK_bufg                 ),
    .wrfifo_wren                        (pixel_data_valid          ),
    .wrfifo_din                         (pixel_data                ),
 //  .wrfifo_wren                        (test_pixel_valid          ),测试数据输入端口
 //  .wrfifo_din                         (test_pixel_data           ),测试数据输入端口

    .wrfifo_full                        (wrfifo_full               ),
    .wrfifo_wr_cnt                      (wrfifo_wr_cnt             ),
    // ==================== 读FIFO用户侧接口 ====================
    .rdfifo_clr                         (frame_rst_state           ),
    .rdfifo_clk                         (pixel_clk_74m             ),
    .rdfifo_rden                        (disp_data_req             ),
    .rdfifo_dout                        (rdfifo_dout               ),
    .rdfifo_empty                       (rdfifo_empty              ),
    .rdfifo_rd_cnt                      (rdfifo_rd_cnt             ),
    // ==================== DDR3侧接口 ====================
    .ddr3_dq                            (ddr3_dq                   ),
    .ddr3_dqs_n                         (ddr3_dqs_n                ),
    .ddr3_dqs_p                         (ddr3_dqs_p                ),
    .ddr3_addr                          (ddr3_addr                 ),
    .ddr3_ba                            (ddr3_ba                   ),
    .ddr3_ras_n                         (ddr3_ras_n                ),
    .ddr3_cas_n                         (ddr3_cas_n                ),
    .ddr3_we_n                          (ddr3_we_n                 ),
    .ddr3_reset_n                       (ddr3_reset_n              ),
    .ddr3_ck_p                          (ddr3_ck_p                 ),
    .ddr3_ck_n                          (ddr3_ck_n                 ),
    .ddr3_cke                           (ddr3_cke                  ),
    .ddr3_cs_n                          (ddr3_cs_n                 ),
    .ddr3_dm                            (ddr3_dm                   ),
    .ddr3_odt                           (ddr3_odt                  ),
    // ==================== 输出mig侧的时钟和复位 ====================
    .ui_clk                             (mig_ui_clk                ),
    .ui_clk_sync_rst                    (ui_clk_sync_rst           ),

    // ==================== 实验接口 ====================
    .w_done                             (camera_w_done             )//output,用以hdmi模块产生读fifo使能disp_data_req
);


//////////////////////////////////////////    摄像头初始化模块       //////////////////////////////////////////////

sccb_master#(
    .IMAGE_TYPE                         (IMAGE_TYPE                ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
    .IMAGE_FLIP                         (IMAGE_FLIP                ),
    .IMAGE_MIRROR                       (IMAGE_MIRROR              ),
    .SYS_CLOCK                          (SYS_CLOCK                 ),
    .SCL_CLOCK                          (SCL_CLOCK                 ) //sccb时钟频率
)
 camera_init(
// ==================== 全局信号 ====================
    .clk                                (sys_clk                   ),
    .rst_n                              (sys_clk_sync_rst_n        ),
// ==================== camera参数接口 ====================
    .camera_init_done                   (camera_init_done          ),// 配置完成标志（做完变1）
    .camera_init_fail                   (camera_init_fail          ),// 配置失败（做完变1）
    .camera_rst_n                       (camera_rst_n              ),// 给摄像头的复位信号
    .camera_pwdn                        (camera_pwdn               ),// 摄像头省电模式（这里直接关掉，为0）
// ==================== 物理层接口(iic) ====================
    .iic_sclk                           (sccb_sclk                 ),
    .iic_sdat                           (sccb_sdat                 ) 
);





endmodule

//////////////////////////////////////////    调试过程中弃用的方案       //////////////////////////////////////////////
/*
//==================================================================================================
//按键复位输入消抖模块 
//弃用原因，加不加影响不大，加了导致复位无法释放（不可综合的消抖模块），不加复位系统正常，也从未出错

key_filter#(
    .CLK_FREQ                           (50_000_000                ),
    .DEBOUNCE_MS                        (20                        ) 
)
 u_key_filter(
    .clk                                (sys_clk                   ),// 系统主时钟
    .key_in                             (rst_n                     ),// 外部复位按键输入
    .sys_rst_n                          (sys_rst_n                 ) // 消抖后的系统按键复位输出
);

//==================================================================================================
//使用camera和hdmi的vysnc来标定写完和读完成
//弃用原因，跨时钟域后导致画面闪屏，不稳定，但是图像不错位！
//后续加了时序约束可考虑用回
wire   vsync_hdmi;
assign vsync_camera=camera_vsync;

wire vsync_hdmi_ui_clk;   
wire vsync_camera_ui_clk;

// 在ui时钟域下检测vsync_camera，并得出上升沿信号(dvp_done)
reg [1:0]vsync_dvp_r;
always @(posedge mig_ui_clk or posedge ui_clk_sync_rst)   
        begin                                        
            if(ui_clk_sync_rst)                               
                vsync_dvp_r<=0;
            else begin
                vsync_dvp_r[0]<=vsync_camera_ui_clk;
                vsync_dvp_r[1]<=vsync_dvp_r[0];
            end                                               
        end                                          
assign  dvp_done= vsync_dvp_r==2'b01;

//用以检测vsync_hdmi下降沿,得出下降沿信号(hdmi_done)
reg [1:0]vsync_hdmi_r;
always @(posedge mig_ui_clk or posedge ui_clk_sync_rst)   
        begin                                        
            if(ui_clk_sync_rst)                               
                vsync_hdmi_r<=0;
            else begin
                vsync_hdmi_r[0]<=vsync_hdmi_ui_clk;
                vsync_hdmi_r[1]<=vsync_hdmi_r[0];                
            end      
        end
assign  hdmi_done= vsync_hdmi_r==2'b10;


//=================================================
// 将HDMI的vsync同步到ui_clk时钟域

xpm_cdc_single #(
    .DEST_SYNC_FF                       (3                         ),// 同步级数，
    .SRC_INPUT_REG                      (0                         ),// 是否在源端寄存
    .INIT_SYNC_FF                       (0                         ) // 是否初始化为已知值
) u_vsync_hdmi_sync (
    .src_clk                            (pixel_clk_74m             ),
    .dest_clk                           (mig_ui_clk                ),
    .src_in                             (vsync_hdmi                ),
    .dest_out                           (vsync_hdmi_ui_clk         ) 
);

//=================================================
// 将camera的vsync同步到ui_clk时钟域

xpm_cdc_single #(
    .DEST_SYNC_FF                       (3                         ),
    .SRC_INPUT_REG                      (0                         ),
    .INIT_SYNC_FF                       (0                         ) 
) u_vsync_cam_sync (
    .src_clk                            (PCLK_bufg                 ),
    .dest_clk                           (mig_ui_clk                ),
    .src_in                             (vsync_camera              ),
    .dest_out                           (vsync_camera_ui_clk       ) 
);



//==================================================================================================
//使用DVP capture输出的像素计数器来标定写完成
//弃用原因：图像错位！
//后续不考虑，已用数突发写入次数来代替（关联axi id）

wire camera_w_done;
wire camera_w_done_pulse_ui_clk;
reg camera_w_done_pulse;//只持续 1 个 PCLK
assign camera_w_done=    pixel_data_valid &&
                        (haddr == IMAGE_WIDTH -1) &&
                        (vaddr == IMAGE_HEIGHT-1 );
always @(posedge PCLK_bufg or negedge dvp_pclk_sync_rst_n) begin
    if (!dvp_pclk_sync_rst_n)
        camera_w_done_pulse <= 0;
    else if (camera_w_done)
        camera_w_done_pulse <= 1;
    else
        camera_w_done_pulse <= 0;
end

//=================================================
// 将camerad的一帧写完信号同步到ui_clk时钟域

xpm_cdc_single #(
    .DEST_SYNC_FF                       (3                         ),
    .SRC_INPUT_REG                      (0                         ),
    .INIT_SYNC_FF                       (0                         ) 
) u_camera_w_done_pulse_sync (
    .src_clk                            (PCLK_bufg                 ),
    .dest_clk                           (mig_ui_clk                ),
    .src_in                             (camera_w_done_pulse       ),
    .dest_out                           (camera_w_done_pulse_ui_clk) 

);


//==================================================================================================
//测试图像生成器（定位错位用），问题已解决，遂弃用
//将实现原理：将行号转化为5次突发（256一次突发，1280一共计数5次突发），将列号直接在图像上标记出来，同时标记一帧图像的开始和结尾，用不同颜色
reg                     test_pixel_valid;
reg [15:0]              test_pixel_data;
reg [ 9:0]              test_row;        // 行号 1~720
reg [10:0]              test_col;        // 列号 0~1279
reg [ 2:0]              test_burst;      // 行内突发号 1~5

always @(posedge PCLK_bufg) begin
    if (frame_rst_state) begin
        test_row   <= 10'd1;
        test_col   <= 11'd0;
        test_burst <= 3'd1;
    end else if (pixel_data_valid) begin
        if (test_col == IMAGE_WIDTH - 1) begin
            // 行尾：复位列和突发号，行号加1
            test_col   <= 11'd0;
            test_burst <= 3'd1;
            test_row   <= (test_row == IMAGE_HEIGHT) ? 10'd1 : test_row + 10'd1;
        end else begin
            test_col <= test_col + 11'd1;
            // 每256个像素，突发号加1（1→2→3→4→5→1...）
            if (test_col > 0 && (test_col % 256 == 0))
                test_burst <= (test_burst == 3'd5) ? 3'd1 : test_burst + 3'd1;
        end
    end
end

localparam MARKER_BEGIN   = 16'hF7F7;   // 帧头标记：纯白
localparam MARKER_END = 16'h001F;   // 帧尾标记：纯蓝

always @(posedge PCLK_bufg) begin
    test_pixel_valid <= pixel_data_valid;
    
    // 帧头标记：第1行、第1次突发（列0~255）
//    if (test_row == 10'd1 && test_burst == 3'd1)
    if (test_row == 10'd1 &&  test_col == 3'd0)
        test_pixel_data <= MARKER_BEGIN;
    // 帧尾标记：第720行、第5次突发（列1024~1279）
    else if (test_row == IMAGE_HEIGHT && test_burst == 3'd5)
        test_pixel_data <= MARKER_END;
    // 其他像素：保持行列编码
    else
        test_pixel_data <= {test_row[9:0], 3'b000, test_burst};
end



//==================================================================================================
//利用hdmi_driver的行、列计数器，产生一帧读结束信号
//这个信号在单缓中相当稳定，单在缓冲切换时会导致fifo中留有上一帧的数据，不能用于缓存切换，遂弃用

wire hdmi_r_done;
assign hdmi_r_done = ( h_counter== IMAGE_WIDTH - 1) &&
                     ( v_counter== IMAGE_HEIGHT - 1);
reg   hdmi_r_done_pulse;//只持续 1 个 pixel_clk
wire hdmi_r_done_pulse_ui_clk;

always @(posedge pixel_clk_74m or negedge pixel_clk_sync_rst_n) begin
    if (!pixel_clk_sync_rst_n)
        hdmi_r_done_pulse <= 0;
    else if (hdmi_r_done)
        hdmi_r_done_pulse <= 1;
    else
        hdmi_r_done_pulse <= 0;
end
//=================================================
// 将hmdi的一帧写完信号同步到ui_clk时钟域

xpm_cdc_single #(
    .DEST_SYNC_FF                       (3                         ),
    .SRC_INPUT_REG                      (0                         ),
    .INIT_SYNC_FF                       (0                         ) 
) u_hdmi_r_done_pulse_sync (
    .src_clk                            (pixel_clk_74m             ),
    .dest_clk                           (mig_ui_clk                ),
    .src_in                             (hdmi_r_done_pulse         ),
    .dest_out                           (hdmi_r_done_pulse_ui_clk  ) 

);
*/
