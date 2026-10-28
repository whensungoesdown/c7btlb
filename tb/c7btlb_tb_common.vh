// Common testbench body for the c7btlb tests: DUT, clock, reference model
// and tasks. Include it inside "module top_tb;".
//
// All DUT inputs are driven on the falling clock edge and all outputs are
// sampled on the falling edge, so there is no race with the rising-edge
// logic of the DUT.
//
// The reference model follows the LA32R TLB rules, written independently of
// the RTL:
//   - an entry matches when E=1, VPPN is equal and (G=1 or ASID is equal);
//     V does not take part in the match
//   - when several entries match, the one with the lowest index is used
//   - reset clears E of every entry
//   - INVTLB op 0/1 all, 2 G=1, 3 G=0, 4 G=0 and ASID, 5 G=0 and ASID and
//     VA, 6 (G=1 or ASID) and VA, other ops do nothing
//
// Low half of an entry, as used by the tasks and the model (26 bits):
//   {v, d, mat[1:0], plv[1:0], ppn[19:0]}

   // ------------------------------------------------------------------
   // DUT
   // ------------------------------------------------------------------
   reg         clk;
   reg         resetn;

   reg         s_vld;
   reg  [18:0] s_vppn;
   reg         s_odd_page;
   reg  [ 9:0] s_asid;
   wire        s_found;
   wire [ 4:0] s_index;
   wire [19:0] s_pfn;
   wire        s_d;
   wire        s_v;
   wire [ 1:0] s_mat;
   wire [ 1:0] s_plv;

   reg         we;
   reg  [ 4:0] w_index;
   reg  [18:0] w_vppn;
   reg  [ 9:0] w_asid;
   reg         w_g;
   reg  [ 5:0] w_ps;
   reg         w_e;
   reg         w_v0;
   reg         w_d0;
   reg  [ 1:0] w_mat0;
   reg  [ 1:0] w_plv0;
   reg  [19:0] w_ppn0;
   reg         w_v1;
   reg         w_d1;
   reg  [ 1:0] w_mat1;
   reg  [ 1:0] w_plv1;
   reg  [19:0] w_ppn1;

   reg  [ 4:0] r_index;
   wire [18:0] r_vppn;
   wire [ 9:0] r_asid;
   wire        r_g;
   wire [ 5:0] r_ps;
   wire        r_e;
   wire        r_v0;
   wire        r_d0;
   wire [ 1:0] r_mat0;
   wire [ 1:0] r_plv0;
   wire [19:0] r_ppn0;
   wire        r_v1;
   wire        r_d1;
   wire [ 1:0] r_mat1;
   wire [ 1:0] r_plv1;
   wire [19:0] r_ppn1;

   reg         inv_en;
   reg  [ 4:0] inv_op;
   reg  [ 9:0] inv_asid;
   reg  [18:0] inv_vppn;

   c7btlb dut (
      .clk         (clk),
      .resetn      (resetn),

      .s_vld       (s_vld),
      .s_vppn      (s_vppn),
      .s_odd_page  (s_odd_page),
      .s_asid      (s_asid),
      .s_found     (s_found),
      .s_index     (s_index),
      .s_pfn       (s_pfn),
      .s_d         (s_d),
      .s_v         (s_v),
      .s_mat       (s_mat),
      .s_plv       (s_plv),

      .we          (we),
      .w_index     (w_index),
      .w_vppn      (w_vppn),
      .w_asid      (w_asid),
      .w_g         (w_g),
      .w_ps        (w_ps),
      .w_e         (w_e),
      .w_v0        (w_v0),
      .w_d0        (w_d0),
      .w_mat0      (w_mat0),
      .w_plv0      (w_plv0),
      .w_ppn0      (w_ppn0),
      .w_v1        (w_v1),
      .w_d1        (w_d1),
      .w_mat1      (w_mat1),
      .w_plv1      (w_plv1),
      .w_ppn1      (w_ppn1),

      .r_index     (r_index),
      .r_vppn      (r_vppn),
      .r_asid      (r_asid),
      .r_g         (r_g),
      .r_ps        (r_ps),
      .r_e         (r_e),
      .r_v0        (r_v0),
      .r_d0        (r_d0),
      .r_mat0      (r_mat0),
      .r_plv0      (r_plv0),
      .r_ppn0      (r_ppn0),
      .r_v1        (r_v1),
      .r_d1        (r_d1),
      .r_mat1      (r_mat1),
      .r_plv1      (r_plv1),
      .r_ppn1      (r_ppn1),

      .inv_en      (inv_en),
      .inv_op      (inv_op),
      .inv_asid    (inv_asid),
      .inv_vppn    (inv_vppn)
   );

   initial clk = 1'b0;
   always #5 clk = ~clk;   // 10 ns period

   // ------------------------------------------------------------------
   // Reference model
   // ------------------------------------------------------------------
   reg         m_e    [0:31];
   reg  [18:0] m_vppn [0:31];
   reg  [ 9:0] m_asid [0:31];
   reg         m_g    [0:31];
   reg  [ 5:0] m_ps   [0:31];
   reg  [25:0] m_lo0  [0:31];
   reg  [25:0] m_lo1  [0:31];

   // last sampled search result
   reg         t_found;
   reg  [ 4:0] t_index;
   reg  [19:0] t_pfn;
   reg         t_v;
   reg         t_d;
   reg  [ 1:0] t_mat;
   reg  [ 1:0] t_plv;

   // expected search result, from model_search
   reg         e_found;
   reg  [ 4:0] e_index;
   reg  [25:0] e_lo;
   integer     e_nmatch;      // number of matching entries
   reg         e_grp_multi;   // several matches in the lowest group of 4

   reg         last_ok;       // result of the last check_result

   integer     n_pass;
   integer     n_fail;
   integer     n_print;

   localparam  MAX_PRINT = 20;   // failure messages printed per test

   function [25:0] mk_lo;
      input        v;
      input        d;
      input [ 1:0] mat;
      input [ 1:0] plv;
      input [19:0] ppn;
      begin
         mk_lo = {v, d, mat, plv, ppn};
      end
   endfunction

   // ------------------------------------------------------------------
   // Tasks
   // ------------------------------------------------------------------

   task init_signals;
      integer i;
      begin
         resetn     = 1'b0;
         s_vld      = 1'b0;
         s_vppn     = 19'h0;
         s_odd_page = 1'b0;
         s_asid     = 10'h0;
         we         = 1'b0;
         w_index    = 5'h0;
         w_vppn     = 19'h0;
         w_asid     = 10'h0;
         w_g        = 1'b0;
         w_ps       = 6'd12;
         w_e        = 1'b1;
         {w_v0, w_d0, w_mat0, w_plv0, w_ppn0} = 26'h0;
         {w_v1, w_d1, w_mat1, w_plv1, w_ppn1} = 26'h0;
         r_index    = 5'h0;
         inv_en     = 1'b0;
         inv_op     = 5'h0;
         inv_asid   = 10'h0;
         inv_vppn   = 19'h0;

         n_pass  = 0;
         n_fail  = 0;
         n_print = 0;

         for (i = 0; i < 32; i = i + 1) begin
            m_e[i]    = 1'b0;
            m_vppn[i] = 19'h0;
            m_asid[i] = 10'h0;
            m_g[i]    = 1'b0;
            m_ps[i]   = 6'd12;
            m_lo0[i]  = 26'h0;
            m_lo1[i]  = 26'h0;
         end
      end
   endtask

   // reset clears E only; the other fields keep their value
   task do_reset;
      integer i;
      begin
         @(negedge clk);
         resetn = 1'b0;
         @(negedge clk);
         @(negedge clk);
         resetn = 1'b1;
         @(negedge clk);
         for (i = 0; i < 32; i = i + 1)
            m_e[i] = 1'b0;
      end
   endtask

   task model_write;
      input [ 4:0] index;
      input [18:0] vppn;
      input [ 9:0] asid;
      input        g;
      input [ 5:0] ps;
      input        e;
      input [25:0] lo0;
      input [25:0] lo1;
      begin
         m_e[index]    = e;
         m_vppn[index] = vppn;
         m_asid[index] = asid;
         m_g[index]    = g;
         m_ps[index]   = ps;
         m_lo0[index]  = lo0;
         m_lo1[index]  = lo1;
      end
   endtask

   // set the write port; the write happens at the next rising edge
   task drive_write;
      input [ 4:0] index;
      input [18:0] vppn;
      input [ 9:0] asid;
      input        g;
      input [ 5:0] ps;
      input        e;
      input [25:0] lo0;
      input [25:0] lo1;
      begin
         we      = 1'b1;
         w_index = index;
         w_vppn  = vppn;
         w_asid  = asid;
         w_g     = g;
         w_ps    = ps;
         w_e     = e;
         {w_v0, w_d0, w_mat0, w_plv0, w_ppn0} = lo0;
         {w_v1, w_d1, w_mat1, w_plv1, w_ppn1} = lo1;
      end
   endtask

   task tlb_write;
      input [ 4:0] index;
      input [18:0] vppn;
      input [ 9:0] asid;
      input        g;
      input [ 5:0] ps;
      input        e;
      input [25:0] lo0;
      input [25:0] lo1;
      begin
         @(negedge clk);
         drive_write(index, vppn, asid, g, ps, e, lo0, lo1);
         @(negedge clk);
         we = 1'b0;
         model_write(index, vppn, asid, g, ps, e, lo0, lo1);
      end
   endtask

   task model_inv;
      input [ 4:0] op;
      input [ 9:0] asid;
      input [18:0] vppn;
      integer i;
      reg hit;
      begin
         for (i = 0; i < 32; i = i + 1) begin
            case (op)
               5'd0, 5'd1: hit = 1'b1;
               5'd2:       hit = m_g[i];
               5'd3:       hit = !m_g[i];
               5'd4:       hit = !m_g[i] && (m_asid[i] == asid);
               5'd5:       hit = !m_g[i] && (m_asid[i] == asid) && (m_vppn[i] == vppn);
               5'd6:       hit = (m_g[i] || (m_asid[i] == asid)) && (m_vppn[i] == vppn);
               default:    hit = 1'b0;
            endcase
            if (hit)
               m_e[i] = 1'b0;
         end
      end
   endtask

   task drive_inv;
      input [ 4:0] op;
      input [ 9:0] asid;
      input [18:0] vppn;
      begin
         inv_en   = 1'b1;
         inv_op   = op;
         inv_asid = asid;
         inv_vppn = vppn;
      end
   endtask

   task tlb_inv;
      input [ 4:0] op;
      input [ 9:0] asid;
      input [18:0] vppn;
      begin
         @(negedge clk);
         drive_inv(op, asid, vppn);
         @(negedge clk);
         inv_en = 1'b0;
         model_inv(op, asid, vppn);
      end
   endtask

   task sample_result;
      begin
         t_found = s_found;
         t_index = s_index;
         t_pfn   = s_pfn;
         t_v     = s_v;
         t_d     = s_d;
         t_mat   = s_mat;
         t_plv   = s_plv;
      end
   endtask

   // one search: request in one cycle, result one cycle later
   task tlb_search;
      input [18:0] vppn;
      input        odd;
      input [ 9:0] asid;
      begin
         @(negedge clk);
         s_vld      = 1'b1;
         s_vppn     = vppn;
         s_odd_page = odd;
         s_asid     = asid;
         @(negedge clk);
         sample_result;
         s_vld = 1'b0;
      end
   endtask

   task model_search;
      input [18:0] vppn;
      input        odd;
      input [ 9:0] asid;
      integer i;
      begin
         e_found     = 1'b0;
         e_index     = 5'd0;
         e_lo        = 26'h0;
         e_nmatch    = 0;
         e_grp_multi = 1'b0;
         for (i = 0; i < 32; i = i + 1) begin
            if (m_e[i] && (m_vppn[i] == vppn) && (m_g[i] || (m_asid[i] == asid))) begin
               if (!e_found) begin
                  e_found = 1'b1;
                  e_index = i;
                  e_lo    = odd ? m_lo1[i] : m_lo0[i];
               end else if ((i / 4) == (e_index / 4)) begin
                  e_grp_multi = 1'b1;
               end
               e_nmatch = e_nmatch + 1;
            end
         end
      end
   endtask

   task note_fail;
      begin
         n_fail = n_fail + 1;
         n_print = n_print + 1;
      end
   endtask

   // compare the last sampled result (t_*) with the model
   task check_result;
      input [18:0] vppn;
      input        odd;
      input [ 9:0] asid;
      begin
         model_search(vppn, odd, asid);
         last_ok = (t_found === e_found);
         if (e_found)
            last_ok = last_ok && (t_index === e_index) &&
                      ({t_v, t_d, t_mat, t_plv, t_pfn} === e_lo);

         if (last_ok) begin
            n_pass = n_pass + 1;
         end else begin
            note_fail;
            if (n_print <= MAX_PRINT) begin
               if (e_found)
                  $display("  FAIL: search vppn=%05h odd=%0d asid=%03h: got found=%0d index=%0d lo=%07h, expected index %0d lo=%07h (%0d matching entries)",
                           vppn, odd, asid, t_found, t_index,
                           {t_v, t_d, t_mat, t_plv, t_pfn}, e_index, e_lo, e_nmatch);
               else
                  $display("  FAIL: search vppn=%05h odd=%0d asid=%03h: got found=%0d index=%0d, expected a miss",
                           vppn, odd, asid, t_found, t_index);
            end
         end
      end
   endtask

   task search_and_check;
      input [18:0] vppn;
      input        odd;
      input [ 9:0] asid;
      begin
         tlb_search(vppn, odd, asid);
         check_result(vppn, odd, asid);
      end
   endtask

   // compare the read port with the model for every entry
   task check_read_all;
      integer i;
      reg ok;
      begin
         @(negedge clk);
         for (i = 0; i < 32; i = i + 1) begin
            r_index = i;
            #1;
            ok = (r_e === m_e[i]);
            if (m_e[i])
               ok = ok && (r_vppn === m_vppn[i]) && (r_asid === m_asid[i]) &&
                    (r_g === m_g[i]) && (r_ps === m_ps[i]) &&
                    ({r_v0, r_d0, r_mat0, r_plv0, r_ppn0} === m_lo0[i]) &&
                    ({r_v1, r_d1, r_mat1, r_plv1, r_ppn1} === m_lo1[i]);
            if (ok) begin
               n_pass = n_pass + 1;
            end else begin
               note_fail;
               if (n_print <= MAX_PRINT)
                  $display("  FAIL: read entry %0d: e=%0d vppn=%05h asid=%03h g=%0d ps=%0d, expected e=%0d vppn=%05h asid=%03h g=%0d ps=%0d",
                           i, r_e, r_vppn, r_asid, r_g, r_ps,
                           m_e[i], m_vppn[i], m_asid[i], m_g[i], m_ps[i]);
            end
         end
      end
   endtask

   task report;
      begin
         $display("");
         $display("=============================================");
         if (n_fail == 0)
            $display("TEST SUMMARY: ALL PASS (%0d checks)", n_pass);
         else
            $display("TEST SUMMARY: %0d PASS, %0d FAIL", n_pass, n_fail);
         $display("=============================================");
      end
   endtask
