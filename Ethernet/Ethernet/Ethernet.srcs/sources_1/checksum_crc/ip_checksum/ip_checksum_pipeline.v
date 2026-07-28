//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: KongDeJing
// 
// Create Date: 2026/05/06 17:41:11
// Design Name: 
// Module Name: ip_checksum
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 流水线计算ip_checksum，提高效率
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ip_checksum_pipeline (
    // ==================== 全局信号 ====================
    input                               clk                        ,
    input                               rst_n                      ,
    
    // ==================== 并行输入接口 ====================
    // 整个IP头
    input                [   7: 0]      ip_hdr_0                   ,// 字节0: 版本+IHL
    input                [   7: 0]      ip_hdr_1                   ,// 字节1: 服务类型
    input                [   7: 0]      ip_hdr_2                   ,// 字节2: 总长度高8位
    input                [   7: 0]      ip_hdr_3                   ,// 字节3: 总长度低8位
    input                [   7: 0]      ip_hdr_4                   ,// 字节4: 标识高8位
    input                [   7: 0]      ip_hdr_5                   ,// 字节5: 标识低8位
    input                [   7: 0]      ip_hdr_6                   ,// 字节6: 标志+片偏移高8位
    input                [   7: 0]      ip_hdr_7                   ,// 字节7: 标志+片偏移低8位
    input                [   7: 0]      ip_hdr_8                   ,// 字节8: TTL
    input                [   7: 0]      ip_hdr_9                   ,// 字节9: 协议
    // 字节10-11: 校验和字段（计算时视为0，不输入）
    input                [   7: 0]      ip_hdr_12                  ,// 字节12: 源IP[31:24]
    input                [   7: 0]      ip_hdr_13                  ,// 字节13: 源IP[23:16]
    input                [   7: 0]      ip_hdr_14                  ,// 字节14: 源IP[15:8]
    input                [   7: 0]      ip_hdr_15                  ,// 字节15: 源IP[7:0]
    input                [   7: 0]      ip_hdr_16                  ,// 字节16: 目的IP[31:24]
    input                [   7: 0]      ip_hdr_17                  ,// 字节17: 目的IP[23:16]
    input                [   7: 0]      ip_hdr_18                  ,// 字节18: 目的IP[15:8]
    input                [   7: 0]      ip_hdr_19                  ,// 字节19: 目的IP[7:0]
    
    // ==================== 控制信号及输出结果 ====================    
    input                               calc_start                 ,// 脉冲,启动计算
    output reg                          calc_busy                  ,//计算忙，忙时忽略新的启动信号
    output reg           [  15: 0]      checksum                   ,// 校验和
    output reg                          checksum_valid              // 校验和有效
);


//=================================================
//产生calc_start的上升沿脉冲
wire calc_start_latch_pluse;
wire calc_start_pluse;
reg [1:0]calc_start_reg;
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                                                             
               calc_start_reg<=3'b0;                                                  
            else begin
                calc_start_reg[0]<=calc_start;
                calc_start_reg[1]<=calc_start_reg[0];
            end                                                 
        end       
                    
