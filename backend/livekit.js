import { AccessToken, RoomServiceClient, AgentDispatchClient } from 'livekit-server-sdk';
import crypto from 'crypto';

// Read environment variables lazily to ensure dotenv has loaded them
function getLiveKitApiKey() {
  const key = process.env.LIVEKIT_API_KEY?.trim();
  if (!key) {
    console.error('❌ LIVEKIT_API_KEY is not set in environment variables');
  }
  return key;
}

function getLiveKitApiSecret() {
  const secret = process.env.LIVEKIT_API_SECRET?.trim();
  if (!secret) {
    console.error('❌ LIVEKIT_API_SECRET is not set in environment variables');
  }
  return secret;
}

function getLiveKitUrlValue() {
  const url = process.env.LIVEKIT_URL?.trim();
  if (!url) {
    console.error('❌ LIVEKIT_URL is not set in environment variables');
  }
  return url;
}

// Debug logging (called after dotenv loads)
export function logLiveKitConfig() {
  const apiKey = getLiveKitApiKey();
  const apiSecret = getLiveKitApiSecret();
  const url = getLiveKitUrlValue();

  console.log('🔑 LiveKit Config:', {
    apiKey: apiKey ? `${apiKey.slice(0, 6)}...` : 'NOT SET',
    apiSecret: apiSecret ? 'SET' : 'NOT SET',
    url: url || 'NOT SET'
  });
}

export function generateRoomName() {
  return `room-${crypto.randomBytes(8).toString('hex')}`;
}

export async function generateLiveKitToken(roomName, participantName) {
  // Read credentials lazily
  const apiKey = getLiveKitApiKey();
  const apiSecret = getLiveKitApiSecret();

  // More detailed error checking
  if (!apiKey) {
    console.error('❌ LIVEKIT_API_KEY is missing');
    throw new Error('LiveKit credentials not configured: LIVEKIT_API_KEY is missing');
  }
  if (!apiSecret) {
    console.error('❌ LIVEKIT_API_SECRET is missing');
    throw new Error('LiveKit credentials not configured: LIVEKIT_API_SECRET is missing');
  }

  const at = new AccessToken(apiKey, apiSecret, {
    identity: participantName,
    ttl: '10h', // Token valid for 10 hours
  });

  at.addGrant({
    roomJoin: true,
    room: roomName,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
  });

  const token = await at.toJwt();
  return token;
}

export function getLiveKitUrl() {
  const url = getLiveKitUrlValue();
  if (!url) {
    throw new Error('LiveKit URL not configured: LIVEKIT_URL environment variable is missing');
  }
  return url;
}

function getLiveKitApiUrl() {
  const url = getLiveKitUrl();
  return url.replace('wss://', 'https://').replace('ws://', 'http://');
}


const DEFAULT_AGENT_NAME = 'agent';
const BASIC_AGENT_IDENTITIES = ['agent', 'assistant', 'roadtrip-voice-assistant'];
const AGENT_IDENTITY_KEYWORDS = ['voice-assistant', 'voiceassistant', 'roadtrip'];

const normalizeIdentity = (identity) => (identity || '').trim().toLowerCase();

export function getAgentName() {
  const configured = process.env.LIVEKIT_AGENT_NAME;
  if (typeof configured === 'string') {
    const trimmed = configured.trim();
    if (trimmed.length > 0) {
      return trimmed;
    }
  }
  return DEFAULT_AGENT_NAME;
}

export function isLikelyAgentParticipant(identity, expectedIdentity) {
  const normalizedIdentity = normalizeIdentity(identity);
  if (!normalizedIdentity) {
    return false;
  }

  // Skip obvious user/device identities before applying fuzzy agent checks
  if (normalizedIdentity.startsWith('user-') || normalizedIdentity.startsWith('device-')) {
    return false;
  }

  const normalizedExpected = normalizeIdentity(expectedIdentity);
  if (normalizedExpected) {
    if (normalizedIdentity === normalizedExpected) {
      return true;
    }
    // LiveKit often appends suffixes to the agent identity (e.g. "agent-abc123")
    if (normalizedIdentity.startsWith(`${normalizedExpected}-`)) {
      return true;
    }
  }

  // Handle generic agent identities like "agent-xyz" / "assistant-123"
  if (BASIC_AGENT_IDENTITIES.some(name => normalizedIdentity === name || normalizedIdentity.startsWith(`${name}-`))) {
    return true;
  }

  // Fall back to keyword-based heuristics for new agent names
  if (normalizedExpected && normalizedIdentity.includes(normalizedExpected)) {
    return true;
  }
  return AGENT_IDENTITY_KEYWORDS.some(keyword => normalizedIdentity.includes(keyword));
}

