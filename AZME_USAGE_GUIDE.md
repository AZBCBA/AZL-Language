# AZME Usage Guide - Pure AZL Implementation

## 🚀 What is AZME?

AZME (Advanced Zonal Machine Environment) is a pure AZL implementation of an agent-based system that allows you to:

- **🤖 Spawn Agents**: Create autonomous agents with specific behaviors
- **📨 Send Messages**: Communicate between agents asynchronously
- **❓ Ask/Reply**: Request-reply pattern with correlation tracking
- **📊 Monitor Stats**: Track system performance and activity

## 🎯 Quick Start

### 1. Basic AZME Usage

```azl
# Start AZME runtime
component ::my_azme_app {
  init {
    say "🚀 Starting AZME application..."
    emit start_azme
  }

  behavior {
    # Start AZME
    listen for "start_azme" then {
      # Spawn a calculator agent
      emit azme.spawn with "calculator" "calculator_behavior"
      
      # Send a calculation request
      emit azme.ask with "coordinator" "calculator" "add" [5, 3]
    }
    
    # Handle agent spawned
    listen for "agent.spawned" then {
      set ::agent_id = $1
      say "✅ Agent spawned: ::agent_id"
    }
    
    # Handle replies
    listen for "reply.sent" then {
      set ::correlation_id = $1
      say "💬 Reply received: ::correlation_id"
    }
  }
}
```

### 2. Agent Behaviors

```azl
# Calculator Agent
component ::calculator_behavior {
  init {
    say "🧮 Calculator agent ready"
  }

  behavior {
    # Handle add operation
    listen for "process_ask" then {
      set ::ask = $1
      
      if ::ask.kind == "add" {
        set ::numbers = ::ask.payload
        set ::result = ::numbers[0] + ::numbers[1]
        
        say "🧮 Calculator: ::numbers[0] + ::numbers[1] = ::result"
        
        # Reply with result
        emit azme.reply with ::ask.correlation ::result
      }
    }
  }
}
```

## 🤖 Agent Operations

### Spawning Agents

```azl
# Spawn an agent with behavior
emit azme.spawn with "agent_id" "behavior_name"

# Example: Spawn a calculator agent
emit azme.spawn with "calc1" "calculator_behavior"
```

### Sending Messages

```azl
# Send a message from one agent to another
emit azme.send with "from_agent" "to_agent" "message_kind" "payload"

# Example: Send a greeting
emit azme.send with "coordinator" "greeter" "greet" "Hello!"
```

### Ask/Reply Pattern

```azl
# Ask an agent for a response
emit azme.ask with "from_agent" "to_agent" "ask_kind" "payload"

# Example: Ask calculator to add numbers
emit azme.ask with "coordinator" "calculator" "add" [5, 3]

# Handle the reply
listen for "reply.sent" then {
  set ::correlation_id = $1
  say "💬 Reply received: ::correlation_id"
}
```

### Getting Statistics

```azl
# Get AZME runtime statistics
emit azme.stats

# Handle stats response
listen for "stats.ready" then {
  set ::stats = $1
  say "📊 Agents: ::stats.agents"
  say "📨 Messages: ::stats.messages"
  say "❓ Correlations: ::stats.correlations"
}
```

## 🎭 Agent Behavior Patterns

### 1. Message Processing

```azl
component ::my_agent {
  behavior {
    # Process incoming messages
    listen for "process_message" then {
      set ::message = $1
      
      if ::message.kind == "task" {
        # Handle task
        say "📋 Processing task: ::message.payload"
      } else if ::message.kind == "greet" {
        # Handle greeting
        say "👋 Greeting: ::message.payload"
      }
    }
  }
}
```

### 2. Ask Processing

```azl
component ::my_agent {
  behavior {
    # Process incoming asks
    listen for "process_ask" then {
      set ::ask = $1
      
      if ::ask.kind == "calculate" {
        set ::result = ::perform_calculation(::ask.payload)
        emit azme.reply with ::ask.correlation ::result
      }
    }
  }
}
```

### 3. Event-Driven Behavior

```azl
component ::my_agent {
  behavior {
    # Listen for specific events
    listen for "data_ready" then {
      set ::data = $1
      say "📊 Data ready: ::data"
      
      # Process data and send result
      set ::result = ::process_data(::data)
      emit azme.send with "my_agent" "coordinator" "result" ::result
    }
  }
}
```

## 🔄 Common Patterns

### 1. Coordinator Pattern

```azl
component ::coordinator {
  behavior {
    # Coordinate multiple agents
    listen for "start_task" then {
      # Spawn workers
      emit azme.spawn with "worker1" "worker_behavior"
      emit azme.spawn with "worker2" "worker_behavior"
      
      # Distribute work
      emit azme.send with "coordinator" "worker1" "task" "task1"
      emit azme.send with "coordinator" "worker2" "task" "task2"
    }
    
    # Collect results
    listen for "process_message" then {
      set ::message = $1
      if ::message.kind == "result" {
        say "📊 Received result: ::message.payload"
      }
    }
  }
}
```

