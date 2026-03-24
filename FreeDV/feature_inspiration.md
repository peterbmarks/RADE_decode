# 功能擴展靈感 — Portable SWL Edition

> 使用場景：iPhone + 收音機/SDR 出門做可攜式 SWL
> 重點方向：使用體驗、進階分析、硬體整合與自動化

### 架構前提

- **App 只處理音訊，不控制收音機。** 收音機的頻率、模式等由使用者在收音機上操作。
- **音訊輸入方式：** iPhone 內建麥克風（放在喇叭旁）或透過 USB 音效介面連接收音機的音訊輸出。
- **App 內的「頻率」欄位** 是使用者手動輸入的標籤，僅用於 FreeDV Reporter 回報和日誌記錄，與收音機無連動。

---

## A. 使用體驗與易用性

### A1. Live Activity + Dynamic Island

**為什麼重要：** 戶外操作時 iPhone 常常放口袋或夾在背包上，不會一直盯螢幕。Live Activity 讓你鎖屏也能一眼看到狀態。

**顯示內容：**

```
┌─ Dynamic Island（緊湊模式）──────────┐
│  🟢 SYNC  SNR: 14dB  VK5DGR        │
└─────────────────────────────────────┘

┌─ Dynamic Island（展開模式）──────────┐
│  RADE V1 ● SYNCED                   │
│  SNR: 14 dB    Freq: +1.2 Hz       │
│  Last: VK5DGR   14.236 MHz         │
│  ⏱ 00:12:34    📡 3 decoded today  │
└─────────────────────────────────────┘

┌─ 鎖定畫面 Live Activity ───────────┐
│ 📻 FreeDV SWL                      │
│ 🟢 SYNC │ SNR 14dB │ 14.236 MHz   │
│ Last decoded: VK5DGR  2 min ago    │
│ ████████████░░░░ Session: 12m      │
└─────────────────────────────────────┘
```

**實作要點：**
- 使用 ActivityKit framework（iOS 16.1+）
- 建立 `FreeDVWidgetExtension` target
- 用 `ActivityAttributes` 定義靜態/動態內容
- 從 AudioManager 透過 `Activity.update()` 推送狀態變更
- SEARCH → SYNC 和呼號解碼是兩個關鍵更新時機
- 不需要推播伺服器，純 local Live Activity

```swift
struct FreeDVAttributes: ActivityAttributes {
    // 靜態（session 開始時設定）
    struct ContentState: Codable, Hashable {
        var syncState: Int       // 0=SEARCH, 1=CANDIDATE, 2=SYNC
        var snr: Float
        var freqOffsetHz: Float
        var lastCallsign: String
        var decodedCount: Int
        var sessionDuration: TimeInterval
    }
    var frequencyMHz: String
    var startTime: Date
}
```

---

### A2. Haptic 回饋系統

**三級觸覺回饋，不用看螢幕也知道發生什麼事：**

| 事件 | Haptic 類型 | 感覺 |
|------|------------|------|
| SEARCH → SYNC | `.medium` impact | 輕敲一下 — 「鎖定訊號了」 |
| 呼號解碼成功 | `.success` notification | 明顯的成功震動 — 「收到呼號」 |
| SYNC → SEARCH（失鎖） | `.warning` notification | 兩下短震 — 「訊號丟了」 |
| SNR > 20dB（強訊號）| `.light` impact | 極輕微 — 背景感知 |

```swift
class HapticManager {
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()
    
    func prepare() {
        impactLight.prepare()
        impactMedium.prepare()
        notification.prepare()
    }
    
    func onSync()         { impactMedium.impactOccurred() }
    func onUnsync()       { notification.notificationOccurred(.warning) }
    func onCallsign()     { notification.notificationOccurred(.success) }
    func onStrongSignal() { impactLight.impactOccurred(intensity: 0.4) }
}
```

設定頁面提供開關和強度控制，戶外/口袋模式下特別有用。

---

### A3. 單手快速操作模式

戶外時可能只有一隻手空著。設計一個「快速操作」手勢層：

