import os
import logging
import sys
import asyncio
import time
import aiohttp
import json
from typing import AsyncIterator, Callable
from dotenv import load_dotenv
from anthropic import AsyncAnthropic, APIStatusError as AnthropicAPIStatusError
import google.generativeai as genai
from livekit import agents
from livekit.agents import AgentSession, Agent, RoomInputOptions, function_tool, RunContext
from livekit.agents import inference
from livekit.agents import io as agents_io
from livekit.agents import utils as agent_utils
from livekit.agents.inference.llm import to_fnc_ctx
from livekit.agents.types import DEFAULT_API_CONNECT_OPTIONS, NOT_GIVEN
from livekit.agents._exceptions import APIConnectionError, APIStatusError
from livekit.plugins import openai, cartesia

# Load environment variables from .env file
load_dotenv()

# Configure logging with more detail
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Verify required environment variables
def verify_env():
    """Verify that required environment variables are set"""
    required_vars = {
        'LIVEKIT_URL': os.getenv('LIVEKIT_URL'),
        'LIVEKIT_API_KEY': os.getenv('LIVEKIT_API_KEY'),
        'LIVEKIT_API_SECRET': os.getenv('LIVEKIT_API_SECRET'),
    }
    
    missing = [var for var, value in required_vars.items() if not value]
    if missing:
        logger.error(f"❌ Missing required environment variables: {', '.join(missing)}")
        logger.error("   The agent worker cannot connect to LiveKit Cloud without these variables.")
        return False
    
    logger.info("✅ All required environment variables are set")
    logger.info(f"   LIVEKIT_URL: {os.getenv('LIVEKIT_URL')}")
    logger.info(f"   LIVEKIT_API_KEY: {os.getenv('LIVEKIT_API_KEY')[:6]}...")
    cartesia = os.getenv('CARTESIA_API_KEY')
    eleven = os.getenv('ELEVENLABS_API_KEY')
    perplexity = os.getenv('PERPLEXITY_API_KEY')
    anthropic = os.getenv('ANTHROPIC_API_KEY')
    gemini = os.getenv('GEMINI_API_KEY')
    logger.info(f"   CARTESIA_API_KEY: {cartesia[:6] + '...' if cartesia else 'not set'}")
    logger.info(f"   ELEVENLABS_API_KEY: {eleven[:6] + '...' if eleven else 'not set'}")
    logger.info(f"   PERPLEXITY_API_KEY: {perplexity[:6] + '...' if perplexity else 'not set'}")
    logger.info(f"   ANTHROPIC_API_KEY: {anthropic[:6] + '...' if anthropic else 'not set'}")
    logger.info(f"   GEMINI_API_KEY: {gemini[:6] + '...' if gemini else 'not set'}")
    return True

# Backend API configuration
BACKEND_URL = os.getenv('BACKEND_URL', 'https://roadtrip.up.railway.app')

LANGUAGE_DISPLAY_NAMES = {
    "en-US": "English (US)",
    "en-GB": "English (UK)",
    "en-AU": "English (Australia)",
    "es-MX": "Spanish (Mexico)",
}

DEFAULT_OPENAI_CHAT_MODEL = "gpt-5.1-nano"

def resolve_openai_chat_model(model: str | None) -> str:
    """Convert internal identifiers (e.g. openai/gpt-5.1-nano) to OpenAI chat model names."""
    normalized = (model or "").strip()
    if not normalized:
        return DEFAULT_OPENAI_CHAT_MODEL

    if normalized.startswith("openai/"):
        return normalized.split("/", 1)[1]

    logger.warning(f"⚠️  Unsupported provider for non-realtime mode: {normalized}. Falling back to {DEFAULT_OPENAI_CHAT_MODEL}")
    return DEFAULT_OPENAI_CHAT_MODEL

ANTHROPIC_MODEL_CANDIDATES: dict[str, list[str]] = {
    "claude-sonnet-4-5": [
        "claude-3-5-sonnet-20241022",
        "claude-3-opus-20240229",
    ],
    "claude-haiku-4-5": [
        "claude-3-5-haiku-20241022",
        "claude-3-haiku-20240307",
    ],
}

GOOGLE_MODEL_MAP: dict[str, str] = {
    "google/gemini-2.5-pro": "models/gemini-2.5-pro",
    "google/gemini-2.5-flash": "models/gemini-2.5-flash",
    "google/gemini-2.5-flash-lite": "models/gemini-2.5-flash-lite-preview-06-17",
}

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

