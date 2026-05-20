# TPU
<img src="./README.md.pic/TopView.png" width="100%">

├── 1_rtl
│   ├── AHB
│   ├── AXI_TOP
│   ├── Comm_IP
│   ├── CTRL
│   ├── SA_TOP
│   └── TOP
├── 2_tb
│   ├── cfg
│   ├── env
│   ├── if
│   ├── reg_model
│   ├── seq
│   ├── test
│   ├── top
│   └── tpu_top_tb.f
├── 3_bin
│   ├── env_setup.sh
│   └── Makefile
├── 4_syn
│   ├── out
│   ├── tpu_top.sdc
│   └── tpu_top_syn.f
└── 5_spyglass
    ├── cdc.prj
    ├── lint.prj
    └── tpu_top.sgdc

## systolic array `sa.v`
1. 概述: 实例化 16*16 个 PE modules `pe.v` 形成一个脉动阵列 systolic array, 用于执行矩阵乘法
2. I/O interface:
   - `input wire [31:0] i_A [15][15];`
   - `input wire [31:0] i_B [15][15];`
   - `output wire [31:0] i_AB [15][15];`

### multi-precision processing unit `pe.v`
1. 概述: 每个PE模块对输入 `i_a`, `i_b` 支持四种精度运算(fp32, fp16, int8, int4), 针对不同的精度做不同的运算
   - 针对 fp32: 
     - fp32 浮点数乘法 `pe_fp32_multiply.v`, 
     - 累加器 `pe_fp32.v`
   - 针对 fp16: 
     - 取输入数据 `i_a`, `i_b` 低 16 位, 浮定转换 `pe_fp16_int16.v`, 定点数乘法(int32), 定浮转换 `pe_int32_fp32.v`
     - 取输入 partial sum `i_add` (fp32)
     - 累加器 `pe_fp32.v`
   - 针对 int8: 
     - 取输入数据 `i_a`, `i_b` 低 8 位, 定点数乘法(int32), 
     - 累加器(int36), 位宽变换(int32) 
   - 针对 int4: 
     - 取输入数据 `i_a`, `i_b` 低 4 位, 定点数乘法(int32), 
     - 累加器(int36), 位宽变换(int32) 
2. I/O interface:
   - `input wire [31:0] i_a;`
   - `input wire [31:0] i_b;`
   - `output wire [31:0] o_a;`: 将 `i_a` 传给右边和下边的PE module in the systolic array
   - `output wire [31:0] o_b;`: 将 `i_b` 传给右边和下边的PE module in the systolic array
   - `output wire [31:0] o_pe_current_value;`: 目前计算累加得到的值，用于脉动阵列下一次"脉动"后的计算累加


#### fp32乘法 `pe_fp32_multiply.v`
1. 概述: 使用 IEEE 32-bit floating-point binary format 定义的32位浮点数 (`[31]` sign; `[30:23]` 8-bit exponent; `[22:0]` 23-bit fraction; bias = 127) 实现32位浮点数乘法
2. I/O interface: 
   - `input wire clk;` Clock
     `input wire rst_n;` Asynchronous active-low reset
     `input wire vld_in;` Input valid
     `input wire cpt_en;` Compute enable
     `input wire [31:0] a;` = $(-1)^ {s_a} \times 1.{f_a} |_2 \times 2^{(e_a-127)}$
     `input wire [31:0] b;` = $(-1)^ {s_b} \times 1.{f_b} |_2 \times 2^{(e_b-127)}$
   - `output reg vld_out;` Output valid
     `output reg [31:0] out;` = a * b = $(1.{f_a} \times 1.{f_b}) \times 2^{(e_a-127+e_b-127)}$ 
     `output reg out_is_zero;` Indicates if the output is 0
     `output reg out_is_inf;` Indicates if the output is infinite
     `output reg out_is_nan;` Indicates if the output is not a number
     `output reg out_is_of;` Indicates if the output has overflow
     `output reg out_is_uf;` Indicates if the output has underflow