**長按螢幕任意處** → 彈出圓形快捷選單（類似 3D Touch 選單）：
- ▶️ Start / ⏹ Stop
- 📸 螢幕截圖（帶 SNR、頻率浮水印，存到相簿）
- 📍 標記目前位置（GPS bookmark）
- 📝 快速加入備註（語音或文字）

**搖動手機（Shake）** → 快速標記目前位置為「好的接收點」（加入 GPS bookmark）

> **注意：** App 無法控制收音機的頻率。頻率欄位僅用於 Reporter 回報和日誌記錄，需使用者手動輸入目前收音機上的頻率。

---

### A4. 戶外可見性模式

強日光下螢幕很難看清楚。加入一個「戶外模式」：

- 高對比度配色（純黑底 + 亮綠/亮紅文字，類似軍用 NVG 風格）
- 關鍵資訊放大（SNR 數字特大，60pt+）
- 簡化顯示：只顯示 SYNC 狀態 + SNR + 最近呼號，隱藏頻譜/瀑布
- 自動偵測環境亮度 > 閾值時切換

```swift
struct OutdoorView: View {
    let snr: Float
    let syncState: Int
    let callsign: String
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                // 巨大同步指示燈
                Circle()
                    .fill(syncState == 2 ? .green : .red)
                    .frame(width: 80, height: 80)
                
                // 巨大 SNR
                Text("\(Int(snr)) dB")
                    .font(.system(size: 72, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                
                // 呼號
                Text(callsign.isEmpty ? "—" : callsign)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.yellow)
            }
        }
        .persistentSystemOverlays(.hidden)  // 隱藏狀態列
    }
}
```

---

## B. 進階分析與數據

### B1. GPS 標記接收日誌 — 傳播地圖

**核心概念：** 每次解碼到訊號時，同時記錄 GPS 座標。這樣你事後可以看到「在哪裡收到了什麼」。

**資料庫新增欄位：**

```swift
// 擴展 SignalSnapshot
@Model
class SignalSnapshot {
    // ... 現有欄位 ...
    var latitude: Double?     // GPS 緯度
    var longitude: Double?    // GPS 經度
    var altitude: Double?     // 海拔 (m)
    var heading: Double?      // 方向角
}

// 擴展 ReceptionSession
@Model
class ReceptionSession {
    // ... 現有欄位 ...
    var startLatitude: Double?
    var startLongitude: Double?
    var startAltitude: Double?
    var locationName: String?  // 反向地理編碼的地名
}

// 新增：接收地點熱力圖資料
@Model
class ReceptionLocation {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var bestSNR: Float           // 該位置收到的最佳 SNR
    var callsignsDecoded: [String]
    var sessionsCount: Int
    var firstVisit: Date
    var lastVisit: Date
}
```

**GPS 追蹤（低功耗模式）：**

```swift
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var currentLocation: CLLocation?
    
    func startTracking() {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters  // 省電
        manager.distanceFilter = 100  // 移動 100m 才更新
        manager.allowsBackgroundLocationUpdates = true  // 背景更新
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
        manager.startUpdatingLocation()
    }
}
```

**地圖視覺化：** 用 MapKit 畫出你的路線 + 每個收到訊號的點：

- 綠色大圓點 = SYNC + 高 SNR
- 黃色小圓點 = SYNC + 低 SNR
- 灰色點 = 只有 SEARCH，沒有解碼成功
- 呼號標籤浮在解碼成功的點上

這對「某山頂是不是好的接收點」這類問題特別有價值。

---

### B2. 呼號追蹤系統（SWL DX 追蹤）

類似 DXCC 或 SOTA 追蹤，但給 SWL：

```swift
@Model
class CallsignRecord {
    var callsign: String       // 呼號
    var firstHeard: Date       // 首次收到時間
    var lastHeard: Date        // 最近收到時間
    var timesHeard: Int        // 收到次數
    var bestSNR: Float         // 最佳 SNR
    var bestSNRDate: Date      // 最佳 SNR 的日期
    var frequencies: [UInt64]  // 在哪些頻率上收到（使用者手動設定的頻率標籤）
    var gridSquare: String?    // 對方的 Grid（從 Reporter 取）
    var distanceKm: Double?    // 距離
    var country: String?       // DXCC 國家（從 callsign prefix 推算）
    var continent: String?     // 洲
    var isFavorite: Bool       // 收藏
}
```

