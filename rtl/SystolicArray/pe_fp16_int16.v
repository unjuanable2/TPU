`timescale 1ps/1ps
`default_nettype none

module pe_fp16_int16 (
  input  wire        clk, rst_n,
  input  wire        vld_in,
  input  wire        cpt_en, // compute_enable 计算使能信号
  input  wire [15:0] in, // IEEE FP16: (-1)^s * 1.f * 2^(e-15)

  output reg         vld_out,
  output reg  [15:0] out, // signed two's-complement int16
  output reg         out_is_of,
  output reg         out_is_uf
);

/////////////////////////////////////////////
// 中间变量申明                              //
/////////////////////////////////////////////
// 1. 输入预处理
// 1.1. 输入fp16的符号位、阶码位和尾数位
wire       s_in; // 符号位
wire [4:0] e_in; // 阶码位, 正常范围在[1,30]，0和31分别代表特殊情况
wire [9:0] f_in; // 尾数位

// 1.2. 处理输入的特殊情况
wire in_is_zero;
wire in_is_subnormal;
wire in_is_inf;
wire in_is_nan;
wire data_mask;

// 2. 真实指数
wire signed [5:0] real_e_in; 
wire [5:0]        abs_real_e_in; 

// 3. 尾数移位
wire [10:0] f_bits; // 1.f
reg  [24:0] f_shift;

// [打拍]
reg vld_in_1d, in_is_zero_1d, in_is_of_1d, in_is_uf_1d;
reg s_in_1d; reg [24:0] f_shift_1d;

// 4. 舍入和符号处理
wire        round_carry;
wire [15:0] mag_round;
wire [15:0] signed_out_pre;

// 5. 拼接输出
wire [15:0] out_pre;
wire        out_is_of_pre;
wire        out_is_uf_pre;

//////////////////////////////////////////////
// 逻辑实现                                  //
//////////////////////////////////////////////
// 1. 输入预处理
// 1.1. 提取出输入in的符号位、阶码位和尾数位
assign s_in = in[15];
assign e_in = in[14:10]; // [1:30]是正常数，0和31分别代表特殊情况
assign f_in = in[9:0];

// 1.2. 处理输入的特殊情况（零，正无穷，非数，次正规数）
assign in_is_zero      = (e_in == 5'b0) && (f_in == 10'b0);
assign in_is_subnormal = (e_in == 5'b0) && (f_in != 10'b0);
assign in_is_inf       = (e_in == 5'b11111) && (f_in == 10'b0);
assign in_is_nan       = (e_in == 5'b11111) && (f_in != 10'b0);
assign data_mask       = in_is_zero || in_is_subnormal || in_is_inf || in_is_nan;

