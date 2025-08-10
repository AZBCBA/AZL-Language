# AZL Enterprise Build System - Production Setup Guide

## Overview
The AZL Enterprise Build System is a pure AZL implementation providing:
- Long-lived build daemon with isolated worker pools
- File watching with intelligent change detection
- Resource management and backpressure
- Build history and analytics
- REST API for external tooling integration

## Quick Start (One-liner)

```bash
# Generate API token and start daemon
export AZL_API_TOKEN=$(openssl rand -hex 32) && \
./scripts/azl-buildd config/prod.azl.json
```

## Step-by-Step Setup

### 1. Verify Repository Structure
Ensure you have the required components:
```
azl-language/
├── azl/build/build_daemon_enterprise.azl    # Enterprise daemon
├── azl/build/build_orchestrator.azl         # Build orchestrator
├── azl/build/worker_pool.azl                # Worker pool management
├── azl/build/cache_manager.azl              # Cache management
├── config/prod.azl.json                     # Production config
├── scripts/azl-buildd                       # Daemon launcher
└── scripts/azl                              # AZL CLI
```

### 2. Build the Daemon
The daemon is already implemented in pure AZL, so no compilation step is needed.

### 3. Configure Production Settings
The production config is already created at `config/prod.azl.json` with:
- API server on port 8080
- Content-addressed caching
- Worker isolation and limits
- Analytics and monitoring
- File watching enabled

### 4. Start the Daemon

#### Option A: Foreground Mode (Development)
```bash
# Generate API token
export AZL_API_TOKEN=$(openssl rand -hex 32)

# Start daemon
./scripts/azl-buildd config/prod.azl.json
```

#### Option B: Background Mode (Production)
```bash
# Start as background daemon
./scripts/azl-buildd config/prod.azl.json --daemon

# Check status
ps aux | grep azl-buildd
cat .azl/daemon.log
```

#### Option C: Systemd Service (Production)
```bash
# Copy service file
sudo cp deployment/systemd/azl-buildd.service /etc/systemd/system/

# Generate token and enable service
export AZL_API_TOKEN=$(openssl rand -hex 32)
sudo systemctl daemon-reload
sudo systemctl enable azl-buildd@$AZL_API_TOKEN
sudo systemctl start azl-buildd@$AZL_API_TOKEN

# Check status
sudo systemctl status azl-buildd@$AZL_API_TOKEN
```

### 5. Verify Daemon is Running

#### Health Checks
```bash
# Check if daemon is responding
curl -fsS http://localhost:8080/healthz
curl -fsS http://localhost:8080/readyz

# Check API with token
curl -H "Authorization: Bearer $AZL_API_TOKEN" \
     http://localhost:8080/status
```

#### Test Build System
```bash
# Run comprehensive test
./scripts/azl run scripts/test-build-system.azl
```

### 6. Use the Build System

#### Via REST API
```bash
# Start a build
curl -H "Authorization: Bearer $AZL_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "files": ["azl/core/error_system.azl"],
       "options": {
         "backend": "bytecode",
         "workers": 4,
         "incremental": true
       }
     }' \
     http://localhost:8080/build

# Check build status (replace <build_id> with returned ID)
curl -H "Authorization: Bearer $AZL_API_TOKEN" \
     http://localhost:8080/status/<build_id>
```

#### Via AZL CLI
```bash
# Build specific files
./scripts/azl build azl/core/error_system.azl --workers 4

# Build entire project
./scripts/azl build azl/ --workers 8
```

### 7. Monitor and Analytics

#### View Metrics
```bash
# Check analytics endpoint
curl -H "Authorization: Bearer $AZL_API_TOKEN" \
     http://localhost:8080/analytics

# View metrics file
tail -f .azl/metrics.ndjson
```

#### Monitor Resources
```bash
# Check daemon logs
tail -f .azl/daemon.log

# Monitor cache usage
du -sh .azl/cache

# Check worker utilization
curl -H "Authorization: Bearer $AZL_API_TOKEN" \
     http://localhost:8080/workers/status
```

## Configuration Options

### Production Config (`config/prod.azl.json`)
```json
{
  "mode": "production",
  "orchestrator": { 
    "concurrency": { "min": 2, "max": 32 } 
  },
  "workers": {
    "isolation": "process",
    "limits": { "cpu_percent": 85, "rss_mb": 2048 }
  },
  "cache": {
    "type": "content_addressed",
    "path": ".azl/cache",
    "eviction": { "strategy": "lru", "target_gb": 50 }
  },
  "api": {
    "bind": "0.0.0.0:8080",
    "auth": { "type": "token", "env": "AZL_API_TOKEN" }
  }
}
```

### Environment Variables
- `AZL_API_TOKEN`: Authentication token
- `AZL_BUILD_CONFIG`: Config file path
- `AZL_BUILD_API_PORT`: API server port
- `AZL_BUILD_MAX_CONCURRENT`: Max concurrent builds
- `AZL_BUILD_MAX_MEMORY`: Memory limit in bytes
- `AZL_BUILD_MAX_CPU`: CPU usage limit percentage

## Troubleshooting

### Common Issues

#### Daemon Won't Start
```bash
# Check logs
cat .azl/daemon.log

# Verify dependencies
ls -la azl/build/build_daemon_enterprise.azl

# Check permissions
chmod +x scripts/azl-buildd
```

#### API Not Responding
```bash
# Check if port is in use
netstat -tlnp | grep 8080

# Verify token is set
echo $AZL_API_TOKEN

# Test with curl
curl -v http://localhost:8080/healthz
```

#### Build Failures
```bash
# Check build logs
tail -f .azl/daemon.log

# Verify file paths
ls -la azl/core/error_system.azl

# Check cache
ls -la .azl/cache/
```

### Performance Tuning

#### Increase Concurrency
```json
{
  "orchestrator": { 
    "concurrency": { "min": 4, "max": 64 } 
  }
}
```

#### Adjust Memory Limits
```json
{
  "workers": {
    "limits": { "cpu_percent": 90, "rss_mb": 4096 }
  }
}
```

#### Optimize Cache
```json
{
  "cache": {
    "eviction": { "strategy": "lru", "target_gb": 100 }
  }
}
```

## Security Considerations

1. **API Token**: Use a strong, randomly generated token
2. **Network Access**: Configure firewall rules for port 8080
3. **File Permissions**: Ensure proper ownership and permissions
4. **Resource Limits**: Set appropriate memory and CPU limits
5. **Logging**: Monitor logs for suspicious activity

## Production Deployment Checklist

- [ ] Daemon starts successfully
- [ ] Health checks return 200
- [ ] API authentication works
- [ ] Build requests are accepted
- [ ] Cache directory is populated
- [ ] Metrics are being collected
- [ ] Logs are being written
- [ ] Resource limits are enforced
- [ ] Systemd service is enabled (if using)
- [ ] Firewall rules are configured
- [ ] Monitoring is set up

## Support

For issues or questions:
1. Check the logs in `.azl/daemon.log`
2. Verify configuration in `config/prod.azl.json`
3. Test with the provided test script
4. Review the troubleshooting section above
