# Reception Log Feature — 開發規劃

> 目標：自動記錄每次接收 session 的 RADE 訊號品質數據與音訊，提供圖表分析功能。

---

## 1. 資料模型（SwiftData）

使用 SwiftData（iOS 17+）作為 App 內資料庫。若需支援 iOS 16 則改用 Core Data，schema 相同。

### 1.1 Schema 設計

```
┌─────────────────────────┐
│     ReceptionSession    │    一次 START → STOP 為一個 session
├─────────────────────────┤
│ id: UUID  (PK)          │
│ startTime: Date         │
│ endTime: Date?          │
│ duration: TimeInterval  │    計算值 = endTime - startTime
│ audioDevice: String     │    USB 音效卡名稱
│ sampleRateHz: Int       │    硬體取樣率（通常 48000）
│ audioFilename: String?  │    錄音檔名（相對路徑）
│ audioFileSize: Int64    │    檔案大小 bytes
│ totalModemFrames: Int   │    收到的 modem frame 總數
│ syncedFrames: Int       │    處於 SYNC 狀態的 frame 數
│ syncRatio: Double       │    計算值 = syncedFrames / totalModemFrames
│ peakSNR: Float          │    session 內最高 SNR
│ avgSNR: Float           │    session 內平均 SNR（僅 SYNC 期間）
│ callsignsDecoded: [String] │ 解碼到的呼號列表
│ notes: String           │    使用者備註
├─────────────────────────┤
│ ◆ snapshots: [SignalSnapshot]    1:N
│ ◆ syncEvents: [SyncEvent]        1:N
│ ◆ callsignEvents: [CallsignEvent] 1:N
└─────────────────────────┘

┌─────────────────────────┐
│     SignalSnapshot      │    高頻取樣的訊號品質快照
├─────────────────────────┤
│ id: UUID  (PK)          │
│ timestamp: Date         │    絕對時間
│ offsetMs: Int64         │    相對 session 開始的毫秒偏移（用於圖表 X 軸）
│ snr: Float              │    SNR (dB)，rade_snrdB_3k_est()
│ freqOffset: Float       │    頻率偏移 (Hz)，rade_freq_offset()
│ syncState: Int          │    0=SEARCH, 1=CANDIDATE, 2=SYNC
│ inputLevelDb: Float     │    輸入電平 (dB)
│ outputLevelDb: Float    │    輸出電平 (dB)
│ nin: Int                │    rade_nin() 當前值（反映 timing 追蹤）
│ clockOffset: Float      │    timing clock offset（如有）
├─────────────────────────┤
│ ◇ session: ReceptionSession     N:1
└─────────────────────────┘

┌─────────────────────────┐
│       SyncEvent         │    同步狀態變化事件
├─────────────────────────┤
│ id: UUID  (PK)          │
│ timestamp: Date         │
│ offsetMs: Int64         │
│ fromState: Int          │    0=SEARCH, 1=CANDIDATE, 2=SYNC
│ toState: Int            │
│ snrAtEvent: Float       │    狀態變化時的 SNR
│ freqOffsetAtEvent: Float│    狀態變化時的頻率偏移
├─────────────────────────┤
│ ◇ session: ReceptionSession     N:1
└─────────────────────────┘

┌─────────────────────────┐
│     CallsignEvent       │    EOO 呼號解碼事件
├─────────────────────────┤
│ id: UUID  (PK)          │
│ timestamp: Date         │
│ offsetMs: Int64         │
│ callsign: String        │    解碼到的呼號
│ snrAtDecode: Float      │    解碼時的 SNR
│ modemFrame: Int         │    解碼時的 modem frame 編號
├─────────────────────────┤
│ ◇ session: ReceptionSession     N:1
└─────────────────────────┘
```

### 1.2 SwiftData 實作

