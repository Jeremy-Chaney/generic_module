
/**
 * @brief Task to end the test
 */
task TSK_EndTest;
    $display("INFO: Test finished at time %0t", $time);
    $finish;
endtask
