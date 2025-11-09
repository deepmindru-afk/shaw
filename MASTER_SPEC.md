# MASTER SPEC: AI VOICE COPILOT (CARPLAY + IOS)

**VERSION:** 1.1  
**STATUS:** IMPLEMENTATION READY  
**LAST UPDATED:** 2024

---

## 1. PRODUCT OVERVIEW

### 1.1 Concept

AI Voice Copilot is an iOS and CarPlay app that lets users place a "call" to an AI assistant and have a natural, full-duplex, low-latency voice conversation while driving.

**Key behaviors:**
- Voice-only, hands-free interaction through CarPlay and/or iPhone
- System-native experience using CallKit for calls and CarPlay templates for in-car UI
- LiveKit as the real-time transport for audio to/from the AI agent
- Optional conversation logging and automatic summaries available later in the mobile app
- Strict compliance with Apple's CarPlay and driver distraction rules (no chat UI or transcripts on CarPlay)

### 1.2 Goals

- Provide a safe, compliant way to talk to an AI while driving
- Make the UX feel like calling a trusted assistant
- Persist sessions (with consent) and provide high-quality summaries
- Design architecture cleanly so it's maintainable and production-ready

### 1.3 Non-Goals (MVP)

- No on-screen messaging/chat interface on CarPlay
- No display of transcripts or message content on CarPlay
- No Android/Android Auto in v1
- No arbitrary custom CarPlay UI outside templates

---

## 2. ARCHITECTURE OVERVIEW

### 2.1 App Components (Client-Side)

The iOS project is structured as follows:

```
CarPlaySwiftUI/
├── Models/
│   ├── Session.swift              # Session, SessionSummary, Turn models
│   └── UserSettings.swift         # User preferences and settings
├── Services/
│   ├── CallManager.swift          # CallKit + AVAudioSession wrapper
│   ├── LiveKitService.swift       # LiveKit room join/leave and media
│   └── SessionLogger.swift        # Backend API client for sessions
├── Coordinators/
│   ├── AppCoordinator.swift       # High-level navigation management
│   └── AssistantCallCoordinator.swift  # End-to-end call orchestration
├── Screens/
│   ├── HomeScreen.swift           # Main screen with call button
│   ├── OnboardingScreen.swift     # First-launch consent flow
│   ├── SessionsListScreen.swift   # Past sessions list
│   ├── SessionDetailScreen.swift  # Session summary and transcript
│   └── SettingsScreen.swift       # Logging preferences and data management
├── CarPlaySceneDelegate.swift     # CarPlay template configuration
├── SceneDelegate.swift            # Phone UI scene delegate
├── AppDelegate.swift               # App lifecycle and scene configuration
└── ContentView.swift               # Root SwiftUI view with onboarding check
```

### 2.2 Backend Components

**Required backend services:**

- **Auth Service**
  - User authentication, tokens

- **Session Service**
  - Session lifecycle, logs, summaries APIs
  - Endpoints:
    - `POST /v1/sessions/start` - Create session, return LiveKit credentials
    - `POST /v1/sessions/end` - Mark session ended, trigger summarization
    - `POST /v1/sessions/:id/turn` - Log conversation turn
    - `GET /v1/sessions` - List user sessions
    - `GET /v1/sessions/:id` - Get session details with summary
    - `DELETE /v1/sessions/:id` - Delete specific session
    - `DELETE /v1/sessions` - Delete all user sessions

- **LiveKit Server**
  - Rooms, tokens, media SFU
  - Token generation bound to user_id and session_id

- **AI Orchestrator**
  - STT, LLM, TTS, and summarization
  - Joins LiveKit room as assistant participant
  - Processes user audio → STT → LLM → TTS → assistant audio

- **Background Workers**
  - Summarization and data retention

### 2.3 Media & Call Flow (High-Level)

1. **User initiates call** from phone or CarPlay
2. **CallManager** starts CallKit call ("AI Assistant")
3. **On call connect:**
   - `AssistantCallCoordinator` asks backend to start session → gets LiveKit token/room
   - `LiveKitService` connects, publishes mic, subscribes to assistant audio
4. **AI Orchestrator** joins the room:
   - User audio → STT → LLM → TTS → back as audio
   - (If logging enabled) sends turns to Session Service
5. **On call end:**
   - LiveKit disconnect
   - Backend marks session ended and runs summarization
6. **User later:**
   - Views summaries (and optionally transcripts) inside phone app only

---