```swift
import SwiftData

@Model
class ReceptionSession {
    @Attribute(.unique) var id: UUID
    var startTime: Date
    var endTime: Date?
    var audioDevice: String
    var sampleRateHz: Int
    var audioFilename: String?
    var audioFileSize: Int64
    var totalModemFrames: Int
    var syncedFrames: Int
    var peakSNR: Float
    var avgSNR: Float
    var callsignsDecoded: [String]
    var notes: String
    
    @Relationship(deleteRule: .cascade, inverse: \SignalSnapshot.session)
    var snapshots: [SignalSnapshot]
    
    @Relationship(deleteRule: .cascade, inverse: \SyncEvent.session)
    var syncEvents: [SyncEvent]
    
    @Relationship(deleteRule: .cascade, inverse: \CallsignEvent.session)
    var callsignEvents: [CallsignEvent]
    
    var duration: TimeInterval {
        guard let end = endTime else { return Date().timeIntervalSince(startTime) }
        return end.timeIntervalSince(startTime)
    }
    
    var syncRatio: Double {
        guard totalModemFrames > 0 else { return 0 }
        return Double(syncedFrames) / Double(totalModemFrames)
    }
}

@Model
class SignalSnapshot {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var offsetMs: Int64
    var snr: Float
    var freqOffset: Float
    var syncState: Int        // 0=SEARCH, 1=CANDIDATE, 2=SYNC
    var inputLevelDb: Float
    var outputLevelDb: Float
    var nin: Int
    var clockOffset: Float
    
    var session: ReceptionSession?
}

@Model
class SyncEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var offsetMs: Int64
    var fromState: Int
    var toState: Int
    var snrAtEvent: Float
    var freqOffsetAtEvent: Float
    
    var session: ReceptionSession?
}

@Model
class CallsignEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var offsetMs: Int64
    var callsign: String
    var snrAtDecode: Float
    var modemFrame: Int
    
    var session: ReceptionSession?
}
```

### 1.3 ModelContainer 設定

```swift
// FreeDVApp.swift
@main
struct FreeDVApp: App {
    let container: ModelContainer
    
    init() {
        let schema = Schema([
            ReceptionSession.self,
            SignalSnapshot.self,
            SyncEvent.self,
            CallsignEvent.self
        ])
        let config = ModelConfiguration(
            "ReceptionLog",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        container = try! ModelContainer(for: schema, configurations: config)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
```

---

## 2. 數據擷取引擎

### 2.1 取樣策略

| 數據源 | 原始頻率 | 記錄頻率 | 說明 |
|--------|---------|---------|------|
| SNR | 每 modem frame (~8.3 Hz) | **每 modem frame** | rade_rx() 每次回傳後即取 rade_snrdB_3k_est() |
| 頻率偏移 | 每 modem frame (~8.3 Hz) | **每 modem frame** | rade_freq_offset() |
| 同步狀態 | 每 modem frame (~8.3 Hz) | **每 modem frame** | rade_sync() |
| 輸入電平 | 每 audio buffer (~100 Hz) | **每 modem frame** | 取最近一次 RMS 值 |
| 輸出電平 | 每 decoded frame | **每 modem frame** | FARGAN 輸出的 RMS |
| nin | 每 modem frame | **每 modem frame** | rade_nin() 值 |
| FFT 頻譜 | ~15 Hz (1024pt/50%overlap) | **不記錄到 DB** | 僅 UI 即時顯示，資料量太大 |
| 音訊 PCM | 8 kHz continuous | **連續寫入 WAV** | modem 原始輸入音訊 |

**每 modem frame 一筆 snapshot = 每 120ms 一筆 ≈ 每秒 8.3 筆。**

一小時的 session 約產生 30,000 筆 SignalSnapshot。每筆約 60 bytes，一小時約 1.8 MB 資料庫開銷，完全可接受。

### 2.2 資料擷取位置（嵌入 AudioManager）

在 `processingQueue` 上，`rade_rx()` 呼叫之後立即擷取：

```swift
// AudioManager.swift — processingQueue 中

// 現有的 rade_rx 呼叫之後加入：
let now = Date()
let offsetMs = Int64(now.timeIntervalSince(sessionStartTime) * 1000)

let snapshot = SignalSnapshot(
    id: UUID(),
    timestamp: now,
    offsetMs: offsetMs,
    snr: currentSNR,
    freqOffset: currentFreqOffset,
    syncState: currentSyncState,
    inputLevelDb: currentInputLevel,
    outputLevelDb: currentOutputLevel,
    nin: currentNin,
    clockOffset: 0  // 如有 timing 資訊
)

// 批量寫入（見 2.3）
snapshotBuffer.append(snapshot)
```

