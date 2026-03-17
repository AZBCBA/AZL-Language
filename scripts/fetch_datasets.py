#!/usr/bin/env python3
import os, sys, json, time
from typing import Iterable
from datasets import load_dataset
from datasets.utils.logging import set_verbosity_warning
set_verbosity_warning()

ROOT = '/home/abdulrahman-alzalameh/azl-language'
OUTDIR = '/mnt/ssd2t/azl_datasets'
os.makedirs(OUTDIR, exist_ok=True)

# Caps per dataset to fit disk. Adjust if you have more space.
DEFAULT_CAPS = {
  'c4_en': 200_000,
  'openwebtext': 200_000,
  'fineweb_edu': 200_000,
  'wikipedia_en': 500_000,
  'arxiv_scipapers': 100_000,
  'stackexchange': 200_000,
  'bookcorpusopen': 200_000,
  'mc4_en': 200_000,
  'the_stack_smol_py_js_ts': 200_000,
}


def write_jsonl(path: str, items: Iterable[str], cap: int):
    n = 0
    with open(path, 'w', encoding='utf-8') as w:
        for txt in items:
            if not txt:
                continue
            w.write(json.dumps({'text': txt})+'\n')
            n += 1
            if n % 10000 == 0:
                print(f"wrote {n} -> {path}")
            if n >= cap:
                break
    print(f"DONE {path} lines={n}")


def stream_c4_en(cap: int):
    ds = load_dataset('c4', 'en', split='train', streaming=True)
    for ex in ds:
        yield ex.get('text')

def stream_openwebtext(cap: int):
    # Updated community mirror frequently used
    ds = load_dataset('openwebtext', split='train', streaming=True)
    for ex in ds:
        yield ex.get('text')

def stream_fineweb_edu(cap: int):
    # Correct dataset id / mirror: fineweb-edu is commonly served as 'HuggingFaceFW/fineweb-edu'
    # Fallback to 'HuggingFaceH4/FineWeb' if needed
    try:
        ds = load_dataset('HuggingFaceFW/fineweb-edu', split='train', streaming=True)
    except Exception:
        ds = load_dataset('HuggingFaceH4/FineWeb', split='train', streaming=True)
    for ex in ds:
        yield ex.get('text')

def stream_wikipedia_en(cap: int):
    # Use a recent known-good config; allow override via WIKI_CFG
    cfg = os.environ.get('WIKI_CFG', '20231101.en')
    try:
        ds = load_dataset('wikimedia/wikipedia', cfg, split='train', streaming=True)
    except Exception:
        # Fallback older snapshot
        ds = load_dataset('wikimedia/wikipedia', '20220301.en', split='train', streaming=True)
    for ex in ds:
        yield ex.get('text')

def stream_arxiv_scipapers(cap: int):
    ds = load_dataset('allenai/scientific_papers', 'arxiv', split='train', streaming=True)
    for ex in ds:
        parts = [ex.get('article'), ex.get('abstract'), ex.get('title')]
        yield '\n\n'.join([p for p in parts if p])

def stream_stackexchange(cap: int):
    ds = load_dataset('flax-community/stackexchange', split='train', streaming=True)
    for ex in ds:
        q = ex.get('question') or ''
        a = '\n\n'.join(ex.get('answers') or [])
        txt = (q + '\n\n' + a).strip()
        yield txt

def stream_bookcorpusopen(cap: int):
    ds = load_dataset('bookcorpusopen', split='train', streaming=True)
    for ex in ds:
        yield ex.get('text')

def stream_mc4_en(cap: int):
    ds = load_dataset('mc4', 'en', split='train', streaming=True)
    for ex in ds:
        yield ex.get('text')

def stream_the_stack_smol_py_js_ts(cap: int):
    ds = load_dataset('bigcode/the-stack-smol', split='train', streaming=True)
    for ex in ds:
        if ex.get('lang') not in {'python','javascript','typescript'}:
            continue
        yield ex.get('content')

# Prefer reliable sources first; temporarily skip c4 and openwebtext due to upstream streaming issues
TASKS = [
  ('wikipedia_en', stream_wikipedia_en),
  ('bookcorpusopen', stream_bookcorpusopen),
  ('arxiv_scipapers', stream_arxiv_scipapers),
  ('stackexchange', stream_stackexchange),
  ('mc4_en', stream_mc4_en),
  ('the_stack_smol_py_js_ts', stream_the_stack_smol_py_js_ts),
  # ('c4_en', stream_c4_en),
  # ('openwebtext', stream_openwebtext),
  ('fineweb_edu', stream_fineweb_edu),
]


def main():
    print('Starting dataset fetch...')
    os.environ.setdefault('HF_DATASETS_CACHE', os.path.join(ROOT, '.hf_cache'))
    os.makedirs(os.environ['HF_DATASETS_CACHE'], exist_ok=True)
    for name, fn in TASKS:
        cap = int(os.environ.get(f'CAP_{name.upper()}', DEFAULT_CAPS.get(name, 100000)))
        out = os.path.join(OUTDIR, f'{name}.jsonl')
        print(f'Fetching {name} -> {out} cap={cap}')
        try:
            write_jsonl(out, fn(cap), cap)
        except Exception as e:
            print(f'ERROR {name}: {e!r}')
    print('All fetch done.')

if __name__ == '__main__':
    main()
