/* 对于数据格式的说明：
signed  exp       fraction
31      30...23   22...0

特殊情况：
exponent  fraction   value
-------------------------------------------------------------
0         zero       0                           "zero"
0         non-zero   +-2^(-126)*0.(fraction)     "subnormal"
1~254     any        +-2^(exp-127)*1.(fraction)  "normal"
255       zero       +-inf                       "infinity"
255       non-zero   NaN                         "NaN"
*/

module pe_fp32_adder (
    input             clk,
    input             rst_n,
    input      [31:0]  a,
    input      [31:0]  b,
    output reg [31:0]  out
);

///////////////////////////////////////
// 中间变量定义
//////////////////////////////////////
// 1. 输入处理
// (1) 拆分符号位、指数位和尾数位
wire s_a, s_b;
wire [7:0] e_a, e_b;
wire [22:0] f_a, f_b;

// (2) 尾数处理
reg [66:0]  extended_f_a;
reg [66:0]  extended_f_b;

// (3) 特殊情况处理
reg a_is_inf, a_is_nan;
reg b_is_inf, b_is_nan;

// 2. 对阶
reg [66:0] aligned_f_a;
reg [66:0] aligned_f_b;
reg [8:0] e_a_align;
reg [8:0] e_b_align;
reg [8:0] e_out;

// 3. 尾数加减
reg [66:0] f_out;
reg s_out;

// 4. 规格化
reg [66:0] f_out_normalized;
reg [8:0] e_out_normalized;
integer i;
reg [6:0] shift_amount;
reg found_one;
// shift_amount 用于记录需要左移的位数，范围是1~65

// 5. 舍入 (RNE算法)
reg G_bit, S_bit;
reg [66:0] f_out_temp;
reg [66:0] f_out_round;
reg [8:0] e_out_round;

// 6. 输出选择
reg [31:0] out_comb;
    
///////////////////////////////////////
// 组合逻辑实现
//////////////////////////////////////
// 1. 输入处理
// (1) 拆分符号位、指数位和尾数位
assign s_a     = a[31];
assign s_b     = b[31];
assign e_a = a[30:23];
assign e_b = b[30:23];
assign f_a     = a[22:0];
assign f_b     = b[22:0];

