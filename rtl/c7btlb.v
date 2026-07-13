// TLB ENTRY 32
module c7btlb
(
   input               clk,
   input               resetn,

   // search port
   input               s_vld,  // ifu/lsu requires address translation
   input  [18:0]       s_vppn, // vppn aka vpn2, two vpns
   input               s_odd_page, // Select page 1 if high
   input  [ 9:0]       s_asid,
   output              s_found,
   output [ 4:0]       s_index,
   output [19:0]       s_pfn,
   //output [ 2:0]       s_c,
   output              s_d,
   output              s_v,
   output [ 1:0]       s_mat,
   output [ 1:0]       s_plv,

   // write port
   input               we,
   input  [ 4:0]       w_index,
   input  [18:0]       w_vppn,
   input  [ 9:0]       w_asid,
   input               w_g,
   //input  [ 5:0]       w_ps,
   //input               w_e,
   input               w_v0,
   input               w_d0,
   input  [ 1:0]       w_mat0,
   input  [ 1:0]       w_plv0,
   input  [19:0]       w_ppn0,
   input               w_v1,
   input               w_d1,
   input  [ 1:0]       w_mat1,
   input  [ 1:0]       w_plv1,
   input  [19:0]       w_ppn1,

   // read port
   input  [ 4:0]       r_index,
   output [18:0]       r_vppn,
   output [ 9:0]       r_asid,
   //output              r_g,
   //output [ 5:0]       r_ps,
   //output              r_e,
   output              r_v0,
   output              r_d0,
   output [ 1:0]       r_mat0,
   output [ 1:0]       r_plv0,
   output [19:0]       r_ppn0,
   output              r_v1,
   output              r_d1,
   output [ 1:0]       r_mat1,
   output [ 1:0]       r_plv1,
   output [19:0]       r_ppn1,

   // invalid port
   input               inv_en,
   input  [ 4:0]       inv_op,
   input  [ 9:0]       inv_asid,
   //input  [18:0]       inv_vpn
   input  [18:0]       inv_vppn
);

   // TLB entries
   // TLBHI
   //reg        tlb_e        [31:0];
   reg [ 9:0] tlb_asid     [31:0];
   reg        tlb_g        [31:0];
   //reg [ 5:0] tlb_ps       [31:0];
   reg [18:0] tlb_vppn     [31:0];

   // TLBLO0
   reg        tlb_v0       [31:0];
   reg        tlb_d0       [31:0];
   reg [ 1:0] tlb_plv0     [31:0];
   reg [ 1:0] tlb_mat0     [31:0];
   reg [19:0] tlb_ppn0     [31:0];

   // TLBLO1
   reg        tlb_v1       [31:0];
   reg        tlb_d1       [31:0];
   reg [ 1:0] tlb_plv1     [31:0];
   reg [ 1:0] tlb_mat1     [31:0];
   reg [19:0] tlb_ppn1     [31:0];


   reg s_vld_g;
   reg [18:0] s_vppn_g;
   reg s_odd_page_g;
   reg [9:0] s_asid_g;


   integer j, k;

   // ---------- Reset ----------
   always @(posedge clk or negedge resetn) begin
      if (!resetn) begin
         for (j = 0; j < 32; j = j + 1) begin
            tlb_v0[j] <= 1'b0;
            tlb_v1[j] <= 1'b0;
         end
         s_vld_g <= 1'b0;
      end
   end


   // ---------- Register the search inputs ----------

   always @(posedge clk) begin
      s_vld_g <= s_vld;
   end

   always @(posedge clk) begin
      if (s_vld) begin
         s_vppn_g <= s_vppn;
         s_odd_page_g <= s_odd_page;
         s_asid_g <= s_asid;
      end
   end
	   
   // ---------- Match signal generation (using registered signals) ----------
   wire [31:0] match;   // match[i] = 1 if entry i matches the registered search request

   genvar i;
   generate
      for (i = 0; i < 32; i = i + 1) begin : match_gen
         //assign match[i] = (s_vppn_g == tlb_vppn[i]) && ((s_asid_g == tlb_asid[i][9:0]) || tlb_g[i]);
         assign match[i] = (s_vppn_g == tlb_vppn[i]) &&
                  ((s_asid_g == tlb_asid[i][9:0]) || tlb_g[i]) &&
                  (s_odd_page_g ? tlb_v1[i] : tlb_v0[i]);
      end
   endgenerate  
  

   // uty: test , need encoder? find leading 1?

