module ahb_slave(
    // AHB-Lite 总线接口
    // global signals
    input       hclk,  // 总线时钟
    input       hrstn, // 总线复位信号, 低电平有效
    input       hsel,
    // 主设备发出/ 从设备接收的 address + control signals 
    input [31:0] haddr, 
    input        hwrite, // 1: 写操作，0: 读操作
    input [2:0]  hsize,  // 每次传输的读/写数据的大小
    input [2:0]  hburst, // 表示接下来传输是不是连续访问，以及连续访问的模式是什么
                         // 假设为 SINGLE，表示单次访问
    input [3:0]  hprot,  // 表示一次总线访问的保护控制信息
    input [1:0]  htrans, // 表示当前传输的类型：IDLE, BUSY, NONSEQ, SEQ
                         // 假设为 NONSEQ，表示当前传输是一个新的非连续访问
    // 主设备发出/ 从设备接收的 data
    input [31:0] hwdata,
    // 从设备发出/ MUX 接收的 data
    output [31:0] hrdata, 
	// transfer response
    input  hready_in,  
    output hready_out, // 从设备发出，目的地是 Multiplexer, 表示当前 slave 是否完成了本次传输。
    output hresp,      // 从设备发出，目的地是 Multiplexer, 表示当前传输的响应状态：OKAY, ERROR
                       // 假设为 OKAY
     
    // AHB slave 到寄存器列表接口 
    input  [31:0] ahb_rd_data,  // 寄存器读取回的数据
	output [7:0]  ahb_addr,     // 经过锁存的寄存器偏移地址
    output [31:0] ahb_wr_data,  // 写入寄存器的数据
    output        ahb_wr_en,    // 内部寄存器写使能信号
    output        ahb_rd_en     // 内部寄存器读使能信号
);

// AHB 协议参数定义
// HTRANS[1:0]
parameter IDLE    = 2'b00;
parameter BUSY    = 2'b01;
parameter NONSEQ  = 2'b10;
parameter SEQ     = 2'b11;
// HRESP
parameter OKAY    = 1'b0;
parameter ERROR   = 1'b1;

////////////////////////////////////////////////////////////////////////////
// 1. 地址周期：
// 写：
// 主机拉高 HWRITE，并在 HADDR 上驱动要写的地址
// 
// 读：
// 主机拉低 HWRITE，并在 HADDR 上驱动要读的地址
/////////////////////////////////////////////////////////////////////////////

// 有 hsel=1，并且 htrans=NONSEQ，才认为 CPU 正在发起一次有效访问
wire transmission_valid;
assign transmission_valid = hsel & (htrans == NONSEQ);

// 在地址周期，锁存主机的请求信息，包括读写选择、地址和有效信号，以供后续数据周期使用
reg [7:0] haddr_1d; 
reg       hwrite_1d;
reg       transmission_valid_1d;
always @(posedge hclk or negedge hrstn) begin
    if(!hrstn) begin
        haddr_1d <= 8'd0;
        hwrite_1d <= 1'b0;
        transmission_valid_1d <= 1'b0;
    end else if (hready_in) begin // 如果总线 ready
        if (transmission_valid) begin // 如果当前有有效 AHB 访问
            haddr_1d <= haddr[7:0]; // 仅提取低 8 位
            hwrite_1d <= hwrite;
            transmission_valid_1d <= 1'b1;
        end else begin // 如果当前没有有效 AHB 访问，则清除锁存的请求信息
            transmission_valid_1d <= 1'b0; 
        end
    end
end

///////////////////////////////////////////////////////////////////////////////
// 2. 数据周期：
// 写：
// 本模块在 HCLK 上升沿捕获写地址，同时主机在 HWDATA 上驱动要写的数据 
// 
// 读：
// 本模块根据地址从 Register_map 获取数据，并驱动到 HRDATA 总线上
///////////////////////////////////////////////////////////////////////////////

// 写地址用锁存到 haddr_1d 中的
assign ahb_addr    = haddr_1d;
// 写数据直接使用主机在 HWDATA 上驱动的数据
assign ahb_wr_data = hwdata; 

// 读数据直接从 Register_Map 获取，并驱动到 HRDATA 上
assign hrdata = ahb_rd_data;

// 输出给 Register_Map 的使能信号
assign ahb_wr_en = transmission_valid_1d & hwrite_1d;
assign ahb_rd_en = transmission_valid_1d & !hwrite_1d;  

///////////////////////////////
// 3. AHB 响应输出
///////////////////////////////
assign hready_out = hready_in;
assign hresp      = OKAY; // 始终返回 OKAY 响应

endmodule
