module CTRL_DATA_TRANS #(
    parameter ROW     = 4,
    parameter DW      = 32,
    parameter DW_OUT  = 32,
    parameter FIFO_DW = 128
)(
    input  wire                   sys_clk,
    input  wire                   rst_n,
    input  wire                   cpu_sw_rst_sync,
    input  wire [1:0]             cpu_cpt_mode_sync,
    input  wire                   fifo_in_re,
    input  wire [FIFO_DW-1:0]     fifo_in_rdata,
    output wire                   dat_out_vld,
    output wire [ROW*DW_OUT-1:0]  dat_out
);

localparam MAX_DLY = 16;

wire [3:0] L = (cpu_cpt_mode_sync == 2'b10) ? 4'd3 : 
               (cpu_cpt_mode_sync == 2'b11) ? 4'd4 : 4'd1;
wire [3:0] tap1 = L;
wire [3:0] tap2 = 2 * L;
wire [3:0] tap3 = 3 * L;
reg [DW_OUT-1:0] row1_sr [0:MAX_DLY-1];
reg [DW_OUT-1:0] row2_sr [0:MAX_DLY-1];
reg [DW_OUT-1:0] row3_sr [0:MAX_DLY-1];
reg [MAX_DLY-1:0] row_vld_sr;
reg [DW_OUT-1:0] row0_out;

assign dat_out[31:0]   = row0_out;
assign dat_out[63:32]  = row1_sr[tap1-1];
assign dat_out[95:64]  = row2_sr[tap2-1];
assign dat_out[127:96] = row3_sr[tap3-1];
assign dat_out_vld     = row_vld_sr[tap3-1];

always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n)               row0_out <= 0;
  else if (cpu_sw_rst_sync) row0_out <= 0;
  else if (fifo_in_re)      row0_out <= fifo_in_rdata[31:0];
end

integer i;
always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n) begin
    for (i=0; i<MAX_DLY; i=i+1) begin
      row1_sr[i] <= 0; row2_sr[i] <= 0; row3_sr[i] <= 0;
    end
    row_vld_sr <= 0;
    
  end else if (fifo_in_re) begin
    row1_sr[0] <= fifo_in_rdata[63:32];
    row2_sr[0] <= fifo_in_rdata[95:64];
    row3_sr[0] <= fifo_in_rdata[127:96];
    for (i=1; i<MAX_DLY; i=i+1) begin
      row1_sr[i] <= row1_sr[i-1];
      row2_sr[i] <= row2_sr[i-1];
      row3_sr[i] <= row3_sr[i-1];
    end
    row_vld_sr <= {row_vld_sr[MAX_DLY-2:0], 1'b1};
    
  end else begin
    for (i=1; i<MAX_DLY; i=i+1) begin
      row1_sr[i] <= row1_sr[i-1];
      row2_sr[i] <= row2_sr[i-1];
      row3_sr[i] <= row3_sr[i-1];
    end
    row_vld_sr <= {row_vld_sr[MAX_DLY-2:0], 1'b0};
  end
end

endmodule
