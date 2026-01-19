`timescale 1ps/1ps
`default_nettype none

module fp16_to_fp32 (
  input  wire [15:0] i_fp16,
  output wire [31:0] o_fp32
);
  wire s = i_fp16[15];
  wire [4:0] e = i_fp16[14:10];
  wire [9:0] f = i_fp16[9:0];

  reg [31:0] y;

  integer sh;
  reg [9:0] frac;
  reg [4:0] exp16;
  reg [7:0] exp32;

  always @* begin
    y = 32'b0;

    if (e == 5'b0) begin
      if (f == 10'b0) begin
        // zero
        y = {s, 8'b0, 23'b0};
      end else begin
        // subnormal -> normalize
        frac = f;
        sh = 0;
        while (frac[9] == 1'b0) begin
          frac = frac << 1;
          sh = sh + 1;
        end
        // now frac[9]=1, value = (0.frac)*2^(1-bias) -> normalized to 1.xxx * 2^(...)
        // Effective exponent (unbiased) = (1-15) - sh
        exp32 = (8'd127 - 8'd15) - sh[7:0];
        y = {s, exp32, {frac[8:0], 14'b0}}; // drop leading 1, align to 23 frac (9 bits -> top)
      end
    end else if (e == 5'b11111) begin
      // inf / NaN
      if (f == 10'b0) y = {s, 8'hFF, 23'b0};
      else            y = {1'b0, 8'hFF, 23'h400000}; // quiet NaN
    end else begin
      // normal
      exp32 = e - 5'd15 + 8'd127;
      y = {s, exp32, {f, 13'b0}};
    end
  end

  assign o_fp32 = y;

endmodule

`default_nettype wire