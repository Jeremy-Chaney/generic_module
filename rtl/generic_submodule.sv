
module generic_submodule #(
    parameter int WIDTH = 8
) (
    input logic clk,
    input logic reset_n,
    input logic [WIDTH-1:0] data_in,
    output logic [WIDTH-1:0] data_out
);
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            data_out <= '0;
        end else begin
            data_out <= data_in;
        end
    end
endmodule
