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
wire [7:0]  exp_base;

// 4. 尾数移位
wire [4:0]  lshift; // 左移位数, range [0,31]
wire [4:0]  rshift; // 右移位数, range [0,31]
wire [23:0] mag_in_shift; // 根据lod_index对输入绝对值进行移位后的结果
                          // hidden bit + 23-bit fraction

// 5. 尾数舍入处理
wire        mag_in_R_bit;
wire        mag_in_S_bit;
wire        mag_in_round_inc; 
wire [24:0] mag_in_round; // 舍入后的尾数，{0, hidden bit, fraction}，
                          // 可能会有25位是因为舍入可能会导致进位
wire [22:0] frac; // 最终的23位fraction部分                          
wire [7:0]  exp;

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
assign exp_base = in_is_zero ? 8'd0 : (8'd127 + {2'b0, lod_index});

// 4. 尾数移位
assign lshift = 5'd23 - lod_index[4:0];
assign rshift = lod_index[4:0] - 5'd23;
assign mag_in_shift = in_is_zero ? 24'd0 :
                      (lod_index <= 6'd23) ? (mag_in << lshift) :
                                             (mag_in >> rshift);

// 5. 尾数舍入处理，当 lod_index > 23 时才需要舍入
// mag_in[rshift-1'b1:0] 是需要舍入的部分
assign mag_in_R_bit = (lod_index > 6'd23) ? mag_in[rshift - 1'b1] : 1'b0;
assign mag_in_S_bit = (lod_index > 6'd23) ? 
                    |(mag_in & ((32'h1 << (rshift - 1'b1)) - 32'h1)) : 1'b0;
assign mag_in_round_inc = (lod_index > 6'd23) && mag_in_R_bit 
                    && (mag_in_S_bit || mag_in_shift[0]);
assign mag_in_round = {1'b0, mag_in_shift} + mag_in_round_inc;
                    // {0, hidden bit + 23-bit fraction} + round_inc
assign frac = in_is_zero ? 23'd0 :
              // 如果是左移，直接取 mag_in_shift 的23位作为frac
              (lod_index <= 6'd23) ? mag_in_shift[22:0] :
              // 如果是右移
              // 如果发生了进位，mag_in_round 的最高位会变为1，此时需要将 frac 其右移一位
              mag_in_round[24] ? mag_in_round[23:1] : mag_in_round[22:0];
assign exp = in_is_zero ? 8'd0 :
             // 如果是左移，exp = exp_base
             (lod_index <= 6'd23) ? exp_base :
             // 如果是右移，
             // 如果发生了进位，exp = exp_base + 1，否则 exp = exp_base
             mag_in_round[24] ? (exp_base + 8'd1) :  exp_base;                                

// 6. 拼接输出
assign out_pre = in_is_zero ? 32'b0 : {s_in, exp, frac};

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
