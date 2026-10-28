# c7btlb — 32-entry TLB of cpu7b (ITLB / DTLB)

`c7btlb` is the translation lookaside buffer of the cpu7b LA32R core. The
same module is instantiated twice:

| Instance | Parent | Searched by | File |
|---|---|---|---|
| `u_itlb` | `c7bifu` | instruction fetch (`pf_vaddr_q`) and TLBSRCH | `c7bifu/rtl/c7bifu.v:404` |
| `u_dtlb` | `c7blsu` | load/store (`lsu_addr_ls2`) and TLBSRCH | `c7blsu/rtl/c7blsu.v:406` |

The two instances are not kept coherent by hardware. Software selects which
one a TLBWR / TLBFILL / TLBRD / TLBSRCH acts on through the
non-architectural bit `TLBIDX.I_D` (bit 16, 0 = ITLB, 1 = DTLB,
`c7bcsr/rtl/c7bcsr.v:511`). INVTLB has no index and invalidates matching
entries in both TLBs, as on a unified TLB.

The module has four ports:

- **Search port** - one registered request per cycle, result available
  combinationally in the following cycle (1-cycle latency).
- **Write port** - synchronous write of one full entry (TLBWR / TLBFILL).
- **Read port** - fully combinational read of one entry (TLBRD).
- **Invalidate port** - synchronous INVTLB, clears the `E` bit of all
  matching entries in one cycle.

## Block diagram

```
  s_vld ---------------------------+------------------+
  s_vppn[18:0], s_odd_page,        |                  |
  s_asid[9:0]                      v                  v
        |             +---------------------+   +-----------+
        +------------>| s_vppn_g            |   | s_vld_g   |  (reset 0)
                      | s_odd_page_g        |   +-----------+
                      | s_asid_g  (en=s_vld)|         |
                      +---------------------+         |
                                 | cycle N+1          |
                                 v                    |
  +---------------+   +---------------------+         |
  | entry array   |-->| 32 x match[i]       |  |match |
  | 32 x 89 bits  |   | VPPN & (ASID|G) & E |---------(&)---> s_found
  +---------------+   +---------------------+
    ^    ^    |                  | match[31:0]
    |    |    |                  v
    |    |    |       +---------------------+
    |    |    |       | enc32               |-------------> s_index[4:0]
    |    |    |       +---------------------+
    |    |    |                  | match_index
    |    |    |                  v
    |    |    +------>+---------------------+
    |    |            | entry[match_index]  |-------------> s_pfn s_v s_d
    |    |            | page0/1 by odd_g    |               s_mat s_plv
    |    |            +---------------------+
    |    |
    |    +-- we, w_index, w_*                 (TLBWR / TLBFILL)
    +------- inv_en, inv_op, inv_asid, inv_vppn  (INVTLB)

  entry array [r_index] (combinational) ----> r_vppn r_asid r_g r_ps r_e
                                              r_v0..r_ppn0 r_v1..r_ppn1
```

## Files

