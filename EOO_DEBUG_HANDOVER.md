# EOO Callsign Decode — Debug Handover

## Problem Statement

RADE (Radio Autoencoder) 接收端偵測到 EOO (End-of-Over) 訊框，但無法解碼出內嵌的呼號。
Diagnostic log 顯示 LDPC decoder BER ≈ 50%（等同隨機資料），且 EOO 在整段通話中每一幀都觸發。

---

## System Architecture Overview

### EOO Frame Structure (TX)

```
Normal voice:  P  D  D  D  D  P_next   (6 OFDM symbols)
EOO frame:     P  E  D  D  D  E        (6 OFDM symbols)
               0  1  2  3  4  5        ← position index
```

- **P** = Barker-13 pilot, `P[c] = sqrt(2) * barker13[c % 13]` (real-valued)
- **E** = EOO pilot (Pend), `Pend[c] = P[c] * (-1)^c` (odd carriers negated)
- **D** = QPSK data carrying callsign (3 symbols × 30 carriers × I,Q = 180 floats)
- Total: `(Ns-1) × Nc × 2 = 3 × 30 × 2 = 180` soft-decision floats = 90 QPSK symbols

### Callsign Codec (LDPC)

```
Encoding: callsign → 8 chars × 6-bit OTA = 48 bits + 8-bit CRC-8 = 56 info bits
          → LDPC(112,56) HRA_56_56 → 112 coded bits → 56 QPSK symbols
          → golden-prime interleaver (N=56, b=37) → modulated onto 90 carrier slots
Decoding: 90 QPSK symbols → deinterleave → LLR → LDPC sum-product (max 100 iter)
          → BER gate (< 0.2) → CRC-8 check → OTA→ASCII
```

### Signal Flow (RX)

```
RF → ADC → rx_buf → freq correction (rx_corrected) → DFT per symbol
  → rade_ofdm_demod_eoo() → quality metric + equalized symbols
  → quality > threshold? → eoo_out → Swift → eoo_callsign_decode()
```

### Key Files

| File | Role |
|------|------|
| `Libraries/radae/rade_ofdm.c` | OFDM demod, EOO demod + quality metric |
| `Libraries/radae/rade_rx.c` | RX state machine, EOO threshold check |
| `Libraries/radae/rade_tx.c` | TX EOO frame construction |
| `Libraries/radae/rade_dsp.c` | Pilot generation (Barker-13, Pend) |
| `Libraries/radae/rade_acq.c` | Acquisition EOO detection (diagnostic only) |
| `Libraries/eoo/EooCallsignCodec.cpp` | LDPC callsign codec with diagnostics |
| `FreeDV/Bridge/RADETypes.swift` | Swift EOO decode integration |

---

## Debugging Timeline

### Round 1: Interpolated Equalization (FAILED)

**Hypothesis**: Original `rade_ofdm_demod_eoo()` used single-average phase correction
across all 3 data symbols. Residual frequency offset causes phase drift exceeding
the codec's ±30° tolerance.

**Fix**: Changed to interpolated phase correction between early pilots (P@0, E@1)
and late pilot (E@5), matching the approach of `rade_ofdm_pilot_eq()` for normal frames.

**Result**: Still 50% BER. The fix was necessary but not sufficient — the real
problem was false positive detection (see Round 2).

### Round 2: Normalized Quality Metric (CURRENT)

**Root cause found**: The quality metric was triggering on EVERY voice frame, not
just actual EOO frames.

**Why the old metric failed**:

Old metric: `q = Σ_c |H0[c] + H1[c] + H5[c]|`, threshold `2 × Nc = 60` (absolute)

For a **normal voice frame** at position Ns+1 = 5, the next pilot P is received:
```
H5[c] = rx_sym[5][c] / Pend[c]
       = P[c] · H[c] / Pend[c]
       = P[c] · H[c] / ((-1)^c · P[c])
       = (-1)^c · H[c]
```

So for **even carriers**: `H0 + H5 = H + H = 2H` → quality contribution ≈ 2|H|
For **odd carriers**: `H0 + H5 = H - H = 0` → only random H1 contributes

With Nc=30 (15 even + 15 odd): q ≈ 15 × 2|H| + 15 × |H| = 45|H|