3. 内部逻辑描述:  
   
   <center><img src="./README.md.pic/image.png" width="40%"></center>

   1. 输入处理: 
      - 把 A、B 拆成符号 s、指数 e、尾数 f $\in [1,2)$
      - 处理特殊情况: 
        - e = 0 && f = 0: 0
        - e = 255 && f = 0: inf
        - e = 255 && f != 0: NaN
        - e = 0 && f != 0: denormal/ subnormal
          - 这里一起归入 zero 的处理
      - 符号处理 s_out = s_a XOR s_b
   2. 尾数相乘 `[47:0] f_multi` = 1.f_a * 1.f_b $\in [1,4)$ (`[47:46]` 是整数部分, `[45:0]` 是小数部分), 再移位置 `[47:0] f_output` (`[47:46]` 是整数部分, `[45:0]` 是小数部分) 
   3. 阶码相加 `[8:0] e_add` = e_a - 127 + e_b, 根据尾数是否移位再调整 `[8:0] e_add_shift`
   4. 规格化移位对尾数和阶码的调整：如果尾数乘积结果大于等于2，则需要右移一位，并且阶码加1.
      - if (`f_multi` >=2): `[47:0] f_multi_shift = f_multi >> 1`, `[9:0] e_add_shift = e_add + 1`.
   5. 尾数舍入处理: 因为尾数相乘会产生比 23 位更多的位数，最后只能存 23 位尾数，所以要按规则截断。这里使用: RNE算法
      - `[24:0] f_round`中，`[24:23]` 代表小数点前的部分，`[22:0]` 代表小数点后的部分
   6. 处理一种特殊情况：如果 `f_multi_shift` 的整数部分是 1.1111...1，在舍入处理后 `f_round` 是 10.0000...0，这时需要将尾数再次移位（调整为 01.0000...0），并且阶码再次加1
      - 这步产生尾数 `[22:0] f_out` 
      - 这步产生阶码 `[9:0] e_out`
   7. overflow/underflow 监测
      - 阶码再调整后，if `e_out` >= 255, 产生overflow
      - 阶码再调整后，if `e_out` <= 0, 产生underflow
   8. 通路选择
      ```verilog
      if (is_NaN) {1'b0, 8'hff, 23'h1}
      else if (is_inf) {s_out, 8'hff, 23'h0}
      else if (is_zero) {s_out, 8'h0, 23'h0}
      else if (underflow) {s_out, 8'h0, 23'h0}
      else if (overflow) {s_out, 8'hff, 23'h0}
      else 原乘法计算结果 {s_out, e_out[7:0], f_out}
      ```
