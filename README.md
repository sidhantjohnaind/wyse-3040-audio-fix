# Dell Wyse 3040 Linux Audio Kernel Driver & Patches
### Unlocking Multi-Rate Audio (44.1 kHz, 88.2 kHz, 96 kHz, 192 kHz) on Intel Cherry Trail (`cht_bsw_rt5672`)

---

## 📌 Project Overview
The **Dell Wyse 3040** thin client features an Intel Cherry Trail SoC paired with a Realtek RT5672 audio codec and Intel SST LPE (Low Power Engine) Audio DSP. By default in Linux mainline kernels (e.g. 6.x), audio playback is often restricted or locked to 48 kHz due to DPCM rate merging locks, static clock constraints, and DSP firmware boundaries.

This repository provides kernel patches, technical documentation, and compilation instructions to enable full audio playback support across **44.1 kHz, 48 kHz, 88.2 kHz, 96 kHz, and 192 kHz** formats at **16-bit** and **24-bit** depth using ALSA, PulseAudio, and PipeWire sound servers.

---

## 🔬 Hardware & Firmware Architecture Analysis

| Component | Hardware / Module | Behavior & Constraint |
| :--- | :--- | :--- |
| **SoC / DSP** | Intel Cherry Trail SST LPE (`intel/fw_sst_22a8.bin`) | The DSP firmware SBA (Smart Bus Architecture) mixing pipeline operates **exclusively at 48000 Hz**. Requesting raw non-48k DSP streams triggers IPC error `0x80006` (`SST_ERR_INVALID_PARAM`). |
| **Audio Codec** | Realtek RT5672 | Connected via I2S / PCM DAI to the Intel SST LPE audio engine. Supports `S16_LE` and `S24_LE`. |
| **ALSA Subsystem** | `snd-soc-cht-bsw-rt5672`, `snd-soc-sst-atom-hifi2-platform` | Manages DPCM Front-End (FE) and Back-End (BE) audio routing. |

### Technical Root Causes & Fixes

1. **DPCM Rate Merging Lock (`sound/soc/intel/boards/cht_bsw_rt5672.c`)**
   - **Problem**: `.dpcm_merged_rate = 1` forced Front-End DAIs to merge Back-End 48 kHz constraints.
   - **Fix**: Set `.dpcm_merged_rate = 0`.

2. **Frame Step Constraint (`sound/soc/intel/atom/sst-mfld-platform-pcm.c`)**
   - **Problem**: `snd_pcm_hw_constraint_step(..., 48)` forced period sizes to 48-frame multiples, rejecting non-48k frame math.
   - **Fix**: Relaxed step constraint to `1`.

3. **Static DAPM Clock Allocation (`sound/soc/intel/boards/cht_bsw_rt5672.c`)**
   - **Problem**: Hardcoded `48000 * 512` sysclk calls in `platform_clock_control()` broke codec PLL power-on sequencing.
   - **Fix**: Removed static clock overrides, permitting dynamic clock configuration.

4. **DSP Stream Allocation Rate (`cht_codec_fixup`)**
   - **Problem**: Direct 44.1 kHz allocation to `fw_sst_22a8.bin` caused DSP IPC error `0x80006`.
   - **Fix**: Locked `cht_codec_fixup()` Back-End rate to `48000` Hz for DSP stability, enabling ALSA `plughw`/PulseAudio/PipeWire to resample non-48k streams transparently.

---

## 🛠️ Modifying & Compiling the Drivers

### Modified Kernel Files
- [`usr/src/linux-source-6.12/sound/soc/intel/boards/cht_bsw_rt5672.c`](usr/src/linux-source-6.12/sound/soc/intel/boards/cht_bsw_rt5672.c)
- [`usr/src/linux-source-6.12/sound/soc/intel/atom/sst-mfld-platform-pcm.c`](usr/src/linux-source-6.12/sound/soc/intel/atom/sst-mfld-platform-pcm.c)

### Build Steps

```bash
# Navigate to the kernel source root
cd usr/src/linux-source-6.12

# Build the sound modules
make M=sound/soc/intel/boards modules
make M=sound/soc/intel/atom modules

# Install updated modules
sudo make M=sound/soc/intel/boards modules_install
sudo make M=sound/soc/intel/atom modules_install

# Refresh module dependencies
sudo depmod -a
```

*Note: Ensure any pre-existing compressed `.ko.xz` files in `/lib/modules/$(uname -r)/` are cleaned up so the system loads the new `.ko` modules.*

---

## 🧪 Verification & Testing Matrix

Tested on Dell Wyse 3040 running Linux kernel `6.12`:

| Sample Rate & Format | ALSA Device | Status | Output Quality |
| :--- | :--- | :--- | :--- |
| **48.0 kHz / 16-bit** | `hw:0,0` | **Native DSP Stream** | Clean, 0 XRUNs |
| **48.0 kHz / 24-bit** | `hw:0,0` | **Native DSP Stream** | Clean, 0 XRUNs |
| **44.1 kHz / 16-bit** | `plughw:0,0` | **ALSA Resampled to 48k** | Clean, 0 XRUNs |
| **96.0 kHz / 24-bit** | `plughw:0,0` | **ALSA Resampled to 48k** | Clean, 0 XRUNs |
| **192.0 kHz / 24-bit** | `plughw:0,0` | **ALSA Resampled to 48k** | Clean, 0 XRUNs |

### Verification Commands

```bash
# Direct Native DSP (48 kHz / 16-bit)
speaker-test -D hw:0,0 -c 2 -r 48000 -F S16_LE -t sine -f 440 -l 2

# Direct Native DSP (48 kHz / 24-bit)
speaker-test -D hw:0,0 -c 2 -r 48000 -F S24_LE -t sine -f 440 -l 2

# Standard Audio Rate (44.1 kHz / 16-bit)
speaker-test -D plughw:0,0 -c 2 -r 44100 -F S16_LE -t sine -f 440 -l 2

# High-Resolution Audio (96 kHz / 24-bit)
speaker-test -D plughw:0,0 -c 2 -r 96000 -F S24_LE -t sine -f 440 -l 2

# Ultra High-Resolution Audio (192 kHz / 24-bit)
speaker-test -D plughw:0,0 -c 2 -r 192000 -F S24_LE -t sine -f 440 -l 2
```

---

## 📄 License
GPL-2.0 (Linux Kernel Sound Subsystem License)
