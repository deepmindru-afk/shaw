import asyncio
import base64
import json
import logging
import os
from dataclasses import dataclass
from typing import Any, Dict, Iterable, Optional

import aiohttp
import openai
from anthropic import AsyncAnthropic
from anthropic.types import MessageStreamEvent
from dotenv import load_dotenv
from google.ai import generativelanguage as glm
from google.generativeai import types as genai_types
import google.generativeai as genai
from google.protobuf import json_format
from livekit import agents
from livekit.agents import (
    Agent,
    AgentSession,
    APIConnectionError,
    APIStatusError,
    APITimeoutError,
    RoomInputOptions,
    RunContext,
    function_tool,
    inference,
    llm,
)
from livekit.agents.llm import ChatChunk, ChoiceDelta, CompletionUsage, FunctionToolCall
from livekit.agents.llm import utils as llm_utils
from livekit.agents.llm.tool_context import (
    FunctionTool,
    RawFunctionTool,
    get_function_info,
    get_raw_function_info,
    is_function_tool,
    is_raw_function_tool,
)
from livekit.agents.utils import is_given
from livekit.plugins.cartesia import tts as cartesia_tts
from livekit.plugins.elevenlabs import tts as elevenlabs_tts
from urllib3.exceptions import NotOpenSSLWarning

# Ensure compatibility for google.api_core on Python 3.9
try:
    from importlib import metadata as stdlib_metadata  # type: ignore
except ImportError:  # pragma: no cover
    import importlib_metadata as stdlib_metadata  # type: ignore

if not hasattr(stdlib_metadata, 'packages_distributions'):  # pragma: no cover
    import importlib_metadata as _importlib_metadata  # type: ignore

    stdlib_metadata.packages_distributions = _importlib_metadata.packages_distributions  # type: ignore

import warnings

warnings.filterwarnings('ignore', category=FutureWarning, module='google.api_core._python_version_support')
warnings.filterwarnings('ignore', category=NotOpenSSLWarning)

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BACKEND_URL = os.getenv('BACKEND_URL', 'https://shaw.up.railway.app')
DEFAULT_VOICE = 'cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc'
DEFAULT_TEMPERATURE = float(os.getenv('LLM_TEMPERATURE', '0.6'))
DEFAULT_MAX_TOKENS = int(os.getenv('LLM_MAX_OUTPUT_TOKENS', '1024'))
DEFAULT_STT_MODEL = os.getenv('LIVEKIT_STT_MODEL', 'deepgram/nova-3')

ANTHROPIC_MODEL_MAP = {
    'claude-sonnet-4-5': 'claude-3.5-sonnet-20241022',
    'claude-haiku-4-5': 'claude-3.5-haiku-20241022',
}


def _to_bool(value: Any, fallback: bool) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lower = value.lower()
        if lower in ('true', '1', 'yes'):
            return True
        if lower in ('false', '0', 'no'):
            return False
    if isinstance(value, (int, float)):
        return value != 0
    return fallback


@dataclass
class SessionMetadata:
    session_id: str
    model: str
    voice: str
    tool_calling_enabled: bool = True
    web_search_enabled: bool = True
    language: Optional[str] = None

    @classmethod
    def from_payload(cls, payload: Dict[str, Any]) -> 'SessionMetadata':
        session_id = payload.get('session_id')
        model = payload.get('model')
        voice = payload.get('voice', DEFAULT_VOICE)

        if not session_id or not model or not voice:
            raise ValueError('Dispatch metadata must include session_id, model, and voice')

        return cls(
            session_id=session_id,
            model=model,
            voice=voice,
            tool_calling_enabled=_to_bool(payload.get('tool_calling_enabled', True), True),
            web_search_enabled=_to_bool(payload.get('web_search_enabled', True), True),
            language=payload.get('language'),
        )


def _normalize_model(model: str) -> tuple[str, str]:
    if model.startswith('openai/'):
        return 'openai', model.split('/', 1)[1]
    if model.startswith('google/'):
        return 'google', model.split('/', 1)[1]
    if model.startswith('claude'):
        resolved = ANTHROPIC_MODEL_MAP.get(model, model)
        return 'anthropic', resolved
    raise ValueError(f'Unsupported model provider for {model}')