// 2. 真实指数
assign real_e_in = $signed({1'b0, e_in}) - 6'sd15;
// e_in 是无符号数，范围[1,30]，通过在前面补0扩展为6位的有符号数后再减去15，
// 可以得到范围在[-14,15]的真实指数 real_e_in:
// real_e_in[5] 代表符号位, real_e_in[4:0] 代表指数值, 范围在[-14,15]

// 3. 尾数移位
assign abs_real_e_in = real_e_in[5] ? (~real_e_in + 6'sd1) : real_e_in;
// 如果 real_e_in 是负数，abs_real_e_in = -real_e_in；
// 如果 real_e_in 是非负数，abs_real_e_in = real_e_in
assign f_bits = {1'b1, f_in}; 
// 对于正常数，f_bits 是 1.f 的形式, 11-bit
// 对于零、inf、nan、subnormal，f_bits 的值不影响最终结果，因为 data_mask 会屏蔽掉这些情况

always @(*) begin
  f_shift = 25'b0; // normal FP16 path: 11-bit significand, left shift up to 14 bits before int16 overflow
  if (!data_mask) begin
    if (real_e_in[5] == 1'b0)
      f_shift = f_bits << abs_real_e_in[4:0];
    else
      f_shift = f_bits >> abs_real_e_in[4:0];
  end
end

// [打拍]
// vld_in -> vld_in_1d, in_is_zero -> in_is_zero_1d, 
// in_is_inf/in_is_nan/too large -> in_is_of_1d, subnormal -> in_is_uf_1d
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    vld_in_1d     <= 1'b0;
    in_is_zero_1d <= 1'b0;
    in_is_of_1d   <= 1'b0;
    in_is_uf_1d   <= 1'b0;
  end else if (!cpt_en) begin
    vld_in_1d     <= 1'b0;
    in_is_zero_1d <= 1'b0;
    in_is_of_1d   <= 1'b0;
    in_is_uf_1d   <= 1'b0;
  end else begin
    vld_in_1d     <= vld_in;
    in_is_zero_1d <= vld_in && in_is_zero;
    in_is_of_1d   <= vld_in && (in_is_inf || in_is_nan || (real_e_in >= 6'sd15));
    in_is_uf_1d   <= vld_in && in_is_subnormal;
  end
end
// s_in -> s_in_1d, f_shift -> f_shift_1d
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    s_in_1d <= 1'b0;
    f_shift_1d <= 25'b0;
  end else if (!cpt_en) begin
    s_in_1d <= 1'b0;
    f_shift_1d <= 25'b0;
  end else if (vld_in) begin
    s_in_1d <= s_in;
    f_shift_1d <= f_shift;
  end // 否则保持不变
end

// 4. 舍入和符号处理
// f_shift[24:10]是整数部分，f_shift[9]是被截断部分的最高位。
assign {round_carry, mag_round[14:0]} = {1'b0, f_shift_1d[24:10]} + f_shift_1d[9];
assign mag_round[15] = round_carry;
// mag_round 的最高位 mag_round[15] 是舍入后的结果的符号位（对于绝对值来说），
// mag_round[14:0] 是舍入后的结果的数值部分（绝对值），总共15位，可以表示的范围是 [0, 32767]，
// int16 的范围是 [-32768, 32767] = [-2^15, 2^15-1]
// 需要注意的是，mag_round 的值是基于绝对值进行舍入的结果，还没有考虑符号位，符号位会在最后处理输出时再加上。
assign signed_out_pre = s_in_1d ? (~mag_round + 16'b1) : mag_round;

// 5. 拼接输出
assign out_is_of_pre = in_is_of_1d || (round_carry && !s_in_1d) 
    || (s_in_1d && (mag_round[15] == 1'b1) && (mag_round[14:0] != 15'b0));
// 当 s_in_1d 是正数时，如果舍入后 mag_round 超过了 int16 的最大正数 32767（即 mag_round[15] = 1），就发生了正溢出；
// 当 s_in_1d 是负数时，mag_round == 16'h8000 代表 -32768，没有发生负溢出；大于该值才是负溢出。
assign out_is_uf_pre = in_is_uf_1d;
assign out_pre = in_is_zero_1d ? 16'h0000 :
                 out_is_uf_pre ? 16'h0000 :
                 out_is_of_pre ? (s_in_1d ? 16'h8000 : 16'h7fff) : signed_out_pre;

// [打拍]
// out_pre -> out, out_is_of_pre -> out_is_of, out_is_uf_pre -> out_is_uf
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    vld_out   <= 1'b0;
    out       <= 16'b0;
    out_is_of <= 1'b0;
    out_is_uf <= 1'b0;
  end else if (!cpt_en) begin
    vld_out   <= 1'b0;
    out       <= 16'b0;
    out_is_of <= 1'b0;
    out_is_uf <= 1'b0;
  end else begin
    vld_out <= vld_in_1d;
    if (vld_in_1d) begin
      out       <= out_pre;
      out_is_of <= out_is_of_pre;
      out_is_uf <= out_is_uf_pre;
    end
  end
end

endmodule

`default_nettype wire
