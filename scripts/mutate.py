#!/usr/bin/env python3
"""Minimal mutation testing for Sources/SRTCore (run via `make mutate`; slow, never in CI).

Muter, the usual Swift tool, has had no release since 2023, so this script does the core job:
it applies one small operator mutation at a time to a *copy* of the repo, runs `swift test`, and
reports which mutants the tests failed to kill. The working tree is never modified.

Usage: scripts/mutate.py [--files GLOB] [--max N] [--timeout SECONDS]
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# (pattern, replacement). Spaces around binary operators avoid generics (`<T>`) and ranges (`..<`).
OPERATORS = [
    (" == ", " != "), (" != ", " == "),
    (" && ", " || "), (" || ", " && "),
    (" < ", " <= "), (" <= ", " < "), (" > ", " >= "), (" >= ", " > "),
    (" + ", " - "), (" - ", " + "),
    (r"\btrue\b", "false"), (r"\bfalse\b", "true"),
]


def code_spans(line: str):
    """Yield (start, end) of the parts of a line outside string literals and // comments."""
    in_str, start, i = False, 0, 0
    while i < len(line):
        if not in_str and line.startswith("//", i):
            break
        if line[i] == '"' and (i == 0 or line[i - 1] != "\\"):
            if not in_str:
                yield start, i
            in_str = not in_str
            start = i + 1
        i += 1
    if not in_str:
        yield start, i


def mutants(path: Path):
    lines = path.read_text().splitlines(keepends=True)
    for n, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith(("//", "import ", "#", "@")):
            continue
        for pattern, repl in OPERATORS:
            regex = re.compile(pattern if pattern.startswith("\\") else re.escape(pattern))
            for s, e in code_spans(line):
                for m in regex.finditer(line, s, e):
                    mutated = line[: m.start()] + repl + line[m.end():]
                    yield n, line, mutated, f"{pattern.strip()} -> {repl.strip()}".replace("\\b", "")


def run_tests(cwd: Path, timeout: int) -> str:
    try:
        r = subprocess.run(["swift", "test"], cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "killed"  # a hang counts as detected
    out = r.stdout + r.stderr
    if r.returncode == 0:
        return "survived"
    return "uncompilable" if "error:" in out and "Test run with" not in out else "killed"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--files", default="Sources/SRTCore/**/*.swift")
    ap.add_argument("--max", type=int, default=0, help="stop after N mutants (0 = all)")
    ap.add_argument("--timeout", type=int, default=180)
    args = ap.parse_args()

    work = Path(tempfile.mkdtemp(prefix="srt-mutate-"))
    for item in ["Package.swift", "Package.resolved", "Sources", "Tests"]:
        src = ROOT / item
        (shutil.copytree if src.is_dir() else shutil.copy2)(src, work / item)
    print(f"Working copy: {work}")
    print("Baseline build + tests…", flush=True)
    if run_tests(work, 1800) != "survived":
        print("Baseline tests fail in the working copy; fix them first.", file=sys.stderr)
        return 2

    files = sorted(p for p in work.glob(args.files) if p.is_file())
    results, survivors, started = {"killed": 0, "survived": 0, "uncompilable": 0}, [], time.time()
    count = 0
    for path in files:
        original = path.read_text()
        lines = original.splitlines(keepends=True)
        for n, before, after, label in mutants(path):
            if args.max and count >= args.max:
                break
            count += 1
            mutated = lines.copy()
            mutated[n] = after
            path.write_text("".join(mutated))
            outcome = run_tests(work, args.timeout)
            path.write_text(original)
            results[outcome] += 1
            rel = path.relative_to(work)
            mark = {"killed": "✔", "survived": "✘", "uncompilable": "·"}[outcome]
            print(f"{mark} {rel}:{n + 1} {label}", flush=True)
            if outcome == "survived":
                survivors.append(f"{rel}:{n + 1}  {label}\n    {before.strip()}\n    {after.strip()}")

    valid = results["killed"] + results["survived"]
    score = 100.0 * results["killed"] / valid if valid else 0.0
    print(f"\nMutants: {count}  killed: {results['killed']}  survived: {results['survived']}  "
          f"uncompilable (ignored): {results['uncompilable']}  time: {time.time() - started:.0f}s")
    print(f"Mutation score: {score:.1f}%")
    if survivors:
        print("\nSurviving mutants (tests did not notice the change):")
        print("\n".join(survivors))
    shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
