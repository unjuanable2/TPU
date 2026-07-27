// 参数化权重固定型脉动阵列。
//
// 本模块采用的数据流：
//   1. B 权重固定不动：
//      PE(row=r, col=c) 固定使用 data_in_b[r][c] 作为本地权重。
//      对于矩阵乘法 C = A * B，row r 表示 K 维度下标 r，
//      col c 表示输出矩阵 C 的列下标 c，因此 PE(r,c) 存 B[r][c]。
//
//   2. A 从左往右流动：
//      data_in_a 每一拍打包一组 A 数据，每个 PE row 输入一个 A 值。
//      进入 row r 的 A 值会通过 out_a/out_a_vld 沿该行向右传递。
//
//   3. 部分和从上往下流动：
//      第 0 行从 0 开始累加；下面每一行接收正上方 PE 传下来的部分和，
//      加上本 PE 的 A * B 乘积后继续向下传。
//
//   4. 最底行产生输出：
//      data_out[c] 是 PE(row=ROW-1, col=c) 输出的最终部分和。

module sa #(
    parameter ROW    = 4,  // PE 行数；在权重固定型数据流中对应 K 维度
    parameter COL    = 4,  // PE 列数；对应输出矩阵 C 的列数 N
    parameter DW     = 32, // 输入数据和权重数据位宽
    parameter DW_OUT = 32  // 部分和与输出数据位宽
)(
    input wire clk, // 系统时钟（“动作”）
    input wire rst_n, // 异步复位，低电平有效

    // CPU 控制接口，同步脉冲信号（“动作”）
    input wire cpu_sw_rst_sync, // CPU software reset synchronized
        // CPU 通过软件写寄存器发出的复位信号，并且已经同步到 sa.v 使用的 clk 里
        // 表示 CPU 要求清除所有 PE 内部状态，准备开始新一轮计算。
    input wire cpu_sw_tpu_start_sync, // CPU TPU start synchronized
        // CPU 通过软件写寄存器发出的 TPU 启动信号，并且已经同步到 sa.v 使用的 clk 里
        // 表示 CPU 已经准备好输入数据、权重、模式等配置，然后通知 TPU：可以开始这一轮计算了

    // 控制信号（“状态”）
    input wire       tpu_en, // TPU 当前是否允许工作
    input wire [1:0] cpt_mode, // 计算模式：00=INT4, 01=INT8, 10=FP16, 11=FP32

    // 输入数据
    input wire                   data_in_vld, // data_in_a 有效信号
    input wire [ROW*DW-1:0]      data_in_a,
    // 在当前拍给每个 PE row 提供一个 A 元素：
    //   data_in_a[ (r+1)*DW-1 -: DW ] = 进入 row r 的 A 值。
    input wire [ROW*COL*DW-1:0]  data_in_b,
    // 在权重固定型数据流下，data_in_b 包含所有 PE 固定保存的权重：
    //   data_in_b[ ((r*COL+c)+1)*DW-1 -: DW ] = PE(r,c) 保存的 B 权重。
    
    // 最底行输出，每一列输出一个值
    output wire                  data_out_vld, // data_out 有效信号
    output wire [COL*DW_OUT-1:0] data_out
);

// 计算周期 = 阵列填充/排空周期 + PE 内部流水延迟。
localparam integer BASE_CYCLES = ROW + COL - 1;
localparam integer MAX_PE_LATENCY = 4; // max{INT4/8=1, FP32=4, FP16=4}
localparam integer MATMUL_CYCLES_MAX = BASE_CYCLES + MAX_PE_LATENCY;
                // MATMUL: matrix multiplication
// 用来计数的寄存器位宽，足够表示最大计算周期数。
localparam integer COUNTER_WIDTH = (MATMUL_CYCLES_MAX <= 1) ? 1 : $clog2(MATMUL_CYCLES_MAX);

/////////////////////////////////////////////////
// 中间信号声明
//////////////////////////////////////////////////
wire [2:0] pe_latency_by_mode; // 当前计算模式下 PE 内部的流水延迟
wire [COUNTER_WIDTH-1:0] matmul_cycles; // 当前计算模式下整个矩阵乘法的总周期数

// 根据 counter 和 matmul_cycles 生成 flag_clear 信号，to 通知 PE 清除内部状态。
reg [COUNTER_WIDTH-1:0] counter; 
reg flag_clear;

wire [ROW*COL*DW-1:0] pe_a_bus;
// pe_a_bus[PE_IDX] 保存 PE(r,c) 向右传给 PE(r,c+1) 的 A 数据
// PE 的一维编号 PE_IDX = r * COL + c
wire [ROW*COL-1:0] pe_a_vld_bus;
// 有效信号与对应数据沿相同方向传递
wire [ROW*COL*DW_OUT-1:0] pe_psum_bus;
// pe_psum_bus[PE_IDX] 保存 PE(r,c) 向下传给 PE(r+1,c) 的部分和
wire [ROW*COL-1:0] pe_psum_vld_bus;
// 有效信号与对应数据沿相同方向传递

wire [COL-1:0] bottom_vld;
// bottom_vld[c] = PE(row=ROW-1, col=c) 输出的部分和是否有效

//////////////////////////////////////////////////////////////////////////
// 逻辑实现
//////////////////////////////////////////////////////////////////////////

