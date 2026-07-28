//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/04/29 16:18:38
// fix Date   : 2026/05/23   完善功能逻辑，增加起始脉冲上升沿锁存功能,且修改使用IOBUF
           //    2026/05/24  修复iic_done产生条件只适配400khz的特性，使用SCL_CNT_M作为产生条件，目前适配所有频率
// Design Name: 
// Module Name: iic_bit_shift
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description:产生iic的最小单元 ,也可用于SCCB
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//////////////////////////////////////////////////////////////////////////////////


module iic_bit_shift
#(
    parameter SYS_CLOCK = 50_000_000,    //系统时钟频率
    parameter SCL_CLOCK = 400_000        //iic总线工作时钟频率
)
(
    // ==================== 全局信号 ====================
    input                               clk                        ,// 主时钟 50Mhz
    input                               rst_n                      ,// 异步低有效复位，同步化后使用
    
    // ==================== 控制接口 ====================
    output reg                          iic_done                   ,//发送完成时给出的脉冲信号
    output reg                          iic_busy                   ,// 模块忙标志，为1时忽略新的iic_start   
    input                               iic_start                  ,//开始发送iic命令 

    // ==================== 协议参数接口 ====================
    input                [   5: 0]      iic_cmd                    ,//用户操作命令
    input                [   7: 0]      iic_tx_data                ,//8位数据，要转化为iic总线发走    
    output reg           [   7: 0]      iic_rx_data                ,//总线上接受到的数据，转化为8位数输出
    output reg                          iic_ack                    ,//应答信号，本模块为最基础模块，不做判断，送出去让外部模块判断
    output reg                          ack_check_flag             ,//外部检测应答信号，产生应答位后置1，帮助外部模块判断应答位
    output reg                          ack_gen_flag               ,//应答位产生标志信号，仅用连续读最后一位操作时，提前改变命令为iic_cmd<=RD|NACK|STO;
 
    // ==================== 物理层接口(iic) ====================顶层使用IOBUF例化
    output reg                          iic_sclk                   ,//串行时钟线
    output reg                          iic_sdat_o                 ,// iic串行数据线输出
    input                               iic_sdat_i                 ,// iic串行数据线输入
    output reg                          iic_sdat_t                  // 三态控制，0可输出，1为高阻，释放总线
    );

//=================================================
//操作命令以及三段式状态机的状态

	localparam 
		WR   = 6'b000001,   //写请求
		STA  = 6'b000010,   //起始位请求
		RD   = 6'b000100,   //读请求
		STO  = 6'b001000,   //停止位请求
		ACK  = 6'b010000,   //应答位请求
		NACK = 6'b100000;   //无应答请求


// FSM 自动编码选择（Vivado官方标准）

//(* fsm_encoding = "one_hot" *)
reg [6:0] current_state;  
//(* fsm_encoding = "one_hot" *)
reg [6:0] next_state;

    localparam
    		IDLE      = 7'b0000_001,   //空闲状态
    		GEN_STA   = 7'b0000_010,   //产生起始信号
    		WR_DATA   = 7'b0000_100,   //写数据状态
    		RD_DATA   = 7'b0001_000,   //读数据状态
    		CHECK_ACK = 7'b0010_000,   //检测应答状态
    		GEN_ACK   = 7'b0100_000,   //产生应答状态
    		GEN_STO   = 7'b1000_000;   //产生停止信号

//=================================================
//产生开始脉冲信号
    wire                                iic_start_pluse            ;//开始脉冲信号上升沿
    reg                                 iic_start_pluse_r          ;//开始脉冲信号上升沿延后一拍
reg [1:0]iic_start_r;
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                                                             
               iic_start_r<=2'b0;                                                  
            else begin
                iic_start_r[0]<=iic_start;
                iic_start_r[1]<=iic_start_r[0];
            end                                                 
        end                                          
