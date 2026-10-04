`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// hit_detector.v —— 鼓槌敲击检测（MATLAB main_drum_engine Part 3 的 RTL 直译）
//
// 算法（与 lib/ 黄金模型逐拍对齐）：
//   1) 慢速平均求重力基线：  base += (cur - base) >> 5
//      同一个滤波器办两件事 —— 减掉它就是"动作分量"，保留它就是"朝向"
//   2) 动作分量幅值平方与阈值平方比较（躲开开根号）
//      ⚠️ 千万别对加速度做两次积分求位置 —— 漂移会爆炸
//   3) 状态机 IDLE -> TRACK(峰值窗) -> FIRE -> REFRACTORY(不应期)
//      不应期必须有：鼓槌弹跳会造成一敲触发三四次，听着像机关枪
//   4) 峰值窗内累加 ay 求均值判方位（左/中/右 -> 军鼓/底鼓/镲）
//   5) 力度 = 峰值幅值 / (10g) * 127，幅值要真开方（阈值可以比平方，
//      力度必须是幅值本身，所以 isqrt 躲不掉）
//
// 延迟：峰值窗 WIN_MS 是主要来源。WIN_MS=5 时端到端约 6ms（红线 10ms）。
////////////////////////////////////////////////////////////////////////////////
module hit_detector #(
    parameter LSBG     = 2048,      // 1g 对应的 LSB（±16g 量程下 = 2048）
    parameter IMU_RATE = 1000,      // 加速度计采样率 Hz
    parameter WIN_MS   = 5,         // 峰值跟踪窗 ms（决定延迟）
    parameter REFR_MS  = 100        // 不应期 ms（抑制鼓槌弹跳）
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             sample_valid,   // 新样本到达，一个周期
    input  wire signed [15:0] ax,
    input  wire signed [15:0] ay,
    input  wire signed [15:0] az,
    output reg              hit_valid,      // 检测到敲击，一个周期
    output reg  [1:0]       hit_type,       // 1=底鼓 2=军鼓 3=镲
    output reg  [6:0]       hit_vel         // 力度 0..127
);

    // 阈值 = 0.5g；方向判据 = ±0.3g
    localparam signed [31:0] THR_SQ = (LSBG/2) * (LSBG/2);
    localparam signed [31:0] DIR_TH = (LSBG*3)/10;
    localparam WIN_CNT  = (WIN_MS  * IMU_RATE) / 1000 + 1;   // MATLAB: wcnt>5 才触发
    localparam REFR_CNT = (REFR_MS * IMU_RATE) / 1000;
    localparam VEL_K    = (127 * 65536) / (10 * LSBG);       // Q16: vel = amp*VEL_K >> 16

    localparam S_IDLE = 2'd0, S_TRACK = 2'd1, S_SQRT = 2'd2, S_REFR = 2'd3;

    // ---- 重力基线（慢速平均）----
    reg signed [31:0] bx, by, bz;
    reg signed [31:0] dx, dy, dz;

    // ---- 峰值窗 ----
    reg [39:0] peak_sq;
    reg signed [31:0] ysum;
    reg [7:0]  wcnt;
    reg [7:0]  refr;
    reg [1:0]  st;
    reg [1:0]  type_r;

    // ---- 峰值幅值平方（40 bit，防三轴平方和溢出）----
    wire signed [39:0] dxe = dx;
    wire signed [39:0] dye = dy;
    wire signed [39:0] dze = dz;
    wire [39:0] magsq = dxe*dxe + dye*dye + dze*dze;

    // ---- 开方求真实幅值（力度需要）----
    wire        sqrt_start = (st == S_TRACK) && sample_valid && (wcnt >= WIN_CNT);
    wire        sqrt_done;
    wire [15:0] amp;
    reg         sqrt_start_d;

    isqrt u_sqrt (
        .clk   (clk),
        .rst_n (rst_n),
        .start (sqrt_start_d),
        .din   (peak_sq[31:0]),
        .dout  (amp),
        .done  (sqrt_done)
    );

    always @(posedge clk) sqrt_start_d <= sqrt_start;

    // ---- 主状态机 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bx <= 32'd0; by <= 32'd0; bz <= 32'd0;
            dx <= 32'd0; dy <= 32'd0; dz <= 32'd0;
            peak_sq <= 40'd0; ysum <= 32'd0; wcnt <= 8'd0; refr <= 8'd0;
            st <= S_IDLE; hit_valid <= 1'b0; hit_type <= 2'd0; hit_vel <= 7'd0;
            type_r <= 2'd0;
        end else begin
            hit_valid <= 1'b0;

            if (sample_valid) begin
                // 慢速平均：base += (cur - base) >> 5，算术右移保留符号
                bx <= bx + (({{16{ax[15]}}, ax} - bx) >>> 5);
                by <= by + (({{16{ay[15]}}, ay} - by) >>> 5);
                bz <= bz + (({{16{az[15]}}, az} - bz) >>> 5);
                // 动作分量 = 当前值 - 基线
                dx <= {{16{ax[15]}}, ax} - bx;
                dy <= {{16{ay[15]}}, ay} - by;
                dz <= {{16{az[15]}}, az} - bz;
            end

            case (st)
                S_IDLE: begin
                    if (sample_valid && refr == 8'd0 && magsq > THR_SQ) begin
                        peak_sq <= magsq;
                        ysum    <= dy;
                        wcnt    <= 8'd1;
                        st      <= S_TRACK;
                    end else if (sample_valid && refr != 8'd0) begin
                        refr <= refr - 8'd1;
                    end
                end

                S_TRACK: begin
                    if (sample_valid) begin
                        if (magsq > peak_sq) peak_sq <= magsq;
                        ysum <= ysum + dy;
                        wcnt <= wcnt + 8'd1;
                    end
                    if (sqrt_start) begin
                        // 方位 = 窗内 ay 均值
                        if (ysum / WIN_CNT >  DIR_TH) type_r <= 2'd2;   // 军鼓
                        else if (ysum / WIN_CNT < -DIR_TH) type_r <= 2'd3; // 镲
                        else type_r <= 2'd1;                            // 底鼓
                        st <= S_SQRT;
                    end
                end

                S_SQRT: begin
                    if (sqrt_done) begin
                        hit_valid <= 1'b1;
                        hit_type  <= type_r;
                        hit_vel   <= (amp * VEL_K) > 16'h7F00 ? 7'd127 : (amp * VEL_K) >> 16;
                        refr      <= REFR_CNT;
                        st        <= S_REFR;
                    end
                end

                S_REFR: begin
                    if (sample_valid) begin
                        if (refr != 8'd0) refr <= refr - 8'd1;
                        if (refr <= 8'd1) st <= S_IDLE;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
