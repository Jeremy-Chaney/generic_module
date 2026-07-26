
module generic_module #(
    parameter int WIDTH = 8
) (
    input clk,
    input reset_n,
    input [31:0] paddr,
    input psel,
    input penable,
    input pwrite,
    input [31:0] pwdata,
    output logic [31:0] prdata,
    output logic pready,
    output logic pslverr,
    input [WIDTH-1:0] data_in,
    output wire [WIDTH-1:0]  data_out
);

    logic data_switch_cfg;

    wire [WIDTH-1:0] data_in_local = data_switch_cfg ? '0 : data_in;
    wire [WIDTH-1:0] data_in_submodule = data_switch_cfg ? data_in : '0;

    wire [WIDTH-1:0] data_out_submodule;
    reg [WIDTH-1:0] data_out_local;

    assign data_out = data_switch_cfg ? data_out_submodule : data_out_local;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            data_out_local <= '0;
        end else begin
            data_out_local <= data_in_local;
        end
    end

    generic_submodule #(
        .WIDTH(WIDTH)
    ) u_generic_submodule (
        .clk(clk),
        .reset_n(reset_n),
        .data_in(data_in_submodule),
        .data_out(data_out_submodule)
    );

    config_registers #(
        .WIDTH(WIDTH)
    ) u_config_registers (
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
        .data_switch_cfg(data_switch_cfg),
        .status_data(data_out)
    );
endmodule
