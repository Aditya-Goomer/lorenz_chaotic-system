// =============================================================================
// Lorenz RK4 integrator - FSM version, ONE STATE PER RK4 STAGE - DEBUG BUILD.
//
// Functionally identical to lorenz_rk4_fsm_stages.v. x_out/y_out/z_out still
// only update once per full RK4 step (that's mathematically correct - it's
// the actual integrated trajectory, sampled once per step, just like the
// Python xs.append(x) happening once per loop iteration).
//
// Added for waveform debugging only: state_out, xe_out/ye_out/ze_out (the
// per-stage evaluation point) DO change every single clock, since the FSM
// evaluates a new stage each cycle. Add these to your waveform if you want
// to see activity on every clock edge instead of once every 6 cycles.
//
// Requires lorenz_common.v (mult_q16, lorenz_deriv) to also be compiled.
// =============================================================================
module lorenz_rk4_fsm #(
    parameter WIDTH      = 32,
    parameter FRAC       = 16,
    parameter NUM_STEPS  = 20000
)(
    input                       clk,
    input                       rst,
    input                       enable,
    output signed [WIDTH-1:0]   x_out,
    output signed [WIDTH-1:0]   y_out,
    output signed [WIDTH-1:0]   z_out,
    output                      valid,
    output                      done,

    // ---- Debug-only outputs: change every clock cycle, for waveform viewing ----
    output       [2:0]          state_out,   // current FSM state (1-4=stage, 5=combine, 6=update)
    output signed [WIDTH-1:0]   xe_out,      // x evaluation point used THIS cycle
    output signed [WIDTH-1:0]   ye_out,
    output signed [WIDTH-1:0]   ze_out,
    output signed [WIDTH-1:0]   dx_out,      // raw derivative computed THIS cycle
    output signed [WIDTH-1:0]   dy_out,
    output signed [WIDTH-1:0]   dz_out
);

    localparam signed [WIDTH-1:0] SIGMA     = 32'sd524288;   // 8.0
    localparam signed [WIDTH-1:0] RHO       = 32'sd1835008;  // 28.0
    localparam signed [WIDTH-1:0] BETA      = 32'sd174763;   // 8/3
    localparam signed [WIDTH-1:0] DT        = 32'sd655;      // 0.01
    localparam signed [WIDTH-1:0] ONE_SIXTH = 32'sd10923;    // 1/6
    localparam signed [WIDTH-1:0] ONE       = 32'sd65536;    // 1.0

    localparam [2:0]
        S_RESET   = 3'd0,
        S_STAGE1  = 3'd1,
        S_STAGE2  = 3'd2,
        S_STAGE3  = 3'd3,
        S_STAGE4  = 3'd4,
        S_COMBINE = 3'd5,
        S_UPDATE  = 3'd6,
        S_DONE    = 3'd7;

    reg [2:0] state;
    reg signed [WIDTH-1:0] x, y, z;
    reg signed [WIDTH-1:0] kx [1:4];
    reg signed [WIDTH-1:0] ky [1:4];
    reg signed [WIDTH-1:0] kz [1:4];
    reg signed [WIDTH-1:0] deltax, deltay, deltaz;
    reg [31:0] step_count;
    reg        valid_r;

    reg signed [WIDTH-1:0] xe, ye, ze;
    always @(*) begin
        case (state)
            S_STAGE1: begin xe = x;                 ye = y;                 ze = z;                 end
            S_STAGE2: begin xe = x + (kx[1]>>>1);   ye = y + (ky[1]>>>1);   ze = z + (kz[1]>>>1);   end
            S_STAGE3: begin xe = x + (kx[2]>>>1);   ye = y + (ky[2]>>>1);   ze = z + (kz[2]>>>1);   end
            S_STAGE4: begin xe = x + kx[3];          ye = y + ky[3];          ze = z + kz[3];          end
            default:  begin xe = x;                 ye = y;                 ze = z;                 end
        endcase
    end

    wire signed [WIDTH-1:0] dx_w, dy_w, dz_w;
    lorenz_deriv #(WIDTH, FRAC) deriv_unit (
        .x(xe), .y(ye), .z(ze),
        .sigma(SIGMA), .rho(RHO), .beta(BETA),
        .dx(dx_w), .dy(dy_w), .dz(dz_w)
    );

    reg  signed [WIDTH-1:0] mul_a_x, mul_a_y, mul_a_z;
    reg  signed [WIDTH-1:0] mul_b;
    wire signed [WIDTH-1:0] mul_p_x, mul_p_y, mul_p_z;

    mult_q16 #(WIDTH, FRAC) mult_x (.a(mul_a_x), .b(mul_b), .p(mul_p_x));
    mult_q16 #(WIDTH, FRAC) mult_y (.a(mul_a_y), .b(mul_b), .p(mul_p_y));
    mult_q16 #(WIDTH, FRAC) mult_z (.a(mul_a_z), .b(mul_b), .p(mul_p_z));

    wire signed [WIDTH-1:0] sumx, sumy, sumz;
    assign sumx = kx[1] + (kx[2]<<<1) + (kx[3]<<<1) + kx[4];
    assign sumy = ky[1] + (ky[2]<<<1) + (ky[3]<<<1) + ky[4];
    assign sumz = kz[1] + (kz[2]<<<1) + (kz[3]<<<1) + kz[4];

    always @(*) begin
        case (state)
            S_STAGE1, S_STAGE2, S_STAGE3, S_STAGE4: begin
                mul_a_x = dx_w; mul_a_y = dy_w; mul_a_z = dz_w; mul_b = DT;
            end
            S_COMBINE: begin
                mul_a_x = sumx; mul_a_y = sumy; mul_a_z = sumz; mul_b = ONE_SIXTH;
            end
            default: begin
                mul_a_x = 0; mul_a_y = 0; mul_a_z = 0; mul_b = 0;
            end
        endcase
    end

    // ---------------- Outputs ----------------
    assign x_out = x;
    assign y_out = y;
    assign z_out = z;
    assign valid = valid_r;
    assign done  = (state == S_DONE);

    // Debug: these change every clock, unlike x_out/y_out/z_out
    assign state_out = state;
    assign xe_out = xe;
    assign ye_out = ye;
    assign ze_out = ze;
    assign dx_out = dx_w;
    assign dy_out = dy_w;
    assign dz_out = dz_w;

    // ---------------- Main FSM ----------------
    always @(posedge clk) begin
        if (rst) begin
            x          <= ONE;
            y          <= ONE;
            z          <= ONE;
            step_count <= 32'd0;
            valid_r    <= 1'b0;
            state      <= S_STAGE1;
        end else if (enable) begin
            valid_r <= 1'b0;

            case (state)
                S_STAGE1: begin kx[1] <= mul_p_x; ky[1] <= mul_p_y; kz[1] <= mul_p_z; state <= S_STAGE2;  end
                S_STAGE2: begin kx[2] <= mul_p_x; ky[2] <= mul_p_y; kz[2] <= mul_p_z; state <= S_STAGE3;  end
                S_STAGE3: begin kx[3] <= mul_p_x; ky[3] <= mul_p_y; kz[3] <= mul_p_z; state <= S_STAGE4;  end
                S_STAGE4: begin kx[4] <= mul_p_x; ky[4] <= mul_p_y; kz[4] <= mul_p_z; state <= S_COMBINE; end

                S_COMBINE: begin
                    deltax <= mul_p_x;
                    deltay <= mul_p_y;
                    deltaz <= mul_p_z;
                    state  <= S_UPDATE;
                end

                S_UPDATE: begin
                    x          <= x + deltax;
                    y          <= y + deltay;
                    z          <= z + deltaz;
                    step_count <= step_count + 1;
                    valid_r    <= 1'b1;
                    if (step_count + 1 >= NUM_STEPS)
                        state <= S_DONE;
                    else
                        state <= S_STAGE1;
                end

                S_DONE: state <= S_DONE;

                default: state <= S_STAGE1;
            endcase
        end
    end

endmodule