//   // ---------- Search logic (using registered odd_page) ----------
//   // Find the first matching entry (lowest index)
//   reg [4:0]  match_index;
//   reg        match_found;
//   reg found_tmp;      // local flag to stop further assignments
//   integer idx;
//
//   always @(*) begin
//      found_tmp = 1'b0;
//      match_index = 5'b0;
//      for (idx = 0; idx < 32; idx = idx + 1) begin
//         if (!found_tmp && match[idx]) begin
//            found_tmp = 1'b1;
//            match_index = idx[4:0];
//         end
//      end
//      match_found = found_tmp;
//   end

   // ---------- Priority encoder for match ----------
   // enc32 finds the lowest index where match[i] is 1.
   wire [4:0] match_index;
   enc32 u_enc32 (.in(match), .out(match_index));

   // match_found is true if any match bit is set
   wire match_found = |match;


   // Select page 0 or page 1 based on registered s_odd_page_g
   wire sel_v   = s_odd_page_g ? tlb_v1[match_index] : tlb_v0[match_index];
   wire sel_d   = s_odd_page_g ? tlb_d1[match_index] : tlb_d0[match_index];
   wire [1:0] sel_mat = s_odd_page_g ? tlb_mat1[match_index] : tlb_mat0[match_index];
   wire [1:0] sel_plv = s_odd_page_g ? tlb_plv1[match_index] : tlb_plv0[match_index];
   wire [19:0] sel_ppn= s_odd_page_g ? tlb_ppn1[match_index] : tlb_ppn0[match_index];

   // Output assignments – use registered s_vld_g to qualify found
   assign s_found = match_found && s_vld_g;
   assign s_index = match_index;
   assign s_pfn   = sel_ppn;
   assign s_d     = sel_d;
   assign s_v     = sel_v;
   assign s_mat   = sel_mat;
   assign s_plv   = sel_plv;


   // ---------- Write port ----------
   always @(posedge clk) begin
      if (we) begin
         tlb_vppn[w_index] <= w_vppn;
         tlb_asid[w_index] <= w_asid;
         //tlb_ps  [w_index] <= w_ps;
         tlb_g   [w_index] <= w_g;
         tlb_v0  [w_index] <= w_v0;
         tlb_d0  [w_index] <= w_d0;
         tlb_mat0[w_index] <= w_mat0;
         tlb_plv0[w_index] <= w_plv0;
         tlb_ppn0[w_index] <= w_ppn0;
         tlb_v1  [w_index] <= w_v1;
         tlb_d1  [w_index] <= w_d1;
         tlb_mat1[w_index] <= w_mat1;
         tlb_plv1[w_index] <= w_plv1;
         tlb_ppn1[w_index] <= w_ppn1;
      end
   end


   // ---------- Read port ----------
   assign r_vppn = tlb_vppn[r_index];
   assign r_asid = tlb_asid[r_index];
   //assign r_ps   = tlb_ps  [r_index];
   assign r_v0   = tlb_v0  [r_index];
   assign r_d0   = tlb_d0  [r_index];
   assign r_mat0 = tlb_mat0[r_index];
   assign r_plv0 = tlb_plv0[r_index];
   assign r_ppn0 = tlb_ppn0[r_index];
   assign r_v1   = tlb_v1  [r_index];
   assign r_d1   = tlb_d1  [r_index];
   assign r_mat1 = tlb_mat1[r_index];
   assign r_plv1 = tlb_plv1[r_index];
   assign r_ppn1 = tlb_ppn1[r_index];


   // ---------- Invalidation port ----------
   // Supported operations (inv_op encoding):
   // 0: invalidate all entries (global)
   // 1: invalidate by ASID
   // 2: invalidate by VPN (ignores ASID)
   // Others: reserved (no operation)
   always @(posedge clk) begin
      if (inv_en) begin
         case (inv_op)
            5'b00000: begin  // Global invalidate
               for (k = 0; k < 32; k = k + 1) begin
                  tlb_v0[k] <= 1'b0;
                  tlb_v1[k] <= 1'b0;
               end
            end
            5'b00001: begin  // Invalidate by ASID
               for (k = 0; k < 32; k = k + 1) begin
                  if (tlb_asid[k][9:0] == inv_asid[9:0]) begin
                     tlb_v0[k] <= 1'b0;
                     tlb_v1[k] <= 1'b0;
                  end
               end
            end
            5'b00010: begin  // Invalidate by VPN
               for (k = 0; k < 32; k = k + 1) begin
                  if (tlb_vppn[k] == inv_vppn) begin
                     tlb_v0[k] <= 1'b0;
                     tlb_v1[k] <= 1'b0;
                  end
               end
            end
            default: ; // No operation
         endcase
      end
   end

