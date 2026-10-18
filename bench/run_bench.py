#!/usr/bin/env python3
"""
run_bench.py — Parse MIST-ES benchmark logs and emit report files.

Usage:
    python3 run_bench.py --results-dir results/ --iterations 1000

Output:
    results/report.md      — Markdown report
    results/report.csv     — CSV for further analysis
"""

import argparse
import re
import sys
from pathlib import Path
from datetime import datetime


def parse_log(log_path: Path):
    if not log_path.exists():
        return {"name": log_path.stem, "status": "MISSING",
                "sim_cycles": None, "bench_cycles": None}
    text = log_path.read_text()
    r = {"name": log_path.stem, "status": "MISSING",
         "sim_cycles": None, "bench_cycles": None}

    m = re.search(
        r'\[BENCH\]\s+(\S+)\s+sim_cycles=(\d+)'
        r'(?:\s+bench_cycles=(\d+))?'
        r'\s+(PASS|FAIL\S*)', text)
    if m:
        r["name"]         = m.group(1)
        r["sim_cycles"]   = int(m.group(2))
        r["bench_cycles"] = int(m.group(3)) if m.group(3) else None
        r["status"]       = m.group(4)
    elif "TIMEOUT" in text:
        r["status"] = "TIMEOUT"
        sc = re.search(r'sim_cycles=(\d+)', text)
        if sc: r["sim_cycles"] = int(sc.group(1))
    return r


def fmt(n, sep=True):
    if n is None: return "—"
    return f"{n:,}" if sep else str(n)


def write_report(results_dir: Path, iterations: int):
    """Generate MIST-ES benchmark report."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cm = parse_log(results_dir / "coremark.log")
    cm_cycles = cm["bench_cycles"] if cm["bench_cycles"] else cm["sim_cycles"]
    cpi = cm_cycles / iterations if cm_cycles else None

    md = [
        "# MIST-ES Benchmark Results",
        "",
        f"Generated: {now}  ",
        "Simulator: **Verilator** (cycle-accurate)  ",
        "Compiler: `-O2 -march=rv32imc_zicsr -mabi=ilp32`  ",
        "",
        "## CoreMark",
        "",
        f"ITERATIONS = {iterations:,}",
        "",
    ]
    if cm["status"] == "PASS" and cpi:
        md += [
            f"- Status: **✅ PASS**",
            f"- Total sim cycles: **{fmt(cm['sim_cycles'])}**",
        ]
        if cm["bench_cycles"]:
            md.append(f"- Total bench cycles: **{fmt(cm['bench_cycles'])}**")
        md += [
            f"- Cycles/iteration: **{cpi:,.1f}**",
            f"- CoreMark/MHz: **{1e6/cpi:.4f}**",
            f"- Total Score @ 50 MHz: **{1e6/cpi*50:.2f}**",
            "",
        ]
    else:
        md += [f"- Status: **❌ {cm['status']}**", ""]

    results_dir.mkdir(parents=True, exist_ok=True)
    (results_dir / "report.md").write_text("\n".join(md) + "\n")
    print(f"[REPORT] Written: {results_dir / 'report.md'}")

    # ---- CSV ----------------------------------------------------------------
    csv = ["benchmark,sim_cycles,bench_cycles,status"]
    csv.append(f"coremark,{cm['sim_cycles'] or ''},{cm['bench_cycles'] or ''},{cm['status']}")
    (results_dir / "report.csv").write_text("\n".join(csv) + "\n")
    print(f"[REPORT] Written: {results_dir / 'report.csv'}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--results-dir",  default="results")
    p.add_argument("--iterations",   type=int, default=1000)
    args = p.parse_args()

    out = Path(args.results_dir)
    write_report(out, args.iterations)


if __name__ == "__main__":
    main()
