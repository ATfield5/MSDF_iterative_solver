#!/usr/bin/env python3
"""Model how many online iteration stages should be cascaded.

The model is intentionally simple: it answers whether a K-stage digit-stream
wavefront has enough latency advantage to justify K copies of the row engine.
It does not replace RTL simulation; it is the sizing rule before implementing a
large K-stage PageRank pipeline.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "generated/wavefront_stage_depth_model.md"


def full_wait_cycles(k: int, data_width: int, online_delay: int, boundary: int) -> int:
    return k * (data_width + online_delay + boundary)


def wavefront_cycles(k: int, data_width: int, online_delay: int, inter_stage_delay: int) -> int:
    if k <= 0:
        return 0
    return data_width + k * online_delay + (k - 1) * inter_stage_delay


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-width", type=int, default=14)
    parser.add_argument(
        "--online-delay",
        type=int,
        default=10,
        help="Cycles before the next iteration can consume the first stable output digit.",
    )
    parser.add_argument(
        "--boundary",
        type=int,
        default=4,
        help="Per-iteration barrier/control overhead in the full-wait reference.",
    )
    parser.add_argument("--inter-stage-delay", type=int, default=0)
    parser.add_argument("--max-stages", type=int, default=16)
    parser.add_argument("--max-practical-stages", type=int, default=8)
    parser.add_argument(
        "--min-marginal-speedup",
        type=float,
        default=1.05,
        help="Stop recommending deeper K when K+1 gives less than this total speedup ratio over K.",
    )
    args = parser.parse_args()

    rows = []
    prev_speedup = 0.0
    recommended = 1
    for k in range(1, args.max_stages + 1):
        fw = full_wait_cycles(k, args.data_width, args.online_delay, args.boundary)
        wf = wavefront_cycles(k, args.data_width, args.online_delay, args.inter_stage_delay)
        speedup = fw / wf
        marginal = speedup / prev_speedup if prev_speedup > 0 else speedup
        rows.append(
            {
                "k": k,
                "full_wait": fw,
                "wavefront": wf,
                "speedup": speedup,
                "marginal": marginal,
            }
        )
        if k <= args.max_practical_stages and (k == 1 or marginal >= args.min_marginal_speedup):
            recommended = k
        prev_speedup = speedup

    OUT.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Wavefront Stage-Depth Model",
        "",
        "This report sizes the number of cascaded online PageRank iteration stages.",
        "It is a sizing model, not an RTL result.",
        "",
        "## Model",
        "",
        "Full-wait baseline:",
        "",
        "$$",
        "T_{\\mathrm{full}}(K)=K(D+\\delta+B)",
        "$$",
        "",
        "Digit-stream wavefront:",
        "",
        "$$",
        "T_{\\mathrm{wave}}(K)=D+K\\delta+(K-1)F",
        "$$",
        "",
        "where:",
        "",
        f"- $D={args.data_width}$ is the committed state digit width.",
        f"- $\\delta={args.online_delay}$ is the usable online output delay.",
        f"- $B={args.boundary}$ is the full-wait iteration barrier overhead.",
        f"- $F={args.inter_stage_delay}$ is any extra register/FIFO delay between stages.",
        "",
        "## Sweep",
        "",
        "| K stages | full-wait cycles | wavefront cycles | speedup | marginal speedup vs K-1 |",
        "| ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            f"| {row['k']} | {row['full_wait']} | {row['wavefront']} | "
            f"{row['speedup']:.3f}x | {row['marginal']:.3f}x |"
        )

    lines.extend(
        [
            "",
            "## Recommendation",
            "",
            f"Recommended first RTL depth: **K={recommended}**.",
            "",
            "Reasoning:",
            "",
            "- K must not exceed the number of PageRank iterations we want to fuse.",
            "- Area grows approximately linearly with K because each stage needs its own row engines/residual state.",
            "- K beyond the recommendation has diminishing total-speedup gain under the current delay model.",
            "- K=4 is the minimum useful paper checkpoint because it demonstrates more than a two-stage handoff.",
            "- K=8 is the practical upper checkpoint for the next sweep; deeper K should wait for routed resource data.",
            "",
            "## JSON",
            "",
            "```json",
            json.dumps({"params": vars(args), "recommended": recommended, "rows": rows}, indent=2),
            "```",
            "",
        ]
    )
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"recommended_k={recommended}")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
