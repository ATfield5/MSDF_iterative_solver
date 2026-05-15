# P3-SP Fast2 Start-Gap Checkpoint

## Goal

This checkpoint only tests the current `K=4` feedback version and only changes the local online affine core. It does not add more wavefront stages, deeper overlap, or a new scheduling policy.

The target experiment was to reduce the adjacent output start gap from 4 cycles to 2 cycles:

$$
\mathrm{start\ gap}=t_{\mathrm{first\ valid},1}-t_{\mathrm{first\ valid},0}
$$

## Finding

The original combinational-output `fast2_core` did reduce the measured simulation gap to 2 cycles, but route analysis showed that this was not a valid synchronous microarchitecture. It allowed stage outputs to feed later stages combinationally in the same clock period, collapsing multiple online stages into one timing path.

The invalid route path was:

$$
\text{feedback FIFO read pointer}
\rightarrow
\text{stage0 source mux}
\rightarrow
\text{stage0 online add/select}
\rightarrow
\text{later stage source muxes}
\rightarrow
\text{stage capture registers}
$$

The routed timing report showed worst paths over `60 ns`, with about `87%` route delay and `81` logic levels. That is a code-structure problem, not a realistic arithmetic critical path.

## Microarchitecture Change

The baseline P3-SP core registers the parallel-in contribution before residual update:

$$
u[j]=2^{-\delta_{SP}}\left(\sum_s a_s x_{s,j+1+\delta_{SP}}+b_{j+1+\delta_{SP}}\right)
$$

$$
v[j]=2w[j]+u[j-1]
$$

That extra contribution register is safe for timing, but it adds one scheduling bubble before the residual/output-update loop can emit the next useful digit packet.

The corrected `fast2_core` keeps a synchronous output register boundary but removes the internal contribution register. It computes contribution, residual candidate, digit selection, and residual update in one local online step, then registers the emitted digit:

$$
u[j]=2^{-\delta_{SP}}\left(\sum_s a_s x_{s,j+1+\delta_{SP}}+b_{j+1+\delta_{SP}}\right)
$$

$$
v[j]=2w[j]+u[j]
$$

$$
z[j+1]=\mathrm{sel}(\hat v[j])
$$

$$
w[j+1]=v[j]-z[j+1]
$$

The external contract is unchanged: `DATA_WIDTH=32`, `BIT_WIDTH=30`, `BIAS_WIDTH=32`, `PHYSICAL_DEGREE=8`, `ONLINE_DELAY=2`. The valid synchronous version removes the internal contribution-to-residual register but preserves the stage boundary.

## Functional Results

Command shape:

```bash
iverilog -g2012 -I MSDF_iterative_solver/tb \
  -DPARALLEL_IN_FAST2_VALUE=<0_or_1> \
  -DPARALLEL_IN_FEEDBACK_STAGES_VALUE=4 \
  -DPARALLEL_IN_FEEDBACK_SUPERSTEPS_VALUE=2 \
  -DPARALLEL_IN_FEEDBACK_LINF_ETA_VALUE=1 \
  ...
```

| core | K | target supersteps | PASS | total cycles | first_valid0 | first_valid1 | first_gap01 | feedback_stall | status |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| baseline | 4 | 2 | yes | 94 | 5 | 9 | 4 | 0 | valid |
| fast2 combinational output | 4 | 2 | yes | 82 | 3 | 5 | 2 | 0 | invalid for route |
| fast2 registered output + value-accumulated Linf | 4 | 2 | yes | 88 | 4 | 7 | 3 | 0 | valid synchronous boundary |

The attempted combinational-output start-gap reduction was:

$$
4\ \mathrm{cycles}\rightarrow 2\ \mathrm{cycles}
$$

but this result is not a legal routed claim. With a valid synchronous output boundary, the current result is:

$$
4\ \mathrm{cycles}\rightarrow 3\ \mathrm{cycles}
$$

The reason is structural: after a stage emits a registered digit on clock edge `t`, the next stage can only consume it on edge `t+1`. Therefore a synchronous stage-to-stage boundary adds one cycle:

$$
\mathrm{gap}_{\min}=\delta_{SP}+1=3
$$

To claim a true `2`-cycle stage-to-stage gap, the design would need a different timing contract, such as latch/time-borrowing, two-phase clocks, or same-cycle combinational stage chaining. Those are not the current FPGA-safe design style.

## Linf Certification Fix

The original feedback top rebuilt every row value from `p/n` words after a stage completed:

