`timescale 1ps/1ps
`default_nettype none

module PE (
  input  wire [31:0] i_a,
  input  wire [31:0] i_b,
  input  wire [1:0]  i_mode, // 2'b00=fp32, 2'b01=fp16, 2'b10=int8, 2'b11=int4
  output wire [31:0] o_y,

  // 这些 flag 主要对浮点模式有意义；整数模式下置 0
  output wire        o_is_zero,
  output wire        o_is_inf,
  output wire        o_is_nan,
  output wire        o_overflow,
  output wire        o_underflow
);

/* fp32 path */
wire [31:0] fp32_y;
wire fp32_is_zero, fp32_is_inf, fp32_is_nan, fp32_ovf, fp32_udf;
PE_fp32_multiply i_PE_fp32_multiply (
  .i_fp32_a(i_a),
  .i_fp32_b(i_b),
  .o_fp32_output(fp32_output),
  .o_fp32_output_is_zero(fp32_output_is_zero),
  .o_fp32_output_is_inf(fp32_output_is_inf),
  .o_fp32_output_is_nan(fp32_output_is_nan),
  .o_fp32_output_overflow(fp32_output_overflow),
  .o_fp32_output_underflow(fp32_output_underflow)
);

/* fp16 path */
wire [31:0] a16_to_32, b16_to_32;
PE_fp16_to_fp32 u_a16_to_32 (.i_fp16(i_a[15:0]), .o_fp32(a16_to_32));
PE_fp16_to_fp32 u_b16_to_32 (.i_fp16(i_b[15:0]), .o_fp32(b16_to_32));

wire [31:0] fp16_mul_fp32_y;
wire fp16_mul_is_zero, fp16_mul_is_inf, fp16_mul_is_nan, fp16_mul_ovf, fp16_mul_udf;
PE_fp32_multiply u_fp16_via_fp32_mul (
    .i_fp32_a(a16_to_32),
    .i_fp32_b(b16_to_32),
    .o_fp32_output(fp16_mul_fp32_y),
    .o_fp32_output_is_zero(fp16_mul_is_zero),
    .o_fp32_output_is_inf(fp16_mul_is_inf),
    .o_fp32_output_is_nan(fp16_mul_is_nan),
    .o_fp32_output_overflow(fp16_mul_ovf),
    .o_fp32_output_underflow(fp16_mul_udf)
);

  wire [15:0] fp16_y16;
  fp32_to_fp16 u_fp32_to_fp16 (
    .i_fp32(fp16_mul_fp32_y),
    .o_fp16(fp16_y16)
  );

  wire [31:0] fp16_y = {16'b0, fp16_y16};

  // ---------------- int8 path ----------------
  wire signed [7:0] a8, b8;
  fp32_to_int8_sat_trunc u_fp32_to_i8_a (.i_fp32(i_a), .o_i8(a8));
  fp32_to_int8_sat_trunc u_fp32_to_i8_b (.i_fp32(i_b), .o_i8(b8));

  wire signed [15:0] p16 = a8 * b8;
  wire signed [31:0] p32 = {{16{p16[15]}}, p16[15:0]};

  wire [31:0] int8_y_fp32;
  int32_to_fp32 u_i32_to_fp32 (.i_i32(p32), .o_fp32(int8_y_fp32));

  // ---------------- int4 path ----------------
  wire signed [3:0] a4 = i_a[3:0];
  wire signed [3:0] b4 = i_b[3:0];
  wire signed [7:0] p8 = a4 * b4;
  wire [31:0] int4_y = {{24{p8[7]}}, p8[7:0]};

  // ---------------- mux outputs ----------------
  reg [31:0] y_sel;
  reg z_sel, inf_sel, nan_sel, ovf_sel, udf_sel;

  always @* begin
    // defaults
    y_sel   = 32'b0;
    z_sel   = 1'b0;
    inf_sel = 1'b0;
    nan_sel = 1'b0;
    ovf_sel = 1'b0;
    udf_sel = 1'b0;

    case (i_mode)
      2'b00: begin // fp32
        y_sel   = fp32_y;
        z_sel   = fp32_is_zero;
        inf_sel = fp32_is_inf;
        nan_sel = fp32_is_nan;
        ovf_sel = fp32_ovf;
        udf_sel = fp32_udf;
      end
      2'b01: begin // fp16
        y_sel   = fp16_y;
        z_sel   = fp16_mul_is_zero;
        inf_sel = fp16_mul_is_inf;
        nan_sel = fp16_mul_is_nan;
        ovf_sel = fp16_mul_ovf;
        udf_sel = fp16_mul_udf;
      end
      2'b10: begin // int8 -> fp32
        y_sel   = int8_y_fp32;
      end
      2'b11: begin // int4 -> int
        y_sel   = int4_y;
      end
      default: begin
        y_sel = 32'b0;
      end
    endcase
  end

  assign o_y         = y_sel;
  assign o_is_zero   = z_sel;
  assign o_is_inf    = inf_sel;
  assign o_is_nan    = nan_sel;
  assign o_overflow  = ovf_sel;
  assign o_underflow = udf_sel;

endmodule

`default_nettype wire