anthropic_client = AsyncAnthropic(api_key=ANTHROPIC_API_KEY) if ANTHROPIC_API_KEY else None
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)


class ExternalLLM(agents.llm.LLM):
    def __init__(
        self,
        *,
        provider: str,
        model_key: str,
        fetch_fn: Callable[
            [agents.llm.ChatContext, list[agents.llm.FunctionTool | agents.llm.RawFunctionTool]],
            AsyncIterator[agents.llm.ChatChunk],
        ],
    ) -> None:
        super().__init__()
        self._provider = provider
        self._model_key = model_key
        self._fetch_fn = fetch_fn

    @property
    def model(self) -> str:
        return self._model_key

    @property
    def provider(self) -> str:
        return self._provider

    def chat(
        self,
        *,
        chat_ctx: agents.llm.ChatContext,
        tools: list[agents.llm.FunctionTool | agents.llm.RawFunctionTool] | None = None,
        conn_options=DEFAULT_API_CONNECT_OPTIONS,
        parallel_tool_calls=NOT_GIVEN,
        tool_choice=NOT_GIVEN,
        extra_kwargs=NOT_GIVEN,
    ) -> agents.llm.LLMStream:
        return ExternalLLMStream(
            self,
            chat_ctx=chat_ctx,
            tools=tools or [],
            conn_options=conn_options,
            fetch_fn=self._fetch_fn,
        )


class ExternalLLMStream(agents.llm.LLMStream):
    def __init__(
        self,
        llm: agents.llm.LLM,
        *,
        chat_ctx: agents.llm.ChatContext,
        tools: list[agents.llm.FunctionTool | agents.llm.RawFunctionTool],
        conn_options,
        fetch_fn: Callable[
            [agents.llm.ChatContext, list[agents.llm.FunctionTool | agents.llm.RawFunctionTool]],
            AsyncIterator[agents.llm.ChatChunk],
        ],
    ) -> None:
        super().__init__(llm, chat_ctx=chat_ctx, tools=tools, conn_options=conn_options)
        self._fetch_fn = fetch_fn

    async def _run(self) -> None:
        async for chunk in self._fetch_fn(self._chat_ctx, self._tools):
            self._event_ch.send_nowait(chunk)


def build_anthropic_tool_schemas(
    tools: list[agents.llm.FunctionTool | agents.llm.RawFunctionTool],
) -> list[dict[str, object]]:
    schemas: list[dict[str, object]] = []
    for tool in to_fnc_ctx(tools, strict=True):
        fnc = tool.get("function", {})
        if not fnc:
            continue
        params = fnc.get("parameters") or {"type": "object", "properties": {}}
        schemas.append(
            {
                "name": fnc.get("name", "function"),
                "description": fnc.get("description", ""),
                "input_schema": params,
            }
        )
    return schemas


def _convert_schema_for_gemini(value: dict[str, object]) -> dict[str, object]:
    converted: dict[str, object] = {}
    for key, val in value.items():
        if key == "type" and isinstance(val, str):
            converted[key] = val.upper()
        elif key == "properties" and isinstance(val, dict):
            converted[key] = {k: _convert_schema_for_gemini(v) for k, v in val.items()}
        elif key == "items" and isinstance(val, dict):
            converted[key] = _convert_schema_for_gemini(val)
        else:
            converted[key] = val
    return converted


def build_gemini_tool_declarations(
    tools: list[agents.llm.FunctionTool | agents.llm.RawFunctionTool],
) -> list[dict[str, object]]:
    declarations: list[dict[str, object]] = []
    for tool in to_fnc_ctx(tools, strict=True):
        fnc = tool.get("function", {})
        if not fnc:
            continue
        schema = fnc.get("parameters") or {"type": "object", "properties": {}}
        declarations.append(
            {
                "name": fnc.get("name", "function"),
                "description": fnc.get("description", ""),
                "parameters": _convert_schema_for_gemini(schema),
            }
        )
    return declarations


