================================================================================
                    SMART GEO-TAGGED LANDMARKS APPLICATION
                         CSE 489: Mobile App Development
                              Lab Exam (v5)
                              
                            Student ID: 24241348
================================================================================

PROJECT OVERVIEW
================================================================================

This is a Flutter-based Android mobile application designed to interact with 
a faculty-provided REST API for managing and visualizing Smart Geo-Tagged 
Landmarks. The application enables users to:

- View a list of landmarks with their titles, images, and activity-based scores
- Display landmarks on a map with color-coded markers reflecting scores
- Visit landmarks using GPS location and receive distance calculations
- Browse visit history and user activity
- Create new landmarks with images and GPS coordinates
- Work offline with local caching and automatic sync when connectivity returns

The app implements a modern MVVM architecture with Repository pattern, using 
Room for local data persistence, Retrofit for API communication, and WorkManager 
for reliable background job processing.

API Endpoint: https://labs.anontech.info/cse489/exm3/api.php
Base URL includes student key in query parameters (e.g., ?action=get_landmarks&key=YOUR_KEY)

================================================================================

FEATURES IMPLEMENTED
================================================================================

1. LANDMARKS DISPLAY (Core Requirement 1)
   ✓ Fetch landmarks from REST API using Retrofit
   ✓ Display landmark list with Title, Score, and Image
   ✓ Handle dynamic data updates correctly
   ✓ Cache data locally using Room database
   ✓ Support pulling-to-refresh for live updates

2. MAP VIEW (Core Requirement 2)
   ✓ Display all landmarks on Google Maps
   ✓ Center map on Bangladesh (coordinates: ~23.6850°N, 90.3563°E)
   ✓ Color-coded markers reflecting score values (gradient: red → yellow → green)
   ✓ Interactive markers showing landmark details on click
   ✓ InfoWindow displays title, score, and current visit count

3. VISIT FEATURE (Core Requirement 3) - IMPORTANT
   ✓ Get current GPS location using Fused Location Provider
   ✓ Send visit_landmark request (POST) and receive job_id
   ✓ Poll get_job_status asynchronously in background (using WorkManager)
   ✓ Non-blocking UI during job polling
   ✓ Display calculated distance once job completes
   ✓ Show success/failure messages via Toast/Snackbar
   ✓ Handle job status polling with retry mechanism

4. LANDMARKS LIST (Core Requirement 4)
   ✓ Display all landmarks in RecyclerView format
   ✓ Show Title, Score, and Image for each landmark
   ✓ Sort by score (ascending/descending)
   ✓ Filter by minimum score threshold
   ✓ Real-time updates from database

5. ACTIVITY SCREEN - VISIT HISTORY (Core Requirement 5)
   ✓ Display recent visits in chronological order
   ✓ Show Landmark name, Visit timestamp, and Distance traveled
   ✓ Persistent storage of visit history in Room database
   ✓ Support clearing history

6. ADD LANDMARK (Core Requirement 6)
   ✓ Input fields: Title, Latitude, Longitude, Image
   ✓ Auto-fetch GPS location for current position
   ✓ Image picker integration (Photo Picker API)
   ✓ Form validation for all fields
   ✓ Submit as multipart/form-data (NOT raw JSON for file uploads)

7. SOFT DELETE HANDLING (Core Requirement 7)
   ✓ Deleted landmarks removed from list display
   ✓ Support restore_landmark endpoint
   ✓ Graceful handling of data changes
   ✓ No crashes on delete/restore operations

8. OFFLINE SUPPORT (Core Requirement 8 - MANDATORY)
   ✓ Cache all fetched landmarks locally (Room database)
   ✓ Display cached data when device is offline
   ✓ Queue visit requests when offline with pending status
   ✓ Sync queued requests automatically when connectivity returns
   ✓ Handle offline failures gracefully

9. ERROR HANDLING (Core Requirement 9)
   ✓ Success messages via Toast/Snackbar
   ✓ Error dialogs for API failures
   ✓ Network error detection and user notification
   ✓ Graceful API error responses (e.g., HTTP 403 for invalid key)
   ✓ Input validation and user guidance

10. BACKGROUND JOB QUEUE (Core Requirement 10)
    ✓ WorkManager for polling get_job_status asynchronously
    ✓ Survival across app restarts
    ✓ Retry logic with exponential backoff
    ✓ Drain offline visit queue when connectivity restored
    ✓ Update local cache/UI with job results