function getAgentVerificationTargets(expectedIdentity) {
  const normalizedExpected = normalizeIdentity(expectedIdentity);
  if (normalizedExpected) {
    return [normalizedExpected];
  }
  return BASIC_AGENT_IDENTITIES;
}

/**
 * Verify that an agent participant has joined the room
 * @param {string} roomName - The room name to check
 * @param {number} maxAttempts - Maximum number of attempts to check
 * @param {number} delayMs - Delay between attempts in milliseconds
 * @returns {Promise<boolean>} - True if agent found, false otherwise
 */
async function verifyAgentJoined(roomName, maxAttempts = 10, delayMs = 500, expectedIdentity) {
  const apiKey = getLiveKitApiKey();
  const apiSecret = getLiveKitApiSecret();
  const url = getLiveKitUrl();

  if (!apiKey || !apiSecret || !url) {
    console.error('❌ Cannot verify agent: LiveKit credentials not configured');
    return false;
  }

  const roomService = new RoomServiceClient(getLiveKitApiUrl(), apiKey, apiSecret);

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      // List rooms and find the one we're looking for
      // Note: listRooms() returns all rooms, we filter for the one we want
      const rooms = await roomService.listRooms();
      const room = rooms && rooms.find ? rooms.find(r => r.name === roomName) : null;

      if (!room) {
        // Room may not exist yet - LiveKit creates rooms automatically when participants join
        // This is normal, we'll keep checking
        console.log(`⏳ [${attempt}/${maxAttempts}] Room ${roomName} not found yet (will be auto-created when agent joins), waiting...`);
        await new Promise(resolve => setTimeout(resolve, delayMs));
        continue;
      }

      // Get participants for this room
      const participants = await roomService.listParticipants(roomName);

      const verificationTargets = getAgentVerificationTargets(expectedIdentity);
      if (attempt === 1 || attempt % 5 === 0) {
        console.log(`🔎 Expecting agent identity in room ${roomName}: ${verificationTargets.join(', ')}`);
      }

      // Log all participants for debugging
      if (participants && participants.length > 0) {
        const participantList = participants.map(p => `${p.identity} (${p.state})`).join(', ');
        console.log(`👥 Room ${roomName} participants [${attempt}/${maxAttempts}]: ${participantList}`);
      }

      // Look for agent participant - check multiple patterns
      const agentParticipant = participants && participants.find
        ? participants.find(p => isLikelyAgentParticipant(p.identity, expectedIdentity))
        : null;

      if (agentParticipant) {
        console.log(`✅ Agent verified in room ${roomName}: ${agentParticipant.identity} (SID: ${agentParticipant.sid}, State: ${agentParticipant.state})`);
        // Optional: Check if state is connected?
        return true;
      }

      // If we have participants but none match agent patterns, log them for debugging
      if (participants && participants.length > 0) {
        // console.log(`⏳ [${attempt}/${maxAttempts}] Found ${participants.length} participant(s) but none matched the expected agent identity`);
      } else {
        console.log(`⏳ [${attempt}/${maxAttempts}] No participants found in room ${roomName} yet`);
      }

      if (attempt < maxAttempts) {
        await new Promise(resolve => setTimeout(resolve, delayMs));
      }
    } catch (error) {
      console.error(`⚠️  Error checking room ${roomName} (attempt ${attempt}/${maxAttempts}):`, error.message);
      if (attempt < maxAttempts) {
        await new Promise(resolve => setTimeout(resolve, delayMs));
      }
    }
  }

  console.error(`❌ Agent did not join room ${roomName} within ${maxAttempts * delayMs}ms`);
  return false;
}

/**
 * Dispatch agent to room with retry logic
 * @param {string} roomName - The room name
 * @param {string} sessionId - The session ID
 * @param {string} model - The model to use
 * @param {string} voice - The voice to use
 * @param {boolean} toolCallingEnabled - Whether tool calling is enabled
 * @param {boolean} webSearchEnabled - Whether web search is enabled
 * @param {string} language - Preferred STT language (e.g. en-US)
 * @param {string} languageLabel - Human friendly name for the language
 * @param {number} maxRetries - Maximum number of retry attempts
 * @returns {Promise<Object>} - The dispatch object
 */
