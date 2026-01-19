`timescale 1ps/1ps
`default_nettype none

module PE_fp32_multiply (
  input wire clk, rst_n,
  input wire vld_in,
  input wire cpt_en, // 使能信号
  input wire [31:0] a, // = (-1)^{s_a} * 1.f_a * 2^{(e_a-127)}
  input wire [31:0] b, // = (-1)^{s_b} * 1.f_b * 2^{(e_b-127)}
  output reg vld_out,
  output reg [31:0] out, // = i_fp32_a * i_fp32_b = (1.f_a * 1.f_b) * 2^{(e_a-127+e_b-127)} 
  output reg out_is_zero, 
  output reg out_is_inf,
  output reg out_is_nan,
  output reg out_is_of, 
  output reg out_is_uf 
);

/////////////////////////////////////////////
// 中间变量申明                              //
/////////////////////////////////////////////
// 1. 输入预处理
// 1.1. 输入fp32_a和fp32_b的符号位、阶码位和尾数位
wire s_a; // 符号位
wire [7:0] e_a; // 阶码位, 正确的范围在[1,254]，0和255分别代表特殊情况（零/次正规数和inf/NaN）
wire [22:0] f_a; // 尾数位
wire s_b; // 符号位
wire [7:0] e_b; // 阶码位, 正确的范围在[1,254]，0和255分别代表特殊情况（零/次正规数和inf/NaN）
wire [22:0] f_b; // 尾数位
// 1.2. 处理输入的特殊情况
wire a_is_zero, a_is_inf, a_is_nan; // 输入a的特殊情况
wire b_is_zero, b_is_inf, b_is_nan; // 输入b的特殊情况
wire is_nan; // 输出NaN
wire is_inf; // 输出inf
wire is_zero; // 输出0
wire data_mask; // 是否是非正常数据
// 1.3. 输出的符号位
wire s_out;

// 2. 尾数相乘（不包括规格化移位的调整）
wire [47:0] f_multi; // 尾数相乘的初始结果，未移位
// f_multi[47:46] 代表小数点前的部分, 范围在[1,4)
// f_multi[45:0] 代表小数点后的部分

// 3. 阶码相加（不包括规格化移位的调整）
wire signed [9:0] e_add; // 阶码相加的结果，未调整
// e_add[9] 代表符号位, e_add[8:0] 代表阶码值.
// e_a + e_b - 127 的范围在 [-126, 381]，所以需要9位来表示数值 + 1位符号位来区分正负。

// [打拍]
reg vld_in_1d, is_nan_1d, is_inf_1d, is_zero_1d;
reg s_out_1d;
reg [47:0] f_multi_1d;
reg signed [9:0] e_add_1d;

// 4. 规格化移位对尾数和阶码的调整：如果尾数乘积结果大于等于2，则需要右移一位，并且阶码加1
wire [47:0] f_multi_shift;
// f_multi_shift[47:46] 代表小数点前的部分, 范围在[1,2)
// f_multi_shift[45:0] 代表小数点后的部分, [45:23]是最终尾数舍入处理后留下的23位有效尾数, [22:0]是舍入处理时需要丢掉的部分
wire signed [9:0] e_add_shift;

// 5. 尾数舍入处理
wire f_multi_shift_R; // R位
wire f_multi_shift_S; // S位
wire [24:0] f_round; // 舍入后的尾数
// f_round[24:23] 代表小数点前的部分
// f_round[22:0] 代表小数点后的部分

// [打拍]
reg vld_in_2d, is_nan_2d, is_inf_2d, is_zero_2d;
reg s_out_2d;
reg [24:0] f_round_1d;
reg signed [9:0] e_add_shift_1d;

// 6. 处理一种特殊情况：如果 f_multi_shift 的整数部分是 1.1111...1，在舍入处理后 f_round 是 10.0000...0，
// 这时需要将尾数再次移位（调整为 01.0000...0），并且阶码再次加1
wire [22:0] f_out; // 最终输出的23位尾数部分
wire signed [9:0] e_out; // e_out[7:0]是最终输出的8位阶码部分

// 7. 处理overflow/underflow
wire is_of; // 是否overflow
wire is_uf; // 是否underflow

// 8. 拼接输出
wire [31:0] out_pre; // 拼接后的输出结果，未打拍

// [打拍] 输出变量已在模块接口中定义

//////////////////////////////////////////////
// 逻辑实现                                  //
//////////////////////////////////////////////
// 1. 输入预处理
// 1.1. 提取出输入a和b的符号位、阶码位和尾数位
assign s_a = a[31];
assign e_a = a[30:23];
assign f_a = a[22:0];
assign s_b = b[31];
assign e_b = b[30:23];
assign f_b = b[22:0];

