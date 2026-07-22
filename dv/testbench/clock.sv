
initial begin
    @(posedge reset_n);
    #11ns;

    // 100 kHz clock: 10 us period, 5 us half-period.
    while(1) begin
        #5ns;
        clk = ~clk;
    end
end