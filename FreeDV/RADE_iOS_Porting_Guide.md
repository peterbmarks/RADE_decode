# RADE iOS 移植指引

## 給 Xcode 中的 Claude 的完整操作手冊

**專案目標：** 將 FreeDV RADE 的純 C 實作（radae_nopy / librade）移植到 iOS，製作一個可以在 iPhone/iPad 上即時收發 RADE HF 數位語音的 App。

**來源 Repo：** https://github.com/peterbmarks/radae_decoder
**參考 iOS 舊專案：** https://github.com/peterbmarks/iOS-FreeDV （Codec2 時代的 iOS 版，可參考音訊架構）
**上游 RADE 研究 Repo：** https://github.com/drowe67/radae
**授權：** BSD-2-Clause

---

## 第零步：理解整體架構

### 什麼是 RADE

RADE（Radio Autoencoder）是 FreeDV 的新一代 HF 數位語音模式，結合了機器學習與傳統 DSP。核心流程：

**RX（接收解碼）：**
```
音訊輸入 (8 kHz mono)
  → Hilbert 轉換 (127-tap FIR) → 複數 IQ
  → RADE 接收器 (pilot 擷取, OFDM 解調, 神經網路解碼)
  → FARGAN 語音合成器 → 16 kHz mono 語音
  → 音訊輸出
```

**TX（發射編碼）：**
```
麥克風輸入 (16 kHz mono)
  → LPCNet 特徵提取 (36 features per 10ms frame)
  → 累積 12 個特徵幀 (120 ms)
  → RADE 發射器 (神經網路編碼, OFDM 調變)
  → 960 個複數 IQ 樣本 @ 8 kHz
  → [可選] 700–2300 Hz 帶通濾波器
  → 取實數部分，縮放 TX 音量
  → 音訊輸出到無線電
```

### 關鍵技術參數

| 參數 | 值 |
|------|-----|
| 調變取樣率 | 8000 Hz |
| 語音取樣率 | 16000 Hz |
| OFDM 載波數 | 30 |
| 頻寬 | ~1.3 kHz |
| Modem Frame | 960 samples @ 8 kHz (120 ms) |
| 隱空間維度 | 80 (neural autoencoder bottleneck) |
| 語音幀 | 160 samples @ 16 kHz (10 ms) |
| 每 Modem Frame 的特徵幀 | 12 |
| 神經網路權重 | ~47 MB（編譯進二進位） |

### 原始碼架構（需要移植的部分）

```
src/
├── radae/                    ← 【核心：必須完整移植】純 C 庫
│   ├── rade_api.h / .c       公開 API: rade_open, rade_rx, rade_tx, rade_close
│   ├── rade_ofdm.h / .c      OFDM 調變/解調: DFT/IDFT, pilot, 循環前綴, 均衡
│   ├── rade_rx.h / .c         RADE 接收器: pilot 擷取, OFDM 解調, 神經網路解碼, 同步狀態機
│   ├── rade_tx.h / .c         RADE 發射器: 神經網路編碼, OFDM 調變
│   ├── rade_acq.h / .c        基於 Pilot 的信號擷取與頻率/時序同步
│   ├── rade_bpf.h / .c        700–2300 Hz 帶通 FIR 濾波器
│   ├── rade_dsp.h / .c        DSP 基本操作: 複數運算, Hilbert 轉換, FFT
│   ├── rade_enc.h / .c        神經網路編碼器 (GRU + 卷積)
│   ├── rade_enc_data.h / .c   編碼器預訓練權重 (~24 MB)
│   ├── rade_dec.h / .c        神經網路解碼器 (GRU + 卷積)
│   └── rade_dec_data.h / .c   解碼器預訓練權重 (~23 MB)
│
├── radae_top/                ← 【需要移植】C++ 包裝層
│   ├── rade_core.h            共享類型與常數
│   ├── rade_constants.h       自動生成的神經網路維度
│   ├── rade_decoder.h/.cpp    RadaeDecoder: RX pipeline 線程
│   ├── rade_encoder.h/.cpp    RadaeEncoder: TX pipeline 線程
│   └── audio_passthrough.h/.cpp  音訊直通
│
├── eoo/                      ← 【移植】End-of-over callsign codec
│   └── EooCallsignCodec.h/.cpp
```

**不需要移植的部分（iOS 不用）：**
- `src/gui/` — GTK3 GUI（iOS 用 SwiftUI 重寫）
- `src/audio/audio_stream_alsa.cpp` — ALSA 後端
- `src/audio/audio_stream_pulse.cpp` — PulseAudio 後端
- `src/audio/audio_stream_portaudio.cpp` — PortAudio 後端（但架構可參考）
- `src/network/` — FreeDV Reporter（之後再考慮）
- `src/tools/` — 命令列工具

**需要從 Opus fork 編譯的外部依賴：**
- Opus（含 FARGAN/LPCNet 支援）— CMake 首次建構會從 GitHub 下載

---

