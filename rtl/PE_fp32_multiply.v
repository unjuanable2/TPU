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

// 1. Input Preprocessing 
// 1.1. Extract the sign, exponent, and fraction from the input 32-bit floating-point numbers
wire s_a = i_fp32_a[31];
wire [7:0] e_a = i_fp32_a[30:23];
wire [22:0] f_a = i_fp32_a[22:0];

wire s_b = i_fp32_b[31];
wire [7:0] e_b = i_fp32_b[30:23];
wire [22:0] f_b = i_fp32_b[22:0];

// 1.2. Handle special cases (zero, inf, NaN, subnormal)
wire a_is_zero = (e_a == 8'b0) && (f_a == 23'b0);
wire a_is_inf = (e_a == 8'b11111111) && (f_a == 23'b0);
wire a_is_nan = (e_a == 8'b11111111) && (f_a != 23'b0);
wire a_is_subnormal = (e_a == 8'b0) && (f_a != 23'b0);

wire b_is_zero = (e_b == 8'b0) && (f_b == 23'b0);
wire b_is_inf = (e_b == 8'b11111111) && (f_b == 23'b0);
wire b_is_nan = (e_b == 8'b11111111) && (f_b != 23'b0);
wire b_is_subnormal = (e_b == 8'b0) && (f_b != 23'b0);

assign o_fp32_output_is_zero = a_is_zero || b_is_zero;
assign o_fp32_output_is_inf = (a_is_inf && !b_is_zero) || (!a_is_zero && b_is_inf);
assign o_fp32_output_is_nan = a_is_nan || b_is_nan || (a_is_inf && b_is_inf);

// 1.3. Decide the sign of the output
wire s_output = s_a ^ s_b; 

// 2. Multiply the fractions
wire [47:0] f_output_initial = (48'h1 << 23 | f_a) * (48'h1 << 23 | f_b); // 1.f_a * 1.f_b
         // f_output_initial[47:46] is the integer part, f_output_initial[45:0] is the fractional part
wire [22:0] f_output;
assign f_output = (f_output_initial[47:46] < 2'b01) ? f_output_initial[45:23] : // if f_output_initial < 2, it is already
                  (f_output_initial >> 1)[45:23]; 




endmodule
`default_nettype wire