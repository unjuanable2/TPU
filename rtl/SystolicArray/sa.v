// Parameterized systolic array
module SA_TOP #(
    parameter ROW    = 4,
    parameter COL    = 4,
    parameter DW     = 32,
    parameter DW_OUT = 32
)(
    input                             clk,
    input                             rst_n,

    // CPU interface (synchronous pulses)
    input                             cpu_sw_rst_sync,
    input                             cpu_tpu_start_sync,

    // Control
    input                             tpu_en,
    input      [1:0]                  cpt_mode,

    // Input data from the left side of the systolic array.
    // data_in_a packs one A value per row.
    // data_in_b packs one stationary B/weight value per PE.
    input                             data_in_vld,
    input      [ROW*DW-1:0]           data_in_a,
    input      [ROW*COL*DW-1:0]       data_in_b,

    // Bottom-row outputs, one value per column.
    output     [COL*DW_OUT-1:0]       data_out,
    output                            data_out_vld
);

    // Compute cycles = array fill/flush cycles + PE internal latency.
    localparam integer BASE_CYCLES       = ROW + COL - 1;
    localparam integer MAX_PE_LATENCY    = 3; // max{INT4/8=1, FP32=3, FP16=3}
    localparam integer MATMUL_CYCLES_MAX = BASE_CYCLES + MAX_PE_LATENCY;
    localparam integer CNT_W             = (MATMUL_CYCLES_MAX <= 1) ? 1 :
                                           $clog2(MATMUL_CYCLES_MAX);

    reg  [CNT_W-1:0] counter;
    reg              flag_clear;

    wire [2:0]       pe_lat_by_mode;
    wire [CNT_W-1:0] matmul_cycles;

    wire [ROW*COL*DW-1:0]     pe_a_bus;
    wire [ROW*COL*DW_OUT-1:0] pe_psum_bus;
    wire [ROW*COL-1:0]        pe_a_vld_bus;
    wire [ROW*COL-1:0]        pe_psum_vld_bus;
    wire [COL-1:0]            bottom_vld;

    assign pe_lat_by_mode = (cpt_mode == 2'b11) ? 3'd3 :
                            (cpt_mode == 2'b10) ? 3'd3 :
                                                   3'd1;
    assign matmul_cycles = BASE_CYCLES + pe_lat_by_mode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter    <= {CNT_W{1'b0}};
            flag_clear <= 1'b0;
        end else if (cpu_sw_rst_sync) begin
            counter    <= {CNT_W{1'b0}};
            flag_clear <= 1'b1;
        end else if (tpu_en && cpu_tpu_start_sync) begin
            counter    <= {CNT_W{1'b0}};
            flag_clear <= 1'b1;
        end else if (tpu_en && data_in_vld) begin
            if (counter == (matmul_cycles - 1'b1)) begin
                counter    <= {CNT_W{1'b0}};
                flag_clear <= 1'b1;
            end else begin
                counter    <= counter + 1'b1;
                flag_clear <= 1'b0;
            end
        end else begin
            counter    <= {CNT_W{1'b0}};
            flag_clear <= 1'b0;
        end
    end

    genvar r, c;
    generate
        for (r = 0; r < ROW; r = r + 1) begin : GEN_ROW
            for (c = 0; c < COL; c = c + 1) begin : GEN_COL
                localparam integer PE_IDX = r * COL + c;

                wire [DW-1:0]     pe_input_in;
                wire [DW_OUT-1:0] pe_psum_in;
                wire [DW-1:0]     pe_weight_in;
                wire              pe_input_vld_in;
                wire              pe_psum_vld_in;
                wire              pe_data_vld_in;
                wire [DW-1:0]     pe_input_out;
                wire [DW_OUT-1:0] pe_psum_out;
                wire              pe_input_vld_out;
                wire              pe_psum_vld_out;

                assign pe_input_in = (c == 0) ?
                                     data_in_a[(r+1)*DW-1 -: DW] :
                                     pe_a_bus[((r*COL + c-1)+1)*DW-1 -: DW];

                assign pe_input_vld_in = (c == 0) ?
                                         data_in_vld :
                                         pe_a_vld_bus[r*COL + c-1];

                assign pe_psum_in = (r == 0) ?
                                    {DW_OUT{1'b0}} :
                                    pe_psum_bus[(((r-1)*COL + c)+1)*DW_OUT-1 -: DW_OUT];

                assign pe_psum_vld_in = (r == 0) ?
                                        1'b1 :
                                        pe_psum_vld_bus[(r-1)*COL + c];

                assign pe_weight_in   = data_in_b[(PE_IDX+1)*DW-1 -: DW];
                assign pe_data_vld_in = pe_input_vld_in & pe_psum_vld_in;

                PE_MP #(
                    .DATA_IN    (DW),
                    .DATA_OUT   (DW_OUT),
                    .MODE_WIDTH (2)
                ) u_pe (
                    .clk          (clk),
                    .rst_n        (rst_n),
                    .tpu_en       (tpu_en),
                    .data_in_b    (pe_weight_in),
                    .cpt_mode     ({30'd0, cpt_mode}),
                    .flag         (flag_clear),
                    .data_in_vld  (pe_data_vld_in),
                    .data_in_a    (pe_input_in),
                    .data_in_add  (pe_psum_in),
                    .data_out_vld (pe_psum_vld_out),
                    .data_out     (pe_psum_out),
                    .out_a        (pe_input_out),
                    .out_a_vld    (pe_input_vld_out)
                );

                assign pe_a_bus[(PE_IDX+1)*DW-1 -: DW]          = pe_input_out;
                assign pe_psum_bus[(PE_IDX+1)*DW_OUT-1 -: DW_OUT] = pe_psum_out;
                assign pe_a_vld_bus[PE_IDX]                    = pe_input_vld_out;
                assign pe_psum_vld_bus[PE_IDX]                 = pe_psum_vld_out;
            end
        end
    endgenerate

    generate
        for (c = 0; c < COL; c = c + 1) begin : GEN_OUT
            assign data_out[(c+1)*DW_OUT-1 -: DW_OUT] =
                   pe_psum_bus[(((ROW-1)*COL + c)+1)*DW_OUT-1 -: DW_OUT];
            assign bottom_vld[c] = pe_psum_vld_bus[(ROW-1)*COL + c];
        end
    endgenerate

    assign data_out_vld = tpu_en & (&bottom_vld);

endmodule