UI STRUCTURE
   ✓ Bottom Navigation with 4 tabs:
     - Map: Google Maps view with all landmarks
     - Landmarks: List view with sorting/filtering
     - Activity: Visit history
     - Add/View: Create new landmarks or view landmark details

================================================================================

API USAGE
================================================================================

API Base URL: https://labs.anontech.info/cse489/exm3/api.php

Authentication: Student key passed as URL parameter (?key=YOUR_KEY)

Endpoints Implemented:

1. GET_LANDMARKS
   GET ?action=get_landmarks&key=YOUR_KEY
   Response: List of landmarks with fields:
   - id: Landmark unique identifier
   - title: Landmark name
   - lat, lon: Geographic coordinates
   - image: Image URL
   - score: Activity-based score
   - visit_count: Number of visits
   - avg_distance: Average visit distance

2. VISIT_LANDMARK (Asynchronous)
   POST ?action=visit_landmark&key=YOUR_KEY
   Body (JSON):
   {
     "landmark_id": <integer>,
     "user_lat": <float>,
     "user_lon": <float>
   }
   Response: { "job_id": <integer>, "status": "pending" }
   
   Note: Visit is not processed immediately. App must poll job status.

3. GET_JOB_STATUS
   GET ?action=get_job_status&key=YOUR_KEY&job_id=<job_id>
   Polling responses:
   - Pending: { "job_id": <id>, "status": "pending" }
   - Completed: { "job_id": <id>, "status": "done", "distance": <float> }
   - Not Found: HTTP 404 { "error": "job_not_found" }
   
   Expected delay: 1-5 seconds before job completion

4. CREATE_LANDMARK
   POST ?action=create_landmark&key=YOUR_KEY
   Body (multipart/form-data):
   - landmark[title]: Landmark title string
   - landmark[lat]: Latitude float
   - landmark[lon]: Longitude float
   - landmark[image]: Image file
   
   Note: Must use form-data, NOT raw JSON

5. DELETE_LANDMARK (Soft Delete)
   POST ?action=delete_landmark&key=YOUR_KEY
   Body: { "landmark_id": <integer> }

6. RESTORE_LANDMARK
   POST ?action=restore_landmark&key=YOUR_KEY
   Body: { "landmark_id": <integer> }

Error Response:
   HTTP 403 with body: { "error": "invalid_or_expired_key" }

================================================================================

OFFLINE STRATEGY
================================================================================

The application implements a comprehensive offline-first architecture:

1. LOCAL DATA CACHE (Room Database)
   - Landmarks table: Caches all fetched landmarks with full metadata
   - Visit history table: Stores all completed visits
   - Offline queue table: Persists pending visit requests
   - Job tracking table: Maintains polling state for async jobs

2. OFFLINE LANDMARK DISPLAY
   - On app launch: Check network connectivity
   - If offline: Load landmarks from Room database
   - If online: Fetch fresh from API and update cache
   - Display cached data in all views (Map, List, Details)

3. OFFLINE VISIT QUEUE
   - When user visits landmark offline:
     * Create pending Visit object in Room
     * Store landmark_id, user_lat, user_lon, timestamp
     * Mark status as "pending"
     * Show "Queued" badge in UI
   - Display to user: "Visit queued. Will sync when online."
   
4. SYNC MECHANISM (WorkManager)
   - Monitors network connectivity changes
   - On connectivity restored:
     * Retrieve all pending visits from offline queue
     * Re-submit each visit to API
     * Handle retry on failure (exponential backoff: 15s → 30s → 60s)
     * Maximum 3 retry attempts
     * Remove from queue on success
   
5. JOB STATUS POLLING
   - WorkManager polls get_job_status every 3 seconds
   - Stops polling when job completes
   - Stores distance in local cache
   - Updates UI through LiveData/StateFlow

6. DATA CONSISTENCY
   - Single source of truth: Room database
   - API fetches update Room, not directly update UI
   - Background work writes to Room
   - UI observes Room through reactive streams
   - No stale data conflicts

================================================================================

ARCHITECTURE USED
================================================================================

Architecture Pattern: MVVM (Model-View-ViewModel) with Repository Pattern

Layer Structure:

┌─────────────────────────────────────────────────────────────────┐
│                            UI LAYER                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│  │ MapView  │  │ ListView │  │Activity  │  │ AddView  │         │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘         │
│       │             │             │            │                 │
│       └─────────────┼─────────────┼────────────┘                 │
│                     │             │                              │
└─────────────────────┼─────────────┼──────────────────────────────┘
                      │             │
