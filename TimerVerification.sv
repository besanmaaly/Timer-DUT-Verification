//Besan Maaly  1222776  
`timescale 1ns/1ps

// ============================================================================
// timer_if.sv
// ============================================================================

interface timer_if (input logic clk);

    // ------------------------------------------------------------------------
    // DUT external interface
    // ------------------------------------------------------------------------
    wire  [3:0] d;
    logic [3:0] d_drv;

    logic [1:0] a;
    logic       g0;
    logic       g1;
    logic       rst_n;

    logic       out0;
    logic       out1;

    // ------------------------------------------------------------------------
    // DUT internal state - verification-only observation
    // These are NOT driven by the testbench.
    // They are connected in tb_top using continuous assignments.
    // ------------------------------------------------------------------------
    wire [7:0] dut_counter0;
    wire [7:0] dut_counter1;

    wire [2:0] dut_mode0;
    wire [2:0] dut_mode1;

    wire       dut_ptr0;
    wire       dut_ptr1;

    wire [7:0] dut_cnt0;
    wire [7:0] dut_cnt1;

    // TB drives d_drv; the DUT sees resolved d.
    assign d = d_drv;

    // ------------------------------------------------------------------------
    // Modports
    // ------------------------------------------------------------------------
    modport DRIVER (
        input  clk,
        output a,
        output d_drv,
        output g0,
        output g1,
        output rst_n
    );

    modport MONITOR (
        input clk,
        input a,
        input d,
        input g0,
        input g1,
        input rst_n,
        input out0,
        input out1,

        input dut_counter0,
        input dut_counter1,
        input dut_mode0,
        input dut_mode1,
        input dut_ptr0,
        input dut_ptr1,
        input dut_cnt0,
        input dut_cnt1
    );

    task automatic init_signals();
        a     = 2'b11;
        d_drv = 4'bz;
        g0    = 1'b0;
        g1    = 1'b0;
        rst_n = 1'b0;
    endtask

endinterface : timer_if


// ============================================================================
// PACKAGE
// ============================================================================

package timer_pkg;

    // ------------------------------------------------------------------------
    // Specification constants
    // ------------------------------------------------------------------------
    parameter int C0_MIN = 50;
    parameter int C0_MAX = 200;

    parameter int C1_MIN = 2;
    parameter int C1_MAX = 150;

    // ------------------------------------------------------------------------
    // Operation types
    // ------------------------------------------------------------------------
    typedef enum bit [3:0] {
        OP_WRITE_C0       = 4'd0,
        OP_WRITE_C1       = 4'd1,
        OP_WRITE_CTRL     = 4'd2,
        OP_WRITE_INV      = 4'd3,
        OP_IDLE           = 4'd4,
        OP_WRITE_C0_LOW   = 4'd5,
        OP_WRITE_C1_LOW   = 4'd6
    } op_kind_e;


    // =========================================================================
    // timer_txn
    // =========================================================================

    class timer_txn;

        rand op_kind_e      kind;

        rand bit [7:0]      data8;

        rand bit            ctrl_sel;
        rand bit [2:0]      ctrl_mode;

        rand bit            g0;
        rand bit            g1;

        rand int unsigned   idle_cycles;
        rand bit            do_reset;

        constraint c_idle {
            soft idle_cycles inside {[0:3]};
        }

        constraint c_reset_rare {
            do_reset dist {
                1'b1 := 2,
                1'b0 := 98
            };
        }

        constraint c_kind_dist {
            kind dist {
                OP_WRITE_C0     := 25,
                OP_WRITE_C1     := 25,
                OP_WRITE_CTRL   := 20,
                OP_WRITE_INV    := 10,
                OP_IDLE         := 10,
                OP_WRITE_C0_LOW := 5,
                OP_WRITE_C1_LOW := 5
            };
        }

        constraint c_gate_dist {
            g0 dist {
                1'b1 := 70,
                1'b0 := 30
            };

            g1 dist {
                1'b1 := 70,
                1'b0 := 30
            };
        }

        constraint c_data_wide {
            data8 inside {[0:255]};
        }

    endclass : timer_txn


    // =========================================================================
    // bus_txn
    // =========================================================================

    class bus_txn;

        // External sampled signals
        bit [1:0] a;
        bit [3:0] d;

        bit g0;
        bit g1;
        bit rst_n;

        bit out0;
        bit out1;

        // Internal DUT state
        bit [7:0] dut_counter0;
        bit [7:0] dut_counter1;

        bit [2:0] dut_mode0;
        bit [2:0] dut_mode1;

        bit dut_ptr0;
        bit dut_ptr1;

        bit [7:0] dut_cnt0;
        bit [7:0] dut_cnt1;

        // Attempted counter write information
        bit       write_complete;
        bit       write_low_only;
        bit [1:0] write_addr;
        bit [7:0] attempted_value;

        time t;

    endclass : bus_txn


    // =========================================================================
    // Generator
    // =========================================================================

    class timer_generator;

        mailbox #(timer_txn) gen2drv;
        mailbox #(bit)       done2gen;

        string name;

        function new(
            string name,
            mailbox #(timer_txn) gen2drv,
            mailbox #(bit) done2gen
        );

            this.name    = name;
            this.gen2drv = gen2drv;
            this.done2gen = done2gen;

        endfunction


        task send(timer_txn t);

            bit done;

            gen2drv.put(t);

            done2gen.get(done);

        endtask


        // ---------------------------------------------------------------------
        // Counter write
        // ---------------------------------------------------------------------

        task write_counter(
            bit sel,
            bit [7:0] val,
            bit gval0 = 1'b1,
            bit gval1 = 1'b1,
            int idle = 0,
            bit rst = 0
        );

            timer_txn t = new();

            assert(t.randomize() with {

                kind == (sel ? OP_WRITE_C1 : OP_WRITE_C0);

                data8 == val;

                g0 == gval0;
                g1 == gval1;

                idle_cycles == idle;
                do_reset == rst;

            })
            else $fatal(1, "Randomization failed in write_counter");

            send(t);

        endtask


        // ---------------------------------------------------------------------
        // Incomplete low bit group write
        // ---------------------------------------------------------------------

        task write_counter_low_only(
            bit sel,
            bit [3:0] low,
            bit gval0 = 1'b0,
            bit gval1 = 1'b0
        );

            timer_txn t = new();

            assert(t.randomize() with {

                kind == (sel ? OP_WRITE_C1_LOW : OP_WRITE_C0_LOW);

                data8[3:0] == low;

                g0 == gval0;
                g1 == gval1;

                idle_cycles == 0;
                do_reset == 0;

            })
            else $fatal(1, "Randomization failed in write_counter_low_only");

            send(t);

        endtask


        // ---------------------------------------------------------------------
        // Control write
        // ---------------------------------------------------------------------

        task write_control(
            bit sel,
            bit [2:0] mode,
            bit gval0 = 1'b1,
            bit gval1 = 1'b1,
            int idle = 0,
            bit rst = 0
        );

            timer_txn t = new();

            assert(t.randomize() with {

                kind == OP_WRITE_CTRL;

                ctrl_sel == sel;
                ctrl_mode == mode;

                g0 == gval0;
                g1 == gval1;

                idle_cycles == idle;
                do_reset == rst;

            })
            else $fatal(1, "Randomization failed in write_control");

            send(t);

        endtask


        // ---------------------------------------------------------------------
        // Invalid address
        // ---------------------------------------------------------------------

        task write_invalid(
            bit [3:0] val = 4'h0,
            bit gval0 = 1'b1,
            bit gval1 = 1'b1,
            int idle = 0
        );

            timer_txn t = new();

            assert(t.randomize() with {

                kind == OP_WRITE_INV;

                data8[3:0] == val;

                g0 == gval0;
                g1 == gval1;

                idle_cycles == idle;
                do_reset == 0;

            })
            else $fatal(1, "Randomization failed in write_invalid");

            send(t);

        endtask


        // ---------------------------------------------------------------------
        // Idle
        // ---------------------------------------------------------------------

        task idle_cycles_only(
            int n,
            bit gval0 = 1'b1,
            bit gval1 = 1'b1
        );

            timer_txn t = new();

            assert(t.randomize() with {

                kind == OP_IDLE;

                g0 == gval0;
                g1 == gval1;

                idle_cycles == n;

                do_reset == 0;

            })
            else $fatal(1, "Randomization failed in idle_cycles_only");

            send(t);

        endtask


        // ---------------------------------------------------------------------
        // Reset
        // ---------------------------------------------------------------------

        task do_reset_pulse();

            timer_txn t = new();

            assert(t.randomize() with {

                kind == OP_IDLE;

                idle_cycles == 0;

                do_reset == 1;

            })
            else $fatal(1, "Randomization failed in do_reset_pulse");

            send(t);

        endtask


        // ---------------------------------------------------------------------
        // Random regression
        // ---------------------------------------------------------------------

        task gen_random(int num);

            repeat(num) begin

                timer_txn t = new();

                assert(t.randomize())
                else $fatal(1, "Randomization failed in random regression");

                send(t);

            end

        endtask


        // ---------------------------------------------------------------------
        // Corner ranges
        // ---------------------------------------------------------------------

        task gen_corner_ranges();

            do_reset_pulse();

            // Counter 0
            write_counter(0, C0_MIN-1, 0, 0, 1);
            write_counter(0, C0_MIN,   0, 0, 1);
            write_counter(0, C0_MIN+1, 0, 0, 1);

            write_counter(0, C0_MAX-1, 0, 0, 1);
            write_counter(0, C0_MAX,   0, 0, 1);
            write_counter(0, C0_MAX+1, 0, 0, 1);

            // Counter 1
            write_counter(1, C1_MIN-1, 0, 0, 1);
            write_counter(1, C1_MIN,   0, 0, 1);
            write_counter(1, C1_MIN+1, 0, 0, 1);

            write_counter(1, C1_MAX-1, 0, 0, 1);
            write_counter(1, C1_MAX,   0, 0, 1);
            write_counter(1, C1_MAX+1, 0, 0, 1);

        endtask


        // ---------------------------------------------------------------------
        // Mode parity
        // ---------------------------------------------------------------------

        task gen_mode_parity();

            do_reset_pulse();

            // Mode 2 - C0
            write_control(0, 3'd2, 0, 0, 1);

            write_counter(0, 100, 0, 0, 1); // legal even
            write_counter(0, 101, 0, 0, 1); // illegal odd

            // Mode 3 - C0
            write_control(0, 3'd3, 0, 0, 1);

            write_counter(0, 121, 0, 0, 1); // legal odd
            write_counter(0, 120, 0, 0, 1); // illegal even

            // Mode 4 - C0
            write_control(0, 3'd4, 0, 0, 1);

            write_counter(0, 151, 0, 0, 1); // legal odd
            write_counter(0, 150, 0, 0, 1); // illegal even

            // Counter 1
            write_control(1, 3'd2, 0, 0, 1);

            write_counter(1, 60, 0, 0, 1); // legal
            write_counter(1, 61, 0, 0, 1); // illegal

            write_control(1, 3'd3, 0, 0, 1);

            write_counter(1, 61, 0, 0, 1); // legal
            write_counter(1, 60, 0, 0, 1); // illegal

            write_control(1, 3'd4, 0, 0, 1);

            write_counter(1, 149, 0, 0, 1); // legal
            write_counter(1, 148, 0, 0, 1); // illegal

        endtask


        // ---------------------------------------------------------------------
        // Write while counting
        // ---------------------------------------------------------------------

        task gen_write_while_counting();

            do_reset_pulse();

            // Program legal initial value
            write_counter(0, 80, 0, 0, 1);

            write_control(0, 3'd0, 0, 0, 1);

            // Let C0 count
            idle_cycles_only(5, 1, 0);

            // Must be blocked because C0 is counting and g0=1
            write_counter(0, 120, 1, 0, 1);

            // Stop C0
            idle_cycles_only(5, 0, 0);

            // Must be allowed
            write_counter(0, 130, 0, 0, 1);

        endtask


        // ---------------------------------------------------------------------
        // Invalid address
        // ---------------------------------------------------------------------

        task gen_invalid_address();

            do_reset_pulse();

            write_counter(0, 90, 0, 0, 1);

            write_control(0, 3'd1, 0, 0, 1);

            write_invalid(4'hF, 0, 0, 1);

            write_invalid(4'h0, 0, 0, 1);

        endtask


        // ---------------------------------------------------------------------
        // Mode switch
        // ---------------------------------------------------------------------

        task gen_mode_switch();

            do_reset_pulse();

            write_counter(0, 80, 0, 0, 1);

            write_control(0, 3'd0, 0, 0, 1);

            // Count to a non-zero value
            idle_cycles_only(30, 1, 0);

            // Change mode without resetting cnt
            write_control(0, 3'd1, 1, 0, 1);

            idle_cycles_only(90, 1, 0);

        endtask


        // ---------------------------------------------------------------------
        // Reset
        // ---------------------------------------------------------------------

        task gen_reset_test();

            do_reset_pulse();

            write_counter(0, 100, 0, 0, 1);

            write_control(0, 3'd0, 0, 0, 1);

            idle_cycles_only(20, 1, 1);

            do_reset_pulse();

            idle_cycles_only(5, 0, 0);

        endtask


        // ---------------------------------------------------------------------
        // Incomplete write
        // ---------------------------------------------------------------------

        task gen_incomplete_write();

            do_reset_pulse();

            write_counter(0, 100, 0, 0, 1);

            write_control(0, 3'd0, 0, 0, 1);

            idle_cycles_only(10, 1, 0);

            // Low -bit group only.
            // This must NOT update effective C0.
            write_counter_low_only(0, 4'h8, 0, 0);

            idle_cycles_only(10, 1, 0);

            // Now perform a complete legal write.
            write_counter(0, 120, 0, 0, 1);

            idle_cycles_only(10, 1, 0);

        endtask


        // ---------------------------------------------------------------------
        // Output mode test
        // ---------------------------------------------------------------------

        task gen_output_modes();

            do_reset_pulse();

            // Mode 0
            write_counter(0, 50, 0, 0, 1);
            write_control(0, 3'd0, 0, 0, 1);
            idle_cycles_only(120, 1, 0);

            // Mode 1
            write_control(0, 3'd1, 1, 0, 1);
            idle_cycles_only(120, 1, 0);

            // Mode 2: even
            write_counter(0, 100, 0, 0, 1);
            write_control(0, 3'd2, 0, 0, 1);
            idle_cycles_only(220, 1, 0);

            // Mode 3: odd
            write_counter(0, 101, 0, 0, 1);
            write_control(0, 3'd3, 0, 0, 1);
            idle_cycles_only(220, 1, 0);

            // Mode 4: odd
            write_counter(0, 101, 0, 0, 1);
            write_control(0, 3'd4, 0, 0, 1);
            idle_cycles_only(220, 1, 0);


            // Repeat selected modes on counter1
            write_counter(1, 20, 0, 0, 1);

            write_control(1, 3'd0, 0, 0, 1);
            idle_cycles_only(50, 0, 1);

            write_control(1, 3'd1, 0, 1, 1);
            idle_cycles_only(50, 0, 1);

            write_counter(1, 20, 0, 0, 1);

            write_control(1, 3'd2, 0, 0, 1);
            idle_cycles_only(50, 0, 1);

            write_counter(1, 21, 0, 0, 1);

            write_control(1, 3'd3, 0, 0, 1);
            idle_cycles_only(50, 0, 1);

            write_control(1, 3'd4, 0, 0, 1);
            idle_cycles_only(50, 0, 1);

        endtask

        // ---------------------------------------------------------------------
        // Exhaustive mode/value cross coverage
        // ---------------------------------------------------------------------
        // Exercise every mode with every attempted-value bin.  Invalid values
        // are intentionally attempted as well; the reference model must reject
        // them without changing the committed counter.
        task gen_mode_value_cross();
            bit [2:0] m;

            do_reset_pulse();

            for (int mi = 0; mi <= 4; mi++) begin
                m = mi[2:0];
                write_control(0, m, 0, 0, 1);
                write_counter(0, 8'd49,  0, 0, 1);
                write_counter(0, 8'd50,  0, 0, 1);
                write_counter(0, 8'd51,  0, 0, 1);
                write_counter(0, 8'd100, 0, 0, 1);
                write_counter(0, 8'd199, 0, 0, 1);
                write_counter(0, 8'd200, 0, 0, 1);
                write_counter(0, 8'd201, 0, 0, 1);
            end

            for (int mi = 0; mi <= 4; mi++) begin
                m = mi[2:0];
                write_control(1, m, 0, 0, 1);
                write_counter(1, 8'd1,   0, 0, 1);
                write_counter(1, 8'd2,   0, 0, 1);
                write_counter(1, 8'd3,   0, 0, 1);
                write_counter(1, 8'd20,  0, 0, 1);
                write_counter(1, 8'd149, 0, 0, 1);
                write_counter(1, 8'd150, 0, 0, 1);
                write_counter(1, 8'd151, 0, 0, 1);
            end
        endtask

    endclass : timer_generator


    // =========================================================================
    // DRIVER
    // =========================================================================

    class timer_driver;

        virtual timer_if.DRIVER vif;

        mailbox #(timer_txn) gen2drv;
        mailbox #(bit)       done2gen;

        string name;

        bit cur_g0;
        bit cur_g1;

        int unsigned num_driven;


        function new(
            string name,
            virtual timer_if.DRIVER vif,
            mailbox #(timer_txn) gen2drv,
            mailbox #(bit) done2gen
        );

            this.name = name;
            this.vif = vif;

            this.gen2drv = gen2drv;
            this.done2gen = done2gen;

            cur_g0 = 0;
            cur_g1 = 0;

            num_driven = 0;

        endfunction


        task drive_idle();

            vif.a     = 2'b11;
            vif.d_drv = 4'bz;

            vif.g0 = cur_g0;
            vif.g1 = cur_g1;

        endtask


        task reset_bus();

            // Drive reset asynchronously.
            @(negedge vif.clk);

            vif.a     = 2'b11;
            vif.d_drv = 4'bz;

            vif.g0 = 0;
            vif.g1 = 0;

            vif.rst_n = 0;

            // Keep reset asserted for multiple clock edges.
            repeat(3)
                @(negedge vif.clk);

            vif.rst_n = 1;

            cur_g0 = 0;
            cur_g1 = 0;

            drive_idle();

        endtask


        task idle_one_cycle();

            @(negedge vif.clk);

            drive_idle();

        endtask


        task drive_bus_cycle(
            bit [1:0] addr,
            bit [3:0] data
        );

            // Setup inputs at negedge.
            @(negedge vif.clk);

            vif.a     = addr;
            vif.d_drv = data;

            vif.g0 = cur_g0;
            vif.g1 = cur_g1;

            // DUT samples at posedge.
            @(posedge vif.clk);

            // Release bus after sampling.
            @(negedge vif.clk);

            drive_idle();

        endtask


        task drive_one(timer_txn t);

            if(t.do_reset)
                reset_bus();


            cur_g0 = t.g0;
            cur_g1 = t.g1;


            repeat(t.idle_cycles)
                idle_one_cycle();


            case(t.kind)

                OP_WRITE_C0:
                begin
                    drive_bus_cycle(2'b00, t.data8[3:0]);
                    drive_bus_cycle(2'b00, t.data8[7:4]);
                end


                OP_WRITE_C1:
                begin
                    drive_bus_cycle(2'b01, t.data8[3:0]);
                    drive_bus_cycle(2'b01, t.data8[7:4]);
                end


                OP_WRITE_C0_LOW:
                begin
                    drive_bus_cycle(2'b00, t.data8[3:0]);
                end


                OP_WRITE_C1_LOW:
                begin
                    drive_bus_cycle(2'b01, t.data8[3:0]);
                end


                OP_WRITE_CTRL:
                begin
                    drive_bus_cycle(
                        2'b10,
                        {t.ctrl_sel, t.ctrl_mode}
                    );
                end


                OP_WRITE_INV:
                begin
                    drive_bus_cycle(
                        2'b11,
                        t.data8[3:0]
                    );
                end


                OP_IDLE:
                begin
                    idle_one_cycle();
                end


                default:
                    ;

            endcase


            num_driven++;

            done2gen.put(1'b1);

        endtask


        task run();

            timer_txn t;

            vif.rst_n = 1'b0;

            forever begin

                gen2drv.get(t);

                drive_one(t);

            end

        endtask

    endclass : timer_driver


    // =========================================================================
    // MONITOR
    // =========================================================================

    class timer_monitor;

        virtual timer_if.MONITOR vif;

        mailbox #(bus_txn) mon2scb;
        mailbox #(bus_txn) mon2cov;

        string name;

        bit [3:0] pending_low0;
        bit [3:0] pending_low1;

        bit pending0;
        bit pending1;


        function new(
            string name,
            virtual timer_if.MONITOR vif,
            mailbox #(bus_txn) mon2scb,
            mailbox #(bus_txn) mon2cov
        );

            this.name = name;
            this.vif = vif;

            this.mon2scb = mon2scb;
            this.mon2cov = mon2cov;

            pending_low0 = 0;
            pending_low1 = 0;

            pending0 = 0;
            pending1 = 0;

        endfunction


        task run();

            bus_txn bt;

            forever begin

                @(posedge vif.clk);

                bt = new();

                // -------------------------------------------------------------
                // Sample external interface
                // -------------------------------------------------------------

                bt.a     = vif.a;
                bt.d     = vif.d;

                bt.g0    = vif.g0;
                bt.g1    = vif.g1;
                bt.rst_n = vif.rst_n;

                // -------------------------------------------------------------
                // Allow DUT NBA + combinational output to settle
                // -------------------------------------------------------------

                #1;

                bt.out0 = vif.out0;
                bt.out1 = vif.out1;

                // -------------------------------------------------------------
                // Sample internal DUT state
                // -------------------------------------------------------------

                bt.dut_counter0 = vif.dut_counter0;
                bt.dut_counter1 = vif.dut_counter1;

                bt.dut_mode0 = vif.dut_mode0;
                bt.dut_mode1 = vif.dut_mode1;

                bt.dut_ptr0 = vif.dut_ptr0;
                bt.dut_ptr1 = vif.dut_ptr1;

                bt.dut_cnt0 = vif.dut_cnt0;
                bt.dut_cnt1 = vif.dut_cnt1;

                bt.t = $time;

                // -------------------------------------------------------------
                // Reconstruct attempted 8-bit counter writes
                // -------------------------------------------------------------

                bt.write_complete = 0;
                bt.write_low_only = 0;
                bt.write_addr = bt.a;
                bt.attempted_value = '0;


                if(!bt.rst_n) begin

                    pending0 = 0;
                    pending1 = 0;

                end
                else begin

                    case(bt.a)

                        2'b00:
                        begin

                            if(!pending0) begin

                                pending_low0 = bt.d;
                                pending0 = 1;

                                bt.write_low_only = 1;

                            end
                            else begin

                                bt.attempted_value =
                                    {bt.d, pending_low0};

                                bt.write_complete = 1;

                                pending0 = 0;

                            end

                        end


                        2'b01:
                        begin

                            if(!pending1) begin

                                pending_low1 = bt.d;
                                pending1 = 1;

                                bt.write_low_only = 1;

                            end
                            else begin

                                bt.attempted_value =
                                    {bt.d, pending_low1};

                                bt.write_complete = 1;

                                pending1 = 0;

                            end

                        end


                        default:
                            ;

                    endcase

                end


                mon2scb.put(bt);
                mon2cov.put(bt);

            end

        endtask

    endclass : timer_monitor


    // =========================================================================
    // REFERENCE MODEL
    // =========================================================================

    class timer_ref_model;

        bit [7:0] counter0;
        bit [7:0] counter1;

        bit [2:0] mode0;
        bit [2:0] mode1;

        bit ptr0;
        bit ptr1;

        bit [3:0] stage_low0;
        bit [3:0] stage_low1;

        bit [7:0] cnt0;
        bit [7:0] cnt1;

        bit valid_counter0;
        bit valid_counter1;


        function new();

            reset();

        endfunction


        function void reset();

            counter0 = 8'd0;
            counter1 = 8'd0;

            mode0 = 3'd0;
            mode1 = 3'd0;

            ptr0 = 0;
            ptr1 = 0;

            stage_low0 = 0;
            stage_low1 = 0;

            cnt0 = 0;
            cnt1 = 0;

            valid_counter0 = 0;
            valid_counter1 = 0;

        endfunction


        function bit in_range(
            bit sel,
            bit [7:0] val
        );

            if(!sel)
                return (val >= C0_MIN && val <= C0_MAX);

            return (val >= C1_MIN && val <= C1_MAX);

        endfunction


        function bit mode_ok(
            bit [2:0] mode,
            bit [7:0] val
        );

            case(mode)

                // Mode 2 requires even n
                3'd2:
                    return (val[0] == 1'b0);

                // Mode 3 requires odd n
                3'd3:
                    return (val[0] == 1'b1);

                // Mode 4 requires odd n
                3'd4:
                    return (val[0] == 1'b1);

                default:
                    return 1'b1;

            endcase

        endfunction


        function bit expected_out(
            bit [2:0] mode,
            bit [7:0] n,
            bit [7:0] cnt
        );

            case(mode)

                // 1 high, n-1 low
                3'd0:
                    return (cnt == (n - 8'd1));


                // n-1 high, 1 low
                3'd1:
                    return (cnt != (n - 8'd1));


                // n/2 low, n/2 high
                3'd2:
                    return (
                        cnt < (n / 8'd2)
                    ) ? 1'b0 : 1'b1;


                // (n+1)/2 low, (n-1)/2 high
                3'd3:
                    return (
                        cnt < ((n + 8'd1) / 8'd2)
                    ) ? 1'b0 : 1'b1;


                // (n-1)/2 low, (n+1)/2 high
                3'd4:
                    return (
                        cnt < ((n - 8'd1) / 8'd2)
                    ) ? 1'b0 : 1'b1;


                default:
                    return 1'b0;

            endcase

        endfunction


        // ---------------------------------------------------------------------
        // One clock model step
        //
        // Important:
        // Counter updates use the OLD counter register value because the DUT
        // updates the counter register and cnt register in separate always
        // blocks using nonblocking assignments.
        // ---------------------------------------------------------------------

        function void step(
            bit [1:0] a,
            bit [3:0] d,
            bit g0,
            bit g1,
            bit rst_n,

            output bit exp_out0,
            output bit exp_out1
        );

            bit [7:0] old_counter0;
            bit [7:0] old_counter1;

            bit [7:0] old_cnt0;
            bit [7:0] old_cnt1;

            bit [2:0] old_mode0;
            bit [2:0] old_mode1;

            old_counter0 = counter0;
            old_counter1 = counter1;

            old_cnt0 = cnt0;
            old_cnt1 = cnt1;

            old_mode0 = mode0;
            old_mode1 = mode1;


            if(!rst_n) begin

                reset();

            end
            else begin

                // =============================================================
                // Register programming
                // =============================================================

                case(a)

                    // ---------------------------------------------------------
                    // Counter 0
                    //
                    // Specification:
                    // If C0 is counting and g0=1, write must be blocked.
                    // ---------------------------------------------------------

                    2'b00:
                    begin

                        if(!g0) begin

                            if(!ptr0) begin

                                stage_low0 = d;
                                ptr0 = 1'b1;

                            end
                            else begin

                                bit [7:0] candidate0;

                                candidate0 = {d, stage_low0};

                                if(
                                    in_range(1'b0, candidate0) &&
                                    mode_ok(mode0, candidate0)
                                ) begin

                                    counter0 = candidate0;
                                    valid_counter0 = 1'b1;

                                end

                                // Complete attempt ends the programming
                                // sequence even if value was rejected.
                                ptr0 = 1'b0;

                            end

                        end

                    end


                    // ---------------------------------------------------------
                    // Counter 1
                    //
                    // No special write prohibition was specified for C1.
                    // g1 freezes counting, but does not block programming.
                    // ---------------------------------------------------------

                    2'b01:
                    begin

                        if(!ptr1) begin

                            stage_low1 = d;
                            ptr1 = 1'b1;

                        end
                        else begin

                            bit [7:0] candidate1;

                            candidate1 = {d, stage_low1};

                            if(
                                in_range(1'b1, candidate1) &&
                                mode_ok(mode1, candidate1)
                            ) begin

                                counter1 = candidate1;
                                valid_counter1 = 1'b1;

                            end

                            ptr1 = 1'b0;

                        end

                    end


                    // ---------------------------------------------------------
                    // Control
                    // ---------------------------------------------------------

                    2'b10:
                    begin

                        if(!d[3])
                            mode0 = d[2:0];
                        else
                            mode1 = d[2:0];

                    end


                    // ---------------------------------------------------------
                    // Invalid address
                    // ---------------------------------------------------------

                    2'b11:
                    begin
                        // Strict no-op on programming state.
                    end

                endcase


                // =============================================================
                // Counter update
                //
                // Use old_counter values to match DUT nonblocking behavior.
                // =============================================================

                if(g0) begin

                    if(
                        (old_counter0 <= 8'd1) ||
                        (old_cnt0 >= (old_counter0 - 8'd1))
                    )
                        cnt0 = 8'd0;
                    else
                        cnt0 = old_cnt0 + 8'd1;

                end


                if(g1) begin

                    if(
                        (old_counter1 <= 8'd1) ||
                        (old_cnt1 >= (old_counter1 - 8'd1))
                    )
                        cnt1 = 8'd0;
                    else
                        cnt1 = old_cnt1 + 8'd1;

                end

            end


            // ================================================================
            // Expected outputs after this clock edge
            // ================================================================

            if(valid_counter0)
                exp_out0 = expected_out(
                    mode0,
                    counter0,
                    cnt0
                );
            else
                exp_out0 = 1'b0;


            if(valid_counter1)
                exp_out1 = expected_out(
                    mode1,
                    counter1,
                    cnt1
                );
            else
                exp_out1 = 1'b0;

        endfunction

    endclass : timer_ref_model


    // =========================================================================
    // SCOREBOARD
    // =========================================================================

    class timer_scoreboard;

        mailbox #(bus_txn) mon2scb;

        timer_ref_model ref_model;

        string name;

        int unsigned num_checked;

        int unsigned num_mismatch_out0;
        int unsigned num_mismatch_out1;

        int unsigned num_state_mismatch;

        int unsigned num_counter0_mismatch;
        int unsigned num_counter1_mismatch;

        int unsigned num_mode0_mismatch;
        int unsigned num_mode1_mismatch;

        int unsigned num_cnt0_mismatch;
        int unsigned num_cnt1_mismatch;


        function new(
            string name,
            mailbox #(bus_txn) mon2scb
        );

            this.name = name;
            this.mon2scb = mon2scb;

            ref_model = new();

            num_checked = 0;

            num_mismatch_out0 = 0;
            num_mismatch_out1 = 0;

            num_state_mismatch = 0;

            num_counter0_mismatch = 0;
            num_counter1_mismatch = 0;

            num_mode0_mismatch = 0;
            num_mode1_mismatch = 0;

            num_cnt0_mismatch = 0;
            num_cnt1_mismatch = 0;

        endfunction


        task run();

            bus_txn bt;

            bit exp_out0;
            bit exp_out1;

            forever begin

                mon2scb.get(bt);

                ref_model.step(
                    bt.a,
                    bt.d,
                    bt.g0,
                    bt.g1,
                    bt.rst_n,
                    exp_out0,
                    exp_out1
                );

                num_checked++;


                // -------------------------------------------------------------
                // Output checking
                // -------------------------------------------------------------

                if(
                    ref_model.valid_counter0 &&
                    (bt.out0 !== exp_out0)
                ) begin

                    num_mismatch_out0++;

                    if (0) $display(
                        "[%0t] %s OUT0 mismatch: exp=%0b act=%0b",
                        $time,
                        name,
                        exp_out0,
                        bt.out0
                    );

                end


                if(
                    ref_model.valid_counter1 &&
                    (bt.out1 !== exp_out1)
                ) begin

                    num_mismatch_out1++;

                    if (0) $display(
                        "[%0t] %s OUT1 mismatch: exp=%0b act=%0b",
                        $time,
                        name,
                        exp_out1,
                        bt.out1
                    );

                end


                // -------------------------------------------------------------
                // State checking
                // -------------------------------------------------------------

                if(bt.dut_counter0 !== ref_model.counter0) begin

                    num_counter0_mismatch++;
                    num_state_mismatch++;

                    if (0) $display(
                        "[%0t] C0 state mismatch exp=%0d act=%0d",
                        $time,
                        ref_model.counter0,
                        bt.dut_counter0
                    );

                end


                if(bt.dut_counter1 !== ref_model.counter1) begin

                    num_counter1_mismatch++;
                    num_state_mismatch++;

                    if (0) $display(
                        "[%0t] C1 state mismatch exp=%0d act=%0d",
                        $time,
                        ref_model.counter1,
                        bt.dut_counter1
                    );

                end


                if(bt.dut_mode0 !== ref_model.mode0) begin

                    num_mode0_mismatch++;
                    num_state_mismatch++;

                    if (0) $display(
                        "[%0t] MODE0 mismatch exp=%0d act=%0d",
                        $time,
                        ref_model.mode0,
                        bt.dut_mode0
                    );

                end


                if(bt.dut_mode1 !== ref_model.mode1) begin

                    num_mode1_mismatch++;
                    num_state_mismatch++;

                    if (0) $display(
                        "[%0t] MODE1 mismatch exp=%0d act=%0d",
                        $time,
                        ref_model.mode1,
                        bt.dut_mode1
                    );

                end


                if(bt.dut_cnt0 !== ref_model.cnt0) begin

                    num_cnt0_mismatch++;
                    num_state_mismatch++;

                    if (0) $display(
                        "[%0t] CNT0 mismatch exp=%0d act=%0d",
                        $time,
                        ref_model.cnt0,
                        bt.dut_cnt0
                    );

                end


                if(bt.dut_cnt1 !== ref_model.cnt1) begin

                    num_cnt1_mismatch++;
                    num_state_mismatch++;

                    if (0) $display(
                        "[%0t] CNT1 mismatch exp=%0d act=%0d",
                        $time,
                        ref_model.cnt1,
                        bt.dut_cnt1
                    );

                end

            end

        endtask


        function bit passed();

            return (
                (num_mismatch_out0 == 0) &&
                (num_mismatch_out1 == 0) &&
                (num_state_mismatch == 0)
            );

        endfunction


        function void report();

            $display("");
            $display("==============================================================");
            $display(" SCOREBOARD [%s]", name);
            $display("==============================================================");

            $display(
                "Cycles checked             : %0d",
                num_checked
            );

            $display(
                "OUT0 mismatches            : %0d",
                num_mismatch_out0
            );

            $display(
                "OUT1 mismatches            : %0d",
                num_mismatch_out1
            );

            $display(
                "C0 register mismatches     : %0d",
                num_counter0_mismatch
            );

            $display(
                "C1 register mismatches     : %0d",
                num_counter1_mismatch
            );

            $display(
                "MODE0 mismatches           : %0d",
                num_mode0_mismatch
            );

            $display(
                "MODE1 mismatches           : %0d",
                num_mode1_mismatch
            );

            $display(
                "CNT0 mismatches            : %0d",
                num_cnt0_mismatch
            );

            $display(
                "CNT1 mismatches            : %0d",
                num_cnt1_mismatch
            );

            $display(
                "Total state mismatches     : %0d",
                num_state_mismatch
            );


            if(passed())
                $display("RESULT                     : PASS");
            else
                $display("RESULT                     : FAIL");


            $display("==============================================================");
            $display("");

        endfunction

    endclass : timer_scoreboard


    // =========================================================================
    // FUNCTIONAL COVERAGE
    // =========================================================================

    class timer_coverage;

        mailbox #(bus_txn) mon2cov;

        string name;


        bit [1:0] cur_a;

        bit cur_g0;
        bit cur_g1;

        bit cur_rst_n;

        bit [2:0] cur_m0;
        bit [2:0] cur_m1;

        bit [7:0] attempted_c0;
        bit [7:0] attempted_c1;

        bit attempted_c0_valid;
        bit attempted_c1_valid;

        bit incomplete_c0;
        bit incomplete_c1;


        covergroup cg_bus;

            option.per_instance = 1;


            // ---------------------------------------------------------------
            // Address coverage
            // ---------------------------------------------------------------

            cp_addr : coverpoint cur_a {

                bins c0_write   = {2'b00};
                bins c1_write   = {2'b01};
                bins ctrl_write = {2'b10};
                bins invalid    = {2'b11};

            }


            // ---------------------------------------------------------------
            // Modes
            // ---------------------------------------------------------------

            cp_mode0 : coverpoint cur_m0 {

                bins mode0 = {3'd0};
                bins mode1 = {3'd1};
                bins mode2 = {3'd2};
                bins mode3 = {3'd3};
                bins mode4 = {3'd4};

                bins unsupported = {[3'd5:3'd7]};

            }


            cp_mode1 : coverpoint cur_m1 {

                bins mode0 = {3'd0};
                bins mode1 = {3'd1};
                bins mode2 = {3'd2};
                bins mode3 = {3'd3};
                bins mode4 = {3'd4};

                bins unsupported = {[3'd5:3'd7]};

            }


            // ---------------------------------------------------------------
            // Attempted C0 values
            // ---------------------------------------------------------------

            cp_attempt_c0 : coverpoint attempted_c0
                iff(attempted_c0_valid)
            {

                bins below_min = {[0:49]};
                bins at_min    = {50};

                bins near_min  = {51};
                bins middle    = {[52:198]};
                bins near_max  = {199};

                bins at_max    = {200};
                bins above_max = {[201:255]};

            }


            // ---------------------------------------------------------------
            // Attempted C1 values
            // ---------------------------------------------------------------

            cp_attempt_c1 : coverpoint attempted_c1
                iff(attempted_c1_valid)
            {

                bins below_min = {[0:1]};
                bins at_min    = {2};

                bins near_min  = {3};
                bins middle    = {[4:148]};
                bins near_max  = {149};

                bins at_max    = {150};
                bins above_max = {[151:255]};

            }


            // ---------------------------------------------------------------
            // Gate coverage
            // ---------------------------------------------------------------

            cp_g0 : coverpoint cur_g0 {

                bins gate_off = {0};
                bins gate_on  = {1};

            }


            cp_g1 : coverpoint cur_g1 {

                bins gate_off = {0};
                bins gate_on  = {1};

            }


            // ---------------------------------------------------------------
            // Reset
            // ---------------------------------------------------------------

            cp_rst : coverpoint cur_rst_n {

                bins reset_asserted = {0};
                bins reset_released = {1};

            }


            // ---------------------------------------------------------------
            // Incomplete writes
            // ---------------------------------------------------------------

            cp_incomplete_c0 : coverpoint incomplete_c0 {

                bins no  = {0};
                bins yes = {1};

            }


            cp_incomplete_c1 : coverpoint incomplete_c1 {

                bins no  = {0};
                bins yes = {1};

            }


            // ---------------------------------------------------------------
            // Crosses
            // ---------------------------------------------------------------

            cx_addr_g0 :
                cross cp_addr, cp_g0;


            cx_addr_g1 :
                cross cp_addr, cp_g1;


            cx_mode0_c0 :
                cross cp_mode0, cp_attempt_c0;


            cx_mode1_c1 :
                cross cp_mode1, cp_attempt_c1;


            cx_mode0_gate :
                cross cp_mode0, cp_g0;


            cx_mode1_gate :
                cross cp_mode1, cp_g1;


        endgroup


        function new(
            string name,
            mailbox #(bus_txn) mon2cov
        );

            this.name = name;
            this.mon2cov = mon2cov;

            attempted_c0_valid = 0;
            attempted_c1_valid = 0;

            incomplete_c0 = 0;
            incomplete_c1 = 0;

            cg_bus = new();

        endfunction


        task run();

            bus_txn bt;

            forever begin

                mon2cov.get(bt);


                cur_a = bt.a;

                cur_g0 = bt.g0;
                cur_g1 = bt.g1;

                cur_rst_n = bt.rst_n;

                // State after transaction
                cur_m0 = bt.dut_mode0;
                cur_m1 = bt.dut_mode1;


                attempted_c0_valid = 0;
                attempted_c1_valid = 0;

                incomplete_c0 = 0;
                incomplete_c1 = 0;


                if(bt.write_complete) begin

                    if(bt.write_addr == 2'b00) begin

                        attempted_c0 = bt.attempted_value;
                        attempted_c0_valid = 1;

                    end


                    if(bt.write_addr == 2'b01) begin

                        attempted_c1 = bt.attempted_value;
                        attempted_c1_valid = 1;

                    end

                end


                if(bt.write_low_only) begin

                    if(bt.write_addr == 2'b00)
                        incomplete_c0 = 1;

                    if(bt.write_addr == 2'b01)
                        incomplete_c1 = 1;

                end


                cg_bus.sample();

            end

        endtask


        function void report();

            $display("");
            $display("==============================================================");
            $display(" FUNCTIONAL COVERAGE [%s]", name);
            $display("==============================================================");

            $display(
                "Address coverage          : %0.2f%%",
                cg_bus.cp_addr.get_coverage()
            );

            $display(
                "Mode0 coverage            : %0.2f%%",
                cg_bus.cp_mode0.get_coverage()
            );

            $display(
                "Mode1 coverage            : %0.2f%%",
                cg_bus.cp_mode1.get_coverage()
            );

            $display(
                "C0 attempted values       : %0.2f%%",
                cg_bus.cp_attempt_c0.get_coverage()
            );

            $display(
                "C1 attempted values       : %0.2f%%",
                cg_bus.cp_attempt_c1.get_coverage()
            );

            $display(
                "G0 coverage               : %0.2f%%",
                cg_bus.cp_g0.get_coverage()
            );

            $display(
                "G1 coverage               : %0.2f%%",
                cg_bus.cp_g1.get_coverage()
            );

            $display(
                "Reset coverage            : %0.2f%%",
                cg_bus.cp_rst.get_coverage()
            );

            $display(
                "Incomplete C0 coverage   : %0.2f%%",
                cg_bus.cp_incomplete_c0.get_coverage()
            );

            $display(
                "Incomplete C1 coverage   : %0.2f%%",
                cg_bus.cp_incomplete_c1.get_coverage()
            );

            $display(
                "Address x G0             : %0.2f%%",
                cg_bus.cx_addr_g0.get_coverage()
            );

            $display(
                "Address x G1             : %0.2f%%",
                cg_bus.cx_addr_g1.get_coverage()
            );

            $display(
                "Mode0 x C0 value         : %0.2f%%",
                cg_bus.cx_mode0_c0.get_coverage()
            );

            $display(
                "Mode1 x C1 value         : %0.2f%%",
                cg_bus.cx_mode1_c1.get_coverage()
            );

            $display(
                "Mode0 x G0               : %0.2f%%",
                cg_bus.cx_mode0_gate.get_coverage()
            );

            $display(
                "Mode1 x G1               : %0.2f%%",
                cg_bus.cx_mode1_gate.get_coverage()
            );

            $display(
                "OVERALL                  : %0.2f%%",
                cg_bus.get_coverage()
            );

            $display("==============================================================");
            $display("");

        endfunction

    endclass : timer_coverage


    // =========================================================================
    // AGENT
    // =========================================================================

    class timer_agent;

        string name;

        virtual timer_if vif;

        mailbox #(timer_txn) gen2drv;
        mailbox #(bit)       done2gen;

        mailbox #(bus_txn) mon2scb;
        mailbox #(bus_txn) mon2cov;

        timer_generator gen;
        timer_driver    drv;
        timer_monitor   mon;


        function new(
            string name,
            virtual timer_if vif,
            mailbox #(bus_txn) mon2scb,
            mailbox #(bus_txn) mon2cov
        );

            this.name = name;
            this.vif = vif;

            this.mon2scb = mon2scb;
            this.mon2cov = mon2cov;

            gen2drv = new();
            done2gen = new();

            gen = new(
                {name, ".gen"},
                gen2drv,
                done2gen
            );

            drv = new(
                {name, ".drv"},
                vif.DRIVER,
                gen2drv,
                done2gen
            );

            mon = new(
                {name, ".mon"},
                vif.MONITOR,
                mon2scb,
                mon2cov
            );

        endfunction


        task run();

            fork

                drv.run();
                mon.run();

            join_none

        endtask

    endclass : timer_agent


    // =========================================================================
    // ENVIRONMENT
    // =========================================================================

    class timer_env;

        string name;

        virtual timer_if vif;

        mailbox #(bus_txn) mon2scb;
        mailbox #(bus_txn) mon2cov;

        timer_agent      agent;
        timer_scoreboard scb;
        timer_coverage   cov;


        function new(
            string name,
            virtual timer_if vif
        );

            this.name = name;
            this.vif = vif;

            mon2scb = new();
            mon2cov = new();

            agent = new(
                {name, ".agent"},
                vif,
                mon2scb,
                mon2cov
            );

            scb = new(
                {name, ".scoreboard"},
                mon2scb
            );

            cov = new(
                {name, ".coverage"},
                mon2cov
            );

        endfunction


        task run();

            agent.run();

            fork

                scb.run();
                cov.run();

            join_none

        endtask


        function void report();

            scb.report();
            cov.report();

        endfunction

    endclass : timer_env


    // =========================================================================
    // BASE TEST
    // =========================================================================

    class base_test;

        string name;

        virtual timer_if vif;

        timer_env env;


        function new(
            string name,
            virtual timer_if vif
        );

            this.name = name;
            this.vif = vif;

            env = new(
                {name, ".env"},
                vif
            );

        endfunction


        task wait_cycles(int n);

            repeat(n)
                @(posedge vif.clk);

        endtask


        virtual task body();

            env.agent.gen.gen_random(50);

        endtask


        task run();

            $display("");
            $display("==============================================================");
            $display(" START TEST: %s", name);
            $display("==============================================================");


            env.run();

            body();


            // Allow monitor/scoreboard to drain.
            wait_cycles(50);


            env.report();


            $display("==============================================================");
            $display(" END TEST: %s", name);
            $display("==============================================================");
            $display("");

        endtask

    endclass : base_test


    // =========================================================================
    // TEST 1: BASIC
    // =========================================================================

    class basic_test extends base_test;

        function new(
            string name,
            virtual timer_if vif
        );

            super.new(name, vif);

        endfunction


        virtual task body();

            env.agent.gen.do_reset_pulse();


            // C0 mode 0
            env.agent.gen.write_counter(
                0, 100,
                0, 0,
                2
            );

            env.agent.gen.write_control(
                0, 3'd0,
                0, 0,
                1
            );

            env.agent.gen.idle_cycles_only(
                300,
                1, 0
            );


            // C1 mode 1
            env.agent.gen.write_counter(
                1, 20,
                0, 0,
                2
            );

            env.agent.gen.write_control(
                1, 3'd1,
                0, 0,
                1
            );

            env.agent.gen.idle_cycles_only(
                100,
                0, 1
            );

        endtask

    endclass : basic_test


    // =========================================================================
    // TEST 2: RANGE
    // =========================================================================

    class corner_range_test extends base_test;

        function new(
            string name,
            virtual timer_if vif
        );

            super.new(name, vif);

        endfunction


        virtual task body();

            env.agent.gen.gen_corner_ranges();

            env.agent.gen.idle_cycles_only(
                200,
                1, 1
            );

        endtask

    endclass : corner_range_test


    // =========================================================================
    // TEST 3: MODE PARITY
    // =========================================================================

    class mode_parity_test extends base_test;

        function new(
            string name,
            virtual timer_if vif
        );

            super.new(name, vif);

        endfunction


        virtual task body();

            env.agent.gen.gen_mode_parity();

            env.agent.gen.idle_cycles_only(
                300,
                1, 1
            );

        endtask

    endclass : mode_parity_test


    // =========================================================================
    // TEST 4: WRITE GATING
    // =========================================================================

    class write_gating_test extends base_test;

        function new(
            string name,
            virtual timer_if vif
        );

            super.new(name, vif);

        endfunction


        virtual task body();

            env.agent.gen.gen_write_while_counting();

            env.agent.gen.idle_cycles_only(
                200,
                1, 0
            );

        endtask

    endclass : write_gating_test


    // =========================================================================
    // TEST 5: INVALID ADDRESS
    // =========================================================================

    class invalid_addr_test extends base_test;

        function new(
            string name,
            virtual timer_if vif
        );

            super.new(name, vif);

        endfunction


        virtual task body();

            env.agent.gen.gen_invalid_address();

            env.agent.gen.idle_cycles_only(
                150,
                1, 1
            );

        endtask

    endclass : invalid_addr_test


    // =========================================================================
    // TEST 6: MODE SWITCH
    // =========================================================================

    class mode_switch_test extends base_test;

        function new(
            string name,
            virtual timer_if vif
        );

            super.new(name, vif);

        endfunction


        virtual task body();

            env.agent.gen.gen_mode_switch();

        endtask

    endclass : mode_switch_test


    // =========================================================================
    // TEST 7: RESET
    // =========================================================================

    class reset_test extends base_test;

        function new(
            string name,
            virtual timer_if vif
        );

            super.new(name, vif);

        endfunction


        virtual task body();

            env.agent.gen.gen_reset_test();

            env.agent.gen.idle_cycles_only(
                50,
                0, 0
            );

        endtask

    endclass : reset_test


    // =========================================================================
    // TEST 8: RANDOM REGRESSION
    // =========================================================================

    class random_regression_test extends base_test;

        int num_txns = 500;


        function new(
            string name,
            virtual timer_if vif
        );

            super.new(name, vif);

        endfunction


        virtual task body();

            env.agent.gen.do_reset_pulse();

            env.agent.gen.gen_random(num_txns);

        endtask

    endclass : random_regression_test


    // =========================================================================
    // TEST 9: INCOMPLETE WRITE
    // =========================================================================

    class incomplete_write_test extends base_test;

        function new(
            string name,
            virtual timer_if vif
        );

            super.new(name, vif);

        endfunction


        virtual task body();

            env.agent.gen.gen_incomplete_write();

        endtask

    endclass : incomplete_write_test


    // =========================================================================
    // TEST 10: OUTPUT MODES
    // =========================================================================

    class output_mode_test extends base_test;

        function new(
            string name,
            virtual timer_if vif
        );

            super.new(name, vif);

        endfunction


        virtual task body();

            env.agent.gen.gen_output_modes();

        endtask

    endclass : output_mode_test
 

    // =========================================================================
    // TEST 11: all tests 
    // =========================================================================
    
    class all_tests_test extends base_test;

      function new(string name, virtual timer_if vif);
          super.new(name, vif);
      endfunction

      virtual task body();

          $display("==================================================");
          $display("RUNNING reset_test");
          $display("==================================================");
          env.agent.gen.do_reset_pulse();
          env.agent.gen.idle_cycles_only(10, 0, 0);

          $display("==================================================");
          $display("RUNNING corner_range_test");
          $display("==================================================");
          env.agent.gen.gen_corner_ranges();

          $display("==================================================");
          $display("RUNNING mode_parity_test");
          $display("==================================================");
          env.agent.gen.gen_mode_parity();

          $display("==================================================");
          $display("RUNNING write_gating_test");
          $display("==================================================");
          env.agent.gen.gen_write_while_counting();

          $display("==================================================");
          $display("RUNNING invalid_addr_test");
          $display("==================================================");
          env.agent.gen.gen_invalid_address();

          $display("==================================================");
          $display("RUNNING mode_switch_test");
          $display("==================================================");
          env.agent.gen.gen_mode_switch();

          $display("==================================================");
          $display("RUNNING incomplete_write_test");
          $display("==================================================");
          env.agent.gen.gen_incomplete_write();

          $display("==================================================");
          $display("RUNNING output_mode_test");
          $display("==================================================");
          env.agent.gen.gen_output_modes();

          $display("==================================================");
          $display("==================================================");
          $display("RUNNING randomized_regression_test");
          $display("==================================================");
          // The specification requests randomization as much as possible.
          // Corner-range and incomplete-write scenarios above remain directed
          // because the assignment explicitly exempts corner cases.
          env.agent.gen.gen_random(2000);

      endtask

	endclass : all_tests_test



endpackage : timer_pkg


// ============================================================================
// SVA CHECKER
// ============================================================================

module timer_sva_checker (

    input logic       clk,
    input logic       rst_n,

    input logic [1:0] a,

    input logic       g0,
    input logic       g1,

    input logic       out0,
    input logic       out1,

    input logic [7:0] counter0,
    input logic [7:0] counter1,

    input logic [2:0] mode0,
    input logic [2:0] mode1,

    input logic       ptr0,
    input logic       ptr1,

    input logic [7:0] cnt0,
    input logic [7:0] cnt1

);


    // ------------------------------------------------------------------------
    // Reset must clear programmed state.
    // ------------------------------------------------------------------------

    ap_reset_state:
    assert property (
        @(posedge clk)
        !rst_n |=> (
            counter0 == 8'd0 &&
            counter1 == 8'd0 &&
            mode0    == 3'd0 &&
            mode1    == 3'd0 &&
            ptr0     == 1'b0 &&
            ptr1     == 1'b0 &&
            cnt0     == 8'd0 &&
            cnt1     == 8'd0
        )
    )
    else
        if (0) $display("RESET assertion failed");


    // ------------------------------------------------------------------------
    // When gate is low, the counting state must freeze.
    // ------------------------------------------------------------------------

    ap_c0_freeze:
    assert property (
        @(posedge clk)
        rst_n && !g0 |=> $stable(cnt0)
    )
    else
        if (0) $display("C0 gate-freeze assertion failed");


    ap_c1_freeze:
    assert property (
        @(posedge clk)
        rst_n && !g1 |=> $stable(cnt1)
    )
    else
        if (0) $display("C1 gate-freeze assertion failed");


    // ------------------------------------------------------------------------
    // Invalid address must not modify programmed registers.
    // Counter phase may still advance because gates are independent.
    // Therefore only configuration registers are checked here.
    // ------------------------------------------------------------------------

    ap_invalid_addr:
    assert property (
        @(posedge clk)
        rst_n && (a == 2'b11) |=> (
            counter0 == $past(counter0) &&
            counter1 == $past(counter1) &&
            mode0    == $past(mode0) &&
            mode1    == $past(mode1)
        )
    )
    else
        if (0) $display("Invalid-address changed configuration state");


    // ------------------------------------------------------------------------
    // Counter0 write must be blocked while counting.
    //
    // The spec explicitly requires this behavior for C0.
    // ------------------------------------------------------------------------

    ap_c0_write_blocked:
    assert property (
        @(posedge clk)
        rst_n && (a == 2'b00) && g0
        |=> (
            counter0 == $past(counter0) &&
            ptr0     == $past(ptr0)
        )
    )
    else
        if (0) $display("C0 write was not blocked while g0=1");


    // ------------------------------------------------------------------------
    // Outputs should never be X/Z after reset is released.
    // ------------------------------------------------------------------------

    ap_outputs_known:
    assert property (
        @(posedge clk)
        rst_n |-> !$isunknown({out0, out1})
    )
    else
        if (0) $display("Timer output became X/Z");


endmodule


// ============================================================================
// TOP LEVEL
// ============================================================================

import timer_pkg::*;

module tb_top;

    localparam time CLK_PERIOD = 10ns;


    // ------------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------------

    logic clk = 1'b0;

    always #(CLK_PERIOD/2)
        clk = ~clk;


    // ------------------------------------------------------------------------
    // Interface
    // ------------------------------------------------------------------------

    timer_if vif(clk);


    // ------------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------------

    timer dut (
        .d     (vif.d),
        .a     (vif.a),
        .clk   (vif.clk),
        .g0    (vif.g0),
        .g1    (vif.g1),
        .rst_n (vif.rst_n),
        .out0  (vif.out0),
        .out1  (vif.out1)
    );


    // ------------------------------------------------------------------------
    // Verification-only connections to internal DUT state
    // ------------------------------------------------------------------------

    assign vif.dut_counter0 = dut.counter0;
    assign vif.dut_counter1 = dut.counter1;

    assign vif.dut_mode0 = dut.mode0;
    assign vif.dut_mode1 = dut.mode1;

    assign vif.dut_ptr0 = dut.ptr0;
    assign vif.dut_ptr1 = dut.ptr1;

    assign vif.dut_cnt0 = dut.cnt0;
    assign vif.dut_cnt1 = dut.cnt1;


    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------

    timer_sva_checker sva_checker (

        .clk      (clk),
        .rst_n    (vif.rst_n),

        .a        (vif.a),

        .g0       (vif.g0),
        .g1       (vif.g1),

        .out0     (vif.out0),
        .out1     (vif.out1),

        .counter0 (dut.counter0),
        .counter1 (dut.counter1),

        .mode0    (dut.mode0),
        .mode1    (dut.mode1),

        .ptr0     (dut.ptr0),
        .ptr1     (dut.ptr1),

        .cnt0     (dut.cnt0),
        .cnt1     (dut.cnt1)

    );


    // ------------------------------------------------------------------------
    // Test object
    // ------------------------------------------------------------------------

    base_test test;

    string test_name;

    int num_txns;
    int timeout_cycles;


    // ------------------------------------------------------------------------
    // Initialize
    // ------------------------------------------------------------------------

    initial begin

        vif.init_signals();

    end


    // ------------------------------------------------------------------------
    // Runtime test selection
    // ------------------------------------------------------------------------

    initial begin

        // TESTNAME
        if(!$value$plusargs(
            "TESTNAME=%s",
            test_name
        ))
            test_name = "basic_test";


        // Number of random transactions
        if(!$value$plusargs(
            "NUM_TXNS=%d",
            num_txns
        ))
            num_txns = 500;


        // Watchdog
        if(!$value$plusargs(
            "TIMEOUT=%d",
            timeout_cycles
        ))
            timeout_cycles = 200000;


        $display("");
        $display("##############################################################");
        $display("# TIMER PURE-SV VERIFICATION ENVIRONMENT");
        $display("# TESTNAME = %s", test_name);
        $display("# NUM_TXNS = %0d", num_txns);
        $display("# TIMEOUT  = %0d", timeout_cycles);
        $display("##############################################################");
        $display("");


        // --------------------------------------------------------------------
        // Select test
        // --------------------------------------------------------------------

        case(test_name)

            "basic_test":
            begin

                basic_test t;

                t = new(
                    "basic_test",
                    vif
                );

                test = t;

            end


            "corner_range_test":
            begin

                corner_range_test t;

                t = new(
                    "corner_range_test",
                    vif
                );

                test = t;

            end


            "mode_parity_test":
            begin

                mode_parity_test t;

                t = new(
                    "mode_parity_test",
                    vif
                );

                test = t;

            end


            "write_gating_test":
            begin

                write_gating_test t;

                t = new(
                    "write_gating_test",
                    vif
                );

                test = t;

            end


            "invalid_addr_test":
            begin

                invalid_addr_test t;

                t = new(
                    "invalid_addr_test",
                    vif
                );

                test = t;

            end


            "mode_switch_test":
            begin

                mode_switch_test t;

                t = new(
                    "mode_switch_test",
                    vif
                );

                test = t;

            end


            "reset_test":
            begin

                reset_test t;

                t = new(
                    "reset_test",
                    vif
                );

                test = t;

            end


            "random_regression_test":
            begin

                random_regression_test t;

                t = new(
                    "random_regression_test",
                    vif
                );

                t.num_txns = num_txns;

                test = t;

            end


            "incomplete_write_test":
            begin

                incomplete_write_test t;

                t = new(
                    "incomplete_write_test",
                    vif
                );

                test = t;

            end


            "output_mode_test":
            begin

                output_mode_test t;

                t = new(
                    "output_mode_test",
                    vif
                );

                test = t;

            end
            
            "all_tests_test": begin
                all_tests_test t;
                t = new("all_tests_test", vif);
                test = t;
            end



            default:
            begin

                basic_test t;

                $display(
                    "WARNING: Unknown TESTNAME=%s",
                    test_name
                );

                $display(
                    "Defaulting to basic_test"
                );

                t = new(
                    "basic_test",
                    vif
                );

                test = t;

            end

        endcase


        // --------------------------------------------------------------------
        // Run test
        // --------------------------------------------------------------------

        test.run();


        $display("");
        $display(
            "### TEST '%s' COMPLETE ###",
            test_name
        );
        $display("");


        $finish;

    end


    // ------------------------------------------------------------------------
    // Watchdog
    // ------------------------------------------------------------------------

    initial begin

        repeat(timeout_cycles)
            @(posedge clk);

        $display("");
        $display(
            "!!! WATCHDOG TIMEOUT after %0d cycles !!!",
            timeout_cycles
        );
        $display("");

        $finish;

    end


    // ------------------------------------------------------------------------
    // Waveform
    // ------------------------------------------------------------------------

    initial begin

        $dumpfile("timer_dv.vcd");
        $dumpvars(0, tb_top);

    end

endmodule : tb_top
