# FreeDV iOS — Architecture & Implementation Guide

> Last updated: 2026-03-23

## Overview

FreeDV iOS 是一個 **SWL（Short Wave Listening）專用** 的 RADE (Radio Autoencoder) 數位語音解調應用。透過 iPhone 連接 USB 音效卡接收 SDR 的 RADE OFDM 調變訊號，使用 C 語言的 RADE modem 解調，再經由 FARGAN 神經網路聲碼器合成語音輸出。

定位為 **RX-only**（僅接收）。典型使用場景：SDR 接收機 → USB 音效卡 → iPhone → 耳機/喇叭。

---

## 1. 目錄結構

```
FreeDV/
├── App/
│   ├── FreeDVApp.swift          # @main 進入點
│   ├── ContentView.swift        # 根 View，載入 TransceiverView
│   └── LogManager.swift         # 全域日誌管理（singleton）
├── Audio/
│   ├── AudioManager.swift       # 核心音訊管線（AVAudioEngine + RADE + FFT）
│   └── AudioDeviceManager.swift # 音訊裝置列舉與選擇
├── Bridge/
│   ├── FreeDV-Bridging-Header.h # C/C++ → Swift 橋接
│   └── RADETypes.swift          # RADE C API Swift 包裝 + FARGAN 聲碼器
├── ViewModels/
│   └── TransceiverViewModel.swift # UI 狀態管理（Timer polling）
├── Views/
│   ├── TransceiverView.swift    # 主畫面（狀態列 + 頻譜 + 瀑布 + 電平表）
│   ├── SpectrumView.swift       # FFT 頻譜圖（Canvas）
│   ├── WaterfallView.swift      # 瀑布圖（Canvas）
│   ├── MeterView.swift          # LED 電平表
│   ├── SettingsView.swift       # 設定（音訊裝置 + RADE 資訊）
│   └── LogView.swift            # 診斷日誌檢視器
├── Info.plist
└── Assets.xcassets

Libraries/
├── radae/                       # RADE modem C 函式庫
│   ├── rade_all.c               # Unity build（包含所有 .c）
│   ├── rade_nnet.c              # 神經網路層（獨立編譯）
│   ├── rade_api.h               # 公開 API
│   ├── rade_rx.h / .c           # 接收器（acquisition + demod + decoder）
│   ├── rade_ofdm.h / .c         # OFDM 調變/解調
│   ├── rade_acq.h / .c          # Pilot 偵測與同步
│   ├── rade_bpf.h / .c          # 複數帶通濾波器
│   ├── rade_dsp.h / .c          # DSP 基元與系統常數
│   ├── rade_core.h              # 神經網路 encoder/decoder
│   ├── rade_constants.h         # 模型維度常數
│   ├── rade_enc_data.c/h        # Encoder 權重 (~24 MB)
│   ├── rade_dec_data.c/h        # Decoder 權重 (~24 MB)
│   ├── kiss_fft.c/h             # FFT 函式庫
│   └── kiss_fftr.c/h            # 實數 FFT
├── opus/
│   ├── lib/libopus.a            # 預編譯靜態庫（arm64，含 FARGAN/nnet）
│   ├── dnn/                     # Opus DNN headers (fargan.h, lpcnet.h, nnet.h)
│   └── include/                 # Opus public headers
├── eoo/
│   ├── EooCallsignCodec.h/.cpp  # EOO 呼號編解碼（C++）
│   └── eoo_callsign_codec_c.h/.cpp # C 包裝
└── radae_top/                   # （暫未使用）

Scripts/
└── build_opus.sh                # 交叉編譯 libopus.a for iOS arm64

RADE.xcconfig                    # Xcode build 設定（路徑、flags、linking）
```

---

## 2. 音訊處理管線（RX Path）