## 第一步：建立 Xcode 專案

### 1.1 建立新專案

1. 在 Xcode 中建立新專案：**iOS → App**
2. 專案名稱：`RADE_iOS`（或 `FreeDV_RADE`）
3. 語言：**Swift**（UI 層）
4. UI 框架：**SwiftUI**
5. Bundle Identifier：`org.freedv.rade-ios`（或你自己的）
6. Deployment Target：**iOS 16.0**（需要 AVAudioEngine 的新功能）

### 1.2 專案目錄結構

在專案根目錄中建立以下結構：

```
RADE_iOS/
├── RADE_iOS.xcodeproj
├── RADE_iOS/
│   ├── App/
│   │   ├── RADE_iOSApp.swift          SwiftUI App 入口
│   │   └── ContentView.swift           主畫面
│   ├── Views/                          SwiftUI 視圖
│   │   ├── TransceiverView.swift       收發介面（模式切換、音量表、狀態）
│   │   ├── SpectrumView.swift          頻譜顯示
│   │   ├── WaterfallView.swift         瀑布圖
│   │   ├── MeterView.swift             音量表
│   │   └── SettingsView.swift          設定頁面
│   ├── ViewModels/
│   │   └── TransceiverViewModel.swift  管理 RX/TX 狀態的 ObservableObject
│   ├── Audio/
│   │   ├── AudioManager.swift          AVAudioEngine 管理（取代 ALSA/Pulse/PortAudio）
│   │   └── AudioDeviceManager.swift    iOS 音訊裝置列舉與路由
│   ├── Bridge/
│   │   ├── RADE_iOS-Bridging-Header.h  Objective-C Bridging Header
│   │   ├── RADEWrapper.h               Objective-C++ 包裝類 (.h)
│   │   └── RADEWrapper.mm              Objective-C++ 包裝類 (.mm)
│   ├── Resources/
│   │   └── Info.plist
│   └── Assets.xcassets
├── Libraries/                          C/C++ 原始碼（從 radae_decoder 複製）
│   ├── radae/                          librade 核心 C 庫（完整複製 src/radae/）
│   ├── radae_top/                      C++ 包裝層（選擇性複製）
│   ├── opus/                           Opus with FARGAN/LPCNet（需編譯）
│   └── eoo/                            End-of-over codec
└── Scripts/
    └── build_opus.sh                   編譯 Opus for iOS 的腳本
```

### 1.3 Bridging Header 設定

在 Build Settings 中設定：
- **Objective-C Bridging Header**：`RADE_iOS/Bridge/RADE_iOS-Bridging-Header.h`

---

## 第二步：Clone 並整合 C 原始碼

### 2.1 取得原始碼

```bash
# 在專案根目錄旁邊 clone
cd ~/Projects
git clone https://github.com/peterbmarks/radae_decoder.git
```

### 2.2 複製 librade 核心

將以下檔案複製到 `Libraries/radae/`：

```bash
# 從 radae_decoder/src/radae/ 複製所有 .h 和 .c 檔案
cp radae_decoder/src/radae/*.h RADE_iOS/Libraries/radae/
cp radae_decoder/src/radae/*.c RADE_iOS/Libraries/radae/
```

**包含的檔案清單（確認全部都有）：**
- `rade_api.h` / `rade_api.c`
- `rade_ofdm.h` / `rade_ofdm.c`
- `rade_rx.h` / `rade_rx.c`
- `rade_tx.h` / `rade_tx.c`
- `rade_acq.h` / `rade_acq.c`
- `rade_bpf.h` / `rade_bpf.c`
- `rade_dsp.h` / `rade_dsp.c`
- `rade_enc.h` / `rade_enc.c`
- `rade_enc_data.h` / `rade_enc_data.c` ← ⚠️ 約 24 MB
- `rade_dec.h` / `rade_dec.c`
- `rade_dec_data.h` / `rade_dec_data.c` ← ⚠️ 約 23 MB

### 2.3 複製 C++ 包裝層

```bash
# 選擇性複製 — 主要需要 rade_core.h 和 rade_constants.h
cp radae_decoder/src/radae_top/rade_core.h RADE_iOS/Libraries/radae_top/
cp radae_decoder/src/radae_top/rade_constants.h RADE_iOS/Libraries/radae_top/
# rade_decoder.h/.cpp 和 rade_encoder.h/.cpp 可以複製來參考，
# 但 iOS 版需要重寫音訊 I/O 部分
cp radae_decoder/src/radae_top/rade_decoder.h RADE_iOS/Libraries/radae_top/
cp radae_decoder/src/radae_top/rade_decoder.cpp RADE_iOS/Libraries/radae_top/
cp radae_decoder/src/radae_top/rade_encoder.h RADE_iOS/Libraries/radae_top/
cp radae_decoder/src/radae_top/rade_encoder.cpp RADE_iOS/Libraries/radae_top/
```

### 2.4 複製 EOO codec

