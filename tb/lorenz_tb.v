// =============================================================================
// Testbench for lorenz_rk4_fsm_stages_dbg.
// Also writes a VCD waveform dump so you can load it straight into a viewer
// (or ISE ISIM will show waveforms automatically without needing this dump).
// =============================================================================
`timescale 1ns/1ps

module lorenz_tb;

    localparam NUM_STEPS = 20000;  // small run, just enough to inspect waveforms

    reg  clk;
    reg  rst;
    reg  enable;

    wire signed [31:0] x_out, y_out, z_out;
    wire valid, done;
    wire [2:0] state_out;
    wire signed [31:0] xe_out, ye_out, ze_out;
    wire signed [31:0] dx_out, dy_out, dz_out;
    
    integer fp;

    lorenz_rk4_fsm #(
        .WIDTH(32),
        .FRAC(16),
        .NUM_STEPS(NUM_STEPS)
    ) uut (
        .clk(clk), .rst(rst), .enable(enable),
        .x_out(x_out), .y_out(y_out), .z_out(z_out),
        .valid(valid), .done(done),
        .state_out(state_out),
        .xe_out(xe_out), .ye_out(ye_out), .ze_out(ze_out),
        .dx_out(dx_out), .dy_out(dy_out), .dz_out(dz_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("lorenz_rk4_fsm.vcd");
        $dumpvars(0, lorenz_tb);
        
        // Open text file for MATLAB
fp = $fopen("lorenz_data.txt","w");

// Optional header
$fwrite(fp,"Time\tX\tY\tZ\n");

        rst    = 1;
        enable = 0;
        @(posedge clk);
        @(posedge clk);
        rst    = 0;
        enable = 1;

        while (!done) @(posedge clk);

        $display("Done.");
        $finish;
    end
    
    always @(posedge clk)
begin
    if(valid)
    begin
        $fwrite(fp,"%0t\t%d\t%d\t%d\n",
                $time,
                x_out,
                y_out,
                z_out);
    end
end

endmodule