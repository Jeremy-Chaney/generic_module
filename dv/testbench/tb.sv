
`timescale 1ns/1ps

module tb;
    localparam int WIDTH = 8;
    localparam time RESET_HOLD = 2ns;
    localparam time SIM_TIMEOUT = 2ms;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic data_switch = 1'b0;
    logic [WIDTH-1:0] data_in;
    logic [WIDTH-1:0] data_out;

    generic_module #(
        .WIDTH(WIDTH)
    ) u_dut (
        .clk(clk),
        .reset_n(reset_n),
        .data_switch(data_switch),
        .data_in(data_in),
        .data_out(data_out)
    );

    // clocking logic for the testbench
    `include "clock.sv"

    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);

        // Keep reset_n asserted briefly, then let the selected directed test run.
        #RESET_HOLD reset_n = 1'b1;
    end

    initial begin : simulation_watchdog
        #SIM_TIMEOUT;
        $display("Simulation finished at t=%0t ns", $time);
        $finish;
    end

`include "test.sv"

endmodule