$$
\{p,n\}_{32\times32}
\rightarrow
\mathrm{sd\_value}
\rightarrow
|\Delta|
\rightarrow
\max_i|\Delta_i|
\rightarrow
\mathrm{stop/FIFO\ control}
$$

That put a 32-row reconstruction and max-reduction into the same control path. The current Verilog instead maintains numeric old/new row values while digits are captured:

$$
x_{\mathrm{acc}}[j+1]=2x_{\mathrm{acc}}[j]+d[j]
$$

When a stage finishes, the `L∞` path uses these accumulated values and registers the max before driving convergence/stop control. This keeps certification functionally equivalent while removing the worst `sd_value()` reconstruction from the feedback-control path.

## Strict Termination Regression

The strict termination regression uses the original PageRank-style criterion:

$$
\max_i |r_i^{(k+1)}-r_i^{(k)}|\le 1\ \mathrm{raw\ LSB}
$$

Command shape:

```bash
iverilog -g2012 -I MSDF_iterative_solver/tb \
  -DPARALLEL_IN_FAST2_VALUE=1 \
  -DPARALLEL_IN_FEEDBACK_STAGES_VALUE=4 \
  -DPARALLEL_IN_FEEDBACK_SUPERSTEPS_VALUE=32 \
  -DPARALLEL_IN_FEEDBACK_EXPECT_CONVERGED_VALUE=1 \
  -DPARALLEL_IN_FEEDBACK_LINF_ETA_VALUE=1 \
  ...
```

Current valid registered-output result:

| core | K | PASS | total cycles | final_supersteps | first_gap01 | converged | converged_stage | feedback_stall |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fast2 registered output + value-accumulated Linf | 4 | yes | 961 | 25 | 3 | 1 | 1 | 0 |

The previous strict termination result for the combinational-output checkpoint is superseded and should not be used as route evidence.

The next strict termination regression must be rerun with the registered-output `fast2_core` before using it as a formal result.

## Timing Status

The invalid combinational-output fast2 version lengthened the effective critical path because it combined:

$$
\text{parallel contribution tree}
\rightarrow
\text{residual add}
\rightarrow
\text{selection}
\rightarrow
\text{residual subtract/update}
$$

and also allowed multiple stages to chain combinationally. The bad routed path is therefore not a fair measure of the intended online core.

The corrected registered-output fast2 version has been iteratively optimized on U55C at a 5 ns target:

| checkpoint | WNS | LUT | FF | CARRY8 | DSP | BRAM | dynamic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| synth, value-accumulated Linf | -15.438 ns | 121483 | 23552 | 11985 | 0 | 0 | 1.936 W |
| synth, pipelined Linf max-reduction | -1.946 ns | 116738 | 28702 | 11852 | 0 | 0 | 1.684 W |
| synth, feedback FIFO prefetch + local digit index | -0.866 ns | 116880 | 29273 | 11852 | 0 | 0 | 1.632 W |
| synth, continuous non-stall digit stream | -0.166 ns | 119109 | 29292 | 11852 | 0 | 0 | 1.850 W |
| route, continuous non-stall digit stream | -9.326 ns | 118464 | 29974 | 11852 | 0 | 0 | 1.703 W |
| synth, stop decoupled from stage0 arithmetic | -0.166 ns | 118711 | 29286 | 11852 | 0 | 0 | 1.817 W |
| synth, local stage digit index + 4-row output groups | -0.166 ns | 119045 | 29322 | 11852 | 0 | 0 | 1.863 W |
| route, local stage digit index + 4-row output groups | -9.005 ns | 118433 | 30103 | 11852 | 0 | 0 | 1.689 W |
| route, core33 registered fast2 before selector rewrite | -2.303 ns | 112809 | 22379 | 11468 | 0 | 0 | 1.571 W |
| route, core33 exact threshold selector | -1.866 ns | 109853 | 22350 | 10828 | 0 | 0 | 1.542 W |
| route, high-field correction ablation | -2.006 ns | 111410 | 22314 | 10828 | 0 | 0 | 1.633 W |
| route, feedback term preselect | -1.851 ns | 109374 | 22615 | 10828 | 0 | 0 | 1.660 W |
| route, feedback term preselect + valid/data decoupling | -1.746 ns | 109578 | 22616 | 10828 | 0 | 0 | 1.766 W |
| route, bounded estimate selector, exact contribution source | -0.905 ns | 104918 | 22618 | 10188 | 0 | 0 | NA |
| route, split bounded estimate selector | -0.594 ns | 112990 | 22952 | NA | 0 | 0 | NA |
| route, split estimate + PageRank nonnegative coefficient path | -0.272 ns | 93395 | 22569 | 8140 | 0 | 0 | 1.608 W |
| route, split estimate + PageRank nonnegative coeff/bias path | -0.121 ns | 92002 | 22564 | 8140 | 0 | 0 | 1.589 W |
| route, split selector + high-field correction | -1.209 ns | 115602 | 22918 | NA | 0 | 0 | NA |