async def anthropic_chat_stream(
    model_key: str,
    chat_ctx: agents.llm.ChatContext,
    tools: list[agents.llm.FunctionTool | agents.llm.RawFunctionTool],
) -> AsyncIterator[agents.llm.ChatChunk]:
    if not anthropic_client:
        raise APIConnectionError("Anthropic API key not configured.", retryable=False)

    messages, meta = chat_ctx.to_provider_format("anthropic")
    system_prompt = "\n\n".join(meta.system_messages) if meta and meta.system_messages else None
    tool_specs = build_anthropic_tool_schemas(tools)
    candidates = ANTHROPIC_MODEL_CANDIDATES.get(model_key, [model_key])

    for idx, candidate in enumerate(candidates):
        try:
            system_blocks = (
                [{"type": "text", "text": system_prompt}] if system_prompt else None
            )
            request_kwargs = {
                "model": candidate,
                "max_tokens": 800,
                "messages": messages,
            }
            if system_blocks:
                request_kwargs["system"] = system_blocks
            if tool_specs:
                request_kwargs["tools"] = tool_specs
            response = await anthropic_client.messages.create(**request_kwargs)

            chunk_id = response.id or agent_utils.shortuuid("anthropic_")
            text_parts: list[str] = []
            tool_calls: list[agents.llm.FunctionToolCall] = []
            for block in response.content or []:
                block_type = getattr(block, "type", None)
                if block_type == "text":
                    text = getattr(block, "text", None)
                    if text:
                        text_parts.append(text)
                elif block_type == "tool_use":
                    input_payload = getattr(block, "input", {}) or {}
                    tool_calls.append(
                        agents.llm.FunctionToolCall(
                            arguments=json.dumps(input_payload),
                            name=getattr(block, "name", "tool"),
                            call_id=getattr(block, "id", agent_utils.shortuuid("tool_")),
                        )
                    )

            if text_parts:
                yield agents.llm.ChatChunk(
                    id=chunk_id,
                    delta=agents.llm.ChoiceDelta(role="assistant", content="\n\n".join(text_parts)),
                )
            if tool_calls:
                yield agents.llm.ChatChunk(
                    id=f"{chunk_id}_tool",
                    delta=agents.llm.ChoiceDelta(role="assistant", tool_calls=tool_calls),
                )

            usage = getattr(response, "usage", None)
            if usage:
                yield agents.llm.ChatChunk(
                    id=f"{chunk_id}_usage",
                    usage=agents.llm.CompletionUsage(
                        completion_tokens=getattr(usage, "output_tokens", 0) or 0,
                        prompt_tokens=getattr(usage, "input_tokens", 0) or 0,
                        prompt_cached_tokens=0,
                        total_tokens=getattr(usage, "input_tokens", 0) + getattr(usage, "output_tokens", 0),
                    ),
                )
            return
        except AnthropicAPIStatusError as err:
            if err.status_code == 404 and idx < len(candidates) - 1:
                continue
            raise APIStatusError(
                err.message,
                status_code=err.status_code,
                body=getattr(err, "response", None),
                retryable=err.status_code >= 500,
            ) from err
        except Exception as err:
            raise APIConnectionError(str(err), retryable=False) from err


async def gemini_chat_stream(
    model_key: str,
    chat_ctx: agents.llm.ChatContext,
    tools: list[agents.llm.FunctionTool | agents.llm.RawFunctionTool],
) -> AsyncIterator[agents.llm.ChatChunk]:
    if not GEMINI_API_KEY:
        raise APIConnectionError("Gemini API key not configured.", retryable=False)

    api_model = GOOGLE_MODEL_MAP.get(model_key, "models/gemini-2.5-flash")
    turns, meta = chat_ctx.to_provider_format("google")
    system_prompt = "\n\n".join(meta.system_messages) if meta and meta.system_messages else None
    tool_decls = build_gemini_tool_declarations(tools)

    payload: dict[str, object] = {"contents": turns}
    if system_prompt:
        payload["systemInstruction"] = {"role": "system", "parts": [{"text": system_prompt}]}
    if tool_decls:
        payload["tools"] = [{"functionDeclarations": tool_decls}]

    url = f"https://generativelanguage.googleapis.com/v1beta/{api_model}:generateContent?key={GEMINI_API_KEY}"
    timeout = aiohttp.ClientTimeout(total=30)

    async with aiohttp.ClientSession(timeout=timeout) as session:
        async with session.post(url, json=payload) as resp:
            if resp.status >= 400:
                body = await resp.text()
                raise APIStatusError(
                    f"Gemini request failed ({resp.status})",
                    status_code=resp.status,
                    body=body,
                    retryable=resp.status >= 500,
                )
            data = await resp.json()

    candidates = data.get("candidates") or []
    if not candidates:
        raise APIConnectionError("Gemini response did not include candidates.", retryable=True)

    candidate = candidates[0]
    parts = candidate.get("content", {}).get("parts", [])
    text_parts: list[str] = []
    tool_calls: list[agents.llm.FunctionToolCall] = []

    for part in parts:
        if "text" in part and part["text"]:
            text_parts.append(part["text"])
        elif "functionCall" in part:
            fn_call = part["functionCall"]
            args = fn_call.get("args", {})
            tool_calls.append(
                agents.llm.FunctionToolCall(
                    arguments=json.dumps(args),
                    name=fn_call.get("name", "function"),
                    call_id=agent_utils.shortuuid("tool_"),
                )
            )

    chunk_id = candidate.get("content", {}).get("id", agent_utils.shortuuid("gemini_"))
    if text_parts:
        yield agents.llm.ChatChunk(
            id=chunk_id,
            delta=agents.llm.ChoiceDelta(role="assistant", content="\n\n".join(text_parts)),
        )
    if tool_calls:
        yield agents.llm.ChatChunk(
            id=f"{chunk_id}_tool",
            delta=agents.llm.ChoiceDelta(role="assistant", tool_calls=tool_calls),
        )

    usage = data.get("usageMetadata") or {}
    if usage:
        yield agents.llm.ChatChunk(
            id=f"{chunk_id}_usage",
            usage=agents.llm.CompletionUsage(
                completion_tokens=usage.get("candidatesTokenCount", 0) or 0,
                prompt_tokens=usage.get("promptTokenCount", 0) or 0,
                prompt_cached_tokens=0,
                total_tokens=usage.get("totalTokenCount", 0) or 0,
            ),
        )