```bash
cp radae_decoder/src/eoo/EooCallsignCodec.h RADE_iOS/Libraries/eoo/
cp radae_decoder/src/eoo/EooCallsignCodec.cpp RADE_iOS/Libraries/eoo/
```

### 2.5 複製 LPCNet/FARGAN 相關檔案

原始專案使用修改過的 Opus（含 FARGAN/LPCNet 支援），CMake 會自動下載。你需要：

```bash
# 查看 CMakeLists.txt 中 Opus 的下載來源
# 通常是 drowe67 的 fork，包含 FARGAN 支援
# 在 radae_decoder/build/ 目錄中找到已下載的 opus 源碼

# 需要的關鍵檔案在 opus 中的 dnn/ 目錄
# 包含 lpcnet.h, fargan.h 等
```

**⚠️ 重要：** Opus 的 FARGAN/LPCNet 部分是整個專案最複雜的外部依賴。建議先在 Mac 上用 CMake 完整 build 一次 radae_decoder，確認 opus 的結構，再移植到 iOS。

---

## 第三步：編譯 Opus（含 FARGAN）for iOS

### 3.1 先在 Mac 上成功 build

```bash
cd radae_decoder
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_GUI=OFF ..
make -j$(sysctl -n hw.ncpu)
```

這會下載 Opus 源碼到 `build/` 中某個目錄。記錄它的位置。

### 3.2 建立 iOS 交叉編譯腳本

建立 `Scripts/build_opus.sh`：

```bash
#!/bin/bash
# build_opus.sh — 為 iOS (arm64) 編譯 Opus with FARGAN/LPCNet
#
# 使用方式: ./Scripts/build_opus.sh <opus-source-dir> <output-dir>

set -e

OPUS_SRC="${1:?用法: $0 <opus-source-dir> <output-dir>}"
OUTPUT_DIR="${2:?用法: $0 <opus-source-dir> <output-dir>}"
IOS_DEPLOYMENT_TARGET="16.0"

# iOS SDK 路徑
SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)
CC=$(xcrun --sdk iphoneos --find clang)
CXX=$(xcrun --sdk iphoneos --find clang++)

mkdir -p "$OUTPUT_DIR"
cd "$OPUS_SRC"

# 如果 Opus 使用 autotools:
if [ -f "configure.ac" ]; then
    autoreconf -fi
    
    # arm64 (iPhone/iPad)
    mkdir -p build-ios-arm64
    cd build-ios-arm64
    
    ../configure \
        --host=aarch64-apple-darwin \
        --prefix="$OUTPUT_DIR/arm64" \
        --enable-static \
        --disable-shared \
        --disable-doc \
        --disable-extra-programs \
        CC="$CC" \
        CXX="$CXX" \
        CFLAGS="-arch arm64 -isysroot $SDKROOT -mios-version-min=$IOS_DEPLOYMENT_TARGET -O2 -fembed-bitcode" \
        CXXFLAGS="-arch arm64 -isysroot $SDKROOT -mios-version-min=$IOS_DEPLOYMENT_TARGET -O2 -fembed-bitcode" \
        LDFLAGS="-arch arm64 -isysroot $SDKROOT"
    
    make -j$(sysctl -n hw.ncpu)
    make install
    cd ..
fi

# 如果 Opus 使用 CMake:
if [ -f "CMakeLists.txt" ] && [ ! -f "configure.ac" ]; then
    mkdir -p build-ios-arm64
    cd build-ios-arm64
    
    cmake .. \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR/arm64" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF
    
    make -j$(sysctl -n hw.ncpu)
    make install
    cd ..
fi

echo "✅ Opus for iOS 編譯完成: $OUTPUT_DIR"
```

### 3.3 加入 Xcode 專案

1. 將編譯好的 `.a` 靜態庫加入專案
2. 在 Build Settings → Header Search Paths 加入 Opus header 路徑
3. 在 Build Settings → Library Search Paths 加入 `.a` 所在路徑
4. 在 Build Phases → Link Binary With Libraries 加入 `libopus.a`

---

## 第四步：Xcode 專案設定

### 4.1 將 C/C++ 檔案加入專案

在 Xcode 中：

1. 右鍵 Libraries group → **Add Files to "RADE_iOS"...**
2. 選取整個 `Libraries/radae/` 目錄
3. 選取整個 `Libraries/radae_top/` 目錄
4. 選取整個 `Libraries/eoo/` 目錄
5. 確保 **"Copy items if needed"** 有勾選
6. Target Membership 確保 `RADE_iOS` 有勾

### 4.2 Build Settings 調整

在 Build Settings 中設定：

```
// Header Search Paths (recursive)
$(SRCROOT)/Libraries/radae
$(SRCROOT)/Libraries/radae_top
$(SRCROOT)/Libraries/eoo
$(SRCROOT)/Libraries/opus/include

// Other C Flags
-DHAVE_CONFIG_H=1

// C Language Dialect
GNU11 (-std=gnu11)

// C++ Language Dialect
C++17 (-std=c++17)

// Enable Modules (C and Objective-C)
Yes

// Apple Clang - Language - C++
C++ Standard Library → libc++
```

