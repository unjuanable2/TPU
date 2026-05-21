module pe
  # (parameter DATA_IN    = 32,
     parameter DATA_OUT   = 32,
     parameter MODE_WIDTH = 2)
  (
    // Clock and Reset
    input wire clk,
    input wire rst_n,
    // Cfg Signals
    input wire tpu_en, // TPU enable signal configured by CPU through AHB bus
    input wire [DATA_IN-1:0] data_in_b, // B data configured by CPU through AHB bus
    input wire [31:0] cpt_mode, // 00: INT4; 01: INT8; 10: FP16; 11: FP32
    // Data In
    input wire flag, // Flag signal to indicate the end of a computation, 
                     // used to reset the internal state of the PE
    input wire data_in_vld, // Data valid signal from the left PE
    input wire [DATA_IN-1:0]  data_in_a, // A data from the left PE 
    input wire [DATA_OUT-1:0] data_in_add, // Partial sum from the above PE 

    // Data Out
    output reg data_out_vld,
    output reg [DATA_OUT-1:0] data_out,
    output reg out_a_vld,
    output reg [DATA_IN-1:0] out_a
);

localparam MODE_INT4 = 2'b00;
localparam MODE_INT8 = 2'b01;
localparam MODE_FP16 = 2'b10;
localparam MODE_FP32 = 2'b11;

// ============================================================================
// Mode and enable signals
// ============================================================================
wire [1:0] mode;
wire       enable_fp32;
wire       enable_fp16;
wire       enable_int8;
wire       enable_int4;
assign mode        = cpt_mode[1:0];
assign enable_fp32 = tpu_en && (mode == MODE_FP32);
assign enable_fp16 = tpu_en && (mode == MODE_FP16);
assign enable_int8 = tpu_en && (mode == MODE_INT8);
assign enable_int4 = tpu_en && (mode == MODE_INT4);

// ============================================================================
// FP32 path: FP32 multiply -> FP32 add
// ============================================================================
wire        fp32_mul_vld;
wire [31:0] fp32_mul_out;
pe_fp32_multiply U_FP32_MUL (
    // Input
    .clk         (clk),
    .rst_n       (rst_n),
    .vld_in      (data_in_vld && enable_fp32),
    .cpt_en      (enable_fp32),
    .a           (data_in_a),
    .b           (data_in_b),
    // Output
    .vld_out     (fp32_mul_vld),
    .out         (fp32_mul_out),
    .out_is_zero (),
    .out_is_inf  (),
    .out_is_nan  (),
    .out_is_of   (),
    .out_is_uf   ()
);

// 因为FP32的乘法器有3个周期的延迟，所以需要将加数延迟3个周期，以便与乘法结果对齐
reg  [31:0] fp32_addend_d1;
reg  [31:0] fp32_addend_d2;
reg  [31:0] fp32_addend_d3;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        fp32_addend_d1 <= 32'd0;
        fp32_addend_d2 <= 32'd0;
        fp32_addend_d3 <= 32'd0;
    end else if(!enable_fp32 || flag) begin
        fp32_addend_d1 <= 32'd0;
        fp32_addend_d2 <= 32'd0;
        fp32_addend_d3 <= 32'd0;
    end else begin // enable_fp32 && !flag
        if(data_in_vld) begin
            fp32_addend_d1 <= data_in_add;
        end
        fp32_addend_d2 <= fp32_addend_d1;
        fp32_addend_d3 <= fp32_addend_d2;
    end
end

// FP32 adder
wire [31:0] fp32_add_out;
pe_fp32_adder U_FP32_ADD (
    // Input
    .clk   (clk),
    .rst_n (rst_n),
    .a     (fp32_mul_out),
    .b     (fp32_addend_d3),
    // Output
    .out   (fp32_add_out)
);

// 输出 fp32_out
wire [31:0] fp32_out;
assign fp32_out = fp32_add_out;