┌─────────────────────┼─────────────┼──────────────────────────────┐
│                     ▼             ▼                              │
│               VIEWMODEL LAYER                                    │
│  ┌────────────────────────────────────────────────────────┐     │
│  │ LandmarkViewModel, VisitViewModel, MapViewModel        │     │
│  │ - Manages UI state via LiveData/StateFlow              │     │
│  │ - Handles user interactions                            │     │
│  │ - Coordinates with repository                          │     │
│  └────────────────────────────────────────────────────────┘     │
│                            │                                    │
└────────────────────────────┼────────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────────┐
│                            ▼                                    │
│                 REPOSITORY LAYER                               │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ LandmarkRepository, VisitRepository, JobRepository     │   │
│  │ - Abstract data sources (local & remote)               │   │
│  │ - Handle data fetching, caching, sync logic            │   │
│  │ - Coordinate offline/online strategies                 │   │
│  └────────────────────────────────────────────────────────┘   │
│              │                           │                    │
└──────────────┼───────────────────────────┼────────────────────┘
               │                           │
    ┌──────────▼─────────────┐  ┌──────────▼──────────────┐
    │   LOCAL DATA LAYER     │  │   REMOTE DATA LAYER    │
    │  (Room Database)       │  │  (REST API - Retrofit) │
    │                        │  │                        │
    │ ┌────────────────────┐ │  │ ┌────────────────────┐ │
    │ │ Landmarks DAO      │ │  │ │ API Service        │ │
    │ │ Visits DAO         │ │  │ │ - GET landmarks    │ │
    │ │ Jobs DAO           │ │  │ │ - POST visit       │ │
    │ │ Offline Queue DAO  │ │  │ │ - GET job status   │ │
    │ └────────────────────┘ │  │ │ - POST create      │ │
    │                        │  │ │ - POST delete      │ │
    │ SQLite Database        │  │ └────────────────────┘ │
    └────────────────────────┘  └────────────────────────┘

Background Work:

┌──────────────────────────────────────────────────────┐
│              WORKMANAGER LAYER                       │
│  ┌────────────────────────────────────────────────┐  │
│  │ JobStatusPollingWorker                         │  │
│  │ - Polls get_job_status for pending jobs        │  │
│  │ - Updates Room with results                    │  │
│  │ - Retries on network failure                   │  │
│  └────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────┐  │
│  │ OfflineSyncWorker                              │  │
│  │ - Drains offline visit queue                   │  │
│  │ - Resubmits visits when online                 │  │
│  │ - Retry with exponential backoff               │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘

Key Components:

- ViewModels: Observe data from repositories via LiveData/StateFlow
- Repositories: Aggregate data from Room (local) and Retrofit (remote)
- Room Database: Single source of truth for all data
- WorkManager: Handles async jobs that survive app restart
- Retrofit: Type-safe HTTP client for API communication
- Google Maps SDK: Map integration with custom markers
- Fused Location Provider: Current GPS location retrieval

Data Flow Example (Visit Landmark):
1. User clicks "Visit" button in UI
2. ViewModel requests visit from Repository
3. Repository fetches current location (Fused Location Provider)
4. Repository submits visit_landmark POST request via Retrofit API
5. API returns job_id
6. Repository saves pending job to Room JobsTable
7. WorkManager JobStatusPollingWorker starts polling
8. Polling updates Room with job status
9. UI observes Room and updates display with distance
10. On success, visit saved to VisitHistory table

================================================================================

CHALLENGES FACED
================================================================================

1. ASYNCHRONOUS JOB HANDLING
   Challenge: Visit processing is now asynchronous (v5 update). App must 
   poll job status without blocking UI.
   
   Solution Implemented:
   - WorkManager polls get_job_status every 3 seconds
   - UI updates via LiveData observation pattern
   - NoSQL database tracks pending jobs
   - Graceful timeout handling after max attempts

2. OFFLINE-FIRST ARCHITECTURE
   Challenge: App must work offline, cache data, and sync when online.
   
   Solution Implemented:
   - Room database as single source of truth
   - Offline visit queue table for pending visits
   - WorkManager monitors connectivity and auto-syncs
   - Retry logic with exponential backoff (15s → 30s → 60s)

3. FILE UPLOAD COMPLEXITY
   Challenge: Specification states "if you send raw JSON, $_FILES will be 
   empty server-side. For file upload you must use Body → form-data."
   
   Solution Implemented:
   - Used Retrofit @Multipart annotation
   - Created RequestBody objects for file fields
   - Wrapped parameters in @Part annotations
   - Tested with actual file uploads to API

