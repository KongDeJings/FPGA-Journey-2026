`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/11 14:17:00
// Design Name: 
// Module Name: mdio_shift_bit
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 根据控制信号，产生一次对PHY的读或写操作
//代码中禁止使用魔数！
//////////////////////////////////////////////////////////////////////////////////

module mdio_shift_bit
#(
    parameter                           MDC_CLOCK                   = 1250_000             ,  // MDC目标频率1.25Mhz
    parameter                           SYS_CLOCK                   = 50_000_000           // 输入时钟频率50Mhz
)(
    // 系统接口
    input                               clk                        ,
    input                               rst_n                      ,
    
    // 控制接口
    input                               mdio_start                 ,// 启动信号，脉冲
    output reg                          mdio_busy                  ,// 模块忙
    output reg                          mdio_done                  ,// 操作完成，脉冲
    output reg                          mdio_ack                   ,// PHY应答成功,0有效，空闲时mdio_ack为高电平
    output reg                          mdio_timeout               ,// 超时错误
    
    // 操作参数
    input                               rnw                        ,// 1=读，0=写
    input                [   4: 0]      phy_addr                   ,
    input                [   4: 0]      reg_addr                   ,
    input                [  15: 0]      wr_data                    ,
    output reg           [  15: 0]      rd_data                    ,
    
    // MDIO物理接口
    output reg                          mdc                        ,// MDC时钟输出
    output reg                          mdio_o                     ,// 数据输出
    input                               mdio_i                     ,// 数据输入
    output reg                          mdio_t                      // 三态控制，0可输出，1为高阻，释放总线
);

// ==================== 本地参数定义 ====================
reg [5:0]   current_state, next_state;

localparam  IDLE               = 6'b00_0001,
            S_WAIT_PREAMBLE    = 6'b00_0010,    // 等待前导码发送完成
            S_SEND_SHIFT       = 6'b00_0100,    // 发送器件地址和写入phy的数据（写入时）
            S_READ_SHIFT       = 6'b00_1000,    // 等待PHY应答并读取串行线上的数据 
            S_WAIT_7_MDC       = 6'b01_0000,    // 操作完成后等待7个MDC时钟
            S_DONE             = 6'b10_0000;    // 结束，只保留1个时钟周期

localparam  MDC_CNT_M              = SYS_CLOCK/MDC_CLOCK/4 - 1    ,//基础分频计数器值，将一个MDC时钟分为4份，并在每一份操作
            PREAMBLE_OP            =   32*4 -1                    ,//前导码 32 个 MDC 周期 *4
            WRITE_SHIFT_OP         =   32*4 -1                    ,//Start + Op + PHYAD + REGAD + TA + Data（32 个 MDC 周期 ）*4
            WRITE_SHIFT_2_READ_OP  =   14*4 -1                    ,//Start + Op + PHYAD + REGAD(14 个 MDC 周期 ）*4
            READ_SHIFT_OP          =   18*4 -1                    ,//TA + Data（18 个 MDC 周期 ）*4
            MDC_7_OP               =   7*4  -1                    ;//等待7个MDC时钟周期*4

//=================================================
//产生开始脉冲信号
wire mdio_start_pluse;                      //开始脉冲信号上升沿
reg [1:0]mdio_start_r;
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                                                             
               mdio_start_r<=2'b0;                                                  
            else begin
                mdio_start_r[0]<=mdio_start;
                mdio_start_r[1]<=mdio_start_r[0];
            end                                                 
        end                                          
assign mdio_start_pluse=(mdio_start_r==2'b01);

//=================================================
//产生mdio_busy
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                                                             
               mdio_busy<=0;
            else if(mdio_done)
               mdio_busy<=0;                                                   
            else if(mdio_start_pluse&&~mdio_done)    
               mdio_busy<=1;                                             
        end                                          
//=================================================
//在上升沿脉冲时锁存外部数据，后续只用_r,防止中途变化！
    reg                                 rnw_r                      ;
    reg                  [   4: 0]      phy_addr_r                 ;
    reg                  [   4: 0]      reg_addr_r                 ;
    reg                  [  15: 0]      wr_data_r                  ;

    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)begin
                rnw_r      <=0;
                phy_addr_r <=0;
                reg_addr_r <=0;
                wr_data_r  <=0;                
            end                                                                                                             
            else if(mdio_start_pluse)begin
                rnw_r      <=rnw     ;
                phy_addr_r <=phy_addr;
                reg_addr_r <=reg_addr;
                wr_data_r  <=wr_data ;
            end                                                 
        end 

//=================================================
//产生mdc的基础分频计数器，将一个MDC周期四分频,并产生分频脉冲
    reg   [($clog2(MDC_CNT_M+1))-1: 0]               div_cnt       ;//自动为分配位宽，MDC的基础分频计数器
    reg                                              div_cnt_en    ;//计数器开始计数使能信号
    wire                                             MDC_pluse     ;

    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)
            div_cnt <= 0;
        else if(div_cnt_en)begin
            if(div_cnt>=MDC_CNT_M)
                div_cnt <= 0;
            else
                div_cnt <= div_cnt+1;
            end
        else
            div_cnt <= 0;
            end
assign MDC_pluse=(div_cnt==MDC_CNT_M);                 //产生操作cnt的脉冲

//=================================================
//操作cnt，在状态机中很关键,通过它指导MDC和mdio的变化
    reg                  [$clog2(PREAMBLE_OP+1)-1: 0]op_cnt                     ;
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                op_cnt<=0;                                           
            else if(MDC_pluse)begin                     //只在分频脉冲时改变计数器的值
                if(current_state==S_WAIT_PREAMBLE)                  begin
                	if(op_cnt ==PREAMBLE_OP )
						op_cnt <= 0;
					else
					    op_cnt <= op_cnt + 1'b1;    
                end
                else if(current_state==S_SEND_SHIFT)                begin
                    if(rnw_r)begin
                	    if(op_cnt == WRITE_SHIFT_2_READ_OP)//读操作在写完地址后要跳转
					    	op_cnt <= 0;
					    else
					        op_cnt <= op_cnt + 1'b1;  
                    end
                    else begin
                	    if(op_cnt == WRITE_SHIFT_OP)
					    	op_cnt <= 0;
					    else
					        op_cnt <= op_cnt + 1'b1;                          
                    end

                end
                else if(current_state==S_READ_SHIFT)                begin
                	if(op_cnt == READ_SHIFT_OP)
						op_cnt <= 0;
					else
					    op_cnt <= op_cnt + 1'b1;    
                end
                else if(current_state==S_WAIT_7_MDC)                begin
                	if(op_cnt == MDC_7_OP)
						op_cnt <= 0;
					else
					    op_cnt <= op_cnt + 1'b1;    
                end                    
                end
            else
                op_cnt<=op_cnt;
            end  
//=================================================
//拼接发送状态的数据，Start + Op + PHYAD + REGAD + TA + Data（32 个
    wire                 [  31: 0]      send_data_assembly         ;
assign send_data_assembly=rnw_r?{2'b01,2'b10,phy_addr_r,reg_addr_r,18'b1}:    //读时只发前14位，后面的不发
                                        {2'b01,2'b01,phy_addr_r,reg_addr_r,2'b10,wr_data_r};  //写时全发，完整拼接

// ==================== 第一段：状态转移 ====================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
    end else begin
        current_state <= next_state;
    end
end

// ==================== 第二段：下一状态逻辑 ====================
    always @(*) begin
        case (current_state)
            IDLE              :begin
                if(mdio_start_pluse&&~mdio_busy) //在不忙的时候来脉冲才跳转
                    next_state=S_WAIT_PREAMBLE;
                else
                    next_state = IDLE;
            end
            S_WAIT_PREAMBLE   :begin
                if(op_cnt==PREAMBLE_OP&&(div_cnt==MDC_CNT_M))
                    next_state=S_SEND_SHIFT;
                else    
                    next_state=S_WAIT_PREAMBLE;
            end
            S_SEND_SHIFT      :begin
                if(~rnw_r)begin    //写操作
                    if(op_cnt==WRITE_SHIFT_OP&&(div_cnt==MDC_CNT_M))
                        next_state=S_WAIT_7_MDC;
                    else    
                        next_state=S_SEND_SHIFT;                    
                end
                else begin         //读操作
                    if(op_cnt==WRITE_SHIFT_2_READ_OP&&(div_cnt==MDC_CNT_M))//半路跳走
                        next_state=S_READ_SHIFT;
                    else    
                        next_state=S_SEND_SHIFT;                    
                end                    
            end
            S_READ_SHIFT      :begin
                if((op_cnt==5)&&MDC_pluse&&(mdio_i==1))    //opcnt在第5位(第二bit的上升沿)时没有应答，产生mdio_timeout
                    next_state = IDLE;
                else if(op_cnt==READ_SHIFT_OP&&(div_cnt==MDC_CNT_M))
                    next_state=S_WAIT_7_MDC;
                else    
                    next_state=S_READ_SHIFT;                
            end
            S_WAIT_7_MDC      :begin
                if(op_cnt==MDC_7_OP&&(div_cnt==MDC_CNT_M))
                    next_state=S_DONE;
                else    
                    next_state=S_WAIT_7_MDC;
            end                
            S_DONE            :begin
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

// ==================== 第三段：输出逻辑 ====================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位所有寄存器   
                div_cnt_en      <=0       ;
                mdio_done       <=0       ;
                mdio_ack        <=1       ;
                mdio_timeout    <=0       ;
                rd_data         <=16'b0   ;
                mdc             <=0       ;
                mdio_o          <=1       ;   //空闲必须拉高
                mdio_t          <=1       ;   //空闲必须为高阻
    end 
        else begin    
        case (current_state)
            IDLE              :begin
        // 复位所有寄存器   
                div_cnt_en      <=0       ;
                mdio_done       <=0       ;
                mdio_ack        <=1       ;
                mdio_timeout    <=0       ;
                rd_data         <=16'b0   ;
                mdc             <=0       ;
                mdio_o          <=1       ;   //空闲必须拉高
                mdio_t          <=1       ;   //空闲必须为高阻                
                div_cnt_en <= (next_state != IDLE) && (next_state != S_DONE);// 下一拍非IDLE或DONE，则提前开启计数器使能                
            end
            S_WAIT_PREAMBLE   :begin
                if(MDC_pluse)begin    
                case (op_cnt)
                    1,  5,9,13,17,21,25,29,33,37,41,45,49,53,57,61,65,
                    69,73,77,81,85,89,93,97,101,105,109,113,117,121,125,

                    2,  6,10,14,18,22,26,30,34,38,42,46,50,54,58,62,66,
                    70,74,78,82,86,90,94,98,102,106,110,114,118,122,126:begin
                        mdc<=1;
                        mdio_t<=1;
                    end
                    0,   4,8,12,16,20,24,28,32,36,40,44,48,52,56,60,64,
                    68,72,76,80,84,88,92,96,100,104,108,112,116,120,124,

                    3,   7,11,15,19,23,27,31,35,39,43,47,51,55,59,63,
                    67,71,75,79,83,87,91,95,99,103,107,111,115,119,123:begin
                        mdc<=0;
                        mdio_t<=1;
                    end
                    127:begin
                        mdc<=0;
                        mdio_t<=0;                        
                    end
                    default:mdc<=0;
                endcase
                end
            end
            S_SEND_SHIFT      :begin
                if(MDC_pluse)begin
                    if(~rnw_r)begin  //写操作 32
                case (op_cnt)
                    0:begin
                        mdc<=0;
                        mdio_t<=0;
                        mdio_o<=send_data_assembly[31];                            
                    end
                    1,        5,9,13,17,21,25,29,33,37,41,45,49,53,61,65,
                    69,73,77,81,85,89,93,97,101,105,109,113,117,121,125:begin
                        mdc<=1;
                        mdio_t<=0;
                    end
                    2,       6,10,14,18,22,26,30,34,38,42,46,50,54,62,66,
                    70,74,78,82,86,90,94,98,102,106,110,114,118,122,126:begin
                        mdc<=1;
                        mdio_t<=0;
                    end
                            4,8,12,16,20,24,28,32,36,40,44,48,52,60,64,
                    68,72,76,80,84,88,92,96,100,104,108,112,116,120,124:begin
                        mdc<=0;
                        mdio_t<=0;
                    end
                    
                    3,        7,11,15,19,23,27,31,35,39,43,47,51,59,63,
                    67,71,75,79,83,87,91,95,99,103,107,111,115,119,123:begin
                        mdc<=0;
                        mdio_t<=0;
                        mdio_o<=send_data_assembly[30-op_cnt[$clog2(PREAMBLE_OP+1)-1:2]];//根据数学规律，舍弃末尾两位恰好为0-31

                    end
                    55:begin    //起始位第一位，需要单独拎出
                        mdio_t<=1;
                        mdc<=0;                    end 
                    56:begin
                        mdc<=0;
                        mdio_t<=1;                 end
                    57:begin
                        mdc<=1;
                        mdio_t<=1;                 end
                    58:begin
                        mdc<=1;
                        mdio_t<=1;                 end                    
                    127:begin
                        mdio_t<=1;
                        mdio_o<=1;
                        mdc<=0;                    end                
                    default:mdc<=0;
                endcase
                    end
                    else begin       //读操作 14
                        case (op_cnt)
                    0:begin
                        mdc<=0;
                        mdio_t<=0;
                        mdio_o<=send_data_assembly[31];  end
                    1,5,9,13,17,21,25,29,33,37,41,45,49,53:begin
                        mdc<=1; 
                        mdio_t<=0;                       
                    end
                    2,6,10,14,18,22,26,30,34,38,42,46,50,54:begin
                        mdc<=1;
                        mdio_t<=0;
                    end
                      4,8,12,16,20,24,28,32,36,40,44,48,52:begin
                        mdc<=0; 
                        mdio_t<=0;                       
                    end
                    3,7,11,15,19,23,27,31,35,39,43,47,51:begin
                        mdc<=0;
                        mdio_t<=0;
                        mdio_o<=send_data_assembly[30-op_cnt[$clog2(PREAMBLE_OP+1)-1:2]];//根据数学规律，舍弃末尾两位恰好为0-31
                    end
                    55:begin
                        mdc<=0;
                        mdio_t<=1;      //下一个状态为读，交由PHY控制，主机主动释放总线，等待PHY拉高                   
                    end
                            default: mdc<=0;
                        endcase                        
                    end
                end
            end
            S_READ_SHIFT      :begin   
                if(MDC_pluse)begin
                case (op_cnt)
                    0,4,8,12,16,20,24,28,32,36,40,44,48,52,56,60,64,68:begin
                        mdc<=0;
                    end
                    3,11,15,19,23,27,31,35,39,43,47,51,55,59,63,67,71:begin
                        mdc<=0;
                    end
                    1:mdc<=1;     // 1的时候不需要检测mdio_i的数据
                    9,13,17,21,25,29,33,37,41,45,49,53,57,61,65,69:begin
                        rd_data<={rd_data[14:0],mdio_i};
                        mdc<=1;
                    end
                    2,6,10,14,18,22,26,30,34,38,42,46,50,54,58,62,66,70:begin
                        mdc<=1;
                    end
                    5:begin //在MDC上升沿采样ack，若未采样到，timeout为1
                        if(mdio_i==0)begin
                            mdio_ack<=0;
                            mdio_timeout<=0;   end
                        else begin
                            mdio_timeout<=1;
                            mdio_ack<=1;
                        end
                    end
                    7:begin
                        mdc<=0;
                        mdio_ack<=1;//检测到ack后下一个mdc时钟周期将其复位
                    end
                    default: mdc<=0;
                endcase
                end
            end
            S_WAIT_7_MDC      :begin
                if(MDC_pluse)begin
                case (op_cnt)
                    1,5,9,13,17,21,25,
                    2,6,10,14,18,22,26:begin
                        mdc<=1;
                    end
                    0,4,8,12,16,20,24,
                    3,7,11,15,19,23,27:
                    begin
                        mdc<=0;
                    end
                    default: mdc<=0;
                endcase
                end
            end
            S_DONE            :begin
                mdio_done<=1;
            end

            default: begin
        // 复位所有寄存器   
                div_cnt_en      <=0       ;
                mdio_done       <=0       ;
                mdio_ack        <=1       ;
                mdio_timeout    <=0       ;
                rd_data         <=16'b0   ;
                mdc             <=0       ;
                mdio_o          <=1       ;//空闲必须拉高
                mdio_t          <=1       ;
            end
        endcase        
    end
end



endmodule