### 2.3 批量寫入策略

不要每筆 snapshot 都立即寫入 SwiftData，改用批量寫入減少 I/O：

```swift
class ReceptionLogger {
    private let modelContext: ModelContext
    private var currentSession: ReceptionSession?
    private var snapshotBuffer: [SignalSnapshot] = []
    private var lastSyncState: Int = 0
    
    private let flushInterval: TimeInterval = 5.0  // 每 5 秒寫入一次
    private let maxBufferSize = 100                 // 或累積 100 筆
    
    private var flushTimer: Timer?
    private let writeQueue = DispatchQueue(label: "receptionlog.write", qos: .utility)
    
    // 開始新 session
    func beginSession(audioDevice: String, sampleRate: Int) {
        let session = ReceptionSession(
            id: UUID(),
            startTime: Date(),
            audioDevice: audioDevice,
            sampleRateHz: sampleRate,
            // ... 初始值
        )
        currentSession = session
        modelContext.insert(session)
        
        // 開始定時 flush
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            self?.flushBuffer()
        }
    }
    
    // 每個 modem frame 呼叫
    func recordSnapshot(_ snapshot: SignalSnapshot) {
        snapshot.session = currentSession
        snapshotBuffer.append(snapshot)
        
        // 偵測同步狀態變化
        if snapshot.syncState != lastSyncState {
            let event = SyncEvent(/* ... */)
            event.session = currentSession
            modelContext.insert(event)
            lastSyncState = snapshot.syncState
        }
        
        // 更新 session 統計
        currentSession?.totalModemFrames += 1
        if snapshot.syncState == 2 { // SYNC
            currentSession?.syncedFrames += 1
            currentSession?.peakSNR = max(currentSession?.peakSNR ?? -99, snapshot.snr)
        }
        
        if snapshotBuffer.count >= maxBufferSize {
            flushBuffer()
        }
    }
    
    // 批量寫入
    private func flushBuffer() {
        guard !snapshotBuffer.isEmpty else { return }
        let batch = snapshotBuffer
        snapshotBuffer.removeAll(keepingCapacity: true)
        
        writeQueue.async { [weak self] in
            guard let self else { return }
            for snap in batch {
                self.modelContext.insert(snap)
            }
            try? self.modelContext.save()
        }
    }
    
    // 結束 session
    func endSession() {
        flushTimer?.invalidate()
        flushBuffer()
        currentSession?.endTime = Date()
        // 計算 avgSNR
        // ...
        try? modelContext.save()
    }
}
```

---

## 3. 音訊錄製

### 3.1 錄製策略

錄製 **8 kHz Int16 mono** 的 modem 輸入音訊（重採樣後、送入 rade_rx 之前的原始訊號）。

理由：
- 8 kHz Int16 = 16 KB/s = 57.6 MB/hr，大小合理
- 可事後用桌面版 FreeDV 重新解碼
- 保留完整的 OFDM modem 訊號

### 3.2 WAV Writer

