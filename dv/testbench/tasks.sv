
/**
 * @brief Task to end the test
 */
task TSK_EndTest;
    $display("Simulation finished at t=%0t ns", $time);
    $finish;
endtask