def infer_model_provider(model: str | None) -> str:
    if not model:
        return "openai"
    if model.startswith("openai/"):
        return "openai"
    if model in ANTHROPIC_MODEL_CANDIDATES:
        return "anthropic"
    if model in GOOGLE_MODEL_MAP:
        return "google"
    return "openai"


def create_hybrid_llm(model: str | None) -> agents.llm.LLM:
    provider = infer_model_provider(model)
    if provider == "anthropic" and anthropic_client:
        model_key = model or "claude-sonnet-4-5"

        async def fetch(ctx: agents.llm.ChatContext, ctx_tools: list[agents.llm.FunctionTool | agents.llm.RawFunctionTool]):
            async for chunk in anthropic_chat_stream(model_key, ctx, ctx_tools):
                yield chunk

        return ExternalLLM(provider="anthropic", model_key=model_key, fetch_fn=fetch)
    if provider == "anthropic" and not anthropic_client:
        logger.warning("Anthropic model requested but ANTHROPIC_API_KEY is not configured. Falling back to OpenAI.")

    if provider == "google" and GEMINI_API_KEY:
        model_key = model or "google/gemini-2.5-flash-lite"

        async def fetch(ctx: agents.llm.ChatContext, ctx_tools: list[agents.llm.FunctionTool | agents.llm.RawFunctionTool]):
            async for chunk in gemini_chat_stream(model_key, ctx, ctx_tools):
                yield chunk

        return ExternalLLM(provider="google", model_key=model_key, fetch_fn=fetch)
    if provider == "google" and not GEMINI_API_KEY:
        logger.warning("Gemini model requested but GEMINI_API_KEY is not configured. Falling back to OpenAI.")

    target = resolve_openai_chat_model(model)
    return openai.llm.LLM(model=target)