The retained RTL changes are:

- feedback FIFO read-ahead, so `rd_ptr` no longer feeds stage0 arithmetic in the same cycle;
- accumulated old/new numeric values and pipelined `L∞` reduction, so certification is off the arithmetic critical path;
- continuous non-stall stage operation, so feedback `valid` no longer gates the online core every cycle.
- stop control decoupling, so `r_stop_requested` no longer drives stage0 residual arithmetic in the same cycle;
- local stage digit indexing, so non-stall stages use their own feed counter rather than the previous stage digit index for internal bias/digit selection;
- 4-row producer-side output groups, which slightly reduce routed inter-stage fanout but do not solve the global PageRank route problem.
- exact `\pm 1/2` threshold decoding for the digit selector, so the fast2 path no longer builds full-width signed comparators for `z=+1/0/-1`.
- feedback term preselection, so the feedback FIFO packet is converted from `32` row digits to `row x term` input digits before stage0 arithmetic consumes it;
- digit valid/data decoupling, so `o_z_p/o_z_n` are no longer cleared by `w_valid_now`; downstream stages use `o_valid` for sampling.
- bounded estimate selection, so `z` is selected from a small high-bit estimate of `2w+u` rather than the full binary residual candidate;
- split estimate contribution, so the selector estimate uses an independent high-bit contribution tree instead of waiting for the full-width contribution tree.

Two attempted changes were not retained:

- a stage0 input register closed more local paths but increased compute cycles from `88` to `90`;
- row-local feedback buffer replication and output `max_fanout` increased resources/power without improving the routed result.
- per-row producer-side output replication made Icarus simulation impractical for even the 2-superstep regression and is not retained.
- high-field residual correction rewrote `w_v - z*2^frac_bits` into low-bit passthrough plus high-field `+/-1`; it was exact but worsened route from `-1.866 ns` to `-2.006 ns`, so it is not retained.

The current routed failure is no longer caused by the certification path. The worst routed path is a PageRank global-source inter-stage data path:

$$
\text{stage }s\ \text{row output digit}
\rightarrow
\text{stage }s+1\ \text{global source mux / contribution tree}
\rightarrow
\text{online residual register}
$$

The routed reports show route-dominated worst paths. Earlier core36 routes were about `82%` to `85%` route delay; after switching to the core33 datapath, exact threshold selector, feedback term preselect, and valid/data decoupling, the latest worst path is still `70.2%` route delay with `8` CARRY8 levels. The selector rewrite improved WNS from `-2.303 ns` to `-1.866 ns`; feedback term preselect and valid/data decoupling further improved the best WNS to `-1.746 ns`. This is still not timing-clean. The remaining issue is the same-cycle PageRank source mux, contribution tree, `2w+u`, and selector path between physical stages, not the certification path.

The current defensible conclusion is:

$$
\text{valid synchronous start gap}=3
$$

The earlier `2`-cycle result is kept only as a debugging artifact showing why same-cycle combinational chaining is unsafe.

At the current K=4 feedback scale, local no-cycle RTL tuning plus bounded estimate selection reduced the routed fast2 failure to `WNS=-0.594 ns`.  The PageRank-specific nonnegative coefficient/bias path further improves the best result to `WNS=-0.121 ns` and lowers LUT to `92002`, because the transition matrix and teleport/bias terms are nonnegative and do not need signed coefficient/bias decode.  Route still fails because the residual feedback update remains a full binary carry-propagate path. Closing U55C 5 ns without increasing arithmetic cycles now requires a mathematically valid redundant residual state, graph/source banking to reduce PageRank source fanout, floorplanned stage clusters, or an explicit inter-stage register that moves the stage gap back toward `4`.

## Interpretation

This experiment shows that the current FPGA-safe synchronous design cannot honestly claim a `2`-cycle stage-to-stage start interval with edge-triggered registers. The valid improvement is `4 -> 3` cycles. Further reduction requires changing the timing contract or changing what is measured; it should not be claimed by allowing combinational stage collapse.
