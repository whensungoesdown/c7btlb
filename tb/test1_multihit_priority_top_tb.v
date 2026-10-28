// test1_multihit_priority: several entries match the same search
//
// When more than one entry matches, the lowest index must be used. This is
// what the kernel relies on when it searches with TLBSRCH and then
// overwrites the entry it found.
//
// c7btlb builds a 32-bit priority encoder from 4-bit encoders (enc4). enc4
// encodes the index as idx[0] = in[1] | in[3], idx[1] = in[2] | in[3],
// which is only correct when at most one input is set. With two or more
// matches in the lowest group of four, it returns the OR of their indices:
// matches at 1 and 2 give index 3, an entry that may not match at all. The
// lookup then returns that entry's PPN, so a load or fetch goes to an
// unrelated physical page, and TLBSRCH reports the wrong index.
//
//   part A  every combination of matches inside one group of four
//   part B  every pair of matching entries (same group and different groups)
//   part C  the case seen in Linux: a V=0 entry left by a TLB refill and the
//           valid entry written after the page fault, both for the same page
//
// Expected on c7btlb.v with the enc4 above: FAIL in parts A, B (same group
// only) and C. Single matches and matches in different groups pass.

`timescale 1ns / 1ps

module top_tb;

`include "c7btlb_tb_common.vh"

   localparam [18:0] TARGET = 19'h12345;
   localparam [ 9:0] ASID   = 10'h001;

   // entry i: TARGET if sel, otherwise a VPPN of its own; PPNs identify i
   task put;
      input [4:0] i;
      input       sel;
      begin
         tlb_write(i, sel ? TARGET : (19'h40000 | i), ASID, 1'b0, 6'd12, 1'b1,
                   mk_lo(1'b1, 1'b0, 2'b01, 2'b00, 20'hA0000 | i),
                   mk_lo(1'b1, 1'b0, 2'b01, 2'b00, 20'hB0000 | i));
      end
   endtask

   integer g, m, b, i, j;
   integer fail_before;
   integer a_cases, a_fail;
   integer same_cases, same_fail, diff_cases, diff_fail;
   reg [3:0] mask;

   initial begin
      init_signals;
      do_reset;

      $display("");
      $display("TEST test1_multihit_priority: several matching entries, lowest index must win");

      // ---------------------------------------------------------------
      // Part A
      // ---------------------------------------------------------------
      $display("");
      $display("Part A: every set of matches inside one group of four (8 groups x 15 sets)");
      a_cases = 0;
      a_fail  = 0;
      for (g = 0; g < 8; g = g + 1) begin
         for (m = 1; m < 16; m = m + 1) begin
            mask = m;
            do_reset;
            for (b = 0; b < 4; b = b + 1)
               put(g * 4 + b, mask[b]);

            fail_before = n_fail;
            search_and_check(TARGET, 1'b0, ASID);
            a_cases = a_cases + 1;
            if (n_fail != fail_before)
               a_fail = a_fail + 1;

            if (g == 0)
               $display("    group 0, matching entries %b: index %0d, expected %0d%s",
                        mask, t_index, e_index,
                        (t_index === e_index) ? "" : "   <-- wrong entry");
         end
      end
      $display("  part A: %0d of %0d sets give a wrong index", a_fail, a_cases);

      // ---------------------------------------------------------------
      // Part B
      // ---------------------------------------------------------------
      $display("");
      $display("Part B: every pair of matching entries");
      same_cases = 0;
      same_fail  = 0;
      diff_cases = 0;
      diff_fail  = 0;
      for (i = 0; i < 32; i = i + 1) begin
         for (j = i + 1; j < 32; j = j + 1) begin
            do_reset;
            put(i, 1'b1);
            put(j, 1'b1);

            fail_before = n_fail;
            search_and_check(TARGET, 1'b0, ASID);
            if ((i / 4) == (j / 4)) begin
               same_cases = same_cases + 1;
               if (n_fail != fail_before)
                  same_fail = same_fail + 1;
            end else begin
               diff_cases = diff_cases + 1;
               if (n_fail != fail_before)
                  diff_fail = diff_fail + 1;
            end
         end
      end
      $display("  part B: pairs in the same group of four: %0d of %0d wrong", same_fail, same_cases);
      $display("  part B: pairs in different groups:       %0d of %0d wrong", diff_fail, diff_cases);

      // ---------------------------------------------------------------
      // Part C
      // ---------------------------------------------------------------
      $display("");
      $display("Part C: V=0 entry from the refill and the valid entry for the same page");
      do_reset;
      // entry 1: written by the TLB refill handler, page not present yet
      tlb_write(5'd1, TARGET, ASID, 1'b0, 6'd12, 1'b1,
                mk_lo(1'b0, 1'b0, 2'b01, 2'b00, 20'h00000),
                mk_lo(1'b0, 1'b0, 2'b01, 2'b00, 20'h00000));
      // entry 2: written after the page fault, page now present
      tlb_write(5'd2, TARGET, ASID, 1'b0, 6'd12, 1'b1,
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h0AAAA),
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h0AAAB));
      // entry 3: another page of the same process
      tlb_write(5'd3, 19'h00777, ASID, 1'b0, 6'd12, 1'b1,
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h0BBBB),
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h0BBBC));

      search_and_check(TARGET, 1'b0, ASID);
      $display("    search for the page: index %0d, v=%0d, pfn=%05h (expected index 1, v=0)",
               t_index, t_v, t_pfn);
      if (t_found && (t_index == 5'd3))
         $display("    index 3 belongs to another page: a load from this page reads physical page %05h, and TLBWR after TLBSRCH overwrites the other page's entry",
                  t_pfn);

      report;
      $finish;
   end

endmodule