**統計儀表板：**

```
┌─ SWL DX 統計 ──────────────────────┐
│                                     │
│  📡 收到總呼號數: 47                 │
│  🌍 國家/地區數: 12                  │
│  🏔 最遠距離: 13,200 km (VK5DGR)    │
│  📈 今日新呼號: 3                    │
│  ⭐ 最佳 SNR: 28 dB (W1AW)         │
│                                     │
│  ─── 今日時間軸 ───                  │
│  07:15  K1ABC     20m  12dB  🆕     │
│  07:32  VK3TPM    20m  18dB         │
│  08:01  JH1NBN    20m   8dB  🆕     │
│  08:45  W5ABC     20m  15dB  🆕     │
│                                     │
│  ─── 國家排名 ───                    │
│  🇺🇸 USA        15 stations         │
│  🇦🇺 Australia   8 stations         │
│  🇯🇵 Japan       6 stations         │
│  🇳🇿 New Zealand 3 stations         │
└─────────────────────────────────────┘
```

**Callsign → 國家 對照表：** 用 ITU callsign prefix 資料庫，可以內嵌一個簡化版（約 500 筆 prefix → country 對照）。

---

### B3. 傳播條件即時評分

根據目前 SNR 和接收狀況，給出一個直覺的傳播評分：

```swift
struct PropagationScore {
    let band: String           // "20m"
    let score: Int             // 0-100
    let label: String          // "Excellent" / "Good" / "Fair" / "Poor" / "Dead"
    let activeStations: Int    // Reporter 上這個頻段的活躍電台數
    let avgSNR: Float          // 這個頻段的平均 SNR
    
    static func calculate(
        recentSnapshots: [SignalSnapshot],
        reporterStations: [ReporterStation],
        band: String
    ) -> PropagationScore {
        // 基於最近 5 分鐘的 SNR 數據 + Reporter 上的電台數量
        // 加權計算出 0-100 分
    }
}
```

顯示方式：一排彩色方塊代表各頻段狀態（類似 DX cluster 的 band condition 顯示）

```
Band Conditions:
80m ⬛  40m 🟡  20m 🟢  15m 🟢  10m 🟡
```

---

### B4. Session 比較模式

選兩個不同的 session，並排比較它們的 SNR 曲線。用途：
- 比較同一地點不同時間的傳播差異
- 比較不同地點（如山頂 vs 平地）的接收品質
- 比較不同天線/SDR 的效果

```swift
struct SessionComparisonView: View {
    let sessionA: ReceptionSession
    let sessionB: ReceptionSession
    
    var body: some View {
        VStack {
            // 並排 SNR 圖表（同一時間軸）
            Chart {
                ForEach(sessionA.snapshots) { snap in
                    LineMark(x: .value("Time", snap.offsetMs),
                             y: .value("SNR", snap.snr))
                    .foregroundStyle(.blue)
                    .opacity(0.8)
                }
                ForEach(sessionB.snapshots) { snap in
                    LineMark(x: .value("Time", snap.offsetMs),
                             y: .value("SNR", snap.snr))
                    .foregroundStyle(.orange)
                    .opacity(0.8)
                }
            }
            
            // 比較摘要表格
            Grid {
                GridRow {
                    Text("")
                    Text("Session A").bold()
                    Text("Session B").bold()
                }
                GridRow {
                    Text("平均 SNR")
                    Text("\(sessionA.avgSNR, specifier: "%.1f") dB")
                    Text("\(sessionB.avgSNR, specifier: "%.1f") dB")
                }
                GridRow {
                    Text("同步率")
                    Text("\(sessionA.syncRatio * 100, specifier: "%.0f")%")
                    Text("\(sessionB.syncRatio * 100, specifier: "%.0f")%")
                }
                GridRow {
                    Text("呼號數")
                    Text("\(sessionA.callsignsDecoded.count)")
                    Text("\(sessionB.callsignsDecoded.count)")
                }
            }
        }
    }
}
```

---

## C. 硬體整合與自動化

