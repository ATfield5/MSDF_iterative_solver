#!/usr/bin/env python3
"""Run a finite smoke test for the prior paper's MSDF_MUL_ADD_8 RTL."""

from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "MSDF_operator_srcs/MSDF_Operators/MSDF_Operators/MSDF_Operators.srcs/sources_1/new"
TB = ROOT / "MSDF_iterative_solver/tb/tb_prior_mma8_smoke.v"
OUT = Path("/tmp/tb_prior_mma8_smoke.vvp")
REPORT = ROOT / "MSDF_iterative_solver/generated/prior_online_original_smoke_report.md"


SOURCES = [
    "DFF.v",
    "full_adder.v",
    "parallel_online_adder_block.v",
    "parallel_online_adder.v",
    "parallel_online_adder_4.v",
    "parallel_online_adder_4_with_obuf.v",
    "vector_append.v",
    "selector.v",
    "append_and_select.v",
    "output_and_update.v",
    "MSDF_MUL_ADD_8.v",
]


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True, text=True)


def main() -> None:
    compile_cmd = [
        "iverilog",
        "-g2012",
        "-o",
        str(OUT),
        *[str(SRC / name) for name in SOURCES],
        str(TB),
    ]
    run(compile_cmd)
    sim = run(["vvp", str(OUT)])

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(
        "\n".join(
            [
                "# Prior Online Original RTL Smoke Report",
                "",
                "This is the finite P1 smoke entry for the original `MSDF_MUL_ADD_8` operator.",
                "It verifies that the local copy of the prior paper RTL compiles and emits",
                "operator-level output digits. It does not claim solver-level PageRank behavior.",
                "",
                "## Command",
                "",
                "```bash",
                "python MSDF_iterative_solver/run_prior_online_original_smoke.py",
                "```",
                "",
                "## Icarus Output",
                "",
                "```text",
                sim.stdout.strip(),
                "```",
                "",
                "## Interpretation",
                "",
                "- `MSDF_MUL_ADD_8` is a valid operator-level integrated online inner-product RTL block.",
                "- It has no state memory, PageRank source template, iteration controller, or convergence logic.",
                "- P2 therefore must wrap this operator into the current runtime shell before it can be used as a fair prior-online baseline.",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(sim.stdout, end="")
    print(f"Wrote {REPORT}")


if __name__ == "__main__":
    main()
