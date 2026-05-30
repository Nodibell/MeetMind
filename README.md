# MeetMind 🧠🎤

**MeetMind** is a modern macOS application for automatic meeting transcription and AI-powered summary generation. The entire process runs locally on your device, ensuring maximum privacy.

![App Icon](meetmind_app_icon.png)

## Key Features ✨

- **ECAPA-TDNN Speaker Diarization & RMS VAD**: State-of-the-art voice activity detection using Root-Mean-Square (RMS) signal energy thresholds on short-time audio slices (filters silence below `-45dB`), coupled with a pretrained CoreML `ECAPATDNN` speaker embedding extractor (192-dimensional voiceprints) and Agglomerative Hierarchical Clustering (AHC) to dynamically estimate speaker counts on the fly via a Cosine distance threshold ($< 0.45$).
- **Mutual Exclusivity VRAM/RAM Manager**: Thread-safe global actor `ModelMemoryManager` coordinating the dynamic loading and unloading of high-memory models (WhisperKit STT and Local MLX LLM engines). Metal command buffers and transient heaps are completely purged from GPU cache upon swap to avoid Out-Of-Memory (OOM) kernel panics on base Apple Silicon configurations.
- **Parent-Child Hierarchical RAG Architecture**: Advanced local knowledge base indexer that partitions speaker turns (`TranscriptSegment`) into overlapping sliding window sub-chunks (`ChildEmbeddingEntity`, 120 chars, 30 overlap) for high-recall search, but retrieves the complete parent segment expanded with a chronological context window of $\pm 2$ neighboring segments for maximum generation coherence in the Q&A Chat.
- **Hybrid Search & Reciprocal Rank Fusion (RRF)**: High-performance search combining precision virtual SQLite FTS5 table keyword MATCH queries with vector-based semantic proximity (calculated using Apple's Accelerate framework `vDSP` dot-product functions on Apple Silicon). Both retrieval lists are synthesized using Reciprocal Rank Fusion (RRF) with a smoothing parameter ($k=60$) to order the best results.
- **Local Multi-Meeting RAG**: Group multiple meeting transcripts and audio recordings into folder structures (groups) using dynamic drag-and-drop or explicit search sheets, and run semantic queries across all transcripts inside the folder concurrently using custom local embeddings.
- **Persistent Conversation Threads (Multi-Session Chats)**: Manage multiple conversation sessions under each meeting group, supporting creating, switching, and deleting conversation threads with smart auto-naming based on the first query.
- **Local Transcription**: Uses Apple's WhisperKit for high-quality speech recognition directly on your Mac (CPU/Neural Engine) with a dedicated **Whisper Language Picker** (Auto-detect, Ukrainian, English).
- **Target Summary/Notes Language**: Choose whether your final Obsidian meeting notes and action items are written in Ukrainian, English, or dynamically match the transcript language.
- **Meeting Intelligence Database**: Relational SwiftData models for `TranscriptSegmentModel`, `ActionItem` (with live two-way toggle-to-file sync), and `Decision`, enabling high-performance local SQL queries.
- **Resilient Database Auto-Recovery & Backups**: Multi-tiered initializer that detects schema conflicts, copies database files safely to `Backups/MeetMind.store.backup-<timestamp>`, and uses in-app banners for non-destructive diagnostics.
- **Deep Search & Vault-Independent AI**: Full-text sidebar search over transcript segments, and local semantic AI queries that run 100% offline without demanding an Obsidian Vault path.
- **System Audio Support**: Record your microphone, system audio (Zoom/Google Meet), or both simultaneously using ScreenCaptureKit.
- **Pause & Resume**: Full control over your recording sessions with the ability to pause and continue without losing context.
- **AI Summaries & Premium Chat Q&A**: Automatically generate key takeaways and action items, and ask questions in an overhauled, beautiful **Meeting Q&A Chat** with modern message bubbles, real-time streaming, and native markdown copy controls.
- **Obsidian Export**: Direct integration with your Obsidian vault for seamless workflow automation.
- **Floating Status Indicator**: A sleek, borderless overlay that shows real-time recording status and active speaker identification.
- **Privacy First**: Your data never leaves your device. No cloud APIs are used for transcription or analysis.
- **Modern & Adaptive Design**: Sleek macOS interface with Glassmorphism, a professional onboarding experience, and **fully native, live-switching Light, Dark, and System Theme preferences**.

## Tech Stack 🛠

- **Swift & SwiftUI**: Modern interface and high performance.
- **WhisperKit**: OpenAI Whisper port by Argmax optimized for CoreML.
- **ECAPA-TDNN CoreML**: Pretrained neural network voiceprint extractor.
- **Ollama, LM Studio & DeepMLX**: Multiple local LLM integration pathways with dynamic memory unloading and VRAM actor optimization.
- **SwiftData**: Reliable persistence for hierarchical meetings, groups, child embeddings, and summaries.
- **ScreenCaptureKit**: High-quality audio capture.

## Getting Started 🚀

### Prerequisites
- macOS 14.0+
- [Ollama](https://ollama.com/) (installed and running)
- Whisper Models (downloaded automatically on first run)

### Installation

#### Option 1: Quick Install (Recommended)
1. Download the latest packaged release disk image: **[MeetMind_v1.5.0.dmg](https://github.com/Nodibell/MeetMind/releases/download/v1.5.0/MeetMind_v1.5.0.dmg)**.
2. Open the `.dmg` file and drag **MeetMind** to your **Applications** folder.

#### Option 2: Build from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/Nodibell/MeetMind.git
   ```
2. Open `MeetMind.xcodeproj` in Xcode.
3. Ensure all Swift Packages are resolved.
4. Click **Run** (Cmd + R).

## Configuration ⚙️

1. **Obsidian**: Select your vault folder in the app settings for automatic export.
2. **Local LLM Settings**: 
   * **Ollama**: Choose your model and endpoint (default: `http://localhost:11434`).
   * **LM Studio**: Compatible with local OpenAI-compatible servers (default: `http://localhost:1234`).
   * **DeepMLX**: Point directly to local Apple Silicon Metal-optimized MLX model sharded weight directories for zero-server direct local inference.
   * **Memory Management**: Customize the inactivity auto-unload VRAM/RAM timer to conserve your Mac's hardware resources.
3. **Language**: Independently choose the Whisper transcription language and the target Obsidian summary language.

## Privacy 🔒

MeetMind collects absolutely zero data. Audio transcription is processed locally via CoreML, and meeting summaries are generated by a local instance of Ollama.

> **Note on network entitlement**: The app sandbox includes `com.apple.security.network.client` to communicate with local servers (Ollama at `localhost:11434`, LM Studio at `localhost:1234`) and to download Whisper model weights on first launch. No audio, transcripts, or meeting data are ever sent to external services.

## License 📄

This project is licensed under the MIT License. See the `LICENSE` file for details.