def _build_function_schema(tool: FunctionTool | RawFunctionTool) -> Dict[str, Any]:
    if is_raw_function_tool(tool):
        info = get_raw_function_info(tool)
        schema = info.raw_schema.copy()
        schema.setdefault('description', '')
        schema.setdefault('parameters', {'type': 'object', 'properties': {}})
        return {
            'name': schema['name'],
            'description': schema.get('description') or '',
            'parameters': schema.get('parameters') or {'type': 'object', 'properties': {}},
        }

    if is_function_tool(tool):
        schema = llm_utils.build_strict_openai_schema(tool)
        fn = schema['function']
        return {
            'name': fn['name'],
            'description': fn.get('description') or '',
            'parameters': fn.get('parameters') or {'type': 'object', 'properties': {}},
        }

    raise ValueError('Unsupported tool type')


def _build_openai_tools(tools: Iterable[FunctionTool | RawFunctionTool]) -> list[dict]:
    payload: list[dict] = []
    for tool in tools:
        if is_raw_function_tool(tool):
            info = get_raw_function_info(tool)
            payload.append({
                'type': 'function',
                'function': info.raw_schema,
            })
        else:
            payload.append(llm_utils.build_strict_openai_schema(tool))
    return payload


def _build_anthropic_tools(tools: Iterable[FunctionTool | RawFunctionTool]) -> list[dict]:
    payload: list[dict] = []
    for tool in tools:
        schema = _build_function_schema(tool)
        payload.append({
            'name': schema['name'],
            'description': schema['description'],
            'input_schema': schema['parameters'],
        })
    return payload


def _build_gemini_tools(tools: Iterable[FunctionTool | RawFunctionTool]) -> list[genai_types.Tool]:
    declarations = []
    for tool in tools:
        schema = _build_function_schema(tool)
        declarations.append(
            genai_types.FunctionDeclaration(
                name=schema['name'],
                description=schema['description'],
                parameters=schema['parameters'],
            )
        )

    if not declarations:
        return []

    return [genai_types.Tool(function_declarations=declarations)]


def _serialize_image_content(image: llm.ImageContent) -> str:
    serialized = llm_utils.serialize_image(image)
    if serialized.external_url:
        return serialized.external_url
    assert serialized.data_bytes is not None
    mime = serialized.mime_type or 'image/jpeg'
    encoded = base64.b64encode(serialized.data_bytes).decode('utf-8')
    return f'data:{mime};base64,{encoded}'


def _build_responses_input(chat_ctx: llm.ChatContext) -> list[dict]:
    items: list[dict] = []
    for entry in chat_ctx.items:
        if entry.type == 'message':
            if entry.role == 'assistant':
                content = []
                for part in entry.content:
                    if isinstance(part, str) and part.strip():
                        content.append({
                            'type': 'output_text',
                            'text': part,
                            'annotations': [],
                        })
                if content:
                    items.append({
                        'type': 'message',
                        'role': 'assistant',
                        'content': content,
                        'status': 'completed',
                        'id': entry.id,
                    })
                continue

            if entry.role in ('system', 'user', 'developer'):
                content = []
                for part in entry.content:
                    if isinstance(part, str) and part.strip():
                        content.append({'type': 'input_text', 'text': part})
                    elif isinstance(part, llm.ImageContent):
                        content.append({
                            'type': 'input_image',
                            'image_url': _serialize_image_content(part),
                            'detail': part.inference_detail or 'auto',
                        })
                if content:
                    items.append({
                        'type': 'message',
                        'role': entry.role if entry.role != 'developer' else 'developer',
                        'content': content,
                    })
                continue

        if entry.type == 'function_call':
            items.append({
                'type': 'function_call',
                'call_id': entry.call_id,
                'name': entry.name,
                'arguments': entry.arguments or '',
                'status': 'completed',
            })
        elif entry.type == 'function_call_output':
            items.append({
                'type': 'function_call_output',
                'call_id': entry.call_id,
                'output': entry.output,
                'status': 'completed',
            })

    if not items:
        return [{
            'type': 'message',
            'role': 'user',
            'content': [{'type': 'input_text', 'text': '.'}],
        }]

    return items