class TranscriptManager:
    """Aggregates streamed transcription chunks and saves finalized turns."""

    DEDUPE_WINDOW_SECONDS = 5.0

    def __init__(self, session_id: str | None):
        self._session_id = session_id
        self._recent_turns: dict[str, dict[str, float]] = {
            'user': {},
            'assistant': {},
        }
        self._pending_user_partial: str | None = None

    def handle_user_transcript_chunk(self, transcript: str, is_final: bool) -> None:
        normalized = self._normalize_text(transcript)
        if not normalized:
            return

        self._pending_user_partial = normalized
        if is_final:
            self._maybe_save_turn('user', normalized)
            self._pending_user_partial = None

    def handle_user_final_text(self, text: object | None) -> None:
        normalized = self._normalize_text(text) or self._pending_user_partial
        if normalized:
            self._maybe_save_turn('user', normalized)
            self._pending_user_partial = None

    def handle_assistant_text(self, text: object | None) -> None:
        normalized = self._normalize_text(text)
        if normalized:
            self._maybe_save_turn('assistant', normalized)

    def handle_conversation_item(self, message: object | None) -> None:
        if not message:
            return
        role = getattr(message, 'role', None)
        if role not in ('user', 'assistant'):
            return
        text_content = getattr(message, 'text_content', None)
        content = text_content if text_content else getattr(message, 'content', None)
        normalized = self._normalize_text(content)
        if normalized:
            self._maybe_save_turn(role, normalized)

    def _normalize_text(self, text: object | None) -> str:
        flattened = self._flatten_text(text)
        if not flattened:
            return ""
        normalized = " ".join(flattened.strip().split())
        return normalized

    def _flatten_text(self, value: object | None) -> str:
        if value is None:
            return ""

        if hasattr(value, 'text_content'):
            text_value = getattr(value, 'text_content')
            if text_value:
                return text_value

        if isinstance(value, bytes):
            try:
                return value.decode('utf-8', errors='ignore')
            except Exception:
                return ""

        if isinstance(value, (list, tuple, set)):
            parts = [self._flatten_text(part) for part in value]
            return " ".join(part for part in parts if part)

        if isinstance(value, dict):
            for key in ('text', 'transcript', 'content', 'value'):
                if key in value and value[key]:
                    flattened = self._flatten_text(value[key])
                    if flattened:
                        return flattened
            return ""

        for attr in ('text', 'transcript', 'value', 'content'):
            if hasattr(value, attr):
                attr_value = getattr(value, attr)
                flattened = self._flatten_text(attr_value)
                if flattened:
                    return flattened

        if not isinstance(value, str):
            value = str(value)

        return value

    def _maybe_save_turn(self, speaker: str, text: str) -> None:
        if not self._session_id or not text:
            return

        if self._is_duplicate(speaker, text):
            logger.debug(f"🔁 Skipping duplicate {speaker} transcript chunk")
            return

        logger.debug(f"📝 Queueing {speaker} turn ({len(text)} chars)")
        asyncio.create_task(save_turn(self._session_id, speaker, text))

    def _is_duplicate(self, speaker: str, text: str) -> bool:
        now = time.monotonic()
        cache = self._recent_turns.setdefault(speaker, {})

        expired = [phrase for phrase, ts in cache.items()
                   if now - ts > self.DEDUPE_WINDOW_SECONDS]
        for phrase in expired:
            del cache[phrase]

        last_seen = cache.get(text)
        if last_seen and now - last_seen < self.DEDUPE_WINDOW_SECONDS:
            return True

        cache[text] = now
        return False

class AssistantTranscriptSink(agents_io.TextOutput):
    """Captures assistant text streamed from TTS and forwards it to the transcript manager."""

    def __init__(self, transcript_manager: TranscriptManager):
        super().__init__(label="assistant_transcript_sink", next_in_chain=None)
        self._transcript_manager = transcript_manager
        self._buffer: list[str] = []

    async def capture_text(self, text: str) -> None:
        if text:
            self._buffer.append(text)

    def flush(self) -> None:
        if not self._buffer:
            return

        combined = "".join(self._buffer).strip()
        self._buffer.clear()

        if combined:
            self._transcript_manager.handle_assistant_text(combined)

class Assistant(Agent):
    def __init__(
        self,
        tool_calling_enabled: bool = True,
        web_search_enabled: bool = True,
        preferred_language_name: str | None = None,
        stt_model: str | None = None,
        stt_language: str | None = None,
    ) -> None:
        language_name = preferred_language_name or "English (US)"
        # Update instructions based on tool availability
        base_instructions = (
            f"You are a helpful voice AI assistant for CarPlay. "
            f"Keep responses concise, clear, and in {language_name} for safe driving. "
            f"Default to {language_name} unless the driver explicitly asks for another language."
        )

        if tool_calling_enabled and web_search_enabled:
            instructions = base_instructions + " When users ask questions requiring current information (news, weather, traffic, events, facts), use the web_search tool."
        else:
            instructions = base_instructions + " Rely on your built-in knowledge to answer questions."

        # Configure STT for hybrid mode (defaults to Deepgram via LiveKit Inference)
        # Provide a descriptor string "provider/model:language" or construct explicitly
        stt_descriptor = None
        if stt_model:
            if stt_language:
                stt_descriptor = f"{stt_model}:{stt_language}"
            else:
                stt_descriptor = stt_model

        super().__init__(
            instructions=instructions,
            stt=stt_descriptor if stt_descriptor else inference.STT.from_model_string("deepgram/nova-3:en-US"),
            use_tts_aligned_transcript=True,
        )

        # Store settings
        self._tool_calling_enabled = tool_calling_enabled
        self._web_search_enabled = web_search_enabled

        # If tool calling is disabled, drop all tools so the LLM cannot discover them
        if not tool_calling_enabled:
            self._tools = []

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
        # Check if web search is enabled
        if not self._web_search_enabled:
            return "Web search is currently disabled in your settings."

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