```
iOS 麥克風 / USB 音效卡
    │
    ▼
AVAudioSession（48 kHz, .measurement mode, 固定 input gain 0.5）
    │
    ▼
AVAudioEngine.inputNode（可能是 2ch stereo, 48kHz, Float32, deinterleaved）
    │
    ▼
[Audio Thread] installTap → processRXInput()
    │
    ├─ Step 1: Stereo → Mono（取 ch0）
    │
    ├─ Step 2: AVAudioConverter（mono 48kHz Float32 → 8kHz Int16）
    │
    ├─ Step 3: 計算 RMS → dB → 更新 inputLevel（Main Thread）
    │
    └─ Step 4: 複製 samples → dispatch 到 processingQueue
                    │
                    ▼
            [processingQueue] (QoS: .userInteractive)
                    │
                    ├─ RADEWrapper.rxProcessInputSamples()
                    │       │
                    │       ├─ Int16 → RADE_COMP（real = sample/32768, imag = 0）
                    │       │
                    │       ├─ Loop: while rxInputBuffer.count >= rade_nin()
                    │       │       │
                    │       │       ├─ rade_rx() → features / EOO
                    │       │       ├─ 更新 sync, snr, freqOffset
                    │       │       └─ dispatch features → farganQueue
                    │       │
                    │       └─ EOO detected → eoo_callsign_decode()
                    │
                    └─ accumulateForFFT()
                            │
                            └─ 1024-pt Hann-windowed vDSP FFT
                               → 512 dB bins → fftData（Main Thread）

            [farganQueue] (QoS: .userInitiated)
                    │
                    ├─ Warmup: 前 5 frames → fargan_cont() 初始化
                    │
                    └─ 每 frame: fargan_synthesize_int()
                            → 160 samples @ 16kHz Int16
                            → onDecodedAudio callback
                                    │
                                    ▼
                            playDecodedAudio()
                                    │
                                    ├─ Int16 → Float32
                                    ├─ 計算 outputLevel
                                    └─ playerNode.scheduleBuffer()
                                            │
                                            ▼
                                        iOS 喇叭
```

---

## 3. 執行緒架構

| Queue | QoS | 職責 |
|-------|-----|------|
| **Audio Thread** | Real-time | inputNode tap callback，極低延遲，僅做 stereo→mono + 複製 |
| **processingQueue** | .userInteractive | RADE RX 解調 + FFT 計算 |
| **farganQueue** | .userInitiated | FARGAN 神經網路語音合成（有 overload 保護） |
| **Main Thread** | — | UI 更新、@Published 屬性、日誌寫入 |

### FARGAN Overload 保護

```swift
private var farganBusy = false

func dispatchFargan(frames: [[Float]]) {
    if farganBusy {
        appLog("FARGAN: dropping \(frames.count) frames (overloaded)")
        return  // 丟棄，避免凍結
    }
    farganBusy = true
    farganQueue.async {
        // 處理 frames...
        self.farganBusy = false
    }
}
```

---

## 4. RADE Modem 信號處理鏈

### 4.1 OFDM 參數

| 參數 | 值 | 說明 |
|------|----|------|
| Fs | 8000 Hz | Modem 取樣率 |
| Nc | 30 | OFDM 載波數 |
| M | 160 | 每 OFDM symbol 的取樣數 |
| Ncp | 32 | 循環前綴取樣數（4 ms） |
| Ns | 4 | 每 modem frame 的資料 symbol 數 |
| Nmf | 960 | 每 modem frame 的總取樣數 = (4+1)×(160+32) |
| Frame duration | 120 ms | 960 / 8000 |
| Latent dim | 80 | 每 latent vector 維度 |
| Nzmf | 3 | 每 modem frame 的 latent vector 數 |
| NB_TOTAL_FEATURES | 36 | 特徵向量大小（含 padding） |
| Carrier bandwidth | ~1.5 kHz | 30 carriers × 50 Hz spacing |
| Carrier range | ~700–2200 Hz | OFDM 載波頻率範圍 |

### 4.2 接收器狀態機

```
SEARCH → CANDIDATE → SYNC
  │          │          │
  │          │          ├─ 追蹤 timing/freq，解調資料
  │          │          ├─ UW error 超過門檻 → SEARCH
  │          │          ├─ EOO 偵測 → SEARCH
  │          │          └─ Pilot 遺失 3 秒 → SEARCH
  │          │
  │          ├─ 連續 3+ frames 偵測到 pilot → SYNC
  │          └─ Pilot 遺失 → SEARCH
  │
  └─ Pilot 相關性超過門檻 → CANDIDATE
```