4. BACKGROUND WORK PERSISTENCE
   Challenge: Background jobs (polling, sync) must survive app restart 
   and process unreliable connectivity gracefully.
   
   Solution Implemented:
   - WorkManager instead of manual Thread/Timer
   - Periodic work scheduling for polling
   - ExistingPeriodicWorkPolicy.KEEP to avoid duplicates
   - Database persistence of work state

5. SCORE-BASED MARKER COLORS
   Challenge: Need to map continuous score values to discrete colors 
   (red → yellow → green) for visual feedback.
   
   Solution Implemented:
   - Color interpolation algorithm
   - Min/max score detection from API data
   - Dynamic gradient mapping to color spectrum
   - Marker color updated on data refresh

6. NETWORK STATE DETECTION
   Challenge: Detecting connectivity changes and triggering sync logic.
   
   Solution Implemented:
   - ConnectivityManager broadcasts for network changes
   - BroadcastReceiver listening for CONNECTIVITY_ACTION
   - WorkManager enqueued on connectivity restoration

7. GPS LOCATION PERMISSIONS
   Challenge: Requesting and handling location permissions on Android 6.0+
   
   Solution Implemented:
   - AndroidX Permissions handling
   - RequestMultiplePermissions launchers
   - Fine and Coarse location permissions
   - User-friendly permission request dialogs

8. IMAGE HANDLING AND CACHING
   Challenge: Download, cache, and display images from API URLs efficiently
   
   Solution Implemented:
   - Glide image loading library with caching
   - Disk cache for offline image display
   - Placeholder and error images
   - Network-only or cache-only strategies based on connectivity

9. UI STATE MANAGEMENT ACROSS CONFIGURATION CHANGES
   Challenge: Maintaining UI state (filters, sort order, map zoom) across 
   screen rotations or other configuration changes.
   
   Solution Implemented:
   - ViewModel lifecycle management
   - SavedStateHandle for bundle-based state
   - LiveData observers persist across config changes

10. API KEY MANAGEMENT
    Challenge: Keeping student API key secure while allowing all requests.
    
    Solution Implemented:
    - API key stored in BuildConfig (build-time)
    - Interceptor adds key to all requests automatically
    - No hardcoding of key in source files
    - Configuration for build variants if needed

================================================================================

TECHNOLOGY STACK
================================================================================

Core Framework:
- Flutter 3.x / Dart 3.x (Mobile App)
- Android minimum SDK: 21
- Target SDK: 34

Architecture & DI:
- MVVM + Repository Pattern
- GetIt (or similar) for dependency injection

Local Data Persistence:
- Room Database (SQLite)
- Shared Preferences for configuration

Network Communication:
- Retrofit 2.x (REST API client)
- OkHttp 4.x (HTTP client with interceptors)
- Gson (JSON serialization)

Asynchronous & Background:
- WorkManager (background job processing)
- Coroutines / async-await patterns
- LiveData for reactive UI updates

Location & Maps:
- Google Maps API (display landmarks)
- Fused Location Provider (current GPS location)
- GoogleMaps SDK for Android

UI & Media:
- Material Design 3 components
- Bottom Navigation for tab navigation
- RecyclerView for list displays
- Glide for image loading and caching
- Photo Picker API for image selection

Connectivity:
- ConnectivityManager for network state
- BroadcastReceiver for connectivity changes

Logging & Debugging:
- Timber (logging library)
- Logcat for debugging

Testing:
- JUnit for unit tests
- Espresso for UI tests
- MockWebServer for API mocking

================================================================================

BUILD & DEPLOYMENT
================================================================================

Build System: Gradle (Kotlin DSL)

Project Structure:
```
App/
├── src/
│   ├── main/
│   │   ├── AndroidManifest.xml
│   │   ├── java/com/example/midterm_project/
│   │   │   ├── data/
│   │   │   │   ├── local/   (Room DAOs)
│   │   │   │   ├── remote/  (Retrofit services)
│   │   │   │   └── repository/
│   │   │   ├── ui/
│   │   │   │   ├── screens/  (Fragment views)
│   │   │   │   ├── viewmodels/
│   │   │   │   └── adapters/
│   │   │   ├── workers/  (WorkManager workers)
│   │   │   ├── models/   (Data classes)
│   │   │   ├── utils/    (Helpers)
│   │   │   └── MainActivity.kt
│   │   └── res/
│   │       ├── layout/  (XML layouts)
│   │       ├── values/  (Strings, colors, dimens)
│   │       ├── drawable/
│   │       └── mipmap/
│   └── test/
└── build.gradle.kts
```