def create_tts_from_voice_descriptor(voice_descriptor: str):
    """Create a TTS instance from a voice descriptor string.
    
    Supports:
    - Cartesia: "cartesia/sonic-3:voice-id" -> cartesia.TTS()
    - ElevenLabs: "elevenlabs/eleven_turbo_v2_5:voice-id" -> (fallback to LiveKit Inference)
    - Other formats: fallback to LiveKit Inference
    
    Returns a TTS instance or the original string descriptor for LiveKit Inference fallback.
    """
    if not voice_descriptor or not isinstance(voice_descriptor, str):
        return voice_descriptor
    
    # Parse Cartesia format: "cartesia/sonic-3:voice-id"
    if voice_descriptor.startswith("cartesia/"):
        try:
            # Extract model and voice ID
            # Format: "cartesia/sonic-3:voice-id"
            parts = voice_descriptor.split(":", 1)
            if len(parts) == 2:
                model_part = parts[0]  # "cartesia/sonic-3"
                voice_id = parts[1]     # "voice-id"
                
                # Extract model name (e.g., "sonic-3" from "cartesia/sonic-3")
                model = model_part.split("/")[-1] if "/" in model_part else "sonic-3"
                
                # Check if Cartesia API key is available
                if os.getenv('CARTESIA_API_KEY'):
                    logger.info(f"🎤 Using Cartesia plugin directly (bypasses LiveKit Inference TTS limit)")
                    return cartesia.TTS(model=model, voice=voice_id)
                else:
                    logger.warning(f"⚠️  CARTESIA_API_KEY not set, falling back to LiveKit Inference")
                    return voice_descriptor
            else:
                logger.warning(f"⚠️  Invalid Cartesia voice format: {voice_descriptor}")
                return voice_descriptor
        except Exception as e:
            logger.error(f"❌ Error creating Cartesia TTS: {e}")
            return voice_descriptor
    
    if voice_descriptor.startswith("elevenlabs/"):
        # Fallback to LiveKit Inference for ElevenLabs
        return voice_descriptor

    return voice_descriptor

async def save_turn(session_id: str, speaker: str, text: str):
    """Save a conversation turn to the backend database
    
    This function is called by the agent when user speech or agent speech is committed.
    The turns are stored in the database and later used to generate summaries.
    """
    if not session_id or not text.strip():
        logger.warning(f"⚠️  Skipping turn save - missing session_id or empty text")
        return

    try:
        url = f"{BACKEND_URL}/v1/sessions/{session_id}/turns"
        async with aiohttp.ClientSession() as session:
            async with session.post(
                url,
                json={
                    "speaker": speaker,
                    "text": text.strip()
                },
                headers={"Content-Type": "application/json"},
                timeout=aiohttp.ClientTimeout(total=5)
            ) as response:
                if response.status == 201:
                    logger.debug(f"✅ Saved {speaker} turn for session {session_id[:20]}...")
                else:
                    error_text = await response.text()
                    logger.error(f"❌ Failed to save turn: {response.status} - {error_text}")
                    logger.error(f"   Session ID: {session_id[:20]}..., Speaker: {speaker}")
    except asyncio.TimeoutError:
        logger.error(f"❌ Timeout saving turn for session {session_id[:20]}...")
    except Exception as e:
        logger.error(f"❌ Error saving turn: {e}")
        logger.error(f"   Session ID: {session_id[:20]}..., Speaker: {speaker}")

