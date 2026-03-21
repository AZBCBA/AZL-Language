#!/usr/bin/env bash
# Quality metrics for AZL (parallel to how mature languages are judged).
# Always: timed native gates + codebase/doc inventory (JSON + plain-language Markdown report).
# Optional: see AZL_MEASURE_* below. ERROR[BENCHMARK_AZL_QUALITY_PARALLEL]: docs/ERROR_SYSTEM.md
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/azl_local_layout.sh"

die() {
  local c="${1:?}"
  shift
  echo "ERROR[BENCHMARK_AZL_QUALITY_PARALLEL]: $*" >&2
  exit "$c"
}

if [ ! -f "Makefile" ] || [ ! -d "scripts" ]; then
  die 320 "must run from repository root"
fi
if ! command -v python3 >/dev/null 2>&1; then
  die 321 "python3 is required to write reports"
fi

# AZL_MEASURE_COMPREHENSIVE=1 → doc promoted timing + reference C/Python bench + perf_smoke timing (each may skip if tools missing)
if [ "${AZL_MEASURE_COMPREHENSIVE:-0}" = "1" ]; then
  export AZL_MEASURE_DOC_PROMOTED="${AZL_MEASURE_DOC_PROMOTED:-1}"
  export AZL_MEASURE_REFERENCE="${AZL_MEASURE_REFERENCE:-1}"
  export AZL_MEASURE_PERF_SMOKE="${AZL_MEASURE_PERF_SMOKE:-1}"
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_JSON="${AZL_BENCHMARKS_DIR}/azl_quality_measurement_${TS}.json"
OUT_MD="${AZL_BENCHMARKS_DIR}/azl_quality_measurement_${TS}_report.md"
mkdir -p "$AZL_BENCHMARKS_DIR"

p0_count="$(find azl/tests -maxdepth 1 -name 'p0_semantic_*.azl' 2>/dev/null | wc -l)"
p0_count="${p0_count//[[:space:]]/}"
f_gate_count="$(grep -c 'echo "\[gate\] F' scripts/check_azl_native_gates.sh 2>/dev/null || echo 0)"
f_gate_count="${f_gate_count//[[:space:]]/}"

start_g=$(date +%s)
set +e
bash scripts/check_azl_native_gates.sh
gates_rc=$?
set -e
end_g=$(date +%s)
gates_sec=$((end_g - start_g))

verify_sec=""
verify_rc=""
if [ "${AZL_MEASURE_FULL_VERIFY:-0}" = "1" ]; then
  start_v=$(date +%s)
  set +e
  RUN_OPTIONAL_BENCHES=0 bash scripts/run_full_repo_verification.sh
  verify_rc=$?
  set -e
  end_v=$(date +%s)
  verify_sec=$((end_v - start_v))
fi

docs_sec=""
docs_rc=""
if [ "${AZL_MEASURE_DOC_PROMOTED:-0}" = "1" ]; then
  start_d=$(date +%s)
  set +e
  bash scripts/verify_documentation_pieces.sh --promoted-only
  docs_rc=$?
  set -e
  end_d=$(date +%s)
  docs_sec=$((end_d - start_d))
fi

perf_sec=""
perf_rc=""
if [ "${AZL_MEASURE_PERF_SMOKE:-0}" = "1" ] && [ -x scripts/perf_smoke.sh ]; then
  start_p=$(date +%s)
  set +e
  bash scripts/perf_smoke.sh
  perf_rc=$?
  set -e
  end_p=$(date +%s)
  perf_sec=$((end_p - start_p))
elif [ "${AZL_MEASURE_PERF_SMOKE:-0}" = "1" ]; then
  perf_rc=-2
fi

tests_sec=""
tests_rc=""
if [ "${AZL_MEASURE_RUN_ALL_TESTS:-0}" = "1" ]; then
  start_t=$(date +%s)
  set +e
  bash scripts/run_all_tests.sh
  tests_rc=$?
  set -e
  end_t=$(date +%s)
  tests_sec=$((end_t - start_t))
fi

ref_c_mean_ms=""
ref_py_mean_ms=""
ref_ratio=""
ref_path=""
ref_note="skipped"
ref_rc=0
if [ "${AZL_MEASURE_REFERENCE:-0}" = "1" ]; then
  if command -v hyperfine >/dev/null 2>&1 && command -v gcc >/dev/null 2>&1; then
    set +e
    bash scripts/benchmark_language_real_world.sh
    ref_rc=$?
    set -e
    ref_path="${AZL_BENCHMARKS_DIR}/benchmark_language_real_world_hyperfine.json"
    if [ "$ref_rc" -ne 0 ]; then
      ref_note="benchmark_language_real_world_failed_exit_${ref_rc}"
    fi
    if [ -f "$ref_path" ]; then
      read -r ref_c_mean_ms ref_py_mean_ms ref_ratio <<EOF