Build Commands:
```
# Build debug APK
./gradlew assembleDebug

# Build release APK
./gradlew assembleRelease

# Run on connected device
./gradlew installDebug
./gradlew connectedAndroidTest
```

Dependencies (Summary):
- androidx.appcompat:appcompat
- androidx.lifecycle:lifecycle-runtime
- androidx.work:work-runtime
- androidx.room:room-runtime
- androidx.room:room-compiler
- com.google.android.gms:play-services-maps
- com.google.android.gms:play-services-location
- com.square.retrofit2:retrofit
- com.square.retrofit2:converter-gson
- com.squareup.okhttp3:okhttp
- com.github.bumptech.glide:glide
- com.google.code.gson:gson

================================================================================

HOW TO RUN
================================================================================

Prerequisites:
1. Android Studio 2022.1 or later
2. Java Development Kit (JDK) 11+
3. Android SDK with API level 21-34
4. Gradle 8.0+
5. Valid API key from course instructor

Setup Steps:

1. Clone/Open Project in Android Studio
   $ git clone <repository-url>
   $ cd App

2. Configure API Key
   - Open: App/src/main/java/.../BuildConfig.kt (or similar)
   - Set: API_KEY = "YOUR_STUDENT_KEY"
   - Alternative: Add to local.properties (excluded from git)

3. Install Dependencies
   $ ./gradlew build

4. Connect Android Device or Emulator
   - Enable USB debugging (if physical device)
   - Ensure ADB recognizes device: adb devices

5. Grant Permissions
   - Location permission: Allow when prompted
   - Camera permission: Allow when prompted

6. Build and Run
   $ ./gradlew installDebug
   # App launches automatically

7. Testing
   - Map view: Verify landmarks appear with correct markers
   - Visit feature: Tap landmark, allow location access, observe polling
   - Offline: Disable internet, verify cached data displays
   - Re-enable internet: Verify queued visits sync automatically

Troubleshooting:

- "Invalid or expired key" → Verify API key in code, check with instructor
- "Location permission denied" → Grant permission in Settings
- "Google Maps not displaying" → Ensure Google Maps API key in AndroidManifest.xml
- "Offline data not appearing" → Check Room database setup and migrations
- "WorkManager not polling" → Verify battery optimization settings (disable for app)

================================================================================

SUBMISSION DETAILS
================================================================================

GitHub Repository:
- Private repository created
- Instructor added as collaborator (GitHub: rahman9909)
- Repository structure:
  ├── App/          (Contains all source code, excluding Build folder)
  ├── Ai_usage.txt  (AI assistance justification)
  └── README.txt    (This file)

Submission Form:
https://forms.gle/3YvyKYNwb824yeH17

Deadline:
- 15th August 2026, Midnight (No late submissions accepted)
- Only ONE submission allowed

Academic Integrity:
- Code is original work with minimal AI assistance
- No copying of full projects or complete solutions
- Small snippets and ideas discussed with peers
- Code similarity checked by instructors

================================================================================

REFERENCES & RESOURCES
================================================================================

Official Documentation:
1. Google Maps Android API
   https://developers.google.com/maps/documentation/android-sdk/overview

2. OpenStreetMap Android Integration
   https://wiki.openstreetmap.org/wiki/Android

3. Retrofit: Type-Safe HTTP Client for Android
   https://square.github.io/retrofit/

4. Room: Save Data in Local Database
   https://developer.android.com/training/data-storage/room

5. CameraX
   https://developer.android.com/media/camera/camerax

6. Photo Picker API
   https://developer.android.com/training/data-storage/shared/photo-picker

7. Get Last Known Location
   https://developer.android.com/develop/sensors-and-location/location/retrieve-current

8. WorkManager: Background Work
   https://developer.android.com/topic/libraries/architecture/workmanager

Additional Resources:
- Android Developers Blog: https://android-developers.googleblog.com/
- Stack Overflow (Android tag)
- Android Architecture Components Guide

================================================================================

CONTACT & SUPPORT
================================================================================

Student Information:
- Name: [Your Name]
- ID: 24241348
- Course: CSE 489 - Mobile Application Development
- Institution: BRAC University

For Questions:
- Consult course materials and API documentation first
- Post clarifications on course forum
- Contact instructor via course email

================================================================================

END OF README
================================================================================
Date Created: August 15, 2026
Version: 1.0
Last Updated: August 15, 2026

================================================================================
