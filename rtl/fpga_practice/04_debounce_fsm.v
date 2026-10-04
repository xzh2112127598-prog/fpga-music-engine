//============================================================
// 练习4：按键消抖状态机（FSM）
// 对应知识点：7(状态机) ＋ 复习 3/4/6
// 约定：key_in 高电平 = 按下（若你的板子按键是低有效，在顶层取反后再接进来）
// 输出：
//   key_out   消抖后的稳定电平
//   key_press 确认按下瞬间的“单周期脉冲”（以后用它触发音符）
//============================================================
module debounce_fsm #(
    parameter integer CLK_FREQ = 24_000_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,
    output reg  key_out,
    output reg  key_press
);
    localparam integer DEB_CNT = CLK_FREQ/100 - 1;   // 稳定 10ms 才确认
    localparam integer W       = $clog2(DEB_CNT + 1);

    localparam [1:0] S_IDLE       = 2'd0,  // 没按
                     S_PRESS_DEB  = 2'd1,  // 正在确认按下
                     S_PRESSED    = 2'd2,  // 已按下
                     S_RELEASE_DEB= 2'd3;  // 正在确认释放

    reg [1:0] state;
    reg [W-1:0] dc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; dc <= 0; key_out <= 1'b0; key_press <= 1'b0;
        end else begin
            key_press <= 1'b0;           // 默认拉低，只在确认瞬间高一拍
            case (state)
                S_IDLE: begin
                    key_out <= 1'b0;
                    if (key_in) begin
                        state <= S_PRESS_DEB; dc <= 0;
                    end
                end

                S_PRESS_DEB: begin
                    if (!key_in) begin
                        state <= S_IDLE; dc <= 0;        // 抖动，重新等
                    end else if (dc == DEB_CNT) begin
                        state <= S_PRESSED;
                        key_out   <= 1'b1;
                        key_press <= 1'b1;               // 单周期脉冲
                    end else begin
                        dc <= dc + 1'b1;
                    end
                end

                S_PRESSED: begin
                    key_out <= 1'b1;
                    if (!key_in) begin
                        state <= S_RELEASE_DEB; dc <= 0;
                    end
                end

                S_RELEASE_DEB: begin
                    if (key_in) begin
                        state <= S_PRESSED; dc <= 0;     // 抖动，仍算按住
                    end else if (dc == DEB_CNT) begin
                        state <= S_IDLE; key_out <= 1'b0;
                    end else begin
                        dc <= dc + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