```swift
class WAVRecorder {
    private var fileHandle: FileHandle?
    private var totalSamples: UInt32 = 0
    private let sampleRate: UInt32 = 8000
    private let bitsPerSample: UInt16 = 16
    private let channels: UInt16 = 1
    
    func start(filename: String) throws {
        let url = Self.recordingsDirectory.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: url)
        
        // 寫入 WAV header（先寫佔位，結束時更新）
        writeWAVHeader(dataSize: 0)
        totalSamples = 0
    }
    
    // 在 processingQueue 上呼叫，寫入重採樣後的 8kHz Int16 samples
    func writeSamples(_ samples: UnsafePointer<Int16>, count: Int) {
        let data = Data(bytes: samples, count: count * 2)
        fileHandle?.write(data)
        totalSamples += UInt32(count)
    }
    
    func stop() {
        // 回到開頭更新 WAV header 的 data size
        let dataSize = totalSamples * UInt32(bitsPerSample / 8) * UInt32(channels)
        fileHandle?.seek(toFileOffset: 4)
        writeUInt32(36 + dataSize)   // RIFF chunk size
        fileHandle?.seek(toFileOffset: 40)
        writeUInt32(dataSize)        // data chunk size
        
        fileHandle?.closeFile()
        fileHandle = nil
    }
    
    static var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

### 3.3 錄音檔管理

- 檔名格式：`rade_rx_20260323_143052.wav`（日期時間）
- 存放路徑：`Documents/Recordings/`
- Session 結束時將檔名存入 `ReceptionSession.audioFilename`
- 設定頁面提供「自動錄音」開關（預設開啟）
- 設定頁面提供「最大儲存空間」限制（如 2 GB），超過自動刪除最舊的錄音

---

## 4. 圖表規劃

使用 Swift Charts（iOS 16+）繪製。共規劃 6 種圖表。

### 4.1 SNR 時序圖（主圖表）

```
用途：觀察訊號品質隨時間的變化
類型：LineMark
X 軸：時間（offsetMs → 秒/分鐘）
Y 軸：SNR (dB)，範圍 -5 ~ 40 dB
附加：
  - 背景色帶：綠 (>6dB), 黃 (2~6dB), 紅 (<2dB) 對應不同品質區間
  - SyncEvent 標記：垂直虛線標示 SYNC/UNSYNC 時刻
  - CallsignEvent 標記：標註解碼到呼號的時刻
  - 可拖曳選取時間範圍放大
```

```swift
Chart(snapshots) { snap in
    LineMark(
        x: .value("Time", Double(snap.offsetMs) / 1000.0),
        y: .value("SNR", snap.snr)
    )
    .foregroundStyle(snrColor(snap.snr))
    .interpolationMethod(.monotone)
}
.chartYScale(domain: -5...40)
.chartYAxis {
    AxisMarks(values: stride(from: -5, through: 40, by: 5).map { $0 })
}
// 疊加 sync event 標記
.chartOverlay { proxy in
    // 在 syncEvents 位置繪製垂直虛線
}
```

### 4.2 頻率偏移時序圖

```
用途：觀察頻率穩定性（反映收發雙方頻率校準）
類型：LineMark
X 軸：時間
Y 軸：頻率偏移 (Hz)，範圍 ±20 Hz
附加：
  - 0 Hz 參考線
  - 標準差標註
  - 僅顯示 SYNC 期間的數據（SEARCH 時無意義）
```

### 4.3 同步狀態時間軸

```
用途：一目瞭然整個 session 的同步歷史
類型：RectangleMark（色帶）
X 軸：時間
Y 軸：無（或固定高度）
顏色：
  - 紅色 = SEARCH（搜尋中）
  - 黃色 = CANDIDATE（候選）
  - 綠色 = SYNC（已同步）
附加：
  - 呼號標籤標在對應的解碼時間點
```

```swift
Chart(snapshots) { snap in
    RectangleMark(
        xStart: .value("Start", Double(snap.offsetMs) / 1000.0),
        xEnd: .value("End", Double(snap.offsetMs + 120) / 1000.0),  // 120ms per frame
        yStart: .value("", 0),
        yEnd: .value("", 1)
    )
    .foregroundStyle(syncStateColor(snap.syncState))
}
.chartYAxis(.hidden)
.frame(height: 30)
```

### 4.4 輸入電平時序圖

```
用途：確認輸入訊號電平是否適當（過高 clipping、過低 SNR 不足）
類型：AreaMark + LineMark
X 軸：時間
Y 軸：電平 (dB)，範圍 -60 ~ 0 dB
附加：
  - 危險區域標示：> -3 dB 紅色區域（可能 clipping）
  - < -40 dB 灰色區域（訊號可能過弱）
```

### 4.5 SNR 分佈直方圖

```
用途：了解整個 session 的 SNR 統計分佈
類型：BarMark（histogram）
X 軸：SNR (dB)，2 dB bins
Y 軸：出現次數（百分比或絕對值）
附加：
  - 中位數垂直線
  - 平均值垂直線
  - 僅計算 SYNC 期間的數據
```

```swift
// 計算 histogram bins
let syncedSnapshots = snapshots.filter { $0.syncState == 2 }
let bins = Dictionary(grouping: syncedSnapshots) { snap in
    Int(floor(snap.snr / 2.0)) * 2  // 2 dB bins
}