## 3. CARPLAY AND COMPLIANCE REQUIREMENTS

### 3.1 Category & Entitlements

- **Target category:** Communication
- **Required entitlements:**
  - `com.apple.developer.carplay-driving-task`
  - `com.apple.developer.carplay-communication` (must be requested from Apple)

**Note:** The CarPlay Communication entitlement requires approval from Apple. Until approved, the app will not appear in CarPlay.

### 3.2 CarPlay UI Rules

- **Use CarPlay templates only:**
  - Specifically `CPListTemplate` for MVP
- **CarPlay root UI:**
  - Title: "AI Voice Copilot"
  - Single prominent list item: "Talk to Assistant"
- **Prohibited on CarPlay:**
  - Chat bubbles
  - Message content
  - Transcripts
  - Summaries
  - On-screen keyboard for composing content while driving

### 3.3 Call Behavior

- All "assistant sessions" are modeled as VoIP-style calls via CallKit
- Audio routing and controls are via system UI
- Comply with CallKit guidelines:
  - Properly report call connect/disconnect
  - Correct use of audio sessions
  - Handle interruptions gracefully

### 3.4 Logging & Privacy

- Explicit opt-in for recording/transcription
- Clear UI copy: "Your assistant calls can be recorded and summarized for your benefit."
- In-app controls:
  - Toggle logging
  - View/delete sessions
- No deceptive behavior

---

## 4. SCENE & PROJECT CONFIGURATION

### 4.1 Scene Manifest

**Info.plist configuration:**

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <true/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>CPTemplateApplicationScene</string>
                <key>UISceneConfigurationName</key>
                <string>CarPlay</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
            </dict>
        </array>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>UIWindowScene</string>
                <key>UISceneConfigurationName</key>
                <string>Phone</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>
