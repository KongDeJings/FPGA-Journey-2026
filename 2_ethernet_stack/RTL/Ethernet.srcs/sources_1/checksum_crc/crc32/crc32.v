
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/06 08:22:33
// Design Name: 
// Module Name: crc32
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description:    CRC32并行计算模块，使用网站https://bues.ch/cms/hacking/crcgen.html生成
/*
INIT    = 0xFFFFFFFF  （初始值）
REFIN   = 1           （输入反转 → 并行已做）
REFOUT  = 1           （输出反转 → 并行已做）
XOROUT  = 0xFFFFFFFF  （最终取反 → 你必须加 ~），和全是1异或，就是按位取反！
*/

//////////////////////////////////////////////////////////////////////////////////
`ifndef CRC32_V_
`define CRC32_V_

// CRC polynomial coefficients: x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1
//                              0xEDB88320 (hex)反向多项式	

// CRC width:                   32 bits
// CRC shift direction:         right (little endian)
// Input word width:            8 bits


module crc32 (
    input [31:0] crcIn,
    input [7:0] data,
    output [31:0] crcOut
);
    assign crcOut[0]  = crcIn[2] ^ crcIn[8]  ^ data[2];
    assign crcOut[1]  = crcIn[0] ^ crcIn[3]  ^ crcIn[9] ^ data[0] ^ data[3];
    assign crcOut[2]  = crcIn[0] ^ crcIn[1]  ^ crcIn[4] ^ crcIn[10] ^ data[0] ^ data[1] ^ data[4];
    assign crcOut[3]  = crcIn[1] ^ crcIn[2]  ^ crcIn[5] ^ crcIn[11] ^ data[1] ^ data[2] ^ data[5];
    assign crcOut[4]  = crcIn[0] ^ crcIn[2]  ^ crcIn[3] ^ crcIn[6] ^ crcIn[12] ^ data[0] ^ data[2] ^ data[3] ^ data[6];
    assign crcOut[5]  = crcIn[1] ^ crcIn[3]  ^ crcIn[4] ^ crcIn[7] ^ crcIn[13] ^ data[1] ^ data[3] ^ data[4] ^ data[7];    
    assign crcOut[6]  = crcIn[4] ^ crcIn[5]  ^ crcIn[14]^ data[4] ^ data[5];
    assign crcOut[7]  = crcIn[0] ^ crcIn[5]  ^ crcIn[6] ^ crcIn[15] ^ data[0] ^ data[5] ^ data[6];
    assign crcOut[8]  = crcIn[1] ^ crcIn[6]  ^ crcIn[7] ^ crcIn[16] ^ data[1] ^ data[6] ^ data[7];
    assign crcOut[9]  = crcIn[7] ^ crcIn[17] ^ data [7];
    assign crcOut[10] = crcIn[2] ^ crcIn[18] ^ data [2];
    assign crcOut[11] = crcIn[3] ^ crcIn[19] ^ data [3];
    assign crcOut[12] = crcIn[0] ^ crcIn[4]  ^ crcIn[20] ^ data[0] ^ data[4];
    assign crcOut[13] = crcIn[0] ^ crcIn[1]  ^ crcIn[5] ^ crcIn[21] ^ data[0] ^ data[1] ^ data[5];
    assign crcOut[14] = crcIn[1] ^ crcIn[2]  ^ crcIn[6] ^ crcIn[22] ^ data[1] ^ data[2] ^ data[6];
    assign crcOut[15] = crcIn[2] ^ crcIn[3]  ^ crcIn[7] ^ crcIn[23] ^ data[2] ^ data[3] ^ data[7];
    assign crcOut[16] = crcIn[0] ^ crcIn[2]  ^ crcIn[3] ^ crcIn[4] ^ crcIn[24] ^ data[0] ^ data[2] ^ data[3] ^ data[4];
    assign crcOut[17] = crcIn[0] ^ crcIn[1]  ^ crcIn[3] ^ crcIn[4] ^ crcIn[5] ^ crcIn[25] ^ data[0] ^ data[1] ^ data[3] ^ data[4] ^ data[5];
    assign crcOut[18] = crcIn[0] ^ crcIn[1]  ^ crcIn[2] ^ crcIn[4] ^ crcIn[5] ^ crcIn[6] ^ crcIn[26] ^ data[0] ^ data[1] ^ data[2] ^ data[4] ^ data[5] ^ data[6];
    assign crcOut[19] = crcIn[1] ^ crcIn[2]  ^ crcIn[3] ^ crcIn[5] ^ crcIn[6] ^ crcIn[7] ^ crcIn[27] ^ data[1] ^ data[2] ^ data[3] ^ data[5] ^ data[6] ^ data[7];
    assign crcOut[20] = crcIn[3] ^ crcIn[4]  ^ crcIn[6] ^ crcIn[7] ^ crcIn[28] ^ data[3] ^ data[4] ^ data[6] ^ data[7];
    assign crcOut[21] = crcIn[2] ^ crcIn[4]  ^ crcIn[5] ^ crcIn[7] ^ crcIn[29] ^ data[2] ^ data[4] ^ data[5] ^ data[7];
    assign crcOut[22] = crcIn[2] ^ crcIn[3]  ^ crcIn[5] ^ crcIn[6] ^ crcIn[30] ^ data[2] ^ data[3] ^ data[5] ^ data[6];
    assign crcOut[23] = crcIn[3] ^ crcIn[4]  ^ crcIn[6] ^ crcIn[7] ^ crcIn[31] ^ data[3] ^ data[4] ^ data[6] ^ data[7];
    assign crcOut[24] = crcIn[0] ^ crcIn[2]  ^ crcIn[4] ^ crcIn[5] ^ crcIn[7] ^ data[0] ^ data[2] ^ data[4] ^ data[5] ^ data[7];
    assign crcOut[25] = crcIn[0] ^ crcIn[1]  ^ crcIn[2] ^ crcIn[3] ^ crcIn[5] ^ crcIn[6] ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[5] ^ data[6];
    assign crcOut[26] = crcIn[0] ^ crcIn[1]  ^ crcIn[2] ^ crcIn[3] ^ crcIn[4] ^ crcIn[6] ^ crcIn[7] ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4] ^ data[6] ^ data[7];
    assign crcOut[27] = crcIn[1] ^ crcIn[3]  ^ crcIn[4] ^ crcIn[5] ^ crcIn[7] ^ data[1] ^ data[3] ^ data[4] ^ data[5] ^ data[7];
    assign crcOut[28] = crcIn[0] ^ crcIn[4]  ^ crcIn[5] ^ crcIn[6] ^ data[0] ^ data[4] ^ data[5] ^ data[6];
    assign crcOut[29] = crcIn[0] ^ crcIn[1]  ^ crcIn[5] ^ crcIn[6] ^ crcIn[7] ^ data[0] ^ data[1] ^ data[5] ^ data[6] ^ data[7];
    assign crcOut[30] = crcIn[0] ^ crcIn[1]  ^ crcIn[6] ^ crcIn[7] ^ data[0] ^ data[1] ^ data[6] ^ data[7];
    assign crcOut[31] = crcIn[1] ^ crcIn[7]  ^  data[1] ^ data[7];
endmodule

`endif // CRC32_V_
