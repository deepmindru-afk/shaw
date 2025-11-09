# Engineering Handoff: AI Voice Copilot for CarPlay

**Date:** 2024  
**Repository:** https://github.com/jjeremycai/ai-voice-copilot-carplay  
**Status:** Foundation Complete, Ready for LiveKit Integration & Backend Connection

---

## 📋 Project Overview

AI Voice Copilot is an iOS and CarPlay app that enables hands-free voice conversations with an AI assistant. Users can initiate calls via CallKit (modeled as VoIP calls) that connect to a LiveKit room for real-time audio streaming. The app supports optional conversation logging and automatic summaries.

**Key Technologies:**
- Swift/SwiftUI
- CallKit (VoIP calls)
- CarPlay (CPListTemplate)
- LiveKit (real-time audio - **not yet integrated**)
- Async/await networking

---

## ✅ What's Complete

### Core Architecture
- ✅ **CallManager**: CallKit integration with dependency injection for testing
- ✅ **AssistantCallCoordinator**: Orchestrates calls, LiveKit, and session management
- ✅ **SessionLogger**: Backend API client with authentication support
- ✅ **AuthService**: Token management with Keychain storage
- ✅ **UserSettings**: Persistent user preferences

### CarPlay Integration
- ✅ **CarPlaySceneDelegate**: CPListTemplate with "Talk to Assistant" button
- ✅ **Scene Configuration**: Multiple scenes (CarPlay + Phone) properly configured
- ✅ **Entitlements**: CarPlay Communication entitlement configured (needs Apple approval)

### Phone UI
- ✅ **HomeScreen**: Main screen with call button
- ✅ **OnboardingScreen**: First-launch consent flow
- ✅ **SessionsListScreen**: Past sessions list
- ✅ **SessionDetailScreen**: Session summary and transcript view
- ✅ **SettingsScreen**: Logging preferences and data management

### Testing
- ✅ **Unit Tests**: CallManager, AssistantCallCoordinator, SessionLogger, AuthService
- ✅ **Mock Infrastructure**: MockCallKit, MockURLProtocol for isolated testing
- ✅ **Test Coverage**: All critical paths have test coverage

### Data Models
- ✅ **Session Models**: Session, SessionSummary, Turn, SessionListItem
- ✅ **Snake_case Decoding**: All models decode server's snake_case responses
- ✅ **Empty Response Handling**: Properly handles 204 No Content responses

### Error Handling
- ✅ **Error Recovery UI**: User-visible alerts for failures
- ✅ **Error Propagation**: Errors flow from services → coordinators → UI

---

## ⚠️ What's NOT Working Yet

### Critical: LiveKit Integration
**Status:** Placeholder/simulated only

**Current Behavior:**
- `LiveKitService.connect()` simulates connection after 0.5 seconds
- No actual audio streaming
- No microphone publishing
- No audio subscription

**What Needs to Happen:**
1. Add LiveKit Swift SDK via Swift Package Manager
2. Uncomment integration code in `Services/LiveKitService.swift`
3. Test with real LiveKit server

**Files to Update:**
- `Services/LiveKitService.swift` (lines 37-166 contain commented integration code)

### Backend Connection
**Status:** Client ready, but needs configuration

**What's Missing:**
- Backend API base URL (currently `https://api.example.com/v1`)
- Real authentication endpoint implementation
- LiveKit server URL and token generation

**Files to Update:**
- `Services/SessionLogger.swift` (line 9: update `baseURL`)
- `Services/AuthService.swift` (line 111: update login endpoint)

### CarPlay Entitlement
**Status:** Configured but needs Apple approval

**What's Needed:**
- Request CarPlay Communication entitlement from Apple Developer Portal
- Update provisioning profiles once approved
- Without this, app won't appear in CarPlay

---

## 🚀 Getting Started

### Prerequisites
- Xcode 15.2+
- iOS 17.2+ deployment target
- Apple Developer account (for CarPlay entitlement)
- LiveKit server (for audio streaming)
- Backend API (for sessions and authentication)

### Setup Steps

1. **Clone Repository**
   ```bash
   git clone https://github.com/jjeremycai/ai-voice-copilot-carplay.git
   cd ai-voice-copilot-carplay
   ```