```

**Required permissions:**

```xml
<key>NSMicrophoneUsageDescription</key>
<string>AI Voice Copilot needs access to your microphone to enable voice conversations with your AI assistant.</string>
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
</array>
```

### 4.2 CarPlaySceneDelegate Behavior

**On connect:**
- Setup `CPListTemplate` with:
  - Title: "AI Voice Copilot"
  - Single `CPListItem`: "Talk to Assistant"
  - Handler: calls `AssistantCallCoordinator.startAssistantCall(context: "carplay")`
- Set as root template

**On disconnect:**
- Clean up if needed (no active dependencies should assume CarPlay persists)

---

## 5. DETAILED CLIENT IMPLEMENTATION

### 5.1 AssistantCallCoordinator

**Purpose:**
Central orchestrator that ties together:
- `CallManager`
- `LiveKitService`
- `SessionLogger`

**Responsibilities:**

**Exposed methods:**
- `startAssistantCall(context: String)` - Initiate call from phone or CarPlay
- `endAssistantCall()` - Terminate call and cleanup

**Internal flow:**
1. On `CallManager` connection:
   - Start session via `SessionLogger`
   - Connect `LiveKitService`
2. On `CallManager` end:
   - End session
   - Disconnect `LiveKitService`
3. Handle error cases and propagate UI state

**State management:**
- `@Published var callState: CallState` - Observable state for UI
- `@Published var currentSessionID: String?` - Track active session

### 5.2 CallManager

**Purpose:**
Encapsulate:
- `CXProvider`
- `CXCallController`
- `AVAudioSession` configuration

**Behavior:**

**`startAssistantCall()`:**
- Create `CXStartCallAction` with handle "AI Assistant"
- Submit via `CXCallController`

**`provider(perform: CXStartCallAction)`:**
- Configure `AVAudioSession`:
  - Category: `.playAndRecord`
  - Mode: `.voiceChat` or `.voiceChat` with voice processing
  - Options:
    - `.allowBluetooth`
    - `.allowBluetoothA2DP`
    - `.allowAirPlay`
- On success: fulfill action and notify `AssistantCallCoordinator`

**`endCurrentCall()`:**
- Issue `CXEndCallAction`

**`provider(perform: CXEndCallAction)`:**
- Fulfill, reset state, notify `AssistantCallCoordinator`

**Key points:**
- Must work seamlessly with CarPlay route changes
- Ensure session deactivation on call end
- Handle interruptions (incoming calls, etc.)

### 5.3 LiveKitService

**Purpose:**
Manage joining/leaving LiveKit room and wiring audio.

**Current status:**
- Placeholder implementation with interface defined
- TODO: Integrate actual LiveKit Swift SDK (https://github.com/livekit/client-swift)

**Planned behavior:**

**`connect(sessionID, url, token)`:**
- Initialize `Room`
- Connect using provided URL/token
- On success:
  - Publish local microphone audio track
  - Subscribe to remote assistant audio track

**`disconnect()`:**
- Leave room, cleanup

**Considerations:**
- Integrate with configured `AVAudioSession` (no conflicting session mgmt)
- Handle reconnection gracefully (initial MVP: fail soft and end call if needed)

### 5.4 SessionLogger

**Purpose:**
Communicate with backend session APIs.

**Responsibilities:**

**`startSession(context)`:**
- `POST /v1/sessions/start`
- Input: context ("carplay" or "phone")
- Output:
  - `session_id`
  - `livekit_url`
  - `livekit_token`
  - `room_name`

**`endSession(sessionID)`:**
- `POST /v1/sessions/end`

**`logTurn(sessionID, speaker, text, timestamp)`:**
- `POST /v1/sessions/:id/turn`
- Fire-and-forget (non-blocking)
- Only called if logging enabled

**`fetchSessions()`:**
- `GET /v1/sessions`
- Returns list of `SessionListItem`

**`fetchSessionDetail(sessionID)`:**
- `GET /v1/sessions/:id`
- Returns summary and turns

**`deleteSession(sessionID)`:**
- `DELETE /v1/sessions/:id`

**`deleteAllSessions()`:**
- `DELETE /v1/sessions`

**Behavior:**
- Non-blocking for critical path (call should not fail if logging endpoint is slow)
- Honor user's logging settings (skip `/turn` calls if disabled)
- All endpoints require authentication (TODO: implement token management)

### 5.5 Phone UI

**Screens:**

**HomeScreen:**
- Prominent "Call Assistant" button
- Shows current call state if active
- Navigation to Sessions and Settings
- Recording indicator when call is active

**OnboardingScreen:**
- First-launch consent flow
- Two options:
  - "Allow logging & summaries"
  - "Don't allow (voice-only, no history)"
- Sets `UserSettings.hasSeenOnboarding` and `loggingEnabled`

**SessionsListScreen:**
- Shows past sessions:
  - Title
  - Date/time
  - Short summary snippet
- Navigation to detail view
- Pull-to-refresh support

**SessionDetailScreen:**
- Shows:
  - Summary (title, text, action items, tags)
  - Transcript (if logging enabled for that session)
- Delete session option
- Chat bubble UI for transcript turns

**SettingsScreen:**
- Logging on/off toggle
- Retention days setting (7-365 days)
- "Delete all history" option
- Clear privacy messaging

**No CarPlay-only screens;** all rich history UI is phone-only.

---

## 6. BACKEND SPEC

### 6.1 Core Models

**User:**
```json
{
  "id": "uuid",
  "email": "string",
  "settings": {
    "logging_enabled": boolean,
    "retention_days": integer
  }
}
```

**Session:**
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "context": "carplay" | "phone",
  "started_at": "ISO8601",
  "ended_at": "ISO8601" | null,
  "logging_enabled_snapshot": boolean,
  "summary_status": "pending" | "ready" | "failed"
}
```

**Turn:**
```json
{
  "id": "uuid",
  "session_id": "uuid",
  "timestamp": "ISO8601",
  "speaker": "user" | "assistant",
  "text": "string",
  "audio_ref": "string" (optional)
}
```

**Summary:**
```json
{
  "id": "uuid",
  "session_id": "uuid",
  "title": "string",
  "summary_text": "string",
  "action_items": ["string"],
  "tags": ["string"],
  "created_at": "ISO8601"
}
```

### 6.2 APIs

**All endpoints require authentication (Bearer token).**

**POST /v1/sessions/start**
- **Input:**
  ```json
  {
    "context": "carplay" | "phone"
  }
  ```
- **Logic:**
  - Create session record
  - Generate LiveKit token bound to:
    - `user_id`
    - `session_id`
    - Room name (e.g., `session-{session_id}`)
- **Output:**
  ```json
  {
    "session_id": "uuid",
    "livekit_url": "wss://...",
    "livekit_token": "string",
    "room_name": "string"
  }
  ```

**POST /v1/sessions/end**
- **Input:**
  ```json
  {
    "session_id": "uuid"
  }
  ```
- **Logic:**
  - Mark `ended_at` timestamp
  - Enqueue summarization job