class OpenAIResponsesLLM(llm.LLM):
    def __init__(self, *, model: str, temperature: float, allow_parallel_tools: bool, tool_choice: str) -> None:
        super().__init__()
        self._model = model
        self._temperature = temperature
        self._allow_parallel_tools = allow_parallel_tools
        self._tool_choice = tool_choice
        self._client = openai.AsyncClient(max_retries=0)

    @property
    def model(self) -> str:
        return self._model

    @property
    def provider(self) -> str:
        return 'openai'

    def chat(
        self,
        *,
        chat_ctx: llm.ChatContext,
        tools: list[FunctionTool | RawFunctionTool] | None = None,
        conn_options: llm.APIConnectOptions = llm.DEFAULT_API_CONNECT_OPTIONS,
        parallel_tool_calls: llm.NotGivenOr[bool] = llm.NOT_GIVEN,
        tool_choice: llm.NotGivenOr[llm.ToolChoice] = llm.NOT_GIVEN,
        extra_kwargs: llm.NotGivenOr[dict[str, Any]] = llm.NOT_GIVEN,
    ) -> llm.LLMStream:
        return OpenAIResponsesStream(
            self,
            client=self._client,
            model=self._model,
            temperature=self._temperature,
            allow_parallel_tools=self._allow_parallel_tools if not is_given(parallel_tool_calls) else bool(parallel_tool_calls),
            tool_choice=self._tool_choice if not is_given(tool_choice) else tool_choice,  # type: ignore[arg-type]
            chat_ctx=chat_ctx,
            tools=tools or [],
            conn_options=conn_options,
        )


class OpenAIResponsesStream(llm.LLMStream):
    def __init__(
        self,
        llm_ref: OpenAIResponsesLLM,
        *,
        client: openai.AsyncClient,
        model: str,
        temperature: float,
        allow_parallel_tools: bool,
        tool_choice: str,
        chat_ctx: llm.ChatContext,
        tools: list[FunctionTool | RawFunctionTool],
        conn_options: llm.APIConnectOptions,
    ) -> None:
        super().__init__(llm_ref, chat_ctx=chat_ctx, tools=tools, conn_options=conn_options)
        self._client = client
        self._model = model
        self._temperature = temperature
        self._allow_parallel_tools = allow_parallel_tools
        self._tool_choice = tool_choice
        self._pending_calls: dict[str, Dict[str, str]] = {}
        self._response_id: Optional[str] = None

    async def _run(self) -> None:
        input_items = _build_responses_input(self._chat_ctx)
        tools_payload = _build_openai_tools(self._tools)

        params: Dict[str, Any] = {
            'model': self._model,
            'input': input_items,
            'temperature': self._temperature,
        }

        if tools_payload:
            params['tools'] = tools_payload
            params['parallel_tool_calls'] = self._allow_parallel_tools
            params['tool_choice'] = self._tool_choice
        else:
            params['tool_choice'] = 'none'

        try:
            stream_ctx = self._client.responses.stream(**params)
            async with stream_ctx as stream:
                async for event in stream:
                    await self._handle_event(event)
        except openai.APITimeoutError:
            raise APITimeoutError(retryable=False) from None
        except openai.APIStatusError as exc:
            raise APIStatusError(
                exc.message,
                status_code=exc.status_code,
                request_id=exc.request_id,
                body=exc.body,
                retryable=False,
            ) from None
        except Exception as exc:  # pragma: no cover
            raise APIConnectionError(retryable=False) from exc

    async def _handle_event(self, event: Any) -> None:
        event_type = getattr(event, 'type', None)

        if event_type == 'response.created':
            self._response_id = event.response.id
            return

        if event_type == 'response.output_item.added' and event.item.type == 'function_call':
            key = event.item.id or event.item.call_id
            self._pending_calls[key] = {
                'call_id': event.item.call_id,
                'name': event.item.name,
                'arguments': '',
            }
            return

        if event_type == 'response.function_call_arguments.delta':
            pending = self._pending_calls.get(event.item_id)
            if pending is not None and event.delta:
                pending['arguments'] += event.delta
            return

        if event_type == 'response.function_call_arguments.done':
            pending = self._pending_calls.pop(event.item_id, None)
            if pending:
                chunk = ChatChunk(
                    id=self._response_id or pending['call_id'],
                    delta=ChoiceDelta(
                        role='assistant',
                        tool_calls=[FunctionToolCall(name=pending['name'], arguments=pending['arguments'], call_id=pending['call_id'])],
                    ),
                )
                self._event_ch.send_nowait(chunk)
            return

        if event_type == 'response.output_text.delta':
            if not event.delta:
                return
            chunk = ChatChunk(
                id=self._response_id or event.item_id,
                delta=ChoiceDelta(role='assistant', content=event.delta),
            )
            self._event_ch.send_nowait(chunk)
            return

        if event_type == 'response.completed' and event.response.usage:
            usage = event.response.usage
            usage_chunk = ChatChunk(
                id=self._response_id or 'usage',
                usage=CompletionUsage(
                    completion_tokens=usage.output_tokens,
                    prompt_tokens=usage.input_tokens,
                    prompt_cached_tokens=getattr(usage.input_tokens_details, 'cached_tokens', 0),
                    total_tokens=usage.total_tokens,
                ),
            )
            self._event_ch.send_nowait(usage_chunk)


