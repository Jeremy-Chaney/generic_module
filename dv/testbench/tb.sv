
`timescale 1us/1ns

module tb;
    localparam int WIDTH = 8;

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
        #6ns;
        // Initialize data_in to a known value.
        data_in = '0;
        while(1)begin
            #10ns;
            data_in = data_in + 1;
        end
    end

    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);

        // Keep reset asserted briefly, then run to 20 us total.
        #2ns reset = 1'b0;
        #100ns;

        $display("Simulation finished at t=%0t ns", $time);
        $finish;
    end

endmodule