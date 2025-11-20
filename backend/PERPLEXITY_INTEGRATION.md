# Perplexity Web Search Integration

## Overview

Added Perplexity web search as a tool call capability to the Roadtrip AI CarPlay assistant. The agent can now search the web for current information when users ask questions about news, weather, traffic, events, or real-time facts.

## Implementation

### 1. Agent Configuration ([agent.py:19-82](backend/agent.py#L19-L82))

```python
class Assistant(Agent):
    def __init__(self) -> None:
        super().__init__(
            instructions="...When users ask questions requiring current information (news, weather, traffic, events, facts), use the web_search tool."
        )

    @function_tool()
    async def web_search(
        self,
        context: RunContext,
        query: str,
    ) -> str:
        """Search the web for current information using Perplexity."""
        # Implementation uses Perplexity API with llama-3.1-sonar-small-128k-online model
```

### 2. Key Features

- **Model**: `llama-3.1-sonar-small-128k-online` (Perplexity's search-enabled Sonar model)
- **Safety**: Responses limited to 3 sentences for driving safety
- **Timeout**: 10 second timeout for API calls
- **Temperature**: 0.2 for factual, consistent responses
- **Max Tokens**: 200 to keep responses concise
- **Logging**: Full logging of queries and results

### 3. Error Handling

- Missing API key detection
- Graceful failure with user-friendly messages
- HTTP error logging
- Exception handling with fallback responses

## Setup

Add to `backend/.env`:

```bash
PERPLEXITY_API_KEY=your_api_key_here
```

Get your API key from: https://www.perplexity.ai/settings/api

## How It Works

1. **User Query**: "What's the weather in San Francisco?"
2. **LLM Decision**: OpenAI Realtime API decides to call `web_search` tool
3. **Tool Execution**: Agent calls Perplexity API with the query
4. **Response**: Perplexity returns concise, factual answer
5. **Agent Reply**: Agent speaks the search result via Cartesia TTS

## Example Queries

- "What's the weather like today?"
- "What's the latest news?"
- "Is there traffic on Highway 101?"
- "When is the next Warriors game?"
- "What's the current price of Bitcoin?"

## Architecture

```
User Speech
    ↓
OpenAI Realtime API (Speech-to-Text + LLM)
    ↓
Tool Call Decision
    ↓
web_search(@function_tool)
    ↓
Perplexity API (llama-3.1-sonar-small-128k-online)
    ↓
Search Result
    ↓
LLM Processes Result
    ↓
Cartesia TTS (Sonic)
    ↓
Audio Response to User
```

## Cost Considerations

- **Perplexity Pricing**: ~$1-5 per 1M tokens (search queries)
- **When Used**: Only when user asks questions requiring web search
- **Optimization**: Short system prompt, limited tokens, low temperature

## Testing

Test queries to verify integration:

```bash
# Start agent locally
python backend/agent.py

# In CarPlay app, try:
"What's the weather today?"
"Tell me the latest tech news"
"What's happening in the world?"
```

## Future Enhancements

- [ ] Add citation support (return sources)
- [ ] Cache frequent queries (weather, traffic)
- [ ] Location-aware searches using GPS
- [ ] Multi-step research for complex queries
- [ ] Rate limiting for cost control

## References

- **Perplexity API Docs**: https://docs.perplexity.ai/docs/overview
- **LiveKit Tool Calling**: https://docs.livekit.io/agents/build/tools/
- **Implementation Reference**: [LIVEKIT_AGENT_TOOLS_REFERENCE.md](backend/LIVEKIT_AGENT_TOOLS_REFERENCE.md#example-3-perplexity-web-search-tool)

---

**Implementation Date**: 2025-11-11
**Status**: ✅ Complete
**Agent Mode**: OpenAI Realtime (text-only) + Cartesia Sonic TTS
**Search Provider**: Perplexity (llama-3.1-sonar-small-128k-online)
