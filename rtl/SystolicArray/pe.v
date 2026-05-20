module pe
  # (parameter DATA_IN    = 32, // 输入的数据都是32位，具体精度由外部来指示
     parameter DATA_OUT   = 32,
     parameter MODE_WIDTH = 2)
  (
	// Clock and Reset
	input             clk,
	input             rst_n,
	// Cfg Signals 
	input             tpu_en,    //
	input      [31:0] data_in_b, // pre load
	input      [31:0] cpt_mode, // 计算精度模式选择//00:INT4; 01:INT8; 10: FP16; 11:FP32
	//Data In 
	input             flag, // clear flag
	input             data_in_vld,
	input      [31:0] data_in_a,
	input      [31:0] data_in_add,
	//Data Out
	output reg        data_out_vld,
	output reg [31:0] data_out,
    output reg [31:0] out_a,
	output reg   	  out_a_vld
   );
     
	
reg  [31:0]  fp32_out;
reg 		 fp32_out_vld;
wire [31:0]  fp16_out;
wire 		 fp16_out_vld;
wire [31:0]  int8_out;
wire 		 int8_out_vld;
wire [31:0]  int4_out;
wire		 int4_out_vld;

wire [31:0]  fp32_data_in_a;
wire [31:0]  fp16_data_in_a;
wire [31:0]  int8_data_in_a;
wire [31:0]  int4_data_in_a;

wire [31:0]  fp32_data_in_add;
wire [31:0]  fp16_data_in_add;
wire [31:0]  int8_data_in_add;
wire [31:0]  int4_data_in_add;

wire [31:0]  fp32_data_in_vld;
wire [31:0]  fp16_data_in_vld;
wire [31:0]  int8_data_in_vld;
wire [31:0]  int4_data_in_vld;

wire [31:0] fp32_multiply_out;
wire 		fp32_muti_vld;

wire [15:0] fp2fix_data_out_a;
wire 		fp2fix_out_vld;
wire [15:0] fix_b;
wire [31:0] fp16_muti_out;
reg  [33:0] fp16_sum_out;
reg  		fp16_sum_vld;
wire [31:0] fp16_sum_out_clip;

reg  [31:0] int8_sum_out;
reg  	    int8_sum_vld;

reg  [31:0] int4_sum_out;
reg  	    int4_sum_vld;

// 当前状态为start、输入数据有效、复位信号无效且把输入数据指定为某一个精度后，通过外部的配置选择一个模式进行计算
// ========================= input Select ============================= // 
wire enable_FP32;
wire enable_FP16;
wire enable_INT8;
wire enable_INT4;