// 输出 fp32_out_vld
// 因为FP32的加法器有1个周期的延迟，所以fp32_out_vld需要延迟1个周期
reg fp32_out_vld;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        fp32_out_vld <= 1'b0;
    end else if(!enable_fp32 || flag) begin
        fp32_out_vld <= 1'b0;
    end else begin
        fp32_out_vld <= fp32_mul_vld;
    end
end

// ============================================================================
// FP16 path: FP16->INT16 -> INT32 product -> INT32->FP32 -> FP32 add
// ============================================================================
// 取输入数据 data_in_a, data_in_b 低 16 位, 浮定转换为 signed int16
wire fp16_a_vld, fp16_b_vld;
wire [15:0] fp16_a_int16;
wire [15:0] fp16_b_int16;
pe_fp16_int16 U_FP16_A_TO_INT16 (
    // Input
    .clk       (clk),
    .rst_n     (rst_n),
    .vld_in    (data_in_vld && enable_fp16),
    .cpt_en    (enable_fp16),
    .in        (data_in_a[15:0]),
    // Output
    .vld_out   (fp16_a_vld),
    .out       (fp16_a_int16),
    .out_is_of (),
    .out_is_uf ()
);
pe_fp16_int16 U_FP16_B_TO_INT16 (
    // Input
    .clk       (clk),
    .rst_n     (rst_n),
    .vld_in    (data_in_vld && enable_fp16),
    .cpt_en    (enable_fp16),
    .in        (data_in_b[15:0]),
    // Output
    .vld_out   (fp16_b_vld),
    .out       (fp16_b_int16),
    .out_is_of (),
    .out_is_uf ()
);

// int16 定点乘法得到 int32 product
wire fp16_product_vld;
wire signed [31:0] fp16_product_int;
assign fp16_product_vld = fp16_a_vld && fp16_b_vld;
assign fp16_product_int = $signed(fp16_a_int16) * $signed(fp16_b_int16);

// int32 转换为 fp32
wire fp16_product_fp32_vld;
wire [31:0] fp16_product_fp32;
pe_int32_fp32 U_FP16_PRODUCT_TO_FP32 (
    // Input
    .clk         (clk),
    .rst_n       (rst_n),
    .vld_in      (fp16_product_vld),
    .cpt_en      (enable_fp16),
    .in          (fp16_product_int),
    // Output
    .vld_out     (fp16_product_fp32_vld),
    .out         (fp16_product_fp32),
    .out_is_zero ()
);

// 因为 pe_fp16_int16 有 1 个周期的延迟，pe_int32_fp32 有 2 个周期的延迟，
// 总共有3个周期的延迟，所以需要将加数延迟3个周期，以便与乘法结果对齐。
reg  [31:0] fp16_addend_d1;
reg  [31:0] fp16_addend_d2;
reg  [31:0] fp16_addend_d3;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        fp16_addend_d1 <= 32'd0;
        fp16_addend_d2 <= 32'd0;
        fp16_addend_d3 <= 32'd0;
    end else if(!enable_fp16 || flag) begin
        fp16_addend_d1 <= 32'd0;
        fp16_addend_d2 <= 32'd0;
        fp16_addend_d3 <= 32'd0;
    end else begin
        if(data_in_vld) begin
            fp16_addend_d1 <= data_in_add;
        end
        fp16_addend_d2 <= fp16_addend_d1;
        fp16_addend_d3 <= fp16_addend_d2;
    end
end

// FP32 adder
wire [31:0] fp16_add_out;
pe_fp32_adder U_FP16_FP32_ADD (
    // Input
    .clk   (clk),
    .rst_n (rst_n),
    .a     (fp16_product_fp32),
    .b     (fp16_addend_d3),
    // Output
    .out   (fp16_add_out)
);

// 输出 fp16_out
wire [31:0] fp16_out;
assign fp16_out = fp16_add_out;

// 输出 fp16_out_vld
reg fp16_out_vld;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        fp16_out_vld <= 1'b0;
    end else if(!enable_fp16 || flag) begin
        fp16_out_vld <= 1'b0;
    end else begin
        fp16_out_vld <= fp16_product_fp32_vld;
    end
