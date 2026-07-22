
module generic_module #(
    parameter int WIDTH = 8
) (
    input logic clk,
    input logic reset,
    input logic [WIDTH-1:0] data_in,
    output logic [WIDTH-1:0] data_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out <= '0;
        end else begin
            data_out <= data_in;
        end
    end
endmodule