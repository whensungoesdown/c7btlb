// test2_invtlb: INVTLB, reset and writes with E=0
//
// The TLB is filled with 32 entries covering every combination of
// 4 VPPNs, 4 ASIDs and G=0/1. After each operation every entry is read back
// through the read port (TLBRD) and compared with the reference model: E
// must be cleared exactly for the entries the operation selects, and the
// fields of the other entries must not change.
//
// The read port is used instead of searches, so the result does not depend
// on the search priority encoder (see test1).
//
//   INVTLB op 0..6 with several ASID / VA arguments
//   reserved ops 7, 8, 15, 31 must not change anything
//   reset clears E of every entry
//   a write with E=0 (TLBWR with TLBIDX.NE=1) makes the entry invalid

`timescale 1ns / 1ps

module top_tb;

`include "c7btlb_tb_common.vh"

   function [18:0] vp;
      input [1:0] k;
      begin
         case (k)
            2'd0: vp = 19'h11111;
            2'd1: vp = 19'h22222;
            2'd2: vp = 19'h33333;
            default: vp = 19'h44444;
         endcase
      end
   endfunction

   function [9:0] as;
      input [1:0] k;
      begin
         case (k)
            2'd0: as = 10'h001;
            2'd1: as = 10'h002;
            2'd2: as = 10'h003;
            default: as = 10'h3ff;
         endcase
      end
   endfunction

   // entry i: VPPN from i[1:0], ASID from i[3:2], G = i[4]
   task populate;
      integer i;
      begin
         for (i = 0; i < 32; i = i + 1)
            tlb_write(i, vp(i % 4), as((i / 4) % 4), (i / 16) % 2, 6'd12, 1'b1,
                      mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'hC0000 | i),
                      mk_lo(1'b1, 1'b0, 2'b10, 2'b11, 20'hD0000 | i));
      end
   endtask

   task count_valid;
      output [31:0] n;
      integer i;
      begin
         n = 0;
         for (i = 0; i < 32; i = i + 1)
            if (m_e[i])
               n = n + 1;
      end
   endtask

   task run_inv;
      input [ 4:0] op;
      input [ 9:0] asid;
      input [18:0] vppn;
      integer n;
      integer fail_before;
      begin
         do_reset;
         populate;
         tlb_inv(op, asid, vppn);
         count_valid(n);
         fail_before = n_fail;
         check_read_all;
         $display("    INVTLB op %0d asid=%03h vppn=%05h: %0d entries left valid%s",
                  op, asid, vppn, n, (n_fail == fail_before) ? "" : "   <-- mismatch");
      end
   endtask

   integer op, k, n;

   // ASID / VA arguments for ops 4, 5 and 6
   reg [ 9:0] arg_asid [0:4];
   reg [18:0] arg_vppn [0:4];

   initial begin
      init_signals;
      do_reset;

      arg_asid[0] = 10'h001;  arg_vppn[0] = 19'h11111;
      arg_asid[1] = 10'h002;  arg_vppn[1] = 19'h22222;
      arg_asid[2] = 10'h3ff;  arg_vppn[2] = 19'h44444;
      arg_asid[3] = 10'h007;  arg_vppn[3] = 19'h33333;   // ASID not in the TLB
      arg_asid[4] = 10'h001;  arg_vppn[4] = 19'h55555;   // VA not in the TLB

      $display("");
      $display("TEST test2_invtlb: INVTLB ops, reset and E=0 writes, checked through the read port");

      $display("");
      $display("Fill all 32 entries and read them back");
      do_reset;
      populate;
      check_read_all;

      $display("");
      $display("INVTLB op 0..3 (no arguments)");
      for (op = 0; op < 4; op = op + 1)
         run_inv(op, 10'h001, 19'h11111);

      $display("");
      $display("INVTLB op 4..6 (ASID and/or VA)");
      for (op = 4; op < 7; op = op + 1)
         for (k = 0; k < 5; k = k + 1)
            run_inv(op, arg_asid[k], arg_vppn[k]);

      $display("");
      $display("Reserved INVTLB ops must not change the TLB");
      run_inv(5'd7,  10'h001, 19'h11111);
      run_inv(5'd8,  10'h001, 19'h11111);
      run_inv(5'd15, 10'h001, 19'h11111);
      run_inv(5'd31, 10'h001, 19'h11111);

      $display("");
      $display("Two INVTLB in consecutive cycles");
      do_reset;
      populate;
      @(negedge clk);
      drive_inv(5'd4, 10'h001, 19'h0);
      @(negedge clk);
      model_inv(5'd4, 10'h001, 19'h0);
      drive_inv(5'd6, 10'h002, 19'h33333);
      @(negedge clk);
      inv_en = 1'b0;
      model_inv(5'd6, 10'h002, 19'h33333);
      check_read_all;

      $display("");
      $display("Reset clears E of every entry");
      do_reset;
      populate;
      do_reset;
      check_read_all;
      for (k = 0; k < 4; k = k + 1)
         search_and_check(vp(k), 1'b0, 10'h001);   // all must miss

      $display("");
      $display("Write with E=0 makes the entry invalid");
      do_reset;
      populate;
      tlb_write(5'd5, 19'h66666, 10'h001, 1'b0, 6'd12, 1'b0,
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h12345),
                mk_lo(1'b1, 1'b1, 2'b01, 2'b00, 20'h12346));
      check_read_all;
      search_and_check(19'h66666, 1'b0, 10'h001);       // must miss

      report;
      $finish;
   end

endmodule
