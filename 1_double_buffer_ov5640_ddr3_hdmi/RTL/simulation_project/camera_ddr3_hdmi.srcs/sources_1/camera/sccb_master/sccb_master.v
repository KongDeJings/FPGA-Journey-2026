`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing 
// 
// Create Date: 2026/05/12 17:10:27
// Design Name: 
// Module Name: sccb_master
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description:     调用iic底层模块，rom查找表，完成摄像头初始化配置,输出配置有效/无效信号
// 代码严禁出现魔数！
//////////////////////////////////////////////////////////////////////////////////
module sccb_master
#(
    parameter                           IMAGE_TYPE                  = 0                    ,//0:RGB   1：JPEG
    parameter                           IMAGE_WIDTH                 = 640                  ,//图片宽度
    parameter                           IMAGE_HEIGHT                = 480                  ,//图片高度(≤720)
    parameter                           IMAGE_FLIP                  = 0                    ,//0:不翻转,1:上下翻转
    parameter                           IMAGE_MIRROR                = 0                    ,//0:不镜像,1:左右镜像 
    parameter                           SYS_CLOCK                   = 50_000_000           ,//系统时钟频率
    parameter                           SCL_CLOCK                   = 80_000               //希望SCCB跑多少频率。SCCB 时钟频率是否在 100kHz 以内（OV5640 要求）

)
(
    // ==================== 全局信号 ====================
    input                               clk                        ,
    input                               rst_n                      ,

    // ==================== camera参数接口 ====================	
    output reg                          camera_init_done           ,// 配置完成标志（做完变1）
    output reg                          camera_init_fail           ,// 配置失败（做完变1）
    output reg                          camera_rst_n               ,// 给摄像头的复位信号
    output                              camera_pwdn                ,// 摄像头省电模式（这里直接关掉，为0）
    // ==================== 物理层接口(iic) ====================
    output                              iic_sclk                   ,
    inout                               iic_sdat                       
    );

//===============================================================================================================
//本地参数及接口定义、连线
	localparam         OV5640_ID    =        7'h3C                               ,     //摄像头器件地址
                       CNTM_25ms    =        25*1000_000/(1000_000_000/SYS_CLOCK),     //25ms延时计数器计数数
                       CNTM_3ms     =         3*1000_000/(1000_000_000/SYS_CLOCK),     //5ms延时计数器计数数
                    RGB_LUT_SIZE    =        252                                 ,
                    JPEG_LUT_SIZE   =        250                                 ,
                 ROM_ADDR_WIDTH     =         8                                  ;     //rom查找表地址宽度

	localparam         IDLE        = 5'b00001             ,     
                       S_RD_ROM    = 5'b00010             ,     
                       S_START_IIC = 5'b00100             ,
                       FAIL        = 5'b01000             ,     
                       DONE        = 5'b10000             ;     

    localparam 
                    OV5640_NORMAL_MIRROR  = 8'h40,   // 正常模式
                    OV5640_FLIP_MIRROR    = 8'h47,   // 翻转模式
                    OV5640_MIRROR_EN      = 4'h7,    // 镜像使能
                    OV5640_MIRROR_DIS     = 4'h0;    // 镜像禁止

              
   // ==================== 寄存器地址
    wire                 [  15: 0]      reg_addr                   ;
   // ==================== 读写信号
    wire                 [   7: 0]      wr_data                    ;// 写数据
    wire                                wr_data_req                ;// 告诉外界，写数据已经发完，把剩下的数据接着送进来
    wire                 [   7: 0]      rd_data                    ;// 读出的数据(本例用不上！)
    wire                                rd_data_vld                ;// 读数据有效标志，这是一个脉冲信号，只保持一个周期
   // ==================== 控制信号
    reg                                 iic_start                  ;// 总启动信号
    wire                                iic_done                   ;//配置完一个寄存器后来得脉冲
    wire                                iic_fail                   ;
   // ==================== 对外信号（SCCB）
//    wire                                iic_sdat_o                 ;
//    wire                                iic_sdat_t                 ;
//    wire                                iic_sdat_i                 ;
   // ==================== 状态机
    reg                  [   3: 0]      current_state              ;
    reg                  [   3: 0]      next_state                 ;
  
    wire                 [  23: 0]      rom_data                   ;//查找表读取的rom数据      
    reg                  [ROM_ADDR_WIDTH-1: 0]send_cnt                   ;//记录目前操作到哪一个寄存器（共lut_size大小），同时作为rom地址
    wire                 [($clog2(RGB_LUT_SIZE)-1): 0]lut_size                   ;//指定查找表大小，RGB252,JPEG250(一共要配置多少个寄存器)

    assign                              camera_pwdn                 = 0                    ;//关掉摄像头省电模式
    assign                              reg_addr                    = rom_data[23:8]       ;
    assign                              wr_data                     = rom_data[7:0]        ;


//=================================================
//上电延时复位操作
    reg                  [($clog2(CNTM_25ms)-1): 0]delay_cnt       ;//上电复位计数器
    reg                                 send_en                    ;//复位结束，可以开始写入。使能

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        delay_cnt <= 0;
        camera_rst_n <= 0;
        send_en <= 0;
    end
    else begin
        if(delay_cnt < CNTM_25ms)
            delay_cnt <= delay_cnt + 1;

        // 控制camera_rst_n
        if(delay_cnt < CNTM_3ms) 
            camera_rst_n <= 0;  // 前5ms：复位低电平
        else 
            camera_rst_n <= 1;  // 之后：释放复位,再保持25ms再发送
        
        // 控制send_en
        if(delay_cnt >= CNTM_25ms-1)
            send_en <= 1;  // 25ms后：使能发送
        else if(iic_fail)
            send_en <= 0;
        else
            send_en <= 0;

    end
end   
//=================================================
//产生send_en_flag

    reg                  [   1: 0]      reg_send_en_flag         ;
    wire                                send_en_flag             ;
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                reg_send_en_flag<=2'b0;                                                                                                                    
            else
                reg_send_en_flag[0]<=send_en;
                reg_send_en_flag[1]<=reg_send_en_flag[0];                                     
        end                                          
assign  send_en_flag= (reg_send_en_flag==2'b01);
//=================================================
//在RD_ROM状态保持一个周期,保证数据能读取成功
reg rom_rd_vld;  // 用来延时 1 拍

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rom_rd_vld <= 0;
    else if(current_state == S_RD_ROM)
        rom_rd_vld <= 1;  // 进入RD_ROM状态后，下一个周期变 1
    else
        rom_rd_vld <= 0;
end

//=================================================
//产生初始化失败标志（持续拉高）
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                camera_init_fail<=0;                                           
            else if(iic_fail) 
                camera_init_fail<=iic_fail;                                                               
            else
                camera_init_fail<=camera_init_fail;                                     
        end        
//=================================================
//产生初始化camera_init_done                                
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                camera_init_done<=0;                                           
            else if(iic_done&&~iic_fail&&(send_cnt==lut_size-1)) 
                camera_init_done<=1;                                                               
            else
                camera_init_done<=camera_init_done;                                     
        end
//=================================================
//初始化寄存器状态机
//======================== 第一段：时序逻辑 状态寄存 ========================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

//======================== 第二段：组合逻辑 状态转移 ========================
always @(*) begin
    case(current_state)
        IDLE: begin
            if(send_en_flag)
                next_state = S_RD_ROM;
            else
                next_state = IDLE;
        end
        
        S_RD_ROM: begin
            if(rom_rd_vld)          // 等待标志变 1，保证rom数据读取正确
                next_state = S_START_IIC;
            else
                next_state = S_RD_ROM;  // 否则停留

        end
        
        S_START_IIC: begin
            if(iic_fail)
                next_state = FAIL;
             if(iic_done&&~iic_fail&&(send_cnt<lut_size-1))
                next_state =S_RD_ROM;   //未传输完，继续读ROM
            else if(iic_done&&~iic_fail&&(send_cnt==lut_size-1))
                next_state =DONE;
            else
                next_state=S_START_IIC;
        end
        FAIL: begin
            next_state = IDLE;
        end
        
        DONE: begin
            next_state = IDLE;
        end
        
        default:
            next_state = IDLE;
    endcase
end

//======================== 第三段：时序逻辑 输出控制 ========================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        // 复位输出初始化
        send_cnt<=0;
        iic_start <=0;
    end
    else begin
        case(current_state)
            IDLE: begin
                send_cnt<=send_cnt;
                iic_start <=0;                
            end
            S_RD_ROM: begin
                if(send_en)
                iic_start <=1;                 
            end
            
            S_START_IIC: begin

                if(send_en)begin
                  if( iic_done&&~iic_fail&&(send_cnt<lut_size))begin
                        send_cnt<=send_cnt+1;
                        iic_start <=0;  
                    end
              
            end
            end
            FAIL: begin
                send_cnt<=send_cnt;
                iic_start <=0;                   
            end
            
            DONE: begin
                send_cnt<=send_cnt;
                iic_start <=0;                    
            end
        endcase
    end
end                              
//=================================================
//产生双向外部引脚
IOBUF #(
    .DRIVE                              (12                        ),// 输出驱动强度
    .IBUF_LOW_PWR                       ("TRUE"                    ),// 输入缓冲器低功耗模式
    .IOSTANDARD                         ("DEFAULT"                 ),// IO电平标准
    .SLEW                               ("SLOW"                    ) // 压摆率控制
) IOBUF_inst (
    .O                                  (iic_sdat_i                ),// 输出到FPGA内部逻辑
    .IO                                 (iic_sdat                  ),// 双向外部引脚（接顶层port）
    .I                                  (iic_sdat_o                ),// 从FPGA内部来
    .T                                  (iic_sdat_t                ) // 三态控制
);

//=================================================
//例化iic_control，设置为一次只写1个数据的模式

iic_control
#(
   .SYS_CLOCK      (SYS_CLOCK        ),
   .SCL_CLOCK      (SCL_CLOCK        )
)
 u_iic_control(
    .clk                                (clk                       ),
    .rst_n                              (rst_n                     ),
// 控制启动
    .iic_start                          (iic_start                 ),// 总启动信号
    .iic_rw                             (0                         ),// 读写控制 1=读 0=写
    .byte_num                           (1                         ),// 连续读写字节数（核心！）
// 配置接口
    .reg_addr                           (reg_addr                  ),// 寄存器地址
    .addr_mode                          (1                         ),// 0=只发低8位地址[7:0]， 1=16位地址，先发[15:8],再发[7:0]
    .device_addr                        (OV5640_ID                 ),// 从机地址， device_addr 只用 7 位有效，bit0 指示读写
// 数据接口
    .wr_data                            (wr_data                   ),// 写数据
    .wr_data_req                        (wr_data_req               ),// 告诉外界，写数据已经发完，把剩下的数据接着送进来
    .rd_data                            (rd_data                   ),// 读出的数据
    .rd_data_vld                        (rd_data_vld               ),// 读数据有效标志，这是一个脉冲信号，只保持一个周期
// 状态标志
    .iic_done                           (iic_done                  ),// 一次传输完成，一次传输结束后才发送
    .iic_fail                           (iic_fail                  ),// 一次传输完成，一次传输结束后才发送
// IIC 物理总线
    .iic_sclk                           (iic_sclk                  ),// 串行时钟线
    .iic_sdat_o                         (iic_sdat_o                ),// iic串行数据线输出
    .iic_sdat_t                         (iic_sdat_t                ),// 三态控制，0可输出，1为高阻，释放总线
    .iic_sdat_i                         (iic_sdat_i                )// iic串行数据线输入
);

//=================================================
//generate 条件编译,根据IMAGE_TYPE的值来选择输出
	
	generate
	if(IMAGE_TYPE == 0)//RGB
		begin
			assign lut_size = RGB_LUT_SIZE;
			case ({IMAGE_FLIP[0], IMAGE_MIRROR[0]})
				2'b00:
					begin
                        ov5640_init_table_rgb#(
                            .DATA_WIDTH                         (24                        ),
                            .ADDR_WIDTH                         (8                         ),
                            .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
                            .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
                            .IMAGE_FLIP                         (OV5640_NORMAL_MIRROR      ),
                            .IMAGE_MIRROR                       (OV5640_MIRROR_EN          ) 
                        )
                         u_ov5640_init_table_rgb(
                            .clk                                (clk                       ),
                            .addr                               (send_cnt                  ),
                            .rom_data                           (rom_data                  ) 
                        );
					end
				2'b01:
					begin
                        ov5640_init_table_rgb#(
                            .DATA_WIDTH                         (24                        ),
                            .ADDR_WIDTH                         (8                         ),
                            .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
                            .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
                            .IMAGE_FLIP                         (OV5640_NORMAL_MIRROR      ),
                            .IMAGE_MIRROR                       (OV5640_MIRROR_DIS         ) 
                        )
                         u_ov5640_init_table_rgb(
                            .clk                                (clk                       ),
                            .addr                               (send_cnt                  ),
                            .rom_data                           (rom_data                  ) 
                        );
					end
				2'b10:
					begin
                        ov5640_init_table_rgb#(
                            .DATA_WIDTH                         (24                        ),
                            .ADDR_WIDTH                         (8                         ),
                            .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
                            .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
                            .IMAGE_FLIP                         (OV5640_FLIP_MIRROR        ),
                            .IMAGE_MIRROR                       (OV5640_MIRROR_EN          ) 
                        )
                         u_ov5640_init_table_rgb(
                            .clk                                (clk                       ),
                            .addr                               (send_cnt                  ),
                            .rom_data                           (rom_data                  ) 
                        );
					end
				2'b11:
					begin
                        ov5640_init_table_rgb#(
                            .DATA_WIDTH                         (24                        ),
                            .ADDR_WIDTH                         (8                         ),
                            .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
                            .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
                            .IMAGE_FLIP                         (OV5640_FLIP_MIRROR        ),
                            .IMAGE_MIRROR                       (OV5640_MIRROR_DIS         ) 
                        )
                         u_ov5640_init_table_rgb(
                            .clk                                (clk                       ),
                            .addr                               (send_cnt                  ),
                            .rom_data                           (rom_data                  ) 
                        );
					end
			endcase
		end
	else //IMAGE_TYPE == JPEG
		begin
			assign lut_size = JPEG_LUT_SIZE;
			case ({IMAGE_FLIP[0], IMAGE_MIRROR[0]})
				2'b00:
					begin
                        ov5640_init_table_jpeg#(
                            .DATA_WIDTH                         (24                        ),
                            .ADDR_WIDTH                         (8                         ),
                            .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
                            .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
                            .IMAGE_FLIP                         (OV5640_NORMAL_MIRROR      ),
                            .IMAGE_MIRROR                       (OV5640_MIRROR_EN          ) 
                        )
                         u_ov5640_init_table_jpeg(
                            .clk                                (clk                       ),
                            .addr                               (send_cnt                  ),
                            .rom_data                           (rom_data                  ) 
                        );
					end
				2'b01:
					begin
                        ov5640_init_table_jpeg#(
                            .DATA_WIDTH                         (24                        ),
                            .ADDR_WIDTH                         (8                         ),
                            .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
                            .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
                            .IMAGE_FLIP                         (OV5640_NORMAL_MIRROR      ),
                            .IMAGE_MIRROR                       (OV5640_MIRROR_DIS         ) 
                        )
                         u_ov5640_init_table_jpeg(
                            .clk                                (clk                       ),
                            .addr                               (send_cnt                  ),
                            .rom_data                           (rom_data                  ) 
                        );
					end
				2'b10:
					begin
                        ov5640_init_table_jpeg#(
                            .DATA_WIDTH                         (24                        ),
                            .ADDR_WIDTH                         (8                         ),
                            .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
                            .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
                            .IMAGE_FLIP                         (OV5640_FLIP_MIRROR        ),
                            .IMAGE_MIRROR                       (OV5640_MIRROR_EN          ) 
                        )
                         u_ov5640_init_table_jpeg(
                            .clk                                (clk                       ),
                            .addr                               (send_cnt                  ),
                            .rom_data                           (rom_data                  ) 
                        );
					end
				2'b11:
					begin
                        ov5640_init_table_jpeg#(
                            .DATA_WIDTH                         (24                        ),
                            .ADDR_WIDTH                         (8                         ),
                            .IMAGE_WIDTH                        (IMAGE_WIDTH               ),
                            .IMAGE_HEIGHT                       (IMAGE_HEIGHT              ),
                            .IMAGE_FLIP                         (OV5640_FLIP_MIRROR        ),
                            .IMAGE_MIRROR                       (OV5640_MIRROR_DIS         ) 
                        )
                         u_ov5640_init_table_jpeg(
                            .clk                                (clk                       ),
                            .addr                               (send_cnt                  ),
                            .rom_data                           (rom_data                  ) 
                        );
					end
			endcase
		end
	endgenerate
endmodule