end

// ============================================================================
// INT8 path: signed INT8 product + signed INT32 partial sum
// ============================================================================
// 取输入数据 data_in_a, data_in_b 低 8 位, 转换为 signed int8
wire signed [7:0] int8_a;
wire signed [7:0] int8_b;
assign int8_a = data_in_a[7:0];
assign int8_b = data_in_b[7:0];

// INT8 定点乘法得到 INT16 product
wire signed [15:0] int8_product;
assign int8_product = int8_a * int8_b;

// INT16 product 转换为 INT32, 并与 data_in_add 相加得到 INT32 sum
wire signed [31:0] int8_sum;
assign int8_sum = {{16{int8_product[15]}}, int8_product} + $signed(data_in_add);

// 输出 int8_out，和 int8_out_vld
reg int8_out_vld;
reg [31:0] int8_out;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        int8_out_vld <= 1'b0;
        int8_out     <= 32'd0;
    end else if(!enable_int8 || flag) begin
        int8_out_vld <= 1'b0;
        int8_out     <= 32'd0;
    end else begin
        int8_out_vld <= data_in_vld;
        if(data_in_vld) begin
            int8_out <= int8_sum;
        end
    end
end

// ============================================================================
// INT4 path: signed INT4 product + signed INT32 partial sum
// ============================================================================
// 将输入数据 data_in_a, data_in_b 低 4 位转换为 signed int4
wire signed [3:0] int4_a;
wire signed [3:0] int4_b;
assign int4_a = data_in_a[3:0];
assign int4_b = data_in_b[3:0];

// INT4 定点乘法得到 INT8 product
wire signed [7:0] int4_product;
assign int4_product = int4_a * int4_b;

// INT8 product 转换为 INT32, 并与 data_in_add 相加得到 INT32 sum
wire signed [31:0] int4_sum;
assign int4_sum = {{24{int4_product[7]}}, int4_product} + $signed(data_in_add);

// 输出 int4_out，和 int4_out_vld
reg int4_out_vld;
reg [31:0] int4_out;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        int4_out_vld <= 1'b0;
        int4_out     <= 32'd0;
    end else if(!enable_int4 || flag) begin
        int4_out_vld <= 1'b0;
        int4_out     <= 32'd0;
    end else begin
        int4_out_vld <= data_in_vld;
        if(data_in_vld) begin
            int4_out <= int4_sum;
        end
    end
end

// ============================================================================
// Output select
// ============================================================================
always @(*) begin
    data_out_vld = 1'b0;
    data_out     = {DATA_OUT{1'b0}};

    case(mode)
        MODE_FP32: begin // 总延迟为 3+1 = 4 个周期
            data_out_vld = fp32_out_vld;
            data_out     = fp32_out;
        end
        MODE_FP16: begin // 总延迟为 3+1 = 4 个周期
            data_out_vld = fp16_out_vld;
            data_out     = fp16_out;
        end
        MODE_INT8: begin // 总延迟为 1 个周期
            data_out_vld = int8_out_vld;
            data_out     = int8_out;
        end
        MODE_INT4: begin // 总延迟为 1 个周期
            data_out_vld = int4_out_vld;
            data_out     = int4_out;
        end
        default: begin
            data_out_vld = 1'b0;
            data_out     = {DATA_OUT{1'b0}};
        end
    endcase
end

// Pass A data to the next PE belowA.
// out_a 和 out_a_vld 总延迟为 1 个周期
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        out_a     <= {DATA_IN{1'b0}};
        out_a_vld <= 1'b0;
    end else if(!tpu_en || flag) begin
        out_a     <= {DATA_IN{1'b0}};
        out_a_vld <= 1'b0;
    end else begin
        out_a_vld <= data_in_vld;
        if(data_in_vld) begin
            out_a <= data_in_a;
        end
    end
end

endmodule
