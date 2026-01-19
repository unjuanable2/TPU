# TPU
<img src="./README.md.pic/总架构图.JPG" width="100%">


## systolic array: SA.v
1. 概述: 实例化 16*16 个 PE modules `PE.v` 形成一个脉动阵列 systolic array, 用于执行矩阵乘法
2. I/O interface:
   - `input wire [31:0] i_A [15][15];`
   - `input wire [31:0] i_B [15][15];`
   - `output wire [31:0] i_AB [15][15];`

## processing unit: PE.v
1. 概述: 每个PE模块对输入 `i_a`, `i_b` 支持四种精度运算(fp32, fp16, int8, int4), 针对不同的精度做不同的运算
   - 针对fp32: fp32 浮点数乘法 `PE_fp32_multiply.v` (including 位宽变换)
   - 针对fp16: 对输入取低16位, fp32 浮点数乘法 `PE_fp32_multiply.v` (including 位宽变换)
   - 针对int8: 浮定转换, 定点数乘法, 位宽变换, 定浮转换
   - 针对int4: 浮定转换, 定点数乘法, 位宽变换
2. I/O interface:
   - `input wire [31:0] i_a;`
   - `input wire [31:0] i_b;`
   - `output wire [31:0] o_a;`: 将 `i_a` 传给右边和下边的PE module in the systolic array
   - `output wire [31:0] o_b;`: 将 `i_b` 传给右边和下边的PE module in the systolic array
   - `output wire [31:0] o_PE_current_value;`: 目前计算累加得到的值，用于脉动阵列下一次"脉动"后的计算累加


### fp32 浮点数乘法: PE_fp32_multiply.v
1. 概述: 使用 IEEE 32-bit floating-point binary format 定义的32位浮点数 ([31]: sign; [30:23]: exponent; [22:0]: fraction; bias = 127) 实现32位浮点数乘法
2. I/O interface: 
   - `input wire [31:0] i_fp32_a;` = $(-1)^ {s_a} \times 1.{f_a} |_2 \times 2^{(e_a-127)}$
   - `input wire [31:0] i_fp32_b;` = $(-1)^ {s_b} \times 1.{f_b} |_2 \times 2^{(e_b-127)}$
   - `output wire [31:0] o_fp32_output;` = i_fp32_a * i_fp32_b = $(1.{f_a} \times 1.{f_b}) \times 2^{(e_a-127+e_b-127)}$ 
   - `output wire o_fp32_output_is_zero;` Indicates if the output is 0
   - `output wire o_fp32_output_is_inf;` Indicates if the output is infinite
   - `output wire o_fp32_output_is_NaN;` Indicates if the output is not a number
   - `output wire o_fp32_output_overflow;` Indicates if the output has overflow
   - `output wire o_fp32_output_underflow;` Indicates if the output has underflow
3. 内部逻辑描述: 
   
   <center><img src="./README.md.pic/image.png" width="40%"></center>

   1. 输入处理: 
      - 把 A、B 拆成符号 s、指数 e、尾数 f $\in [1,2)$; 并处理特殊情况: 
        - 如果 e = 0 并且 f = 0，则认为输入数是 0
        - 如果 e = 255 并且 f = 0，则认为输入数是 inf
        - 如果 e = 255 并且 f != 0，则认为输入数是 NaN
        - 如果 e = 0 并且 f != 0，则认为输入数是 denormal/ subnormal
      - 决定输出的符号位 = 输入 a 的符号位和输入 b 的符号位的XOR的结果
   2. 尾数相乘 `[47:0] f_multi` = 1.f_a * 1.f_b $\in [1,4)$ 
      - 注：`f_multi[47:46]`代表整数部分, `f_multi[45:0]`代表小数部分
   3. 阶码相加 `signed [9:0] e_add` = e_a - 127 + e_b
   4. 规格化移位对尾数和阶码的调整：如果尾数乘积结果大于等于2，则需要右移一位，并且阶码加1。调整后得到 `[47:0] f_multi_shift`, `signed [9:0] e_add_shift`
   5. 尾数舍入处理: 因为尾数相乘会产生比 23 位更多的位数，最后只能存 23 位 `[24:0] f_round`，所以要按规则截断多余的23位。这里使用: RNE算法。
      - 注：`f_round[24:23]`代表整数部分, `f_multi[22:0]`代表应该要存的23位小数部分
   6. 处理一种特殊情况：如果 `f_multi_shift` 的整数部分是 1.1111...1，在舍入处理后 `f_round` 会变成 10.0000...0，这时需要将尾数再次移位（调整为 01.0000...0），并且阶码再次加1。调整后得到 `[22:0] f_out`, `signed [9:0] e_out`
   7. overflow/underflow 监测
      - 如果 `e_out` >= 255, 则表明产生overflow
      - 如果 `e_out` <= 0, 则表明产生underflow
   8. 通路选择并且包装输出 `[31:0] out`
      ```verilog
      if (is_NaN) {1'b0, 8'hff, 23'h1}
      else if (is_inf) {s_output, 8'hff, 23'h0}
      else if (is_zero) {s_output, 8'h0, 23'h0}
      else if (underflow) {s_output, 8'h0, 23'h0}
      else if (overflow) {s_output, 8'hff, 23'h0}
      else 原乘法计算结果
      ```
4. 补充: 截断规则。假设 `[47:0] f_multi_shift` 是截断前的数，`[24:0] f_round`是截断后的数
   - RZ算法: 直接截断
   - 正无穷舍入:
     - 对正数: 只要 `f_multi_shift [22:0]` 有1, `f_round = f_multi_shift [47:23] + 1`;
     - 对负数: 直接截断
   - 正向四舍五入: 假设 R 位是 `f_multi_shift[22]`, S 位是 `|(f_multi_shift[21:0])`
     - 正数
        - 如果被丢掉的部分明显>=一半，也就是说 R位是1: 进 1
        - 如果明显<一半，也就是说 R位是0: 不变
      - 负数: 直接截断
   - RNE算法: 假设 R 位是 `f_multi_shift[22]`, S 位是 `|(f_multi_shift[21:0])`
     - 如果被丢掉的部分>一半，也就是说 R位是1并且S位是1: 进 1
     - 如果<一半，也就是说 R位是0: 不变
     - 如果=一半，也就是说 R位是1并且S位是0: 如果最后保留位`f_multi_shift[23]`是奇数, 进1; 是偶数, 不变Special