class AnthropicLLM(llm.LLM):
    def __init__(self, *, model: str, temperature: float, max_output_tokens: int, tool_choice: str) -> None:
        super().__init__()
        self._model = model
        self._temperature = temperature
        self._max_output_tokens = max_output_tokens
        self._tool_choice = tool_choice
        self._client = AsyncAnthropic()

    @property
    def model(self) -> str:
        return self._model

    @property
    def provider(self) -> str:
        return 'anthropic'

    def chat(
        self,
        *,
        chat_ctx: llm.ChatContext,
        tools: list[FunctionTool | RawFunctionTool] | None = None,
        conn_options: llm.APIConnectOptions = llm.DEFAULT_API_CONNECT_OPTIONS,
        parallel_tool_calls: llm.NotGivenOr[bool] = llm.NOT_GIVEN,
        tool_choice: llm.NotGivenOr[llm.ToolChoice] = llm.NOT_GIVEN,
        extra_kwargs: llm.NotGivenOr[dict[str, Any]] = llm.NOT_GIVEN,
    ) -> llm.LLMStream:
        raw_tools = tools or []
        messages, format_data = self._chat_ctx_to_anthropic(chat_ctx)
        tools_payload = _build_anthropic_tools(raw_tools)
        choice = self._tool_choice if not is_given(tool_choice) else tool_choice  # type: ignore[assignment]
        return AnthropicStream(
            self,
            client=self._client,
            model=self._model,
            temperature=self._temperature,
            max_output_tokens=self._max_output_tokens,
            system_prompt=format_data,
            anthropic_tools=tools_payload,
            tool_choice=choice if tools_payload else 'none',
            chat_ctx=chat_ctx,
            messages=messages,
            raw_tools=raw_tools,
            conn_options=conn_options,
        )

    @staticmethod
    def _chat_ctx_to_anthropic(chat_ctx: llm.ChatContext) -> tuple[list[dict], Optional[str]]:
        messages, format_data = chat_ctx.to_provider_format('anthropic')
        system_prompt = None
        if format_data.system_messages:
            system_prompt = '\n\n'.join(format_data.system_messages)
        return messages, system_prompt


