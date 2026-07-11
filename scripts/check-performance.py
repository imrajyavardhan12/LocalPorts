#!/usr/bin/env python3

import argparse
import math
import statistics
import subprocess
import sys
import time


SCENARIOS = (
    ("default-json", ("--json",)),
    ("filtered-miss", ("--json", "--port", "65535")),
    ("exposed-json", ("--json", "--exposed")),
)


def run_once(binary, arguments):
    started = time.perf_counter_ns()
    subprocess.run(
        (binary, *arguments),
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return (time.perf_counter_ns() - started) / 1_000_000


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]


def measure_pair(baseline, candidate, arguments, warmups, samples):
    for _ in range(warmups):
        run_once(baseline, arguments)
        run_once(candidate, arguments)

    baseline_samples = []
    candidate_samples = []
    for index in range(samples):
        if index % 2 == 0:
            baseline_samples.append(run_once(baseline, arguments))
            candidate_samples.append(run_once(candidate, arguments))
        else:
            candidate_samples.append(run_once(candidate, arguments))
            baseline_samples.append(run_once(baseline, arguments))

    return {
        "baseline_median": statistics.median(baseline_samples),
        "candidate_median": statistics.median(candidate_samples),
        "baseline_p95": percentile(baseline_samples, 0.95),
        "candidate_p95": percentile(candidate_samples, 0.95),
    }


def regressed(result, median_percent, median_floor, p95_percent, p95_floor):
    median_limit = result["baseline_median"] + max(
        result["baseline_median"] * median_percent,
        median_floor,
    )
    p95_limit = result["baseline_p95"] + max(
        result["baseline_p95"] * p95_percent,
        p95_floor,
    )
    return (
        result["candidate_median"] > median_limit
        or result["candidate_p95"] > p95_limit
    )


def run_suite(args):
    failed = []
    for name, arguments in SCENARIOS:
        result = measure_pair(
            args.baseline,
            args.candidate,
            arguments,
            args.warmups,
            args.samples,
        )
        print(
            f"{name}: "
            f"median {result['baseline_median']:.2f}ms -> {result['candidate_median']:.2f}ms, "
            f"p95 {result['baseline_p95']:.2f}ms -> {result['candidate_p95']:.2f}ms"
        )
        if regressed(
            result,
            args.median_percent,
            args.median_floor_ms,
            args.p95_percent,
            args.p95_floor_ms,
        ):
            failed.append(name)
    return failed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--warmups", type=int, default=10)
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--median-percent", type=float, default=0.20)
    parser.add_argument("--median-floor-ms", type=float, default=1.0)
    parser.add_argument("--p95-percent", type=float, default=0.25)
    parser.add_argument("--p95-floor-ms", type=float, default=2.0)
    args = parser.parse_args()

    failed = run_suite(args)
    if not failed:
        return 0

    print(f"possible regression in {', '.join(failed)}; rerunning once", file=sys.stderr)
    failed = run_suite(args)
    if failed:
        print(f"performance regression in {', '.join(failed)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
