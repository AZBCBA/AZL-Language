### AZME Full-Stack Training Preparation (No Execution)

This prepares a unified corpus and training configs to train all AZME/AZL parts with all datasets, without starting any training jobs.

Steps:

1) Build unified corpus from all available datasets

```bash
python3 scripts/prepare_azme_full_corpus.py
```

Outputs:
- `datasets/real_world_training/azme_full_corpus.txt`
- `datasets/real_world_training/azme_full_corpus.stats.json`

2) Generate master configs and training config without running

```bash
python3 master_training_launcher.py --action prepare --config project/entries/config/master_training_config.json
```

This sets the dataset to the unified corpus and writes:
- `project/entries/config/master_training_config.json`
- `project/entries/config/training_config.json`

3) Verify configs reference the unified corpus and tokenizer path

```bash
grep -n "azme_full_corpus" project/entries/config/master_training_config.json project/entries/config/training_config.json | cat
```

After preparation, you can later start training explicitly:

```bash
# (do not run now unless you want to start training)
python3 master_training_launcher.py --action train --config project/entries/config/master_training_config.json
```

Notes:
- No server/processes are started by the above prepare commands.
- The pipeline integrates event supervision (`tools/event_eval.jsonl`) and will auto-train SentencePiece if needed.

Optional prep utilities (no training):
- Validate setup: `python3 scripts/validate_training_setup.py`
- Train tokenizer: `python3 scripts/prepare_spm_tokenizer.py`
- Deduplicate and shard: `python3 scripts/dedupe_and_shard_corpus.py` (env AZME_SHARDS=N)
- Generate dataset manifest: `python3 scripts/generate_dataset_manifest.py`
- Profile hardware: `python3 scripts/hw_profile.py`

All-in-one preparation (runs all of the above safely, no training):
`python3 scripts/prepare_all.py`


