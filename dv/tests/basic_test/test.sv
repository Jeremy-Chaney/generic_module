
`include "tasks.sv"

initial begin
    localparam logic [31:0] CTRL_ADDR   = 32'h0000_0000;
    localparam logic [31:0] STATUS_ADDR = 32'h0000_0004;

    logic [31:0] rd_data;

    @(posedge reset_n);
    repeat (2) @(posedge clk);

    // Write explicit local-path selection and verify readback.
    u_apb_agent.apb_write(CTRL_ADDR, 32'h0000_0000);
    u_apb_agent.apb_read(CTRL_ADDR, rd_data);
    if (rd_data[0] !== 1'b0) begin
        $error("basic_test: control write/read mismatch, expected 0 got %0h", rd_data);
    end

    // Drive several input values and check status visibility.
    data_in = '0;
    for (int i = 0; i < 10; i++) begin
        @(posedge clk);
        data_in <= data_in + 1'b1;
    end

    repeat (2) @(posedge clk);
    u_apb_agent.apb_read(STATUS_ADDR, rd_data);
    if (rd_data[0] !== 1'b0) begin
        $error("basic_test: status switch bit expected 0, got %0h", rd_data);
    end

    $display("basic_test: APB control/status checks completed.");
    TSK_EndTest();
end