### 4.3 處理大型權重檔案

⚠️ `rade_enc_data.c` (~24 MB) 和 `rade_dec_data.c` (~23 MB) 會顯著增加編譯時間。

**選項 A：直接編譯（簡單但慢）**
- 直接將 .c 檔加入專案
- 首次編譯需要很長時間，但之後增量編譯很快
- 在 Build Settings 中對這兩個檔案設定較高的 optimization：`-O2`

**選項 B：預編譯為靜態庫（推薦用於開發階段）**
```bash
# 先用命令列編譯權重檔為 .o
xcrun -sdk iphoneos clang -c -arch arm64 \
  -mios-version-min=16.0 -O2 \
  Libraries/radae/rade_enc_data.c -o rade_enc_data.o

xcrun -sdk iphoneos clang -c -arch arm64 \
  -mios-version-min=16.0 -O2 \
  Libraries/radae/rade_dec_data.c -o rade_dec_data.o

# 包裝成靜態庫
ar rcs librade_weights.a rade_enc_data.o rade_dec_data.o
```
然後將 `librade_weights.a` 加入專案的 Link Binary With Libraries。
從 Compile Sources 中移除 `rade_enc_data.c` 和 `rade_dec_data.c`。

### 4.4 必要的 iOS Framework

在 Build Phases → Link Binary With Libraries 加入：

- `AVFoundation.framework` — 音訊裝置與會話管理
- `AudioToolbox.framework` — 底層音訊功能
- `Accelerate.framework` — vDSP/BLAS 加速（**強烈建議，用於 FFT 等 DSP 運算**）

---

## 第五步：建立 Objective-C++ Bridge

Swift 不能直接呼叫 C/C++，需要透過 Objective-C++ bridge。

### 5.1 Bridging Header

**`RADE_iOS-Bridging-Header.h`：**
```objc
#ifndef RADE_iOS_Bridging_Header_h
#define RADE_iOS_Bridging_Header_h

#import "RADEWrapper.h"

#endif
```

### 5.2 RADEWrapper 設計

**`RADEWrapper.h`：**
```objc
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 同步狀態，映射到 RADE C 庫的狀態
typedef NS_ENUM(NSInteger, RADESyncState) {
    RADESyncStateSearching = 0,
    RADESyncStateCandidate = 1,
    RADESyncStateSynced = 2
};

// RX 狀態回報
@interface RADERxStatus : NSObject
@property (nonatomic) RADESyncState syncState;
@property (nonatomic) float snr;
@property (nonatomic) float freqOffset;
@end

// 主要 RADE 包裝類
@interface RADEWrapper : NSObject

// 初始化/釋放
- (instancetype)init;
- (void)dealloc;

// RX（接收）
// 輸入：8kHz mono int16 PCM 樣本
// 輸出：16kHz mono float 語音樣本（透過 callback）
- (void)rxProcessInputSamples:(const int16_t *)samples
                        count:(int)sampleCount;

// TX（發射）
// 輸入：16kHz mono int16 PCM 語音樣本
// 輸出：8kHz mono int16 OFDM 調變信號（透過 callback）
- (void)txProcessInputSamples:(const int16_t *)samples
                        count:(int)sampleCount;

// 狀態查詢
- (RADERxStatus *)getRxStatus;
- (BOOL)isSynced;

// TX 控制
@property (nonatomic) float txOutputLevel;  // 0.0 ~ 1.0
@property (nonatomic) BOOL bpfEnabled;      // 帶通濾波器開關

// Callbacks (設定 block)
@property (nonatomic, copy, nullable) void (^onDecodedAudio)(const float *samples, int count);
@property (nonatomic, copy, nullable) void (^onModulatedAudio)(const int16_t *samples, int count);
@property (nonatomic, copy, nullable) void (^onStatusUpdate)(RADERxStatus *status);
@property (nonatomic, copy, nullable) void (^onCallsignDecoded)(NSString *callsign);

@end

NS_ASSUME_NONNULL_END
```

