
`timescale 1ns/1ps

module tb;
    localparam int WIDTH = 8;
    localparam int APB_DWIDTH = 32;
    localparam int APB_AWIDTH = 32;
    localparam time RESET_HOLD = 2ns;
    localparam time SIM_TIMEOUT = 2ms;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic [31:0] paddr;
    logic psel;
    logic penable;
    logic pwrite;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic pready;
    logic pslverr;
    logic [WIDTH-1:0] data_in;
    logic [WIDTH-1:0] data_out;
    logic irq_event_set = 1'b0;

    generic_module #(
        .APB_DWIDTH(APB_DWIDTH),
        .APB_AWIDTH(APB_AWIDTH),
        .WIDTH(WIDTH)
    ) u_dut (
        .clk(clk),
        .reset_n(reset_n),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .data_in(data_in),
        .irq_event_set(irq_event_set),
        .data_out(data_out)
    );

    apb_agent u_apb_agent (
        .clk(clk),
        .reset_n(reset_n),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr)
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