class AnthropicStream(llm.LLMStream):
    def __init__(
        self,
        llm_ref: AnthropicLLM,
        *,
        client: AsyncAnthropic,
        model: str,
        temperature: float,
        max_output_tokens: int,
        system_prompt: Optional[str],
        anthropic_tools: list[dict],
        tool_choice: str,
        chat_ctx: llm.ChatContext,
        messages: list[dict],
        raw_tools: list[FunctionTool | RawFunctionTool],
        conn_options: llm.APIConnectOptions,
    ) -> None:
        super().__init__(llm_ref, chat_ctx=chat_ctx, tools=raw_tools, conn_options=conn_options)
        self._client = client
        self._model = model
        self._temperature = temperature
        self._max_output_tokens = max_output_tokens
        self._system_prompt = system_prompt
        self._messages = messages
        self._anthropic_tools = anthropic_tools
        self._tool_choice = tool_choice
        self._pending_calls: dict[int, Dict[str, str]] = {}

    async def _run(self) -> None:
        params: Dict[str, Any] = {
            'model': self._model,
            'messages': self._messages,
            'temperature': self._temperature,
            'max_output_tokens': self._max_output_tokens,
            'stream': True,
        }

        if self._system_prompt:
            params['system'] = self._system_prompt
        if self._anthropic_tools:
            params['tools'] = self._anthropic_tools
            params['tool_choice'] = self._tool_choice

        try:
            async with self._client.messages.stream(**params) as stream:
                async for event in stream:
                    await self._handle_event(event)
        except Exception as exc:  # pragma: no cover
            raise APIConnectionError(retryable=False) from exc

    async def _handle_event(self, event: MessageStreamEvent) -> None:
        event_type = getattr(event, 'type', None)

        if event_type == 'content_block_delta' and event.delta.type == 'text_delta':
            chunk = ChatChunk(id=self._model, delta=ChoiceDelta(role='assistant', content=event.delta.text))
            self._event_ch.send_nowait(chunk)
            return

        if event_type == 'content_block_start' and event.content_block.type == 'tool_use':
            self._pending_calls[event.index] = {
                'call_id': getattr(event.content_block, 'id', f'tool-{event.index}'),
                'name': event.content_block.name,
                'arguments': '',
            }
            return

        if event_type == 'content_block_delta' and event.delta.type == 'input_json_delta':
            pending = self._pending_calls.get(event.index)
            if pending:
                pending['arguments'] += event.delta.partial_json
            return

        if event_type == 'content_block_stop':
            pending = self._pending_calls.pop(event.index, None)
            if pending:
                chunk = ChatChunk(
                    id=pending['call_id'],
                    delta=ChoiceDelta(
                        role='assistant',
                        tool_calls=[FunctionToolCall(name=pending['name'], arguments=pending['arguments'], call_id=pending['call_id'])],
                    ),
                )
                self._event_ch.send_nowait(chunk)
            return

        if event_type == 'message_stop' and event.message.usage:
            usage = event.message.usage
            usage_chunk = ChatChunk(
                id=event.message.id,
                usage=CompletionUsage(
                    completion_tokens=usage.output_tokens,
                    prompt_tokens=usage.input_tokens,
                    prompt_cached_tokens=usage.cache_read_input_tokens or 0,
                    total_tokens=usage.input_tokens + usage.output_tokens,
                ),
            )
            self._event_ch.send_nowait(usage_chunk)


class GeminiLLM(llm.LLM):
    _configured = False

    def __init__(self, *, model: str, tool_choice: str, temperature: float) -> None:
        super().__init__()
        self._model = model if model.startswith('models/') else f'models/{model}'
        self._tool_choice = tool_choice
        self._temperature = temperature
        self._configure()

    @classmethod
    def _configure(cls) -> None:
        if cls._configured:
            return
        api_key = os.getenv('GEMINI_API_KEY')
        if not api_key:
            raise ValueError('GEMINI_API_KEY is not configured')
        genai.configure(api_key=api_key)
        cls._configured = True

    @property
    def model(self) -> str:
        return self._model

    @property
    def provider(self) -> str:
        return 'google'

    def chat(
        self,
        *,
        chat_ctx: llm.ChatContext,
        tools: list[FunctionTool | RawFunctionTool] | None = None,
        conn_options: llm.APIConnectOptions = llm.DEFAULT_API_CONNECT_OPTIONS,
        parallel_tool_calls: llm.NotGivenOr[bool] = llm.NOT_GIVEN,
        tool_choice: llm.NotGivenOr[llm.ToolChoice] = llm.NOT_GIVEN,
        extra_kwargs: llm.NotGivenOr[dict[str, Any]] = llm.NOT_GIVEN,
    ) -> llm.LLMStream:
        raw_tools = tools or []
        turns, format_data = chat_ctx.to_provider_format('google')
        system_prompt = None
        if format_data.system_messages:
            system_prompt = '\n\n'.join(format_data.system_messages)
        choice = self._tool_choice if not is_given(tool_choice) else tool_choice  # type: ignore[assignment]
        return GeminiStream(
            self,
            model=self._model,
            system_prompt=system_prompt,
            turns=turns,
            gemini_tools=_build_gemini_tools(raw_tools),
            tool_choice=choice,
            temperature=self._temperature,
            chat_ctx=chat_ctx,
            raw_tools=raw_tools,
            conn_options=conn_options,
        )


