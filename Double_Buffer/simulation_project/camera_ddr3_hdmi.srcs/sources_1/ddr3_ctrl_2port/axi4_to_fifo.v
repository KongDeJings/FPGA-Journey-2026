//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/29 10:45:59
// Design Name: 
// Module Name: axi4_fifo_adapter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description:  
//////////////////////////////////////////////////////////////////////////////////


module axi4_to_fifo
#(
    // ==================== 地址与数据参数 ====================
    parameter                           AXI_BYTE_ADDR_BEGIN         = 0                    ,//旧逻辑残留，已经无用
    parameter                           AXI_BYTE_ADDR_END           = 32768-1              ,//旧逻辑残留，已经无用

    parameter                           BUF_A_BEGIN                 = 32'h0100_0000        ,//缓存A基地址
    parameter                           BUF_B_BEGIN                 = 32'h0120_0000        ,//缓存B基地址
    parameter                           AXI_DATA_WIDTH              = 128                  ,
    parameter                           AXI_ADDR_WIDTH              = 32                   ,
    parameter                           AXI_ID_WIDTH                = 4                    ,
    parameter                           AXI_ID                      = 0                    ,
    parameter                           AXI_BURST_LEN               = 31                   ,
    parameter                           FIFO_ADDR_WIDTH             = 8                    ,

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

    // ==================== 写FIFO用户写入侧接口 ====================

    output reg                          fifo_wrreq                 ,
    output reg           [AXI_DATA_WIDTH-1: 0]fifo_wrdata          ,
    input                               fifo_alfull                ,
    input                [FIFO_ADDR_WIDTH-1: 0]fifo_wr_cnt         ,
    input                               fifo_rst_busy              ,

    // ==================== 读地址通道 ====================  
    output         [AXI_ID_WIDTH-1: 0]  m_axi_arid                 ,
    output reg     [AXI_ADDR_WIDTH-1: 0]m_axi_araddr               ,
    output               [   7: 0]      m_axi_arlen                ,
    output               [   2: 0]      m_axi_arsize               ,
    output               [   1: 0]      m_axi_arburst              ,
    output               [   0: 0]      m_axi_arlock               ,
    output               [   3: 0]      m_axi_arcache              ,
    output               [   2: 0]      m_axi_arprot               ,
    output               [   3: 0]      m_axi_arqos                ,
    output               [   3: 0]      m_axi_arregion             ,
    output reg                          m_axi_arvalid              ,
    input                               m_axi_arready              ,

    // ==================== 读数据通道 ==================== 
    input        [AXI_ID_WIDTH-1: 0]    m_axi_rid                  ,
    input        [AXI_DATA_WIDTH-1: 0]  m_axi_rdata                ,
    input                [   1: 0]      m_axi_rresp                ,
    input                               m_axi_rlast                ,
    input                               m_axi_rvalid               ,
    output                              m_axi_rready               ,

    //==================== 实验接口 ====================
    output                               r_done                    ,
    input                               rd_enable                  ,
    // ==================== 双帧缓存切换逻辑信号 ====================
    input                               r_buf                       ,// 0=读帧A, 1=读帧B,默认读B
    input                               r_addr_switch_pulse          //地址切换脉冲，与指针一同出现
    );


