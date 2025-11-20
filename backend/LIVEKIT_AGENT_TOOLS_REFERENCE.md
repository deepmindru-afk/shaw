# LiveKit Agent Tools - Comprehensive Reference

## Overview

LiveKit Agents support powerful tool calling capabilities that enable AI agents to:
- Execute custom functions
- Communicate with backend APIs
- Call frontend methods via RPC
- Hand off between multiple agents
- Manage state and session data
- Control conversation flow

---

## 1. Tool Definition Methods

### Python: Decorator-Based

```python
from livekit.agents import function_tool, Agent, RunContext

class MyAgent(Agent):
    @function_tool()
    async def lookup_weather(
        self,
        context: RunContext,
        location: str,
    ) -> dict[str, Any]:
        """Look up weather information for a location."""
        return {"weather": "sunny", "temperature_f": 70}
```

### Node.js: Function-Based with Zod

```typescript
import { voice, llm } from '@livekit/agents';
import { z } from 'zod';

const lookupWeather = llm.tool({
  description: 'Look up weather information',
  parameters: z.object({
    location: z.string()
  }),
  execute: async ({ location }, { ctx }) => {
    return { weather: "sunny", temperatureF: 70 };
  },
});
```

### Raw Schema Definition (Advanced)

```python
raw_schema = {
    "type": "function",
    "name": "get_weather",
    "parameters": {
        "type": "object",
        "properties": {
            "location": {"type": "string"}
        },
        "required": ["location"]
    }
}

@function_tool(raw_schema=raw_schema)
async def get_weather(raw_arguments: dict, context: RunContext):
    location = raw_arguments["location"]
    return f"Weather for {location}..."
```

---

## 2. Execution Context (RunContext)

The `context` parameter provides access to:

| Property | Description |
|----------|-------------|
| `context.session` | Agent session for generating speech |
| `context.function_call` | Current function call metadata |
| `context.speech_handle` | Control over speech interruptions |
| `context.userdata` | Session-specific data storage |
| `context.room` | Access to the LiveKit room |

### Example: Using RunContext

```python
@function_tool()
async def save_user_preference(context: RunContext, preference: str):
    # Store in session userdata
    context.userdata["preference"] = preference
    
    # Generate agent speech
    await context.session.say(f"I've saved your preference: {preference}")
    
    return {"status": "saved", "value": preference}
```

---

## 3. Return Types & Behaviors

### Standard Returns
Returns are automatically converted to strings before LLM processing.

```python
@function_tool()
async def get_user_age(context: RunContext, user_id: str) -> int:
    return 25  # Converted to "25" for LLM
```

### Silent Completion
Return `None` to complete without LLM response.

```python
@function_tool()
async def log_event(context: RunContext, event: str):
    logger.info(event)
    return None  # No LLM response generated
```

### Agent Handoff (Python)

```python
@function_tool()
async def transfer_to_support(context: RunContext):
    return SupportAgent(), "Transferring to our support team..."
```

### Agent Handoff (Node.js)

```typescript
return llm.handoff({
  agent: new SupportAgent(),
  returns: 'Transferring to support...',
});
```

---

## 4. Error Handling

Use `ToolError` for user-friendly error messages:

```python
from livekit.agents import ToolError

@function_tool()
async def lookup_location(context: RunContext, location: str):
    if location == "mars":
        raise ToolError("Mars weather data is not available yet. Coming soon!")
    
    return await fetch_weather(location)
```

```typescript
if (location === "mars") {
  throw new llm.ToolError("Mars weather data is not available yet.");
}
```

---

## 5. Interruption Management

### Detect Interruptions

```python
@function_tool()
async def long_running_task(context: RunContext):
    task = asyncio.create_task(perform_calculation())
    
    # Wait and check for interruption
    await context.speech_handle.wait_if_not_interrupted([task])
    
    if context.speech_handle.interrupted:
        task.cancel()
        return None  # Silent cancellation
    
    return await task
```

### Disable Interruptions

```python
@function_tool()
async def submit_payment(context: RunContext, amount: float):
    # Prevent interruption for critical operations
    context.disallow_interruptions()
    
    result = await process_payment(amount)
    return {"transaction_id": result.id}
```

---

## 6. RPC: Frontend Integration

### Agent → Frontend Calls

```python
@function_tool()
async def get_user_location(context: RunContext, high_accuracy: bool):
    """Retrieve the user's current geolocation from frontend"""
    room = context.room
    participant_identity = next(iter(room.remote_participants))
    
    response = await room.local_participant.perform_rpc(
        destination_identity=participant_identity,
        method="getUserLocation",
        payload=json.dumps({"highAccuracy": high_accuracy}),
        response_timeout=10.0 if high_accuracy else 5.0,
    )
    
    location = json.loads(response)
    return location
```

### Frontend Handler (JavaScript)

