`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// hit_detector.v —— 鼓槌敲击检测（MATLAB main_drum_engine Part 3 的 RTL 直译）
//
// 算法（与 lib/ 定点黄金模型逐拍对齐，任何改动都要同步改 MATLAB 并重新生成 golden/）：
//   1) 慢速平均求重力基线：  base += (cur - base) >> 5
//      同一个滤波器办两件事 —— 减掉它就是"动作分量"，保留它就是"朝向"
//      ⚠️ 上电第一个样本直接把基线预置成当前值（primed），
//         否则 base 从 0 爬到 1g 的这段时间里 dz≡2048，会连续误触发。
//   2) 动作分量幅值平方与阈值平方比较（躲开开根号）
//      ⚠️ 千万别对加速度做两次积分求位置 —— 漂移会爆炸
//   3) 状态机 IDLE -> TRACK(峰值窗) -> FIRE -> REFRACTORY(不应期)
//      不应期必须有：鼓槌弹跳会造成一敲触发三四次，听着像机关枪
//   4) 峰值窗内累加 ay 求均值判方位（左/中/右 -> 军鼓/底鼓/镲）
//      判据用 ysum 直接与 DIR_TH_NUM 比（避免整除截断造成边界差一）
//   5) 力度 = floor(峰值幅值 * VEL_K / 65536)，封顶 127
//      幅值要真开方（阈值可以比平方，力度必须是幅值本身，所以 isqrt 躲不掉）
//
// 延迟：峰值窗 WIN_MS 是主要来源。WIN_MS=5 时端到端约 6ms（红线 10ms）。
//
// ⚠️ 时序要点：dx/dy/dz 必须是组合逻辑。
//    若把它们打成寄存器，状态机看到的是上一个样本的数据，整体晚一拍，
//    与黄金模型对不上（曾经就是这个原因导致索引差 3、事件数 3 倍）。
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

    // 阈值 = 0.5g（比平方，不开根号）；方位判据 = ±0.3g
    localparam signed [31:0] THR_SQ     = (LSBG/2) * (LSBG/2);
    localparam integer       WIN_CNT    = (WIN_MS  * IMU_RATE) / 1000 + 1;  // MATLAB: wcnt>5
    localparam integer       REFR_CNT   = (REFR_MS * IMU_RATE) / 1000;
    localparam integer       VEL_K      = (127 * 65536) / (10 * LSBG);      // Q16
    // 方位判据的"分子版"：ysum/WIN_CNT > 0.3g  <=>  ysum > 0.3*LSBg*WIN_CNT
    // 用 ceil 保证与 MATLAB 的浮点比较在边界上一致（否则 614.4 附近会差一个类型）
    localparam signed [31:0] DIR_TH_NUM = ((LSBG*3) * WIN_CNT + 9) / 10;

    localparam S_IDLE = 2'd0, S_TRACK = 2'd1, S_SQRT = 2'd2, S_REFR = 2'd3;

    // ---- 重力基线（慢速平均）----
    reg signed [31:0] bx, by, bz;
    reg               primed;          // 第一个样本已用于预置基线

    // ---- 动作分量：组合逻辑，当拍可见 ----
    wire signed [31:0] ax_ext = {{16{ax[15]}}, ax};
    wire signed [31:0] ay_ext = {{16{ay[15]}}, ay};
    wire signed [31:0] az_ext = {{16{az[15]}}, az};
    wire signed [31:0] dx = primed ? (ax_ext - bx) : 32'sd0;
    wire signed [31:0] dy = primed ? (ay_ext - by) : 32'sd0;
    wire signed [31:0] dz = primed ? (az_ext - bz) : 32'sd0;

    // ---- 峰值窗 ----
    reg [39:0] peak_sq;
    reg signed [31:0] ysum;
    reg [7:0]  wcnt;
    reg [7:0]  refr;
    reg [1:0]  st;
    reg [1:0]  type_r;

    // ---- 幅值平方（40 bit，防三轴平方和溢出）----
    wire signed [39:0] dxe = dx;
    wire signed [39:0] dye = dy;
    wire signed [39:0] dze = dz;
    wire [39:0] magsq = dxe*dxe + dye*dye + dze*dze;

    // ---- 开方求真实幅值（力度需要）----
    // 峰值窗满的时刻开火：此时 ysum 已经累加了 WIN_CNT 个 TRACK 样本
    // ⚠️ wcnt 口径必须与 MATLAB 一致：统计"已计入窗内的 TRACK 样本数"，触发拍置 0，
    //    所以开火判据是 (wcnt+1) >= WIN_CNT。若写成触发拍置 1、判据 wcnt >= WIN_CNT，
    //    虽然开火时刻同样是 trigger+WIN_CNT，但 wcnt 读数永远比黄金模型大 1，
    //    逐拍对拍时会被当成差异，掩盖真正的偏差。
    wire        sqrt_start = (st == S_TRACK) && sample_valid && ((wcnt + 8'd1) >= WIN_CNT);
    wire        sqrt_done;
    wire [15:0] amp;
    reg         sqrt_start_d;

    // peak_sq 理论上 3*32768^2=3.22e9 < 2^32，不会溢出；仍加一道饱和保险
    wire [31:0] peak_sat = (peak_sq[39:32] != 8'd0) ? 32'hFFFF_FFFF : peak_sq[31:0];

    isqrt u_sqrt (
        .clk   (clk),
        .rst_n (rst_n),
        .start (sqrt_start_d),
        .din   (peak_sat),
        .dout  (amp),
        .done  (sqrt_done)
    );

    always @(posedge clk) sqrt_start_d <= sqrt_start;

    // ---- 主状态机 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bx <= 32'sd0; by <= 32'sd0; bz <= 32'sd0;
            primed <= 1'b0;
            peak_sq <= 40'd0; ysum <= 32'sd0; wcnt <= 8'd0; refr <= 8'd0;
            st <= S_IDLE; hit_valid <= 1'b0; hit_type <= 2'd0; hit_vel <= 7'd0;
            type_r <= 2'd0;
        end else begin
            hit_valid <= 1'b0;

            if (sample_valid) begin
                if (!primed) begin
                    // 上电预置：基线直接等于第一个样本，避免爬升期误触发
                    bx <= ax_ext; by <= ay_ext; bz <= az_ext;
                    primed <= 1'b1;
                end else begin
                    // 慢速平均：base += (cur - base) >> 5，算术右移 = 向下取整
                    bx <= bx + ((ax_ext - bx) >>> 5);
                    by <= by + ((ay_ext - by) >>> 5);
                    bz <= bz + ((az_ext - bz) >>> 5);
                end
            end

            case (st)
                S_IDLE: begin
                    if (sample_valid && refr == 8'd0 && primed && magsq > THR_SQ) begin
                        peak_sq <= magsq;
                        ysum    <= 32'sd0;   // 触发样本不计入窗内均值（与 MATLAB 一致）
                        wcnt    <= 8'd0;
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
                        // 方位 = 窗内 ay 均值；用"当前样本已计入"的和来判
                        if      (ysum + dy >=  DIR_TH_NUM) type_r <= 2'd2;   // 军鼓
                        else if (ysum + dy <= -DIR_TH_NUM) type_r <= 2'd3;   // 镲
                        else                               type_r <= 2'd1;   // 底鼓
                        st <= S_SQRT;
                    end
                end

                S_SQRT: begin
                    if (sqrt_done) begin
                        // 力度：floor(amp * VEL_K / 65536)，封顶 127
                        // ⚠️ 判据必须比 "结果 > 127"，不能比 "乘积 > 16'h7F00"
                        //    （127 的 Q16 是 32'h7F0000，写成 16'h7F00 会差 256 倍，
                        //     导致力度恒为 127）
                        if ((amp * VEL_K) >> 16 > 7'd127) hit_vel <= 7'd127;
                        else                              hit_vel <= (amp * VEL_K) >> 16;
                        hit_valid <= 1'b1;
                        hit_type  <= type_r;
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
