
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/04/30 08:22:25
// fix Date:  2026/05/13 08:22:25    更改信号命名，新增支持IOBUF,完善边界条件
//                2026/05/14          修复状态机跳转条件if((send_addr_op_cnt==3)&& trans_done_flag_r)，原来是&& trans_done，tb能跑通，应用无法跑通！
//                   2026/05/18         在高速状态机中，用边沿驱动，而不是用电平判断。，更改trans_done那一堆的判断逻辑
//                      2026/05/24         修复在上板过程中SEND_ADDR_PHASE只保持一个周期的故障！原因是未写else语句
// Design Name: 
// Module Name: iic_control
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description:控制iic最小单元，完成完整通用的ic操作 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:代码不许用魔数
//////////////////////////////////////////////////////////////////////////////////
module iic_control
#(
    parameter SYS_CLOCK = 50_000_000,    //系统时钟频率
    parameter SCL_CLOCK = 400_000        //iic总线工作时钟频率
)
(
    input                               clk                        ,
    input                               rst_n                      ,

    // 控制启动
    input                               iic_start                  ,// 总启动信号
    input                               iic_rw                     ,// 读写控制 1=读 0=写
    input                [   4: 0]      byte_num                   ,// 连续读写字节数（核心！）
    
    // 配置接口
    input                [  15: 0]      reg_addr                   ,// 寄存器地址
    input                               addr_mode                  ,// 0=只发低8位地址[7:0]， 1=16位地址，先发[15:8],再发[7:0]
    input                [   6: 0]      device_addr                ,// 从机地址， device_addr 只用 7 位有效，bit0 指示读写
    
    // 数据接口
    input                [   7: 0]      wr_data                    ,// 写数据
    output reg                          wr_data_req                ,// 告诉外界，写数据已经发完，把剩下的数据接着送进来
    output reg           [   7: 0]      rd_data                    ,// 读出的数据
    output reg                          rd_data_vld                ,// 读数据有效标志，这是一个脉冲信号，只保持一个周期
    
    // 状态标志
    output reg                          iic_done                   ,// 一次传输完成，一次传输结束后才发送
    output reg                          iic_fail                   ,// 无应答，一次传输失败   
    
    // IIC 物理总线
    output                              iic_sclk                   ,//串行时钟线
    output                              iic_sdat_o                 ,// iic串行数据线输出
    output                              iic_sdat_t                 ,// 三态控制，0可输出，1为高阻，释放总线
    input                               iic_sdat_i                  // iic串行数据线输入                   
);

//=================================================
//模块连线

    wire                                trans_done                 ;// 每个基本操作发送完成时给出的脉冲信号
    wire                                iic_busy                   ;// 模块忙标志，为1时忽略新的iic_start
    reg                  [   5: 0]      iic_cmd                    ;// 开始发送iic命令
    reg                  [   7: 0]      iic_tx_data                ;
    wire                 [   7: 0]      iic_rx_data                ;
    wire                                ack_check_flag             ;
    wire                                ack_gen_flag               ;
    reg                                 iic_bit_start              ;//底层模块原子操作起始信号
    wire                                iic_ack                    ;//iic应答标志

//=================================================

//操作命令以及三段式状态机的状态

	localparam 
            		WR   = 6'b000001,   //写请求
            		STA  = 6'b000010,   //起始位请求
            		RD   = 6'b000100,   //读请求
            		STO  = 6'b001000,   //停止位请求
            		ACK  = 6'b010000,   //应答位请求
            		NACK = 6'b100000;   //无应答请求

reg [5:0] current_state;  
reg [5:0] next_state;

    localparam
            FAIL           = 6'b000_001,    //未接受到应答，失败状态
            IDLE           = 6'b000_010,    //空闲状态
            SEND_ADDR_PHASE= 6'b000_100,    //发送地址状态
            READ_PHASE     = 6'b001_000,    //循环读数据
            WRITE_PHASE    = 6'b010_000,    //循环写数据
            DONE           = 6'b100_000;    //连续读、连续写状态结束

//=================================================
//将外部送入的，待发送的并行数据打一拍
//通过打两拍，产生iic_start_flag信号
//通过打三拍，产生trans_done_flag信号,所有命令都是在状态机为IDLE时判断，打两拍错过IDLE态，从而提前做出操作。提前做出操作的方法还有ack_check_flag
    reg                  [   7: 0]      wr_data_r                  ;
    reg                  [   7: 0]      wr_data_r_r                ;