### C1. Shortcuts / Siri 整合

建立 App Intents 讓 Shortcuts 和 Siri 可以控制 App：

> **重要限制：** App 只能接收音訊並解碼，無法控制收音機的頻率。頻率欄位是使用者手動輸入的標籤，僅用於 Reporter 回報和日誌記錄。

```swift
import AppIntents

// 「開始監聽」Intent
struct StartListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "開始 FreeDV 監聽"
    static var description = IntentDescription("開始接收並解碼 RADE 訊號")
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 啟動 AudioManager，開始解碼
        return .result(dialog: "開始監聽 FreeDV RADE 訊號")
    }
}

// 「停止監聽」Intent
struct StopListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "停止 FreeDV 監聽"
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "已停止監聽")
    }
}

// 「今天收到幾個呼號？」Intent
struct TodayStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "今天的 FreeDV 接收統計"
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = // 查詢今日 CallsignEvent 數量
        return .result(dialog: "今天收到了 \(count) 個不同的呼號")
    }
}

// 「目前傳播狀況？」Intent
struct PropagationIntent: AppIntent {
    static var title: LocalizedStringResource = "FreeDV 傳播狀況"
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let online = // 查詢 Reporter 在線電台數
        return .result(dialog: "FreeDV Reporter 目前有 \(online) 個電台在線")
    }
}
```

**可以設定的 Shortcuts 自動化範例：**
- 「每天早上 7:00 自動開始監聽」
- 「到達某個地點（GPS 圍欄）時自動開始監聽」
- 「當收到新呼號時發送通知到 Apple Watch」
- 「Siri，開始監聽 FreeDV」
- 「Siri，今天收到幾個電台？」

---

### C2. 主畫面 Widget

三種尺寸的 Widget：

**小型 Widget（2×2）：**
```
┌──────────────┐
│  📻 FreeDV   │
│  🟢 SYNC     │
│  SNR: 14 dB  │
│  VK5DGR      │
└──────────────┘
```

**中型 Widget（4×2）：**
```
┌──────────────────────────────┐
│  📻 FreeDV SWL              │
│  🟢 SYNC  14.236 MHz  14dB  │
│  Last: VK5DGR  3 min ago    │
│  Today: 5 callsigns, 3 new  │
└──────────────────────────────┘
```

**大型 Widget（4×4）— 迷你 SNR 圖表：**
```
┌──────────────────────────────┐
│  📻 FreeDV SWL   14.236 MHz │
│  🟢 SYNC   SNR: 14 dB       │
│                              │
│  SNR (last 10 min):          │
│  ┌─────────────────────┐     │
│  │    ╱╲  ╱╲           │     │
│  │╱╲╱  ╲╱  ╲╱╲╱╲      │     │
│  │              ╲╱╲╱╲  │     │
│  └─────────────────────┘     │
│  Today: VK5DGR, K1ABC, W5XX │
└──────────────────────────────┘
```

實作使用 WidgetKit + App Group 共享數據。

---

### C3. 電力管理 — 可攜式續航優化

戶外操作時電池壽命是命脈。

```swift
class PowerManager {
    
    enum PowerProfile {
        case performance   // 全功能（頻譜、瀑布、高更新率）
        case balanced      // 預設
        case lowPower      // 省電模式
        case ultraLow      // 極限省電（純解碼，無 UI 動畫）
    }
    
    var currentProfile: PowerProfile = .balanced
    
    func applyProfile(_ profile: PowerProfile) {
        switch profile {
        case .performance:
            // FFT 更新率 15 Hz，瀑布開啟，Reporter 連線
            uiUpdateRate = 20   // Hz
            fftEnabled = true
            waterfallEnabled = true
            reporterEnabled = true
            
        case .balanced:
            uiUpdateRate = 10
            fftEnabled = true
            waterfallEnabled = true
            reporterEnabled = true
            
        case .lowPower:
            // 降低 UI 更新率，關閉瀑布
            uiUpdateRate = 5
            fftEnabled = true
            waterfallEnabled = false   // 瀑布很耗電
            reporterEnabled = true
            
        case .ultraLow:
            // 只做解碼，最小化一切 UI
            uiUpdateRate = 2
            fftEnabled = false
            waterfallEnabled = false
            reporterEnabled = false    // 省網路電力
            // 切換到 OutdoorView（極簡 UI）
        }
    }
    
    // 監聽系統低電量通知
    func observeBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            let level = UIDevice.current.batteryLevel
            if level < 0.1 {
                self?.applyProfile(.ultraLow)
            } else if level < 0.2 {
                self?.applyProfile(.lowPower)
            }
        }
    }
}
```

