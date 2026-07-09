`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    14:23:00 07/06/2026 
// Design Name: 
// Module Name:    lorenz_common 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
// =============================================================================
// Shared building blocks for the Lorenz RK4 integrator (Q16.16 fixed point).
// Used by both lorenz_rk4.v (fully parallel) and lorenz_rk4_fsm.v (FSM/serial).
// =============================================================================

// -----------------------------------------------------------------------------
// Fixed-point multiplier: p = (a * b) >>> FRAC
// -----------------------------------------------------------------------------
module mult_q16 #(
    parameter WIDTH = 32,
    parameter FRAC  = 16
)(
    input  signed [WIDTH-1:0]   a,
    input  signed [WIDTH-1:0]   b,
    output signed [WIDTH-1:0]   p
);
    wire signed [2*WIDTH-1:0] full_product;
    assign full_product = a * b;
    assign p = full_product >>> FRAC;
endmodule


// -----------------------------------------------------------------------------
// Lorenz derivative: dx = sigma*(y-x), dy = x*(rho-z)-y, dz = x*x - beta*z
// Purely combinational. Contains 4 internal multiplies.
// -----------------------------------------------------------------------------
module lorenz_deriv #(
    parameter WIDTH = 32,
    parameter FRAC  = 16
)(
    input  signed [WIDTH-1:0] x, y, z,
    input  signed [WIDTH-1:0] sigma, rho, beta,
    output signed [WIDTH-1:0] dx, dy, dz
);
    wire signed [WIDTH-1:0] y_minus_x;
    wire signed [WIDTH-1:0] rho_minus_z;
    wire signed [WIDTH-1:0] x_times_rho_minus_z;
    wire signed [WIDTH-1:0] x_squared;
    wire signed [WIDTH-1:0] beta_times_z;

    assign y_minus_x   = y - x;
    assign rho_minus_z = rho - z;

    mult_q16 #(WIDTH, FRAC) mult_dx (.a(sigma), .b(y_minus_x), .p(dx));

    mult_q16 #(WIDTH, FRAC) mult_dy (.a(x), .b(rho_minus_z), .p(x_times_rho_minus_z));
    assign dy = x_times_rho_minus_z - y;

    mult_q16 #(WIDTH, FRAC) mult_xx (.a(x),    .b(x), .p(x_squared));
    mult_q16 #(WIDTH, FRAC) mult_bz (.a(beta), .b(z), .p(beta_times_z));
    assign dz = x_squared - beta_times_z;

endmodule