$(REF_JSON_PATH="$ref_path" python3 <<'PY'
import json
import os

path = os.environ.get("REF_JSON_PATH", "")
if not path or not os.path.isfile(path):
    print("null null null")
    raise SystemExit(0)
with open(path, encoding="utf-8") as f:
    data = json.load(f)
results = data.get("results") or []
c_ms = py_ms = None
for r in results:
    cmd = r.get("command") or []
    s = " ".join(cmd) if isinstance(cmd, list) else str(cmd)
    t = r.get("mean")
    if t is None:
        continue
    if "spectralnorm_c" in s or "/spectralnorm_c" in s:
        c_ms = float(t) * 1000.0
    elif "spectralnorm.py" in s:
        py_ms = float(t) * 1000.0
ratio = ""
if c_ms and py_ms and c_ms > 0:
    ratio = f"{py_ms / c_ms:.4f}"

def fmt(x):
    return "null" if x is None else str(x)

print(f"{fmt(c_ms)} {fmt(py_ms)} {ratio if ratio else 'null'}")
PY
)
EOF
      if [ "$ref_rc" -eq 0 ]; then
        ref_note="ok"
      fi
    else
      if [ "$ref_rc" -eq 0 ]; then
        ref_note="hyperfine_json_missing"
      fi
    fi
  else
    ref_note="missing_hyperfine_or_gcc"
  fi
fi

git_commit=""
if command -v git >/dev/null 2>&1; then
  git_commit="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
fi

export ROOT_DIR TS OUT_JSON OUT_MD
export p0_count f_gate_count gates_sec gates_rc
export verify_sec verify_rc docs_sec docs_rc perf_sec perf_rc tests_sec tests_rc
export ref_c_mean_ms ref_py_mean_ms ref_ratio ref_path ref_note ref_rc git_commit

python3 <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["ROOT_DIR"]).resolve()


def count_lines(path: Path) -> int:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return sum(1 for _ in f)
    except OSError:
        return 0


def collect_inventory() -> dict:
    azl_sources = sorted(root.glob("azl/**/*.azl"))
    lines = sum(count_lines(p) for p in azl_sources)
    interp = root / "azl/runtime/interpreter/azl_interpreter.azl"
    tests_azl = sorted((root / "azl/tests").glob("*.azl")) if (root / "azl/tests").is_dir() else []
    verify_scripts = sorted((root / "scripts").glob("verify_*.sh"))
    tools_py = sorted((root / "tools").rglob("*.py")) if (root / "tools").is_dir() else []
    return {
        "azl_source_files_count": len(azl_sources),
        "azl_source_total_lines": lines,
        "interpreter_azl_path": str(interp.relative_to(root)) if interp.is_file() else None,
        "interpreter_azl_lines": count_lines(interp) if interp.is_file() else None,
        "azl_tests_fixture_files_count": len(tests_azl),
        "scripts_verify_sh_count": len(verify_scripts),
        "tools_python_files_count": len(tools_py),
    }


def doc_manifest_stats() -> dict:
    p = root / "release/doc_verification_pieces.json"
    if not p.is_file():
        return {"doc_manifest_path": None, "doc_pieces_total": 0, "doc_pieces_promoted": 0}
    with open(p, encoding="utf-8") as f:
        data = json.load(f)
    pieces = data.get("pieces") or []
    promoted = sum(1 for x in pieces if x.get("promoted") is True)
    return {
        "doc_manifest_path": str(p.relative_to(root)),
        "doc_pieces_total": len(pieces),
        "doc_pieces_promoted": promoted,
        "doc_pieces_not_promoted": len(pieces) - promoted,
    }


def num_or_none(s):
    if s is None or s == "" or s == "null":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def int_or_none(s):
    if s is None or s == "":
        return None
    try:
        return int(s)
    except ValueError:
        return None


def env_int(key, default=None):
    v = os.environ.get(key, "")
    if v == "":
        return default
    try:
        return int(v)
    except ValueError:
        return default


out_json = os.environ["OUT_JSON"]
out_md = os.environ["OUT_MD"]
gates_rc = int(os.environ.get("gates_rc", "1"))

inventory = collect_inventory()
doc_stats = doc_manifest_stats()

correctness = {
    "p0_semantic_fixture_count": int_or_none(os.environ.get("p0_count")) or 0,
    "native_gate_echo_f_count": int_or_none(os.environ.get("f_gate_count")) or 0,
    "native_gates_wall_seconds": float(os.environ["gates_sec"]),
    "native_gates_passed": gates_rc == 0,
    "native_gates_exit_code": gates_rc,
}

