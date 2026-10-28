// test4_random: random writes, INVTLB and searches against the model
//
// Every search result is compared with the reference model; every 500
// operations all entries are also compared through the read port.
//
//   phase A  writes never create two valid entries that can match the same
//            search, so every search has at most one matching entry
//   phase B  the same, but duplicate entries are allowed, as they appear
//            when software writes a second entry for a page that is
//            already in the TLB
//
// Mismatches are reported separately for searches with several matches in
// the lowest group of four entries (the enc4 priority encoder bug, see
// test1) and for all other searches. With a correct TLB both phases have no
// mismatches. With the current enc4, phase A passes and phase B fails only
// in searches with several matches in one group of four.
//
// The seed can be changed with +seed=<n> (default 1).

`timescale 1ns / 1ps

module top_tb;

`include "c7btlb_tb_common.vh"

   localparam N_OPS = 5000;   // operations per phase

   integer seed;

   integer ph_search, ph_multi, ph_fail, ph_fail_grp, ph_fail_other;
   integer a_search, a_multi, a_fail, a_fail_grp, a_fail_other;

   // could an entry (vp, as, g) at index idx match the same search as a
   // valid entry somewhere else?
   function conflict_with;
      input [ 4:0] idx;
      input [18:0] vp;
      input [ 9:0] as;
      input        g;
      integer j;
      begin
         conflict_with = 1'b0;
         for (j = 0; j < 32; j = j + 1)
            if ((j != idx) && m_e[j] && (m_vppn[j] == vp) &&
                (g || m_g[j] || (m_asid[j] == as)))
               conflict_with = 1'b1;
      end
   endfunction

   reg [18:0] r_vp;
   reg [ 9:0] r_as;
   reg [25:0] r_lo0;
   reg [25:0] r_lo1;

   // VPPN from a small pool, so that searches hit and entries collide
   task pick_vppn;
      begin
         if (({$random(seed)} % 20) == 0)
            r_vp = $random(seed);
         else
            r_vp = 19'h10000 + ({$random(seed)} % 24) * 19'h00011;
      end
   endtask

   task pick_asid;
      begin
         r_as = 10'h001 + ({$random(seed)} % 3);
      end
   endtask

   task pick_lo;
      begin
         r_lo0 = $random(seed);
         r_lo1 = $random(seed);
      end
   endtask

   task run_phase;
      input allow_dup;
      integer k, r, idx, tries, op;
      reg g, e, odd;
      begin
         ph_search     = 0;
         ph_multi      = 0;
         ph_fail       = 0;
         ph_fail_grp   = 0;
         ph_fail_other = 0;

         do_reset;
         for (k = 0; k < N_OPS; k = k + 1) begin
            r = {$random(seed)} % 100;

            if (r < 35) begin
               // write
               idx = {$random(seed)} % 32;
               g   = (({$random(seed)} % 8) == 0);
               e   = (({$random(seed)} % 16) != 0);
               pick_asid;
               pick_vppn;
               pick_lo;
               tries = 0;
               while (!allow_dup && e && conflict_with(idx, r_vp, r_as, g) && (tries < 20)) begin
                  pick_vppn;
                  tries = tries + 1;
               end
               if (allow_dup || !e || !conflict_with(idx, r_vp, r_as, g))
                  tlb_write(idx, r_vp, r_as, g, 6'd12, e, r_lo0, r_lo1);

            end else if (r < 45) begin
               // INVTLB; op 0/1 (all) only rarely, so the TLB stays filled
               op = {$random(seed)} % 9;
               if ((op <= 1) && (({$random(seed)} % 8) != 0))
                  op = 4;
               if (op == 8)
                  op = 7 + ({$random(seed)} % 25);   // reserved ops 7..31
               pick_asid;
               pick_vppn;
               tlb_inv(op, r_as, r_vp);

            end else begin
               // search
               pick_asid;
               pick_vppn;
               odd = $random(seed);
               search_and_check(r_vp, odd, r_as);
               ph_search = ph_search + 1;
               if (e_nmatch > 1)
                  ph_multi = ph_multi + 1;
               if (!last_ok) begin
                  ph_fail = ph_fail + 1;
                  if (e_grp_multi)
                     ph_fail_grp = ph_fail_grp + 1;
                  else
                     ph_fail_other = ph_fail_other + 1;
               end
            end

            if ((k % 500) == 499)
               check_read_all;
         end
      end
   endtask

   initial begin
      init_signals;
      if (!$value$plusargs("seed=%d", seed))
         seed = 1;

      $display("");
      $display("TEST test4_random: %0d random operations per phase, seed %0d", N_OPS, seed);

      $display("");
      $display("Phase A: no duplicate entries");
      run_phase(1'b0);
      a_search     = ph_search;
      a_multi      = ph_multi;
      a_fail       = ph_fail;
      a_fail_grp   = ph_fail_grp;
      a_fail_other = ph_fail_other;

      $display("");
      $display("Phase B: duplicate entries allowed");
      run_phase(1'b1);

      $display("");
      $display("  phase A: %0d searches, %0d with several matching entries, %0d mismatches",
               a_search, a_multi, a_fail);
      $display("  phase B: %0d searches, %0d with several matching entries, %0d mismatches",
               ph_search, ph_multi, ph_fail);
      $display("    with several matches in the lowest group of four: %0d", ph_fail_grp);
      $display("    other searches:                                    %0d", ph_fail_other);
      if ((a_fail_other + ph_fail_other) != 0)
         $display("  mismatches outside the multi-hit case: a second problem besides enc4");

      report;
      $finish;
   end

endmodule