**`RADEWrapper.mm`：**
```objc
#import "RADEWrapper.h"

// C 庫 headers
extern "C" {
#include "rade_api.h"
#include "rade_rx.h"
#include "rade_tx.h"
#include "rade_dsp.h"
#include "rade_bpf.h"
}

// C++ headers
#include "rade_core.h"
#include "rade_constants.h"

// FARGAN/LPCNet（根據實際 header 名稱調整）
extern "C" {
// #include "lpcnet.h"
// #include "fargan.h"
}

@implementation RADERxStatus
@end

@implementation RADEWrapper {
    // RADE 核心狀態
    struct rade *_rade;
    
    // Hilbert 轉換用的 buffer
    float *_hilbertBuffer;
    int _hilbertLen;
    
    // FARGAN vocoder 狀態
    // FARGANState *_fargan;
    
    // LPCNet 特徵提取狀態（TX 用）
    // LPCNetEncState *_lpcnetEnc;
    
    // 內部 buffer
    float *_featuresBuffer;      // 特徵累積 buffer
    int _featuresCount;          // 已累積的特徵幀數
    RADE_COMP *_iqBuffer;        // IQ 樣本 buffer
    
    // BPF 狀態
    // rade_bpf_state *_bpfState;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 初始化 RADE 核心
        // _rade = rade_open("unused");  // 權重已編譯進二進位
        
        // 初始化 Hilbert 轉換 buffer
        // _hilbertLen = 127;  // 127-tap Hamming-windowed FIR
        
        // 初始化 FARGAN vocoder
        // _fargan = fargan_create();
        
        // 初始化 LPCNet encoder (TX)
        // _lpcnetEnc = lpcnet_encoder_create();
        
        // 分配 buffer
        // _featuresBuffer = (float *)calloc(432, sizeof(float)); // 12 frames × 36 features
        // _iqBuffer = (RADE_COMP *)calloc(960, sizeof(RADE_COMP));
        
        _txOutputLevel = 1.0;
        _bpfEnabled = NO;
    }
    return self;
}

- (void)dealloc {
    // if (_rade) rade_close(_rade);
    // if (_fargan) fargan_destroy(_fargan);
    // if (_lpcnetEnc) lpcnet_encoder_destroy(_lpcnetEnc);
    // free(_featuresBuffer);
    // free(_iqBuffer);
    // free(_hilbertBuffer);
}

- (void)rxProcessInputSamples:(const int16_t *)samples count:(int)sampleCount {
    // 1. int16 → float 轉換
    // 2. Hilbert 轉換 (real → complex IQ)
    // 3. rade_rx() — pilot 擷取, OFDM 解調, 神經網路解碼
    // 4. 如果有解碼出的 features → FARGAN vocoder 合成語音
    // 5. 透過 onDecodedAudio callback 回傳解碼後的語音
    // 6. 更新狀態，透過 onStatusUpdate callback 回報
    
    // === 實作參考 radae_decoder/src/radae_top/rade_decoder.cpp ===
    // 核心邏輯在 RadaeDecoder::processAudio() 方法中
}

- (void)txProcessInputSamples:(const int16_t *)samples count:(int)sampleCount {
    // 1. int16 → float 轉換
    // 2. LPCNet 特徵提取 (每 160 samples @ 16kHz → 36 個 float 特徵)
    // 3. 累積 12 個特徵幀 (432 floats, 120 ms)
    // 4. rade_tx() — 神經網路編碼, OFDM 調變 → 960 RADE_COMP samples
    // 5. [可選] BPF 帶通濾波
    // 6. 取實數部分，乘以 txOutputLevel
    // 7. float → int16 轉換
    // 8. 透過 onModulatedAudio callback 回傳
    
    // === 實作參考 radae_decoder/src/radae_top/rade_encoder.cpp ===
    // 核心邏輯在 RadaeEncoder::processAudio() 方法中
}

- (RADERxStatus *)getRxStatus {
    RADERxStatus *status = [[RADERxStatus alloc] init];
    // 從 _rade 讀取同步狀態, SNR, 頻率偏移
    // status.syncState = ...;
    // status.snr = ...;
    // status.freqOffset = ...;
    return status;
}

- (BOOL)isSynced {
    return [self getRxStatus].syncState == RADESyncStateSynced;
}

@end
```

---

## 第六步：iOS 音訊引擎

這是移植中最關鍵的部分——用 AVAudioEngine 取代 ALSA/PulseAudio/PortAudio。

### 6.1 AudioManager.swift