always @(posedge clk or negedge rst_n)           
    begin                                        
        if(!rst_n) begin
            wr_data_r<=0;  
            wr_data_r_r<=0;
        end                              
                                                               
        else begin
            wr_data_r<=wr_data; 
            wr_data_r_r<=wr_data_r;
        end     
                               
    end                                          

    reg                  [   1: 0]      reg_iic_start_flag         ;
    wire                                iic_start_flag             ;
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                reg_iic_start_flag<=2'b0;                                                                                                                    
            else
                reg_iic_start_flag[0]<=iic_start;
                reg_iic_start_flag[1]<=reg_iic_start_flag[0];                                     
        end                                          
assign  iic_start_flag= (reg_iic_start_flag==2'b01);

//=================================================
//产生trans_done_flag

    reg                  [   2: 0]      reg_trans_done_flag        ;
//    wire                                trans_done_flag_r          ;    用reg_trans_done_flag[1]==1替换
//    reg                                 trans_done_flag            ;    用reg_trans_done_flag[2]==1替换
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                reg_trans_done_flag<=2'b0;                                                                                                                    
            else
                reg_trans_done_flag[0]<=trans_done;
                reg_trans_done_flag[1]<=reg_trans_done_flag[0];  
                reg_trans_done_flag[2]<=reg_trans_done_flag[1];                                  
        end  
//   assign  trans_done_flag_r= (reg_trans_done_flag== 2'b10);  
//   always@(posedge clk or negedge rst_n) 
//       if(~rst_n)
//           trans_done_flag<=0;
//       else
//           trans_done_flag<=trans_done_flag_r;


//=================================================
//产生操作计数器，计数到哪一步

    reg                  [   1: 0]      send_addr_op_cnt           ;//指示地址发送阶段的操作计数器,    从机地址加寄存器地址（1+1）或（1+2）
    reg                  [   5: 0]      w_r_op_cnt                 ;//指示读、写操作阶段的操作计数器   因为读操作要写一次器件地址，所以比byte_num多一位，

always @(posedge clk or negedge rst_n ) 
begin
    if(~rst_n)
        send_addr_op_cnt<=0;
    else if((current_state==SEND_ADDR_PHASE))begin
        if(trans_done)
        send_addr_op_cnt<=send_addr_op_cnt+1;   //加满自动溢出，根据具体addr_mode判断到2结束还是到3结束
        end
    else
        send_addr_op_cnt<=0;
end

always @(posedge clk or negedge rst_n ) 
begin
    if(~rst_n)
        w_r_op_cnt<=0;
    else if((current_state==READ_PHASE))begin
        if(trans_done)
        w_r_op_cnt<=w_r_op_cnt+1;
        end
    else if((current_state==WRITE_PHASE))begin
        if(trans_done)
        w_r_op_cnt<=w_r_op_cnt+1;
        end    
    else
        w_r_op_cnt<=0;      //不在连续读、写状态自动清零
end



//=================================================
//三段式状态机

    // ========== 第一段：状态寄存器 ==========
    always@(posedge clk or negedge rst_n)
    if(~rst_n)
        current_state <= IDLE;
    else
        current_state <= next_state;
    
    // ========== 第二段：状态转移逻辑 ==========
    always@(*) begin
            case (current_state)
            IDLE           :begin
                if(iic_done)
                next_state = IDLE;                
                else if(iic_start_flag)
                next_state=SEND_ADDR_PHASE;
                else
                next_state = IDLE;
            end                
            SEND_ADDR_PHASE:begin
//                if((ack_check_flag&&(iic_ack)))   //检测从机是否产生应答,未产生，则跳转到空闲态，发送结束
//                begin   
//                   next_state = FAIL;        
//                 end   
//                else
                case (addr_mode)                
                    0:begin   //0代表寄存器地址只有一位，写地址阶段只要计数2次
                        if((send_addr_op_cnt==2)&& reg_trans_done_flag[1])begin
                            if(iic_rw)   //1为读，0为写
                            next_state=READ_PHASE;
                            else
                            next_state=WRITE_PHASE;
                    end
                        else begin
                            next_state=SEND_ADDR_PHASE;  // 不满足条件时保持,关键，补全默认条件
                        end
                    end
                    1:begin   //1代表寄存器地址有俩位，写地址阶段只要计数3次
                        if((send_addr_op_cnt==3)&& reg_trans_done_flag[1])begin      //这里是超级大bug！原来是trans_done_flag，单独调试无问题，但是用以SCCB则状态无法调整！！！
                            if(iic_rw)   //1为读，0为写
                            next_state=READ_PHASE;
                            else
                            next_state=WRITE_PHASE;                            
                        end
                        else begin
                            next_state=SEND_ADDR_PHASE;  // 不满足条件时保持
                        end
                    end
                    default :begin
                        next_state=SEND_ADDR_PHASE;
                    end
                endcase
            end
            READ_PHASE     :begin
//              if((w_r_op_cnt==0)&&(ack_check_flag&&(iic_ack)))
//              begin   
//                  next_state = FAIL;        
//               end                    
//              else 
                if(w_r_op_cnt==(byte_num+1))
                    next_state=DONE;
                else
                    next_state=READ_PHASE;
            end
            WRITE_PHASE    :begin
//              if((ack_check_flag&&(iic_ack)))   //检测从机是否产生应答,未产生，则跳转到空闲态，发送结束
//              begin   
//                    next_state = FAIL;        
//               end                 
//              else 
                if(w_r_op_cnt==(byte_num))
                    next_state=DONE;
                else
                    next_state=WRITE_PHASE;
            end
            DONE           :begin
                next_state = IDLE;
            end
            FAIL           :begin
                next_state = IDLE;
            end                
            default:
                next_state = IDLE;
            endcase
    end


// ========== 第三段：输出逻辑 ==========
    always@(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            iic_done<=0;
            iic_fail<=0;
            wr_data_req<=0;
            iic_tx_data<=8'b0;
            iic_cmd<=6'b0;
            iic_bit_start<=0;

        end
        else begin
              
            case (current_state)
            IDLE           :begin
            iic_done<=0;
            iic_fail<=0;
            wr_data_req<=0;

            iic_cmd<=0;
            iic_bit_start<=0;
            iic_tx_data<=8'b0;

            end
            SEND_ADDR_PHASE:begin
                case ({send_addr_op_cnt,addr_mode}) //组合了addr_mode,列出所有情况
                        3'b000:begin  //0
                        iic_cmd<=STA|WR;
                        iic_bit_start<=1;
                        iic_tx_data<={device_addr,1'b0};

                            if(ack_check_flag) begin             //需要提前给命令，否则旧命令STA|WR会导致再发一次起始位
                            iic_cmd<=WR; 
                            iic_bit_start<=0;
                            end
                        end
                        3'b010:begin  //1
                        iic_cmd<=WR;
                        iic_bit_start<=1;
                        iic_tx_data<=reg_addr[7:0];

                            if(ack_check_flag) begin    //需要提前给命令,否则无法正确发出重开始信号
                                if(iic_rw)begin         //若为读操作，则第一位是带起始的写
                                    iic_cmd<=STA|WR;
                                    iic_bit_start<=0;
                                end
                                else begin             ////若为写操作
                                    iic_bit_start<=0;
                                    if(byte_num==1)
                                        iic_cmd<=WR|STO;
                                    else
                                    iic_cmd<=WR;                  
                                end
                        end

                        end
//                        3'b100:begin end //2                        
//                        3'b110:begin end //3

                        3'b001:begin  //0                       
                        iic_cmd<=STA|WR;
                        iic_tx_data<={device_addr,1'b0};
                        iic_bit_start<=1;

                            if(ack_check_flag) begin              
                            iic_cmd<=WR;
                            iic_bit_start<=0;
                        end
                        end
                        3'b011:begin  //1
                        iic_cmd<=WR;
                        iic_tx_data<=reg_addr[15:8];
                        iic_bit_start<=1;

                            if(ack_check_flag) begin              
                            iic_cmd<=WR;
                            iic_bit_start<=0;
                            end
                        end
                        3'b101:begin  //2
                        iic_cmd<=WR;
                        iic_tx_data<=reg_addr[7:0];
                        iic_bit_start<=1;

                            if(ack_check_flag) begin    //需要提前给命令,否则无法正确发出重开始信号
                                if(iic_rw)begin
                                    iic_cmd<=STA|WR;        //若为读操作，则第一位是带起始的写
                                    iic_bit_start<=0;
                                end
                                else begin
                                    iic_bit_start<=0;
                                    if(byte_num==1)
                                        iic_cmd<=WR|STO;
                                    else
                                    iic_cmd<=WR;                               
                                end
                        end                           
                        end
//                        111:begin end //3
                    default: begin
                        iic_cmd<=iic_cmd;
                        iic_tx_data<=iic_tx_data;
                        iic_bit_start<=iic_bit_start;

                    end
                endcase
            end
            READ_PHASE     :begin
                if(reg_trans_done_flag[2])    //给出第一次iic的起始
                iic_bit_start<=1;

                else if(w_r_op_cnt==0)begin    //连续读第一段，写入
                    iic_tx_data<={device_addr,1'b1}; //写入从机地址，改变数据方向为读
                    if(ack_check_flag)begin
                        iic_bit_start<=0;
                            if(byte_num==1)          //解决读取长度为1的边界问题
                            iic_cmd<=RD|NACK|STO;
                            else
                            iic_cmd<=RD|ACK;

                    end
                end
                else if(w_r_op_cnt!=0&&(w_r_op_cnt<(byte_num-1)))begin
                        iic_cmd<=RD|ACK;
                        iic_bit_start<=0;
                end

                else if((w_r_op_cnt==byte_num-1)&&ack_gen_flag)begin   //ack_gen_flag唯一的作用就是在产生最后一位读的时候，提前改变命令为iic_cmd<=RD|NACK|STO;
                        iic_cmd<=RD|NACK|STO;
                        iic_bit_start<=0;                            
                end
                else begin
                    iic_cmd<=iic_cmd;
                    iic_bit_start<=0;
                end
            end
            WRITE_PHASE: begin
                if(reg_trans_done_flag[2]) begin
                    iic_bit_start <= 1;         // 启动第一个写
                    iic_tx_data <= wr_data_r_r; // 第一个数据
                end
                
                else if(trans_done && (w_r_op_cnt<(byte_num-1))) begin
                    wr_data_req <= 1;           // 请求下一个数据
                    if(w_r_op_cnt<(byte_num-2)) begin
                        iic_cmd <= WR;          // 中间字节
                    end
                    else if(w_r_op_cnt==(byte_num-2)) begin
                        iic_cmd <= WR|STO;      // 最后一个字节
                    end                    
                end
                    else begin
                        iic_cmd<=iic_cmd;
                        iic_bit_start<=0;
                        wr_data_req<=0; 
                    end 
            end

                        DONE           :begin
                        iic_done<=1;
                        iic_bit_start<=0;
                        iic_cmd<=0;
                        end    
                        FAIL           :begin
                        iic_done<=1;
                        iic_fail<=1;
                        iic_bit_start<=0;
                        iic_cmd<=0;
                        end               
                        default:begin
                            iic_done<=0;
                            wr_data_req<=0;
                            iic_fail<=0;
                            iic_cmd<=6'b0;
            //               iic_bit_start<=0;
                            iic_tx_data<=8'b0;
            end
                
            endcase
        end
    end

//=================================================
//单独处理读出数据和读出数据有效信号
always @(posedge clk ) begin
    if(~rst_n)begin
        rd_data<=0;
        rd_data_vld<=0;
    end

    if(trans_done&&(current_state==READ_PHASE)&&w_r_op_cnt!=0)begin
        rd_data<=iic_rx_data;
        rd_data_vld<=trans_done;
    end
    else  begin
        rd_data<=rd_data;
        rd_data_vld<=0;
    end
        
end

//=================================================
//例化基本iic单元


iic_bit_shift
#(
   .SYS_CLOCK      (SYS_CLOCK        ),
   .SCL_CLOCK      (SCL_CLOCK        )
)
 u_iic_bit_shift(
// ==================== 全局信号 ====================
    .clk                                (clk                       ),// 主时钟 50Mhz
    .rst_n                              (rst_n                     ),// 异步低有效复位，同步化后使用
// ==================== 控制接口 ====================
    .iic_done                           (trans_done                ),// 发送完成时给出的脉冲信号
    .iic_busy                           (iic_busy                  ),// 模块忙标志，为1时忽略新的iic_start
    .iic_start                          (iic_bit_start             ),// 开始发送iic命令
// ==================== 协议参数接口 ====================
    .iic_cmd                            (iic_cmd                   ),// 用户操作命令
    .iic_tx_data                        (iic_tx_data               ),// 8位数据，要转化为iic总线发走
    .iic_rx_data                        (iic_rx_data               ),// 总线上接受到的数据，转化为8位数输出
    .iic_ack                            (iic_ack                   ),// 应答信号，本模块为最基础模块，不做判断，送出去让外部模块判断
    .ack_check_flag                     (ack_check_flag            ),// 外部检测应答信号，产生应答位后置1，帮助外部模块判断应答位
    .ack_gen_flag                       (ack_gen_flag            ),// 外部检测应答信号，产生应答位后置1，帮助外部模块判断应答位
// ==================== 物理层接口(iic) ====================顶层使用IOBUF例化
    .iic_sclk                           (iic_sclk                  ),// 串行时钟线
    .iic_sdat_o                         (iic_sdat_o                ),// iic串行数据线输出
    .iic_sdat_i                         (iic_sdat_i                ),// iic串行数据线输入
    .iic_sdat_t                         (iic_sdat_t                )// 三态控制，0可输出，1为高阻，释放总线
);


endmodule
