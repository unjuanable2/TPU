`timescale 1ps/1ps
`default_nettype none

module PE_fp32_multiply_tb();

// Instance of the PE_fp32_multiply module
reg [31:0] fp32_a, fp32_b; // 32-bit inputs for single-precision
wire [31:0] fp32_output; // 32-bit output for single-precision
wire fp32_output_is_zero; // Flag for zero output
wire fp32_output_is_inf; // Flag for infinite output
wire fp32_output_is_nan; // Flag for NaN output
wire fp32_output_overflow, fp32_output_underflow; // Flags for overflow and underflow

PE_fp32_multiply iDUT (
  .i_fp32_a(fp32_a),
  .i_fp32_b(fp32_b),
  .o_fp32_output(fp32_output),
  .o_fp32_output_is_zero(fp32_output_is_zero), // Indicates if the output is 0
  .o_fp32_output_is_inf(fp32_output_is_inf), // Indicates if the output is infinite
  .o_fp32_output_is_nan(fp32_output_is_nan), // Indicates if the output is not a number/ invalid
  .o_fp32_output_overflow(fp32_output_overflow), // Indicates if the output has overflow
  .o_fp32_output_underflow(fp32_output_underflow) // Indicates if the output doesn't have overflow
);

// Testbench stimulus
initial begin
  // Test case 1: Normal multiplication
  fp32_a = 32'h3F800000; // 1.0 in IEEE 754
  fp32_b = 32'h40000000; // 2.0 in IEEE 754
  #10; // Wait for 10 time units
  $display("Test Case 1: 1.0 * 2.0");
  $display("Output: %h", fp32_output);
  $display("Is Zero: %b, Is Inf: %b, Is NaN: %b, Overflow: %b, Underflow: %b", 
           fp32_output_is_zero, fp32_output_is_inf, fp32_output_is_nan, fp32_output_overflow, fp32_output_underflow);
end

endmodule
`default_nettype wire