| File | Module | Purpose |
|---|---|---|
| `rtl/c7btlb.v` | `c7btlb` | Top: entry array, search / write / read / invalidate ports |
| `rtl/c7btlb.v` | `enc4`, `enc8`, `enc16`, `enc32` | Priority encoder tree for the match vector |
| `flist/c7btlb.flist` | | RTL file list (`rtl/c7btlb.v`) |
| `flist/sim.files` | | Simulation file list (`rtl/c7btlb.v`, `simulation/altera_mf.v`) |
| `tb/test0_top_tb.v` | `top_tb` | Unit testbench: 12 tasks (reset, write/search, miss, ASID, G, priority, odd page, read port, INVTLB op 0/4/5, reset after INVTLB) |
| `tb/c7btlb_tb_common.vh` | | Shared testbench body for test1..test5: DUT, reference model, tasks |
| `tb/test<N>_*_top_tb.v` | `top_tb` | Tests 1..5, see [Tests](#tests) |
| `simulation/run_all_tests.sh` | | Runs every test, prints PASS/FAIL per test and a summary |
| `simulation/test<N>/simulate.sh` | | ModelSim/Questa flow (`vlib`/`vlog`/`vsim -c`) |

Related logic outside this directory:

| File | Role |
|---|---|
| `c7bifu/rtl/c7bifu.v:349-470` | ITLB search drive, write/inv gating, CSR return path |
| `c7blsu/rtl/c7blsu.v:357-468` | DTLB search drive, write/inv gating, CSR return path |
| `c7bexu/rtl/c7bexu.v:881-919` | Decode of TLB ops into `*_vld_e` strobes, INVTLB operands |
| `c7bexu/rtl/random.v` | 5-bit free-running counter used as the TLBFILL index |
| `c7bcsr/rtl/c7bcsr.v:503-635` | TLBIDX (NE/PS/I_D/INDEX), TLBRD and TLBSRCH update |
| `c7bcsr/rtl/c7bcsr.v:660-1113` | TLBEHI / TLBELO0 / TLBELO1 / ASID update on TLBRD |

## Entry format

Each of the 32 entries is held in separate register arrays
(`c7btlb.v:66-86`):

| Group | Field | Width | Description |
|---|---|---|---|
| HI | `E`    | 1  | Entry exists. Only field cleared by reset and INVTLB |
| HI | `ASID` | 10 | Address space ID |
| HI | `G`    | 1  | Global: ignore ASID on match |
| HI | `PS`   | 6  | Page size. Stored and returned on read; not used by match |
| HI | `VPPN` | 19 | VA[31:13], one virtual page pair (even/odd 4 KB page) |
| LO0 | `V0`, `D0` | 1, 1 | Valid, dirty of even page |
| LO0 | `PLV0`, `MAT0` | 2, 2 | Privilege level, memory access type of even page |
| LO0 | `PPN0` | 20 | Physical page number of even page |
| LO1 | `V1`, `D1`, `PLV1`, `MAT1`, `PPN1` | 1, 1, 2, 2, 20 | Same for odd page |

Total: 37 bits HI + 2 x 26 bits LO = 89 bits per entry.

## Search port

### Request registration

The request is captured on the rising edge (`c7btlb.v:139-151`,
`c7btlb.v:229-235`):

- `s_vld_g <= s_vld` every cycle (reset to 0).
- `s_vppn_g`, `s_odd_page_g`, `s_asid_g` load only when `s_vld = 1`; they
  hold their previous value otherwise and have no reset.

All match logic and outputs use the registered copies, so the result is
available **one cycle after** `s_vld` is asserted, purely combinationally
from `*_g` and the current array contents. The module does not hold the
result: in the cycle after that, the outputs reflect the next request (or the
same `*_g` against possibly updated entries if no new request came).

### Match rule

```
match[i] = (s_vppn_g == tlb_vppn[i])
         & ((s_asid_g == tlb_asid[i]) | tlb_g[i])
         & tlb_e[i]                                   (c7btlb.v:244-247)
```

- Compare is always on the full 19-bit VPPN, i.e. a fixed 4 KB page size
  (8 KB pair). `tlb_ps` is never read by the search path, so entries written
  with any other PS are matched as 4 KB pages.
- The page `V` bit is not part of match (the term is commented out at
  `c7btlb.v:246`). An entry with `E=1` but `V=0` gives `s_found=1, s_v=0`,
  which the callers turn into PIF/PIL/PIS (`c7bifu.v:258`, `c7blsu.v:352-353`).

### Odd / even page select

`s_odd_page_g` (VA[12]) selects LO1 vs LO0 of entry `match_index` for
`s_v`, `s_d`, `s_mat`, `s_plv`, `s_pfn` (`c7btlb.v:262-266`). `s_odd_page`
does not affect `s_found` or `s_index`.

### Priority encoder

`enc32` is built as a tree `enc32 -> 2 x enc16 -> 2 x enc8 -> 2 x enc4`
(`c7btlb.v:303-369`). Each level selects the lower half when it has any bit
set, so between 4-entry groups the lowest group wins. Inside `enc4` the index
is an OR encoding (`idx[0] = in[1]|in[3]`, `idx[1] = in[2]|in[3]`,
`c7btlb.v:312-313`), which is only correct for at most one set bit. With
multiple hits inside one aligned group of 4 the index is the OR of the hit
indices, e.g. hits at 1 and 2 give index 3, which may be a non-matching
entry. The comment at `c7btlb.v:253` ("lowest index") holds only across
groups. Test 6 of `test0` uses entries 2 and 5 (different groups), so it
does not see this; `test1_multihit_priority` and phase B of `test4_random`
do. Multiple hits only arise if software writes overlapping entries.

When `match == 0`, `match_index = 0` (`c7btlb.v:368`).

### Output qualification

| Output | Expression | Qualified by `s_vld_g` |
|---|---|---|
| `s_found` | `\|match & s_vld_g` (`c7btlb.v:269`) | yes |
| `s_index` | `match_index` | no |
| `s_pfn`, `s_v`, `s_d`, `s_mat`, `s_plv` | entry `match_index`, page `s_odd_page_g` | no |

On a miss, or when no request was made in the previous cycle, `s_pfn` /
`s_v` / `s_d` / `s_mat` / `s_plv` show the selected page of entry 0 (or of a
stale match). Callers must gate them with `s_found` and with their own
registered request valid. There is no `s_ps` output, and `s_mat` is not
consumed by either caller in the search path.

## Write port (TLBWR / TLBFILL)

When `we = 1` and `inv_en = 0`, all 15 fields of entry `w_index` are written
on the rising edge (`c7btlb.v:208-225`). INVTLB has priority if both are
asserted in the same cycle (`c7btlb.v:159`). The EXU strobes cannot overlap
since they are decoded from a single `tlb_op_e` (`c7bexu.v:882-900`).

Caller-side drive (identical in IFU and LSU):

| Port | Source | Reference |
|---|---|---|
| `we` | ITLB: `(tlbfill_vld_e \| tlbwr_vld_e) & ~TLBIDX.I_D`; DTLB: same `& TLBIDX.I_D` | `c7bifu.v:385`, `c7blsu.v:390` |
| `w_index` | TLBFILL: `random_tlb_index`; TLBWR: `TLBIDX.INDEX` | `c7bifu.v:388-389`, `c7blsu.v:393-394` |
| `w_vppn` | `TLBEHI.VPPN` | `c7bifu.v:429` |
| `w_asid` | `ASID.ASID` | `c7bifu.v:430` |
| `w_g` | `TLBELO0.G & TLBELO1.G` | `c7bifu.v:431` |
| `w_ps` | `TLBIDX.PS` | `c7bifu.v:432` |
| `w_e` | `CSR.tlbrefill_ctx ? 1 : ~TLBIDX.NE` | `c7bifu.v:433` |
| `w_v0..w_ppn0`, `w_v1..w_ppn1` | `TLBELO0`, `TLBELO1` fields | `c7bifu.v:434-443` |

- `tlbrefill_ctx` is `ESTAT.Ecode == 6'h3f` (`c7bcsr.v:230`).
- The TLBFILL index comes from `random.v`, a 5-bit counter that increments
  every cycle from reset (`random.v:9-16`). It is shared by both TLBs
  (`c7bexu.v:913-919`, `c7bexu.v:567`).
- EXU mapping (`c7bexu.v:882-890`, codes in `c7bifu/rtl/dec_defs.v:90-103`):

| Instruction | EXU strobe | `tlb_op_e` code |
|---|---|---|
| TLBSRCH | `tlbsrch_vld_e` | `LTLB_TLBP` (4'b0010) |
| TLBRD   | `tlbrd_vld_e`   | `LTLB_TLBR` (4'b0011) |
| TLBWR   | `tlbwr_vld_e`   | `LTLB_TLBWI` (4'b0100) |
| TLBFILL | `tlbfill_vld_e` | `LTLB_TLBWR` (4'b0101) |
| INVTLB  | `invtlb_vld_e`  | `LTLB_INVTLB` (4'b1100) |

## Read port (TLBRD)

`r_*` are combinational reads of entry `r_index` (`c7btlb.v:279-293`).
Both instances are driven with `r_index = TLBIDX.INDEX` (`c7bifu.v:446`,
`c7blsu.v:445`). In the TLBRD E cycle (`tlbrd_vld_e`) the CSR block selects
ITLB or DTLB data by `TLBIDX.I_D` and loads TLBEHI, TLBELO0/1, ASID and
TLBIDX.PS/NE on the next edge (`c7bcsr.v:556-585`, `c7bcsr.v:660-681`).

- `r_e` is not wired straight to the CSR. It feeds `tlbidx_e`, and the
  caller returns `itlb_csr_tlbidx_e = tlbsrch_vld_m ? s_found : r_e`
  (`c7bifu.v:397`, `c7blsu.v:399`), so the same CSR input serves both TLBRD
  and TLBSRCH.
- `TLBIDX.NE <= ~E` of the selected TLB (`c7bcsr.v:579`).
- When `E = 0`, VPPN / ELO0 / ELO1 / ASID data are forced to 0 by the CSR
  (`c7bcsr.v:663-666` and similar). PS is loaded from the entry without this
  clearing (`c7bcsr.v:557`).
- `r_g` returns the single stored G bit, which the CSR writes into both
  TLBELO0.G and TLBELO1.G (`c7bcsr.v:755`, `c7bcsr.v:944`).

## Invalidate port (INVTLB)

`inv_en` triggers a one-cycle, all-entry parallel operation on the next edge
(`c7btlb.v:159-207`). Only `tlb_e` is cleared; other fields are kept.

| `inv_op` | Entries with `E` cleared | Reference |
|---|---|---|
| 0 | all | `c7btlb.v:161` |
| 1 | all (same as 0) | `c7btlb.v:166` |
| 2 | `G = 1` | `c7btlb.v:171` |
| 3 | `G = 0` | `c7btlb.v:178` |
| 4 | `G = 0` and `ASID == inv_asid` | `c7btlb.v:185` |
| 5 | `G = 0` and `ASID == inv_asid` and `VPPN == inv_vppn` | `c7btlb.v:192` |
| 6 | (`G = 1` or `ASID == inv_asid`) and `VPPN == inv_vppn` | `c7btlb.v:199` |
| 7..31 | none (no operation) | `c7btlb.v:206` |

- The block comment at `c7btlb.v:153-158` (ops 0/1/2 = all / ASID / VPN) is
  out of date; the case statement above is what the RTL does.
- Operands from EXU: `inv_op = rd`, `inv_asid = rj[9:0]`,
  `inv_vppn = rk[31:13]` (`c7bexu.v:903-910`). VPPN compare is full 19 bits
  (4 KB page pair), independent of the entry's PS.
- The decoder flags INVTLB with `rd > 6` as an illegal instruction
  (`c7bifu/rtl/decoder.v:872`).
- `inv_en` is not gated by `TLBIDX.I_D`: both the ITLB (`c7bifu.v`) and
  the DTLB (`c7blsu.v`) get `invtlb_vld_e`, so one INVTLB invalidates
  matching entries in both TLBs. It used to be gated like the write port,
  which left stale entries in the other TLB whenever the kernel flushed a
  page (for example after copy-on-write) with `I_D` selecting the wrong
  TLB.

## ITLB vs DTLB selection (TLBIDX.I_D)

| Operation | ITLB (`I_D = 0`) | DTLB (`I_D = 1`) |
|---|---|---|
| TLBWR / TLBFILL | written | written |
| INVTLB | both invalidated, `I_D` ignored | both invalidated, `I_D` ignored |
| TLBRD | both read; CSR takes ITLB data | both read; CSR takes DTLB data |
| TLBSRCH | both searched; CSR takes ITLB result | both searched; CSR takes DTLB result |

For write only the selected TLB is modified; INVTLB modifies both. For read and search
both instances see the request and the selection happens in `c7bcsr.v`
(`c7bcsr.v:557`, `c7bcsr.v:579`, `c7bcsr.v:604`). `I_D` is writable only by
CSR write; TLBRD/TLBSRCH do not change it (`c7bcsr.v:533-545`).

## TLBSRCH and the shared search port

There is no separate search port for TLBSRCH. Each caller muxes it onto the
fetch / LSU port:

```
s_vld  = tlb_s_vld | exu_*tlb_tlbsrch_vld_e              (c7bifu.v:411, c7blsu.v:411)
s_vppn = tlbsrch_vld_e ? TLBEHI.VPPN : VA[31:13]           (c7bifu.v:413, c7blsu.v:413)
s_asid = ASID.ASID                                         (c7bifu.v:417; c7blsu.v:416 muxes
                                                            between two copies of the same CSR)
s_odd_page = VA[12] of the fetch / LSU address             (c7bifu.v:414, c7blsu.v:414)
```

- `s_odd_page` is not switched for TLBSRCH; it only affects the page data
  outputs, which TLBSRCH does not use.
- The TLB itself does no arbitration. If a fetch/LSU request and a TLBSRCH
  are presented in the same cycle, TLBSRCH wins the VPPN mux and the caller's
  registered valid (`tlb_res_vld`, `tlb_res_vld_ls2`) would observe the
  TLBSRCH result. Avoiding this relies on pipeline stalls outside the TLB:
  `stall_iq` includes `ifu_exu_tlb_vld_d` (`c7bifu.v:243`), EXU stalls on
  `tlb_vld_e` "to let tlbsrch take tlb's search port" (`c7bexu.v:996`), and
  `c7bifu.v:410` carries a "todo, make tlb instructions stall IFU" note.
- The result is taken one cycle later with `tlbsrch_vld_m`, a register of
  `tlbsrch_vld_e` (`c7bexu.v:894-898`, also duplicated in `c7bifu.v:613`).
  The CSR loads `TLBIDX.NE <= ~s_found` always, and `TLBIDX.INDEX <= s_index`
  only on a hit (`c7bcsr.v:582-609`).

## Timelines

All signals are sampled at the rising edge at the end of the cycle shown.
`R` = result of the request in the column.

### Search

```
cycle            N            N+1            N+2
                 request      result
s_vld            1            0 (or next)
s_vppn/odd/asid  VA                          
s_vld_g          -            1              0
s_vppn_g ..      old          VA             VA (held, no new s_vld)
match[]          (old req)    R              VA vs current entries
s_found          -            hit(R)         0   (s_vld_g = 0)
s_index, s_pfn,  -            R              still entry for VA (unqualified)
s_v/d/mat/plv
caller res_vld   -            1              0
```

Back-to-back requests are accepted every cycle; request N+1 produces its
result in N+2.

### Write then search

```
cycle            N               N+1                N+2
EXU              TLBWR (E)
we, w_index=k    1               0
tlb[k]           old             new (edge N/N+1)
search A: req    N-1 -> result N  : sees old entry k
search B: req    N   -> result N+1: sees new entry k
search C: req    N+1 -> result N+2: sees new entry k
```

Because match uses the current array contents in the result cycle, a search
requested in the same cycle as the write already observes the new entry.

### INVTLB

```
cycle            N                 N+1
EXU              INVTLB op (E)
inv_en           1                 0
tlb_e[match]     1                 0 (edge N/N+1)
search req N-1 -> result N   : still hits the old entry
search req N   -> result N+1 : misses
```

### TLBSRCH

```
cycle            N (E)                    N+1 (M)                    N+2
tlbsrch_vld_e    1                        0
s_vld            1 (OR fetch/LSU)
s_vppn           TLBEHI.VPPN
s_vld_g          -                        1
tlbsrch_vld_m    0                        1
s_found/s_index  -                        result
*_csr_tlbidx_e   r_e                      s_found (mux c7bifu.v:397)
TLBIDX.NE        old                      old                        ~s_found
TLBIDX.INDEX     old                      old                        s_index if hit
```

### TLBRD (for reference)

```
cycle            N (E)                     N+1
tlbrd_vld_e      1
r_index          TLBIDX.INDEX
r_*              entry[INDEX] (comb.)
TLBEHI/ELO/ASID  old                       entry data (0 if E=0), PS, NE
```

## Handling the 1-cycle result latency (callers)

The TLB returns results one cycle after the request and does not hold them.
A caller must therefore:

1. Register its own copy of the request valid and use it to qualify all
   result-based decisions. IFU: `tlb_res_vld <= tlb_s_vld`
   (`c7bifu.v:605-609`), LSU: `tlb_res_vld_ls2 <= tlb_s_vld`
   (`c7blsu.v:830-834`). TLBR / PIx / PPI / PME exceptions are all
   `res_vld & ...` (`c7bifu.v:256-259`, `c7blsu.v:350-355`).
2. Treat `s_pfn`, `s_v`, `s_d`, `s_plv`, `s_mat` as meaningful only when
   `s_found` is high; they are not qualified inside the TLB.
3. Keep the page offset VA[11:0] available in the result cycle; the physical
   address is `{s_pfn, VA[11:0]}` built by the caller (`c7bifu.v:380`,
   `c7blsu.v:387`).
4. Not rely on `s_found` alone to identify its own request, since a TLBSRCH
   in the previous cycle also raises `s_vld_g`.

The fetch-side handling, including how `fcl_req` is aligned to the TLB
result (`c7bifu.v:245`), is described in `../c7bifu/README.md` ("ITLB
timing"). That README (c7bifu commit `d26c8e4`) also describes masking the
request and the TLBR/PIF/PPI checks with `flush_dly1` and `tlbsrch_vld_m`.
In the checked-out `c7bifu.v` the exception terms are qualified only by
`tlb_res_vld` (`c7bifu.v:256-259`), and `tlbsrch_vld_m` is used only for the
`itlb_csr_tlbidx_e` mux (`c7bifu.v:397`).

## Limitations

| Item | Reference |
|---|---|
| Only 4 KB page pairs are matched; `PS` is stored and read back but unused by search and INVTLB | `c7btlb.v:244`, `c7btlb.v:194`, `c7btlb.v:201` |
| `s_pfn`/`s_v`/`s_d`/`s_mat`/`s_plv`/`s_index` are not qualified by `s_vld_g` or `s_found` | `c7btlb.v:270-275` |
| Reset clears only `E` (and `s_vld_g`); other entry fields and `s_*_g` are X until written | `c7btlb.v:141-148`, `c7btlb.v:229-235` |
| Priority encoder returns OR of indices on multiple hits within a 4-entry group | `c7btlb.v:312-313` |
| ITLB and DTLB are separate; software must write each via `TLBIDX.I_D` (INVTLB acts on both) | `c7bifu.v:405`, `c7blsu.v:390` |
| INVTLB op comment block does not match the implemented ops | `c7btlb.v:153-158` |
| Debug wire arrays `test_tlb_*` mirror the entry arrays (simulation visibility only) | `c7btlb.v:97-137` |

## Tests

Run all tests with `simulation/run_all_tests.sh`, or one test with
`./simulate.sh` in its directory (`./viewwave.sh` opens the waveform).
Tests 1..5 compare the DUT with a reference model of the LA32R TLB rules
(`tb/c7btlb_tb_common.vh`), drive inputs and sample outputs on the falling
clock edge, and print `TEST SUMMARY: ALL PASS` or the number of failed
checks.

| Test | Checks | Result with the current RTL |
|---|---|---|
| `test0` | Original unit tests | PASS |
| `test1_multihit_priority` | Several matching entries: every set inside one group of 4, every pair of entries, a V=0 refill entry plus the valid entry for the same page | FAIL: `enc4` returns the OR of the matching indices |
| `test2_invtlb` | INVTLB op 0..6 with several arguments, reserved ops, reset, E=0 writes; every entry checked through the read port | PASS |
| `test3_search_port` | Result latency, back-to-back searches, write / INVTLB in the request cycle, V=0 and E=0 entries, odd/even fields, ASID, G, all VPPN bits | PASS |
| `test4_random` | 5000 random operations per phase against the model; phase A without, phase B with duplicate entries (`+seed=<n>`) | FAIL in phase B only, in searches with several matches in one group of 4 |
| `test5_page_size` | PS=22 (4 MB) entries | FAIL: PS is stored but entries are matched as 4 KB pairs (missing feature, Linux uses 4 KB pages) |

The results in the last column are the expected outcome derived from the
RTL; with `enc4` fixed, tests 0..4 should pass.

## Interface summary

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock |
| `resetn` | in | 1 | Async active-low reset; clears `tlb_e[*]`, `s_vld_g` |
| `s_vld` | in | 1 | Search request valid (registered) |
| `s_vppn` | in | 19 | VA[31:13] to search |
| `s_odd_page` | in | 1 | VA[12], selects page 1 data |
| `s_asid` | in | 10 | ASID to match |
| `s_found` | out | 1 | Hit, cycle after request; `\|match & s_vld_g` |
| `s_index` | out | 5 | Index of hit entry (0 on miss) |
| `s_pfn` | out | 20 | PPN of selected page (unqualified) |
| `s_d` | out | 1 | Dirty of selected page (unqualified) |
| `s_v` | out | 1 | Valid of selected page (unqualified) |
| `s_mat` | out | 2 | MAT of selected page (unqualified) |
| `s_plv` | out | 2 | PLV of selected page (unqualified) |
| `we` | in | 1 | Write enable (ignored when `inv_en = 1`) |
| `w_index` | in | 5 | Entry to write |
| `w_vppn` | in | 19 | VPPN |
| `w_asid` | in | 10 | ASID |
| `w_g` | in | 1 | Global |
| `w_ps` | in | 6 | Page size (stored only) |
| `w_e` | in | 1 | Exists |
| `w_v0`, `w_d0` | in | 1, 1 | Page 0 valid, dirty |
| `w_mat0`, `w_plv0` | in | 2, 2 | Page 0 MAT, PLV |
| `w_ppn0` | in | 20 | Page 0 PPN |
| `w_v1`, `w_d1` | in | 1, 1 | Page 1 valid, dirty |
| `w_mat1`, `w_plv1` | in | 2, 2 | Page 1 MAT, PLV |
| `w_ppn1` | in | 20 | Page 1 PPN |
| `r_index` | in | 5 | Entry to read (combinational) |
| `r_vppn`, `r_asid`, `r_g`, `r_ps`, `r_e` | out | 19, 10, 1, 6, 1 | HI fields of entry `r_index` |
| `r_v0`, `r_d0`, `r_mat0`, `r_plv0`, `r_ppn0` | out | 1, 1, 2, 2, 20 | Page 0 fields |
| `r_v1`, `r_d1`, `r_mat1`, `r_plv1`, `r_ppn1` | out | 1, 1, 2, 2, 20 | Page 1 fields |
| `inv_en` | in | 1 | INVTLB enable (priority over `we`) |
| `inv_op` | in | 5 | INVTLB op, 0..6 implemented |
| `inv_asid` | in | 10 | ASID operand (ops 4, 5, 6) |
| `inv_vppn` | in | 19 | VA[31:13] operand (ops 5, 6) |
