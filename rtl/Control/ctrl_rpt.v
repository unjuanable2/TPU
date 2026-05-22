module CTRL_RPT (
    input  wire        ahb_clk,
    input  wire        rst_n,
    input  wire        compute_done,
    input  wire [31:0] input_cnt,      
    input  wire [2:0]  cur_state,      
    input  wire        cpt_error, 
    output wire        rpt_compute_done,
    output reg  [31:0] rpt_loop_count,
    output reg  [2:0]  rpt_fsm_state,
    output reg         rpt_error_state
);

reg [2:0] done_sync_d;
reg [2:0] fsm_d1, fsm_d2;
reg       err_d1, err_d2;
reg [31:0] cnt_d1, cnt_d2;

assign rpt_compute_done = done_sync_d[1] & ~done_sync_d[2];

always @(posedge ahb_clk or negedge rst_n) begin
    if (!rst_n) done_sync_d <= 3'b0;
    else        done_sync_d <= {done_sync_d[1:0], compute_done};
end

always @(posedge ahb_clk or negedge rst_n) begin
    if (!rst_n) begin
        fsm_d1 <= 3'b0; fsm_d2 <= 3'b0;
        err_d1 <= 1'b0; err_d2 <= 1'b0;
        cnt_d1 <= 32'd0; cnt_d2 <= 32'd0;
    end else begin
        fsm_d1 <= cur_state; fsm_d2 <= fsm_d1;
        err_d1 <= cpt_error; err_d2 <= err_d1;
        cnt_d1 <= input_cnt; cnt_d2 <= cnt_d1;
    end
end

always @(*) begin
    rpt_fsm_state   = fsm_d2;
    rpt_error_state = err_d2;
    rpt_loop_count  = cnt_d2;
end

endmodule