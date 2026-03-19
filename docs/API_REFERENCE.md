# AZL API Reference

Auto-generated from component definitions. Run `bash scripts/generate_api_reference.sh` to update.

## ::api.training_endpoints

**File:** `azl/api/endpoints.azl`

### Events emitted
- `api.build`
- `api.command`
- `api.metrics.consciousness`
- `api.metrics.lha3`
- `api.plugins.disable`
- `api.plugins.enable`
- `api.plugins.list`
- `api.plugins.register`
- `api.plugins.unregister`
- `api.response`
- `api.train.configure`
- `api.train.control`
- `api.train.parallel.start`
- `api.train.parallel.status`
- `api.train.start`
- `api.train.status`
- `api.train.toggle.device`
- `api.train.toggle.hybrid`
- `attempt_recovery`
- `azme.check_permission`
- `azme.respond_with_voice`
- `azme.set_hybrid_config`
- `build_project`
- `daemon.enterprise.build`
- `get_quantum_memory_stats`
- `get_training_status`
- `http.server.add_route`
- `http.server.start`
- `log_error`
- `maybe_checkpoint`
- `metrics.configure`
- `orchestrator.quantum.tick`
- `pause_training`
- `process_command`
- `process_image`
- `process_message`
- `quantum.measure.check`
- `quantum.metrics`
- `read_file`
- `resume_training`
- `runtime`
- `runtime.command`
- `runtime.train.advanced`
- `set_training_config`
- `start_http_server`
- `stop_training`
- `training.parallel.start`
- `training.plugins.disable`
- `training.plugins.enable`
- `training.plugins.list`
- `training.plugins.register`
- `training.plugins.unregister`

### Events listened
- `api.build`
- `api.command`
- `api.metrics.consciousness`
- `api.metrics.lha3`
- `api.plugins.disable`
- `api.plugins.enable`
- `api.plugins.list`
- `api.plugins.register`
- `api.plugins.unregister`
- `api.response`
- `api.train.configure`
- `api.train.control`
- `api.train.parallel.start`
- `api.train.parallel.status`
- `api.train.start`
- `api.train.status`
- `api.train.toggle.device`
- `api.train.toggle.hybrid`
- `azme.chat.response_generated`
- `azme.permission_result`
- `daemon.enterprise.ready`
- `file_read`
- `http.server.started`
- `initialize_chat_interface`
- `memory.quantum_stats.retrieved`
- `start_http_server`
- `training.plugins.response`
- `training.status`