assign iic_start_pluse    =(iic_start_r==2'b01);
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                iic_start_pluse_r<=0;                                                                      
            else
                iic_start_pluse_r<=iic_start_pluse;                                     
        end                                          
//=================================================
//产生iic_busy
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                                                             
               iic_busy<=0;
            else if(iic_done)
               iic_busy<=0;                                                   
            else if(iic_start_pluse_r)    
               iic_busy<=1;                                             
        end                                          
//=================================================
//在上升沿脉冲时锁存外部数据，后续只用_r,防止中途变化！
    reg                  [   5: 0]      iic_cmd_r                  ;
    reg                  [   7: 0]      iic_tx_data_r              ;
    reg                                 iic_cmd_clr                ;//命令数据清理信号，防止影响下一次发送

    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)begin
                iic_cmd_r     <=0;   
                iic_tx_data_r <=0;              
            end
            /*
            else if(iic_cmd_clr)begin
                iic_cmd_r     <=0;   
                iic_tx_data_r <=0;
            end    */                                                                                                                
            else if(iic_start_pluse&&~iic_busy)begin
                iic_cmd_r     <=iic_cmd;
                iic_tx_data_r <=iic_tx_data;
            end                                                 
        end 

//=================================================
//产生SCLK的基础分频计数器，将一个SCLK周期四分频,并产生分频脉冲
localparam SCL_CNT_M = SYS_CLOCK/SCL_CLOCK/4 - 1;
reg[($clog2(SCL_CNT_M+1))-1:0]div_cnt;                //自动为分配位宽，SCLK的基础分频计数器
reg div_cnt_en;                                       //计数器开始计数使能信号
wire sclk_plus;

    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)
            div_cnt <= 0;
        else if(div_cnt_en)begin
            if(div_cnt>=SCL_CNT_M)
                div_cnt <= 0;
            else
                div_cnt <= div_cnt+1;
            end
        else
            div_cnt <= 0;
            end

assign sclk_plus=(div_cnt==SCL_CNT_M);                 //产生操作cnt的脉冲

reg [4:0]op_cnt;                                       //操作cnt，在状态机中很关键,在不同的状态下，需要计数的值也不同
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                op_cnt<=0;                                           
            else if(sclk_plus)begin
                if((current_state==GEN_STA)||(current_state==CHECK_ACK)||
                (current_state==GEN_ACK)||(current_state==GEN_STO))
                begin
                	if(op_cnt == 3)
						op_cnt <= 0;
					else
					    op_cnt <= op_cnt + 1'b1;    
                end
                else if((current_state==RD_DATA)||(current_state==WR_DATA))
                begin
                	if(op_cnt == 31)
						op_cnt <= 0;
					else
					    op_cnt <= op_cnt + 1'b1;    
                end                    
                end
            else
                op_cnt<=op_cnt;
            end                                                                                    

                                         
//=================================================
//完成三段式状态机，第二段，状态跳转


    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)
                current_state<=IDLE;                                                                                                                                                           
            else 
                current_state<=next_state; 
        end                                          

always @(*) begin
    case (current_state)
        IDLE      :begin
            if(iic_start_pluse_r&&~iic_busy)begin         //iic_start是启动IDLE的信号
				if     (iic_cmd_r & STA)
					next_state = GEN_STA;
				else if(iic_cmd_r & WR)
					next_state = WR_DATA;
				else if(iic_cmd_r & RD)
					next_state = RD_DATA;
				else
					next_state = IDLE;  
            end
            else
                next_state = IDLE;
        end
        GEN_STA   :begin
            if(sclk_plus&&(op_cnt==3))begin
                if(iic_cmd_r &WR)
                next_state = WR_DATA;
                else if(iic_cmd_r & RD)
                next_state = RD_DATA;
                else
                next_state = IDLE;
            end
            else
				next_state = GEN_STA;                  
        end
        WR_DATA   :begin
            if(sclk_plus&&(op_cnt==31))
                next_state = CHECK_ACK;
            else
				next_state = WR_DATA;
        end
        RD_DATA   :begin
            if(sclk_plus&&(op_cnt==31))
                next_state = GEN_ACK;
            else
				next_state = RD_DATA;
        end
        CHECK_ACK :begin
            if(sclk_plus&&(op_cnt==3))begin
                if(iic_cmd_r&STO)
                next_state = GEN_STO;
                else
					next_state = IDLE;   
            end
            else
                next_state = CHECK_ACK;

        end
        GEN_ACK   :begin
            if(sclk_plus&&(op_cnt==3))begin           
                if(iic_cmd_r&STO)
                next_state = GEN_STO;
                else
					next_state = IDLE;
            end
            else
                next_state = GEN_ACK;
        end

        GEN_STO   :begin
            if(sclk_plus&&(op_cnt==3))
                next_state = IDLE;
            else
                next_state = GEN_STO;
        end 
        default: next_state = IDLE;
    endcase
end