**POST /v1/sessions/:id/turn**
- **Input:**
  ```json
  {
    "speaker": "user" | "assistant",
    "text": "string",
    "timestamp": "ISO8601"
  }
  ```
- **Logic:**
  - If `logging_enabled_snapshot` is true:
    - Store as `Turn` record

**GET /v1/sessions**
- **Output:**
  ```json
  [
    {
      "id": "uuid",
      "title": "string",
      "summary_snippet": "string",
      "started_at": "ISO8601",
      "ended_at": "ISO8601" | null
    }
  ]
  ```

**GET /v1/sessions/:id**
- **Output:**
  ```json
  {
    "summary": {
      "id": "uuid",
      "title": "string",
      "summary_text": "string",
      "action_items": ["string"],
      "tags": ["string"],
      "created_at": "ISO8601"
    } | null,
    "turns": [
      {
        "id": "uuid",
        "timestamp": "ISO8601",
        "speaker": "user" | "assistant",
        "text": "string"
      }
    ]
  }
  ```

**DELETE /v1/sessions/:id**
- Delete or soft-delete specific session

**DELETE /v1/sessions**
- Delete all sessions for user

### 6.3 AI Orchestrator

**Responsibilities:**

**Live Call:**
1. Join LiveKit room as assistant participant
2. For each user audio segment:
   - STT → user text
   - If logging enabled: `POST /turn` (user)
   - LLM → assistant text
   - If logging enabled: `POST /turn` (assistant)
   - TTS → send assistant audio into LiveKit

**Summarization:**
- On session end:
  - Worker fetches all turns
  - Generate:
    - Title
    - Summary
    - Action items
    - Tags
  - Store in `Summary` table

---

## 7. PRIVACY, SECURITY, AND UX SAFETY

### 7.1 Consent & Settings

**On first launch:**
- Modal (`OnboardingScreen`) with:
  - Explanation of recording/transcription
  - Two buttons:
    - "Allow logging & summaries"
    - "Don't allow (voice-only, no history)"
- Users can change later in Settings

### 7.2 Indicators

**During call:**
- Phone UI: discrete label "Assistant call may be recorded for your summaries."
- CarPlay: Keep extremely short if used at all (e.g., "Summary will be saved in the app.")
- Do not create clutter

### 7.3 Security

- All endpoints over TLS
- Media via secure LiveKit config
- Encrypt sensitive data at rest
- Enforce per-user isolation on queries
- Authentication tokens stored securely (Keychain)

---

## 8. IMPLEMENTATION PLAN (ENGINEERING CHECKLIST)

### Phase 1: Baseline CarPlay App ✅ COMPLETE

- [x] Use CarPlay-enabled repo as base
- [x] Ensure `CarPlaySceneDelegate` is wired
- [x] `CPListTemplate` with "Talk to Assistant" visible in CarPlay simulator
- [x] Multiple scene support configured

### Phase 2: Core Call + LiveKit ⚠️ PARTIAL

- [x] Implement `CallManager`
- [x] Implement `LiveKitService` (placeholder)
- [x] Implement `AssistantCallCoordinator`
- [ ] Create mock backend for `/sessions/start` → returns static LiveKit token/URL for initial testing
- [ ] Confirm: Tap "Talk to Assistant" → Starts CallKit call → Connects to LiveKit → Hear test audio

**TODO:**
- Integrate actual LiveKit Swift SDK
- Implement mock backend or connect to real backend
- Test end-to-end call flow

### Phase 3: Backend + AI Orchestrator ⏳ PENDING

- [ ] Implement real `/sessions/start`
- [ ] Implement `/sessions/end`
- [ ] LiveKit token generation
- [ ] Implement AI Orchestrator:
  - Basic STT → LLM → TTS pipeline
  - Connect to same LiveKit room

### Phase 4: Logging & Summaries ⏳ PENDING

- [x] Implement `SessionLogger` using the API interface
- [ ] Turn logging from AI Orchestrator
- [ ] Summarization worker
- [x] Build `SessionsListScreen` and `SessionDetailScreen` in the app

### Phase 5: Compliance & Polish ⏳ PENDING

- [x] Add onboarding consent (`OnboardingScreen`)
- [x] Add Settings for logging and deletion
- [ ] Request CarPlay Communication entitlement from Apple
- [ ] Test thoroughly:
  - CarPlay simulator
  - Real CarPlay head units
  - Route changes, interruptions, network drops

---

## 9. DEPENDENCIES & SETUP

### 9.1 Required Dependencies

