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
   - 针对fp32: fp32 浮点数乘法 `PE_fp32_multiply.v`, 位宽变换
   - 针对fp16: 对输入取低16位, fp32 浮点数乘法 `PE_fp32_multiply.v`, 位宽变换
   - 针对int8: 浮定转换, 定点数乘法, 位宽变换, 定浮转换
   - 针对int4: 定点数乘法, 位宽变换
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
   - `output wire o_fp32_output_is_nan;` Indicates if the output is not a number/ invalid
   - `output wire o_fp32_output_overflow;` Indicates if the output has overflow
   - `output wire o_fp32_output_underflow;` Indicates if the output doesn't have overflow
3. 内部逻辑描述: 
   <img src="./README.md.pic/image.png" width="40%">
   1. 输入处理: 
      - 把 A、B 拆成符号 s、指数 e、尾数 f $\in [1,2)$; 并处理特殊情况: 
        - e = 0 && f = 0: 0
        - e = 255 && f = 0: inf
        - e = 255 && f != 0: nan
        - e = 0 && f = 0: denormal/ subnormal
      - 符号处理 = sa XOR sb
   2. 尾数相乘 [-1:-46] f_c_initial = 1.fa * 1.fb $\in [1,4)$, 再移位置[-1:-46] f_c
      - if (1 <= f_c_initial <2) f_c = f_c_initial
      - if (f_c_initial >=2) f_c = f_c_initial >> 1
   3. 阶码相加 e_c_initial = e_a - 127 + e_b, 根据尾数是否移位再调整
      - if (1 <= f_c_initial <2) e_c = e_c_initial 
      - if (1 <= f_c_initial <2) e_c = e_c_initial + 1
   4. 尾数舍入处理: 因为尾数相乘会产生比 23 位更多的位数，最后只能存 23 位，所以要按规则截断。这里使用: 就近舍入 + ties to even（最近，遇到正中间选偶数）
      - 如果被丢掉的部分明显大于一半: 进 1
      - 如果明显小于一半: 不变
      - 如果刚好一半: 如果最后保留位是奇数，进位，让它变偶; 如果最后保留位是偶数, 不进位
   5. if f_c 全是 1 (1.1111 舍入进位 → 10.0000), 尾数 & 阶码 需要再调整:
      - 尾数 f_c = f_c_initial >> 1 
      - 阶码 e_c = e_c_initial + 1