4. 补充: 截断规则: 对于某个数 `[22:0] x`, 截断后的数为 `[22:0] y`
   - RZ算法: 直接截断
   - 正无穷舍入:
     - 对正数: 只要 `x[22:0]` 有1, `y = f_output [45:23] + 1;
     - 对负数: 直接截断
   - 正向四舍五入:
     - 正数
        - 如果被丢掉的部分明显>=一半, i.e., `f_multi_shift[22] == 1`: 进 1
        - 如果明显<一半/ f_output[22] == 0: 不变
      - 负数: 直接截断
   - RNE算法:
     - 如果被丢掉的部分>一半/ f_output[22] == 1 && f_output[21:0] != 0: 进 1
     - 如果<一半: 不变
     - 如果=一半 / f_output[22] == 1 && f_output[21:0] == 0: 如果最后保留位是奇数, 进 1; 是偶数, 不变Special

#### 浮定转换 `pe_fp16_int16.v` 
1. 概述: 使用 IEEE 16-bit floating-point binary format 定义的16位浮点数 (`[15]` sign; `[14:10]` 5-bit exponent; `[9:0]` 10-bit fraction; bias = 15) 实现 16 位浮点数到 16 位 int 定点数的转换
2. I/O interface: 
   - `input wire clk;` 
     `input wire rst_n;` 
     `input wire vld_in;`
     `input wire cpt_en;` 
     `input wire [15:0] in;` IEEE FP16 input, $(-1)^s \times 1.f \times 2^{(e-15)}$
   - `output reg vld_out;` Output valid
     `output reg [15:0] out;` Signed two's-complement int16 output
     `output reg out_is_of;` Indicates if the conversion has overflow
     `output reg out_is_uf;` Indicates if the conversion has underflow
3. 内部逻辑描述:  

   <center><img src="./README.md.pic/image-1.png" width="50%"></center>

   1. 输入处理: 
      - 把输入 `[15:0] in` 拆成符号 `s_in = in[15]`、5-bit 指数 `e_in = in[14:10]`、10-bit 尾数 `f_in = in[9:0]`
      - 处理输入的特殊情况：当前实现把 subnormal/inf/NaN 作为特殊输入处理，不进入普通尾数移位路径
        - `in_is_zero`: `e_in == 0 && f_in == 0`
        - `in_is_subnormal`: `e_in == 0 && f_in != 0`
        - `in_is_inf`: `e_in == 31 && f_in == 0`
        - `in_is_nan`: `e_in == 31 && f_in != 0`
   2. 计算真实指数: `real_e_in = e_in - 15`
   3. 尾数移位:
      - 如果 `real_e_in >= 0`，尾数左移, i.e., `[24:0] f_shift = {1'b1, f_in} << abs(real_e_in)`
      - 如果 `real_e_in < 0`，尾数右移, i.e., `[24:0] f_shift = {1'b1, f_in} >> abs(real_e_in)`
      - 对于 zero/subnormal/inf/NaN，`data_mask` 会屏蔽普通移位路径
   4. 位宽变换和舍入:
      - 从移位后的结果中取整数部分 15-bit `f_shift[24:10]`
      - 使用 `f_shift[9]` 作为 round bit 做简单 round-up
      - 得到 magnitude 后，根据 `s_in` 转成 signed two's-complement int16
   5. overflow/underflow 监测:
      - 产生 overflow
        - `in_is_inf` / `in_is_nan` / `real_e_in >= 15` 
        - 正数舍入后超过 `+32767` 时产生 overflow
        - 负数允许刚好输出 `-32768`，超过 `-32768` 时产生 overflow
      - 当前实现只把 subnormal 作为 underflow。小于 1 的普通数按舍入规则转成 0 或 1，不额外报 underflow 
   6. 通路选择:
      ```verilog
      if (in_is_zero)     out = 16'h0000;
      else if (out_is_uf) out = 16'h0000;
      else if (out_is_of) out = s_in ? 16'h8000 : 16'h7fff;
      else                out = s_in ? -mag_round : mag_round;
      ```
   7. 输出时序:
      - `vld_in` 先打一拍得到 `vld_in_1d`
      - `out/out_is_of/out_is_uf/vld_out` 在 `vld_in_1d` 有效时输出

#### 定浮转换 `pe_int32_fp32.v`
1. 概述: 将 32 位 signed two's-complement int 转换成 IEEE 32-bit floating-point binary format (`[31]` sign; `[30:23]` 8-bit exponent; `[22:0]` 23-bit fraction; bias = 127)
2. I/O interface:
   - `input wire clk;`
     `input wire rst_n;`
     `input wire vld_in;`
     `input wire cpt_en;`
     `input wire [31:0] in;` Signed two's-complement int32 input
   - `output reg vld_out;` Output valid
     `output reg [31:0] out;` IEEE FP32 output
     `output reg out_is_zero;` Indicates if the input/output is zero
3. 内部逻辑描述:

   <center><img src="./README.md.pic/image-2.png" width="60%"></center>

   1. 输入处理: 
      - 把输入 `[31:0] in` 拆成符号 `s_in = in[31]` 和 31-bit 数值部分
        - 如果 `s_in == 1`，对输入取 two's-complement 绝对值, i.e., `[31:0] mag_in = ~in + 1'b1`
        - 如果 `s_in == 0`，直接使用输入作为绝对值, i.e., `[31:0] mag_in = in`
      - `in_is_zero = (in == 32'b0)`
   2. 最高有效1检测/ LOD/ Leading one detect: 找到 `mag_in` 最高位的 1 (整数最高有效位)，记为 `[4:0] lod_index` (范围 `[0,31]`).
   3. 生成阶码 `[7:0] exp = 8'd127 + lod_index;`
   4. 尾数移位:
      - 如果 `lod_index <= 23`，说明 int32 的有效位可以完整放入 FP32 的 23-bit fraction，需要左移对齐, i.e.,
        - `[23:0] mag_in_shift = mag_in << (23 - lod_index);`
        - `[22:0] frac = mag_in_shift[22:0];`
      - 如果 `lod_index > 23`，说明低位需要被截断，需要右移对齐, i.e.,
        - `[23:0] mag_in_shift = mag_in >> (lod_index - 23);`
   5. 舍入处理: 当 `lod_index > 23` 时，使用 round bit (被截断部分的最高位) 和 sticky bit (更低被截断位的 OR) 做 RNE 风格舍入.
      - 当 `round_bit == 1` 且 `(sticky_bit == 1 || mag_in_shift[0] == 1)` 时进位, i.e., `[24:0] mag_in_round = {1'b0, mag_in_shift} + 1'b1;`
      - 如果舍入后尾数进位，指数 `exp` 加 1，尾数右移一位
   6. 通路选择:
      ```verilog
      if (in_is_zero) out = 32'h00000000;
      else            out = {s_in, exp, frac};
      ```
   7. 输出时序:
      - `out/out_is_zero/vld_out` 在 `vld_in` 有效后的下一个时钟输出

#### fp32加法 `pe_fp32.v`
1. 概述: 使用 IEEE 32-bit floating-point binary format 定义的32位浮点数 (`[31]` sign; `[30:23]` 8-bit exponent; `[22:0]` 23-bit fraction; bias = 127) 实现 FP32 加法。当前 RTL 文件为 `pe_fp32_adder.v`，模块名为 `FP32_ADDER`
2. I/O interface:
   - `input wire [31:0] src1;` FP32 input operand 1
     `input wire [31:0] src2;` FP32 input operand 2
   - `output reg [31:0] out;` FP32 addition result
3. 内部逻辑描述:
   
   <center><img src="./README.md.pic/image-3.png" width="60%"></center>

   1. 输入处理:
      - 把输入 `src1` 拆成符号 `sign_1 = src1[31]`、指数 `exponent_1 = src1[30:23]`、尾数 `src1[22:0]`
      - 把输入 `src2` 拆成符号 `sign_2 = src2[31]`、指数 `exponent_2 = src2[30:23]`、尾数 `src2[22:0]`
      - 扩展尾数到 `[66:0] fraction_1/fraction_2`，为对阶、加减和舍入保留额外精度
   2. 特殊输入处理:
      - 如果 exponent 为 0，按 zero/subnormal 路径处理，hidden bit 置 0
      - 如果 exponent 不为 0，hidden bit 置 1，按 normal FP32 处理
      - 如果 exponent 为 `8'hff` 且 fraction 为 0，标记为 `inf`
      - 如果 exponent 为 `8'hff` 且 fraction 非 0，标记为 `NaN`
   3. 对阶:
      - 比较 `exponent_1` 和 `exponent_2`
      - 指数较小的一方尾数右移，使两个操作数指数对齐
      - `exponent_Ans` 取较大的指数
   4. 尾数加减:
      - 如果 `sign_1 == sign_2`，两个尾数相加，输出符号为相同符号
      - 如果 `sign_1 != sign_2`，较大的尾数减较小的尾数，输出符号取幅值较大的操作数符号
   5. 规格化:
      - 如果加法产生进位 `fraction_Ans[66] == 1`，尾数右移一位，指数加 1
      - 如果结果尾数最高有效位不在 hidden bit 位置，使用 priority encoder 找到最高位 1，尾数左移并对应调整指数
      - 如果尾数结果为 0，输出 zero
   6. 舍入处理:
      - 使用 `guard_bit`、`round_bit`、`sticky_bit` 判断是否需要舍入
      - 当前 RTL 中预留了 GRS 舍入逻辑，但实际加法语句仍需要进一步确认
   7. 通路选择:
      ```verilog
      if (nan_1 || nan_2 || inf - inf) out = NaN;
      else if (inf_1 || inf_2 || exponent overflow) out = inf;
      else if (fraction_Ans == 0) out = 32'h00000000;
      else out = {sign_Ans, exponent_Ans, fraction_Ans[64:42]};
      ```
   8. 输出时序:
      - 当前 `FP32_ADDER` 是组合逻辑模块，没有 `clk/rst_n/vld_in/vld_out`
      - `out` 随 `src1/src2` 组合变化