```swift
import AVFoundation
import Combine

class AudioManager: ObservableObject {
    
    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    private var outputNode: AVAudioOutputNode { audioEngine.outputNode }
    private var playerNode = AVAudioPlayerNode()
    
    private let radeWrapper = RADEWrapper()
    
    // 音訊格式
    private let modemFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 8000,
        channels: 1,
        interleaved: true
    )!
    
    private let speechFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!
    
    // 狀態
    @Published var isRunning = false
    @Published var isTransmitting = false
    @Published var syncState: RADESyncState = .searching
    @Published var snr: Float = 0
    @Published var freqOffset: Float = 0
    @Published var inputLevel: Float = -60
    @Published var outputLevel: Float = -60
    
    init() {
        setupAudioSession()
        setupRADECallbacks()
    }
    
    // MARK: - 音訊會話設定
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // 設定為 playAndRecord，支援 USB 音訊裝置
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .defaultToSpeaker
                ]
            )
            
            // 設定較低延遲的 buffer
            try session.setPreferredIOBufferDuration(0.01) // 10ms
            
            // 監聽音訊路由變更（外接 USB 裝置等）
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: nil
            )
            
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    // MARK: - RADE Callbacks
    
    private func setupRADECallbacks() {
        // 接收到解碼語音時播放
        radeWrapper.onDecodedAudio = { [weak self] samples, count in
            self?.playDecodedAudio(samples: samples, count: count)
        }
        
        // 接收到調變信號時輸出
        radeWrapper.onModulatedAudio = { [weak self] samples, count in
            self?.playModulatedAudio(samples: samples, count: count)
        }
        
        // 狀態更新
        radeWrapper.onStatusUpdate = { [weak self] status in
            DispatchQueue.main.async {
                self?.syncState = status.syncState
                self?.snr = status.snr
                self?.freqOffset = status.freqOffset
            }
        }
    }
    
    // MARK: - RX（接收模式）
    
    func startRX() {
        guard !isRunning else { return }
        
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode,
                          format: speechFormat)
        
        // 從麥克風/音訊輸入擷取 modem 信號
        // 注意：inputNode 的原始格式通常是 44.1/48 kHz
        // 需要用 AVAudioConverter 轉換到 8kHz
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 960,
                            format: inputFormat) { [weak self] buffer, time in
            self?.processRXInput(buffer: buffer)
        }
        
        do {
            try audioEngine.start()
            playerNode.play()
            isRunning = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func stopRX() {
        inputNode.removeTap(onBus: 0)
        playerNode.stop()
        audioEngine.stop()
        audioEngine.detach(playerNode)
        isRunning = false
    }
    
    private func processRXInput(buffer: AVAudioPCMBuffer) {
        // 1. 重採樣到 8kHz（如果需要）
        // 2. 轉換為 int16
        // 3. 送入 radeWrapper.rxProcessInputSamples()
        
        // 實際需要 AVAudioConverter 做重採樣
        // let converter = AVAudioConverter(from: buffer.format, to: modemFormat)
        // ...
    }
    
    private func playDecodedAudio(samples: UnsafePointer<Float>, count: Int) {
        // 將解碼後的 16kHz float 語音排入 playerNode 播放
        let buffer = AVAudioPCMBuffer(
            pcmFormat: speechFormat,
            frameCapacity: AVAudioFrameCount(count)
        )!
        buffer.frameLength = AVAudioFrameCount(count)
        
        let channelData = buffer.floatChannelData![0]
        memcpy(channelData, samples, count * MemoryLayout<Float>.size)
        
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
    
    // MARK: - TX（發射模式）
    
    func startTX() {
        // TX 模式：從麥克風擷取 16kHz 語音
        // 編碼後輸出 8kHz OFDM 信號到指定的音訊輸出
        // 類似 RX 但方向相反
    }
    
    // MARK: - 音訊路由
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }
        
        switch reason {
        case .newDeviceAvailable:
            // USB 音訊裝置插入
            print("New audio device connected")
        case .oldDeviceUnavailable:
            // USB 音訊裝置移除
            print("Audio device disconnected")
        default:
            break
        }
    }
}
```

### 6.2 關鍵音訊注意事項

1. **取樣率轉換：** iOS 裝置原生通常是 44.1/48 kHz，RADE 需要 8 kHz (modem) 和 16 kHz (speech)。必須使用 `AVAudioConverter` 做重採樣。

2. **USB 音訊裝置：** iPhone 支援透過 Lightning/USB-C 連接 USB 音訊裝置（如 SignaLink）。使用 `AVAudioSession.currentRoute` 偵測。

3. **背景音訊：** 如果要在背景執行，需要在 Info.plist 加入 `UIBackgroundModes` → `audio`。

4. **雙裝置音訊：** iOS 有一個重要限制——不像桌面環境可以選擇不同的輸入/輸出裝置。iOS 的 AVAudioSession 通常會將輸入和輸出綁定到同一個裝置。如果需要從 USB 音訊裝置接收 modem 信號，同時用內建喇叭播放解碼語音，可能需要使用 Audio Unit (AUAudioUnit) 做更底層的控制。

5. **延遲：** RADE 的一個 modem frame 是 120ms，所以總延遲至少包含：
   - 一個 modem frame 的累積延遲 (120ms)
   - FARGAN 暖身 (5 frames = 50ms)
   - iOS 音訊 buffer (通常 ~10-20ms)
   - 整體約 200-300ms，對 HF QSO 來說完全可接受

---

## 第七步：SwiftUI 介面

### 7.1 主要畫面結構

