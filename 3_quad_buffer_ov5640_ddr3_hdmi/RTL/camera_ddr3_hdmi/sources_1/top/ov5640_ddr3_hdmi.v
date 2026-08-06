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
    // ==================== FIFO相关参数 ====================
    parameter                           FIFO_USER_DATA_WIDTH        = 16                   ,  //fifo din/dout的位宽，异步FIFO内部完成 16bit → 128bit 位宽拼接，转到AXI4时为128bit
    parameter                           R_FIFO_RD_DATA_CNT_WIDTH    = 11                   ,
    parameter                           R_FIFO_WR_DATA_CNT_WIDTH    = 8                    ,
    parameter                           W_FIFO_RD_DATA_CNT_WIDTH    = 8                    ,
    parameter                           W_FIFO_WR_DATA_CNT_WIDTH    = 11                   ,

    parameter                           R_HDMI_FIFO_RD_DATA_CNT_WIDTH= 10                  ,
    parameter                           R_HDMI_FIFO_WR_DATA_CNT_WIDTH= 7                   , 

    parameter                           W_CAM_FIFO_RD_DATA_CNT_WIDTH= 7                    ,
    parameter                           W_CAM_FIFO_WR_DATA_CNT_WIDTH= 10                   ,    
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

    parameter                           IN_BUF_0                    = 32'h0000_0000        ,//缓存A基地址
    parameter                           IN_BUF_1                    = 32'h0080_0000        ,//缓存B基地址

    parameter                           PROC_BUF_0                  = 32'h0100_0000        ,//缓存A基地址
    parameter                           PROC_BUF_1                  = 32'h0180_0000        ,//缓存B基地址

    parameter                           AXI_DATA_WIDTH              = 128                  ,
    parameter                           AXI_ADDR_WIDTH              = 32                   ,
    parameter                           AXI_ID_WIDTH                = 4                    ,
    parameter                           AXI_BURST_LEN               = 31                   ,
    parameter                           AXI_SIZE                    = 4                    ,

    parameter                           CAM_AXI_ID                  = 4'b0001              ,
    parameter                           PROC_P_AXI_ID               = 4'b0010              , 
    parameter                           HDMI_AXI_ID                 = 4'b0100              , 
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
    parameter                           AXI_RESET_POLARITY          = 1'b1                 ,

    // ==================== 有关sobel处理的相关信息 ====================
    parameter                           GRAY_PIC_DATA_WIDTH         = 8                    ,// 灰度图像素位宽
    parameter                           RGB_PIC_DATA_WIDTH          = 16                   ,// 灰度图像素位宽
    parameter                           PROC_TYPE                   = 0                    ,// 0:灰度直出  1:二值化
    parameter                           THRESHOLD                   = 125                  ,// 二值化阈值（仅 PROC_TYPE=1 时有效）
    parameter                           LINE_LEN                    = 1920                  // 行长度，最大 2048，支持 1080p

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
    output                              tmds_clk_n                 ,
    output               [   2: 0]      TMDS_Data_p                ,
    output               [   2: 0]      TMDS_Data_n                ,
    output                              hdmi1_oe                   ,//该信号必须置1，控制HMDI输出5V信号给显示器

    // ==================== 全局信号 ====================

    inout                [  15: 0]      ddr3_dq                    ,
    inout                [   1: 0]      ddr3_dqs_n                 ,
    inout                [   1: 0]      ddr3_dqs_p                 ,
     
    output               [  13: 0]      ddr3_addr                  ,
    output               [   2: 0]      ddr3_ba                    ,
    output                              ddr3_ras_n                 ,
    output                              ddr3_cas_n                 ,
    output                              ddr3_we_n                  ,
    output                              ddr3_reset_n               ,
    output                              ddr3_ck_p                  ,
    output                              ddr3_ck_n                  ,
    output                              ddr3_cke                   ,
    output                              ddr3_cs_n                  ,
    output               [   1: 0]      ddr3_dm                    ,
    output                              ddr3_odt                   ,

    // ==================== 复位及关键信号 ====================

    output               [   4: 0]      state_led                   ,//指示系统复位状态
    input                               p_bypass                     //用以旁路P模块的图像处理功能，1时旁路


    
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

   // ==================== ddr3顶层模块

   wire                                       ddr3_init_done             ;//ddr3初始化完成信号
   wire                      [FIFO_DW-1: 0]   wrfifo_din                 ;


    //需跨时钟域同步的信号
        wire                                ddr3_init_done_sync_sys_clk  ;

    //  悬空暂未使用
       wire                                       wrfifo_full                ;
       wire                      [  15: 0]        wrfifo_wr_cnt              ;
       wire                                       rdfifo_empty               ;
       wire                      [  15: 0]        rdfifo_rd_cnt              ;

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

