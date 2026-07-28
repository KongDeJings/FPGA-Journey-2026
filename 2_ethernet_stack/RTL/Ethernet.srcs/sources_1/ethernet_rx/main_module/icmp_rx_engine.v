`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/01 17:41:45
// Design Name: 
// Module Name: icmp_rx_engine
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 解析icmp包中的内容，提供fifo写入信号，外面的模块
// Additional Comments:
// 代码中严禁出现魔数
//////////////////////////////////////////////////////////////////////////////////

module icmp_rx_engine
#(
    parameter                           FPGA_MAC                    = 48'h020A_353C_4D5E   ,  // MAC 02-0A-35-3C-4D-5E 这是xilinx专用mac，可被wireshark识别到
    parameter                           ICMP_ECHO_REQUEST           = 8'h08                ,    //收到别人的请求是0x08
    parameter                           ICMP_ECHO_REPLY             = 8'h00                ,    //回复别人的请求是00
    parameter                           ICMP_CODE                   = 8'h00                     //回复别人的请求是00

)
(
    // ==================== 全局信号 ====================
    input                               clk_125m                   ,
    input                               rst_n                      ,
    input                               gmii_rx_dv_fall            ,
    input                [  47: 0]      recv_dst_mac               ,// 接受到的mac，用以辅助判断这包payload是否应该接受
    // ==================== IP层输入 ====================
    input                [   7: 0]      icmp_rx_data               ,
    input                               icmp_rx_valid              ,
    input                               icmp_rx_start              ,// ICMP包开始
    input                [  15: 0]      icmp_byte_cnt              ,
    input                [  15: 0]      icmp_length                ,//IP层开的小灶
    input                               packet_is_icmp             ,//辅助判断icmp的chencksum是否应该启动
    // ==================== 解析出的 ICMP 数据 ====================
    output               [  15: 0]      echo_reply_checksum        ,
    output                              echo_reply_checksum_valid  ,
    output reg           [  15: 0]      icmp_identifier            ,// 标识符
    output reg           [  15: 0]      icmp_sequence              ,// 序列号


    // ==================== 状态输出 ====================
    output reg                          icmp_rx_error              ,// 协议错误

    // ====================写fifo信号，及写入的数据量  ====================
    output reg                          fifo_wr_en                 ,
    output reg           [   7: 0]      fifo_din                   ,
    input                               icmp_rx_fifo_full          ,//谁写fifo，谁就要管full
    output reg           [  10: 0]      icmp_wr_data_cnt            //读端靠着这个信号来读取多少数据


    );

// ==================== 本地参数定义 ====================
reg [2:0]   current_state, next_state;

    localparam                          IDLE                        = 3'b001,
                                        S_PARSE_ICMP_HDR            = 3'b010, // 解析ICMP头  
                                        S_PAYLOAD                   = 3'b100; // 解析UDP负载的数据

    localparam                           ICMP_HEADER_BYTES           = 8                    ;  //ICMP头长度
    localparam                           ICMP_PAYLOAD_OFFSET         = 28                   ;  //handover_byte_cnt计数到多少才轮到payload

//本地寄存器定义
    reg                  [  15: 0]      recv_checksum_reg          ;
    reg                  [   7: 0]      icmp_type                  ;// ICMP Type
    reg                  [   7: 0]      icmp_code                  ;// ICMP Code
//=================================================
//计算echo_request时的校验和，目的是校验接收是否正确

    reg                  [   7: 0]      echo_request_data_in       ;
    reg                                 echo_request_data_valid    ;
    reg                                 echo_request_calc_start    ;
    reg                                 echo_request_last_byte     ;
    wire                 [  15: 0]      echo_request_checksum      ;
    wire                                echo_request_checksum_valid  ;

//=================================================
//计算echo_reply时的校验和

    reg                  [   7: 0]      echo_reply_data_in         ;
    reg                                 echo_reply_data_valid      ;
    reg                                 echo_reply_calc_start      ;
    reg                                 echo_reply_last_byte       ;



// ==================== 第一段：状态转移 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
    end else begin
        current_state <= next_state;
    end
end

// ==================== 第二段：下一状态逻辑 ====================
    always @(*) begin
        case (current_state)
        IDLE          :begin
            if(icmp_rx_start&&icmp_rx_valid)
                next_state=S_PARSE_ICMP_HDR;
            else    
                next_state = IDLE;
        end
        S_PARSE_ICMP_HDR:begin
            if(icmp_rx_valid)begin
                if(icmp_byte_cnt==ICMP_PAYLOAD_OFFSET-1)
                    next_state = S_PAYLOAD ;
                else
                    next_state=S_PARSE_ICMP_HDR;
            end
            else
                next_state = IDLE;
        end
        S_PAYLOAD     :begin
            if(icmp_rx_valid)begin
                if(icmp_byte_cnt==icmp_length+-1)
                    next_state = IDLE;                   
                else
                    next_state=S_PAYLOAD;
            end
            else
                next_state = IDLE;
        end
            default: next_state = IDLE;
        endcase
    end

// ==================== 第三段：输出逻辑 ====================
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n) begin
                    recv_checksum_reg  <=0;        fifo_wr_en <=0;
                    icmp_identifier<=0;            fifo_din   <=0;
                    icmp_sequence <= 16'd0;
                    icmp_type      <=0;                                    
                    icmp_code      <=0;                                                                                  

            echo_request_data_in     <=0;
            echo_request_data_valid  <=0;
            echo_request_calc_start  <=0;

            echo_reply_data_in       <=0;
            echo_reply_data_valid    <=0;
            echo_reply_calc_start    <=0;                                                                   
    end 
    else begin    
        case (current_state)
        IDLE          :begin
                  fifo_wr_en <=0;
                  fifo_din   <=0;                                     
            echo_request_data_in     <=0;
            echo_request_data_valid  <=0;

            echo_reply_data_in       <=0;
            echo_reply_data_valid    <=0;
            if((icmp_byte_cnt==19)&&packet_is_icmp)begin     //这是专门用来启动icmp_checksum的
                    echo_request_calc_start  <=1;
                    echo_reply_calc_start    <=1;
            end

        end
        S_PARSE_ICMP_HDR:begin
            case (icmp_byte_cnt)
                20: begin 
                    icmp_type                <=icmp_rx_data;
                    echo_request_data_in     <=icmp_rx_data;//电脑发来的icmp请求，类型码是08
                    echo_reply_data_in       <=0;//回复是0
                    echo_request_data_valid  <=1;
                    echo_reply_data_valid    <=1;
                    echo_request_calc_start  <=0;//开始信号只保持1个时钟周期
                    echo_reply_calc_start    <=0;//开始信号只保持1个时钟周期
                    end
                21:begin
                    icmp_code               <=icmp_rx_data;
                    echo_request_data_in     <=icmp_rx_data;
                    echo_reply_data_in       <=icmp_rx_data;
                end 
                22:begin  
                recv_checksum_reg  [15:8]       <=icmp_rx_data;
                echo_request_data_in            <=0;
                echo_reply_data_in              <=0;
                end
                23:begin
                    echo_request_data_in     <=0;
                    echo_reply_data_in       <=0;   
                    recv_checksum_reg  [7:0]      <=icmp_rx_data;                 
                end     
                24:begin
                    echo_request_data_in     <=icmp_rx_data;
                    echo_reply_data_in       <=icmp_rx_data;
                    icmp_identifier  [15:8]       <=icmp_rx_data;                    
                end     
                25:begin
                    echo_request_data_in     <=icmp_rx_data;
                    echo_reply_data_in       <=icmp_rx_data;
                    icmp_identifier  [7:0]        <=icmp_rx_data;
                end     
                26:begin
                    echo_request_data_in     <=icmp_rx_data;
                    echo_reply_data_in       <=icmp_rx_data;  
                    icmp_sequence  [15:8]         <=icmp_rx_data;                  
                end     
                27:begin
                    echo_request_data_in     <=icmp_rx_data;
                    echo_reply_data_in       <=icmp_rx_data;
                    icmp_sequence  [7:0]          <=icmp_rx_data;
                end     
                default: begin
                    //什么都不做
                end
            endcase
        end
        S_PAYLOAD : begin
            if (icmp_rx_valid&&~icmp_rx_fifo_full                    &&(recv_dst_mac==FPGA_MAC)) begin
                fifo_wr_en <= 1;
                fifo_din   <= icmp_rx_data;
                echo_request_data_in     <=icmp_rx_data;
                echo_reply_data_in       <=icmp_rx_data;
                end

            else if (icmp_byte_cnt == icmp_length - 1 && icmp_rx_valid)begin
                echo_reply_data_valid   <=0;   
                echo_request_data_valid <=0;    
            end
             else begin
                fifo_wr_en <= 0;
                fifo_din   <= 8'd0;
            end        
        
        end
            default: begin
                    // 保持，什么都不做           

            end
        endcase
    end
end


//=================================================
//产生icmp_rx_done，告诉外界我东西收完了，你们可以读fifo了
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n)begin
        echo_request_last_byte <=0;
        echo_reply_last_byte<=0;
    end

    else if (current_state == S_PAYLOAD &&
             icmp_byte_cnt == icmp_length - 1 &&
             icmp_rx_valid)begin
        echo_request_last_byte <=1;
        echo_reply_last_byte   <=1;
             end

    else begin
        echo_request_last_byte <=0;
        echo_reply_last_byte<=0;   
    end

end
//=================================================
//处理错误信号

always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n)
        icmp_rx_error<=0;
        else if(gmii_rx_dv_fall&&packet_is_icmp)begin
                if ((icmp_type != ICMP_ECHO_REQUEST &&icmp_type != ICMP_ECHO_REPLY)|| 
                    (icmp_code != ICMP_CODE)||
                    (recv_checksum_reg!=echo_request_checksum)
                    )
                    icmp_rx_error <= 1;
                else
                    icmp_rx_error<=0;
            end
            else
                icmp_rx_error<=0;
end


//=================================================
//产生fifo写入计数器计数，等读的时候靠着这个值来读
always @(posedge clk_125m or negedge rst_n) begin
    if (!rst_n)
        icmp_wr_data_cnt <= 0;
    else if(current_state ==S_PARSE_ICMP_HDR)
        icmp_wr_data_cnt <= 0;
    else if (current_state == S_PAYLOAD &&
             icmp_rx_valid)
        icmp_wr_data_cnt <= icmp_wr_data_cnt+1;
    else
        icmp_wr_data_cnt <= icmp_wr_data_cnt;
end




icmp_checksum echo_request_icmp_checksum(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
// ==================== 输入接口 ====================
    .data_in                            (echo_request_data_in       ),// (input)
    .data_valid                         (echo_request_data_valid    ),// (input)
// ==================== 控制接口 ====================
    .calc_start                         (echo_request_calc_start   ),// (input)// 开始计算,比送入的数据早一拍！，让状态机跳转到计算状态
    .last_byte                          (echo_request_last_byte    ),// (input)// 当前是否是最后一个字节
// ==================== 输出接口 ====================
    .checksum                           (echo_request_checksum     ),// (output)
    .checksum_valid                     (echo_request_checksum_valid) // (output)
);


icmp_checksum echo_reply_icmp_checksum(
// ==================== 全局信号 ====================
    .clk_125m                           (clk_125m                  ),// (input)
    .rst_n                              (rst_n                     ),// (input)
// ==================== 输入接口 ====================
    .data_in                            (echo_reply_data_in        ),// (input)
    .data_valid                         (echo_reply_data_valid     ),// (input)
// ==================== 控制接口 ====================
    .calc_start                         (echo_reply_calc_start     ),// (input)// 开始计算,比送入的数据早一拍！，让状态机跳转到计算状态 
    .last_byte                          (echo_reply_last_byte      ),// (input)// 当前是否是最后一个字节
// ==================== 输出接口 ====================
    .checksum                           (echo_reply_checksum       ),// (output)
    .checksum_valid                     (echo_reply_checksum_valid ) // (output)
);



endmodule
