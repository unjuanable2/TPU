module TPU_CTRL #(
    parameter ROW     = 4,
    parameter COL     = 4,
    parameter DW      = 32, // input data width
    parameter DW_OUT  = 32, // output data width
    parameter FIFO_DW = 128 // FIFO data width, should be no less than ROW*DW
)(  
    // System interface
    input  wire rst_n,   // 来自 CPU 的全局复位信号，低电平有效
    input  wire sys_clk, // 系统时钟域(400MHz)
    input  wire ahb_clk, // AHB 时钟域(100MHz)
    
    // REG_MAP interface
    input  wire        cpu_tpu_en, // TPU 模块使能信号，静态配置
    input  wire        cpu_sw_rst, // 
    input  wire        cpu_tpu_start,
    input  wire [1:0]  cpu_cpt_mode,
    output wire        rpt_compute_done,
    output wire [31:0] rpt_loop_count,
    output wire [2:0]  rpt_fsm_state,
    output wire        rpt_error_state,
    
    // SA_TOP interface
    output wire                  cpu_sw_rst_sync,
    output wire                  cpu_tpu_start_sync,
    output wire                  dat_out_vld,
    output wire [ROW*DW_OUT-1:0] dat_out,
    
    // AXI interface
    output wire       cpu_tpu_en_sync,
    output reg        rd_start,
    output reg        wr_start,
    output reg [31:0] wr_out_len,
    
    // FIFO_IN interface
    output wire               fifo_in_re,
    input  wire               fifo_pre_empty,
    input  wire [FIFO_DW-1:0] fifo_in_rdata
);

localparam IDLE  = 3'd0;
localparam CALC  = 3'd1;
localparam DRAIN = 3'd2;
localparam DONE  = 3'd3;

reg  [2:0] cur_state, next_state;
reg  [31:0] input_cnt;
reg  [31:0] drain_cnt;
wire [1:0] cpu_cpt_mode_sync;
wire [3:0] L;
wire [31:0] drain_max = (ROW-1)*L + (COL-1);
wire cpt_error;

assign cpt_error = 1'b0;
assign L = (cpu_cpt_mode_sync == 2'b10) ? 4'd3 : 
           (cpu_cpt_mode_sync == 2'b11) ? 4'd4 : 4'd1;
assign fifo_in_re = (cur_state == CALC) && !fifo_pre_empty;

CTRL_CFG u_cfg(
  .sys_clk            (sys_clk),
  .rst_n              (rst_n),
  .cpu_tpu_en         (cpu_tpu_en),
  .cpu_sw_rst         (cpu_sw_rst),
  .cpu_tpu_start      (cpu_tpu_start),
  .cpu_cpt_mode       (cpu_cpt_mode),
  .cpu_tpu_en_sync    (cpu_tpu_en_sync),
  .cpu_sw_rst_sync    (cpu_sw_rst_sync),
  .cpu_tpu_start_sync (cpu_tpu_start_sync),
  .cpu_cpt_mode_sync  (cpu_cpt_mode_sync)
);

CTRL_DATA_TRANS #(
  .ROW     (ROW),
  .DW      (DW),
  .DW_OUT  (DW_OUT),
  .FIFO_DW (FIFO_DW)
) u_data_trans (
  .sys_clk            (sys_clk),
  .rst_n              (rst_n),
  .cpu_sw_rst_sync    (cpu_sw_rst_sync),
  .cpu_cpt_mode_sync  (cpu_cpt_mode_sync),
  .fifo_in_re         (fifo_in_re),
  .fifo_in_rdata      (fifo_in_rdata),
  .dat_out_vld        (dat_out_vld),
  .dat_out            (dat_out)
);

CTRL_RPT u_rpt (
  .ahb_clk            (ahb_clk),
  .rst_n              (rst_n),
  .compute_done       (cur_state == DONE),
  .input_cnt          (input_cnt),
  .cur_state          (cur_state),
  .cpt_error          (cpt_error),
  .rpt_compute_done   (rpt_compute_done),
  .rpt_loop_count     (rpt_loop_count),
  .rpt_fsm_state      (rpt_fsm_state),
  .rpt_error_state    (rpt_error_state)
);

always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n)                 cur_state <= IDLE;
  else if (cpu_sw_rst_sync)    cur_state <= IDLE;
  else                        cur_state <= next_state;
end

always @(*) begin
  next_state = cur_state;
  case (cur_state)
    IDLE:  if (cpu_tpu_en_sync && cpu_tpu_start_sync) next_state = CALC;
    CALC:  if (fifo_pre_empty && (input_cnt > 0))      next_state = DRAIN;
    DRAIN: if (drain_cnt >= drain_max)                next_state = DONE;
    DONE:  next_state = IDLE;
    default: next_state = IDLE;
  endcase
end

always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n) rd_start <= 1'b0;
  else        rd_start <= (cur_state == IDLE) && cpu_tpu_en_sync && cpu_tpu_start_sync;
end


always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n)               input_cnt <= 32'd0;
  else if (cur_state == IDLE) input_cnt <= 32'd0;
  else if (fifo_in_re)      input_cnt <= input_cnt + 1'b1;
end

always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n) wr_start <= 1'b0;
  else        wr_start <= (cur_state == CALC) && fifo_pre_empty && (input_cnt > 0);
end

always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n)               wr_out_len <= 32'd0;
  else if (cur_state == CALC) wr_out_len <= input_cnt + drain_max;
end

always @(posedge sys_clk or negedge rst_n) begin
  if (!rst_n)                drain_cnt <= 32'd0;
  else if (cur_state != DRAIN) drain_cnt <= 32'd0;
  else                        drain_cnt <= drain_cnt + 1'b1;
end

endmodule