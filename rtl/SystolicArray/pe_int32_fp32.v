`timescale 1ps/1ps
`default_nettype none

module pe_int32_fp32 (
  input  wire        clk, rst_n,
  input  wire        vld_in,
  input  wire        cpt_en, // compute_enable 计算使能信号
  input  wire [31:0] in, // signed two's-complement int32

  output reg         vld_out,
  output reg  [31:0] out, // IEEE FP32
  output reg         out_is_zero
);

/////////////////////////////////////////////
// 中间变量申明                              //
/////////////////////////////////////////////
// 1. 输入预处理
wire        s_in; // 符号位
wire        in_is_zero;
wire [31:0] mag_in; // 输入绝对值

// 2. Leading one detect
reg [5:0] lod_index; // range [0,31], 表示输入中最高位1的位置，0表示最低位，31表示最高位
integer   i;

// 3. 生成阶码
wire [7:0]  exp;

// 4. 尾数移位
wire [4:0]  lshift; // 左移位数, range [0,31]
wire [4:0]  rshift; // 右移位数, range [0,31]
wire [23:0] mag_in_shift; // 根据lod_index对输入绝对值进行移位后的结果
                          // hidden bit + 23-bit fraction
wire [22:0] frac; // 最终的23位fraction部分                          

// 5. 尾数舍入处理
wire round_bit;
wire sticky_bit;
wire [24:0] mag_in_round; // 舍入后的尾数，包含hidden bit和fraction部分

// 6. 拼接输出
wire [31:0] out_pre; // 拼接后的输出结果，未打拍

// [打拍]

//////////////////////////////////////////////
// 逻辑实现                                  //
//////////////////////////////////////////////
// 1. 输入预处理
assign s_in = in[31]; // 符号位
assign mag_in = s_in ? (~in + 32'b1) : in; // 2's complement to magnitude
assign in_is_zero = (in == 32'b0);

// 2. Leading one detect
always @(*) begin
  lod_index = 6'd0;
  for (i = 0; i < 32; i = i + 1) begin
    if (mag_in[i])
      lod_index = i;
  end
end

// 3. 生成阶码
assign exp = in_is_zero ? 8'd0 : (8'd127 + {2'b0, lod_index});

// 4. 尾数移位
assign lshift = 5'd23 - lod_index[4:0];
assign rshift = lod_index[4:0] - 5'd23;
assign mag_in_shift = in_is_zero ? 24'd0 :
                   (lod_index <= 6'd23) ? (mag_in << lshift) :
                                          (mag_in >> rshift);

// 5. 尾数舍入处理    
always @(*) begin
  if (lod_index <= 6'd23) begin // 左移
    // 需要右移，可能会有舍入和sticky bit
    round_bit = mag_in[rshift - 1'b1];
    sticky_bit = |(mag_in & ((32'h1 << (rshift - 1'b1)) - 32'h1));
    mag_in_round = {1'b0, mag_in_shift[23:0]} + round_bit + sticky_bit;
  end else begin // 右移
    frac = mag_in_shift[22:0]; // 取 mag_in_shift 的低 23 位作为 fraction 部分
  end
end                                       
assign round_bit = (lod_index > 6'd23) ? mag_in[rshift - 1'b1] : 1'b0;
assign sticky_mask = (lod_index > 6'd24) ? ((32'h1 << (rshift - 1'b1)) - 32'h1) : 32'd0;
assign sticky_bit = (lod_index > 6'd23) ? |(mag_in & sticky_mask) : 1'b0;
assign round_inc = (lod_index > 6'd23) && round_bit && (sticky_bit || mant_keep[0]);
assign mant_round = {1'b0, mant_keep} + round_inc;
assign exp_pre = in_is_zero ? 8'd0 :
                 ((lod_index > 6'd23) && mant_round[24]) ? (exp + 1'b1) :
                                                            exp;
assign frac_pre = in_is_zero ? 23'd0 :
                  (lod_index <= 6'd23) ? mant_keep[22:0] :
                  mant_round[24] ? mant_round[23:1] :
                                    mant_round[22:0];

// 4. 拼接输出
assign out_pre = in_is_zero ? 32'b0 : {s_in, exp_pre, frac_pre};

// [打拍]
// out_pre -> out, in_is_zero -> out_is_zero
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    vld_out     <= 1'b0;
    out         <= 32'b0;
    out_is_zero <= 1'b0;
  end else if (!cpt_en) begin
    vld_out     <= 1'b0;
    out         <= 32'b0;
    out_is_zero <= 1'b0;
  end else begin
    vld_out <= vld_in;
    if (vld_in) begin
      out         <= out_pre;
      out_is_zero <= in_is_zero;
    end
  end
end

endmodule
`default_nettype wire