At moderate signal levels (|H| > 1.3), this exceeds threshold 60. Every frame fires.

**New metric**: Normalized correlation
```c
power_sum = Σ_c |H0[c]|²
corr_sum  = Σ_c Re(H1[c]·conj(H0[c])) + Re(H5[c]·conj(H0[c]))
q = corr_sum / power_sum
```

| Frame type | H1 contribution | H5 contribution | q value |
|------------|----------------|-----------------|---------|
| EOO frame  | Σ\|H\|² (coherent) | Σ\|H\|² (coherent) | **≈ 2.0** |
| Voice frame | ≈ 0 (random) | Σ(-1)^c\|H\|² = **0** (cancels, Nc even) | **≈ 0.0** |

Threshold: `0.8f` → robust down to ~0 dB SNR.

---

## Diagnostic Output Format

Added `fprintf` in `EooCallsignCodec.cpp`:
```
EOO_DIAG: symSize=90 rms=2.8058 in[0]=(-0.262,0.682) in[1]=(0.310,-0.496) in[2]=(-2.029,-0.931)
EOO_DIAG: ldpcIter=100 parityChecks=28/56 BER=0.500
EOO_DIAG: CRC rx=0x66 calc=0x47 FAIL
```

**Interpretation guide**:
- `rms` ≈ 0.7 for unit QPSK → much higher means non-QPSK data (false positive)
- `BER = 0.500` → decoder sees random bits (false positive or severe channel error)
- `BER < 0.2` → LDPC converged, check CRC
- `parityChecks = 56/56, BER = 0.000, CRC FAIL` → LDPC found wrong codeword
- `CRC PASS` → successful decode, callsign printed

---

## Open Questions / Remaining Concerns

### 1. Is the transmitter actually sending EOO?

If the other station is a desktop FreeDV without EOO support, the TX won't send
an EOO frame at all. In that case, ALL detections are false positives and no
amount of RX improvement will help.

**Verification**: Check if the TX station supports EOO. The iOS app should set
EOO bits via `rade_tx_state_set_eoo_bits()` before calling `rade_tx_state_eoo()`.

### 2. Phase-only equalization — is magnitude correction needed?

Normal frame equalization (`rade_ofdm_pilot_eq`) has an optional **coarse magnitude
correction** step. The EOO demod does NOT do magnitude correction.

The codec's `eoo_symbols_to_llrs()` normalizes by RMS, which should handle uniform
amplitude scaling. But frequency-selective fading (different |H| per carrier) means
per-carrier amplitude varies. The fixed `amps[i] = rms` assumption might produce
suboptimal LLRs.

**Potential fix**: Add per-carrier magnitude correction in EOO demod, or pass
per-carrier amplitude estimates to the codec.

### 3. pilot_gain and tanh_limit distortion

TX applies `pilot_gain` scaling and `tanh_limit()` (for bottleneck=3) to EOO data
symbols. The RX equalization corrects for the channel but does NOT undo these TX
scaling operations.

For normal voice frames, the neural decoder implicitly handles this. But for EOO
QPSK symbols, the LDPC decoder expects unit-amplitude QPSK.

**Potential fix**: In RX, after phase correction, divide by pilot_gain (and
potentially undo tanh distortion).

### 4. EsNo parameter hardcoded to 3.0

In `EooCallsignCodec.cpp`, `eoo_symbols_to_llrs()` uses `EsNo = 3.0f` (≈ 4.8 dB).
This should ideally match the actual channel SNR. At low SNR, hardcoded EsNo = 3.0
overestimates confidence, producing unreliable LLRs.

### 5. LS pilot smoothing not used for EOO

Normal pilot equalization uses a 3-carrier LS fit (`rade_ofdm_est_pilots()`) for
frequency-domain smoothing. The EOO demod uses raw `H = rx_sym / pilot` without
any smoothing. This makes EOO estimates noisier.

### 6. Normal frame demod interpolation parameter

Normal frame uses:
```c
float t = (float)(s) / (float)(Ns + 1);  // s = 0..Ns-1
```

EOO frame uses:
```c
float t = ((float)s - 0.5f) / ((float)Ns + 0.5f);  // s = 2..Ns
```

Both are phase-only correction. The t ranges are:
- Normal: t ∈ [0, 0.6] for 4 data symbols
- EOO: t ∈ [0.33, 0.78] for 3 data symbols

