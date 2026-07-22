
initial begin
    #6ns;
    // Initialize data_in to a known value.
    data_in = '0;
    for(int i = 0; i < 100; i++) begin
        #10ns;
        data_in = data_in + 1;
    end
    #10ns;

    data_switch = 1'b1;
    // Initialize data_in to a known value.
    data_in = '0;
    for(int i = 0; i < 100; i++) begin
        #10ns;
        data_in = data_in + 1;
    end
end
