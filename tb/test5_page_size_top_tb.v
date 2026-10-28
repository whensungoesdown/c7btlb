// test5_page_size: TLB entries with a 4 MB page size (PS=22)
//
// LA32R allows TLB entries with PS=12 (4 KB pages) and PS=22 (4 MB pages).
// An entry maps a pair of pages, so a PS=22 entry covers 8 MB: it must match
// on VA[31:23] only (s_vppn[18:10]), and the even/odd page is selected by
// VA[22] (s_vppn[9]), not by VA[12].
//
// c7btlb stores PS (it is read back by TLBRD) but matches every entry as a
// pair of 4 KB pages: all 19 VPPN bits are compared and the page is selected
// by s_odd_page. This test reports that as a failure. It is a missing
// feature, not a logic error: Linux on SoC2 uses 4 KB pages only, so it does
// not affect the current kernel.
//
// The caller passes s_vppn = VA[31:13] and s_odd_page = VA[12], as c7bifu
// and c7blsu do; it cannot know the page size before the lookup.

`timescale 1ns / 1ps

module top_tb;

`include "c7btlb_tb_common.vh"

   localparam [ 9:0] ASID = 10'h001;
   localparam [19:0] PPN0 = 20'h02000;   // even 4 MB page
   localparam [19:0] PPN1 = 20'h02400;   // odd 4 MB page

   // search VA and check the expected result
   task check_va;
      input [31:0] va;
      input        exp_found;
      input [ 4:0] exp_index;
      input [19:0] exp_pfn;
      reg ok;
      begin
         tlb_search(va[31:13], va[12], ASID);
         ok = (t_found === exp_found);
         if (exp_found)
            ok = ok && (t_index === exp_index) && (t_pfn === exp_pfn);
         if (ok) begin
            n_pass = n_pass + 1;
            $display("    va %08h: found=%0d index=%0d pfn=%05h", va, t_found, t_index, t_pfn);
         end else begin
            note_fail;
            if (exp_found)
               $display("  FAIL: va %08h: got found=%0d index=%0d pfn=%05h, expected index %0d pfn=%05h",
                        va, t_found, t_index, t_pfn, exp_index, exp_pfn);
            else
               $display("  FAIL: va %08h: got found=%0d, expected a miss", va, t_found);
         end
      end
   endtask

   initial begin
      init_signals;
      do_reset;

      $display("");
      $display("TEST test5_page_size: PS=22 (4 MB) entries");

      // entry 0: VA 0x0080_0000 - 0x00ff_ffff, PS=22
      tlb_write(5'd0, 19'h00400, ASID, 1'b0, 6'd22, 1'b1,
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, PPN0),
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, PPN1));
      // entry 1: an ordinary 4 KB pair, VA 0x0300_0000 - 0x0300_1fff
      tlb_write(5'd1, 19'h01800, ASID, 1'b0, 6'd12, 1'b1,
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h03000),
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h03001));

      $display("");
      $display("4 KB entry (reference)");
      check_va(32'h0300_0000, 1'b1, 5'd1, 20'h03000);
      check_va(32'h0300_1000, 1'b1, 5'd1, 20'h03001);
      check_va(32'h0300_2000, 1'b0, 5'd0, 20'h0);

      $display("");
      $display("Read back PS");
      check_read_all;

      $display("");
      $display("4 MB entry, even page (VA[22] = 0)");
      check_va(32'h0080_0000, 1'b1, 5'd0, PPN0);
      check_va(32'h0080_1000, 1'b1, 5'd0, PPN0);   // VA[12] = 1
      check_va(32'h0092_3000, 1'b1, 5'd0, PPN0);
      check_va(32'h00bf_f000, 1'b1, 5'd0, PPN0);

      $display("");
      $display("4 MB entry, odd page (VA[22] = 1)");
      check_va(32'h00c0_0000, 1'b1, 5'd0, PPN1);
      check_va(32'h00c0_5000, 1'b1, 5'd0, PPN1);
      check_va(32'h00ff_f000, 1'b1, 5'd0, PPN1);

      $display("");
      $display("Outside the 4 MB entry");
      check_va(32'h007f_f000, 1'b0, 5'd0, 20'h0);
      check_va(32'h0100_0000, 1'b0, 5'd0, 20'h0);

      report;
      $finish;
   end

endmodule