The EOO interpolation assumes H_early is at position 0.5 (average of P@0 and E@1)
and H_late is at position Ns+1 = 5. This should be geometrically correct.

---

## What To Try Next

### Priority 1: Verify quality metric fix works

Run the app and observe diagnostic output:
- If no `EOO_DIAG` lines appear during voice → quality metric fix is working
  (no false positives)
- If `EOO_DIAG` still appears on every frame → quality metric still broken

### Priority 2: Confirm TX sends EOO

Test with known iOS-to-iOS connection where both sides have EOO enabled.
Or test with a known-good FreeDV desktop client that sends EOO.

Add quality value to diagnostic: in `rade_rx.c` after threshold check:
```c
if (eoo_quality > eoo_thresh) {
    fprintf(stderr, "EOO_Q: quality=%.3f thresh=%.3f\n", eoo_quality, eoo_thresh);
    ...
}
```

### Priority 3: Amplitude normalization

If quality metric works but decode still fails (BER high), the symbols might
have wrong amplitude. Add magnitude correction to EOO demod:

```c
// After phase correction, apply per-carrier magnitude correction
float mag = rade_cabs(ch_est);
if (mag > 1e-6f) {
    corrected = rade_cscale(corrected, 1.0f / mag);
}
```

### Priority 4: Loopback test

Create a loopback test: TX encode "BX4ACP" → EOO frame → pass directly to
RX demod (no channel, no noise). If this fails, the encode/decode pipeline
has a bug independent of channel effects.

```c
// Pseudocode for loopback test:
rade_tx_state tx;
rade_tx_init(&tx, ...);
eoo_callsign_encode("BX4ACP", eoo_bits, n_eoo_bits);
rade_tx_state_set_eoo_bits(&tx, eoo_bits);
RADE_COMP eoo_iq[RADE_NEOO];
rade_tx_state_eoo(&tx, eoo_iq);

// Demodulate directly (no channel)
float z_hat[180];
float quality;
rade_ofdm_demod_eoo(&rx_ofdm, z_hat, eoo_iq, 0, &quality);

// Decode
char callsign[16];
eoo_callsign_decode(z_hat, 90, callsign, 16);
// Should output "BX4ACP"
```

### Priority 5: Compare with upstream rade_text

The EOO codec is derived from `rade_text` in the upstream RADE codebase. Compare:
- Symbol normalization approach
- LLR calculation parameters
- LDPC decoder configuration
- How the upstream handles the same equalization problem

---

## Code Change Summary

### Modified files (current state):

1. **`rade_ofdm.c:524-602`** — `rade_ofdm_demod_eoo()`
   - Interpolated phase correction between early/late pilots
   - Normalized correlation quality metric (corr_sum / power_sum)

2. **`rade_rx.c:306-308`** — EOO threshold
   - Changed from `2.0f * RADE_NC` (absolute) to `0.8f` (normalized)

3. **`RADETypes.swift:~203-285`** — Swift EOO decode
   - Removed useless 90°/180°/270° QPSK rotation attempts
   - Simplified to 2 attempts: full symbol count and LDPC-only (56)

4. **`EooCallsignCodec.cpp:~639-708`** — Diagnostic fprintf
   - Added `EOO_DIAG:` output for symSize, rms, input symbols, LDPC stats, CRC

---

## Constants Reference

| Constant | Value | Description |
|----------|-------|-------------|
| `RADE_NC` | 30 | Number of OFDM carriers |
| `RADE_NS` | 4 | Data symbols per normal frame |
| `RADE_M` | 160 | DFT/IDFT size |
| `RADE_NCP` | 32 | Cyclic prefix length |
| `RADE_NMF` | 960 | Samples per modem frame = (Ns+1)×(M+Ncp) |
| `RADE_NEOO` | 1152 | Samples in EOO frame = (Ns+2)×(M+Ncp) |
| `n_eoo_bits` | 180 | EOO soft-decision floats = (Ns-1)×Nc×2 |
| LDPC | (112,56) | Rate-1/2, HRA_56_56 parity check matrix |
| Interleaver | N=56, b=37 | Golden-prime interleaver |
| CRC-8 | 0x1D | Generator polynomial |

---

*Last updated: 2026-04-04*
