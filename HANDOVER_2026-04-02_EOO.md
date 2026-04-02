# iOS ↔ Android EOO 呼號交互修復 — 交接文件（2026-04-02）

## 1. 交接摘要

本輪主要工作：修復 iOS RX 無法偵測並解碼 Android TX 發送的 EOO（End-of-Over）呼號。
附帶修復：SwiftData 刪除 session 時 crash 的問題。

---

## 2. 問題背景

Android TX 發送 RADE 語音後，會在結尾送出一個 EOO 幀，其中包含 LDPC 編碼的呼號。
iOS RX 原本完全無法偵測到 EOO 幀，也無法解碼呼號。

根因分析發現 3 個 bug（Android 端已知）加上 iOS 端的閾值問題：

| Bug | 位置 | 說明 |
|-----|------|------|
| Bug 1 | `rade_ofdm.c` | EOO 解調時 EQ 用錯 pilot index：`rx_sym[Ns]` → 應為 `rx_sym[Ns+1]` |
| Bug 2 | `rade_ofdm.c` | 資料提取迴圈少取一個 symbol：`s < Ns` → 應為 `s <= Ns` |
| Bug 3 | Android TX 端 | EOO 幀被額外乘以 0.45× gain，導致 pilot 功率偏低（**尚未修復**） |
| 閾值 | `rade_acq.c` | 原始閾值 100% 對 Bug 3 導致的弱信號過於嚴格 |

---

## 3. iOS 端已完成修復

### 3.1 Bug 1 修復：EOO EQ pilot index（`rade_ofdm.c`）

EOO 幀結構為 `[P][Pend][D][D][D][Pend]`，共 Ns+2 = 6 個 symbol。
第三個 pilot（最後的 Pend）在 `rx_sym[Ns+1]`（index 5），不是 `rx_sym[Ns]`（index 4）。

```c
// rade_ofdm_demod_eoo() — 三 pilot 平均 EQ
sum = rade_cadd(sum, rade_cdiv(rx_sym[0][c],      ofdm->P[c]));     // P
sum = rade_cadd(sum, rade_cdiv(rx_sym[1][c],      ofdm->Pend[c]));  // Pend
sum = rade_cadd(sum, rade_cdiv(rx_sym[Ns + 1][c], ofdm->Pend[c]));  // Pend (修復)
```

### 3.2 Bug 2 修復：資料 symbol 提取範圍（`rade_ofdm.c`）

EOO 幀有 Ns−1 = 3 個資料 symbol，位於 index 2, 3, 4（即 `s = 2` 到 `s = Ns`）。

```c
// 修復前：s < Ns → 只取 index 2, 3（少了 index 4）
// 修復後：s <= Ns → 取 index 2, 3, 4
for (int s = 2; s <= Ns; s++) {
    for (int c = 0; c < Nc; c++) {
        z_hat[out_idx++] = rx_sym[s][c].real;
        z_hat[out_idx++] = rx_sym[s][c].imag;
    }
}
```

### 3.3 EOO 偵測閾值放寬至 40%（`rade_acq.c`）

由於 Android Bug 3（EOO 幀被額外衰減），EOO pilot 相關值只有正常 threshold 的 ~65%。
將閾值從 100% 降至 40%，仍然安全（正常資料幀的 EOO 相關值僅 0.01–0.03，40% 閾值約 0.07）。

```c
// rade_acq_check_pilots()
*endofover = (Dtmax12_eoo > (0.40f * Dthresh_eoo)) ? 1 : 0;
```

**安全性分析：**

| 情境 | Dtmax12_eoo 範圍 | 40% 閾值 (≈0.07) | 結果 |
|------|------------------|-------------------|------|
| 正常資料幀 | 0.01–0.03 | 0.07 | 不偵測（安全） |
| EOO 幀（Bug 3 未修） | ~0.12 | 0.07 | 偵測成功（餘量 64%） |
| EOO 幀（Bug 3 修復後） | ~0.27 | 0.07 | 偵測成功（餘量 286%） |

> **當 Android 修復 Bug 3 後**，可考慮將閾值調回 55–60% 以獲得更好的抗噪能力。

### 3.4 SwiftData 刪除 crash 修復

**問題：** 滑動刪除 session 時 app crash：
```
Fatal error: This backing data was detached from a context without resolving attribute faults
- \ReceptionSession.callsignsDecoded
```

**修復：**
- `ReceptionLogView.deleteSessions()` 用 `withAnimation` 包裹，並在刪除前 fault-in 所有 lazy 屬性
- `SessionRowView`、`SessionSummaryCard`、`SessionMapPin` 加入 `guard session.modelContext != nil` 防護

---

## 4. EOO 幀技術規格

### 4.1 幀結構

```
EOO 幀: [P][Pend][D₁][D₂][D₃][Pend]
         ↑   ↑    ↑   ↑   ↑    ↑
         0   1    2   3   4    5  (symbol index)

P    = 正常 pilot（與資料幀相同）
Pend = EOO 專用 pilot
D    = 呼號 QPSK 資料 symbol
```

- **Symbol 數量：** Ns+2 = 6
- **資料 symbol 數量：** Ns−1 = 3
- **每個 symbol 載波數：** Nc = 30
- **QPSK 軟 symbol 數量：** (Ns−1) × Nc × 2 = 180 floats
- **EOO 幀長度：** RADE_NEOO = (Ns+2) × (M+Ncp) = 1152 samples

### 4.2 呼號編碼 Pipeline