Chart(bins.sorted(by: { $0.key < $1.key }), id: \.key) { bin in
    BarMark(
        x: .value("SNR", "\(bin.key)~\(bin.key+2) dB"),
        y: .value("Count", bin.value.count)
    )
    .foregroundStyle(snrColor(Float(bin.key + 1)))
}
```

### 4.6 Session 總覽圖（歷史趨勢）

```
用途：跨 session 比較，觀察長期趨勢
類型：PointMark + RuleMark
X 軸：Session 日期
Y 軸：平均 SNR
大小：session duration（氣泡大小）
顏色：syncRatio（同步比例越高越綠）
附加：
  - 每個點可點擊進入該 session 的詳細圖表
```

---

## 5. UI 結構

### 5.1 導覽架構

```
TabView
├── Tab 1: TransceiverView（現有的主畫面）
│   └── 加入「正在錄製」指示燈（紅色圓點 + 時間）
│
├── Tab 2: ReceptionLogView（新增）
│   ├── Session 列表（List，按日期排序）
│   │   └── 每列顯示：日期、時長、平均 SNR、呼號、同步比例 mini bar
│   │
│   └── SessionDetailView（點擊進入）
│       ├── Session 摘要卡片
│       │   ├── 開始/結束時間
│       │   ├── 時長
│       │   ├── 裝置名稱
│       │   ├── 平均 SNR / 峰值 SNR
│       │   ├── 同步比例
│       │   └── 解碼呼號列表
│       │
│       ├── 圖表區域（可垂直滑動切換圖表）
│       │   ├── SNR 時序圖（4.1）
│       │   ├── 頻率偏移時序圖（4.2）
│       │   ├── 同步狀態時間軸（4.3）
│       │   ├── 輸入電平時序圖（4.4）
│       │   └── SNR 分佈直方圖（4.5）
│       │
│       ├── 播放錄音按鈕（如有錄音）
│       │
│       ├── 匯出按鈕
│       │   ├── 匯出 CSV（所有 snapshot 數據）
│       │   ├── 匯出 WAV（錄音檔）
│       │   └── 分享（iOS Share Sheet）
│       │
│       └── 備註編輯欄位
│
└── Tab 3: SettingsView（現有，加入錄音設定）
    ├── 現有設定...
    ├── ── 接收日誌 ──
    ├── 自動錄音開關
    ├── 錄音品質（8kHz / 16kHz / 48kHz）
    ├── 最大儲存空間
    ├── 目前使用空間
    └── 清除所有錄音
```

### 5.2 即時錄製指示器

在 TransceiverView 的 StatusBar 加入錄製指示：

```swift
// 在 StatusBar 中加入
if viewModel.isRecording {
    HStack(spacing: 4) {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .opacity(blinkAnimation ? 1.0 : 0.3)  // 閃爍
        Text(viewModel.recordingDuration.formatted())
            .font(.caption.monospacedDigit())
    }
}
```

---

## 6. 數據擷取點整合（修改現有程式碼）

### 6.1 AudioManager.swift 新增

```swift
// 新增屬性
var receptionLogger: ReceptionLogger?
var wavRecorder: WAVRecorder?
var isRecordingEnabled = true  // 設定控制

// startRX() 中新增
func startRX() {
    // ... 現有的 AVAudioEngine 啟動程式碼 ...
    
    if isRecordingEnabled {
        let filename = "rade_rx_\(Self.dateFormatter.string(from: Date())).wav"
        wavRecorder = WAVRecorder()
        try? wavRecorder?.start(filename: filename)
        
        receptionLogger?.beginSession(
            audioDevice: currentAudioDevice ?? "Unknown",
            sampleRate: Int(hardwareSampleRate)
        )
        receptionLogger?.currentSession?.audioFilename = filename
    }
}

// stopRX() 中新增
func stopRX() {
    wavRecorder?.stop()
    receptionLogger?.endSession()
    // ... 現有的停止程式碼 ...
}
```

### 6.2 RADEWrapper / processingQueue 中新增

在 `rade_rx()` 呼叫之後，同一個 processingQueue block 中：

```swift
// processingQueue 內，rade_rx() 之後