async def entrypoint(ctx: agents.JobContext):
    """Entry point for the LiveKit agent"""
    logger.info("=" * 60)
    logger.info(f"🎙️  Agent entrypoint called!")
    logger.info(f"   Room name: {ctx.room.name}")
    logger.info(f"   Job ID: {ctx.job.id}")
    try:
        logger.info(f"   Job metadata: {ctx.job.metadata}")
    except Exception:
        logger.info(f"   Job metadata: (unprintable)")
    logger.info("=" * 60)
    
    # Note: Room is NOT connected yet - AgentSession.start() will connect automatically
    # RoomIO will automatically handle track subscription when AgentSession starts
    # The room may not exist yet - LiveKit will create it automatically when agent joins

    # Parse metadata from dispatch
    import json
    metadata = {}
    session_id = None
    try:
        if ctx.job.metadata:
            metadata = json.loads(ctx.job.metadata)
            logger.info(f"📋 Received metadata: {metadata}")
            session_id = metadata.get('session_id')
            if session_id:
                logger.info(f"📝 Session ID: {session_id}")
    except Exception as e:
        logger.warning(f"Failed to parse metadata: {e}")

    voice = metadata.get('voice', 'cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc')
    if not isinstance(voice, str) or not voice.strip():
        voice = 'cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc'
    voice = voice.strip()
    model = metadata.get('model', 'openai/gpt-5.1-nano')
    tool_calling_enabled = metadata.get('tool_calling_enabled', True)
    web_search_enabled = metadata.get('web_search_enabled', True)
    language = metadata.get('language', 'en-US')
    if not isinstance(language, str) or not language:
        language = 'en-US'
    language_label = metadata.get('language_label')
    if not isinstance(language_label, str) or not language_label.strip():
        language_label = LANGUAGE_DISPLAY_NAMES.get(language, language)

    logger.info(f"🔧 Tool settings - Tool calling: {tool_calling_enabled}, Web search: {web_search_enabled}")
    logger.info(f"🌐 STT language: {language} ({language_label})")
    if tool_calling_enabled and web_search_enabled and not os.getenv('PERPLEXITY_API_KEY'):
        logger.warning("⚠️  web_search tool enabled but PERPLEXITY_API_KEY is missing - tool calls will fail")
    transcript_manager = TranscriptManager(session_id)

    tool_choice = None if tool_calling_enabled else "none"

    def attach_tool_logging(agent_session: AgentSession) -> None:
        @agent_session.on("function_tools_executed")
        def on_function_tools_executed(event):
            try:
                calls = getattr(event, "function_calls", []) or []
                outputs = getattr(event, "function_call_outputs", []) or []
                names = [c.name for c in calls]
                logger.info(f"🛠️ Tool calls executed: {', '.join(names) if names else 'none'}")
                if outputs and any(out is None for out in outputs):
                    logger.warning("⚠️  One or more tool calls returned no output")
            except Exception as e:
                logger.error(f"❌ Failed to log tool execution event: {e}")

    try:
        # Hybrid mode: connect to third-party APIs directly (OpenAI / Anthropic / Gemini)
        logger.info(f"💰 Using HYBRID mode: Direct LLM + {voice}")
        logger.info(f"📢 Requested LLM model: {model}")
        logger.info(f"📢 TTS voice: {voice}")

        llm_model = create_hybrid_llm(model)
        logger.info(f"🧠 Resolved provider: {llm_model.provider} ({llm_model.model})")

        # Create TTS instance - use plugin if available (bypasses LiveKit Inference TTS limit)
        # Otherwise fall back to LiveKit Inference
        tts_instance = create_tts_from_voice_descriptor(voice)
        
        if isinstance(tts_instance, str):
            logger.info(f"📢 Using LiveKit Inference TTS (counts against connection limit)")
        else:
            logger.info(f"📢 Using TTS plugin directly (does NOT count against LiveKit Inference limit)")

        # AgentSession with LiveKit Inference LLM + TTS (plugin or Inference)
        agent_session = AgentSession(
            llm=llm_model,  # OpenAI chat completion model (plugin)
            tts=tts_instance,  # TTS plugin instance or LiveKit Inference descriptor
            stt=inference.STT.from_model_string(f"deepgram/nova-3:{language}"),
        )
        agent_session.output.transcription = AssistantTranscriptSink(transcript_manager)

        # Set up event handlers for transcription capture
        # Note: Event handlers must be synchronous - use asyncio.create_task for async work
        @agent_session.on("user_input_transcribed")
        def on_user_transcribed(event):
            transcript_manager.handle_user_transcript_chunk(event.transcript, event.is_final)

        @agent_session.on("user_speech_committed")
        def on_user_speech(msg: agents.llm.ChatMessage):
            if msg:
                transcript_manager.handle_user_final_text(msg)

        @agent_session.on("agent_speech_committed")
        def on_agent_speech(msg: agents.llm.ChatMessage):
            if msg:
                transcript_manager.handle_assistant_text(msg)

        @agent_session.on("conversation_item_added")
        def on_conversation_item(event):
            try:
                message = getattr(event, "item", None) or event
                transcript_manager.handle_conversation_item(message)
            except Exception as e:
                logger.error(f"❌ Error handling conversation_item_added: {e}")

        # Configure room input options
        # RoomIO (created automatically by AgentSession) handles track subscription
        room_input_options = RoomInputOptions(close_on_disconnect=False)
        logger.info("🎤 Starting hybrid agent session...")
        logger.info("   RoomIO will automatically subscribe to audio tracks")

        assistant_agent = Assistant(
            tool_calling_enabled=tool_calling_enabled,
            web_search_enabled=web_search_enabled,
            preferred_language_name=language_label,
            stt_model="deepgram/nova-3",
            stt_language=language,
        )
        attach_tool_logging(agent_session)

        await agent_session.start(
            room=ctx.room,
            agent=assistant_agent,
            room_input_options=room_input_options,
        )

        if tool_choice == "none" and agent_session._activity:
            agent_session._activity.update_options(tool_choice="none")
        
        # Now that we're connected, log participants and tracks
        logger.info("✅ Agent session started - room connected")
        logger.info(f"🤖 Agent identity: {ctx.room.local_participant.identity if ctx.room.local_participant else 'unknown'}")
        logger.info(f"👥 Remote participants in room: {len(ctx.room.remote_participants)}")
        for participant in ctx.room.remote_participants.values():
            logger.info(f"   - {participant.identity} (SID: {participant.sid})")
            for track_pub in participant.track_publications.values():
                logger.info(f"     Track: {track_pub.name} ({track_pub.kind}) - subscribed: {track_pub.subscribed}")

        await agent_session.generate_reply(
            instructions=f"Greet the driver briefly in {language_label} and ask how you can help them.",
            tool_choice=tool_choice,
        )

        logger.info("✅ Hybrid agent session started successfully")

    except Exception as e:
        logger.error(f"❌ Agent error: {e}")
        raise