// 1.2. 处理输入的特殊情况（零，正无穷，非数，次正规数）
assign a_is_zero = (e_a == 8'b0) ;//&& (f_a == 23'b0); // zero+subnormal
assign a_is_inf = (e_a == 8'b11111111) && (f_a == 23'b0);
assign a_is_nan = (e_a == 8'b11111111) && (f_a != 23'b0);
//wire a_is_subnormal = (e_a == 8'b0) && (f_a != 23'b0); // not used here

assign b_is_zero = (e_b == 8'b0) ;//&& (f_b == 23'b0); // zero+subnormal
assign b_is_inf = (e_b == 8'b11111111) && (f_b == 23'b0);
assign b_is_nan = (e_b == 8'b11111111) && (f_b != 23'b0);
//wire b_is_subnormal = (e_b == 8'b0) && (f_b != 23'b0); // not used here

// 输出NaN: a or b is NaN, or inf * 0 / 0 * inf
assign is_nan = a_is_nan || b_is_nan || (a_is_inf && b_is_zero) || (a_is_zero && b_is_inf);
// 输出inf: inf * non-zero finite / non-zero finite * inf / inf * inf
assign is_inf = (a_is_inf && !(b_is_zero || b_is_nan)) || (!(a_is_zero || a_is_nan) && b_is_inf) || (a_is_inf && b_is_inf);
// 输出0: zero * finite / finite * zero / zero * zero 
assign is_zero = (a_is_zero && !(b_is_inf || b_is_nan)) || (b_is_zero && !(a_is_inf || a_is_nan)) || (a_is_zero && b_is_zero);
// 数据掩码：如果是NaN/inf/zero，则不进行正常的乘法计算，直接输出特殊值；否则进行正常的乘法计算
assign data_mask = is_nan || is_inf || is_zero; // 可以节省功耗

// 1.3. 决定输出的符号位
assign s_out = s_a ^ s_b; 

// 2. 尾数相乘（不包括规格化移位的调整）
assign f_multi = (48'h1 << 23 | f_a) * (48'h1 << 23 | f_b); // 1.f_a * 1.f_b

// 3. 阶码相加（不包括规格化移位的调整）
assign e_add = $signed({2'b0, e_a}) + $signed({2'b0, e_b}) - 10'sd127; // e_a - 127 + e_b - 127 + 127 = e_a + e_b - 127

// [打拍] 
// vld_in -> vld_in_1d, is_nan -> is_nan_1d, is_inf -> is_inf_1d, is_zero -> is_zero_1d
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    vld_in_1d <= 1'b0;
    is_nan_1d <= 1'b0;
    is_inf_1d <= 1'b0;
    is_zero_1d <= 1'b0;
  end else if (!cpt_en) begin
    vld_in_1d <= 1'b0;
    is_nan_1d <= 1'b0;
    is_inf_1d <= 1'b0;
    is_zero_1d <= 1'b0;
  end else begin
    vld_in_1d <= vld_in;
    is_nan_1d <= is_nan;
    is_inf_1d <= is_inf;
    is_zero_1d <= is_zero;
  end
end
// f_multi -> f_multi_1d, e_added -> e_added_1d
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    s_out_1d <= 1'b0;
    f_multi_1d <= 48'b0;
    e_add_1d <= 10'sd0;
  end else if (!cpt_en) begin
    s_out_1d <= 1'b0;
    f_multi_1d <= 48'b0;
    e_add_1d <= 10'sd0;
  end else if (vld_in) begin
    s_out_1d <= s_out; // 应该在 vld_in 时无条件更新（不受 data_mask 影响）
    if (!data_mask) begin
      f_multi_1d <= f_multi;
      e_add_1d <= e_add;
    end
  end // 否则保持不变
end