**Current:**
- iOS 17.2+
- Swift 5.0+
- SwiftUI
- CallKit
- AVFoundation
- CarPlay framework

**To Add:**
- LiveKit Swift SDK (https://github.com/livekit/client-swift)
  - Add via Swift Package Manager or CocoaPods

### 9.2 Configuration

**Backend URL:**
- Update `baseURL` in `SessionLogger.swift`:
  ```swift
  private let baseURL = "https://api.example.com/v1"
  ```

**Authentication:**
- Implement token management in `SessionLogger`
- Store tokens securely in Keychain

**LiveKit Configuration:**
- Replace placeholder in `LiveKitService.swift` with actual SDK integration
- Follow LiveKit documentation for room connection and media handling

### 9.3 CarPlay Entitlement

**Steps to request:**
1. Go to Apple Developer Portal
2. Navigate to Certificates, Identifiers & Profiles
3. Select your App ID
4. Enable "CarPlay Communication" capability
5. Submit request to Apple for approval
6. Once approved, update provisioning profiles

**Note:** Without this entitlement, the app will not appear in CarPlay.

---

## 10. TESTING CHECKLIST

### 10.1 Unit Tests

- [ ] `CallManager` call flow
- [ ] `SessionLogger` API calls
- [ ] `AssistantCallCoordinator` state transitions
- [ ] `UserSettings` persistence

### 10.2 Integration Tests

- [ ] End-to-end call flow (phone)
- [ ] End-to-end call flow (CarPlay)
- [ ] Session creation and logging
- [ ] Error handling and recovery

### 10.3 CarPlay Testing

- [ ] CarPlay Simulator (Xcode)
- [ ] Physical CarPlay head unit
- [ ] Route changes during call
- [ ] Interruptions (incoming calls, Siri)
- [ ] Network drops and reconnection

### 10.4 Edge Cases

- [ ] Call initiated from CarPlay, ended from phone
- [ ] Multiple rapid call starts
- [ ] Backend unavailable scenarios
- [ ] LiveKit connection failures
- [ ] Audio session conflicts

---

## 11. KNOWN LIMITATIONS & FUTURE ENHANCEMENTS

### 11.1 Current Limitations

- LiveKit integration is placeholder (needs actual SDK)
- Backend API not yet implemented (client ready)
- Authentication not yet implemented
- No error recovery UI for network failures
- No offline mode

### 11.2 Future Enhancements

- Push notifications for summary completion
- Rich notifications with summary preview
- Export sessions (PDF, text)
- Voice commands for CarPlay ("Hey Siri, call my assistant")
- Custom wake word detection
- Multi-language support
- Conversation context persistence across sessions

---

## 12. APPENDIX

### 12.1 File Structure Reference

```
CarPlaySwiftUI/
├── Models/
│   ├── Session.swift
│   └── UserSettings.swift
├── Services/
│   ├── CallManager.swift
│   ├── LiveKitService.swift
│   └── SessionLogger.swift
├── Coordinators/
│   ├── AppCoordinator.swift
│   └── AssistantCallCoordinator.swift
├── Screens/
│   ├── HomeScreen.swift
│   ├── OnboardingScreen.swift
│   ├── SessionsListScreen.swift
│   ├── SessionDetailScreen.swift
│   └── SettingsScreen.swift
├── CarPlaySceneDelegate.swift
├── SceneDelegate.swift
├── AppDelegate.swift
├── ContentView.swift
├── Info.plist
└── CarPlaySwiftUI.entitlements
```

### 12.2 Key Classes Reference

**CallManager:**
- Singleton: `CallManager.shared`
- Delegate: `CallManagerDelegate`
- Methods: `startAssistantCall()`, `endCurrentCall()`

**LiveKitService:**
- Singleton: `LiveKitService.shared`
- Delegate: `LiveKitServiceDelegate`
- Methods: `connect(sessionID:url:token:)`, `disconnect()`

**AssistantCallCoordinator:**
- Singleton: `AssistantCallCoordinator.shared`
- Observable: `@Published var callState`, `currentSessionID`
- Methods: `startAssistantCall(context:)`, `endAssistantCall()`

**SessionLogger:**
- Singleton: `SessionLogger.shared`
- Async methods: `startSession()`, `endSession()`, `logTurn()`, etc.

**UserSettings:**
- Singleton: `UserSettings.shared`
- Observable: `@Published var loggingEnabled`, `retentionDays`, `hasSeenOnboarding`

---

**END OF SPEC**

