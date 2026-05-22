module CTRL_CFG (
    input  wire       sys_clk,
    input  wire       rst_n,
    input  wire       cpu_tpu_en,
    input  wire       cpu_sw_rst,
    input  wire       cpu_tpu_start,
    input  wire [1:0] cpu_cpt_mode,
    output wire       cpu_tpu_en_sync,
    output wire       cpu_sw_rst_sync,
    output wire       cpu_tpu_start_sync,
    output wire [1:0] cpu_cpt_mode_sync
);

reg [1:0] tpu_en_d;
reg [1:0] cpt_mode_d1, cpt_mode_d2;
reg [2:0] sw_rst_d;
reg [2:0] tpu_start_d;

assign cpu_tpu_en_sync = tpu_en_d[1];
assign cpu_cpt_mode_sync = cpt_mode_d2;
assign cpu_sw_rst_sync = sw_rst_d[1] & ~sw_rst_d[2];
assign cpu_tpu_start_sync = tpu_start_d[1] & ~tpu_start_d[2];

always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n) tpu_en_d <= 2'b0;
  else        tpu_en_d <= {tpu_en_d[0], cpu_tpu_en};
end

always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n) begin
    cpt_mode_d1 <= 2'b0;
    cpt_mode_d2 <= 2'b0;
  end else begin
    cpt_mode_d1 <= cpu_cpt_mode;
    cpt_mode_d2 <= cpt_mode_d1;
  end
end

always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n) sw_rst_d <= 3'b0;
  else        sw_rst_d <= {sw_rst_d[1:0], cpu_sw_rst};
end

always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n) tpu_start_d <= 3'b0;
  else        tpu_start_d <= {tpu_start_d[1:0], cpu_tpu_start};
end

endmodule