//=========================MIG控制器顶层连线--------------------------------------------------------------------

    // ==================== 写地址通道 ====================

    reg              [AXI_ID_WIDTH-1: 0]m_axi_awid_dynamic         ;
    reg            [AXI_ADDR_WIDTH-1: 0]m_axi_awaddr_dynamic       ;
    reg                                 m_axi_awvalid_dynamic      ;
    wire                                m_axi_awready_dynamic      ;

    // ==================== 写数据通道 ====================

    reg           [AXI_DATA_WIDTH-1: 0] m_axi_wdata_dynamic        ;
    reg                                 m_axi_wlast_dynamic        ;
    reg                                 m_axi_wvalid_dynamic       ;
    wire                                m_axi_wready_dynamic       ;

    // ==================== 写响应通道 ====================    

    wire                 [AXI_ID_WIDTH-1: 0]m_axi_bid_dynamic      ;
    wire                 [   1: 0]      m_axi_bresp_dynamic        ;
    wire                                m_axi_bvalid_dynamic       ;
    reg                                 s_axi_bready_dynamic       ;

    // ==================== 读地址通道 ====================    

    reg                  [AXI_ID_WIDTH-1: 0]m_axi_arid_dynamic     ;
    reg                  [AXI_ADDR_WIDTH-1: 0]m_axi_araddr_dynamic ;
    reg                                 m_axi_arvalid_dynamic      ;

    wire                                m_axi_arready_dynamic      ;

    // ==================== 读数据通道 ====================   

    wire                 [AXI_ID_WIDTH-1: 0]m_axi_rid_dynamic      ;
    wire                 [AXI_DATA_WIDTH-1: 0]m_axi_rdata_dynamic  ;
    wire                 [   1: 0]      m_axi_rresp_dynamic        ;
    wire                                m_axi_rlast_dynamic        ;
    wire                                m_axi_rvalid_dynamic       ;
    reg                                 m_axi_rready_dynamic       ;

    // ==================== 应用层接口 ====================   

    wire                                mmcm_locked                ;
    wire                                init_calib_complete        ;
    assign                              ddr3_init_done              = mmcm_locked&&init_calib_complete;
//=========================W模块顶层连线--------------------------------------------------------------------

    // ==================== 写FIFO用户写入侧接口 ====================

    wire                                rst_cam_w_fifo                ;// (input) 
    wire                                wr_clk_cam_w_fifo             ;// (input) 
    wire                                wr_en_cam_w_fifo              ;// (input) 
    wire                 [FIFO_USER_DATA_WIDTH-1: 0]din_cam_w_fifo    ;// (input) 
    wire                                full_cam_w_fifo               ;// (output)暂时未使用 
    wire [W_CAM_FIFO_WR_DATA_CNT_WIDTH-1: 0]wr_data_count_cam_w_fifo  ;// (output)暂时未使用  
    wire                                wr_rst_busy_cam_w_fifo        ;// (output)暂时未使用 

    // ==================== 写地址通道 ====================

    wire                 [AXI_ID_WIDTH-1: 0]m_axi_cam_awid         ;// (output)
    wire                 [AXI_ADDR_WIDTH-1: 0]m_axi_cam_awaddr     ;// (output)
    wire                                m_axi_cam_awvalid          ;// (output)

    // ==================== 写数据通道 ====================

    wire                 [AXI_DATA_WIDTH-1: 0]m_axi_cam_wdata      ;// (output)
    wire                                m_axi_cam_wlast            ;// (output)
    wire                                m_axi_cam_wvalid           ;// (output)

    // ==================== 写响应通道 ====================    

    wire                                m_axi_cam_bready           ;// (output)
    
    // ==================== 对外输出的写完状态信号 ====================    
    wire                                camera_w_done              ;// (output)
    wire                                w_module_ddr3_w_req        ;// (output)
    wire                                camera_w_start_pulse       ;// (input)
    wire                                camera_burst_done          ;// (output)
    // ==================== 缓存切换逻辑信号 =========================
    wire                                w_buf                      ;// (input)// 0=写帧A, 1=写帧B默认写A
    wire                                w_switch_pulse             ;// (input)// 地址切换脉冲，与指针一同出现
//=========================P模块顶层连线--------------------------------------------------------------------

    // ==================== 写地址通道 ====================

    wire                 [AXI_ID_WIDTH-1: 0]m_axi_p_awid           ;// (output)
    wire                 [AXI_ADDR_WIDTH-1: 0]m_axi_p_awaddr       ;// (output)
    wire                                m_axi_p_awvalid            ;// (output)

    // ==================== 写数据通道 ====================

    wire                 [AXI_DATA_WIDTH-1: 0]m_axi_p_wdata        ;// (output)
    wire                                m_axi_p_wlast              ;// (output)
    wire                                m_axi_p_wvalid             ;// (output)

    // ==================== 写响应通道 ====================    
    wire                                m_axi_p_bready             ;// (output)
    // ==================== 读地址通道 ====================  

    wire                 [AXI_ID_WIDTH-1: 0]m_axi_p_arid           ;// (output)
    wire                 [AXI_ADDR_WIDTH-1: 0]m_axi_p_araddr       ;// (output)
    wire                                m_axi_p_arvalid            ;// (output)

    // ==================== 读数据通道 ====================  

    wire                                m_axi_p_rready             ;// (output)

    // ==================== 缓存控制信号 ==================== 
    wire                                p_done                     ;// (output)
    wire                                p_idle                     ;// (output)
    wire                                p_w_done                   ;// (output)// 从F-A输出的写完一帧信号
    wire                                p_r_done                   ;// (output)// 从A-F输出的读完一帧信号
    wire                                p_r_rdenable               ;// (input)// 必须等摄像头写完一帧后才能启动P读
    wire                                p_module_ddr3_w_req        ;// (output)
    wire                                p_w_start_pulse            ;// (input)
    wire                                p_module_ddr3_r_req        ;// (output)
    wire                                p_r_start_pulse            ;// (input)
    wire                                p_w_burst_done             ;// (output)
    wire                                p_r_burst_done             ;// (output)
    // ==================== 缓存切换脉冲和指针输入 ====================
    wire                                p_rd_buf                   ;// (input)// 当前从哪个读
    wire                                p_wr_buf                   ;// (input)// 当前往哪个写
    wire                                p_switch_pulse             ;// (input)// 与p_rd/p_wr同拍变化(P模块同一时间占用两个buf)
