module sequential_adder #(parameter SIZE = 8)
(
    input logic clk,
    input logic start,

    input logic [SIZE-1:0] a,
    input logic [SIZE-1:0] b,

    output logic [SIZE-1:0] sum,
    output logic carry,
    output logic done
);

logic [SIZE:0] temp0;
logic [SIZE-1:0] temp1;

always_comb begin
    {carry, sum} = temp0;
    done = ~(|temp1);
end

always_ff @(posedge clk) begin
    if(start) begin
        temp0 <= a;
        temp1 <= b;
    end
    else begin
        temp0 <= {(temp0[SIZE-1:0] & temp1), 1'b1};
        temp1 <= temp0 ^ temp1;
    end
end
endmodule