async function dispatchAgentWithRetry(roomName, sessionId, model, voice, toolCallingEnabled, webSearchEnabled, language, languageLabel, maxRetries = 3) {
  const apiKey = getLiveKitApiKey();
  const apiSecret = getLiveKitApiSecret();
  const url = getLiveKitUrl();

  if (!apiKey || !apiSecret || !url) {
    throw new Error('LiveKit credentials not configured');
  }

  const agentDispatchClient = new AgentDispatchClient(getLiveKitApiUrl(), apiKey, apiSecret);

  // Agent metadata to pass to the LiveKit agent
  const agentMetadata = JSON.stringify({
    session_id: sessionId,
    model: model || 'openai/gpt-4o-mini',
    voice: voice || 'cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc',
    instructions: 'You are a helpful voice AI assistant for CarPlay. Keep responses concise and clear for safe driving.',
    tool_calling_enabled: toolCallingEnabled !== undefined ? toolCallingEnabled : true,
    web_search_enabled: webSearchEnabled !== undefined ? webSearchEnabled : true,
    language: language || 'en-US',
    language_label: languageLabel || language || 'English (US)'
  });

  const agentName = getAgentName();

  let lastError;
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`📡 Dispatching agent to room ${roomName} (attempt ${attempt}/${maxRetries})...`);
      console.log(`   Agent identity: ${agentName}`);
      const dispatch = await agentDispatchClient.createDispatch(roomName, agentName, { metadata: agentMetadata });
      console.log(`✅ Agent dispatched to room ${roomName} as "${agentName}":`, dispatch.id);
      return { dispatch, agentName };
    } catch (error) {
      lastError = error;
      console.error(`❌ Failed to dispatch agent (attempt ${attempt}/${maxRetries}):`, error.message);

      if (attempt < maxRetries) {
        const delayMs = Math.min(1000 * Math.pow(2, attempt - 1), 5000); // Exponential backoff, max 5s
        console.log(`⏳ Retrying in ${delayMs}ms...`);
        await new Promise(resolve => setTimeout(resolve, delayMs));
      }
    }
  }

  throw new Error(`Failed to dispatch agent after ${maxRetries} attempts: ${lastError?.message || 'Unknown error'}`);
}

/**
 * Dispatch agent to room and verify it joins
 * This is the main function that ensures the agent actually joins before returning
 * @param {string} roomName - The room name
 * @param {string} sessionId - The session ID
 * @param {string} model - The model to use
 * @param {string} voice - The voice to use
 * @param {boolean} toolCallingEnabled - Whether tool calling is enabled
 * @param {boolean} webSearchEnabled - Whether web search is enabled
 * @param {string} language - Preferred STT language (e.g. en-US)
 * @param {string} languageLabel - Human friendly name for the language
 * @param {boolean} verifyJoin - Whether to verify the agent joined (default: true)
 * @returns {Promise<Object>} - The dispatch object
 */
export async function dispatchAgentToRoom(roomName, sessionId, model, voice, toolCallingEnabled, webSearchEnabled, language, languageLabel, verifyJoin = true) {
  console.log(`🚀 Starting agent dispatch process for room ${roomName} (session: ${sessionId})`);

  // Step 1: Dispatch agent with retry logic
  const { dispatch, agentName } = await dispatchAgentWithRetry(roomName, sessionId, model, voice, toolCallingEnabled, webSearchEnabled, language, languageLabel);

  // Step 2: Verify agent joined (if enabled)
  if (verifyJoin) {
    console.log(`🔍 Verifying agent joined room ${roomName}...`);
    const agentJoined = await verifyAgentJoined(
      roomName,
      15,
      500,
      agentName
    ); // Check up to 15 times with 500ms delay (7.5s total)

    if (!agentJoined) {
      const errorMessage = `Agent dispatch succeeded but agent did not join room ${roomName}`;
      console.error(`❌ CRITICAL: ${errorMessage}`);
      console.error(`   Dispatch ID: ${dispatch.id}`);
      console.error(`   This may indicate the agent worker is not running or not responding to dispatches`);
      console.error(`   Check agent logs: tail -f /tmp/agent.log`);

      // OPTIONAL: We could choose to NOT throw here and let the client try to connect anyway
      // But for now, we'll stick to the strict behavior but with better logging
      const error = new Error('AGENT_JOIN_TIMEOUT');
      error.details = { roomName, sessionId, dispatchId: dispatch.id };
      throw error;
    } else {
      console.log(`✅ Agent successfully joined room ${roomName} - ready for conversation`);
    }
  } else {
    console.log(`⚠️  Agent join verification skipped (verifyJoin=false)`);
  }

  return dispatch;
}