assign calc_start_latch_pluse=({calc_start_reg[0],calc_start}==2'b01);  //锁存沿与上升沿一个周期有效                             
assign calc_start_pluse=(calc_start_reg==2'b01);                        //脉冲沿在下一个周期有效
     
//=================================================
//在检测到开始时锁存需要计算的值
reg [   7: 0]      ip_hdr_0_r ;  
reg [   7: 0]      ip_hdr_1_r ;  
reg [   7: 0]      ip_hdr_2_r ;     reg [   7: 0]      ip_hdr_12_r;  
reg [   7: 0]      ip_hdr_3_r ;     reg [   7: 0]      ip_hdr_13_r;  
reg [   7: 0]      ip_hdr_4_r ;     reg [   7: 0]      ip_hdr_14_r;  
reg [   7: 0]      ip_hdr_5_r ;     reg [   7: 0]      ip_hdr_15_r;  
reg [   7: 0]      ip_hdr_6_r ;     reg [   7: 0]      ip_hdr_16_r;  
reg [   7: 0]      ip_hdr_7_r ;     reg [   7: 0]      ip_hdr_17_r;  
reg [   7: 0]      ip_hdr_8_r ;     reg [   7: 0]      ip_hdr_18_r;  
reg [   7: 0]      ip_hdr_9_r ;     reg [   7: 0]      ip_hdr_19_r;  


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ip_hdr_0_r <=8'b0;
        ip_hdr_1_r <=8'b0;
        ip_hdr_2_r <=8'b0;              ip_hdr_12_r<=8'b0;
        ip_hdr_3_r <=8'b0;              ip_hdr_13_r<=8'b0;
        ip_hdr_4_r <=8'b0;              ip_hdr_14_r<=8'b0;
        ip_hdr_5_r <=8'b0;              ip_hdr_15_r<=8'b0;
        ip_hdr_6_r <=8'b0;              ip_hdr_16_r<=8'b0;
        ip_hdr_7_r <=8'b0;              ip_hdr_17_r<=8'b0;
        ip_hdr_8_r <=8'b0;              ip_hdr_18_r<=8'b0;
        ip_hdr_9_r <=8'b0;              ip_hdr_19_r<=8'b0;

    end
    else if (calc_start_latch_pluse) begin
        ip_hdr_0_r <= ip_hdr_0 ;
        ip_hdr_1_r <= ip_hdr_1 ;
        ip_hdr_2_r <= ip_hdr_2 ;        ip_hdr_12_r<=ip_hdr_12;
        ip_hdr_3_r <= ip_hdr_3 ;        ip_hdr_13_r<=ip_hdr_13;
        ip_hdr_4_r <= ip_hdr_4 ;        ip_hdr_14_r<=ip_hdr_14;
        ip_hdr_5_r <= ip_hdr_5 ;        ip_hdr_15_r<=ip_hdr_15;
        ip_hdr_6_r <= ip_hdr_6 ;        ip_hdr_16_r<=ip_hdr_16;
        ip_hdr_7_r <= ip_hdr_7 ;        ip_hdr_17_r<=ip_hdr_17;
        ip_hdr_8_r <= ip_hdr_8 ;        ip_hdr_18_r<=ip_hdr_18;
        ip_hdr_9_r <= ip_hdr_9 ;        ip_hdr_19_r<=ip_hdr_19; 
       
    end
end    
// ==================== 第1级流水线======================================
// 分组加法 
reg [19:0] sum1_grp0, sum1_grp1, sum1_grp2, sum1_grp3;//分为4组计算
reg        calc_start_d1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        {sum1_grp0, sum1_grp1, sum1_grp2, sum1_grp3} <= {4{20'h0}};
        calc_start_d1 <= 1'b0;
    end
    else if (calc_start_pluse&&~calc_busy) begin     //当不在计算状态下，且上升沿信号脉冲有效时才启动一次发送
        // 分组0：固定头部（字0-1）
        // 字0 = {字节0, 字节1}, 字1 = {字节2, 字节3}
        // 扩展4位到20位，防止2个16位字相加溢出（最大131070）
        sum1_grp0 <= {4'h0, {ip_hdr_0_r, ip_hdr_1_r}} +  // 字0
                     {4'h0, {ip_hdr_2_r, ip_hdr_3_r}};   // 字1
        
        // 分组1：标识与分片（字2-3）
        sum1_grp1 <= {4'h0, {ip_hdr_4_r, ip_hdr_5_r}} +  // 字2
                     {4'h0, {ip_hdr_6_r, ip_hdr_7_r}};   // 字3
        
        // 分组2：协议字段（字4-5）
        // 字4 = {字节8, 字节9}, 字5 = 0（校验和字段）
        sum1_grp2 <= {4'h0, {ip_hdr_8_r, ip_hdr_9_r}} +  // 字4
                     20'h0;                          // 字5（ip校验和字段，视为0）
        
        // 分组3：IP地址（字6-9）→ 4个16位字相加
        // 最大和 = 65535×4 = 262140，需18位，20位有余量
        sum1_grp3 <= {4'h0, {ip_hdr_12_r, ip_hdr_13_r}} +  // 字6: 源IP高16位
                     {4'h0, {ip_hdr_14_r, ip_hdr_15_r}} +  // 字7: 源IP低16位
                     {4'h0, {ip_hdr_16_r, ip_hdr_17_r}} +  // 字8: 目的IP高16位
                     {4'h0, {ip_hdr_18_r, ip_hdr_19_r}};   // 字9: 目的IP低16位
        
        calc_start_d1 <= 1'b1;
    end
    else begin
        calc_start_d1 <= 1'b0;
    end
end

// ==================== 第2级流水====================
// 将4个分组结果两两合并
    reg                  [  23: 0]      sum2_grp0,               sum2_grp1;// 24位：预留合并空间
    reg                                 calc_start_d2              ;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        {sum2_grp0, sum2_grp1} <= {2{24'h0}};//重复运算符
        calc_start_d2 <= 1'b0;
    end
    else if (calc_start_d1) begin
        // 合并前两组：分组0 + 分组1
        sum2_grp0 <= {4'h0, sum1_grp0} + {4'h0, sum1_grp1};//20位补齐到24位
        
        // 合并后两组：分组2 + 分组3
        sum2_grp1 <= {4'h0, sum1_grp2} + {4'h0, sum1_grp3};
        
        calc_start_d2 <= 1'b1;
    end
    else begin
        calc_start_d2 <= 1'b0;
    end
end

// ==================== 第3级流水线 ====================
// 完成所有分组的最终求和
    reg                  [  31: 0]      sum3_total                 ;// 32位：容纳最终和
    reg                                 calc_start_d3              ;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sum3_total <= 32'h0;
        calc_start_d3 <= 1'b0;
    end
    else if (calc_start_d2) begin
        // 合并所有分组
        sum3_total <= {8'h0, sum2_grp0} + {8'h0, sum2_grp1};//24位补齐到32位
        
        calc_start_d3 <= 1'b1;
    end
    else begin
        calc_start_d3 <= 1'b0;
    end
end

// ==================== 第4级流水线：进位折叠 ====================
// 将高16位进位加到低16位
    reg                  [  31: 0]      sum4_folded                ;
    reg                                 calc_start_d4              ;
    reg                                 need_second_fold           ;// 标志是否需要二次折叠

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sum4_folded <= 32'h0;
        calc_start_d4 <= 1'b0;
        need_second_fold <= 1'b0;
    end
    else if (calc_start_d3) begin
        // 第一次进位折叠：高16位 + 低16位
        sum4_folded <= {16'h0, sum3_total[31:16]} + {16'h0, sum3_total[15:0]};

        // 如果 sum4_folded[31:16] != 0，需要再次折叠
        need_second_fold <= |sum4_folded[31:16];
        
        calc_start_d4 <= 1'b1;
    end
    else begin
        calc_start_d4 <= 1'b0;
    end
end

// ==================== 第5级流水线：最终计算 ====================
// 二次折叠判断 + 取反输出
    reg                  [  15: 0]      checksum_pre               ;
    reg                                 checksum_valid_pre         ;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        checksum_pre <= 16'h0;
        checksum_valid_pre <= 1'b0;
    end
    else if (calc_start_d4) begin
 //=================================================产生校验和数据       
        if (need_second_fold) begin
            // 需要二次折叠：高16位仍有值
            // 二次折叠：高16位 + 低16位
            checksum_pre <= ~({16'h0, sum4_folded[31:16]} + 
                              {16'h0, sum4_folded[15:0]});
        end
        else begin
            // 无需二次折叠，直接取反
            checksum_pre <= ~sum4_folded[15:0];
        end
 //=================================================产生校验和有效数据信号  

        checksum_valid_pre <= 1'b1;
    end
    else begin
        checksum_valid_pre <= 1'b0;
    end
end

// ==================== 输出寄存器 ====================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        checksum <= 16'h0;
        checksum_valid <= 1'b0;
    end
    else begin
        checksum <= checksum_pre;
        checksum_valid <= checksum_valid_pre;
    end
end

//=================================================
//产生calc_busy
    always @(posedge clk or negedge rst_n)           
        begin                                        
            if(!rst_n)                               
                calc_busy<=0;  
            else if({checksum_valid,checksum_valid_pre}==2'b01)//当产生了checksum_calid的上升沿时，代表一次计算已经完成
                calc_busy<=0;                                                                  
            else if(calc_start_pluse&&!calc_busy)
                calc_busy<=1;                                                                                                     
        end
     

endmodule