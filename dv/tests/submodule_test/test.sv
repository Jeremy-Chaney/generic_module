
`include "tasks.sv"

initial begin
    localparam logic [31:0] CTRL_ADDR   = 32'h0000_0000;
    localparam logic [31:0] STATUS_ADDR = 32'h0000_0004;

    logic [31:0] rd_data;

    @(posedge reset_n);
    repeat (2) @(posedge clk);

    // Start with local-path mode.
    u_apb_agent.apb_write(CTRL_ADDR, 32'h0000_0000);
    u_apb_agent.apb_read(CTRL_ADDR, rd_data);
    if (rd_data[0] !== 1'b0) begin
        $error("submodule_test: expected local-path control bit 0, got %0h", rd_data);
    end

    data_in = '0;
    for (int i = 0; i < 50; i++) begin
        @(posedge clk);
        data_in <= data_in + 1'b1;
    end

    // Switch to submodule path via APB register and verify readback.
    u_apb_agent.apb_write(CTRL_ADDR, 32'h0000_0001);
    u_apb_agent.apb_read(CTRL_ADDR, rd_data);
    if (rd_data[0] !== 1'b1) begin
        $error("submodule_test: expected submodule-path control bit 1, got %0h", rd_data);
    end

    for (int i = 0; i < 50; i++) begin
        @(posedge clk);
        data_in <= data_in + 1'b1;
    end

    // Status register must reflect switched mode.
    u_apb_agent.apb_read(STATUS_ADDR, rd_data);
    if (rd_data[0] !== 1'b1) begin
        $error("submodule_test: status switch bit expected 1, got %0h", rd_data);
    end

    $display("submodule_test: APB mode switch and status checks completed.");
    TSK_EndTest();
end