//===============================================================================================================   
//本地参数及接口定义、连线

    reg                  [   2: 0]      current_state              ;
    reg                  [   2: 0]      next_state                 ;
    localparam                          S_IDLE                     = 3'b001               ,
                                        S_RD_ADDR                  = 3'b010,
                                        S_RD_RESP                  = 3'b100;

    wire                 [FIFO_ADDR_WIDTH-1: 0]rd_req_cnt_thresh    ;

    localparam                          DATA_SIZE                   = $clog2(AXI_DATA_WIDTH/8)  ;
    localparam                          BURST_BYTE_LEN              = (AXI_BURST_LEN + 1) * (AXI_DATA_WIDTH/8);
    localparam                          FIFO_SAFE_THRESHOLD         = 2**FIFO_ADDR_WIDTH - (AXI_BURST_LEN[7:0]+1'b1); //如果fifo中数据的量大于这个量，那么fifo中剩余的空间就不支持再读一次DDR3了
    localparam                          BURST_COUNT                 = IMAGE_WIDTH*IMAGE_HEIGHT*2/((AXI_BURST_LEN[7:0]+1'b1)*(AXI_DATA_WIDTH/8));//完成一帧操作需要的突发次数
    localparam TOTAL_BEATS =(IMAGE_WIDTH*IMAGE_HEIGHT*2/(AXI_DATA_WIDTH/8)) ;
//===============================================================================================================
//逻辑输出

    assign                              m_axi_arsize                = DATA_SIZE                     ;
    assign                              m_axi_arid                  = AXI_ID                        ;
    assign                              m_axi_arburst               = AXI_ARBURST_INCR              ;
    assign                              m_axi_arlock                = AXI_ARLOCK_NORMAL             ;
    assign                              m_axi_arcache               = AXI_ARCACHE_DEVICE_NON_BUF    ;
    assign                              m_axi_arprot                = AXI_ARPROT_UNPRIV_SECURE      ;
    assign                              m_axi_arqos                 = AXI_ARQOS_DEFAULT             ;
    assign                              m_axi_arregion              = AXI_ARREGION_DEFAULT          ;
    assign                              m_axi_arlen                 = AXI_BURST_LEN                 ;

// ==================== 第一段：状态转移 ====================
always @(posedge clk or posedge reset) begin
    if(reset)
    current_state<=S_IDLE;
    else
    current_state<=next_state;
end

// ==================== 第二段：下一状态逻辑 ====================
reg rd_ddr3_req_pulse;


always @(*) begin
    if(reset)
    next_state=S_IDLE;
    else
    case (current_state)
        S_IDLE    :begin
            if(rd_ddr3_req_pulse)
            next_state=S_RD_ADDR;
            else
            next_state=S_IDLE;
        end
        S_RD_ADDR :begin
            if(m_axi_arvalid&&m_axi_arready)
            next_state=S_RD_RESP;
            else
            next_state=S_RD_ADDR;
        end
        S_RD_RESP :begin
            if(m_axi_rvalid&&m_axi_rready&&m_axi_rlast&&
            (m_axi_rresp==2'b00)&&
            (m_axi_rid==AXI_ID)
            )
            next_state=S_IDLE;   //代表发完一拍数据
            else
            next_state=S_RD_RESP;
        end 
        default: next_state=S_IDLE;
    endcase
end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ==================== 第三段：输出逻辑 ====================
//////////////////////////////////////////////////////////////////////////////////


//=========================m_axi_rready信号怎么产生=======================================//
 assign m_axi_rready  = ~fifo_alfull;    //当fifo将要满时，代表fifo中有足够的数据可以读取，此时“ready”较为合适
 //assign m_axi_rready  = 1'b1;

//=========================产生帧激活信号frame_active======================================//
reg  frame_active;    //拉高代表ddr3内已经有数据可用此时开始读，不会产生“垃圾读”

always @(posedge clk or posedge reset) begin
    if (reset)
        frame_active <= 0;
    else if (rd_enable)
        frame_active <= 1;
end

//=========================产生ddr3开始读信号======================================//
assign rd_req_cnt_thresh = FIFO_SAFE_THRESHOLD[FIFO_ADDR_WIDTH-1:0]; //如果fifo中数据的量大于这个量，那么fifo中剩余的空间就不支持再读一次DDR3了
//目的：保证读 DDR 之前，FIFO 一定有足够空间装下整段突发，绝不溢出！
// 寄存器脉冲生成

wire rd_ddr3_condition;
assign rd_ddr3_condition = (fifo_wr_cnt < rd_req_cnt_thresh - 2) && ~fifo_rst_busy && frame_active;

always @(posedge clk or posedge reset) begin
    if (reset)
        rd_ddr3_req_pulse <= 0;
    else if (rd_ddr3_condition && current_state == S_IDLE)
        rd_ddr3_req_pulse <= 1;   // 只在空闲时产生一个脉冲
    else
        rd_ddr3_req_pulse <= 0;
end



//================================================================================
//通过计数读突发次数，来标定一帧信号结束
reg [($clog2(BURST_COUNT)-1):0] rd_burst_done_cnt;           // 已完成的读突发数
reg        r_brust_complete;                                  // 帧读完成脉冲


always @(posedge clk or posedge reset) begin
    if (reset) begin
        rd_burst_done_cnt <= 0;
        r_brust_complete <= 0;
    end 
    else if (m_axi_rvalid && m_axi_rready && m_axi_rlast &&   // 每完成一个属于自己的读突发，计数+1
            (m_axi_rid == AXI_ID)&&
            frame_active)
             begin
            if (rd_burst_done_cnt == BURST_COUNT-1) begin  // 最后一个突发
                r_brust_complete <= 1;
            rd_burst_done_cnt <= 0;
            end
            else begin
                rd_burst_done_cnt <= rd_burst_done_cnt + 1;
                r_brust_complete <= 0;
            end
        end
    else
                r_brust_complete <= 0;        
end

assign  r_done   =    r_brust_complete;

reg [2:0]r_brust_complete_r;
    always @(posedge clk or posedge reset)           
        begin                                        
            if(reset)                               
                r_brust_complete_r<=0;                                                                       
            else  begin
                r_brust_complete_r[0]<=r_brust_complete;
                r_brust_complete_r[1]<=r_brust_complete_r[0];
                r_brust_complete_r[2]<=r_brust_complete_r[1];    
            end                                    
        end                                          


//================================================================================
//根据地址切换信号，动态更新地址
reg [31:0]dynamic_addr;

    always@(*)begin
            if(r_addr_switch_pulse) begin
               case (r_buf)
                   1: dynamic_addr=BUF_B_BEGIN;
                   0: dynamic_addr=BUF_A_BEGIN;
               endcase      
       end  
    end
    
//===========================如何产生m_axi_araddr信号====================
  always@(posedge clk or posedge reset)
  begin
    if(reset)
      m_axi_araddr <= BUF_B_BEGIN;      //默认读B
    else if(r_brust_complete_r[2])    
      m_axi_araddr <= dynamic_addr;                
    else if((current_state == S_RD_RESP) &&
     m_axi_rready && m_axi_rvalid && m_axi_rlast && 
     (m_axi_rresp == AXI_RRESP_OKAY) &&
      (m_axi_rid == AXI_ID)
      &&frame_active
       )
      m_axi_araddr <= m_axi_araddr +BURST_BYTE_LEN;  
    else
      m_axi_araddr <= m_axi_araddr;
  end

//===========================如何产生m_axi_arvalid信号====================
always @(posedge clk or posedge reset) begin
    if(reset)
    m_axi_arvalid<=0;
    else if((current_state==S_RD_ADDR)&&m_axi_arready && m_axi_arvalid)
    m_axi_arvalid<=0;
    else if((current_state==S_RD_ADDR))
    m_axi_arvalid<=1;
    else
    m_axi_arvalid<=m_axi_arvalid;
end

//===========================如何产生fifo写请求信号====================
    always @(posedge clk or posedge reset) begin
        if(reset)
            fifo_wrreq <= 1'b0;
        else
            fifo_wrreq <= m_axi_rvalid & m_axi_rready&&frame_active;
        end

    always @(posedge clk) begin
        if(m_axi_rvalid && m_axi_rready&&frame_active)
            fifo_wrdata <= m_axi_rdata;
        end


endmodule
//////////////////////////////////////////    调试过程中弃用的方案       //////////////////////////////////////////////
/*
//==================================================================================================
//通过计数读突发次数标定一帧读结束
//弃用原因，ddr3启动时（复位刚结束）会启动一次突发读，这一次好像无法规避，会导致计数错位，表现位画面逐渐变乱，后恢复正常
//不考虑用回，hdmi的行、列计数器已经能很好完成任务
reg [15:0] rd_burst_done_cnt;   // 已完成的读突发数
reg        r_brust_complete;              // 帧读完成脉冲
reg rd_burst_done_cnt_en;


always @(posedge clk or posedge reset) begin     //这段代码的目的是跳过第一个m_axi_rvalid && m_axi_rready && m_axi_rlast,这是无效的！
    if (reset)
    rd_burst_done_cnt_en<=0;
    else if (m_axi_rvalid && m_axi_rready && m_axi_rlast &&   
            (m_axi_rid == AXI_ID)) 
    rd_burst_done_cnt_en<=1;
    
end

always @(posedge clk or posedge reset) begin
    if (reset) begin
        rd_burst_done_cnt <= 0;
        r_brust_complete <= 0;
    end 
    else if (m_axi_rvalid && m_axi_rready && m_axi_rlast &&   // 每完成一个属于自己的读突发，计数+1
            (m_axi_rid == AXI_ID)&&
            rd_burst_done_cnt_en) begin
            if (rd_burst_done_cnt == 16'd3600 -1) begin  // 最后一个突发
                r_brust_complete <= 1;
            rd_burst_done_cnt <= 0;
            end
            else begin
                rd_burst_done_cnt <= rd_burst_done_cnt + 1;
                r_brust_complete <= 0;
            end
        end
    else
                r_brust_complete <= 0;        

end

reg [15:0] rd_burst_done_cnt;   // 已完成的读突发数
reg        r_brust_complete;              // 帧读完成脉冲


always @(posedge clk or posedge reset) begin
    if (reset) begin
        rd_burst_done_cnt <= 0;
        r_brust_complete <= 0;
    end 
    else if (m_axi_rvalid && m_axi_rready && m_axi_rlast &&   // 每完成一个属于自己的读突发，计数+1
            (m_axi_rid == AXI_ID)&&
            frame_active) begin
            if (rd_burst_done_cnt == 16'd3600 -1) begin  // 最后一个突发
                r_brust_complete <= 1;
            rd_burst_done_cnt <= 0;
            end
            else begin
                rd_burst_done_cnt <= rd_burst_done_cnt + 1;
                r_brust_complete <= 0;
            end
        end
    else
                r_brust_complete <= 0;        

end


//===========================如何产生m_axi_araddr信号====================
//调试时留下的，多种方案组合验证的产物，现在废弃
  always@(posedge clk or posedge reset)
  begin
    if(reset)
      m_axi_araddr <= BUF_A_BEGIN;
//else if(m_axi_rready && m_axi_rvalid &&m_axi_rlast&&(m_axi_araddr==32'h011c1e00))
//     m_axi_araddr <= BUF_A_BEGIN;
//   else if(r_done)
//   m_axi_araddr <= BUF_A_BEGIN;      //默认读B
  else if(frame_read_done)
    m_axi_araddr <= BUF_A_BEGIN;      //默认读B
// else if(frame_read_done_safe)
//   m_axi_araddr <= BUF_A_BEGIN;      //默认读B
//    else if(r_brust_complete)
//      m_axi_araddr <= BUF_A_BEGIN;      //默认读B
//  else if(r_addr_switch_pulse) begin
//            case (r_buf)
//                1: m_axi_araddr<=BUF_B_BEGIN;
//                0: m_axi_araddr<=BUF_A_BEGIN;
//            endcase      
//    end                             
    else if((current_state == S_RD_RESP) &&
     m_axi_rready && m_axi_rvalid && m_axi_rlast && 
     (m_axi_rresp == AXI_RRESP_OKAY) &&
      (m_axi_rid == AXI_ID)
      &&frame_active
       )
      m_axi_araddr <= m_axi_araddr +BURST_BYTE_LEN;  
    else
      m_axi_araddr <= m_axi_araddr;
  end



//===========================ILA观察端口====================

ILA axi4_fifo_lia (
    .clk                                (clk                       ),// input wire clk


    .probe0                             (m_axi_rvalid                  ),// input wire [0:0]  probe0  
    .probe1                             (m_axi_rlast                     ),// input wire [0:0]  probe1 
    .probe2                             (frame_read_done             ),// input wire [0:0]  probe2 
    .probe3                             ({r_brust_complete,r_done,rd_ddr3_req_pulse,rd_enable,rd_burst_done_cnt[11:0]}          ),// input wire [16:0]  probe3 
    .probe4                             ({frame_read_done_safe,m_axi_araddr[30:0]}) // input wire [31:0]  probe4
);

//===========================通过计数突发握手次数，来标定一帧结束，弃用原因：过于耗费资源====================

wire frame_read_done;

reg [($clog2(TOTAL_BEATS)-1):0]rdata_beat_cnt;


always @(posedge clk or posedge reset) begin
    if (reset)
        rdata_beat_cnt <= 0;
    else if ((rdata_beat_cnt == TOTAL_BEATS-1 )&&m_axi_rvalid && m_axi_rready&&frame_active)
        rdata_beat_cnt <= 0;
    else if (m_axi_rvalid && m_axi_rready&&frame_active)

        rdata_beat_cnt <= rdata_beat_cnt + 1;
end

assign frame_read_done = (rdata_beat_cnt == TOTAL_BEATS -1) && m_axi_rvalid && m_axi_rready;

// 在 ui_clk 下，把 frame_read_done_raw 同步化
reg frame_read_done_d1;
reg frame_read_done_d2;
always @(posedge clk) begin
    frame_read_done_d1 <= frame_read_done;
    frame_read_done_d2 <= frame_read_done_d1;
end
wire frame_read_done_safe;
assign frame_read_done_safe= frame_read_done_d2;  // 用这个打两拍后的信号


*/