`timescale 1ps/1ps
`default_nettype none

module int32_to_fp32 (
  input  wire signed [31:0] i_i32,
  output wire [31:0] o_fp32
);
  reg [31:0] y;

  reg sign;
  reg [31:0] a;         // abs
  integer msb;
  reg [7:0] exp;
  reg [55:0] shifted;   // room for rounding
  reg [23:0] mant24;
  reg guard, sticky, lsb, inc;

  function automatic integer find_msb(input [31:0] v);
    integer k;
    begin
      find_msb = -1;
      for (k = 31; k >= 0; k = k - 1) begin
        if (v[k]) begin
          find_msb = k;
          k = -1;
        end
      end
    end
  endfunction

  always @* begin
    if (i_i32 == 32'sd0) begin
      y = 32'b0;
    end else begin
      sign = i_i32[31];
      a = sign ? (~i_i32 + 1'b1) : i_i32;

      msb = find_msb(a);
      exp = msb + 8'd127;

      // Normalize so that msb lands at bit 23 of mant24 (1.xxx)
      if (msb > 23) begin
        integer rshift;
        rshift = msb - 23;

        // create extended value to compute guard/sticky
        shifted = {a, 24'b0}; // push left for easy slicing
        // mant24 is top 24 bits after shifting right by rshift
        mant24 = a >> rshift;

        // rounding bits come from the bits shifted out
        guard  = (rshift > 0) ? ((a >> (rshift - 1)) & 1'b1) : 1'b0;
        sticky = (rshift > 1) ? (|(a & ((32'h1 << (rshift - 1)) - 1))) : 1'b0;
        lsb    = mant24[0];
        inc    = guard & (sticky | lsb);

        mant24 = mant24 + inc;

        // handle carry (1.111.. +1 -> 10.000..)
        if (mant24[23] == 1'b0) begin
          // shouldn't happen
        end
        if (mant24 == 24'h1000000) begin
          // became 1_000000... with extra bit (25th), renormalize
          mant24 = mant24 >> 1;
          exp = exp + 1'b1;
        end

      end else begin
        integer lshift;
        lshift = 23 - msb;
        mant24 = a << lshift;

        guard  = 1'b0;
        sticky = 1'b0;
        lsb    = mant24[0];
        inc    = 1'b0;
      end

      y = {sign, exp, mant24[22:0]};
    end
  end

  assign o_fp32 = y;

endmodule

`default_nettype wire
