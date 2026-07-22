
initial begin
    #6ns;
    // Initialize data_in to a known value.
    data_in = '0;
    while(1)begin
        #10ns;
        data_in = data_in + 1;
    end
end