// 1. 寫入 WAV 錄音（8kHz Int16，已經有了）
wavRecorder?.writeSamples(samples, count: Int(sampleCount))

// 2. 記錄 snapshot
let snapshot = SignalSnapshot(
    id: UUID(),
    timestamp: Date(),
    offsetMs: Int64(Date().timeIntervalSince(sessionStartTime) * 1000),
    snr: rade_snrdB_3k_est(radePtr),         // 直接從 C API 取
    freqOffset: rade_freq_offset(radePtr),    // 直接從 C API 取
    syncState: Int(rade_sync(radePtr)),       // 直接從 C API 取
    inputLevelDb: currentInputLevel,
    outputLevelDb: currentOutputLevel,
    nin: Int(rade_nin(radePtr)),
    clockOffset: 0
)
receptionLogger?.recordSnapshot(snapshot)

// 3. 呼號解碼事件（在 EOO 偵測處）
if hasEoo {
    let callsign = eoo_callsign_decode(...)
    receptionLogger?.recordCallsign(callsign, snr: currentSNR, modemFrame: frameCount)
}
```

---

## 7. 匯出功能

### 7.1 CSV 匯出格式

```csv
timestamp_utc,offset_ms,snr_db,freq_offset_hz,sync_state,input_level_db,output_level_db,nin,clock_offset
2026-03-23T14:30:52.120Z,0,12.3,1.5,2,-18.5,-22.3,960,0.0
2026-03-23T14:30:52.240Z,120,11.8,1.3,2,-19.1,-21.8,960,0.0
...
```

### 7.2 匯出實作

```swift
class SessionExporter {
    
    static func exportCSV(session: ReceptionSession) -> URL {
        let filename = "rade_log_\(session.id.uuidString.prefix(8)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        var csv = "timestamp_utc,offset_ms,snr_db,freq_offset_hz,sync_state,input_level_db,output_level_db,nin,clock_offset\n"
        
        for snap in session.snapshots.sorted(by: { $0.offsetMs < $1.offsetMs }) {
            csv += "\(snap.timestamp.iso8601),"
            csv += "\(snap.offsetMs),"
            csv += "\(snap.snr),"
            csv += "\(snap.freqOffset),"
            csv += "\(snap.syncState),"
            csv += "\(snap.inputLevelDb),"
            csv += "\(snap.outputLevelDb),"
            csv += "\(snap.nin),"
            csv += "\(snap.clockOffset)\n"
        }
        
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    static func shareSession(_ session: ReceptionSession, from view: UIViewController) {
        var items: [Any] = []
        
        // CSV
        items.append(exportCSV(session: session))
        
        // WAV（如有）
        if let audioFile = session.audioFilename {
            let audioURL = WAVRecorder.recordingsDirectory.appendingPathComponent(audioFile)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                items.append(audioURL)
            }
        }
        
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        view.present(ac, animated: true)
    }
}
```

---

## 8. 效能與儲存估算

### 8.1 每小時資料量

| 項目 | 計算 | 大小 |
|------|------|------|
| SignalSnapshot | 8.3/sec × 3600s × ~60 bytes | ~1.8 MB |
| SyncEvent | 數十筆（狀態變化才記） | < 1 KB |
| CallsignEvent | 數筆 | < 1 KB |
| WAV 錄音 (8kHz Int16) | 8000 × 2 bytes × 3600s | 57.6 MB |
| **合計（不含 WAV）** | | **~2 MB** |
| **合計（含 WAV）** | | **~60 MB** |

### 8.2 SwiftData 寫入效能

- 批量寫入每 5 秒一次，每批 ~40 筆
- SQLite 輕鬆處理，不會影響 UI 或音訊處理
- `writeQueue` 用 `.utility` QoS，不會搶佔音訊 thread

### 8.3 圖表渲染效能

一小時 session 有 ~30,000 筆 snapshot。Swift Charts 直接繪製 30K 點可能會卡：

**策略：降採樣顯示**

```swift
// 根據顯示寬度計算需要的數據點數
func downsample(snapshots: [SignalSnapshot], targetPoints: Int) -> [SignalSnapshot] {
    guard snapshots.count > targetPoints else { return snapshots }
    let step = snapshots.count / targetPoints
    
    // LTTB (Largest Triangle Three Buckets) 或簡單 stride
    return stride(from: 0, to: snapshots.count, by: step).map { snapshots[$0] }
}

