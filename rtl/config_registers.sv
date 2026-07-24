module config_registers #(
    parameter int WIDTH = 8
) (
    input  logic             clk,
    input  logic             reset_n,
    input  logic [31:0]      paddr,
    input  logic             psel,
    input  logic             penable,
    input  logic             pwrite,
    input  logic [31:0]      pwdata,
    output logic [31:0]      prdata,
    output logic             pready,
    output logic             pslverr,
    output logic             data_switch_cfg,
    input  logic [WIDTH-1:0] status_data
);
    localparam logic [31:0] CTRL_ADDR   = 32'h0000_0000;
    localparam logic [31:0] STATUS_ADDR = 32'h0000_0004;

    logic [31:0] status_word;

    assign pready = 1'b1;
    assign pslverr = 1'b0;

    always_comb begin
        status_word = '0;
        status_word[0] = data_switch_cfg;

        // Pack status_data into status_word[WIDTH:1] up to the 32-bit APB data width.
        for (int i = 0; i < WIDTH; i++) begin
            if ((i + 1) < 32) begin
                status_word[i + 1] = status_data[i];
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            data_switch_cfg <= 1'b0;
        end else if (psel && penable && pwrite) begin
            if (paddr == CTRL_ADDR) begin
                data_switch_cfg <= pwdata[0];
            end
        end
    end

    always_comb begin
        prdata = '0;

        if (psel && !pwrite) begin
            unique case (paddr)
                CTRL_ADDR:   prdata = {31'b0, data_switch_cfg};
                STATUS_ADDR: prdata = status_word;
                default:     prdata = '0;
            endcase
        end
    end
endmodule