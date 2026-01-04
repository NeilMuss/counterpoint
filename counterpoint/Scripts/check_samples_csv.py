#!/usr/bin/env python3
import argparse
import csv
import sys


def parse_args():
    parser = argparse.ArgumentParser(
        description="Sanity-check sample CSV for monotone Y in near-vertical runs."
    )
    parser.add_argument("csv_path", help="Path to sample CSV")
    parser.add_argument("--x-tol", type=float, default=1.0e-6, help="Max |dx| to consider a segment vertical")
    parser.add_argument("--y-tol", type=float, default=1.0e-6, help="Min |dy| to consider a segment moving")
    parser.add_argument("--eps", type=float, default=1.0e-6, help="Allowed epsilon for monotone violations")
    return parser.parse_args()


def main():
    args = parse_args()
    with open(args.csv_path, newline="") as f:
        reader = csv.DictReader(f)
        required = {"x", "y"}
        if not required.issubset(reader.fieldnames or []):
            print(f"Missing required columns: {required}", file=sys.stderr)
            return 2
        rows = []
        for row in reader:
            try:
                x = float(row["x"])
                y = float(row["y"])
            except ValueError:
                continue
            rows.append((x, y))

    if len(rows) < 2:
        print("Not enough rows to check.", file=sys.stderr)
        return 0

    violations = []
    run_start = 0
    run_dir = 0
    for i in range(1, len(rows)):
        x0, y0 = rows[i - 1]
        x1, y1 = rows[i]
        dx = x1 - x0
        dy = y1 - y0
        is_vertical = abs(dx) <= args.x_tol and abs(dy) > args.y_tol
        if not is_vertical:
            run_start = i
            run_dir = 0
            continue

        if run_dir == 0 and abs(y1 - rows[run_start][1]) > args.y_tol:
            run_dir = 1 if y1 >= rows[run_start][1] else -1

        if run_dir > 0 and y1 + args.eps < y0:
            violations.append((i, x0, y0, x1, y1))
        elif run_dir < 0 and y1 - args.eps > y0:
            violations.append((i, x0, y0, x1, y1))

    if violations:
        print("Non-monotone Y detected in near-vertical runs:", file=sys.stderr)
        for index, x0, y0, x1, y1 in violations:
            print(f"  line {index + 1}: ({x0:.6f},{y0:.6f}) -> ({x1:.6f},{y1:.6f})", file=sys.stderr)
        return 1

    print("OK: no non-monotone Y in near-vertical runs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
