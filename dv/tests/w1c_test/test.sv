`include "tasks.sv"

initial begin
    localparam logic [31:0] INT_STATUS_ADDR = 32'h0000_000C;
    logic [31:0] rd_data;

    @(posedge reset_n);
    repeat (2) @(posedge clk);

    u_apb_agent.apb_read(INT_STATUS_ADDR, rd_data);
    if (rd_data[0] !== 1'b0) begin
        $error("w1c_test: expected reset value 0, got %0h", rd_data);
    end

    // Hardware asserts the event flag.
    irq_event_set = 1'b1;
    @(posedge clk);
    irq_event_set = 1'b0;

    repeat (1) @(posedge clk);
    u_apb_agent.apb_read(INT_STATUS_ADDR, rd_data);
    if (rd_data[0] !== 1'b1) begin
        $error("w1c_test: expected event bit to be set by hardware, got %0h", rd_data);
    end

    // Write-0 must not clear W1C bits.
    u_apb_agent.apb_write(INT_STATUS_ADDR, 32'h0000_0000);
    u_apb_agent.apb_read(INT_STATUS_ADDR, rd_data);
    if (rd_data[0] !== 1'b1) begin
        $error("w1c_test: write-0 incorrectly cleared W1C bit, got %0h", rd_data);
    end

    // Write-1 clears the bit.
    u_apb_agent.apb_write(INT_STATUS_ADDR, 32'h0000_0001);
    u_apb_agent.apb_read(INT_STATUS_ADDR, rd_data);
    if (rd_data[0] !== 1'b0) begin
        $error("w1c_test: write-1 failed to clear W1C bit, got %0h", rd_data);
    end

    // Same-cycle clear plus hardware-set should keep the bit high (HW priority).
    irq_event_set = 1'b1;
    u_apb_agent.apb_write(INT_STATUS_ADDR, 32'h0000_0001);
    irq_event_set = 1'b0;
    repeat (1) @(posedge clk);
    u_apb_agent.apb_read(INT_STATUS_ADDR, rd_data);
    if (rd_data[0] !== 1'b1) begin
        $error("w1c_test: expected HW-set priority over SW-clear, got %0h", rd_data);
    end

    $display("w1c_test: W1C behavior checks completed.");
    TSK_EndTest();
end