**預估電力消耗（各模式）：**

| 模式 | 主要耗電來源 | 預估續航（iPhone 15 Pro） |
|------|------------|-------------------------|
| Performance | Audio + RADE + FFT + 瀑布 + Reporter + GPS | ~3-4 小時 |
| Balanced | Audio + RADE + FFT + Reporter + GPS | ~5-6 小時 |
| Low Power | Audio + RADE + Reporter | ~7-8 小時 |
| Ultra Low | Audio + RADE only | ~10+ 小時 |

---

### C4. 離線模式

出門在外網路不一定穩。App 應設計為離線優先：

- **核心解碼功能完全離線運作** — RADE 解碼、FFT 頻譜、錄音、日誌記錄全部不需要網路
- **Reporter 斷線時靜默忽略** — 離線期間的 rx_report 不需要暫存或補送，因為 FreeDV Reporter 是即時 spotting 系統，過時的回報沒有意義
- **網路恢復後自動重連 Reporter** — Socket.IO 的 `reconnects: true` 即可，重連後只需重新發送目前頻率和狀態
- **離線指示** — UI 上顯示 Reporter 斷線圖示，但不干擾使用者操作

```swift
// Reporter 斷線時的處理 — 極簡
func reportRx(callsign: String, snr: Int) {
    guard isReady else { return }  // 沒連線就直接跳過，不暫存
    socket?.emit("rx_report", [
        "callsign": callsign,
        "mode": "RADEV1",
        "snr": snr
    ])
}
```

---

## D. 開發優先級建議

以可攜式 SWL 場景的價值排序：

### Tier 1 — 立即可做，戶外體驗大幅提升
1. **Haptic 回饋**（半天可完成，效果立竿見影）
2. **戶外可見性模式**（一天可完成，強日光下必需）
3. **電力管理 Profile**（一天可完成，續航翻倍）

### Tier 2 — 值得投入，差異化功能
4. **Live Activity / Dynamic Island**（2-3 天，鎖屏監聽的體驗沒有其他 App 做得到）
5. **GPS 標記接收日誌**（2 天，可攜式 SWL 的殺手功能）
6. **主畫面 Widget**（2 天，日常使用便利性）

### Tier 3 — 進階功能，讓 App 更完整
7. **呼號追蹤系統 / SWL DX 統計**（3 天，長期使用動力）
8. **Shortcuts / Siri 整合**（2 天，自動化操作）
9. **Session 比較模式**（1-2 天，分析功能）
10. **傳播條件評分**（2 天，需要更多數據來源）

### Tier 4 — 未來展望
11. **Apple Watch App**（5+ 天，完整 watchOS 開發）
12. **AirPlay 音訊分離輸出**

---

## E. 新增檔案清單（全部功能）

```
FreeDV/
├── Haptics/
│   └── HapticManager.swift              觸覺回饋管理
├── Location/
│   └── LocationManager.swift            GPS 追蹤（低功耗）
├── Power/
│   └── PowerManager.swift               電力 Profile 管理
├── Network/
│   └── FreeDVReporter.swift             現有
├── Views/
│   ├── OutdoorView.swift                戶外高對比度顯示
│   ├── ReceptionMapView.swift           GPS 接收地圖
│   ├── CallsignTrackerView.swift        呼號追蹤 / DX 統計
│   ├── SessionComparisonView.swift      Session 比較
│   └── PropagationBandsView.swift       頻段傳播狀態
├── Intents/
│   ├── StartListeningIntent.swift       Shortcuts: 開始監聽
│   ├── TodayStatsIntent.swift           Shortcuts: 今日統計
│   └── PropagationIntent.swift          Shortcuts: 傳播狀況
├── Widget/
│   ├── FreeDVWidget.swift               主畫面 Widget
│   └── FreeDVWidgetBundle.swift
├── LiveActivity/
│   ├── FreeDVAttributes.swift           Live Activity 定義
│   └── FreeDVLiveActivityView.swift     Lock Screen / Dynamic Island UI
└── Models/
    ├── CallsignRecord.swift             呼號追蹤資料模型
    └── ReceptionLocation.swift          接收地點資料模型
```