// 全畫面寬度 ~400pt，每 pt 一個數據點就夠了
// 放大時重新查詢該時間範圍的完整數據
```

---

## 9. 開發順序

### Phase 1：資料庫基礎
- [ ] 建立 SwiftData models（4 個 @Model class）
- [ ] 設定 ModelContainer
- [ ] 建立 ReceptionLogger class（beginSession / recordSnapshot / endSession）
- [ ] 單元測試：寫入讀取驗證

### Phase 2：數據擷取整合
- [ ] 修改 AudioManager，在 rade_rx() 後插入 snapshot 記錄
- [ ] 修改 startRX() / stopRX() 管理 session 生命週期
- [ ] 實作 SyncEvent 偵測（狀態變化）
- [ ] 實作 CallsignEvent 記錄
- [ ] 驗證：跑一次 session 後檢查 DB 內容

### Phase 3：WAV 錄音
- [ ] 實作 WAVRecorder class
- [ ] 整合到 AudioManager
- [ ] 設定頁面加入錄音開關
- [ ] 驗證：錄音檔可在桌面版 FreeDV 播放

### Phase 4：Session 列表 UI
- [ ] 建立 ReceptionLogView（session 列表）
- [ ] Session 列表 cell（摘要資訊）
- [ ] 滑動刪除
- [ ] Tab 導覽整合

### Phase 5：圖表
- [ ] SNR 時序圖（最重要）
- [ ] 同步狀態時間軸
- [ ] 頻率偏移時序圖
- [ ] 輸入電平時序圖
- [ ] SNR 分佈直方圖
- [ ] 降採樣邏輯（長 session 效能）
- [ ] 圖表互動（拖曳選取放大）

### Phase 6：Session 總覽圖
- [ ] 跨 session 趨勢圖
- [ ] 點擊跳轉到 session 詳情

### Phase 7：匯出與分享
- [ ] CSV 匯出
- [ ] WAV + CSV 打包分享
- [ ] 錄音播放功能

### Phase 8：儲存管理
- [ ] 計算已用空間
- [ ] 自動清理策略（超過上限刪最舊）
- [ ] 設定 UI（空間限制、手動清除）

---

## 10. 新增檔案清單

```
FreeDV/
├── Models/                          【新增目錄】
│   ├── ReceptionSession.swift       SwiftData model
│   ├── SignalSnapshot.swift         SwiftData model
│   ├── SyncEvent.swift              SwiftData model
│   └── CallsignEvent.swift          SwiftData model
├── Services/                        【新增目錄】
│   ├── ReceptionLogger.swift        數據擷取與批量寫入引擎
│   ├── WAVRecorder.swift            WAV 錄音器
│   └── SessionExporter.swift        CSV 匯出 / 分享
├── Views/
│   ├── ReceptionLogView.swift       【新增】Session 列表
│   ├── SessionDetailView.swift      【新增】Session 詳細圖表頁
│   ├── Charts/                      【新增目錄】
│   │   ├── SNRTimeChart.swift       SNR 時序圖
│   │   ├── FreqOffsetChart.swift    頻率偏移時序圖
│   │   ├── SyncTimelineChart.swift  同步狀態時間軸
│   │   ├── InputLevelChart.swift    輸入電平時序圖
│   │   ├── SNRHistogramChart.swift  SNR 分佈直方圖
│   │   └── SessionOverviewChart.swift 跨 session 總覽
│   ├── TransceiverView.swift        【修改】加入錄製指示器
│   └── SettingsView.swift           【修改】加入錄音設定
├── ViewModels/
│   ├── TransceiverViewModel.swift   【修改】加入 isRecording 狀態
│   └── SessionDetailViewModel.swift 【新增】圖表數據處理 + 降採樣
├── Audio/
│   └── AudioManager.swift           【修改】整合 logger + recorder
└── App/
    └── FreeDVApp.swift              【修改】加入 ModelContainer
```