endmodule


// ============================================================
// Submodules for priority encoder
// ============================================================

// 4-bit priority encoder (LSB first)
// Outputs valid and 2-bit index (0~3)
module enc4 (
    input  [3:0] in,
    output       valid,
    output [1:0] idx
);
    assign valid = |in;
    // Binary encoding of least significant set bit
    assign idx[0] = in[1] | in[3];
    assign idx[1] = in[2] | in[3];
endmodule

// 8-bit priority encoder using two 4-bit encoders
module enc8 (
    input  [7:0] in,
    output       valid,
    output [2:0] idx  // 0~7
);
    wire       v_low, v_high;
    wire [1:0] i_low, i_high;

    enc4 low  (.in(in[3:0]), .valid(v_low), .idx(i_low));
    enc4 high (.in(in[7:4]), .valid(v_high), .idx(i_high));

    assign valid = v_low | v_high;
    // If low valid -> idx = i_low (0~3)
    // Else if high valid -> idx = 4 + i_high = {1'b1, i_high} (4~7)
    // Else idx = 0 (handled by default)
    assign idx = v_low ? {1'b0, i_low} : (v_high ? {1'b1, i_high} : 3'b0);
endmodule

// 16-bit priority encoder using two 8-bit encoders
module enc16 (
    input  [15:0] in,
    output        valid,
    output [3:0]  idx  // 0~15
);
    wire        v_low, v_high;
    wire [2:0]  i_low, i_high;

    enc8 low  (.in(in[7:0]),  .valid(v_low), .idx(i_low));
    enc8 high (.in(in[15:8]), .valid(v_high), .idx(i_high));

    assign valid = v_low | v_high;
    // If low valid -> idx = i_low (0~7)
    // Else if high valid -> idx = 8 + i_high = {1'b1, i_high} (8~15)
    assign idx = v_low ? {1'b0, i_low} : (v_high ? {1'b1, i_high} : 4'b0);
endmodule


// 32-bit priority encoder using two 16-bit encoders
module enc32 (
    input  [31:0] in,
    output [4:0]  out  // 0~31
);
    wire        v_low, v_high;
    wire [3:0]  i_low, i_high;

    enc16 low  (.in(in[15:0]), .valid(v_low), .idx(i_low));
    enc16 high (.in(in[31:16]), .valid(v_high), .idx(i_high));

    // If low valid -> idx = i_low (0~15)
    // Else if high valid -> idx = 16 + i_high = {1'b1, i_high} (16~31)
    // Else out = 0
    assign out = v_low ? {1'b0, i_low} : (v_high ? {1'b1, i_high} : 5'b0);
endmodule
