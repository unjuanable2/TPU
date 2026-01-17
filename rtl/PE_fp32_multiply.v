`timescale 1ps/1ps
`default_nettype none

module PE_fp32_multiply (
  input wire [31:0] i_fp32_a; // = (-1)^{s_a} * 1.f_a * 2^{(e_a-127)}
  input wire [31:0] i_fp32_b; // = (-1)^{s_b} * 1.f_b * 2^{(e_b-127)}
  output wire [31:0] o_fp32_output; // = i_fp32_a * i_fp32_b = (1.f_a * 1.f_b) * 2^{(e_a-127+e_b-127)} 
  output wire o_fp32_output_is_zero; // Indicates if the output is 0
  output wire o_fp32_output_is_inf; // Indicates if the output is infinite
  output wire o_fp32_output_is_nan; // Indicates if the output is not a number/ invalid
  output wire o_fp32_output_overflow; // Indicates if the output has overflow
  output wire o_fp32_output_underflow; // Indicates if the output doesn't have overflow
);

/* 1. Input Preprocessing */
// 1.1. Extract the sign, exponent, and fraction from the input 32-bit floating-point numbers
wire s_a = i_fp32_a[31];
wire [7:0] e_a = i_fp32_a[30:23];
wire [22:0] f_a = i_fp32_a[22:0];

wire s_b = i_fp32_b[31];
wire [7:0] e_b = i_fp32_b[30:23];
wire [22:0] f_b = i_fp32_b[22:0];

// 1.2. Handle special cases (zero, inf, NaN, subnormal)
wire a_is_zero = (e_a == 8'b0) ;//&& (f_a == 23'b0);
wire a_is_inf = (e_a == 8'b11111111) && (f_a == 23'b0);
wire a_is_nan = (e_a == 8'b11111111) && (f_a != 23'b0);
//wire a_is_subnormal = (e_a == 8'b0) && (f_a != 23'b0); // not used here

wire b_is_zero = (e_b == 8'b0) ;//&& (f_b == 23'b0); // zero+subnormal
wire b_is_inf = (e_b == 8'b11111111) && (f_b == 23'b0);
wire b_is_nan = (e_b == 8'b11111111) && (f_b != 23'b0);
//wire b_is_subnormal = (e_b == 8'b0) && (f_b != 23'b0); // not used here

// 输出NaN: a or b is NaN, or inf * 0 / 0 * inf
assign o_fp32_output_is_nan = a_is_nan || b_is_nan || (a_is_inf && b_is_zero) || (a_is_zero && b_is_inf);
// 输出inf: inf * non-zero finite / non-zero finite * inf / inf * inf
assign o_fp32_output_is_inf = (a_is_inf && !(b_is_zero || b_is_nan)) || (!(a_is_zero || a_is_nan) && b_is_inf) || (a_is_inf && b_is_inf);
// 输出0: zero * finite / finite * zero / zero * zero 
assign o_fp32_output_is_zero = (a_is_zero && !(b_is_inf || b_is_nan)) || (b_is_zero && !(a_is_inf || a_is_nan)) || (a_is_zero && b_is_zero);

// 1.3. Decide the sign of the output
wire s_output = s_a ^ s_b; 

/* 2. Multiply the fractions */
wire [47:0] f_output_0 = (48'h1 << 23 | f_a) * (48'h1 << 23 | f_b); // 1.f_a * 1.f_b
         // f_output_0[47:46] is the integer part in [1,4), f_output_0[45:0] is the fractional part
wire [47:0] f_output_1 = (f_output_0[47] == 1'b0) ? f_output_0 : // if f_output_0 < 2, it is already
                       f_output_0 >> 1; 
         // f_output_1[47:46] is the integer part in [1,2), f_output_1[45:0] is the fractional part.

/* 3. Add the exponents */
wire signed [10:0] e_output_0 = {2'b0, e_a} + {2'b0, e_b} - 10'd127; // e_a - 127 + e_b - 127 + 127 = e_a + e_b - 127
wire signed [10:0] e_output_1 = (f_output_0[47] == 1'b0) ? e_output_0 : 
                      e_output_0 + 1;

/* 4. 尾数舍入处理 fraction rounding (rule: RNE/ round-to-nearest-even) */
wire [24:0] f_output_2 = {1'b0, 1'b1, f_output_1[45:23]}; // 01.f_output_1[45:23]
wire inc = (f_output_1[22] && (f_output_1[21:0] != 0)) || (f_output_1[22] && (f_output_1[21:0] == 0) && (f_output_1[23] == 1'b1)); // RNE
wire [24:0] f_output_rounded =  f_output_2 + {24'b0, inc};

/* 5. special case: if f_output_2 are all 1s (01.1111...1), 
f_output_rounded is 10.0000, so we need to set f_output to 0 and add 1 to e_output
*/
wire [22:0] f_output_final = (f_output_rounded[24] == 1'b1) ? f_output_rounded[23:1] : f_output_rounded[22:0];
wire signed [10:0] e_output_final = (f_output_rounded[24] == 1'b1) ? e_output_1 + 1 : e_output_1;

/* 6. Handle overflow and underflow */
assign o_fp32_output_overflow = (e_output_final >= 11'sd255) && !o_fp32_output_is_inf && !o_fp32_output_is_nan; // overflow
assign o_fp32_output_underflow = (e_output_final <= 11'sd0) && !o_fp32_output_is_inf && !o_fp32_output_is_nan; // underflow

/* 7. Construct the output */
assign o_fp32_output = o_fp32_output_is_nan ? {1'b0, 8'b11111111, 23'h1} : // NaN
                       o_fp32_output_is_inf ? {s_output, 8'b11111111, 23'b0} : // inf
                       o_fp32_output_is_zero ? {s_output, 8'b0, 23'b0} : // zero
                       o_fp32_output_underflow ? {s_output, 8'b0, 23'b0} : // underflow to zero
                       o_fp32_output_overflow ? {s_output, 8'b11111111, 23'b0} : // overflow to inf
                       {s_output, e_output_final[7:0], f_output_final}; // normal case

endmodule
`default_nettype wire