//=========================R模块顶层连线--------------------------------------------------------------------

    // ==================== 读FIFO用户读取侧接口 ==========
    wire                                rst_hdmi_r_fifo            ;// (input)
    wire                                rdfifo_clk                 ;// (input)
    wire                                rd_en_hdmi_r_fifo          ;// (input)
    wire              [FIFO_USER_DATA_WIDTH-1: 0]dout_hdmi_r_fifo  ;// (output)
    wire                                empty_hdmi_r_fifo               ;// (output)暂时未使用
    wire [R_HDMI_FIFO_RD_DATA_CNT_WIDTH-1: 0]rd_data_count_hdmi_r_fifo  ;// (output)暂时未使用
    wire                                rd_rst_busy_hdmi_r_fifo         ;// (output)暂时未使用

    // ==================== 读地址通道 ====================  
    wire                 [AXI_ID_WIDTH-1: 0]m_axi_hdmi_arid        ;// (output)
    wire                 [AXI_ADDR_WIDTH-1: 0]m_axi_hdmi_araddr    ;// (output)
    wire                                m_axi_hdmi_arvalid         ;// (output)

    // ==================== 读数据通道 ==================== 

    wire                                m_axi_hdmi_rready          ;// (output)
    //==================== 实验接口 ====================
    wire                                r_done                     ;// (output)
    wire                                hdmi_rd_enable             ;// (input)
    wire                                r_module_ddr3_r_req        ;// (output)
    wire                                hdmi_r_start_pulse         ;// (input)
    wire                                hdmi_burst_done            ;// (output)
    // ==================== 缓存切换逻辑信号 ====================
    wire                                r_buf                      ;// (input)// 0=读帧A, 1=读帧B,默认读B
    wire                                r_addr_switch_pulse        ;// (input)// 地址切换脉冲，与指针一同出现
//===============================================================================================================
//逻辑输出
//////////////////////////////////////////////////////////////////////////////////
//=================================================
//指示系统状态
assign state_led={camera_init_done,camera_init_fail,ddr3_init_done,main_pll_locked,dvi_pll_locked};