class GeminiStream(llm.LLMStream):
    def __init__(
        self,
        llm_ref: GeminiLLM,
        *,
        model: str,
        system_prompt: Optional[str],
        turns: list[dict],
        gemini_tools: list[genai_types.Tool],
        tool_choice: str,
        temperature: float,
        chat_ctx: llm.ChatContext,
        raw_tools: list[FunctionTool | RawFunctionTool],
        conn_options: llm.APIConnectOptions,
    ) -> None:
        super().__init__(llm_ref, chat_ctx=chat_ctx, tools=raw_tools, conn_options=conn_options)
        self._model = model
        self._system_prompt = system_prompt
        self._turns = turns
        self._gemini_tools = gemini_tools
        self._tool_choice = tool_choice
        self._temperature = temperature
        self._seen_calls: set[str] = set()

    async def _run(self) -> None:
        tool_config = None
        if self._gemini_tools:
            mode = 'auto' if self._tool_choice != 'none' else 'none'
            tool_config = {'function_calling_config': {'mode': mode}}

        model = genai.GenerativeModel(
            self._model,
            system_instruction=self._system_prompt,
            tools=self._gemini_tools or None,
            tool_config=tool_config,
            generation_config={'temperature': self._temperature},
        )

        response = await model.generate_content_async(self._turns, stream=True)
        async for chunk in response:
            await self._handle_chunk(chunk)

    async def _handle_chunk(self, chunk: genai_types.AsyncGenerateContentResponse) -> None:
        for candidate in chunk.candidates:
            if not candidate.content:
                continue
            for part in candidate.content.parts:
                if getattr(part, 'text', None):
                    self._event_ch.send_nowait(
                        ChatChunk(id=candidate.content.role or 'gemini', delta=ChoiceDelta(role='assistant', content=part.text))
                    )
                if getattr(part, 'function_call', None):
                    call_id = part.function_call.id or part.function_call.name or f'gemini-call-{len(self._seen_calls)}'
                    if call_id in self._seen_calls:
                        continue
                    self._seen_calls.add(call_id)
                    args_payload: Dict[str, Any] = {}
                    if part.function_call.args:
                        try:
                            args_payload = json_format.MessageToDict(part.function_call.args)
                        except TypeError:
                            args_payload = part.function_call.args  # type: ignore[assignment]
                    self._event_ch.send_nowait(
                        ChatChunk(
                            id=call_id,
                            delta=ChoiceDelta(
                                role='assistant',
                                tool_calls=[
                                    FunctionToolCall(
                                        name=part.function_call.name,
                                        arguments=json.dumps(args_payload),
                                        call_id=call_id,
                                    )
                                ],
                            ),
                        )
                    )

        if chunk.usage_metadata:
            usage_chunk = ChatChunk(
                id='usage',
                usage=CompletionUsage(
                    completion_tokens=chunk.usage_metadata.candidates_token_count,
                    prompt_tokens=chunk.usage_metadata.prompt_token_count,
                    prompt_cached_tokens=0,
                    total_tokens=chunk.usage_metadata.total_token_count,
                ),
            )
            self._event_ch.send_nowait(usage_chunk)


class Assistant(Agent):
    def __init__(self, *, tool_calling_enabled: bool, web_search_enabled: bool) -> None:
        instructions = (
            'You are a helpful voice AI assistant for CarPlay. '
            'Keep responses concise and safe for driving. '
            'Default to English unless the driver explicitly requests another language.'
        )
        if tool_calling_enabled and web_search_enabled:
            instructions += ' Use the web_search tool for current information when helpful.'
        super().__init__(instructions=instructions)
        self._web_search_enabled = web_search_enabled and tool_calling_enabled

    @function_tool()
    async def web_search(self, context: RunContext, query: str) -> str:
        if not self._web_search_enabled:
            return 'Web search is currently disabled in your settings.'

        api_key = os.getenv('PERPLEXITY_API_KEY')
        if not api_key:
            logger.error('PERPLEXITY_API_KEY not configured')
            return "Search isn't configured right now."

        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    'https://api.perplexity.ai/chat/completions',
                    headers={
                        'Authorization': f'Bearer {api_key}',
                        'Content-Type': 'application/json',
                    },
                    json={
                        'model': 'llama-3.1-sonar-small-128k-online',
                        'messages': [
                            {
                                'role': 'system',
                                'content': 'Provide concise facts suitable for voice playback while driving.',
                            },
                            {'role': 'user', 'content': query},
                        ],
                        'temperature': 0.2,
                        'max_tokens': 200,
                    },
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as response:
                    if response.status != 200:
                        text = await response.text()
                        logger.error('Perplexity error %s: %s', response.status, text)
                        return "I'm having trouble searching the web right now."
                    data = await response.json()
                    return data['choices'][0]['message']['content']
        except Exception as exc:  # pragma: no cover
            logger.error('Web search error: %s', exc)
            return "Search is temporarily unavailable."


