
module generic_module #(
    parameter int WIDTH = 8
) (
    input clk,
    input reset_n,
    input data_switch,
    input [WIDTH-1:0] data_in,
    output wire [WIDTH-1:0]  data_out
);

    wire [WIDTH-1:0] data_in_local = data_switch ? '0 : data_in;
    wire [WIDTH-1:0] data_in_submodule = data_switch ? data_in : '0;

    wire [WIDTH-1:0] data_out_submodule;
    reg [WIDTH-1:0] data_out_local;

    assign data_out = data_switch ? data_out_submodule : data_out_local;

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
endmodule