2. **Open in Xcode**
   ```bash
   open CarPlaySwiftUI.xcodeproj
   ```

3. **Add LiveKit SDK** (Required for audio streaming)
   - In Xcode: File → Add Packages...
   - URL: `https://github.com/livekit/client-swift`
   - Add to target: `CarPlaySwiftUI`

4. **Configure Backend URL**
   - Edit `Services/SessionLogger.swift`
   - Update line 9: `private let baseURL = "https://your-api.com/v1"`

5. **Configure Authentication** (if needed for development)
   - Edit `Services/AuthService.swift`
   - Update line 111: `guard let url = URL(string: "https://your-api.com/v1/auth/login")`
   - Or use `AuthService.shared.setToken("dev-token")` for testing

6. **Run Tests**
   ```bash
   # In Xcode: Cmd+U
   # Or via command line:
   xcodebuild test -scheme CarPlaySwiftUI -destination 'platform=iOS Simulator,name=iPhone 15'
   ```

---

## 🔧 Integration Guide

### Step 1: Enable LiveKit SDK

1. **Add Package Dependency**
   - Xcode → File → Add Packages...
   - Enter: `https://github.com/livekit/client-swift`
   - Select version (latest stable)
   - Add to `CarPlaySwiftUI` target

2. **Uncomment LiveKit Code**
   - Open `Services/LiveKitService.swift`
   - Uncomment line 12: `import LiveKit`
   - Uncomment lines 37-64 (connect method)
   - Uncomment lines 76-94 (disconnect method)
   - Uncomment lines 104-112 (publishMicrophone)
   - Uncomment lines 118-130 (subscribeToAssistantAudio)
   - Uncomment lines 145-166 (RoomDelegate)

3. **Update Code for Actual SDK**
   The commented code is a template. You may need to adjust:
   - Room initialization parameters
   - Track creation options
   - Delegate method signatures (check LiveKit SDK docs)

4. **Test Connection**
   - Ensure backend returns valid LiveKit URL and token
   - Test with real LiveKit server
   - Verify audio streaming works

### Step 2: Connect Backend

1. **Update API Base URL**
   ```swift
   // Services/SessionLogger.swift
   private let baseURL = "https://your-production-api.com/v1"
   ```

2. **Implement Authentication**
   - Update `AuthService.login()` with real endpoint
   - Ensure backend returns `{ "token": "...", "expires_at": "..." }`
   - Test token storage and refresh

3. **Verify API Endpoints**
   All endpoints should return snake_case JSON:
   - `POST /v1/sessions/start` → `{ "session_id", "livekit_url", "livekit_token", "room_name" }`
   - `POST /v1/sessions/end` → `204 No Content`
   - `GET /v1/sessions` → `[{ "id", "title", "summary_snippet", "started_at", "ended_at" }]`
   - `GET /v1/sessions/:id` → `{ "summary": {...}, "turns": [...] }`
   - `POST /v1/sessions/:id/turn` → `200 OK`
   - `DELETE /v1/sessions/:id` → `204 No Content`

### Step 3: Request CarPlay Entitlement

1. **Apple Developer Portal**
   - Go to Certificates, Identifiers & Profiles
   - Select your App ID
   - Enable "CarPlay Communication" capability
   - Submit request to Apple

2. **Wait for Approval**
   - Apple typically reviews within 1-2 weeks
   - You'll receive email notification

3. **Update Provisioning Profiles**
   - Download updated profiles
   - Xcode will automatically use them

4. **Test on Device**
   - Connect iPhone to CarPlay-enabled vehicle or simulator
   - Verify app appears in CarPlay
   - Test "Talk to Assistant" flow

---

## 📁 Project Structure