### 4.3 Acquisition 參數

| 參數 | 值 |
|------|----|
| 頻率搜尋範圍 | ±100 Hz |
| 頻率步進 | 2.5 Hz |
| 頻率搜尋步數 | 40 |
| Unsync 超時 | 3 秒 |
| UW 錯誤門檻 | 7 |

### 4.4 解調流程

```
IQ 輸入 (8 kHz)
    ↓
[BPF] 帶通濾波（可選，預設開啟）
    ↓
[Acquisition] Pilot 相關性搜尋 → tmax, fmax
    ↓
[頻率校正] exp(-j·2π·fmax·n/Fs) 旋轉
    ↓
[移除循環前綴] M+Ncp → M samples
    ↓
[DFT] M time-domain → Nc 頻域載波
    ↓
[Pilot 估計] 3-pilot LS channel estimation
    ↓
[等化] 資料 symbol / channel estimate
    ↓
[Neural Decoder] latent z_hat[80×3] → features[36×12]
    ↓
[FARGAN] features → 16kHz 語音 PCM
```

---

## 5. C/Swift 橋接

### 5.1 Bridging Header

`FreeDV-Bridging-Header.h` 暴露：
- `rade_api.h` — RADE 主要 API（rade_open, rade_rx, rade_sync 等）
- `fargan.h` — FARGAN 聲碼器（fargan_init, fargan_cont, fargan_synthesize_int）
- `lpcnet.h` — LPCNet（目前未使用）
- `eoo_callsign_codec_c.h` — EOO 呼號解碼 C wrapper

### 5.2 Swift Wrapper（RADETypes.swift）

```swift
class RADEWrapper {
    private var radePtr: OpaquePointer?      // C struct rade*
    private var farganState: UnsafeMutablePointer<FARGANState>?
    private var rxInputBuffer: [RADE_COMP]   // IQ 累積 buffer

    // Callbacks
    var onDecodedAudio: ((UnsafePointer<Int16>?, Int32) -> Void)?
    var onStatusUpdate: ((RADERxStatus?) -> Void)?
    var onCallsignDecoded: ((String?) -> Void)?

    func rxProcessInputSamples(_ samples: UnsafePointer<Int16>, count: Int32)
    func resetFargan()
}
```

### 5.3 關鍵 C API 呼叫

```c
// 初始化
rade_initialize();
struct rade *r = rade_open("built-in", RADE_USE_C_ENCODER | RADE_USE_C_DECODER | RADE_VERBOSE_0);

// RX 處理迴圈
int nin = rade_nin(r);                    // 本次需要的 sample 數
int nFeat = rade_rx(r, features, &hasEoo, eoo, rx_in);  // 解調
int sync = rade_sync(r);                  // 同步狀態
float fOff = rade_freq_offset(r);         // 頻率偏移
int snr = rade_snrdB_3k_est(r);           // SNR 估計

// FARGAN 合成
fargan_init(fg);
fargan_cont(fg, zeros, packed_features);  // warmup
fargan_synthesize_int(fg, pcm_out, features);  // 每 frame 合成
```

---

## 6. Build 設定

### 6.1 RADE.xcconfig

```
// Header 搜尋路徑
HEADER_SEARCH_PATHS = Libraries/radae Libraries/opus/dnn Libraries/opus/celt Libraries/opus/include Libraries/eoo

// 連結 libopus.a
LIBRARY_SEARCH_PATHS = Libraries/opus/lib
OTHER_LDFLAGS = -lopus

// 預處理器定義
GCC_PREPROCESSOR_DEFINITIONS = IS_BUILDING_RADE_API=1 RADE_PYTHON_FREE=1 HAVE_CONFIG_H=1 USE_LIBOPUS=1

// 排除 x86_64（libopus.a 僅 arm64）
EXCLUDED_ARCHS = x86_64
```

