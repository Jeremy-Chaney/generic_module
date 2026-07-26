module apb_agent (
    input  logic        clk,
    input  logic        reset_n,
    output logic [31:0] paddr,
    output logic        psel,
    output logic        penable,
    output logic        pwrite,
    output logic [31:0] pwdata,
    input  logic [31:0] prdata,
    input  logic        pready,
    input  logic        pslverr
);
    logic [31:0] wait_addr;
    logic wait_write;
    logic [31:0] wait_wdata;

    initial begin
        paddr = '0;
        psel = 1'b0;
        penable = 1'b0;
        pwrite = 1'b0;
        pwdata = '0;
    end

    task automatic apb_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk);
        paddr <= addr;
        pwdata <= data;
        pwrite <= 1'b1;
        psel <= 1'b1;
        penable <= 1'b0;

        @(posedge clk);
        penable <= 1'b1;

        wait_addr = addr;
        wait_write = 1'b1;
        wait_wdata = data;

        // Keep driving address/control until handshake completes.
        while (!pready) begin
            @(posedge clk);
            if (paddr !== wait_addr || pwrite !== wait_write || pwdata !== wait_wdata) begin
                $error("APB protocol violation: control/data changed while waiting for PREADY");
            end
        end

        if (pslverr) begin
            $error("APB target signaled PSLVERR on write access");
        end

        @(posedge clk);
        psel <= 1'b0;
        penable <= 1'b0;
        pwrite <= 1'b0;
        paddr <= '0;
        pwdata <= '0;
    endtask

    task automatic apb_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk);
        paddr <= addr;
        pwrite <= 1'b0;
        psel <= 1'b1;
        penable <= 1'b0;

        @(posedge clk);
        penable <= 1'b1;

        wait_addr = addr;
        wait_write = 1'b0;

        // Keep address/select stable until PRDATA is accepted.
        while (!pready) begin
            @(posedge clk);
            if (paddr !== wait_addr || pwrite !== wait_write) begin
                $error("APB protocol violation: control changed while waiting for PREADY");
            end
        end

        if (pslverr) begin
            $error("APB target signaled PSLVERR on read access");
        end

        data = prdata;

        @(posedge clk);
        psel <= 1'b0;
        penable <= 1'b0;
        paddr <= '0;
    endtask

    always @(posedge clk) begin
        if (reset_n && penable && !psel) begin
            $error("APB protocol violation: PENABLE asserted without PSEL");
        end
    end
endmodule