```
carplay-swiftui-master/
├── Services/
│   ├── CallManager.swift              ✅ Complete - CallKit wrapper
│   ├── CallKitProtocols.swift          ✅ Complete - DI protocols
│   ├── LiveKitService.swift            ⚠️ Placeholder - needs SDK integration
│   ├── SessionLogger.swift             ✅ Complete - needs backend URL
│   └── AuthService.swift               ✅ Complete - needs login endpoint
├── Coordinators/
│   ├── AppCoordinator.swift            ✅ Complete
│   └── AssistantCallCoordinator.swift ✅ Complete
├── Models/
│   ├── Session.swift                   ✅ Complete - snake_case decoding
│   └── UserSettings.swift              ✅ Complete
├── Screens/
│   ├── HomeScreen.swift                ✅ Complete
│   ├── OnboardingScreen.swift          ✅ Complete
│   ├── SessionsListScreen.swift        ✅ Complete
│   ├── SessionDetailScreen.swift       ✅ Complete
│   └── SettingsScreen.swift            ✅ Complete
├── CarPlaySceneDelegate.swift          ✅ Complete
├── CarPlaySwiftUITests/
│   ├── Mocks/
│   │   ├── MockCallKit.swift          ✅ Complete
│   │   └── MockURLProtocol.swift      ✅ Complete
│   ├── CallManagerTests.swift          ✅ Complete
│   ├── AssistantCallCoordinatorTests.swift ✅ Complete
│   ├── SessionLoggerTests.swift        ✅ Complete
│   └── AuthServiceTests.swift          ✅ Complete
└── Documentation/
    ├── MASTER_SPEC.md                  ✅ Complete spec
    ├── IMPLEMENTATION_STATUS.md        ✅ Status tracking
    └── FIXES_APPLIED.md                ✅ Fix history
```

---

## 🧪 Testing

### Running Tests
```bash
# All tests
xcodebuild test -scheme CarPlaySwiftUI -destination 'platform=iOS Simulator,name=iPhone 15'

# Specific test suite
xcodebuild test -scheme CarPlaySwiftUI -only-testing:CarPlaySwiftUITests/CallManagerTests
```

### Test Coverage
- ✅ CallManager: Call initiation, termination, error handling
- ✅ AssistantCallCoordinator: State transitions, context propagation
- ✅ SessionLogger: Request structure, authentication, decoding
- ✅ AuthService: Token storage, retrieval, expiry

### Mock Infrastructure
- **MockCallKit**: Simulates CallKit without system dependencies
- **MockURLProtocol**: Intercepts network requests for testing
- All tests run without network access or system permissions

---

## 🔍 Key Implementation Details

### Context Propagation
**How it works:**
- `startAssistantCall(context: "carplay" | "phone")` stores context
- Context flows: UI → Coordinator → SessionLogger → Backend
- Backend receives correct context for analytics

**Files:**
- `Coordinators/AssistantCallCoordinator.swift` (lines 29, 40-41, 84)

### Authentication Flow
**Current State:**
- Token stored in Keychain via `AuthService`
- All API calls include `Authorization: Bearer <token>` header
- `SessionLogger.createAuthenticatedRequest()` handles this automatically

**For Development:**
```swift
// Set token directly (bypasses login)
AuthService.shared.setToken("your-dev-token")
```

**For Production:**
- Implement `AuthService.login()` with real endpoint
- Handle token refresh (currently placeholder)

### Error Handling
**Error Flow:**
1. Service throws error (e.g., `SessionLoggerError`)
2. Coordinator catches, sets `errorMessage`
3. UI observes `errorMessage`, shows alert

**Files:**
- `Coordinators/AssistantCallCoordinator.swift` (line 21: `@Published var errorMessage`)
- `Screens/HomeScreen.swift` (lines 50-59, 88-99: error display)

### Snake_case Decoding
**Implementation:**
- `SessionLogger.createDecoder()` sets `keyDecodingStrategy = .convertFromSnakeCase`
- All models have explicit `CodingKeys` for clarity
- Works with backend's snake_case responses

**Files:**
- `Services/SessionLogger.swift` (lines 21-26: `createDecoder()`)
- `Models/Session.swift` (all structs have `CodingKeys`)

### Empty Response Handling
**Implementation:**
- `handleResponse()` checks for empty data or 204 status
- Returns `EmptyResponse()` without JSON decoding
- Prevents `dataCorrupted` errors

**Files:**
- `Services/SessionLogger.swift` (lines 49-56: empty response handling)

---

