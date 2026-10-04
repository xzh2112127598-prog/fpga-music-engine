`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// isqrt.v —— 整数平方根（Restoring Square Root，每次迭代处理 2 bit）
//
// 用途：敲击检测里 amag = sqrt(dx^2+dy^2+dz^2)，用于力度映射。
//       方案文档建议"用幅值平方躲开开根号"——阈值比较确实可以用平方比，
//       但【力度 vel 必须是幅值本身】，所以开方躲不掉。
//
// 时序：start 拉高一个周期 -> 16 个周期后 done 拉高一个周期，dout 有效。
// 资源：纯移位+减法，不用 DSP。
////////////////////////////////////////////////////////////////////////////////
module isqrt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] din,
    output reg  [15:0] dout,
    output reg         done
);

    reg [31:0] rad;      // 被开方数，每轮左移 2 bit
    reg [31:0] rem;      // 余数
    reg [15:0] root;     // 根
    reg [4:0]  cnt;      // 0..15，共 16 轮
    reg        busy;

    // 组合逻辑：本轮的移位与试减
    wire [31:0] rem_s  = {rem[29:0], rad[31:30]};
    wire [15:0] root_s = {root[14:0], 1'b0};
    // ⚠️ 这里必须是 1'b1（1 位）而不是 1'b01（2 位）。
    // 写 1'b01 时拼接结果是 18 位，赋给 17 位 wire 会把 root_s 的最高位截掉，
    // 试减量变成 {root_s[14:0],1,0}，开方结果整体错乱（iverilog 会报 extra digits）。
    wire [16:0] test   = {root_s, 1'b1};             // 试减量 = 2*root+1
    wire        hit    = (rem_s >= {15'd0, test});   // 零扩展后比较
    wire [31:0] rem_n  = hit ? (rem_s - {15'd0, test}) : rem_s;
    wire [15:0] root_n = hit ? (root_s + 16'd1) : root_s;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rad  <= 32'd0;
            rem  <= 32'd0;
            root <= 16'd0;
            cnt  <= 5'd0;
            busy <= 1'b0;
            done <= 1'b0;
            dout <= 16'd0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                rad  <= din;
                rem  <= 32'd0;
                root <= 16'd0;
                cnt  <= 5'd0;
                busy <= 1'b1;
            end else if (busy) begin
                rem  <= rem_n;
                root <= root_n;
                rad  <= {rad[29:0], 2'b00};
                if (cnt == 5'd15) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    dout <= root_n;
                end
                cnt <= cnt + 5'd1;
            end
        end
    end

endmodule
