# AZME Production Operations Runbook

## Overview

This runbook provides operational guidelines for running the AZME bridge in production environments. The bridge provides a robust messaging system for AZL agents with stateful VMs, backpressure handling, and comprehensive error management.

**🚨 PRODUCTION RUNBOOK WARNING:**
- **THEORETICAL RUNBOOK**: Most features described in this runbook DO NOT EXIST in current implementation
- **NOT PRODUCTION READY**: AZME bridge architecture described is not implemented
- **MISSING COMPONENTS**: Stateful VMs, bounded mailboxes, supervision & recovery are NOT IMPLEMENTED
- **PLACEHOLDER CONFIGURATIONS**: Environment variables and settings described may not work
- **OPERATIONAL RISK**: Following this runbook may lead to system failures

## Architecture

```
AZME Kernel
├── Agent Registry (HashMap<AgentId, AgentHandle>)
├── Stateful VMs (one per agent)
├── Bounded Mailboxes (configurable capacity)
├── Pending Request Tracking
├── Performance Monitoring
└── Supervision & Recovery
```

## Key Features

### 1. Backpressure & Safety
- **Bounded Mailboxes**: Default 1024 messages per agent
- **Overload Policies**: DropOldest, DropNew, Error
- **Cancellation Support**: Cancel pending requests
- **Timeout Protection**: Configurable timeouts per request

### 2. Stateful Agents
- **Per-Agent VMs**: Each agent maintains its own VM instance
- **Persistent State**: State survives across message processing
- **Isolation**: Agents cannot interfere with each other

### 3. Performance Controls
- **Step Limits**: 10M steps per call (configurable)
- **Time Limits**: 2s per call (configurable)
- **Heap Limits**: 64MB per call (configurable)
- **Cooperative Yielding**: Prevents executor hogging

### 4. Observability
- **Agent Stats**: Inbox length, handled/failed counts, latency
- **Structured Errors**: JSON error responses with stack traces
- **Correlation Tracking**: Request/response matching
- **Performance Monitoring**: Per-call timing and limits

## Configuration

### Environment Variables

```bash
# Mailbox configuration
AZME_MAILBOX_CAP=1024
AZME_OVERLOAD_POLICY=error  # drop_oldest, drop_new, error

# Performance limits
AZME_STEP_LIMIT=10000000
AZME_TIME_LIMIT_MS=2000
AZME_HEAP_LIMIT_B=67108864  # 64MB

# Supervision
AZME_SUPERVISION_ENABLED=true
AZME_RESTART_BACKOFF_MS=100
AZME_MAX_RESTART_BACKOFF_MS=10000
```

### Agent Spawning Options

```azl
// Basic spawn
azme.spawn("agent_id", handler_function);

// Spawn with options
azme.spawn_opts("agent_id", handler_function, to_json({
    mailbox: 2048,
    overload: "drop_oldest"  // drop_oldest, drop_new, error
}));
```

## Monitoring

### Key Metrics

1. **Agent Health**
   - Inbox length per agent
   - Handled/failed message counts
   - Average and P95 latency
   - Restart count

2. **System Health**
   - Total active agents
   - Total pending requests
   - Mailbox saturation
   - Error rates

3. **Performance**
   - Step limit violations
   - Time limit violations
   - Heap limit violations
   - Cancellation rates

### Stats API

```azl
// Get system stats
let stats = azme.stats();
print("System stats: " + stats);

// Example response:
// [
//   {
//     "id": "agent1",
//     "inbox": 5,
//     "handled": 1000,
//     "failed": 2,
//     "latency_ms": { "avg": 15.5, "p95": 45.2 }
//   }
// ]
```

## Alerting

### Critical Alerts

1. **High Error Rate**
   - Alert when failed/handled ratio > 5%
   - Check agent logs for root cause

2. **Mailbox Saturation**
   - Alert when inbox length > 80% of capacity
   - Consider scaling or backpressure policy

3. **Restart Storm**
   - Alert when agent restarts > 10 times in 5 minutes
   - Check for infinite loops or resource exhaustion

4. **Performance Degradation**
   - Alert when P95 latency > 1000ms
   - Check for resource contention

### Warning Alerts

1. **High Latency**
   - Warning when P95 latency > 500ms
   - Monitor trend

2. **Memory Usage**
   - Warning when heap usage > 80% of limit
   - Consider increasing limits

3. **Cancellation Rate**
   - Warning when cancellation rate > 10%
   - Check for client timeouts

## Troubleshooting

### Common Issues

#### 1. Agent Not Responding