//=================================================
//将读fifo中读出的RGB565数据转化为rgb888数据，送入显示模块
wire [23:0]disp_data;//待显示的拼接RGB88信号
assign disp_data = {dout_hdmi_r_fifo[15:11],3'd0,dout_hdmi_r_fifo[10:5],2'd0,dout_hdmi_r_fifo[4:0],3'd0};
//assign disp_data =rd_frame_sel?24'hff0000:24'h0000ff;
//=================================================
//打开hdmi开关
assign hdmi1_oe = 1'b1;

//=================================================
//将pll输出的24m时钟与xclk连接
assign camera_xclk = camera_xclk_24M;



//==================================================================================================
//测试图像生成器（定位错位用）修改866行的内容以启用
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


//=================================================
    reg                                 p_w_busy                   ;
    reg                                 camera_w_busy              ;
    reg                                 p_r_busy                   ;
    reg                                 hdmi_r_busy                ;

    always @(posedge mig_ui_clk or posedge ui_clk_sync_rst)
        begin
            if(ui_clk_sync_rst)
                p_w_busy<=0;
            else if(p_w_burst_done)
                p_w_busy<=0;                                            
            else if(p_w_start_pulse)
                p_w_busy<=1; 
            else
                p_w_busy<=p_w_busy;
        end
    always @(posedge mig_ui_clk or posedge ui_clk_sync_rst)
        begin
            if(ui_clk_sync_rst)
                camera_w_busy<=0;
            else if(camera_burst_done)
                camera_w_busy<=0;                                            
            else if(camera_w_start_pulse)
                camera_w_busy<=1; 
            else
                camera_w_busy<=camera_w_busy;
        end
    always @(posedge mig_ui_clk or posedge ui_clk_sync_rst)
        begin
            if(ui_clk_sync_rst)
                p_r_busy<=0;
            else if(p_r_burst_done)
                p_r_busy<=0;                                            
            else if(p_r_start_pulse)
                p_r_busy<=1; 
            else
                p_r_busy<=p_r_busy;
        end
    always @(posedge mig_ui_clk or posedge ui_clk_sync_rst)
        begin
            if(ui_clk_sync_rst)
                hdmi_r_busy<=0;
            else if(hdmi_burst_done)
                hdmi_r_busy<=0;                                            
            else if(hdmi_r_start_pulse)
                hdmi_r_busy<=1; 
            else
                hdmi_r_busy<=hdmi_r_busy;
        end

//=================================================axi4_w_channel_switch
always @(posedge mig_ui_clk or posedge ui_clk_sync_rst) begin
    if (ui_clk_sync_rst) begin
        m_axi_awid_dynamic     <= {AXI_ID_WIDTH{1'b0}};
        m_axi_awaddr_dynamic   <= {AXI_ADDR_WIDTH{1'b0}};
        m_axi_awvalid_dynamic  <= 1'b0;
        m_axi_wdata_dynamic    <= {AXI_DATA_WIDTH{1'b0}};
        m_axi_wlast_dynamic    <= 1'b0;
        m_axi_wvalid_dynamic   <= 1'b0;
        s_axi_bready_dynamic   <= 1'b0;
    end
    else if(camera_w_busy) begin
        m_axi_awid_dynamic     <= m_axi_cam_awid;
        m_axi_awaddr_dynamic   <= m_axi_cam_awaddr;
        m_axi_awvalid_dynamic  <= m_axi_cam_awvalid;
        m_axi_wdata_dynamic    <= m_axi_cam_wdata;
        m_axi_wlast_dynamic    <= m_axi_cam_wlast;
        m_axi_wvalid_dynamic   <= m_axi_cam_wvalid;
        s_axi_bready_dynamic   <= m_axi_cam_bready;
    end
    else if(p_w_busy) begin
        m_axi_awid_dynamic     <= m_axi_p_awid;
        m_axi_awaddr_dynamic   <= m_axi_p_awaddr;
        m_axi_awvalid_dynamic  <= m_axi_p_awvalid;
        m_axi_wdata_dynamic    <= m_axi_p_wdata;
        m_axi_wlast_dynamic    <= m_axi_p_wlast;
        m_axi_wvalid_dynamic   <= m_axi_p_wvalid;
        s_axi_bready_dynamic   <= m_axi_p_bready;
    end
    else begin
        m_axi_awid_dynamic     <= {AXI_ID_WIDTH{1'b0}};
        m_axi_awaddr_dynamic   <= {AXI_ADDR_WIDTH{1'b0}};
        m_axi_awvalid_dynamic  <= 1'b0;
        m_axi_wdata_dynamic    <= {AXI_DATA_WIDTH{1'b0}};
        m_axi_wlast_dynamic    <= 1'b0;
        m_axi_wvalid_dynamic   <= 1'b0;
        s_axi_bready_dynamic   <= s_axi_bready_dynamic;
    end
end


//=================================================axi4_r_channel_switch
always @(posedge mig_ui_clk or posedge ui_clk_sync_rst) begin
    if (ui_clk_sync_rst) begin
        m_axi_arid_dynamic     <= {AXI_ID_WIDTH{1'b0}};
        m_axi_araddr_dynamic   <= {AXI_ADDR_WIDTH{1'b0}};
        m_axi_arvalid_dynamic  <= 1'b0;
        m_axi_rready_dynamic   <= 1'b0;
    end
    else if(p_r_busy) begin
        m_axi_arid_dynamic     <= m_axi_p_arid;
        m_axi_araddr_dynamic   <= m_axi_p_araddr;
        m_axi_arvalid_dynamic  <= m_axi_p_arvalid;
        m_axi_rready_dynamic   <= m_axi_p_rready;
    end
    else if(hdmi_r_busy) begin
        m_axi_arid_dynamic     <= m_axi_hdmi_arid;
        m_axi_araddr_dynamic   <= m_axi_hdmi_araddr;
        m_axi_arvalid_dynamic  <= m_axi_hdmi_arvalid;
        m_axi_rready_dynamic   <= m_axi_hdmi_rready;
    end
    else begin
        m_axi_arid_dynamic     <= {AXI_ID_WIDTH{1'b0}};
        m_axi_araddr_dynamic   <= {AXI_ADDR_WIDTH{1'b0}};
        m_axi_arvalid_dynamic  <= 1'b0;
        m_axi_rready_dynamic   <= m_axi_rready_dynamic;
    end
end

//=================================================
//将突发启动信号打一拍作为真正的启动信号，与busy对齐时序，防止仲裁产生竞争（这是一个大bug）
    reg                                 p_w_start_pulse_reg        ;
    reg                                 p_r_start_pulse_reg        ;
    reg                                 camera_w_start_pulse_reg   ;
    reg                                 hdmi_r_start_pulse_reg     ;

    always @(posedge mig_ui_clk or posedge ui_clk_sync_rst)
        begin
            if(ui_clk_sync_rst)begin
                p_w_start_pulse_reg     <=0;
                p_r_start_pulse_reg     <=0;
                camera_w_start_pulse_reg<=0;
                hdmi_r_start_pulse_reg  <=0;              
            end

            else begin
                p_w_start_pulse_reg     <=p_w_start_pulse;     
                p_r_start_pulse_reg     <=p_r_start_pulse;    
                camera_w_start_pulse_reg<=camera_w_start_pulse;
                hdmi_r_start_pulse_reg  <=hdmi_r_start_pulse;                   
            end

        end
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

    .camera_w_done                      (camera_w_done_hdmi_clk)
);

//////////////////////////////////////////  四缓冲图像切换模块      //////////////////////////////////////////////

quad_buffer_ctrl u_quad_buffer_ctrl(
// ==================== 全局信号 ====================
    .clk                                (mig_ui_clk                ),// (input)// ui_clk
    .reset                              (ui_clk_sync_rst           ),// (input)// ui_clk_sync_rst
// ==================== 完成信号输入 ====================
    .w_done                             (camera_w_done             ),// (input)// 摄像头写完一帧
    .p_idle                             (p_idle                    ),// (input)// P空闲，可接收新任务
    .p_done                             (p_done                    ),// (input)// Sobel处理完一帧
    .r_done                             (r_done                    ),// (input)// HDMI读完一帧
// ==================== 指针输出 ====================
    .w_buf                              (w_buf                     ), // (output)// 当前写哪个in_buf(0~1)
    .p_rd_buf                           (p_rd_buf                  ), // (output)// 当前从哪个in_buf读
    .p_wr_buf                           (p_wr_buf                  ), // (output)// 当前往哪个proc_buf写
    .r_buf                              (r_buf                     ), // (output)// 当前从哪个proc_buf读
// ==================== 切换脉冲输出 ====================
    .w_switch_pulse                     (w_switch_pulse            ), // (output)// 与w_buf同拍变化，持续1个clk
    .p_switch_pulse                     (p_switch_pulse            ), // (output)// 与p_rd/p_wr同拍变化
    .r_switch_pulse                     (r_addr_switch_pulse       ) // (output)// 与r_buf同拍变化
);


//////////////////////////////////////////   写通道仲裁模块       //////////////////////////////////////////////

axi4_w_arbitration u_axi4_w_arbitration(
// ==================== 全局信号 ====================
    .ui_clk                             (mig_ui_clk                ),// (input)
    .reset                              (ui_clk_sync_rst           ),// (input)
// ==================== P模块写 ====================
    .p_w_req                            (p_module_ddr3_w_req       ),// (input)// 电平req
    .p_w_busy                           (p_w_busy                  ),// (input)// 发送模块忙指示
// ==================== camera模块写 ====================
    .camera_w_req                       (w_module_ddr3_w_req       ),// (input)// 电平req
    .camera_w_busy                      (camera_w_busy             ),// (input)// 发送模块忙指示
// ===================  最终仲裁逻辑信号输出 ====================
    .p_w_start_pulse                    (p_w_start_pulse           ),// (output)
    .camera_w_start_pulse               (camera_w_start_pulse      ) // (output)
);

//////////////////////////////////////////   读通道仲裁模块       //////////////////////////////////////////////

axi4_r_arbitration u_axi4_r_arbitration(
// ==================== 全局信号 ====================
    .ui_clk                             (mig_ui_clk                ),// (input)
    .reset                              (ui_clk_sync_rst           ),// (input)
// ==================== P模块读 ====================
    .p_r_req                            (p_module_ddr3_r_req       ),// (input)// 电平req
    .p_r_busy                           (p_r_busy                  ),// (input)// 发送模块忙指示
// ==================== HDMI模块读 ====================
    .hdmi_r_req                         (r_module_ddr3_r_req       ),// (input)// 电平req
    .hdmi_r_busy                        (hdmi_r_busy               ),// (input)// 发送模块忙指示
// ===================  最终仲裁逻辑信号输出 ====================
    .p_r_start_pulse                    (p_r_start_pulse           ),// (output)
    .hdmi_r_start_pulse                 (hdmi_r_start_pulse        ) // (output)
);

//////////////////////////////////////////   W模块       //////////////////////////////////////////////

w_module_ctrl#(
    .FIFO_USER_DATA_WIDTH               (FIFO_USER_DATA_WIDTH        ),
    .W_CAM_FIFO_RD_DATA_CNT_WIDTH       (W_CAM_FIFO_RD_DATA_CNT_WIDTH),
    .W_CAM_FIFO_WR_DATA_CNT_WIDTH       (W_CAM_FIFO_WR_DATA_CNT_WIDTH),
    .IN_BUF_0                           (IN_BUF_0                    ),
    .IN_BUF_1                           (IN_BUF_1                    ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH              ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH              ),
    .AXI_BURST_LEN                      (AXI_BURST_LEN               ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH                ),
    .CAM_AXI_ID                         (CAM_AXI_ID                  ),
    .AXI_AWBURST_INCR                   (AXI_AWBURST_INCR            ),
    .AXI_AWLOCK_NORMAL                  (AXI_AWLOCK_NORMAL           ),
    .AXI_AWCACHE_DEVICE_NON_BUF         (AXI_AWCACHE_DEVICE_NON_BUF  ),
    .AXI_AWPROT_UNPRIV_SECURE           (AXI_AWPROT_UNPRIV_SECURE    ),
    .AXI_AWQOS_DEFAULT                  (AXI_AWQOS_DEFAULT           ),
    .AXI_AWREGION_DEFAULT               (AXI_AWREGION_DEFAULT        ),
    .AXI_BRESP_OKAY                     (AXI_BRESP_OKAY              ),
    .AXI_WSTRB_ALL_VALID                (AXI_WSTRB_ALL_VALID         ),
    .AXI_RESET_POLARITY                 (AXI_RESET_POLARITY          ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH                 ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT                ) 
)
 u_w_module_ctrl(

    .clk                                (mig_ui_clk                ),// (input)// ui_clk
    .reset                              (ui_clk_sync_rst           ),// (input)// ui_clk_sync_rst
// ==================== 写FIFO用户写入侧接口 ====================
    .rst_cam_w_fifo                     (frame_rst_state           ),// (input)
    .wr_clk_cam_w_fifo                  (PCLK_bufg                 ),// (input)
    .wr_en_cam_w_fifo                   (pixel_data_valid          ),// (input)
    .din_cam_w_fifo                     (pixel_data                ),// (input)
//    .wr_en_cam_w_fifo                  (test_pixel_valid          ),// input 测试数据输入端口
//    .din_cam_w_fifo                    (test_pixel_data           ),// input 测试数据输入端口
    .full_cam_w_fifo                    (full_cam_w_fifo           ),// (output)
    .wr_data_count_cam_w_fifo           (wr_data_count_cam_w_fifo  ),// (output)
    .wr_rst_busy_cam_w_fifo             (wr_rst_busy_cam_w_fifo    ),// (output)
// ==================== 写地址通道 ====================
    .m_axi_cam_awid                     (m_axi_cam_awid            ), // (output)
    .m_axi_cam_awaddr                   (m_axi_cam_awaddr          ), // (output)
    .m_axi_cam_awvalid                  (m_axi_cam_awvalid         ), // (output)
    .m_axi_cam_awready                  (m_axi_awready_dynamic     ), // (input)
// ==================== 写数据通道 ====================
    .m_axi_cam_wdata                    (m_axi_cam_wdata           ), // (output)
    .m_axi_cam_wlast                    (m_axi_cam_wlast           ), // (output)
    .m_axi_cam_wvalid                   (m_axi_cam_wvalid          ), // (output)
    .m_axi_cam_wready                   (m_axi_wready_dynamic      ), // (input)
// ==================== 写响应通道 ====================
    .m_axi_cam_bid                      (m_axi_bid_dynamic         ), // (input)
    .m_axi_cam_bresp                    (m_axi_bresp_dynamic       ), // (input)
    .m_axi_cam_bvalid                   (m_axi_bvalid_dynamic      ), // (input)
    .m_axi_cam_bready                   (m_axi_cam_bready          ), // (output)
// ==================== 对外输出的写完状态信号 ====================
    .camera_w_done                      (camera_w_done             ), // (output)
    .w_module_ddr3_w_req                (w_module_ddr3_w_req       ), // (output)
    .camera_w_start_pulse               (camera_w_start_pulse_reg  ), // (input)
    .camera_burst_done                  (camera_burst_done         ),// (output)
// ==================== 缓存切换逻辑信号 =========================
    .w_buf                              (w_buf                     ), // (input)// 0=写帧A, 1=写帧B默认写A
    .w_switch_pulse                     (w_switch_pulse            ) // (input)// 地址切换脉冲，与指针一同出现
);


//////////////////////////////////////////   P模块       //////////////////////////////////////////////

p_module_ctrl#(
    .FIFO_USER_DATA_WIDTH               (FIFO_USER_DATA_WIDTH      ),
    .R_FIFO_RD_DATA_CNT_WIDTH           (R_FIFO_RD_DATA_CNT_WIDTH  ),
    .R_FIFO_WR_DATA_CNT_WIDTH           (R_FIFO_WR_DATA_CNT_WIDTH  ),
    .W_FIFO_RD_DATA_CNT_WIDTH           (W_FIFO_RD_DATA_CNT_WIDTH  ),
    .W_FIFO_WR_DATA_CNT_WIDTH           (W_FIFO_WR_DATA_CNT_WIDTH  ),
    .IN_BUF_0                           (IN_BUF_0                  ),
    .IN_BUF_1                           (IN_BUF_1                  ),
    .PROC_BUF_0                         (PROC_BUF_0                ),
    .PROC_BUF_1                         (PROC_BUF_1                ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH            ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH            ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH              ),
    .PROC_P_AXI_ID                      (PROC_P_AXI_ID             ),
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
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
    .GRAY_PIC_DATA_WIDTH                (GRAY_PIC_DATA_WIDTH       ),
    .RGB_PIC_DATA_WIDTH                 (RGB_PIC_DATA_WIDTH        ),
    .PROC_TYPE                          (PROC_TYPE                 ),
    .THRESHOLD                          (THRESHOLD                 ),
    .LINE_LEN                           (LINE_LEN                  ) 
)
 u_p_module_ctrl(

    .clk                                (mig_ui_clk                ),// (input)// 处理时钟
    .reset                              (ui_clk_sync_rst           ),// (input)// 高有效复位
    .p_bypass                           (1                         ),// (input)//用以旁路P模块的图像处理功能，1时旁路
// ==================== 写地址通道 ====================
    .m_axi_p_awid                       (m_axi_p_awid              ),// (output)
    .m_axi_p_awaddr                     (m_axi_p_awaddr            ),// (output)
    .m_axi_p_awvalid                    (m_axi_p_awvalid           ),// (output)
    .m_axi_p_awready                    (m_axi_awready_dynamic     ),// (input)
// ==================== 写数据通道 ====================
    .m_axi_p_wdata                      (m_axi_p_wdata             ),// (output)
    .m_axi_p_wlast                      (m_axi_p_wlast             ),// (output)
    .m_axi_p_wvalid                     (m_axi_p_wvalid            ),// (output)
    .m_axi_p_wready                     (m_axi_wready_dynamic      ),// (input)
// ==================== 写响应通道 ====================
    .m_axi_p_bid                        (m_axi_bid_dynamic         ),// (input)
    .m_axi_p_bresp                      (m_axi_bresp_dynamic       ),// (input)
    .m_axi_p_bvalid                     (m_axi_bvalid_dynamic      ),// (input)
    .m_axi_p_bready                     (m_axi_p_bready            ),// (output)
// ==================== 读地址通道 ====================
    .m_axi_p_arid                       (m_axi_p_arid              ),// (output)
    .m_axi_p_araddr                     (m_axi_p_araddr            ),// (output)
    .m_axi_p_arvalid                    (m_axi_p_arvalid           ),// (output)
    .m_axi_p_arready                    (m_axi_arready_dynamic     ),// (input)
// ==================== 读数据通道 ====================
    .m_axi_p_rid                        (m_axi_rid_dynamic         ),// (input)
    .m_axi_p_rdata                      (m_axi_rdata_dynamic       ),// (input)
    .m_axi_p_rresp                      (m_axi_rresp_dynamic       ),// (input)
    .m_axi_p_rlast                      (m_axi_rlast_dynamic       ),// (input)
    .m_axi_p_rvalid                     (m_axi_rvalid_dynamic      ),// (input)
    .m_axi_p_rready                     (m_axi_p_rready            ),// (output)
// ==================== 缓存控制信号 ====================
    .p_done                             (p_done                    ),// (output)
    .p_idle                             (p_idle                    ),// (output)
    .p_w_done                           (p_w_done                  ),// (output)// 从F-A输出的写完一帧信号
    .p_r_done                           (p_r_done                  ),// (output)// 从A-F输出的读完一帧信号
    .p_r_rdenable                       (camera_w_done             ),// (input)// 必须等摄像头写完一帧后才能启动P读
    .p_module_ddr3_w_req                (p_module_ddr3_w_req       ),// (output)
    .p_w_start_pulse                    (p_w_start_pulse_reg       ),// (input)
    .p_module_ddr3_r_req                (p_module_ddr3_r_req       ),// (output)
    .p_r_start_pulse                    (p_r_start_pulse_reg       ),// (input)
    .p_w_burst_done                     (p_w_burst_done            ),// (output)
    .p_r_burst_done                     (p_r_burst_done            ),// (output)
// ==================== 缓存切换脉冲和指针输入 ====================
    .p_rd_buf                           (p_rd_buf                  ),// (input)// 当前从哪个读
    .p_wr_buf                           (p_wr_buf                  ),// (input)// 当前往哪个写
    .p_switch_pulse                     (p_switch_pulse            ) // (input)// 与p_rd/p_wr同拍变化(P模块同一时间占用两个buf)
);


//////////////////////////////////////////   R模块       //////////////////////////////////////////////


r_module_ctrl#(
    .FIFO_USER_DATA_WIDTH               (FIFO_USER_DATA_WIDTH         ),
    .R_HDMI_FIFO_RD_DATA_CNT_WIDTH      (R_HDMI_FIFO_RD_DATA_CNT_WIDTH),
    .R_HDMI_FIFO_WR_DATA_CNT_WIDTH      (R_HDMI_FIFO_WR_DATA_CNT_WIDTH),
    .PROC_BUF_0                         (PROC_BUF_0                   ),
    .PROC_BUF_1                         (PROC_BUF_1                   ),
    .AXI_DATA_WIDTH                     (AXI_DATA_WIDTH               ),
    .AXI_ADDR_WIDTH                     (AXI_ADDR_WIDTH               ),
    .AXI_BURST_LEN                      (AXI_BURST_LEN                ),
    .AXI_ID_WIDTH                       (AXI_ID_WIDTH                 ),
    .HDMI_AXI_ID                        (HDMI_AXI_ID                  ),
    .AXI_ARBURST_INCR                   (AXI_ARBURST_INCR             ),
    .AXI_ARLOCK_NORMAL                  (AXI_ARLOCK_NORMAL            ),
    .AXI_ARCACHE_DEVICE_NON_BUF         (AXI_ARCACHE_DEVICE_NON_BUF   ),
    .AXI_ARPROT_UNPRIV_SECURE           (AXI_ARPROT_UNPRIV_SECURE     ),
    .AXI_ARQOS_DEFAULT                  (AXI_ARQOS_DEFAULT            ),
    .AXI_ARREGION_DEFAULT               (AXI_ARREGION_DEFAULT         ),
    .AXI_RRESP_OKAY                     (AXI_RRESP_OKAY               ),
    .AXI_RESET_POLARITY                 (AXI_RESET_POLARITY           ),
    .IMAGE_WIDTH                        (IMAGE_WIDTH                  ),
    .IMAGE_HEIGHT                       (IMAGE_HEIGHT                 ) 
)
 u_r_module_ctrl(
    .clk                                (mig_ui_clk                ),// (input)
    .reset                              (ui_clk_sync_rst           ),// (input)
// ==================== 读FIFO用户读取侧接口 ==========
    .rst_hdmi_r_fifo                    (frame_rst_state           ),// (input)
    .rdfifo_clk                         (pixel_clk_74m             ),// (input)
    .rd_en_hdmi_r_fifo                  (disp_data_req             ), // (input)
    .dout_hdmi_r_fifo                   (dout_hdmi_r_fifo          ), // (output)
    .empty_hdmi_r_fifo                  (empty_hdmi_r_fifo         ), // (output)
    .rd_data_count_hdmi_r_fifo          (rd_data_count_hdmi_r_fifo ), // (output)
    .rd_rst_busy_hdmi_r_fifo            (rd_rst_busy_hdmi_r_fifo   ), // (output)
// ==================== 读地址通道 ====================
    .m_axi_hdmi_arid                    (m_axi_hdmi_arid           ), // (output)
    .m_axi_hdmi_araddr                  (m_axi_hdmi_araddr         ), // (output)
    .m_axi_hdmi_arvalid                 (m_axi_hdmi_arvalid        ), // (output)
    .m_axi_hdmi_arready                 (m_axi_arready_dynamic     ), // (input)
// ==================== 读数据通道 ====================
    .m_axi_hdmi_rid                     (m_axi_rid_dynamic         ), // (input)
    .m_axi_hdmi_rdata                   (m_axi_rdata_dynamic       ), // (input)
    .m_axi_hdmi_rresp                   (m_axi_rresp_dynamic       ), // (input)
    .m_axi_hdmi_rlast                   (m_axi_rlast_dynamic       ), // (input)
    .m_axi_hdmi_rvalid                  (m_axi_rvalid_dynamic      ), // (input)
    .m_axi_hdmi_rready                  (m_axi_hdmi_rready         ), // (output)
//==================== 实验接口 ====================
    .r_done                             (r_done                    ),// (output)
    .hdmi_rd_enable                     (p_w_done                  ),// (input)
    .r_module_ddr3_r_req                (r_module_ddr3_r_req       ),// (output)
    .hdmi_r_start_pulse                 (hdmi_r_start_pulse_reg    ),// (input)
    .hdmi_burst_done                    (hdmi_burst_done           ),// (output)
// ==================== 缓存切换逻辑信号 ====================
    .r_buf                              (r_buf                     ), // (input)// 0=读帧A, 1=读帧B,默认读B
    .r_addr_switch_pulse                (r_addr_switch_pulse       )  // (input)// 地址切换脉冲，与指针一同出现
);


//////////////////////////////////////////    MIG控制器       ///////////////////////////////////////////////////////////////////////////////

mig_7series_0 inst_mig_7series_0 (

    // DDR3接口
    .ddr3_addr                          (ddr3_addr                 ),// output [13:0]		ddr3_addr
    .ddr3_ba                            (ddr3_ba                   ),// output [2:0]		ddr3_ba
    .ddr3_cas_n                         (ddr3_cas_n                ),// output			    ddr3_cas_n
    .ddr3_ck_n                          (ddr3_ck_n                 ),// output [0:0]		ddr3_ck_n
    .ddr3_ck_p                          (ddr3_ck_p                 ),// output [0:0]		ddr3_ck_p
    .ddr3_cke                           (ddr3_cke                  ),// output [0:0]		ddr3_cke
    .ddr3_ras_n                         (ddr3_ras_n                ),// output			    ddr3_ras_n
    .ddr3_reset_n                       (ddr3_reset_n              ),// output			    ddr3_reset_n
    .ddr3_we_n                          (ddr3_we_n                 ),// output			    ddr3_we_n
    .ddr3_dq                            (ddr3_dq                   ),// inout [15:0]		ddr3_dq
    .ddr3_dqs_n                         (ddr3_dqs_n                ),// inout [1:0]		    ddr3_dqs_n
    .ddr3_dqs_p                         (ddr3_dqs_p                ),// inout [1:0]		    ddr3_dqs_p
    .init_calib_complete                (init_calib_complete       ),// output			    init_calib_complete
    .ddr3_cs_n                          (ddr3_cs_n                 ),// output [0:0]		ddr3_cs_n
    .ddr3_dm                            (ddr3_dm                   ),// output [1:0]		ddr3_dm
    .ddr3_odt                           (ddr3_odt                  ),// output [0:0]		ddr3_odt

    //应用层接口

    .ui_clk                             (mig_ui_clk                ),// output			    ui_clk
    .ui_clk_sync_rst                    (ui_clk_sync_rst           ),// output			    ui_clk_sync_rst
    .mmcm_locked                        (mmcm_locked               ),// output			    mmcm_locked
    .aresetn                            (init_calib_complete&&(~ui_clk_sync_rst)),// input	aresetn
   
    //不懂的app信号，先不管，记得前三个带req的写0，后三个不连就行了
    .app_sr_req                         (0                         ),// input			    app_sr_req
    .app_ref_req                        (0                         ),// input			    app_ref_req
    .app_zq_req                         (0                         ),// input			    app_zq_req
    .app_sr_active                      (                          ),// output			    app_sr_active
    .app_ref_ack                        (                          ),// output			    app_ref_ack
    .app_zq_ack                         (                          ),// output			    app_zq_ack

    // Slave 写地址通道
    .s_axi_awid                         (m_axi_awid_dynamic        ),// input [3:0]			s_axi_awid
    .s_axi_awaddr                       (m_axi_awaddr_dynamic      ),// input [27:0]		s_axi_awaddr
    .s_axi_awlen                        (AXI_BURST_LEN             ),// input [7:0]			s_axi_awlen
    .s_axi_awsize                       (AXI_SIZE                  ),// input [2:0]			s_axi_awsize
    .s_axi_awburst                      (AXI_AWBURST_INCR          ),// input [1:0]			s_axi_awburst
    .s_axi_awlock                       (AXI_AWLOCK_NORMAL         ),// input [0:0]			s_axi_awlock
    .s_axi_awcache                      (AXI_AWCACHE_DEVICE_NON_BUF),// input [3:0]			s_axi_awcache
    .s_axi_awprot                       (AXI_AWPROT_UNPRIV_SECURE  ),// input [2:0]			s_axi_awprot
    .s_axi_awqos                        (AXI_AWQOS_DEFAULT         ),// input [3:0]			s_axi_awqos
    .s_axi_awvalid                      (m_axi_awvalid_dynamic     ),// input			    s_axi_awvalid
    .s_axi_awready                      (m_axi_awready_dynamic     ),// output			    s_axi_awready
    // Slave 写数据通道
    .s_axi_wdata                        (m_axi_wdata_dynamic       ),// input [127:0]	    s_axi_wdata
    .s_axi_wstrb                        ({(AXI_DATA_WIDTH/8){AXI_WSTRB_ALL_VALID}}),// input [15:0]	    s_axi_wstrb
    .s_axi_wlast                        (m_axi_wlast_dynamic       ),// input			    s_axi_wlast
    .s_axi_wvalid                       (m_axi_wvalid_dynamic      ),// input			    s_axi_wvalid
    .s_axi_wready                       (m_axi_wready_dynamic      ),// output			    s_axi_wready
    // Slave 写响应通道
    .s_axi_bid                          (m_axi_bid_dynamic         ),// output [3:0]		s_axi_bid
    .s_axi_bresp                        (m_axi_bresp_dynamic       ),// output [1:0]		s_axi_bresp
    .s_axi_bvalid                       (m_axi_bvalid_dynamic      ),// output			    s_axi_bvalid
    .s_axi_bready                       (s_axi_bready_dynamic      ),// input			    s_axi_bready
    // Slave 读地址通道
    .s_axi_arid                         (m_axi_arid_dynamic        ),// input [3:0]			s_axi_arid
    .s_axi_araddr                       (m_axi_araddr_dynamic      ),// input [27:0]		s_axi_araddr
    .s_axi_arlen                        (AXI_BURST_LEN             ),// input [7:0]			s_axi_arlen
    .s_axi_arsize                       (AXI_SIZE                  ),// input [2:0]			s_axi_arsize
    .s_axi_arburst                      (AXI_ARBURST_INCR          ),// input [1:0]			s_axi_arburst
    .s_axi_arlock                       (AXI_ARLOCK_NORMAL         ),// input [0:0]			s_axi_arlock
    .s_axi_arcache                      (AXI_ARCACHE_DEVICE_NON_BUF),// input [3:0]			s_axi_arcache
    .s_axi_arprot                       (AXI_ARPROT_UNPRIV_SECURE  ),// input [2:0]			s_axi_arprot
    .s_axi_arqos                        (AXI_ARQOS_DEFAULT         ),// input [3:0]			s_axi_arqos
    .s_axi_arvalid                      (m_axi_arvalid_dynamic     ),// input			    s_axi_arvalid
    .s_axi_arready                      (m_axi_arready_dynamic     ),// output			    s_axi_arready
    // Slave 读数据通道
    .s_axi_rid                          (m_axi_rid_dynamic         ),// output [3:0]		s_axi_rid
    .s_axi_rdata                        (m_axi_rdata_dynamic       ),// output [127:0]		s_axi_rdata
    .s_axi_rresp                        (m_axi_rresp_dynamic       ),// output [1:0]		s_axi_rresp
    .s_axi_rlast                        (m_axi_rlast_dynamic       ),// output			    s_axi_rlast
    .s_axi_rvalid                       (m_axi_rvalid_dynamic      ),// output			    s_axi_rvalid
    .s_axi_rready                       (m_axi_rready_dynamic      ),// input			    s_axi_rready
    // System Clock Ports
    .sys_clk_i                          (ddr3_clk_200m             ),
    .sys_rst                            (main_pll_locked           ) // input               sys_rst
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



*/