## 🐛 Known Issues & Limitations

### Current Limitations
1. **LiveKit**: Not integrated - simulated only
2. **Backend**: Uses placeholder URL - needs real endpoint
3. **Auth**: Login endpoint not implemented - use `setToken()` for dev
4. **CarPlay**: Entitlement pending Apple approval
5. **Error Recovery**: Basic - no retry logic or offline mode

### Fixed Issues (Already Resolved)
- ✅ CallKit test crashes (fixed with real CXProvider instance)
- ✅ Snake_case decoding (all endpoints use `createDecoder()`)
- ✅ Empty response handling (204 responses handled correctly)
- ✅ Context propagation (CarPlay vs phone properly tracked)

---

## 📝 Next Steps (Priority Order)

### High Priority
1. **Integrate LiveKit SDK**
   - Add package dependency
   - Uncomment and activate integration code
   - Test audio streaming end-to-end

2. **Connect Backend**
   - Update API base URL
   - Implement authentication endpoint
   - Test all API endpoints

3. **Request CarPlay Entitlement**
   - Submit to Apple Developer Portal
   - Wait for approval
   - Test on physical device

### Medium Priority
4. **Enhanced Error Handling**
   - Add retry logic for network failures
   - Implement offline mode detection
   - Better error messages

5. **Integration Testing**
   - End-to-end call flow tests
   - CarPlay integration tests
   - Network failure simulation

### Low Priority
6. **UI Polish**
   - Loading states during call setup
   - Better connection status indicators
   - Animation improvements

---

## 🔐 Security Considerations

### Current Implementation
- ✅ Tokens stored in Keychain (secure)
- ✅ All API calls over HTTPS (when backend configured)
- ✅ No sensitive data in logs
- ✅ User consent for logging (onboarding)

### Recommendations
- Review token refresh strategy
- Implement certificate pinning for production
- Add rate limiting for API calls
- Audit Keychain access patterns

---

## 📚 Documentation References

### Internal Docs
- `MASTER_SPEC.md` - Complete product specification
- `IMPLEMENTATION_STATUS.md` - Current implementation status
- `FIXES_APPLIED.md` - History of fixes and improvements

### External Docs
- [LiveKit Swift SDK](https://github.com/livekit/client-swift)
- [CallKit Documentation](https://developer.apple.com/documentation/callkit)
- [CarPlay Guidelines](https://developer.apple.com/carplay/)

---

## 💡 Development Tips

### Testing Without Backend
```swift
// Set a dev token
AuthService.shared.setToken("dev-token-123")

// Mock responses will be used in tests automatically
```

### Testing Call Flow
```swift
// In tests, use mocks
let mockProvider = MockCXProvider(configuration: config)
let mockController = MockCXCallController()
let callManager = CallManager(provider: mockProvider, callController: mockController)
```

### Debugging CarPlay
- Use CarPlay Simulator in Xcode
- Check Console for CarPlay-specific logs
- Verify entitlements are properly configured

### Common Issues

**Issue:** Tests fail with "Could not cast MockCXProvider to CXProvider"
- **Status:** ✅ Fixed - uses real CXProvider instance now

**Issue:** API responses fail to decode
- **Check:** Ensure backend returns snake_case (e.g., `session_id` not `sessionId`)
- **Verify:** `createDecoder()` is used everywhere

**Issue:** 204 responses cause decoding errors
- **Status:** ✅ Fixed - empty responses handled correctly

---

## 📞 Questions?

If you have questions about:
- **Architecture decisions**: Check `MASTER_SPEC.md`
- **Implementation details**: Check code comments
- **Test failures**: Check `FIXES_APPLIED.md` for known issues
- **Next steps**: See "Next Steps" section above

---

## 🎯 Success Criteria

The project is ready for production when:
- ✅ LiveKit SDK integrated and streaming audio
- ✅ Backend API connected and authenticated
- ✅ CarPlay entitlement approved and working
- ✅ All tests passing
- ✅ End-to-end call flow verified
- ✅ Error handling robust
- ✅ User experience polished

---

**Good luck! The foundation is solid. Focus on LiveKit integration and backend connection to get this to production.** 🚀