```swift
struct TransceiverView: View {
    @StateObject private var viewModel = TransceiverViewModel()
    
    var body: some View {
        VStack(spacing: 16) {
            // 狀態列
            StatusBar(
                syncState: viewModel.syncState,
                snr: viewModel.snr,
                freqOffset: viewModel.freqOffset
            )
            
            // 頻譜/瀑布圖（使用 Canvas 或 Metal）
            SpectrumView(fftData: viewModel.fftData)
                .frame(height: 120)
            
            WaterfallView(history: viewModel.waterfallHistory)
                .frame(height: 200)
            
            // 音量表
            HStack {
                MeterView(label: "Input", level: viewModel.inputLevel)
                MeterView(label: "Output", level: viewModel.outputLevel)
            }
            .frame(height: 30)
            
            // RX / TX 切換
            Picker("Mode", selection: $viewModel.mode) {
                Text("RX").tag(TransceiverMode.rx)
                Text("TX").tag(TransceiverMode.tx)
            }
            .pickerStyle(.segmented)
            
            // TX 音量滑桿（僅在 TX 模式顯示）
            if viewModel.mode == .tx {
                HStack {
                    Text("TX Level")
                    Slider(value: $viewModel.txLevel, in: 0...1)
                    Text("\(Int(viewModel.txLevel * 100))%")
                }
                
                Toggle("BPF (700-2300 Hz)", isOn: $viewModel.bpfEnabled)
            }
            
            // 開始/停止按鈕
            Button(action: { viewModel.toggleRunning() }) {
                Text(viewModel.isRunning ? "Stop" : "Start")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isRunning ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}
```

### 7.2 頻譜顯示建議

對於頻譜和瀑布圖，有幾個選項：

- **SwiftUI Canvas：** 簡單，適合頻譜顯示
- **Metal/MetalKit：** 高性能，適合瀑布圖的即時更新
- **SpriteKit：** 折衷方案

對於 MVP（最小可行產品），建議先用 Canvas，之後再優化為 Metal。

---

## 第八步：平台適配細節

### 8.1 需要修改的 C 程式碼

librade 核心是純 C，應該幾乎不需要修改就能在 iOS 上編譯。但需要注意：

1. **記憶體對齊：** ARM64 通常比 x86 更嚴格，確認沒有未對齊的記憶體存取。

2. **浮點運算：** iPhone 的 ARM64 有硬體浮點，不需要軟體浮點模擬。NEON SIMD 也可用。

3. **`math.h` 函數：** 確認所有 math 函數都可用（`sinf`, `cosf`, `sqrtf` 等）。iOS 的 libm 完整支援。

4. **FFT 加速（可選但推薦）：** 原始碼中的 DFT/IDFT 可以用 Accelerate framework 的 `vDSP_fft_zrip` 替換以獲得更好的性能。這不是必須的，但能顯著降低 CPU 使用。

### 8.2 Preprocessor Definitions

可能需要加入的預處理器定義（根據原始碼的 `#ifdef` 需求調整）：

```
// Build Settings → Preprocessor Macros
HAVE_CONFIG_H=1
// 根據需要添加其他定義
```

### 8.3 Info.plist 設定