perf = {}
vs = os.environ.get("verify_sec", "")
if vs != "":
    perf["full_verify_wall_seconds"] = float(vs)
    perf["full_verify_exit_code"] = env_int("verify_rc", -1)

ds = os.environ.get("docs_sec", "")
if ds != "":
    perf["doc_pieces_promoted_wall_seconds"] = float(ds)
    perf["doc_pieces_promoted_exit_code"] = env_int("docs_rc", -1)
    perf["doc_pieces_promoted_passed"] = env_int("docs_rc", -1) == 0

ps = os.environ.get("perf_sec", "")
if ps != "":
    perf["perf_smoke_wall_seconds"] = float(ps)
    prc = env_int("perf_rc", -99)
    perf["perf_smoke_exit_code"] = prc
    perf["perf_smoke_passed"] = prc == 0
    if prc == -2:
        perf["perf_smoke_note"] = "perf_smoke.sh not executable"

ts_ = os.environ.get("tests_sec", "")
if ts_ != "":
    perf["run_all_tests_wall_seconds"] = float(ts_)
    perf["run_all_tests_exit_code"] = env_int("tests_rc", -1)

ref_note = os.environ.get("ref_note", "")
if ref_note != "skipped":
    ref = {
        "reference_benchmark_note": ref_note,
        "spectral_norm_c_mean_ms": num_or_none(os.environ.get("ref_c_mean_ms")),
        "spectral_norm_python_mean_ms": num_or_none(os.environ.get("ref_py_mean_ms")),
        "python_over_c_time_ratio": num_or_none(os.environ.get("ref_ratio")),
        "hyperfine_json_path": os.environ.get("ref_path") or None,
    }
    perf["reference_c_python_spectral_norm"] = ref

doc = {
    "schema": "azl_quality_measurement_v2",
    "generated_at_utc": os.environ.get("TS", ""),
    "git_commit": os.environ.get("git_commit") or None,
    "codebase_inventory": inventory,
    "documentation_trust_manifest": doc_stats,
    "parallel_to_python_lenses": {
        "correctness_regression_surface": correctness,
        "performance_timings": perf,
        "stability": {
            "note": "Track CHANGELOG, tags, and verify pass rate over time outside this file.",
        },
        "security_and_ops": {
            "note": "Full verify includes live native checks; record CVE/advisory process separately as the project matures.",
        },
        "practicality": {
            "note": "Doc pieces + inventory approximate 'surface area' like ecosystem/docs breadth for a young language.",
        },
    },
}