```typescript
localParticipant.registerRpcMethod(
    'getUserLocation',
    async (data) => {
        const { highAccuracy } = JSON.parse(data.payload);
        const position = await navigator.geolocation.getCurrentPosition({
            enableHighAccuracy: highAccuracy
        });
        return JSON.stringify({
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
        });
    }
);
```

### Frontend → Agent Calls

```python
# Agent registers method
ctx.room.local_participant.register_rpc_method(
    "agent.get_state",
    handle_get_state
)

async def handle_get_state(rpc_data):
    payload = json.loads(rpc_data.caller_payload)
    state_id = payload.get("id")
    
    return json.dumps({
        "status": "success",
        "data": get_state(state_id)
    })
```

```typescript
// Frontend calls agent
const response = await localParticipant.performRpc({
    destinationIdentity: 'agent-identity',
    method: 'agent.get_state',
    payload: JSON.stringify({ id: '123' })
});
```

---

## 7. Dynamic Tool Management

### Add Tools After Creation

```python
# Python
await agent.update_tools(agent.tools + [new_tool])
```

```typescript
// Node.js
await agent.updateTools({ ...agent.toolCtx, newTool })
```

### Remove Tools

```python
# Python
await agent.update_tools(agent.tools - [tool_to_remove])
```

```typescript
// Node.js
const { toolToRemove, ...rest } = agent.toolCtx;
await agent.updateTools(rest)
```

### Temporal Tools (Per LLM Call)

```python
@function_tool()
async def specialized_task(context: RunContext):
    # Create temporary tool just for this invocation
    temp_tool = function_tool(some_function, name="temp_calculator")
    
    # Use it in a specific LLM call
    response = await context.session.generate_reply(
        tools=[temp_tool],
        instructions="Use the calculator"
    )
    
    return response
```

---

## 8. Programmatic Tool Creation

```python
def create_set_field_tool(field: str):
    async def set_value(context: RunContext, value: str):
        context.userdata[field] = value
        return f"field {field} was set to {value}"
    
    return function_tool(
        set_value,
        name=f"set_{field}",
        description=f"Set user {field}"
    )

# Create tools dynamically
phone_tool = create_set_field_tool("phone")
email_tool = create_set_field_tool("email")
address_tool = create_set_field_tool("address")

agent = MyAgent(tools=[phone_tool, email_tool, address_tool])
```

---

## 9. Real-World Tool Examples

### Example 1: Backend API Call

```python
@function_tool()
async def save_transcript_turn(
    context: RunContext,
    session_id: str,
    speaker: str,
    text: str
) -> dict:
    """Save a transcript turn to the backend database"""
    import httpx
    from datetime import datetime
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"https://api.example.com/sessions/{session_id}/transcript",
            json={
                "speaker": speaker,
                "text": text,
                "timestamp": datetime.utcnow().isoformat()
            },
            headers={"Authorization": f"Bearer {API_KEY}"}
        )
        
        if response.status_code == 200:
            return {"success": True}
        else:
            raise ToolError(f"Failed to save transcript: {response.text}")
```

### Example 2: Multi-Agent Restaurant System

```python
class GreeterAgent(Agent):
    @function_tool()
    async def to_reservation(self, context: RunContext):
        """Transfer to reservation department"""
        return ReservationAgent(), "I'll connect you to our reservation desk."
    
    @function_tool()
    async def to_takeaway(self, context: RunContext):
        """Transfer to food ordering"""
        return TakeawayAgent(), "Let me transfer you to place your order."

class ReservationAgent(Agent):
    @function_tool()
    async def update_reservation_time(
        self,
        context: RunContext,
        date: str,
        time: str,
        party_size: int
    ):
        """Record reservation details"""
        context.userdata["reservation"] = {
            "date": date,
            "time": time,
            "party_size": party_size
        }
        return {"status": "recorded"}
    
    @function_tool()
    async def confirm_reservation(self, context: RunContext):
        """Finalize the reservation"""
        reservation = context.userdata.get("reservation")
        if not reservation:
            raise ToolError("No reservation details found")
        
        # Save to backend
        result = await save_to_database(reservation)
        
        return CheckoutAgent(), f"Your reservation is confirmed for {reservation['date']} at {reservation['time']}."
```

### Example 3: Perplexity Web Search Tool

