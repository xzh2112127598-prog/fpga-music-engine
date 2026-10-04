//============================================================
// 练习1：参数化计数器
// 对应知识点：2(模块结构) 3(时序逻辑) 4(非阻塞<=) 6(计数器)
// 现象：cnt 在 0..MAX 之间循环；计到 MAX 时 tick 拉高一个时钟周期
//============================================================
module counter #(
    parameter integer MAX = 9          // 计数上限，可在例化时修改
)(
    input  wire       clk,             // 系统时钟
    input  wire       rst_n,           // 复位，低电平有效
    output reg  [3:0] cnt,             // 计数值（4 位：0~15）
    output wire       tick             // 计到 MAX 的单周期脉冲
);
    // 时序逻辑：时钟沿 + 复位沿触发；内部一律用“非阻塞赋值 <=”
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= 4'd0;               // 复位清零
        else if (cnt == MAX[3:0])
            cnt <= 4'd0;               // 数到上限，回 0
        else
            cnt <= cnt + 4'd1;         // 否则 +1
    end

    // 组合逻辑：tick 只跟 cnt 有关，用 assign + 阻塞语义
    assign tick = (cnt == MAX[3:0]);
endmodule