**Symptoms**: Timeout errors, high inbox length
**Diagnosis**:
```azl
// Check agent stats
let stats = azme.stats();
print("Agent stats: " + stats);

// Check if agent exists
azme.send("main", "problematic_agent", "ping", to_json({}));
```

**Solutions**:
- Restart the agent
- Check for infinite loops
- Increase time limits if needed
- Check resource usage

#### 2. High Memory Usage

**Symptoms**: Heap limit violations, slow performance
**Diagnosis**:
```azl
// Check memory usage in agent
fn memory_test(env) {
    let large_array = [];
    for i in 0..1000000 {
        large_array.push(i);
    }
    return to_json({ size: large_array.length });
}
```

**Solutions**:
- Increase heap limits
- Optimize agent code
- Implement garbage collection
- Use streaming for large data

#### 3. Message Loss

**Symptoms**: Missing responses, correlation mismatches
**Diagnosis**:
```azl
// Check pending requests
let correlation = "test_123";
azme.send("agent", "agent", "test", to_json({ correlation: correlation }));
let cancelled = azme.cancel(correlation);
print("Cancelled: " + cancelled);
```

**Solutions**:
- Check overload policy
- Increase mailbox capacity
- Implement retry logic
- Monitor correlation tracking

#### 4. Performance Issues

**Symptoms**: High latency, step limit violations
**Diagnosis**:
```azl
// Test performance limits
fn perf_test(env) {
    let start = time();
    // Heavy computation
    let result = heavy_computation();
    let duration = time() - start;
    return to_json({ duration: duration, result: result });
}
```

**Solutions**:
- Optimize agent code
- Increase step/time limits
- Use cooperative yielding
- Implement caching

### Debugging Commands

```azl
// Get detailed stats
let stats = azme.stats();
print("Detailed stats: " + stats);

// Test agent connectivity
azme.send("debug", "target_agent", "ping", to_json({}));

// Cancel problematic requests
azme.cancel("correlation_id");

// Test backpressure
for i in 0..1000 {
    azme.send("main", "test_agent", "stress", to_json({ id: i }));
}
```

## Deployment

### Production Checklist

- [ ] Set appropriate mailbox capacities
- [ ] Configure overload policies
- [ ] Set performance limits
- [ ] Enable supervision
- [ ] Configure monitoring
- [ ] Set up alerting
- [ ] Test error scenarios
- [ ] Validate performance
- [ ] Document agent interfaces
- [ ] Set up logging

### Scaling Guidelines

1. **Horizontal Scaling**
   - Deploy multiple AZME instances
   - Use load balancer for agent distribution
   - Implement agent migration

2. **Vertical Scaling**
   - Increase mailbox capacities
   - Adjust performance limits
   - Add more VM resources

3. **Resource Planning**
   - Monitor memory usage per agent
   - Track CPU usage patterns
   - Plan for peak loads

## Security

### Best Practices

1. **Agent Isolation**
   - Each agent runs in its own VM
   - No shared state between agents
   - Resource limits per agent

2. **Input Validation**
   - Validate all message payloads
   - Sanitize agent inputs
   - Implement rate limiting

3. **Error Handling**
   - Never expose internal errors
   - Log security events
   - Implement audit trails

### Security Monitoring

```azl
// Monitor for suspicious activity
fn security_monitor(env) {
    if env.payload.size > 1000000 {
        log("Large payload detected: " + env.from);
        return to_json({ error: "payload_too_large" });
    }
    return to_json({ status: "ok" });
}
```

## Maintenance

### Regular Tasks

1. **Health Checks**
   - Daily stats review
   - Weekly performance analysis
   - Monthly capacity planning

2. **Cleanup**
   - Remove inactive agents
   - Clear old correlations
   - Archive old logs

3. **Updates**
   - Monitor for updates
   - Test in staging
   - Plan maintenance windows

### Backup & Recovery

1. **Agent State**
   - Implement state snapshots
   - Backup agent configurations
   - Test recovery procedures

2. **System State**
   - Backup registry state
   - Export agent stats
   - Document recovery steps

## Support

### Getting Help

1. **Documentation**: Check this runbook first
2. **Logs**: Review agent and system logs
3. **Stats**: Use `azme.stats()` for diagnostics
4. **Community**: Check GitHub issues
5. **Escalation**: Contact the AZME team

### Emergency Procedures

1. **System Down**
   - Restart AZME kernel
   - Check resource usage
   - Review recent changes

2. **Data Loss**
   - Check backup state
   - Restore from snapshots
   - Recreate missing agents

3. **Performance Crisis**
   - Reduce mailbox capacities
   - Increase limits temporarily
   - Scale horizontally

---

*Last updated: [Current Date]*
*Version: 1.0*
