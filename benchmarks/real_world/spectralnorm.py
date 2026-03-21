#!/usr/bin/env python3
# spectral-norm — same algorithm as benchmarks/real_world/spectralnorm.c (Benchmarks Game).
# https://benchmarksgame-team.pages.debian.net/benchmarksgame/performance/spectralnorm.html
from __future__ import annotations

import math
import sys


def eval_a(i: int, j: int) -> float:
    return 1.0 / (((i + j) * (i + j + 1)) // 2 + i + 1)


def eval_a_times_u(n: int, u: list[float]) -> list[float]:
    return [sum(eval_a(i, j) * u[j] for j in range(n)) for i in range(n)]


def eval_at_times_u(n: int, u: list[float]) -> list[float]:
    return [sum(eval_a(j, i) * u[j] for j in range(n)) for i in range(n)]


def eval_ata_times_u(n: int, u: list[float]) -> list[float]:
    v = eval_a_times_u(n, u)
    return eval_at_times_u(n, v)


def main() -> None:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    u = [1.0] * n
    v: list[float]
    for _ in range(10):
        v = eval_ata_times_u(n, u)
        u = eval_ata_times_u(n, v)
    vbv = sum(ui * vi for ui, vi in zip(u, v))
    vv = sum(vi * vi for vi in v)
    print(f"{math.sqrt(vbv / vv):.9f}")


if __name__ == "__main__":
    main()
