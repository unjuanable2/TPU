`timescale 1ps/1ps
`default_nettype none

module fp32_to_fp16 (
  input  wire [31:0] i_fp32,
  output wire [15:0] o_fp16
);
  wire s = i_fp32[31];
  wire [7:0] e = i_fp32[30:23];
  wire [22:0] f = i_fp32[22:0];

  wire is_zero = (e == 8'b0) && (f == 23'b0);
  wire is_inf  = (e == 8'hFF) && (f == 23'b0);
  wire is_nan  = (e == 8'hFF) && (f != 23'b0);

  reg [15:0] y;

  // helper for rounding
  reg [24:0] mant25; // 1.xxx with extra bits for shifting/round
  reg [4:0]  e16;
  integer shift;
  reg guard, sticky, lsb;
  reg inc;

  reg [23:0] mant24; // {1, frac}

  always @* begin
    y = 16'b0;

    if (is_nan) begin
      y = {1'b0, 5'h1F, 10'h200}; // qNaN
    end else if (is_inf) begin
      y = {s, 5'h1F, 10'b0};
    end else if (is_zero) begin
      y = {s, 5'b0, 10'b0};
    end else begin
      // normal/subnormal in fp32
      // unbiased exponent:
      // exp32_unb = e - 127
      // exp16 = exp32_unb + 15
      integer exp16i;
      exp16i = $signed({1'b0,e}) - 127 + 15;

      mant24 = {1'b1, f}; // assume normalized input; subnormal fp32 not handled here (rare in your PE pipeline)

      if (exp16i >= 31) begin
        // overflow -> inf
        y = {s, 5'h1F, 10'b0};
      end else if (exp16i <= 0) begin
        // underflow -> subnormal/zero in fp16
        // we generate subnormal and do RNE
        // shift right by (1-exp16i) to place leading 1 into subnormal range
        shift = 1 - exp16i; // >=1
        if (shift > 24) begin
          y = {s, 5'b0, 10'b0};
        end else begin
          // create a wider mant with room for guard/sticky
          // we want 10 frac bits; take mantissa right shift (shift + 13) effectively
          // Build a 25-bit value: 0.XXXXXXXXXXXXXXX (we'll pick top 10 and use GRS)
          // Do it by forming a 25-bit mant with extra 1 bit, then shifting.
          // Use mant25 = {1'b0, mant24} (25 bits)
          mant25 = {1'b0, mant24};
          // We need to align so that output fraction is mant25[23:14] after total shift=shift+?:
          // easier: produce a 24+? bit stream then pick.
          // We'll directly compute candidate 10-bit fraction from (mant24 >> (shift + 13)).
          // For rounding, guard is next bit, sticky is OR of remaining bits.
          integer rshift;
          rshift = shift + 13;

          if (rshift >= 24) begin
            // everything shifts out -> maybe 0 with sticky
            guard  = 1'b0;
            sticky = |mant24;
            lsb    = 1'b0;
            inc    = 1'b0; // too tiny
            y = {s, 5'b0, 10'b0};
          end else begin
            // fraction candidate
            reg [10:0] frac11; // include an extra bit to catch carry into hidden (not used for subnorm)
            frac11 = mant24 >> rshift; // LSB is bit0
            // rounding bits
            guard  = (rshift-1 >= 0) ? ((mant24 >> (rshift-1)) & 1'b1) : 1'b0;
            sticky = (rshift-2 >= 0) ? (|(mant24 & ((24'h1 << (rshift-1)) - 1))) : 1'b0;
            lsb    = frac11[0];

            inc = guard & (sticky | lsb); // RNE
            // take 10 bits
            reg [9:0] frac10;
            frac10 = frac11[9:0] + inc;
            y = {s, 5'b0, frac10};
          end
        end
      end else begin
        // normal fp16
        e16 = exp16i[4:0];

        // take top 10 frac bits from mant24 (1.f23): keep bits [22:13] as frac10
        // rounding: guard = bit12, sticky = OR[11:0], lsb = bit13
        lsb    = mant24[13];
        guard  = mant24[12];
        sticky = |mant24[11:0];
        inc    = guard & (sticky | lsb);

        // 1 + 10 frac = 11 bits (hidden+frac)
        reg [10:0] mant11;
        mant11 = {1'b1, mant24[22:13]} + inc;

        // handle carry from 1.111.. + 1 -> 10.000..
        if (mant11[10] == 1'b0) begin
          // should not happen
          y = {s, e16, mant11[9:0]};
        end else if (mant11 == 11'b10_0000000000) begin
          // renormalize
          if (e16 == 5'h1E) begin
            y = {s, 5'h1F, 10'b0}; // overflow to inf
          end else begin
            y = {s, e16 + 1'b1, 10'b0};
          end
        end else begin
          y = {s, e16, mant11[9:0]};
        end
      end
    end
  end

  assign o_fp16 = y;

endmodule

`default_nettype wire