---

## F. App Store 上架審查分析

### F1. 結論：可以上架

App 的技術實作完全符合 Apple 審查指南。核心功能（麥克風收音 → 音訊處理 → 解碼輸出）與 App Store 上成千上萬的音訊處理類 App（調音器、頻譜分析器等）使用模式相同，不會觸發任何審查紅線。

### F2. 完全沒問題的部分

| 項目 | 分析 |
|------|------|
| **AVAudioEngine 音訊處理** | 標準 iOS API 使用，App Store 上大量同類 App |
| **C 語言庫靜態連結** | 完全合規，Apple 禁止的是動態下載執行程式碼，靜態編譯不受限 |
| **47 MB 神經網路權重** | App 總大小約 50-60 MB，遠低於 200 MB 行動數據下載門檻 |
| **Socket.IO 連到 qso.freedv.org** | 普通 WebSocket 通訊，與任何連網 App 無異 |
| **BSD-2-Clause 開源授權** | App Store 對開源元件無限制 |
| **GPS 定位** | 有合理用途說明即可 |

### F3. 外接硬體不是問題

App 的主要使用方式是透過 **iPhone 內建麥克風** 接收音訊 — 把手機放在無線電喇叭旁邊即可收到 RADE modem 音訊。進階使用者可透過 USB 音效介面連接收音機的音訊輸出以獲得更好的訊號品質，但這是可選配置，不是必要條件。App 本身不控制任何外部硬體，僅被動接收音訊。

這代表：
- 審查員打開 App → 按 Start → 麥克風收音 → 頻譜跑起來、電平表在動
- 即使環境中沒有 RADE 訊號，App 也正常顯示 "Searching for signal..."
- 這就是一個功能完整、可正常執行的 App

跟調音器 App 用麥克風聽吉他音高完全相同的使用模式，不會有外接硬體的審查問題。

### F4. 需要注意處理的項目

#### ⚠️ 1. 內建 Demo 錄音功能（強烈建議）

雖然 App 不依賴外接硬體，但審查員周圍不可能有 RADE 訊號。建議：

- 內建一個 RADE 測試 WAV 檔（如 `FDV_offair.wav`）
- 提供「播放範例錄音」功能，讓審查員看到完整的解碼流程：頻譜動、瀑布跑、SNR 顯示、呼號解出、語音播放
- 這也對使用者有價值 — 第一次用的人可以先聽 Demo 了解 App 在做什麼

#### ⚠️ 2. 背景音訊 (UIBackgroundModes: audio)

Apple 禁止 App 在背景執行不相關的處理。使用 `audio` background mode 持續接收解碼 RADE 訊號是正當的音訊處理行為，但要確保：

- 只在使用者按了 Start 之後才啟用背景音訊
- 使用者按 Stop 後要完全停止背景活動
- 不要在背景偷做跟音訊無關的事

#### ⚠️ 3. 背景定位權限

如果啟用 GPS 標記功能：

- 優先使用 `When In Use` 權限，避免申請 `Always` 權限（審查更嚴格）
- 使用 `significantLocationChange` 或低精度模式省電
- Info.plist 中的 `NSLocationWhenInUseUsageDescription` 要清楚說明：「記錄接收 FreeDV 訊號的位置，用於傳播分析和接收日誌」

#### ⚠️ 4. 隱私標籤 (App Privacy Labels)

App 透過 FreeDV Reporter 傳輸以下資料到 `qso.freedv.org`：

