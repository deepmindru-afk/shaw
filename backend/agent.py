import os
import logging
import sys
import asyncio
import time
import aiohttp
from dotenv import load_dotenv
from livekit import agents
from livekit.agents import AgentSession, Agent, RoomInputOptions, function_tool, RunContext
from livekit.agents import inference
from livekit.agents import io as agents_io
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
    logger.info(f"   CARTESIA_API_KEY: {cartesia[:6] + '...' if cartesia else 'not set'}")
    logger.info(f"   ELEVENLABS_API_KEY: {eleven[:6] + '...' if eleven else 'not set'}")
    return True

# Backend API configuration
BACKEND_URL = os.getenv('BACKEND_URL', 'https://shaw.up.railway.app')

LANGUAGE_DISPLAY_NAMES = {
    "en-US": "English (US)",
    "en-GB": "English (UK)",
    "en-AU": "English (Australia)",
    "es-MX": "Spanish (Mexico)",
}


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
        self._web_search_enabled = web_search_enabled

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
    """Entry point for the LiveKit agent - supports both Realtime and Turn-based modes"""
    logger.info("=" * 60)
    logger.info(f"🎙️  Agent entrypoint called!")
    logger.info(f"   Room name: {ctx.room.name}")
    logger.info(f"   Room SID: {ctx.room.sid}")
    logger.info(f"   Job ID: {ctx.job.id}")
    logger.info(f"   Job metadata: {ctx.job.metadata}")
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

    realtime_mode = metadata.get('realtime', False)  # Backend sends true for full Realtime, false for hybrid
    voice = metadata.get('voice', 'cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc')
    model = metadata.get('model', 'openai/gpt-4.1-mini')
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
    transcript_manager = TranscriptManager(session_id)

    try:
        if realtime_mode:
            # Full OpenAI Realtime mode (audio I/O) - Pro only
            logger.info(f"🎙️  Using OpenAI Realtime (Full Audio I/O)")
            logger.info(f"📢 Realtime voice: {voice}")

            # Full Realtime model with audio input and output
            realtime_model = openai.realtime.RealtimeModel(
                voice=voice,  # OpenAI voice: alloy, echo, fable, onyx, nova, shimmer
                temperature=0.8,
                modalities=["text", "audio"],  # Full audio I/O
            )

            agent_session = AgentSession(llm=realtime_model)
            agent_session.output.transcription = AssistantTranscriptSink(transcript_manager)

            # Set up event handlers for transcription capture
            # Note: Event handlers must be synchronous - use asyncio.create_task for async work
            @agent_session.on("user_input_transcribed")
            def on_user_transcribed(event):
                transcript_manager.handle_user_transcript_chunk(event.transcript, event.is_final)

            @agent_session.on("user_speech_committed")
            def on_user_speech(msg: agents.llm.ChatMessage):
                if msg:
                    text = getattr(msg, "text_content", None)
                    if text:
                        logger.info(f"🗣️ Committed USER speech ({len(text)} chars) — saving turn")
                    transcript_manager.handle_user_final_text(msg)

            @agent_session.on("agent_speech_committed")
            def on_agent_speech(msg: agents.llm.ChatMessage):
                if msg:
                    text = getattr(msg, "text_content", None)
                    if text:
                        logger.info(f"🗣️ Committed AGENT speech ({len(text)} chars) — saving turn")
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
            logger.info("🎤 Starting full Realtime agent session...")
            logger.info("   RoomIO will automatically subscribe to audio tracks")
            
            await agent_session.start(
                room=ctx.room,
                agent=Assistant(
                    tool_calling_enabled=tool_calling_enabled,
                    web_search_enabled=web_search_enabled,
                    preferred_language_name=language_label,
                    stt_model="deepgram/nova-3",
                    stt_language=language,
                ),
                room_input_options=room_input_options,
            )
            
            # Now that we're connected, log participants and tracks
            logger.info("✅ Agent session started - room connected")
            logger.info(f"🤖 Agent identity: {ctx.room.local_participant.identity if ctx.room.local_participant else 'unknown'}")
            logger.info(f"👥 Remote participants in room: {len(ctx.room.remote_participants)}")
            for participant in ctx.room.remote_participants.values():
                logger.info(f"   - {participant.identity} (SID: {participant.sid})")
                for track_pub in participant.track_publications.values():
                    logger.info(f"     Track: {track_pub.name} ({track_pub.kind}) - subscribed: {track_pub.subscribed}")

            await agent_session.generate_reply(
                instructions=f"Greet the driver briefly in {language_label} and ask how you can help them."
            )

            logger.info("✅ Full Realtime agent session started successfully")
        else:
            # Hybrid mode: LiveKit Inference LLM + TTS (Cartesia/ElevenLabs via plugin or LiveKit Inference)
            logger.info(f"💰 Using HYBRID mode: LiveKit Inference LLM + {voice}")
            logger.info(f"📢 LLM model: {model}")
            logger.info(f"📢 TTS voice: {voice}")

            # Use LiveKit Inference for LLM (not OpenAI Realtime)
            # Model format: "openai/gpt-5-mini", "openai/gpt-4.1-mini", etc.
            # LiveKit Inference handles the connection automatically
            llm_model = model or "openai/gpt-4.1-mini"

            # Create TTS instance - use plugin if available (bypasses LiveKit Inference TTS limit)
            # Otherwise fall back to LiveKit Inference
            tts_instance = create_tts_from_voice_descriptor(voice)
            
            if isinstance(tts_instance, str):
                logger.info(f"📢 Using LiveKit Inference TTS (counts against connection limit)")
            else:
                logger.info(f"📢 Using TTS plugin directly (does NOT count against LiveKit Inference limit)")

            # AgentSession with LiveKit Inference LLM + TTS (plugin or Inference)
            agent_session = AgentSession(
                llm=llm_model,  # LiveKit Inference LLM (string descriptor)
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
            
            await agent_session.start(
                room=ctx.room,
                agent=Assistant(
                    tool_calling_enabled=tool_calling_enabled,
                    web_search_enabled=web_search_enabled,
                    preferred_language_name=language_label,
                    stt_model="deepgram/nova-3",
                    stt_language=language,
                ),
                room_input_options=room_input_options,
            )
            
            # Now that we're connected, log participants and tracks
            logger.info("✅ Hybrid agent session started - room connected")
            logger.info(f"🤖 Agent identity: {ctx.room.local_participant.identity if ctx.room.local_participant else 'unknown'}")
            logger.info(f"👥 Remote participants in room: {len(ctx.room.remote_participants)}")
            for participant in ctx.room.remote_participants.values():
                logger.info(f"   - {participant.identity} (SID: {participant.sid})")
                for track_pub in participant.track_publications.values():
                    logger.info(f"     Track: {track_pub.name} ({track_pub.kind}) - subscribed: {track_pub.subscribed}")

            await agent_session.generate_reply(
                instructions=f"Greet the driver briefly in {language_label} and ask how you can help them."
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
        # This is "agent" for Railway/local workers, or "shaw-voice-assistant" for LiveKit Cloud deployment
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