### 2. Pipeline Pattern

```azl
component ::pipeline {
  behavior {
    # Process data through pipeline
    listen for "process_data" then {
      set ::data = $1
      
      # Stage 1: Validate
      emit azme.ask with "pipeline" "validator" "validate" ::data
    }
    
    # Handle validation result
    listen for "reply.sent" then {
      set ::correlation_id = $1
      if ::correlation_id.starts_with("validate") {
        # Stage 2: Transform
        emit azme.ask with "pipeline" "transformer" "transform" ::data
      }
    }
  }
}
```

### 3. Pub/Sub Pattern

```azl
component ::publisher {
  behavior {
    # Publish events
    listen for "publish_event" then {
      set ::event = $1
      emit azme.send with "publisher" "subscriber1" "event" ::event
      emit azme.send with "publisher" "subscriber2" "event" ::event
    }
  }
}

component ::subscriber {
  behavior {
    # Subscribe to events
    listen for "process_message" then {
      set ::message = $1
      if ::message.kind == "event" {
        say "📡 Received event: ::message.payload"
      }
    }
  }
}
```

## 📊 Monitoring and Debugging

### 1. Enable Debug Mode

```azl
component ::debug_monitor {
  behavior {
    # Monitor all AZME events
    listen for "agent.spawned" then {
      say "🐛 DEBUG: Agent spawned: $1"
    }
    
    listen for "message.sent" then {
      set ::message = $1
      say "🐛 DEBUG: Message: ::message.from -> ::message.to"
    }
    
    listen for "ask.sent" then {
      say "🐛 DEBUG: Ask sent: $1"
    }
  }
}
```

### 2. Performance Monitoring

```azl
component ::performance_monitor {
  behavior {
    # Monitor performance
    listen for "stats.ready" then {
      set ::stats = $1
      say "📈 Performance:"
      say "  🤖 Active agents: ::stats.agents"
      say "  📨 Messages/sec: ::stats.messages"
      say "  ❓ Active correlations: ::stats.correlations"
    }
  }
}
```

## 🚀 Advanced Usage

### 1. Custom Agent Types

```azl
# Define custom agent behavior
component ::custom_agent_behavior {
  init {
    set ::agent_type = "custom"
    set ::capabilities = ["process", "analyze", "respond"]
  }

  behavior {
    # Custom behavior implementation
    listen for "process_message" then {
      set ::message = $1
      set ::result = ::custom_processing(::message.payload)
      emit azme.send with "custom_agent" ::message.from "result" ::result
    }
  }

  memory {
    ::custom_processing = (data) => {
      # Custom processing logic
      return "Processed: " + ::data
    }
  }
}
```

### 2. Agent Composition

```azl
# Compose multiple behaviors
component ::composite_agent {
  init {
    # Link to multiple behaviors
    link ::calculator_behavior
    link ::greeter_behavior
    link ::analyzer_behavior
  }

  behavior {
    # Route messages to appropriate behavior
    listen for "process_message" then {
      set ::message = $1
      
      if ::message.kind == "calculate" {
        emit calculator.process with ::message
      } else if ::message.kind == "greet" {
        emit greeter.process with ::message
      } else if ::message.kind == "analyze" {
        emit analyzer.process with ::message
      }
    }
  }
}
```

## 🎯 Best Practices

1. **Agent Naming**: Use descriptive names for agents (e.g., `calculator`, `greeter`, `coordinator`)
2. **Message Types**: Use clear, descriptive message kinds (e.g., `calculate`, `greet`, `analyze`)
3. **Error Handling**: Always handle potential errors in agent behaviors
4. **Resource Management**: Clean up resources when agents are no longer needed
5. **Monitoring**: Use the stats system to monitor system health
6. **Testing**: Test agent behaviors individually before composing them

## 🔧 Troubleshooting

### Common Issues

1. **Agent not responding**: Check if agent was spawned successfully
2. **Message not delivered**: Verify agent ID and message format
3. **Reply not received**: Check correlation ID and ask format
4. **Performance issues**: Monitor stats and optimize agent behaviors

### Debug Commands

```azl
# Get system status
emit azme.stats

# Check agent status
emit azme.status

# Monitor events
listen for "agent.spawned" then { say "Agent: $1" }
listen for "message.sent" then { say "Message: $1" }
listen for "reply.sent" then { say "Reply: $1" }
```

## 🎉 Conclusion

AZME in pure AZL provides a powerful, self-hosting agent system that runs entirely without Rust dependencies. You can now build complex, distributed applications using only AZL code!

For more examples, see `azme_example.azl` in the project root.