```xml
<!-- 麥克風權限 -->
<key>NSMicrophoneUsageDescription</key>
<string>RADE 需要麥克風來接收 HF 無線電數位語音信號，以及發射時錄製您的語音。</string>

<!-- 背景音訊（如需要） -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

---

## 第九步：開發順序建議

以下是推薦的迭代開發順序，每一步都是可驗證的里程碑：

### Phase 1：C 庫編譯通過（純編譯，不執行）
- [ ] 所有 `src/radae/*.c` 檔案編譯通過
- [ ] Opus with FARGAN 編譯通過
- [ ] 靜態連結無錯誤
- **驗證方法：** 在 Xcode 中 Build 成功，無 error

### Phase 2：離線解碼測試
- [ ] 實作 RADEWrapper 的基本初始化（rade_open/close）
- [ ] 讀取一個 WAV 檔案（從 bundle 載入 `FDV_offair.wav` 測試檔）
- [ ] 送入 RX pipeline，產出解碼後的語音
- [ ] 用 AVAudioPlayer 播放解碼結果
- **驗證方法：** 能聽到清晰的解碼語音

### Phase 3：即時 RX
- [ ] AVAudioEngine 從輸入裝置擷取音訊
- [ ] 重採樣到 8kHz
- [ ] 即時送入 RX pipeline
- [ ] 即時播放解碼語音
- **驗證方法：** 用另一台電腦的 FreeDV 發送 RADE 信號，iOS 裝置能即時解碼

### Phase 4：即時 TX
- [ ] 從麥克風擷取 16kHz 語音
- [ ] LPCNet 特徵提取
- [ ] RADE 編碼 + OFDM 調變
- [ ] 輸出到音訊裝置
- **驗證方法：** iOS 發送的信號能被 FreeDV 桌面版成功解碼

### Phase 5：UI 完善
- [ ] 頻譜顯示
- [ ] 瀑布圖
- [ ] 音量表
- [ ] 設定頁面（裝置選擇等）

### Phase 6：進階功能
- [ ] EOO (End-of-over) callsign codec
- [ ] FreeDV Reporter 整合
- [ ] 設定持久化

---

## 第十步：常見問題與除錯

### Q: 編譯 rade_enc_data.c / rade_dec_data.c 時 Xcode 卡住或 OOM

**A:** 這兩個檔案加起來約 47 MB 的 C 源碼（全是巨大的 float 陣列），編譯需要大量記憶體。解決方案：
1. 使用「預編譯為靜態庫」方法（見 4.3 選項 B）
2. 在 Xcode → Build Settings 中，將這些檔案的 compiler flags 設為 `-O0`（降低最佳化等級以減少記憶體使用）

### Q: 找不到 Opus/FARGAN/LPCNet header

**A:** 先在 Mac 上用 CMake 完整 build radae_decoder，然後到 `build/` 目錄下找 Opus 的源碼位置。通常 CMake 會下載到 `_deps/` 或 `opus-src/` 等目錄。你需要的 header 在 Opus 源碼的 `include/` 和 `dnn/` 目錄。

### Q: ARM64 上的性能如何？

**A:** 根據 Mac Mini M4 的測試，54 秒的音訊需要 11 秒來解碼（約 5x 即時速度）。iPhone 的 A 系列晶片架構類似，性能應該足夠即時處理。iPhone 15 Pro (A17 Pro) 以上應該綽綽有餘。較舊的機型（如 iPhone 12/A14）可能需要測試。

### Q: 如何測試 RX 但沒有 HF 無線電？

**A:** 
1. 用 radae_decoder 的命令列工具產生測試 WAV 檔：
   ```bash
   # 在 Mac 上
   ./rade_modulate voice.wav tx_rade.wav
   ```
2. 將 `tx_rade.wav` 放入 iOS App 的 bundle 中
3. 直接讀取 WAV 檔送入 RX pipeline 測試

### Q: 雙音訊裝置（USB 接無線電 + 內建喇叭）在 iOS 上怎麼實現？

**A:** 這是 iOS 最大的限制。幾個方案：
1. **AUAudioUnit + Multi-Route：** 使用 `AVAudioSession.Category.multiRoute` 和底層 Audio Unit API
2. **USB 裝置全包：** 讓 USB 音訊裝置同時處理無線電和耳機（如 SignaLink + headset）
3. **藍牙 + USB：** 無線電用 USB，操作員耳機用藍牙

---

## 附錄 A：完整 API 對應表

| 原始 C/C++ 函數 | iOS 對應 | 說明 |
|----------------|----------|------|
| `rade_open()` | `RADEWrapper.init()` | 初始化 RADE codec |
| `rade_rx()` | `radeWrapper.rxProcessInputSamples()` | 接收解碼 |
| `rade_tx()` | `radeWrapper.txProcessInputSamples()` | 發射編碼 |
| `rade_close()` | `RADEWrapper.dealloc()` | 釋放資源 |
| `fargan_synthesize()` | 在 RADEWrapper 內部呼叫 | FARGAN 語音合成 |
| `lpcnet_compute_single_frame_features()` | 在 RADEWrapper 內部呼叫 | LPCNet 特徵提取 |
| `AudioStream::read()` | `AVAudioInputNode.installTap()` | 音訊輸入 |
| `AudioStream::write()` | `AVAudioPlayerNode.scheduleBuffer()` | 音訊輸出 |
| `AudioStream::listDevices()` | `AVAudioSession.currentRoute` | 裝置列舉 |

## 附錄 B：記憶體預估

| 組件 | 大小 |
|------|------|
| 神經網路權重（編碼器+解碼器） | ~47 MB |
| RADE 狀態結構 | ~1 MB |
| FARGAN vocoder 狀態 | ~2 MB |
| 音訊 buffer | ~1 MB |
| **總計** | **~51 MB** |

以現代 iPhone 的 RAM (6-8 GB) 來說完全不是問題。

## 附錄 C：執行這份指引的 Checklist

給 Xcode 中的 Claude 使用，依序執行：

```
□ 1. 建立 Xcode iOS App 專案（SwiftUI, iOS 16+）
□ 2. 建立目錄結構（Libraries/, Bridge/, Views/, ViewModels/, Audio/）
□ 3. Clone radae_decoder repo
□ 4. 複製 src/radae/ 所有檔案到 Libraries/radae/
□ 5. 複製 src/radae_top/ 必要檔案到 Libraries/radae_top/
□ 6. 複製 src/eoo/ 到 Libraries/eoo/
□ 7. 在 Mac 上 cmake build radae_decoder 以獲得 Opus 源碼
□ 8. 交叉編譯 Opus for iOS arm64
□ 9. 設定 Xcode Build Settings（Header/Library Search Paths）
□ 10. 建立 Bridging Header
□ 11. 實作 RADEWrapper.h / .mm
□ 12. 加入必要的 iOS frameworks（AVFoundation, AudioToolbox, Accelerate）
□ 13. 設定 Info.plist（麥克風權限等）
□ 14. Phase 1 驗證：Build 通過
□ 15. 放入測試 WAV 檔
□ 16. Phase 2 驗證：離線解碼成功
□ 17. 實作 AudioManager.swift
□ 18. Phase 3 驗證：即時 RX 成功
□ 19. 實作 TX pipeline
□ 20. Phase 4 驗證：即時 TX 成功
□ 21. 實作 SwiftUI 介面
□ 22. Phase 5 驗證：UI 完整
```