### 6.2 Unity Build 策略

`rade_all.c` 以 `#include` 方式包含所有 RADE .c 檔案，確保所有符號都被編譯：

```c
#include "rade_enc_data.c"    // Encoder 權重 (~24 MB)
#include "rade_dec_data.c"    // Decoder 權重 (~24 MB)
#include "kiss_fft.c"         // FFT
#include "kiss_fftr.c"        // Real FFT
#include "rade_dsp.c"         // DSP 基元
#include "rade_ofdm.c"        // OFDM
#include "rade_bpf.c"         // 帶通濾波
#include "rade_acq.c"         // Acquisition
#include "rade_enc.c"         // Encoder
#include "rade_dec.c"         // Decoder（conv1_cond_init 重新命名避免衝突）
#include "rade_tx.c"          // TX
#include "rade_rx.c"          // RX
#include "rade_api_nopy.c"    // Python-free API
```

`rade_nnet.c` 由 Xcode **獨立編譯**（若定義 `USE_LIBOPUS` 則為空，使用 libopus.a 提供的 nnet）。

### 6.3 libopus.a

- 預編譯靜態庫，arm64 only
- 包含：FARGAN 聲碼器、LPCNet encoder、nnet 基元、opus codec
- `dred_rdovae_constants.h` stub 提供 `DRED_MAX_CONV_INPUTS=1536`（FARGAN 需要）
- 編譯腳本：`Scripts/build_opus.sh`

---

## 7. AVAudioSession 設定

```swift
// Category: 可同時錄音和播放
session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])

// 低延遲 buffer
session.setPreferredIOBufferDuration(0.01)  // 10 ms

// 48 kHz 寬頻取樣率（保留 modem 頻譜）
session.setPreferredSampleRate(48000)

// 固定 input gain（防止 iOS AGC 扭曲 modem 訊號）
session.setInputGain(0.5)

// 停用語音處理（取得原始寬頻音訊）
inputNode.setVoiceProcessingEnabled(false)
```

### 為什麼用 .measurement mode？

- 零音訊處理（無 AGC、無噪音抑制、無回音消除）
- 平坦頻率響應
- 對數據模式（OFDM modem）至關重要

---

## 8. FFT 頻譜分析

```swift
// 在 processingQueue 上計算（8kHz 取樣）
let fftSize = 1024          // → 512 magnitude bins
let fftLog2n = 10           // log2(1024)

// 流程：
// 1. 累積 8kHz Int16 samples → Float buffer
// 2. 達到 1024 samples 時：
//    a. 套用 Hann 窗
//    b. vDSP_ctoz → split complex
//    c. vDSP_fft_zrip → forward FFT
//    d. vDSP_zvmags → |X|²
//    e. 除以 N（正規化）
//    f. vDSP_vdbcon → dB (10*log10, ref=1.0)
// 3. 滑動 512 samples（50% overlap）
// 4. 發布 512 bins → fftData（Main Thread）

// 頻譜範圍：0 ~ 4 kHz（8 kHz 取樣的 Nyquist）
// 顯示範圍：-100 ~ 0 dB
```

---

## 9. UI 元件架構

```
NavigationStack
└── TransceiverView (@StateObject viewModel)
    ├── StatusBar
    │   ├── "RX" badge（藍色）
    │   ├── Sync 狀態（紅/黃/綠 圓點 + 文字）
    │   ├── SNR 顯示（色碼：綠 >6dB, 黃 2-6, 紅 <2）
    │   └── 頻率偏移（Hz）
    │
    ├── SpectrumView（Canvas，綠色漸層填充 + 線條）
    │   └── 512 bins, 0–4kHz, -100–0 dB
    │
    ├── WaterfallView（Canvas，最多 100 行歷史）
    │   └── 色彩映射：黑→藍→綠→黃→紅→白
    │
    ├── MeterView × 2（IN / OUT）
    │   └── 30 段 LED：綠 0-70% / 黃 70-85% / 紅 85-100%
    │
    ├── 呼號橫幅（解碼後顯示）
    │
    ├── START/STOP 按鈕
    │
    └── Toolbar
        ├── LogView（診斷日誌，色彩分類，可分享）
        └── SettingsView（裝置選擇，RADE 資訊）
```