```
TX: callsign → OTA 6-bit encoding → CRC-8 → LDPC(112,56) → interleave → QPSK → OFDM
RX: OFDM → QPSK soft syms → deinterleave → LDPC decode → CRC-8 check → OTA decode → callsign
```

- **LDPC 碼：** HRA_56_56, rate 1/2, 112 bits total (56 info + 56 parity)
- **Interleaver：** Golden-prime interleaver, 56 symbols
- **CRC：** CRC-8 over 8 bytes OTA data
- **OTA 編碼：** 每個字元 6 bits, 最多 8 字元
- **Max LDPC 迭代：** 100
- **BER 門檻：** 0.2 (20%)
- **EsNo：** 固定 3.0

### 4.3 iOS RX 解碼策略

Swift 層在收到 EOO 軟 symbol 後，會嘗試多種解碼：

1. **多 offset 嘗試：** offset 0 + full count, offset 0 + 56 symbols, offset 1..8 + 56 symbols
2. **相位旋轉：** 每種 offset 都嘗試 0°, 90°, 180°, 270° 旋轉（解決 constellation ambiguity）

### 4.4 關鍵常數（`rade_dsp.h`）

| 常數 | 值 | 說明 |
|------|-----|------|
| RADE_NC | 30 | OFDM 載波數 |
| RADE_M | 160 | 每 symbol 樣本數 |
| RADE_NCP | 32 | 循環前綴樣本數 |
| RADE_NS | 4 | 每 modem frame 資料 symbol 數 |
| RADE_NMF | 960 | 每 modem frame 樣本數 |
| RADE_NEOO | 1152 | EOO 幀樣本數 |
| RADE_ACQ_PACQ_ERR1 | 0.00001 | EOO 偵測用錯誤機率 |
| RADE_ACQ_PACQ_ERR2 | 0.0001 | 正常 pilot 偵測用錯誤機率 |

---

## 5. 給 Android 開發者的待辦

### 5.1 Bug 3：EOO 幀增益修正（必要）

目前 Android TX 在生成 EOO 幀時，額外乘以 ~0.45× gain（相對於正常資料幀）。
這導致 iOS RX 需要將 EOO 偵測閾值降到 40% 才能可靠偵測。

**建議：**
- 確認 EOO 幀的 pilot 振幅與正常資料幀的 pilot 振幅一致
- 修復後 iOS 的 40% 閾值仍然有效（餘量會從 64% 提升到 286%）
- 可以通知 iOS 端將閾值調回 55–60%

### 5.2 Android 端同樣的 Bug 1 / Bug 2 檢查

如果 Android 端的 EOO 解碼（RX 側）也有相同問題，需同步修復：

- **Bug 1：** `rade_ofdm_demod_eoo()` 中 EQ 的第三個 pilot 應使用 `rx_sym[Ns+1]`
- **Bug 2：** 資料提取迴圈應為 `s = 2; s <= Ns; s++`（包含 `Ns`）

### 5.3 呼號編碼格式相容性確認

iOS 和 Android 必須使用完全相同的：
- OTA 字元映射表（6-bit encoding）
- CRC-8 多項式
- LDPC H 矩陣（HRA_56_56）
- Golden-prime interleaver 參數

---

## 6. 修改檔案清單

### C 層（需 `touch rade_all.c` 觸發重編）

| 檔案 | 修改內容 |
|------|---------|
| `Libraries/radae/rade_ofdm.c` | Bug 1: EQ pilot index 修正, Bug 2: 迴圈範圍修正 |
| `Libraries/radae/rade_acq.c` | EOO 閾值 100% → 40%, 移除 diagnostic stdio |
| `Libraries/radae/rade_rx.c` | 移除 diagnostic fprintf |
| `Libraries/radae/rade_api_nopy.c` | 移除 build marker 和 diagnostic fprintf |

### C++ 層

| 檔案 | 修改內容 |
|------|---------|
| `Libraries/eoo/EooCallsignCodec.cpp` | 移除 decode() 內所有 diagnostic fprintf, 移除 cstdio |

### Swift 層

| 檔案 | 修改內容 |
|------|---------|
| `FreeDV/Bridge/RADETypes.swift` | 移除 eooOut dump log |
| `FreeDV/Views/ReceptionLogView.swift` | SwiftData deletion crash fix（withAnimation + fault-in + guard） |
| `FreeDV/Views/SessionDetailView.swift` | guard session.modelContext != nil |
| `FreeDV/Views/ReceptionMapView.swift` | guard session.modelContext != nil |

---

## 7. 重要注意事項

### 7.1 Unity Build 注意

`rade_all.c` 通過 `#include` 引入所有 `.c` 檔案。Xcode 不追蹤被 include 的 `.c` 檔案變更。
**每次修改 `rade_ofdm.c`、`rade_acq.c`、`rade_rx.c` 等檔案後，必須執行 `touch rade_all.c` 才能觸發重新編譯。**

### 7.2 目前 EOO 偵測成功率

- Android Bug 3 未修復狀態下：約 60–70%（取決於信號品質）
- Android Bug 3 修復後預期：>95%

### 7.3 測試方法

1. Android 端開始 RADE TX（設定好呼號）
2. iOS 端開始 RX，等待 sync
3. Android 端停止 TX（發送 EOO 幀）
4. iOS 端應顯示 `eoo-detected` + 呼號
5. 可在 console log 搜尋 `EOO detected` 或 `callsign decode` 關鍵字