async def save_turn(session_id: str, speaker: str, text: str) -> None:
    if not session_id or not text.strip():
        return

    try:
        url = f"{BACKEND_URL}/v1/sessions/{session_id}/turns"
        async with aiohttp.ClientSession() as session:
            async with session.post(
                url,
                json={'speaker': speaker, 'text': text.strip()},
                headers={'Content-Type': 'application/json'},
            ) as response:
                if response.status != 201:
                    error_text = await response.text()
                    logger.error('Failed to save turn %s: %s', response.status, error_text)
    except Exception as exc:  # pragma: no cover
        logger.error('Error saving turn: %s', exc)


def _build_tts(voice: str, language: Optional[str]) -> llm.TTS:
    default_language = language or 'en'
    if voice.startswith('cartesia/'):
        _, payload = voice.split('/', 1)
        parts = payload.split(':', 1)
        model = parts[0]
        voice_id = parts[1] if len(parts) > 1 else None
        return cartesia_tts.TTS(model=model, voice=voice_id or cartesia_tts.TTSDefaultVoiceId, language=default_language)

    if voice.startswith('elevenlabs/'):
        _, payload = voice.split('/', 1)
        model, voice_id = payload.split(':', 1)
        return elevenlabs_tts.TTS(model=model, voice_id=voice_id, language=default_language)

    logger.warning('Voice %s not recognized, falling back to Cartesia default', voice)
    return cartesia_tts.TTS(model='sonic-3', voice=cartesia_tts.TTSDefaultVoiceId, language=default_language)


def _resolve_llm(metadata: SessionMetadata) -> llm.LLM:
    provider, model_name = _normalize_model(metadata.model)
    if provider == 'openai':
        return OpenAIResponsesLLM(
            model=model_name,
            temperature=DEFAULT_TEMPERATURE,
            allow_parallel_tools=True,
            tool_choice='auto' if metadata.tool_calling_enabled else 'none',
        )
    if provider == 'anthropic':
        return AnthropicLLM(
            model=model_name,
            temperature=DEFAULT_TEMPERATURE,
            max_output_tokens=DEFAULT_MAX_TOKENS,
            tool_choice='auto' if metadata.tool_calling_enabled else 'none',
        )
    if provider == 'google':
        return GeminiLLM(
            model=model_name,
            tool_choice='auto' if metadata.tool_calling_enabled else 'none',
            temperature=DEFAULT_TEMPERATURE,
        )
    raise ValueError(f'No LLM adapter for provider {provider}')


async def entrypoint(ctx: agents.JobContext) -> None:
    logger.info('🎙️  Agent joining room: %s', ctx.room.name)

    metadata = {}
    if ctx.job.metadata:
        try:
            metadata = json.loads(ctx.job.metadata)
        except Exception:  # pragma: no cover
            logger.warning('Failed to parse dispatch metadata')

    config = SessionMetadata.from_payload(metadata)
    logger.info('Session %s using model %s and voice %s', config.session_id, config.model, config.voice)

    llm_adapter = _resolve_llm(config)
    tts_engine = _build_tts(config.voice, config.language)
    stt_engine = inference.STT.from_model_string(DEFAULT_STT_MODEL)

    agent_session = AgentSession(llm=llm_adapter, tts=tts_engine, stt=stt_engine)

    @agent_session.on('user_speech_committed')
    async def _on_user_speech(message: llm.ChatMessage) -> None:
        if message.content:
            await save_turn(config.session_id, 'user', message.content)

    @agent_session.on('agent_speech_committed')
    async def _on_agent_speech(message: llm.ChatMessage) -> None:
        if message.content:
            await save_turn(config.session_id, 'assistant', message.content)

    await agent_session.start(
        room=ctx.room,
        agent=Assistant(tool_calling_enabled=config.tool_calling_enabled, web_search_enabled=config.web_search_enabled),
        room_input_options=RoomInputOptions(),
    )

    await agent_session.generate_reply(
        instructions='Greet the driver briefly and ask how you can help them.'
    )


if __name__ == '__main__':
    agents.cli.run_app(
        agents.WorkerOptions(
            entrypoint_fnc=entrypoint,
            agent_name='agent',
        )
    )