if __name__ == "__main__":
    logger.info("=" * 60)
    logger.info("🚀 Starting LiveKit Agent Worker")
    logger.info("=" * 60)
    
    # Verify environment variables before starting
    if not verify_env():
        logger.error("❌ Environment verification failed. Exiting.")
        sys.exit(1)
    
    # Log agent configuration
    logger.info(f"📋 Agent name: agent")
    logger.info(f"📋 Entrypoint: entrypoint")
    logger.info("=" * 60)
    logger.info("🔌 Connecting to LiveKit Cloud...")
    logger.info("   The agent will listen for dispatches and join rooms as needed.")
    logger.info("=" * 60)
    
    try:
        # Start the agent worker with explicit dispatch support
        # IMPORTANT: agent_name must match the name used in dispatchAgentToRoom() in livekit.js
        # This is "agent" for Railway/local workers, or "roadtrip-voice-assistant" for LiveKit Cloud deployment
        agent_name = os.getenv("LIVEKIT_AGENT_NAME", "agent")
        logger.info(f"📋 Agent name for dispatch: {agent_name}")
        logger.info(f"   This must match the agent name used in dispatchAgentToRoom()")
        logger.info(f"   Set LIVEKIT_AGENT_NAME env var to override (default: 'agent')")
        
        agents.cli.run_app(
            agents.WorkerOptions(
                entrypoint_fnc=entrypoint,
                agent_name=agent_name,  # Required for explicit dispatch - must match dispatch call
            ),
        )
    except KeyboardInterrupt:
        logger.info("🛑 Agent worker stopped by user")
    except Exception as e:
        logger.error(f"❌ Agent worker failed to start: {e}")
        logger.exception("Full error details:")
        sys.exit(1)
if __name__ == "__main__":
    # Flush stdout immediately to ensure logs are captured
    sys.stdout.reconfigure(line_buffering=True)
    
    logger.info("🚀 Agent worker process starting...")
    logger.info(f"   Python: {sys.version}")
    logger.info(f"   CWD: {os.getcwd()}")
    
    if not verify_env():
        logger.error("❌ Environment verification failed - exiting")
        sys.exit(1)

    try:
        # Initialize the worker
        logger.info("🔌 Connecting to LiveKit Cloud...")
        cli.run_app(
            WorkerOptions(
                entrypoint_fnc=entrypoint,
                # Use a specific worker label if needed
                # worker_label="roadtrip-agent",
            )
        )
    except Exception as e:
        logger.critical(f"❌ Unhandled exception in agent worker: {e}", exc_info=True)
        sys.exit(1)
