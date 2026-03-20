#!/usr/bin/env node
/**
 * Node entrypoint for launchers that still invoke `scripts/azl_runtime.js`.
 * Delegates to the canonical semantic spine host (same contract as
 * `scripts/azl_azl_interpreter_runtime.sh` → `tools/azl_runtime_spine_host.py`).
 *
 * ESM: parent directories may set `"type": "module"`; this file must parse as ESM.
 *
 * Required env (validated by the Python host): AZL_COMBINED_PATH, AZL_ENTRY.
 *
 * Exit codes: inherit from Python host (71–73 documented there); 68 spawn
 * failure; 70 missing host script.
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const rootDir = path.resolve(__dirname, '..');
const hostPy = path.join(rootDir, 'tools', 'azl_runtime_spine_host.py');

function emitError(obj) {
  console.error(JSON.stringify(obj));
}

if (!fs.existsSync(hostPy)) {
  emitError({
    type: 'ERR_AZL_RUNTIME_HOST_MISSING',
    message: 'tools/azl_runtime_spine_host.py not found',
    path: hostPy,
  });
  process.exit(70);
}

const pyBin = process.env.AZL_PYTHON3 || 'python3';
const env = { ...process.env };
const toolsPath = path.join(rootDir, 'tools');
if (env.PYTHONPATH) {
  env.PYTHONPATH = `${toolsPath}${path.delimiter}${env.PYTHONPATH}`;
} else {
  env.PYTHONPATH = toolsPath;
}
if (env.AZL_INTERPRETER_DAEMON === undefined) {
  env.AZL_INTERPRETER_DAEMON = '1';
}

const result = spawnSync(pyBin, [hostPy], {
  cwd: rootDir,
  env,
  stdio: 'inherit',
});

if (result.error) {
  emitError({
    type: 'ERR_AZL_RUNTIME_SPAWN_FAILED',
    message: result.error.message,
    syscall: result.error.syscall,
    code: result.error.code,
  });
  process.exit(68);
}

if (result.signal) {
  emitError({
    type: 'ERR_AZL_RUNTIME_SIGNAL',
    signal: result.signal,
  });
  process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);