```python
@function_tool()
async def web_search(
    self,
    context: RunContext,
    query: str,
) -> str:
    """Search the web for current information using Perplexity.

    Args:
        query: The search query to look up current information, news, weather, traffic, or real-time facts

    Returns:
        A concise answer based on web search results
    """
    try:
        api_key = os.getenv('PERPLEXITY_API_KEY')
        if not api_key:
            logger.error("PERPLEXITY_API_KEY not found")
            return "Search unavailable: API key not configured"

        logger.info(f"🔍 Perplexity search: {query}")

        async with aiohttp.ClientSession() as session:
            async with session.post(
                'https://api.perplexity.ai/chat/completions',
                headers={
                    'Authorization': f'Bearer {api_key}',
                    'Content-Type': 'application/json'
                },
                json={
                    'model': 'llama-3.1-sonar-small-128k-online',
                    'messages': [
                        {
                            'role': 'system',
                            'content': 'Provide concise, factual answers suitable for voice interaction while driving. Keep responses under 3 sentences for safety.'
                        },
                        {
                            'role': 'user',
                            'content': query
                        }
                    ],
                    'temperature': 0.2,
                    'max_tokens': 200,
                },
                timeout=aiohttp.ClientTimeout(total=10)
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    result = data['choices'][0]['message']['content']
                    logger.info(f"✅ Perplexity result: {result[:100]}...")
                    return result
                else:
                    error_text = await response.text()
                    logger.error(f"❌ Perplexity API error: {response.status} - {error_text}")
                    return "I'm having trouble searching the web right now."
    except Exception as e:
        logger.error(f"❌ Web search error: {e}")
        return "Search is temporarily unavailable."
```

### Example 4: CarPlay Navigation Tool

```python
@function_tool()
async def show_navigation(
    context: RunContext,
    destination: str,
    use_traffic: bool = True
) -> dict:
    """Display navigation on CarPlay screen"""
    room = context.room
    participant = next(iter(room.remote_participants))

    try:
        response = await room.local_participant.perform_rpc(
            destination_identity=participant.identity,
            method="startNavigation",
            payload=json.dumps({
                "destination": destination,
                "useTrafficData": use_traffic
            }),
            response_timeout=5.0
        )

        result = json.loads(response)

        await context.session.say(
            f"Navigation started to {destination}. "
            f"Estimated arrival in {result['eta_minutes']} minutes."
        )

        return result

    except Exception as e:
        raise ToolError(f"Failed to start navigation: {str(e)}")
```

---

## 10. Session Control Within Tools

Tools can control agent speech during execution:

```python
@function_tool()
async def multi_step_booking(context: RunContext, flight_id: str):
    """Book a flight with multiple confirmations"""
    
    # Step 1: Check availability
    await context.session.say("Checking flight availability...")
    available = await check_flight(flight_id)
    
    if not available:
        return None  # Silent return, already said it
    
    # Step 2: Reserve seat
    await context.session.say("Reserving your seat...")
    seat = await reserve_seat(flight_id)
    
    # Step 3: Process payment
    await context.session.say("Processing payment...")
    payment = await process_payment()
    
    # Step 4: Confirm
    await context.session.generate_reply(
        instructions=f"Confirm the booking with seat {seat} and provide the confirmation number {payment.confirmation}"
    )
    
    return {"booking_id": payment.confirmation, "seat": seat}
```

---

## 11. Model Context Protocol (MCP)

Load tools from external MCP servers:

```python
from livekit.agents import mcp

agent = Agent(
    mcp_servers=[
        mcp.MCPServerHTTP("https://tools.example.com"),
        mcp.MCPServerHTTP("https://integration-tools.example.com")
    ]
)
```

This allows loading pre-built tool ecosystems from third-party providers.

---

## 12. Best Practices

### ✅ DO:
- Keep tool descriptions clear and concise
- Use type hints for better LLM understanding
- Handle errors gracefully with ToolError
- Use silent returns (None) when appropriate
- Validate user input before processing
- Use context.userdata for session state
- Implement proper timeout handling for RPC calls

### ❌ DON'T:
- Don't perform long-running operations without interruption handling
- Don't forget to finish critical operations (use disallow_interruptions)
- Don't expose sensitive data in tool responses
- Don't create tools with side effects that can't be undone
- Don't rely on global state (use context.userdata instead)

### Security Considerations:
- Validate all inputs
- Rate limit API calls
- Sanitize user-provided data
- Use environment variables for secrets
- Implement proper authentication for RPC calls
- Log security-relevant tool executions

---

## 13. Debugging Tools

### Logging Tool Execution

```python
import logging
logger = logging.getLogger(__name__)

@function_tool()
async def debug_tool(context: RunContext, action: str):
    logger.info(f"Tool called: action={action}")
    logger.debug(f"Session userdata: {context.userdata}")
    logger.debug(f"Function call metadata: {context.function_call}")
    
    result = await perform_action(action)
    
    logger.info(f"Tool result: {result}")
    return result
```

### Error Tracking

```python
@function_tool()
async def monitored_tool(context: RunContext):
    try:
        result = await risky_operation()
        return result
    except Exception as e:
        # Log to monitoring service
        await send_to_sentry(e, context={
            "user_id": context.userdata.get("user_id"),
            "session_id": context.session.id
        })
        raise ToolError(f"Operation failed: {str(e)}")
```

---

## Resources

- **Documentation**: https://docs.livekit.io/agents/build/tools/
- **Examples Repository**: https://github.com/livekit-examples/python-agents-examples
- **Main Agents Repo**: https://github.com/livekit/agents
- **RPC Documentation**: https://docs.livekit.io/home/client/data/rpc/

---

**Generated for Roadtrip AI CarPlay Assistant**  
Last Updated: 2025-01-11
