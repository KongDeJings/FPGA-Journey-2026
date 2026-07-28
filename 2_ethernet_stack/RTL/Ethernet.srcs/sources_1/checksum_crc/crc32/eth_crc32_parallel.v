//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/06 08:35:56
// Design Name: 
// Module Name: eth_crc32
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
/*
空闲状态 → en=0 → CRC 寄存器保持不变
前导码(7字节) + SFD(1字节) → en=0 （不计算CRC）
目的MAC(6) + 源MAC(6) + 类型(2) + 数据(...) → en=1 （计算CRC）
CRC字段(4) → en=0 （不计算，这个位置放结果）
帧发送结束 → en=0 → 停止计算，输出最终的 CRC 结果
*/
// 

//////////////////////////////////////////////////////////////////////////////////
module eth_crc32_parallel (
    input                               clk                        ,
    input                               rst_n                      ,
    input                               crc_en                     ,// 帧有效期间为1
    input                               frame_end                  ,// 最后一个数据字节时为1
    input                [   7: 0]      data_in                    ,// MSB-first输入
    input                               data_valid                 ,
    output reg           [  31: 0]      crc_out                    ,
    output reg                          crc_valid                   // CRC结果有效
);

    reg                  [  31: 0]      crc_reg                    ;
    wire                 [   7: 0]      data_rev                   ;
    wire                 [  31: 0]      crc_next                   ;

assign data_rev = data_in;


crc32 u_crc32 (
    .crcIn  (crc_reg),
    .data   (data_rev),
    .crcOut (crc_next)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        crc_reg   <= 32'hFFFFFFFF;
        crc_out   <= 32'h0;
        crc_valid <= 1'b0;
    end else begin
        // 默认值
        crc_valid <= 1'b0;
        
        if (crc_en && data_valid) begin
            // 计算CRC
            crc_reg <= crc_next;
            
            // 如果是帧的最后一个字节
            if (frame_end) begin
                // 输出最终CRC（注意：这里输出的是crc_next，不是crc_reg）
                crc_out <= ~crc_next;  // 取反，以太网标准
                crc_valid <= 1'b1;
                
                // 复位CRC寄存器为下一帧准备
                 crc_reg <= 32'hFFFFFFFF;
            end
        end
    end
end

endmodule