| 資料 | 類型 | 說明 |
|------|------|------|
| 呼號 (Callsign) | 使用者自行輸入 | 業餘無線電操作員的公開識別碼 |
| Grid Square | 使用者自行輸入 | 大約位置（精度約 100km） |
| 接收頻率 | 使用者手動輸入 | 使用者在 App 中輸入的目前收音機頻率（App 無法自動偵測） |

在 App Store Connect 隱私標籤中申報：

```
Data Linked to You:
  - Contact Info: 呼號（可識別使用者身份）
  - Coarse Location: Grid Square

Data Not Linked to You:
  - Usage Data: 接收頻率、SNR（匿名技術數據）

Data Not Collected:
  - Reporter 功能關閉時不收集任何資料
```

#### ⚠️ 5. 命名與商標 — 「FreeDV」名稱

Apple 審查指南 4.1(c) 規定不能在 App 名稱或 icon 中未經授權使用其他開發者的品牌名稱。

**建議做法（擇一）：**

- **方案 A：取得授權** — 聯繫 FreeDV 專案團隊（David Rowe VK5DGR 或 Peter Marks VK3TPM）取得書面同意使用 FreeDV 名稱。開源專案通常歡迎生態系擴展，獲得授權的可能性很高。
- **方案 B：使用自己的名稱** — App 名稱改為「RADE Decoder」、「HF Voice」、「RADE SWL」之類的，在 App 描述和副標題中說明「Compatible with FreeDV RADE V1」。這樣完全不需要授權。

### F5. App Review Notes 範本

提交審查時在 App Store Connect 的 Review Notes 中填寫：

```
This app is a digital voice decoder for amateur radio. It decodes 
FreeDV RADE V1 signals — a digital voice protocol used by ham radio 
operators worldwide on HF (shortwave) frequencies.

HOW IT WORKS:
The app uses the iPhone's built-in microphone to listen to audio 
from a radio receiver's speaker. When it detects a RADE digital 
voice signal, it decodes and plays back the speech in real-time.

TO TEST WITHOUT A RADIO:
1. Launch the app
2. Tap the ≡ menu → "Play Demo Recording"  
3. The app will decode a built-in test signal
4. You will see: spectrum display animating, waterfall scrolling, 
   SNR reading (~15 dB), sync indicator turning green, 
   and hear decoded speech from the speaker

The optional FreeDV Reporter feature connects to qso.freedv.org 
(a public amateur radio spotting network) and can be disabled 
in Settings.

A video demonstration is available at: [URL]
```

### F6. 其他建議

| 項目 | 建議 |
|------|------|
| **App 分類** | Utilities 或 Reference |
| **年齡分級** | 4+（無敏感內容） |
| **最低支援裝置** | 確保在 iPhone SE (3rd gen) 等低階機也能運行 |
| **無網路 Graceful Degradation** | Reporter 連不上時 App 仍正常運作，只是不回報 |
| **無麥克風權限 Graceful Degradation** | 使用者拒絕麥克風權限時顯示清楚的說明，不要 crash |
| **Crash-free 保證** | 審查員隨時可能拒絕麥克風權限、關閉網路、切到背景再回來，所有情況都不能 crash |

### F7. 上架前 Checklist

```
□ 內建 Demo WAV + 播放功能（審查員可在無訊號環境下測試完整解碼流程）
□ Info.plist 所有 Usage Description 都有清楚說明
    □ NSMicrophoneUsageDescription — 說明用途是接收無線電數位語音
    □ NSLocationWhenInUseUsageDescription — 說明用途是記錄接收位置（如啟用 GPS）
□ App 在以下情況不會 crash：
    □ 使用者拒絕麥克風權限
    □ 使用者拒絕定位權限
    □ 無網路連線
    □ 無 USB 音效卡
    □ App 進入背景再回來
    □ 接聽電話中斷音訊後恢復
□ Reporter 功能關閉時不傳送任何資料
□ 隱私標籤在 App Store Connect 中正確填寫
□ FreeDV 名稱使用權已確認（或已改用自有名稱）
□ App Review Notes 填寫完整（含測試步驟）
□ 準備 Demo 操作影片連結
□ App 大小確認 < 200 MB
□ 背景音訊只在 Start 後啟用，Stop 後完全停止
□ 電池消耗合理，無異常耗電行為
```
