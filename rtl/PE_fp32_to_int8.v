`timescale 1ps/1ps
`default_nettype none

module fp32_to_int8_sat_trunc (
  input  wire [31:0] i_fp32,
  output wire signed [7:0] o_i8
);
  wire s = i_fp32[31];
  wire [7:0] e = i_fp32[30:23];
  wire [22:0] f = i_fp32[22:0];

  wire is_nan = (e == 8'hFF) && (f != 23'b0);
  wire is_inf = (e == 8'hFF) && (f == 23'b0);
  wire is_zero = (e == 8'b0) && (f == 23'b0);

  reg signed [7:0] y;

  reg [23:0] mant;
  integer shift;
  reg signed [31:0] val;

  always @* begin
    y = 8'sd0;

    if (is_zero) begin
      y = 8'sd0;
    end else if (is_nan) begin
      y = 8'sd0;
    end else if (is_inf) begin
      y = s ? -8'sd128 : 8'sd127;
    end else begin
      // exp_unbiased = e - 127
      shift = $signed({1'b0,e}) - 127;

      if (shift < 0) begin
        y = 8'sd0; // |x|<1 -> 0 (toward zero)
      end else begin
        mant = {1'b1, f}; // 24-bit

        if (shift >= 31) begin
          val = 32'sh7FFFFFFF;
        end else begin
          if (shift >= 23) val = $signed(mant) <<< (shift - 23);
          else             val = $signed(mant) >>> (23 - shift);
          if (s) val = -val;
        end

        // saturate to int8
        if (val > 32'sd127)        y = 8'sd127;
        else if (val < -32'sd128)  y = -8'sd128;
        else                       y = val[7:0];
      end
    end
  end

  assign o_i8 = y;

endmodule

`default_nettype wire