with open(out_json, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")

# Plain-language Markdown report (non-developer friendly)
inv = inventory
ref = perf.get("reference_c_python_spectral_norm")
lines_md = [
    "# AZL quality snapshot (plain language)",
    "",
    f"**When (UTC):** {doc['generated_at_utc']}",
    f"**Saved detail file:** `{out_json}`",
    "",
    "## 1. Did the main automatic checks pass?",
    "",
    "| Question | Answer |",
    "|----------|--------|",
    f"| Did the **native gate** suite pass? | **{'Yes' if correctness['native_gates_passed'] else 'No'}** |",
    f"| How long did that suite take? | **~{correctness['native_gates_wall_seconds']:.0f} seconds** (whole seconds; your machine may vary slightly) |",
]

if "doc_pieces_promoted_passed" in perf:
    lines_md.extend(
        [
            f"| Did the **promoted documentation checks** pass? | **{'Yes' if perf['doc_pieces_promoted_passed'] else 'No'}** |",
            f"| How long did those doc checks take? | **~{perf['doc_pieces_promoted_wall_seconds']:.1f} seconds** |",
        ]
    )
if "perf_smoke_passed" in perf:
    note = perf.get("perf_smoke_note", "")
    if note:
        lines_md.append(f"| **API perf smoke** | **Skipped or not runnable** ({note}) |")
    else:
        lines_md.append(
            f"| Did **perf smoke** (API timing check) pass? | **{'Yes' if perf['perf_smoke_passed'] else 'No'}** |"
        )
        lines_md.append(f"| How long did perf smoke take? | **~{perf['perf_smoke_wall_seconds']:.1f} seconds** |"
        )
if "full_verify_wall_seconds" in perf:
    lines_md.extend(
        [
            f"| Did **full verify** pass? | **{'Yes' if perf.get('full_verify_exit_code') == 0 else 'No'}** |",
            f"| How long did full verify take? | **~{perf['full_verify_wall_seconds']:.0f} seconds** |",
        ]
    )
if "run_all_tests_wall_seconds" in perf:
    lines_md.extend(
        [
            f"| Did **all tests** pass? | **{'Yes' if perf.get('run_all_tests_exit_code') == 0 else 'No'}** |",
            f"| How long did all tests take? | **~{perf['run_all_tests_wall_seconds']:.0f} seconds** |",
        ]
    )

lines_md.extend(
    [
        "",
        "## 2. How big is the AZL codebase (rough size)?",
        "",
        "| What we counted | Number |",
        "|-----------------|--------:|",
        f"| **AZL source files** (under `azl/`) | **{inv['azl_source_files_count']:,}** |",
        f"| **Total lines** in those files | **{inv['azl_source_total_lines']:,}** |",
    ]
)
if inv.get("interpreter_azl_lines"):
    lines_md.append(
        f"| **Lines in the main interpreter file** | **{inv['interpreter_azl_lines']:,}** |"
    )
lines_md.extend(
    [
        f"| **Test fixture files** in `azl/tests/` | **{inv['azl_tests_fixture_files_count']:,}** |",
        f"| **Semantic parity fixtures** (`p0_semantic_*.azl`) | **{correctness['p0_semantic_fixture_count']:,}** |",
        f"| **`verify_*.sh` scripts** | **{inv['scripts_verify_sh_count']:,}** |",
        f"| **Python tool files** under `tools/` | **{inv['tools_python_files_count']:,}** |",
        "",
        "## 3. Documentation checks wired to the repo",
        "",
        "| What | Count |",
        "|------|------:|",
        f"| **Total doc-linked checks** in the manifest | **{doc_stats['doc_pieces_total']:,}** |",
        f"| **Promoted** (run at start of full verify) | **{doc_stats['doc_pieces_promoted']:,}** |",
        f"| **Not promoted** (bench / optional) | **{doc_stats['doc_pieces_not_promoted']:,}** |",
        "",
        "## 4. Reference speed test (NOT AZL — C vs Python)",
        "",
        "This is the **same small math program** in two ordinary languages. **AZL is not timed here.** "
        "It is only a **ruler** so you see how large the gap can be between a compiled language and Python on one task.",
        "",
    ]
)

if ref and ref.get("spectral_norm_c_mean_ms") is not None:
    c_ms = ref["spectral_norm_c_mean_ms"]
    py_ms = ref["spectral_norm_python_mean_ms"]
    ratio = ref.get("python_over_c_time_ratio")
    lines_md.extend(
        [
            "| Program | Average time this run |",
            "|---------|----------------------:|",
            f"| **C** | **{c_ms:.2f} ms** |",
            f"| **Python** | **{py_ms:.2f} ms** |",
        ]
    )
    if ratio:
        lines_md.append(
            f"| **Roughly** | Python took **~{float(ratio):.1f}× longer** than C on this one exercise |"
        )
else:
    lines_md.append(
        "| Status | Reference benchmark was **not run** or **not available** (needs `hyperfine`, `gcc`, and the spectral-norm files). |"
    )

lines_md.extend(
    [
        "",
        "## 5. What this snapshot does **not** tell you",
        "",
        "- **It does not rank AZL against Python for speed.** To do that, AZL would need to run the **same timed exercise**.",
        "- **It does not measure “how good the language is” in one number.** It is **several rulers** at once: checks passed, sizes, optional times, optional reference race.",
        "",
        "---",
        "*Re-run: `make measure-azl-quality` or `AZL_MEASURE_COMPREHENSIVE=1 bash scripts/measure_azl_quality_parallel.sh`*",
        "",
    ]
)

with open(out_md, "w", encoding="utf-8") as f:
    f.write("\n".join(lines_md))

print(out_json)
print(out_md)
PY

if [ "$gates_rc" -ne 0 ]; then
  die "$gates_rc" "native gates failed (exit $gates_rc); reports written to $OUT_JSON and $OUT_MD"
fi

if [ "${AZL_MEASURE_FULL_VERIFY:-0}" = "1" ] && [ "${verify_rc:-1}" -ne 0 ]; then
  die "$verify_rc" "full verify failed (exit $verify_rc); reports written"
fi

if [ "${AZL_MEASURE_REFERENCE:-0}" = "1" ] && [ "${ref_rc:-0}" -ne 0 ]; then
  die "$ref_rc" "reference benchmark failed (exit $ref_rc); reports written"
fi

if [ "${AZL_MEASURE_DOC_PROMOTED:-0}" = "1" ] && [ "${docs_rc:-1}" -ne 0 ]; then
  die "$docs_rc" "verify_documentation_pieces --promoted-only failed (exit $docs_rc); reports written"
fi

echo "measure-azl-quality-parallel-ok"
