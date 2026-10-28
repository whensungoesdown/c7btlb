// test3_search_port: search port timing and match rules
//
// The search request (s_vld, s_vppn, s_odd_page, s_asid) is registered; the
// result is valid in the cycle after the request. s_found is qualified with
// the registered s_vld, the other outputs are not.
//
// Every entry in this test has its own VPPN, so at most one entry matches a
// search and the result does not depend on the priority encoder (test1).
//
//   1  result one cycle after the request, s_found low without a request
//   2  back-to-back searches, a new request every cycle
//   3  a write or INVTLB in the request cycle is visible in the result
//   4  V=0 entries match (needed for PIL/PIS/PIF and TLBSRCH)
//   5  E=0 entries do not match
//   6  odd/even page selection of all page fields
//   7  ASID compare (all 10 bits) and G
//   8  VPPN compare (all 19 bits)
//   9  outputs other than s_found on a miss (printed, not checked)

`timescale 1ns / 1ps

module top_tb;

`include "c7btlb_tb_common.vh"

   localparam [ 9:0] ASID = 10'h001;

   task entry;
      input [ 4:0] i;
      input [18:0] vppn;
      input [ 9:0] asid;
      input        g;
      begin
         tlb_write(i, vppn, asid, g, 6'd12, 1'b1,
                   mk_lo(1'b1, 1'b0, 2'b01, 2'b00, 20'h50000 | i),
                   mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h60000 | i));
      end
   endtask

   integer k, b;

   reg [18:0] req_vppn [0:7];
   reg        req_odd  [0:7];

   initial begin
      init_signals;
      do_reset;

      $display("");
      $display("TEST test3_search_port: search timing and match rules");

      // ---------------------------------------------------------------
      $display("");
      $display("1. Result one cycle after the request");
      do_reset;
      entry(5'd0, 19'h0A0A0, ASID, 1'b0);
      @(negedge clk);
      s_vld = 1'b1;  s_vppn = 19'h0A0A0;  s_odd_page = 1'b0;  s_asid = ASID;
      @(negedge clk);
      sample_result;
      s_vld = 1'b0;
      check_result(19'h0A0A0, 1'b0, ASID);
      @(negedge clk);
      sample_result;   // no request in the previous cycle
      if (t_found === 1'b0) begin
         n_pass = n_pass + 1;
      end else begin
         note_fail;
         $display("  FAIL: s_found=%b in a cycle without a search request", t_found);
      end

      // ---------------------------------------------------------------
      $display("");
      $display("2. Back-to-back searches");
      do_reset;
      entry(5'd0, 19'h00100, ASID, 1'b0);
      entry(5'd5, 19'h00200, ASID, 1'b0);
      entry(5'd10, 19'h00300, ASID, 1'b0);
      entry(5'd31, 19'h00400, ASID, 1'b0);
      req_vppn[0] = 19'h00100;  req_odd[0] = 1'b0;
      req_vppn[1] = 19'h00200;  req_odd[1] = 1'b1;
      req_vppn[2] = 19'h00999;  req_odd[2] = 1'b0;   // miss
      req_vppn[3] = 19'h00300;  req_odd[3] = 1'b0;
      req_vppn[4] = 19'h00400;  req_odd[4] = 1'b1;
      req_vppn[5] = 19'h00100;  req_odd[5] = 1'b1;
      req_vppn[6] = 19'h00100;  req_odd[6] = 1'b0;   // same page again
      req_vppn[7] = 19'h00300;  req_odd[7] = 1'b1;
      @(negedge clk);
      s_vld = 1'b1;  s_vppn = req_vppn[0];  s_odd_page = req_odd[0];  s_asid = ASID;
      for (k = 1; k <= 8; k = k + 1) begin
         @(negedge clk);
         sample_result;
         if (k < 8) begin
            s_vppn     = req_vppn[k];
            s_odd_page = req_odd[k];
         end else begin
            s_vld = 1'b0;
         end
         check_result(req_vppn[k - 1], req_odd[k - 1], ASID);
      end

      // ---------------------------------------------------------------
      $display("");
      $display("3. Write or INVTLB in the request cycle");
      do_reset;
      entry(5'd0, 19'h01000, ASID, 1'b0);
      // change the PPN of the entry being searched
      @(negedge clk);
      s_vld = 1'b1;  s_vppn = 19'h01000;  s_odd_page = 1'b0;  s_asid = ASID;
      drive_write(5'd0, 19'h01000, ASID, 1'b0, 6'd12, 1'b1,
                  mk_lo(1'b1, 1'b1, 2'b11, 2'b11, 20'h0FACE),
                  mk_lo(1'b1, 1'b1, 2'b11, 2'b11, 20'h0FACF));
      @(negedge clk);
      we = 1'b0;
      model_write(5'd0, 19'h01000, ASID, 1'b0, 6'd12, 1'b1,
                  mk_lo(1'b1, 1'b1, 2'b11, 2'b11, 20'h0FACE),
                  mk_lo(1'b1, 1'b1, 2'b11, 2'b11, 20'h0FACF));
      sample_result;
      s_vld = 1'b0;
      check_result(19'h01000, 1'b0, ASID);
      // add the entry that a missing search is looking for
      @(negedge clk);
      s_vld = 1'b1;  s_vppn = 19'h02000;  s_odd_page = 1'b1;  s_asid = ASID;
      drive_write(5'd7, 19'h02000, ASID, 1'b0, 6'd12, 1'b1,
                  mk_lo(1'b1, 1'b0, 2'b01, 2'b00, 20'h02020),
                  mk_lo(1'b1, 1'b0, 2'b01, 2'b00, 20'h02021));
      @(negedge clk);
      we = 1'b0;
      model_write(5'd7, 19'h02000, ASID, 1'b0, 6'd12, 1'b1,
                  mk_lo(1'b1, 1'b0, 2'b01, 2'b00, 20'h02020),
                  mk_lo(1'b1, 1'b0, 2'b01, 2'b00, 20'h02021));
      sample_result;
      s_vld = 1'b0;
      check_result(19'h02000, 1'b1, ASID);
      // invalidate everything in the request cycle
      @(negedge clk);
      s_vld = 1'b1;  s_vppn = 19'h01000;  s_odd_page = 1'b0;  s_asid = ASID;
      drive_inv(5'd0, 10'h0, 19'h0);
      @(negedge clk);
      inv_en = 1'b0;
      model_inv(5'd0, 10'h0, 19'h0);
      sample_result;
      s_vld = 1'b0;
      check_result(19'h01000, 1'b0, ASID);

      // ---------------------------------------------------------------
      $display("");
      $display("4. V=0 entries match");
      do_reset;
      tlb_write(5'd4, 19'h03000, ASID, 1'b0, 6'd12, 1'b1,
                mk_lo(1'b0, 1'b0, 2'b01, 2'b00, 20'h03030),
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h03031));
      search_and_check(19'h03000, 1'b0, ASID);   // found, v=0
      search_and_check(19'h03000, 1'b1, ASID);   // found, v=1

      // ---------------------------------------------------------------
      $display("");
      $display("5. E=0 entries do not match");
      do_reset;
      tlb_write(5'd6, 19'h04000, ASID, 1'b1, 6'd12, 1'b0,
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h04040),
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h04041));
      search_and_check(19'h04000, 1'b0, ASID);

      // ---------------------------------------------------------------
      $display("");
      $display("6. Odd/even page selection");
      do_reset;
      tlb_write(5'd9, 19'h05000, ASID, 1'b0, 6'd12, 1'b1,
                mk_lo(1'b1, 1'b0, 2'b01, 2'b10, 20'h11111),
                mk_lo(1'b0, 1'b1, 2'b11, 2'b01, 20'h22222));
      search_and_check(19'h05000, 1'b0, ASID);
      search_and_check(19'h05000, 1'b1, ASID);

      // ---------------------------------------------------------------
      $display("");
      $display("7. ASID and G");
      do_reset;
      entry(5'd1, 19'h06000, 10'h200, 1'b0);
      entry(5'd2, 19'h06100, 10'h005, 1'b1);
      search_and_check(19'h06000, 1'b0, 10'h200);   // hit
      search_and_check(19'h06000, 1'b0, 10'h000);   // ASID differs in bit 9
      search_and_check(19'h06000, 1'b0, 10'h201);   // ASID differs in bit 0
      search_and_check(19'h06100, 1'b0, 10'h3ff);   // global, any ASID
      search_and_check(19'h06100, 1'b0, 10'h000);

      // ---------------------------------------------------------------
      $display("");
      $display("8. VPPN compare, every bit");
      do_reset;
      entry(5'd17, 19'h5A5A5, ASID, 1'b0);
      search_and_check(19'h5A5A5, 1'b0, ASID);
      for (b = 0; b < 19; b = b + 1)
         search_and_check(19'h5A5A5 ^ (19'h1 << b), 1'b0, ASID);

      // ---------------------------------------------------------------
      $display("");
      $display("9. Outputs on a miss");
      do_reset;
      entry(5'd0, 19'h07000, ASID, 1'b0);
      tlb_search(19'h07777, 1'b0, ASID);
      check_result(19'h07777, 1'b0, ASID);
      $display("  NOTE: on a miss s_index=%0d s_v=%b s_pfn=%05h; only s_found is qualified, callers must gate the other outputs with s_found",
               t_index, t_v, t_pfn);

      report;
      $finish;
   end

endmodule