always @(*) begin
    // (2) 尾数处理
    extended_f_a = {2'd0, f_a, 42'd0};
    extended_f_b = {2'd0, f_b, 42'd0};
    // [66] 用于保存加法进位
    // [65] 用于保存 hidden bit
    // [64:42] 对应 FP32 23-bit fraction
    // [41:0] 用于保留对阶和舍入过程中的额外精度

    // (3) 特殊情况处理
    a_is_inf = 1'b0;
    a_is_nan = 1'b0;
    b_is_inf = 1'b0;
    b_is_nan = 1'b0;
    e_a_align = (e_a == 8'h00) ? 9'd1 : {1'b0, e_a};
    e_b_align = (e_b == 8'h00) ? 9'd1 : {1'b0, e_b};
    // FP32 有个特殊规定：当 e = 0 时，真实指数不是 0 - 127 = -127，
    // 而是也按 -126 算
    // 也就是说：e = 0  -> 真实指数 -126；e = 1  -> 真实指数 -126
    // 所以在“对阶”时，e=0 要临时当成 e=1 来比较

    if (e_a == 8'h00) begin // zero/subnormal
        extended_f_a[65] = 1'b0;
    end else begin // normal
        extended_f_a[65] = 1'b1;
        
        // exception
        if (e_a == 8'hff) begin
            if (f_a == 23'h0) begin
                a_is_inf = 1'b1;
            end else begin
                a_is_nan = 1'b1;
            end
        end
    end

    if (e_b == 8'h00) begin // zero/subnormal
        extended_f_b[65] = 1'b0;
    end else begin // normal
        extended_f_b[65] = 1'b1;
        
        // exception
        if (e_b == 8'hff) begin
            if (f_b == 23'h0) begin
                b_is_inf = 1'b1;
            end else begin
                b_is_nan = 1'b1;
            end
        end
    end
end

// 2. 对阶
always @(*) begin
    aligned_f_a = extended_f_a;
    aligned_f_b = extended_f_b;
    e_out = e_a_align;

    if(e_a_align > e_b_align) begin
        aligned_f_b = extended_f_b >> (e_a_align - e_b_align);
        e_out = e_a_align;
    end else if(e_a_align < e_b_align) begin
        aligned_f_a = extended_f_a >> (e_b_align - e_a_align);
        e_out = e_b_align;
    end
end

// 3. 尾数加减
always @(*) begin
    if(s_a == s_b) begin
        f_out = aligned_f_a + aligned_f_b;
        s_out = s_a;
    end else if(aligned_f_a >= aligned_f_b) begin
        f_out = aligned_f_a - aligned_f_b;
        s_out = s_a;
    end else begin
        f_out = aligned_f_b - aligned_f_a;
        s_out = s_b;
    end
end

always @(*) begin
    // 4. 规格化
    f_out_normalized = f_out;
    e_out_normalized = e_out;
    shift_amount = 7'd0;
    found_one = 1'b0;
    G_bit = 1'b0;
    S_bit = 1'b0;
    f_out_temp = f_out;
    f_out_round = f_out;
    e_out_round = e_out;

    if(f_out[66]) begin
        // (1) 如果最高位为1，说明有进位，需要右移一位，并且指数加1
        f_out_normalized = f_out >> 1;
        e_out_normalized = e_out + 1'b1;
    end else if(f_out == 67'b0) begin
        // (2) 如果尾数为0，说明结果为0，指数也应该为0
        f_out_normalized = 67'b0;
        e_out_normalized = 9'b0;
    end else if(f_out[65] == 1'b0) begin
        // (3) 如果最高位为0 且结果非零，说明需要左移，直到最高位为1
        for (i = 64; i >= 0; i = i - 1) begin
            if((found_one == 1'b0) && (f_out[i] == 1'b1)) begin
                // 根据最高有效 1 的位置左移尾数，同时调整 e_out
                shift_amount = 65 - i; // 找到第一个1的位置
                f_out_normalized = f_out << shift_amount;
                if(e_out > shift_amount) begin
                    e_out_normalized = e_out - shift_amount;
                end else begin
                    e_out_normalized = 9'd0;
                end
                found_one = 1'b1;
            end
        end
    end

    // 5. 舍入 (RNE算法)
    // f_out_normalized [41:0] 是要舍入的部分
    G_bit  = f_out_normalized[41];
    S_bit = |f_out_normalized[40:0];
    if (G_bit && (S_bit || f_out_normalized[42])) begin
        f_out_temp = f_out_normalized + (67'd1 << 42);

        // 舍入后再处理：检查是否有进位
        if (f_out_temp[66]) begin
            f_out_round = f_out_temp >> 1;
            e_out_round = e_out_normalized + 1'b1;
        end else begin
            f_out_round = f_out_temp;
            e_out_round = e_out_normalized;
        end
    end else begin // 不需要舍入
        f_out_round = f_out_normalized;
        e_out_round = e_out_normalized;
    end
end

// 6. 输出选择
always @(*) begin
    if(a_is_nan || b_is_nan || (a_is_inf && b_is_inf && (s_a ^ s_b))) begin
        out_comb = {1'b0, 8'hff, 23'h1};
    end else if(a_is_inf || b_is_inf) begin
        out_comb = {a_is_inf ? s_a : s_b, 8'hff, 23'h0};
    end else if(e_out_round >= 9'd255) begin
        out_comb = {s_out, 8'hff, 23'h0};
    end else if((f_out_round == 67'b0) || (e_out_round == 9'd0)) begin
        out_comb = 32'h00000000;
    end else begin
        out_comb = {s_out, e_out_round[7:0], f_out_round[64:42]};
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        out <= 32'd0;
    end else begin
        out <= out_comb;
    end
end

endmodule