### ViewModel Polling

```swift
// TransceiverViewModel
// Timer 每 50ms（20 Hz）從 AudioManager 同步所有 @Published 屬性
statusTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
    self.isRunning = audioManager.isRunning
    self.syncState = audioManager.syncState
    self.snr = audioManager.snr
    self.freqOffset = audioManager.freqOffset
    self.inputLevel = audioManager.inputLevel
    self.outputLevel = audioManager.outputLevel
    // FFT → waterfall history 管理（最多 100 行）
}
```

---

## 10. 關鍵設計決策與注意事項

### 10.1 為什麼 FARGAN 需要獨立 Queue？

FARGAN 神經網路合成一幀可能需要 10-50ms（取決於裝置），如果在 processingQueue 上跑會阻塞 rade_rx 處理，導致 audio buffer underrun。獨立 queue + overload 保護確保即使 FARGAN 跟不上也不會凍結。

### 10.2 Stereo → Mono 為什麼只取 ch0？

USB 音效卡（如 Sound Blaster Play! 3）提供 2ch 輸入，但實際訊號可能只在左聲道。右聲道可能是空的、雜訊、或反相訊號。平均兩聲道可能降低 SNR。

### 10.3 為什麼停用 iOS 語音處理？

iOS 的 AGC、噪音抑制、回音消除會嚴重扭曲 OFDM modem 訊號：
- AGC 改變訊號振幅 → pilot 估計失準
- 噪音抑制誤判載波為噪音 → 消除有用訊號
- `.measurement` mode 提供完全無處理的原始音訊

### 10.4 Unity Build 的原因

Xcode 的 build phase 可能不會自動將所有 .c 檔案加入編譯。Unity build（`rade_all.c`）確保所有 RADE 符號都被編譯進目標，同時避免重複符號。

### 10.5 dred_rdovae_constants.h Stub

`Libraries/opus/dnn/dred_rdovae_constants.h` 是一個 stub header，提供 FARGAN 需要的 `DRED_MAX_CONV_INPUTS=1536`。原始值 512 會導致 `nnet.c` 的 assertion failure。

---

## 11. iOS 音訊路由限制

### USB 音效卡的輸入/輸出配對限制

iOS 將 USB 音效卡視為**完整的輸入+輸出配對**。已實測確認：

- `overrideOutputAudioPort(.speaker)` → 輸出切到喇叭，但**輸入也會從 USB 變成內建麥克風**
- `setPreferredInput(usb)` → 輸入切回 USB，但**會清除 speaker override，輸出也回到 USB**
- 兩個 API 互相衝突，**無法同時實現 USB 輸入 + iPhone 喇叭輸出**

### 實際使用方式

| 輸入來源 | 輸出目的地 | 可行性 |
|----------|-----------|--------|
| USB 音效卡 | USB 音效卡（接耳機/喇叭） | 可行（推薦） |
| USB 音效卡 | iPhone 喇叭 | 不可行（iOS 限制） |
| iPhone 麥克風 | iPhone 喇叭 | 可行（但非典型 SWL 場景） |
| 純輸入 USB 裝置（無輸出） | iPhone 喇叭 | 可行（裝置無輸出端，iOS 自動用喇叭） |

**推薦配置**：SDR → USB 音效卡 → iPhone，在 USB 音效卡上接耳機聽解碼語音。

---

## 12. 已知問題與未來方向

- **SWL 專用**：僅支援 RX，TX 功能已移除
- **WiFi 除錯**：USB 音效卡佔用 Lightning/USB-C 接口時無法連線 Xcode，需使用 WiFi 除錯或 in-app LogView
- **FARGAN 效能**：在較舊 iPhone 上可能無法即時合成，overload 保護會丟幀
- **Sample Rate 假設**：目前假設硬體取樣率為 48kHz，理論上 AVAudioConverter 可處理任何取樣率
