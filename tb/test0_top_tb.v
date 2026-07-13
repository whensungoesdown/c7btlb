// Testbench for c7btlb TLB module
// Verilog-2001 compliant
// Each test case is implemented as a separate task
// Final summary prints PASS/FAIL for each test

`timescale 1ns / 1ps

module top_tb;

   // Clock and reset
   reg clk;
   reg resetn;

   // DUT signals
   reg        s_vld;
   reg [18:0] s_vppn;
   reg        s_odd_page;
   reg [ 9:0] s_asid;
   wire       s_found;
   wire [4:0] s_index;
   wire [19:0] s_pfn;
   wire       s_d;
   wire       s_v;
   wire [1:0] s_mat;
   wire [1:0] s_plv;

   reg        we;
   reg [4:0]  w_index;
   reg [18:0] w_vppn;
   reg [9:0]  w_asid;
   reg        w_g;
   reg        w_v0;
   reg        w_d0;
   reg [1:0]  w_mat0;
   reg [1:0]  w_plv0;
   reg [19:0] w_ppn0;
   reg        w_v1;
   reg        w_d1;
   reg [1:0]  w_mat1;
   reg [1:0]  w_plv1;
   reg [19:0] w_ppn1;

   reg [4:0]  r_index;
   wire [18:0] r_vppn;
   wire [9:0]  r_asid;
   wire        r_v0;
   wire        r_d0;
   wire [1:0]  r_mat0;
   wire [1:0]  r_plv0;
   wire [19:0] r_ppn0;
   wire        r_v1;
   wire        r_d1;
   wire [1:0]  r_mat1;
   wire [1:0]  r_plv1;
   wire [19:0] r_ppn1;

   reg        inv_en;
   reg [4:0]  inv_op;
   reg [9:0]  inv_asid;
   reg [18:0] inv_vppn;

   // Instantiate DUT
   c7btlb dut (
      .clk(clk),
      .resetn(resetn),
      .s_vld(s_vld),
      .s_vppn(s_vppn),
      .s_odd_page(s_odd_page),
      .s_asid(s_asid),
      .s_found(s_found),
      .s_index(s_index),
      .s_pfn(s_pfn),
      .s_d(s_d),
      .s_v(s_v),
      .s_mat(s_mat),
      .s_plv(s_plv),
      .we(we),
      .w_index(w_index),
      .w_vppn(w_vppn),
      .w_asid(w_asid),
      .w_g(w_g),
      .w_v0(w_v0),
      .w_d0(w_d0),
      .w_mat0(w_mat0),
      .w_plv0(w_plv0),
      .w_ppn0(w_ppn0),
      .w_v1(w_v1),
      .w_d1(w_d1),
      .w_mat1(w_mat1),
      .w_plv1(w_plv1),
      .w_ppn1(w_ppn1),
      .r_index(r_index),
      .r_vppn(r_vppn),
      .r_asid(r_asid),
      .r_v0(r_v0),
      .r_d0(r_d0),
      .r_mat0(r_mat0),
      .r_plv0(r_plv0),
      .r_ppn0(r_ppn0),
      .r_v1(r_v1),
      .r_d1(r_d1),
      .r_mat1(r_mat1),
      .r_plv1(r_plv1),
      .r_ppn1(r_ppn1),
      .inv_en(inv_en),
      .inv_op(inv_op),
      .inv_asid(inv_asid),
      .inv_vppn(inv_vppn)
   );

   // Clock generation
   always #5 clk = ~clk;   // 10 ns period

   // Test control
   integer pass_count, fail_count;
   integer test_id;

   // Helper task: reset the DUT
   task do_reset;
      begin
         resetn = 1'b0;
         repeat (2) @(posedge clk);
         resetn = 1'b1;
         repeat (2) @(posedge clk);
      end
   endtask

   // Helper task: write a TLB entry
   task write_entry;
      input [4:0]  index;
      input [18:0] vppn;
      input [9:0]  asid;
      input        g;
      input        v0, d0;
      input [1:0]  mat0, plv0;
      input [19:0] ppn0;
      input        v1, d1;
      input [1:0]  mat1, plv1;
      input [19:0] ppn1;
      begin
         @(posedge clk);
         we = 1'b1;
         w_index = index;
         w_vppn  = vppn;
         w_asid  = asid;
         w_g     = g;
         w_v0    = v0;
         w_d0    = d0;
         w_mat0  = mat0;
         w_plv0  = plv0;
         w_ppn0  = ppn0;
         w_v1    = v1;
         w_d1    = d1;
         w_mat1  = mat1;
         w_plv1  = plv1;
         w_ppn1  = ppn1;
         @(posedge clk);
         we = 1'b0;
      end
   endtask

   // Helper task: issue a search and return result
   // The search result is available one cycle after s_vld is asserted
   // Outputs are connected to reg variables in the caller.
   task search;
      input [18:0] vppn;
      input        odd_page;
      input [9:0]  asid;
      output       found;
      output [4:0] idx;
      output [19:0] pfn;
      output       d, v;
      output [1:0] mat, plv;
      begin
         @(posedge clk);
         s_vld = 1'b1;
         s_vppn = vppn;
         s_odd_page = odd_page;
         s_asid = asid;
         @(posedge clk);
         s_vld = 1'b0;
         //@(posedge clk);
	 //#1;   // 给组合逻辑 1 ns 传播时间（仅在仿真中有效）
	 //#0;   // 强制 delta 延迟   NOT WORKING
	 @(negedge clk);                   // 等待下降沿，确保信号稳定
         // Sample results after one cycle
         found = s_found;
         idx   = s_index;
         pfn   = s_pfn;
         d     = s_d;
         v     = s_v;
         mat   = s_mat;
         plv   = s_plv;
      end
   endtask


   // Test 1: Reset and search should miss
   task test_reset;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         $display("\nTEST %0d: Reset - search after reset should miss", test_id);
         do_reset();
         search(18'h0, 1'b0, 10'h0, found, idx, pfn, d, v, mat, plv);
         if (found === 1'b0)
            $display("  PASS: s_found = 0 as expected");
         else
            $display("  FAIL: s_found = 1, expected 0");
         if (found === 1'b0) pass_count = pass_count + 1;
         else fail_count = fail_count + 1;
         test_id = test_id + 1;
      end
   endtask

   // Test 2: Write and search hit
   task test_write_and_search;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         $display("\nTEST %0d: Write entry 0 and search hit", test_id);
         do_reset();
         write_entry(5'd0, 18'h12345, 10'h01, 1'b0,
                     1'b1, 1'b1, 2'b01, 2'b10, 20'hABCDE,
                     1'b0, 1'b0, 2'b00, 2'b00, 20'h0);
         search(18'h12345, 1'b0, 10'h01, found, idx, pfn, d, v, mat, plv);
         if (found && idx == 5'd0 && pfn == 20'hABCDE && v == 1'b1 && d == 1'b1 && mat == 2'b01 && plv == 2'b10)
            $display("  PASS: found at index 0 with correct fields");
         else begin
            $display("  FAIL: expected found=1, idx=0, pfn=ABCDE, v=1, d=1, mat=01, plv=10");
            $display("        got found=%b, idx=%d, pfn=%h, v=%b, d=%b, mat=%b, plv=%b",
                     found, idx, pfn, v, d, mat, plv);
         end
         if (found && idx == 5'd0 && pfn == 20'hABCDE) pass_count = pass_count + 1;
         else fail_count = fail_count + 1;
         test_id = test_id + 1;
      end
   endtask

   // Test 3: Search miss (vppn mismatch)
   task test_search_miss;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         $display("\nTEST %0d: Search miss - vppn not present", test_id);
         do_reset();
         write_entry(5'd0, 18'h12345, 10'h01, 1'b0,
                     1'b1, 1'b1, 2'b01, 2'b10, 20'hABCDE,
                     1'b0, 1'b0, 2'b00, 2'b00, 20'h0);
         search(18'h54321, 1'b0, 10'h01, found, idx, pfn, d, v, mat, plv);
         if (found === 1'b0)
            $display("  PASS: miss as expected");
         else
            $display("  FAIL: expected miss, got hit");
         if (found === 1'b0) pass_count = pass_count + 1;
         else fail_count = fail_count + 1;
         test_id = test_id + 1;
      end
   endtask

   // Test 4: ASID mismatch (non-global)
   task test_asid_mismatch;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         $display("\nTEST %0d: ASID mismatch (non-global)", test_id);
         do_reset();
         write_entry(5'd0, 18'h12345, 10'h01, 1'b0,
                     1'b1, 1'b1, 2'b01, 2'b10, 20'hABCDE,
                     1'b0, 1'b0, 2'b00, 2'b00, 20'h0);
         search(18'h12345, 1'b0, 10'h02, found, idx, pfn, d, v, mat, plv);
         if (found === 1'b0)
            $display("  PASS: miss due to ASID mismatch");
         else
            $display("  FAIL: expected miss, got hit");
         if (found === 1'b0) pass_count = pass_count + 1;
         else fail_count = fail_count + 1;
         test_id = test_id + 1;
      end
   endtask

   // Test 5: Global bit allows any ASID
   task test_global;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         $display("\nTEST %0d: Global bit - different ASID should hit", test_id);
         do_reset();
         write_entry(5'd0, 18'h12345, 10'h01, 1'b1,
                     1'b1, 1'b1, 2'b01, 2'b10, 20'hABCDE,
                     1'b0, 1'b0, 2'b00, 2'b00, 20'h0);
         search(18'h12345, 1'b0, 10'h02, found, idx, pfn, d, v, mat, plv);
         if (found && idx == 5'd0 && pfn == 20'hABCDE)
            $display("  PASS: global entry hit with different ASID");
         else begin
            $display("  FAIL: expected hit, got found=%b, idx=%d, pfn=%h", found, idx, pfn);
         end
         if (found && idx == 5'd0) pass_count = pass_count + 1;
         else fail_count = fail_count + 1;
         test_id = test_id + 1;
      end
   endtask

   // Test 6: Priority (lowest index wins)
   task test_priority;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         $display("\nTEST %0d: Priority - lowest index among matches", test_id);
         do_reset();
         write_entry(5'd2, 18'h55555, 10'h0A, 1'b0,
                     1'b1, 1'b1, 2'b01, 2'b10, 20'hAAAAA,
                     1'b0, 1'b0, 2'b00, 2'b00, 20'h0);
         write_entry(5'd5, 18'h55555, 10'h0A, 1'b0,
                     1'b1, 1'b1, 2'b11, 2'b01, 20'hBBBBB,
                     1'b0, 1'b0, 2'b00, 2'b00, 20'h0);
         search(18'h55555, 1'b0, 10'h0A, found, idx, pfn, d, v, mat, plv);
         if (found && idx == 5'd2 && pfn == 20'hAAAAA)
            $display("  PASS: lowest index (2) selected, pfn=AAAAA");
         else begin
            $display("  FAIL: expected idx=2, pfn=AAAAA; got idx=%d, pfn=%h", idx, pfn);
         end
         if (found && idx == 5'd2) pass_count = pass_count + 1;
         else fail_count = fail_count + 1;
         test_id = test_id + 1;
      end
   endtask

   // Test 7: odd_page selection
   task test_odd_page;
      reg ok;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         ok = 1'b1;
         $display("\nTEST %0d: odd_page selection (page 0 vs page 1)", test_id);
         do_reset();
         write_entry(5'd0, 18'h77777, 10'h03, 1'b0,
                     1'b1, 1'b0, 2'b00, 2'b00, 20'h11111,
                     1'b1, 1'b1, 2'b11, 2'b11, 20'h22222);
         // Page 0
         search(18'h77777, 1'b0, 10'h03, found, idx, pfn, d, v, mat, plv);
         if (!(found && pfn == 20'h11111 && v == 1'b1 && d == 1'b0)) ok = 1'b0;
         // Page 1
         search(18'h77777, 1'b1, 10'h03, found, idx, pfn, d, v, mat, plv);
         if (!(found && pfn == 20'h22222 && v == 1'b1 && d == 1'b1)) ok = 1'b0;
         if (ok) begin
            $display("  PASS: odd_page selection works correctly");
            pass_count = pass_count + 1;
         end else begin
            $display("  FAIL: odd_page selection failed");
            fail_count = fail_count + 1;
         end
         test_id = test_id + 1;
      end
   endtask

   // Test 8: Read port
   task test_read_port;
      begin
         $display("\nTEST %0d: Read port", test_id);
         do_reset();
         write_entry(5'd3, 18'h99999, 10'h0F, 1'b1,
                     1'b1, 1'b1, 2'b10, 2'b01, 20'h33333,
                     1'b0, 1'b0, 2'b00, 2'b00, 20'h0);
         @(posedge clk);
         r_index = 5'd3;
         @(negedge clk);
         @(posedge clk);
         if (r_vppn == 18'h99999 && r_asid == 10'h0F && r_v0 == 1'b1 && r_d0 == 1'b1 &&
             r_mat0 == 2'b10 && r_plv0 == 2'b01 && r_ppn0 == 20'h33333 &&
             r_v1 == 1'b0 && r_d1 == 1'b0 && r_mat1 == 2'b00 && r_plv1 == 2'b00 && r_ppn1 == 20'h0)
            $display("  PASS: read port matches written data");
         else begin
            $display("  FAIL: read port mismatch");
            $display("    expected: vppn=99999, asid=0F, v0=1, d0=1, mat0=10, plv0=01, ppn0=33333");
            $display("    got: vppn=%h, asid=%h, v0=%b, d0=%b, mat0=%b, plv0=%b, ppn0=%h",
                     r_vppn, r_asid, r_v0, r_d0, r_mat0, r_plv0, r_ppn0);
         end
         if (r_vppn == 18'h99999 && r_asid == 10'h0F) pass_count = pass_count + 1;
         else fail_count = fail_count + 1;
         test_id = test_id + 1;
      end
   endtask

   // Test 9: Invalidate all
   task test_inv_all;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         $display("\nTEST %0d: Invalidate all entries", test_id);
         do_reset();
         write_entry(5'd0, 18'h11111, 10'h01, 1'b0, 1'b1, 1'b1, 2'b01, 2'b10, 20'hAAAAA, 1'b0,1'b0,2'b00,2'b00,20'h0);
         write_entry(5'd1, 18'h22222, 10'h02, 1'b0, 1'b1, 1'b1, 2'b01, 2'b10, 20'hBBBBB, 1'b0,1'b0,2'b00,2'b00,20'h0);
         @(posedge clk);
         inv_en = 1'b1;
         inv_op = 5'b00000;
         @(posedge clk);
         inv_en = 1'b0;
         search(18'h11111, 1'b0, 10'h01, found, idx, pfn, d, v, mat, plv);
         if (found === 1'b0)
            $display("  PASS: all invalidated, search miss");
         else
            $display("  FAIL: entry still found after global invalidate");
         if (found === 1'b0) pass_count = pass_count + 1;
         else fail_count = fail_count + 1;
         test_id = test_id + 1;
      end
   endtask

   // Test 10: Invalidate by ASID
   task test_inv_asid;
      reg ok;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         ok = 1'b1;
         $display("\nTEST %0d: Invalidate by ASID", test_id);
         do_reset();
         write_entry(5'd0, 18'h11111, 10'h01, 1'b0, 1'b1, 1'b1, 2'b01, 2'b10, 20'hAAAAA, 1'b0,1'b0,2'b00,2'b00,20'h0);
         write_entry(5'd1, 18'h22222, 10'h02, 1'b0, 1'b1, 1'b1, 2'b01, 2'b10, 20'hBBBBB, 1'b0,1'b0,2'b00,2'b00,20'h0);
         @(posedge clk);
         inv_en = 1'b1;
         inv_op = 5'b00001;
         inv_asid = 10'h01;
         @(posedge clk);
         inv_en = 1'b0;
         search(18'h11111, 1'b0, 10'h01, found, idx, pfn, d, v, mat, plv);
         if (found !== 1'b0) ok = 1'b0;
         search(18'h22222, 1'b0, 10'h02, found, idx, pfn, d, v, mat, plv);
         if (!(found && idx == 5'd1 && pfn == 20'hBBBBB)) ok = 1'b0;
         if (ok) begin
            $display("  PASS: ASID-based invalidation works");
            pass_count = pass_count + 1;
         end else begin
            $display("  FAIL: ASID-based invalidation failed");
            fail_count = fail_count + 1;
         end
         test_id = test_id + 1;
      end
   endtask

   // Test 11: Invalidate by VPN
   task test_inv_vpn;
      reg ok;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         ok = 1'b1;
         $display("\nTEST %0d: Invalidate by VPN", test_id);
         do_reset();
         write_entry(5'd0, 18'hAAAAA, 10'h01, 1'b0, 1'b1, 1'b1, 2'b01, 2'b10, 20'h11111, 1'b0,1'b0,2'b00,2'b00,20'h0);
         write_entry(5'd1, 18'hBBBBB, 10'h02, 1'b0, 1'b1, 1'b1, 2'b01, 2'b10, 20'h22222, 1'b0,1'b0,2'b00,2'b00,20'h0);
         @(posedge clk);
         inv_en = 1'b1;
         inv_op = 5'b00010;
         inv_vppn = 18'hAAAAA;
         @(posedge clk);
         inv_en = 1'b0;
         search(18'hAAAAA, 1'b0, 10'h01, found, idx, pfn, d, v, mat, plv);
         if (found !== 1'b0) ok = 1'b0;
         search(18'hBBBBB, 1'b0, 10'h02, found, idx, pfn, d, v, mat, plv);
         if (!(found && idx == 5'd1 && pfn == 20'h22222)) ok = 1'b0;
         if (ok) begin
            $display("  PASS: VPN-based invalidation works");
            pass_count = pass_count + 1;
         end else begin
            $display("  FAIL: VPN-based invalidation failed");
            fail_count = fail_count + 1;
         end
         test_id = test_id + 1;
      end
   endtask

   // Test 12: Reset after operations (clears valid bits)
   task test_reset_after_inv;
      reg found;
      reg [4:0] idx;
      reg [19:0] pfn;
      reg d, v;
      reg [1:0] mat, plv;
      begin
         $display("\nTEST %0d: Reset after operations - clears valid bits", test_id);
         do_reset();
         write_entry(5'd0, 18'h12345, 10'h01, 1'b0, 1'b1, 1'b1, 2'b01, 2'b10, 20'hABCDE, 1'b0,1'b0,2'b00,2'b00,20'h0);
         do_reset();
         search(18'h12345, 1'b0, 10'h01, found, idx, pfn, d, v, mat, plv);
         if (found === 1'b0)
            $display("  PASS: reset cleared entries");
         else
            $display("  FAIL: reset did not clear entries");
         if (found === 1'b0) pass_count = pass_count + 1;
         else fail_count = fail_count + 1;
         test_id = test_id + 1;
      end
   endtask

   // Main test flow
   initial begin
      // Initialize signals
      clk = 1'b0;
      resetn = 1'b1;
      s_vld = 1'b0;
      s_vppn = 18'h0;
      s_odd_page = 1'b0;
      s_asid = 10'h0;
      we = 1'b0;
      w_index = 5'h0;
      w_vppn = 18'h0;
      w_asid = 10'h0;
      w_g = 1'b0;
      w_v0 = 1'b0;
      w_d0 = 1'b0;
      w_mat0 = 2'b00;
      w_plv0 = 2'b00;
      w_ppn0 = 20'h0;
      w_v1 = 1'b0;
      w_d1 = 1'b0;
      w_mat1 = 2'b00;
      w_plv1 = 2'b00;
      w_ppn1 = 20'h0;
      r_index = 5'h0;
      inv_en = 1'b0;
      inv_op = 5'h0;
      inv_asid = 10'h0;
      inv_vppn = 18'h0;

      pass_count = 0;
      fail_count = 0;
      test_id = 1;

      // Wait for reset to be released
      @(posedge clk);
      @(posedge clk);

      // Run all tests
      test_reset();
      test_write_and_search();
      test_search_miss();
      test_asid_mismatch();
      test_global();
      test_priority();
      test_odd_page();
      test_read_port();
      test_inv_all();
      test_inv_asid();
      test_inv_vpn();
      test_reset_after_inv();

      // Summary
      $display("\n=============================================");
      if (0 == fail_count)
      	 $display("TEST SUMMARY: ALL PASS");
      else
      	 $display("TEST SUMMARY: %0d PASS, %0d FAIL", pass_count, fail_count);
      $display("=============================================");
      $finish;
   end

endmodule