//=================================================
    /*
ila_SCCB ila_SCCB (
    .clk                                (clk                       ),// input wire clk

    .probe0                             (iic_sdat_o                ),// input wire [0:0]  probe0  
    .probe1                             (iic_sdat_i                ),// input wire [0:0]  probe1 
    .probe2                             (iic_sclk                  ),// input wire [0:0]  probe2 
    .probe3                             (iic_done                  ),// input wire [0:0]  probe3 
    .probe4                             (iic_start            ),// input wire [0:0]  probe4 
    .probe5                             (iic_cmd_r                ),// input wire [0:0]  probe5 
    .probe6                             (current_state             ),// input wire [7:0]  probe6 
    .probe7                             (iic_tx_data_r                   ), // input wire [5:0]  probe75]
    .probe8(div_cnt),
    .probe9(op_cnt)
);
    */

//=================================================
//状态机第三段，时序逻辑输出
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(~rst_n) begin
                iic_rx_data       <= 0;
                iic_sdat_t        <= 1;
                div_cnt_en        <= 0;
                iic_done          <= 0;
                iic_ack           <= 1;
                ack_check_flag    <= 0;
                ack_gen_flag      <= 0;
                iic_sdat_o        <= 1; //串行数据总线，默认两条线都为高
                iic_sclk          <= 1;
                iic_cmd_clr       <= 0;
            end                              
                                                                                      
            else 
            case (current_state)
                IDLE      :begin
                    iic_cmd_clr      <= 0;
                    iic_done         <= 0;
                    iic_sdat_t       <= 0;//三态门默认开启，保持输出
                    iic_ack<=1;
                    ack_check_flag   <=0;
                    ack_gen_flag      <= 0;
                    div_cnt_en       <= (next_state != IDLE);// 下一拍非IDLE，则提前开启计数器使能
                end
                GEN_STA   :begin
                    case (op_cnt)
                        0:begin
                            iic_sdat_t    <= 0;
                            iic_sdat_o  <= 1;
                            iic_sclk    <= iic_sclk;    //调试过程中找到的问题，防止状态切换产生毛刺
                        end
                        1:begin
                            iic_sdat_o  <= 1;
                            iic_sclk    <= 1;
                        end
                        2:begin
                            iic_sdat_o  <= 0;       //SDA先产生 下降沿
                            iic_sclk    <= 1;
                        end
                        3:begin
                            iic_sdat_o  <= 0;
                            iic_sclk    <= 0;       //SCLK后产生 下降沿
                        end 
                        default: begin
                            iic_sdat_o  <= 1;       //默认两条线都为高
                            iic_sclk    <= 1;                            
                        end
                    endcase
                end
                WR_DATA   :begin
                    case (op_cnt)
                        0,4,8,12,16,20,24,28:begin
                            iic_sdat_t  <= 0;                            
                            iic_sdat_o <= iic_tx_data_r[7-op_cnt[4:2]];  //利用操作计数器的前三位，完成数据的并转串发送
                            iic_sclk   <= 0;
                            end                
                        1,5,9,13,17,21,25,29:begin
                            iic_sdat_o <= iic_sdat_o;               //其余时间数据保持不动
                            iic_sclk   <= 1;
                            end
                        2,6,10,14,18,22,26,30:begin
                            iic_sdat_o <= iic_sdat_o;               //其余时间数据保持不动
                            iic_sclk   <= 1;
                            end                
                        3,7,11,15,19,23,27,31:begin
                            iic_sdat_o <= iic_sdat_o;               //其余时间数据保持不动
                            iic_sclk   <= 0;
                            end
                        default: begin
                            iic_sdat_o  <= 1; //默认两条线都为高
                            iic_sclk    <= 1;                            
                        end
                    endcase                    
                end
                RD_DATA   :begin
                    case (op_cnt)
                        0,4,8,12,16,20,24,28:begin
                            iic_sdat_t <= 1;                       //将sda设置为输入                            
                            iic_sclk   <= 0;
                            end                
                        1,5,9,13,17,21,25,29:begin
                            iic_sclk   <= 1;
                            end
                        2,6,10,14,18,22,26,30:begin
                            iic_sclk   <= 1;
                            if(sclk_plus)
                            iic_rx_data    <={iic_rx_data[6:0],iic_sdat_i};  //向左移位，直到8位全部读取满
                            end                
                        3,7,11,15,19,23,27,31:begin
                            iic_sclk   <= 0;
                            end
                        default: begin
                            iic_sclk    <= 1;    //默认时钟线为高                         
                        end
                    endcase                    

                end
                CHECK_ACK :begin
                    case (op_cnt)
                        0:begin
                            iic_sdat_t  <= 1;
                            iic_sclk    <= 0;                        
                        end
                        1:begin
                            iic_sclk    <= 1;
                        end
                        2:begin
                            iic_sclk    <= 1;
                            iic_ack       <=iic_sdat_i;
                            ack_check_flag <=1;
                        end
                        3:begin
                            iic_sclk    <= 0;
                            if(iic_cmd_r&STO)begin
                                iic_done     <= 0; 
                       
                            end
                            else if(div_cnt==SCL_CNT_M)begin
                                iic_done     <= 1; 
                                iic_cmd_clr  <= 1;  //清空命令为下一拍做准备 
                            end
                            else begin
                                iic_done     <= 0; 
                                iic_cmd_clr  <= 0;
                            end            
                        end 
                        default: begin
                            iic_sclk    <= 1;     //默认时钟线为高                          
                        end
                    endcase
                end
                GEN_ACK   :begin
                    case (op_cnt)
                        0:begin
                            iic_sdat_t  <= 0;
                            iic_sclk    <= 0;
                            ack_gen_flag      <= 1;
                            if(iic_cmd_r&ACK)
                            iic_sdat_o  <=0;
                            else if(iic_cmd_r&NACK)
                            iic_sdat_o  <=1;
                            else
                            iic_sdat_o  <=1;     //默认情况下为高

                        end
                        1:begin
                            iic_sdat_o  <= iic_sdat_o;
                            iic_sclk    <= 1;
                        end
                        2:begin
                            iic_sdat_o  <= iic_sdat_o;    
                            iic_sclk    <= 1;
                        end
                        3:begin
                            iic_sdat_o  <= 1;     //恢复默认为高的状态
                            iic_sclk    <= 0;     //SCLK后产生 下降沿
                            ack_gen_flag      <= 0;
                            if(iic_cmd_r&STO)begin
                                iic_done     <= 0;                         
                            end   
                            else if(div_cnt==SCL_CNT_M)begin
                                iic_done     <= 1; 
                                iic_cmd_clr  <= 1;  //清空命令为下一拍做准备 
                            end
                            else begin
                                iic_done     <= 0; 
                                iic_cmd_clr  <= 0;
                            end    
                        end 
                        default: begin
                            iic_sdat_o  <= 1; //默认两条线都为高
                            iic_sclk    <= 1; 
                            ack_gen_flag      <= 0;                           
                        end
                    endcase
                end
                GEN_STO   :begin
                    case (op_cnt)
                        0:begin
                            iic_cmd_clr  <= 1;  //清空命令为下一拍做准备  
                            iic_sdat_t    <= 0;
                            iic_sdat_o  <= 0;
                            iic_sclk    <= 0;
                            iic_done  <=0; 
                            iic_ack       <= 1;
                            ack_check_flag <=0;                                
                        end
                        1:begin
                            iic_sdat_o  <= 0;
                            iic_sclk    <= 1;
                        end
                        2:begin
                            iic_sdat_o  <= 1;     //SDA先产生 上升沿
                            iic_sclk    <= 1;
                        end
                        3:begin
                            iic_sdat_o  <= 1;
                            iic_sclk    <= 1;
                            if(sclk_plus&&(div_cnt==SCL_CNT_M))begin
                            iic_done  <= 1;     //产生传输完成信号
                            iic_cmd_clr  <= 1;  //清空命令为下一拍做准备                             
                            end                          
                        end 
                        default: begin
                            iic_sdat_o  <= 1; //默认两条线都为高
                            iic_sclk    <= 1;                            
                        end
                    endcase
                end           
                default: begin
                    iic_rx_data       <= iic_rx_data;
                    iic_sdat_t        <= iic_sdat_t;
                    div_cnt_en        <= div_cnt_en;
                    iic_done          <= 1'b0;
                    iic_ack           <= iic_ack;
                    ack_check_flag    <= 0;
                    ack_gen_flag      <= 0;
                    iic_sdat_o        <= 1'b1;
                    iic_sclk          <= 1'b1;
                    iic_cmd_clr       <= 0;  
                end
            endcase                                     
        end                                          

endmodule