// 根据计算模式计算出 PE 内部流水延迟
assign pe_latency_by_mode = (cpt_mode == 2'b11) ? 3'd4 :
                            (cpt_mode == 2'b10) ? 3'd4 : 3'd1;
// 和整个矩阵乘法的总周期数
assign matmul_cycles = BASE_CYCLES + pe_latency_by_mode;

// 计数器逻辑：
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter    <= {COUNTER_WIDTH{1'b0}};
        flag_clear <= 1'b0;
    end else if (cpu_sw_rst_sync) begin 
        // 软件复位：下一拍清除所有 PE 内部状态。
        counter    <= {COUNTER_WIDTH{1'b0}};
        flag_clear <= 1'b1;
    end else if (tpu_en && cpu_sw_tpu_start_sync) begin 
        // 开始新一轮计算：清除上一轮遗留的部分和。
        counter    <= {COUNTER_WIDTH{1'b0}};
        flag_clear <= 1'b1;
    end else if (tpu_en && data_in_vld) begin
        // 数据流有效期间计数，直到整个波前穿过阵列并经过 PE 内部流水。
        if (counter == (matmul_cycles - 1'b1)) begin
            counter    <= {COUNTER_WIDTH{1'b0}};
            flag_clear <= 1'b1;
        end else begin
            counter    <= counter + 1'b1;
            flag_clear <= 1'b0;
        end
    end else begin
        counter    <= {COUNTER_WIDTH{1'b0}};
        flag_clear <= 1'b0;
    end
end

// 生成 ROW x COL 个 PE 实例，诶个完成计算
genvar r, c;
// genvar 表示 r 和 c 是 generate 循环的变量，不能在 always 块里使用。
// 在编译完成preprocessor后, 就不存在during simulation of design
generate
// Generate instantiations resolved during "elaboration" 
// (在compile阶段/ before simulation or sythesis/ When module instantiations are linked to module definitions), 
// 所以not dynamically created hardware.

    for (r = 0; r < ROW; r = r + 1) begin : GEN_ROW // Typically name the generate block as reference
        for (c = 0; c < COL; c = c + 1) begin : GEN_COL
            // PE(r,c) 的一维编号
            localparam integer PE_IDX = r * COL + c; 

            // A 输入选择： 
            wire [DW-1:0] pe_input_in;
            wire          pe_input_vld_in;
            // - 第 0 列从 SA 左边界接收 A
            // - 其它列从左边相邻 PE 接收 A
            assign pe_input_in = (c == 0) ? data_in_a[(r+1)*DW-1 -: DW] :
                                            pe_a_bus[(r*COL+c)*DW-1 -: DW];
            assign pe_input_vld_in = (c == 0) ? data_in_vld : pe_a_vld_bus[r*COL + c-1];

            // 部分和输入选择：
            wire [DW_OUT-1:0] pe_psum_in;
            wire              pe_psum_vld_in;
            // - 第 0 行从 0 开始累加。
            // - 其它行从正上方相邻 PE 接收部分和。
            assign pe_psum_in = (r == 0) ? {DW_OUT{1'b0}} :
                                           pe_psum_bus[((r-1)*COL+c+1)*DW_OUT-1 -: DW_OUT];
            assign pe_psum_vld_in = (r == 0) ? 1'b1 : pe_psum_vld_bus[(r-1)*COL+c];

            // PE(r,c) 固定保存的权重。
            wire [DW-1:0] pe_weight_in;
            assign pe_weight_in = data_in_b[(PE_IDX+1)*DW-1 -: DW];

            // 只有横向 A 数据和纵向部分和同时有效时，PE 才进行计算。
            wire pe_data_vld_in;
            assign pe_data_vld_in = pe_input_vld_in & pe_psum_vld_in;

            // PE 的功能：pe_psum_out = pe_psum_in + pe_input_in * pe_weight_in
            wire [DW-1:0]     pe_input_out; // = pe_input_in；向右传
            wire [DW_OUT-1:0] pe_psum_out; // 向下传
            wire              pe_input_vld_out;
            wire              pe_psum_vld_out;
            pe #(.DATA_IN(DW), .DATA_OUT(DW_OUT), .MODE_WIDTH(2)) u_pe (
                // Clock and Reset
                .clk  (clk), .rst_n (rst_n),
                // Cfg Signals
                .tpu_en (tpu_en),
                .data_in_b (pe_weight_in),
                .cpt_mode ({30'd0, cpt_mode}),
                // Data In
                .flag (flag_clear), // 每个 PE 都收到同一个 flag_clear
                                    // 在 pe.v 里，只要 flag 为 1，PE 就会清空内部寄存器
                .data_in_vld (pe_data_vld_in),
                .data_in_a (pe_input_in),
                .data_in_add (pe_psum_in),
                // Data Out
                .data_out_vld (pe_psum_vld_out),
                .data_out (pe_psum_out),
                .out_a (pe_input_out),
                .out_a_vld (pe_input_vld_out)
            );

            // 将 PE 的输出连接到下一列 PE 的输入 A 和下一行 PE 的输入 psum
            assign pe_a_bus[(PE_IDX+1)*DW-1 -: DW] = pe_input_out;
            assign pe_psum_bus[(PE_IDX+1)*DW_OUT-1 -: DW_OUT] = pe_psum_out;
            assign pe_a_vld_bus[PE_IDX] = pe_input_vld_out;
            assign pe_psum_vld_bus[PE_IDX] = pe_psum_vld_out;
        end
    end
endgenerate

// 最底行 PE 的输出就是整个阵列的输出
generate
    for (c = 0; c < COL; c = c + 1) begin : GEN_OUT
        // 每一列的最终输出来自最底行 PE 输出的部分和。
        assign data_out[(c+1)*DW_OUT-1 -: DW_OUT] = pe_psum_bus[((ROW-1)*COL+c+1)*DW_OUT-1 -: DW_OUT];
        assign bottom_vld[c] = pe_psum_vld_bus[(ROW-1)*COL+c];
    end
endgenerate
// 所有最底行 PE 都输出有效时，整个 data_out 向量有效。
assign data_out_vld = tpu_en & (&bottom_vld);

endmodule