assign enable_FP32 = tpu_en && (cpt_mode == 2'b11);
assign enable_FP16 = tpu_en && (cpt_mode == 2'b10);
assign enable_INT8 = tpu_en && (cpt_mode == 2'b01);
assign enable_INT4 = tpu_en && (cpt_mode == 2'b00);

assign fp32_data_in_a = (cpt_mode == 2'b11) ? data_in_a : 32'd0;
assign fp16_data_in_a = (cpt_mode == 2'b10) ? data_in_a : 32'd0;
assign int8_data_in_a = (cpt_mode == 2'b01) ? data_in_a : 32'd0;
assign int4_data_in_a = (cpt_mode == 2'b00) ? data_in_a : 32'd0;

assign fp32_data_in_add = (cpt_mode == 2'b11) ? data_in_add : 32'd0;
assign fp16_data_in_add = (cpt_mode == 2'b10) ? data_in_add : 32'd0;
assign int8_data_in_add = (cpt_mode == 2'b01) ? data_in_add : 32'd0;
assign int4_data_in_add = (cpt_mode == 2'b00) ? data_in_add : 32'd0;

assign fp32_data_in_vld = (cpt_mode == 2'b11) ? data_in_vld : 1'b0;
assign fp16_data_in_vld = (cpt_mode == 2'b10) ? data_in_vld : 1'b0;
assign int8_data_in_vld = (cpt_mode == 2'b01) ? data_in_vld : 1'b0;
assign int4_data_in_vld = (cpt_mode == 2'b00) ? data_in_vld : 1'b0;

// ========================= FP32 PATH ============================= // 
pe_fp32_multiply U_FP32_MUTI(
	.clk                 (clk               ),
	.rst_n               (rst_n             ),
	.cpt_en              (tpu_en            ), // tpu_en
	.vld_in              (fp32_data_in_vld  ), // 输入数据有效信号
	.a           (fp32_data_in_a    ), // 输入的第一个32位数据
	.b           (data_in_b         ), // 输入的第二个32位数据
	.out                 (fp32_multiply_out ), // 输出的乘积结果，32位
	.vld_out             (fp32_muti_vld     ), // 输出数据有效信号
	.out_is_zero         (                  ), // 输出结果是否为零
	.out_is_inf          (                  ), // 输出结果是否为正无穷
	.out_is_nan          (                  ), // 输出结果是否为非数
	.out_is_of           (                  ), // 输出结果是否发生溢出
	.out_is_uf           (                  ) // 输出结果是否发生下溢
	);

FP32_ADDER U_FP32_ADDER(
	.src1                (fp32_multiply_out ), // 乘法的输出结果作为加法的第一个输入
	.src2                (fp32_data_in_add  ), // 
	.out                 (fp32adder_out     )  // 加法的输出结果，32位
	);

always @ (posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		fp32_out <= 32'd0;
		fp32_out_vld <= 1'b0;
	end
	else if (enable_FP32==1'b0)begin
		fp32_out <= 32'd0;
		fp32_out_vld <= 1'b0;
	end
	else if (flag==1'b1) begin
		fp32_out <= 32'd0;
		fp32_out_vld <= 1'b0;
	end
	else if (enable_FP32==1'b1 && flag==1'b0 && fp32_muti_vld==1'b1)  begin
		fp32_out     <= fp32adder_out; 
		fp32_out_vld <= fp32_muti_vld; // 迭代过程中输出数据有效
	end
end



// ========================= FP16 PATH ============================= // 
FP2FIX  U_FP2FIX_A (
	.clk                 (clk               ),
	.rst_n               (rst_n             ),
	.en                  (tpu_en       ),
	.vld_in              (fp16_data_in_vld  ),
	.data_in             (fp16_data_in_a[15:0]), // 输入的第一个32位数据，虽然是32位，但只有低16位有效，高位悬空
	.data_out            (fp2fix_data_out_a ), // 输出的结果，16位
	.overflow            (                  ), // 输出结果是否发生溢出
	.underflow           (                  ), // 输出结果是否发生下溢
	.vld_out             (fp2fix_out_vld)  // 输出数据有效信号
);
FP2FIX  U_FP2FIX_B (
	.clk                 (clk               ),
	.rst_n               (rst_n             ),
	.en                  (tpu_en      		 ),
	.vld_in              (1'b1 			 ),
	.data_in             (data_in_b[15:0]   ), // 输入的第一个32位数据，虽然是32位，但只有低16位有效，高位悬空
	.data_out            (fix_b             ), // 输出的结果，16位
	.overflow            (                  ), // 输出结果是否发生溢出
	.underflow           (                  ), // 输出结果是否发生下溢
	.vld_out             (				     )  // 输出数据有效信号
);
										 
assign fp16_muti_out = $singed(fp2fix_data_out_a) * $singed(fix_b);

always @ (posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		fp16_sum_out <= 36'd0;
	end
	else if (enable_FP16==1'b0)begin
		fp16_sum_out <= 36'd0;
	end
	else if (flag==1'b1) begin
		fp16_sum_out <= 36'd0;
	end
	else if (enable_FP16==1'b1 && flag==1'b0 && fp2fix_out_vld)  begin
		fp16_sum_out <= $singed(fp16_muti_out) + $singed(fp16_data_in_add); 
	end
end
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		fp16_sum_vld <= 1'b0;
	end
	else if (enable_FP16==1'b0)begin
		fp16_sum_vld <= 1'b0;
	end
	else begin
		fp16_sum_vld <= fp2fix_out_vld;
	end
end
assign  fp16_sum_out_clip = fp16_sum_out[33:2];

	pe_int32_fp32 U_FIX2FP (
		.clk                 (clk               ),
		.rst_n               (rst_n             ),
		.cpt_en              (tpu_en            ),
		.vld_in              (fp16_sum_vld      ),
		.in                  (fp16_sum_out_clip ), // 
		.vld_out             (fp16_out_vld 	   ), // 输出数据有效信号
		.out                 (fp16_out 		   ), // 输出的结果，32位
		.out_is_zero         (                  )
	);
	
	
	
// ========================= INT8 PATH ============================= // 
assign int8_muti_out = $singed(int8_data_in_a) * $singed(data_in_b);

always @ (posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		int8_sum_out <= 32'd0;
	end
	else if (enable_INT8==1'b0)begin
		int8_sum_out <= 32'd0;
	end
	else if (flag==1'b1) begin
		int8_sum_out <= 32'd0;
	end
	else if (enable_INT8==1'b1 && flag==1'b0 && int8_data_in_vld)  begin
		int8_sum_out <= $singed(int8_muti_out) + $singed(int8_data_in_add); 
	end
end
  
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		int8_sum_vld <= 1'b0;
	end
	else if (enable_INT8==1'b0)begin
		int8_sum_vld <= 1'b0;
	end
	else begin
		int8_sum_vld <= int8_data_in_vld;
	end
end

assign int8_out = int8_sum_out;
assign int8_out_vld = int8_sum_vld;

// ========================= INT4 PATH ============================= // 
assign int4_muti_out = $singed(int4_data_in_a) * $singed(data_in_b);

always @ (posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		int4_sum_out <= 32'd0;
	end
	else if (enable_INT4==1'b0)begin
		int4_sum_out <= 32'd0;
	end
	else if (flag==1'b1) begin
		int4_sum_out <= 32'd0;
	end
	else if (enable_INT4==1'b1 && flag==1'b0 && int4_data_in_vld)  begin
		int4_sum_out <= $singed(int4_muti_out) + $singed(int4_data_in_add); 
	end
end
  
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		int4_sum_vld <= 1'b0;
	end
	else if (enable_INT4==1'b0)begin
		int4_sum_vld <= 1'b0;
	end
	else begin
		int4_sum_vld <= int4_data_in_vld;
	end
end

assign int4_out = int4_sum_out;
assign int4_out_vld = int4_sum_vld;

// ========================= Output Select ========================= //
always@(*)begin
	case(cpt_mode)
		00: data_out_vld = int4_out_vld;
		01: data_out_vld = int8_out_vld;
		10: data_out_vld = fp16_out_vld;
		11: data_out_vld = fp32_out_vld;
		default: data_out_vld = int4_out_vld;
	endcase
end

always@(*)begin
	case(cpt_mode)
		00: data_out = int4_out;
		01: data_out = int8_out;
		10: data_out = fp16_out;
		11: data_out = fp32_out;
		default: data_out = int4_out;
	endcase
end

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		out_a <= 32'd0;
		out_a_vld <= 1'b0;
	end
	else if (tpu_en== 1'b0)begin
		out_a <= 32'd0;
		out_a_vld <= 1'b0;
	end
	else if(data_in_vld==1'b1) begin
		out_a <= data_in_a;
		out_a_vld <= data_in_vld;
	end
end
endmodule
