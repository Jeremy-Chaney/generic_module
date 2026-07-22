
`timescale 1ns/1ps

`ifndef TEST_FILE
`define TEST_FILE "../tests/basic_test/test.sv"
`endif

module tb;
    localparam int WIDTH = 8;
    localparam time RESET_HOLD = 2ns;
    localparam time SIM_TIMEOUT = 100ns;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [WIDTH-1:0] data_in;
    logic [WIDTH-1:0] data_out;

    generic_module #(
        .WIDTH(WIDTH)
    ) dut (
        .clk(clk),
        .reset(reset),
        .data_in(data_in),
        .data_out(data_out)
    );

    // 100 kHz clock: 10 us period, 5 us half-period.
    always #5ns clk = ~clk;

    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);

        // Keep reset asserted briefly, then let the selected directed test run.
        #RESET_HOLD reset = 1'b0;
    end

    initial begin : simulation_watchdog
        #SIM_TIMEOUT;
        $display("Simulation finished at t=%0t ns", $time);
        $finish;
    end

`include `TEST_FILE

endmodule