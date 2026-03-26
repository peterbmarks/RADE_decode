# Third-Party Notices

This project includes third-party software components. Their original licenses apply to those components.

## 1) RADE Modem Library
- Path: `Libraries/radae/`
- Copyright: David Rowe and contributors
- License: BSD-2-Clause-style (as stated in file headers, e.g. `Libraries/radae/rade_api.h`)

## 2) KISS FFT (used within RADE/Opus sources)
- Paths:
  - `Libraries/radae/kiss_fft.c`
  - `Libraries/radae/kiss_fftr.c`
  - `Libraries/radae/_kiss_fft_guts.h`
  - `Libraries/opus/celt/kiss_fft.c`
- Copyright: Mark Borgerding and contributors
- License: BSD-3-Clause-style (as stated in file headers)

## 3) Opus / FARGAN / LPCNet related code and binaries
- Path: `Libraries/opus/`
- Copyright: Xiph.Org, Skype Limited, Octasic, Jean-Marc Valin, Timothy B. Terriberry, CSIRO, Gregory Maxwell, Mark Borgerding, Erik de Castro Lopo, Mozilla, Amazon
- License: BSD-style (see `Libraries/opus/COPYING` and `Libraries/opus/LICENSE_PLEASE_READ.txt`)
- Patent notices: see links listed in `Libraries/opus/COPYING`

## 4) EOO Callsign Codec
- Path: `Libraries/eoo/`
- Copyright: Derived from codec2 and FreeDV GUI works
- License: LGPL-2.1-or-later (as stated in `Libraries/eoo/EooCallsignCodec.h` and `Libraries/eoo/EooCallsignCodec.cpp`)

## Notes
- The repository-level `LICENSE` is set to `LGPL-2.1-or-later`.
- Keep upstream copyright/license headers intact when redistributing source or binaries.
- If you distribute binaries containing LGPL components, ensure LGPL obligations are met for that distribution.