// 4. 规格化移位对尾数和阶码的调整：如果尾数乘积结果大于等于2，则需要右移一位，并且阶码加1
assign f_multi_shift = (f_multi_1d[47] == 1'b0) ? f_multi_1d : f_multi_1d >> 1; 
assign e_add_shift = (f_multi_1d[47] == 1'b0) ? e_add_1d : e_add_1d + 10'sd1;  

// 5. 尾数舍入处理（采用的算法：RNE算法）
assign f_multi_shift_R = f_multi_shift[22]; 
assign f_multi_shift_S = |(f_multi_shift[21:0]); // (f_multi_shift[20:0] != 0);
                 // 根据RNE算法，如果 R位为1 且 S位为1（即丢弃部分大于0.5），需要进位
assign f_round = (f_multi_shift_R && f_multi_shift_S) ? f_multi_shift[47:23] + 1'b1 :
                 // 如果 R位为1 且 S位为0 且 当前尾数部分是奇数（即丢弃部分等于0.5 且最后保留位为奇数），需要进位
                 (f_multi_shift_R && !f_multi_shift_S && f_multi_shift[23]) ? f_multi_shift[47:23] + 1'b1 :
                 // 如果 R位为0（即丢弃部分小于0.5），不需要进位
                 // 如果 R位为1 且 S位为0 且 当前尾数部分是偶数（即丢弃部分等于0.5 且最后保留位为偶数），不需要进位
                 f_multi_shift[47:23]; 
                 
// [打拍]
// vld_in_1d -> vld_in_2d, is_nan_1d -> is_nan_2d, is_inf_1d -> is_inf_2d, is_zero_1d -> is_zero_2d
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    vld_in_2d <= 1'b0;
    is_nan_2d <= 1'b0;
    is_inf_2d <= 1'b0;
    is_zero_2d <= 1'b0;
  end else if (!cpt_en) begin
    vld_in_2d <= 1'b0;
    is_nan_2d <= 1'b0;
    is_inf_2d <= 1'b0;
    is_zero_2d <= 1'b0;
  end else begin
    vld_in_2d <= vld_in_1d;
    is_nan_2d <= is_nan_1d;
    is_inf_2d <= is_inf_1d;
    is_zero_2d <= is_zero_1d;
  end
end
// s_out_1d -> s_out_2d, f_round -> f_round_1d, e_add_shift -> e_add_shift_1d
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    s_out_2d <= 1'b0;
    f_round_1d <= 25'b0;
    e_add_shift_1d <= 10'sd0;
  end else if (!cpt_en) begin
    s_out_2d <= 1'b0;
    f_round_1d <= 25'b0;
    e_add_shift_1d <= 10'sd0;
  end else if (vld_in_1d) begin 
    s_out_2d <= s_out_1d;
    f_round_1d <= f_round;
    e_add_shift_1d <= e_add_shift;
  end // 否则保持不变
end

// 6. 处理一种特殊情况：如果 f_multi_shift 的整数部分是 1.1111...1，在舍入处理后 f_round 是 10.0000...0，
// 这时需要将尾数再次移位（调整为 01.0000...0），并且阶码再次加1
assign f_out = (f_round_1d[24] == 1'b1) ? f_round_1d[23:1] : f_round_1d[22:0]; // 如果发生了进位，尾数需要右移一位
assign e_out = (f_round_1d[24] == 1'b1) ? e_add_shift_1d + 1 : e_add_shift_1d; // 如果发生了进位，阶码需要加

// 7. 处理overflow/underflow
assign is_of = (is_nan_2d || is_inf_2d || is_zero_2d) ? 1'b0 : e_out >= 10'sd255;
assign is_uf = (is_nan_2d || is_inf_2d || is_zero_2d) ? 1'b0 : e_out <= 10'sd0;

// 8. 拼接输出
assign out_pre = is_nan_2d ? {1'b0, 8'b11111111, 23'h1} : // NaN
                 is_inf_2d ? {s_out_2d, 8'b11111111, 23'b0} : // inf
                 is_zero_2d ? {s_out_2d, 8'b0, 23'b0} : // zero
                 is_uf ? {s_out_2d, 8'b0, 23'b0} : // underflow to zero
                 is_of ? {s_out_2d, 8'b11111111, 23'b0} : // overflow to inf
                 {s_out_2d, e_out[7:0], f_out}; // normal case

// [打拍]
// vld_in_2d -> vld_out, is_nan_2d -> out_is_nan, is_inf_2d -> out_is_inf, is_zero_2d -> out_is_zero
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    vld_out <= 1'b0;
    out_is_nan <= 1'b0;
    out_is_inf <= 1'b0;
    out_is_zero <= 1'b0;
  end else if (!cpt_en) begin
    vld_out <= 1'b0;
    out_is_nan <= 1'b0;
    out_is_inf <= 1'b0;
    out_is_zero <= 1'b0;
  end else begin
    vld_out <= vld_in_2d;
    out_is_nan <= is_nan_2d;
    out_is_inf <= is_inf_2d;
    out_is_zero <= is_zero_2d;
  end
end
// out_pre -> out, is_of -> out_is_of, is_uf -> out_is_uf
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    out <= 32'b0;
    out_is_of <= 1'b0;
    out_is_uf <= 1'b0;
  end else if (!cpt_en) begin
    out <= 32'b0;
    out_is_of <= 1'b0;
    out_is_uf <= 1'b0;
  end else if (vld_in_2d) begin
    out <= out_pre;
    out_is_of <= is_of;
    out_is_uf <= is_uf;
  end // 否则保持不变
end

endmodule
`default_nettype wire