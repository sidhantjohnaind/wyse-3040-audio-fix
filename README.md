# Dell Wyse 3040 Linux Audio Kernel Driver & Patches
### Unlocking Multi-Rate Audio (44.1 kHz, 88.2 kHz, 96 kHz, 192 kHz) on Intel Cherry Trail (`cht_bsw_rt5672`)

---

## 📌 Project Overview
The **Dell Wyse 3040** thin client features an Intel Cherry Trail SoC paired with a Realtek RT5672 audio codec and Intel SST LPE (Low Power Engine) Audio DSP. By default in Linux mainline kernels (e.g. 6.x), audio playback is often restricted or locked to 48 kHz due to DPCM rate merging locks, static clock constraints, and DSP firmware boundaries.

This repository provides kernel patches, pre-compiled kernel module binaries (`.ko`), Debian kernel configuration files, and technical documentation to enable full audio playback support across **44.1 kHz, 48 kHz, 88.2 kHz, 96 kHz, and 192 kHz** formats at **16-bit** and **24-bit** depth using ALSA, PulseAudio, and PipeWire sound servers.

---

## 🔬 Hardware Limitations & Technical Deep-Dive

> [!NOTE]
> **Why Native 44.1 kHz Hardware Bit-Perfect Output Is Physically Unsupported**
> 
> A common question is why raw 44.1 kHz cannot be passed directly to the physical hardware without resampling. The limitation is driven by physical motherboard crystal oscillators and Intel SoC DSP firmware eFuse constraints:

### 1. Master Clock (MCLK) & Crystal Oscillator Grid
- **48 kHz Clock Grid**: The master crystal oscillator / PLL clock generator on the Dell Wyse 3040 motherboard supplies a **24.576 MHz** master clock (`48000 Hz × 512 = 24.576 MHz`).
- **Missing 22.5792 MHz Crystal**: Native bit-perfect 44.1 kHz playback requires a **22.5792 MHz** master clock grid (`44100 Hz × 512 = 22.5792 MHz`). The Wyse 3040 PCB lacks a dedicated 22.5792 MHz crystal oscillator for 44.1k multiples.

### 2. Intel SST DSP Firmware & SoC eFuse Limits
- **Firmware Blob (`intel/fw_sst_22a8.bin`)**: The Intel Cherry Trail SST LPE DSP binary firmware blob internal Smart Bus Architecture (SBA) mixing pipeline is hardcoded and fused to operate **exclusively at 48000 Hz**.
- **Hardware eFuse Constraints**: Internal SoC ROM / eFuse tables lock the DSP processing pipeline. Sending an IPC stream allocation request for raw 44.1 kHz to `fw_sst_22a8.bin` causes the firmware to reject the request with IPC error `0x80006` (`SST_ERR_INVALID_PARAM`).

### 3. The Resampling Solution
Because raw 44.1 kHz DSP stream allocation is physically rejected by hardware/firmware, our kernel patches configure ALSA (`plughw:0,0`), PulseAudio, and PipeWire to automatically accept **44.1 kHz, 88.2 kHz, 96 kHz, and 192 kHz** inputs at 16/24-bit and perform high-quality software resampling to 48 kHz before passing data to the DSP.

---

## 🛠️ Building From Source

### Prerequisites
On Debian / Ubuntu / Linux Mint systems, install standard kernel build utilities and build headers:
```bash
sudo apt update
sudo apt install build-essential linux-headers-$(uname -r) git bc flex bison libssl-dev libelf-dev
```

### Step 1: Clone the Repository
```bash
git clone https://github.com/sidhantjohnaind/wyse-3040-audio-fix.git
cd wyse-3040-audio-fix
```

### Step 2: Build the Sound Driver Modules
Compile the driver modules against your active kernel headers:
```bash
# Navigate to the kernel source directory
cd usr/src/linux-source-6.12

# Build the machine driver module (cht_bsw_rt5672)
make -C /lib/modules/$(uname -r)/build M=$PWD/sound/soc/intel/boards modules

# Build the platform driver module (sst-atom-hifi2-platform)
make -C /lib/modules/$(uname -r)/build M=$PWD/sound/soc/intel/atom modules
```

### Step 3: Install the Modules & Update Dependencies
```bash
# Install the compiled modules
sudo make -C /lib/modules/$(uname -r)/build M=$PWD/sound/soc/intel/boards modules_install
sudo make -C /lib/modules/$(uname -r)/build M=$PWD/sound/soc/intel/atom modules_install

# Clean up compressed module overrides (.ko.xz) if present
sudo rm -f /lib/modules/$(uname -r)/kernel/sound/soc/intel/boards/*.ko.xz
sudo rm -f /lib/modules/$(uname -r)/kernel/sound/soc/intel/atom/*.ko.xz

# Refresh module dependency maps
sudo depmod -a
```

### Step 4: Reload Driver Modules (or Reboot)
```bash
# Unload old drivers
sudo modprobe -r snd_soc_sst_cht_bsw_rt5672 snd_soc_sst_atom_hifi2_platform

# Load updated drivers
sudo modprobe snd_soc_sst_atom_hifi2_platform
sudo modprobe snd_soc_sst_cht_bsw_rt5672
```

---

## 📦 Quick Install via Pre-Compiled Binaries

If you are running Linux Kernel `6.12.100+deb13-amd64` (or compatible 6.12.x kernels), you can skip building and install the pre-compiled `.ko` module binaries directly:

- **Debian Kernel Config**: [`wyse-6.12.100.config`](wyse-6.12.100.config)
- **Pre-Compiled Driver Modules**:
  1. [`snd-soc-sst-cht-bsw-rt5672.ko`](usr/src/linux-source-6.12/sound/soc/intel/boards/snd-soc-sst-cht-bsw-rt5672.ko) (Machine Driver)
  2. [`snd-soc-sst-atom-hifi2-platform.ko`](usr/src/linux-source-6.12/sound/soc/intel/atom/snd-soc-sst-atom-hifi2-platform.ko) (Platform Driver)

```bash
# Copy pre-compiled modules
sudo cp usr/src/linux-source-6.12/sound/soc/intel/boards/snd-soc-sst-cht-bsw-rt5672.ko /lib/modules/$(uname -r)/kernel/sound/soc/intel/boards/
sudo cp usr/src/linux-source-6.12/sound/soc/intel/atom/snd-soc-sst-atom-hifi2-platform.ko /lib/modules/$(uname -r)/kernel/sound/soc/intel/atom/

# Remove conflicting compressed modules if present
sudo rm -f /lib/modules/$(uname -r)/kernel/sound/soc/intel/boards/*.ko.xz
sudo rm -f /lib/modules/$(uname -r)/kernel/sound/soc/intel/atom/*.ko.xz

# Update depmod
sudo depmod -a
```

---

## 🔬 Technical Root Causes & Kernel Fixes

| Issue | File Location | Root Cause | Solution |
| :--- | :--- | :--- | :--- |
| **DPCM Rate Merging Lock** | [`usr/src/linux-source-6.12/sound/soc/intel/boards/cht_bsw_rt5672.c`](usr/src/linux-source-6.12/sound/soc/intel/boards/cht_bsw_rt5672.c) | `.dpcm_merged_rate = 1` forced Front-End DAIs to merge Back-End rate constraints. | Set `.dpcm_merged_rate = 0`. |
| **Frame Step Constraint** | [`usr/src/linux-source-6.12/sound/soc/intel/atom/sst-mfld-platform-pcm.c`](usr/src/linux-source-6.12/sound/soc/intel/atom/sst-mfld-platform-pcm.c) | `snd_pcm_hw_constraint_step(..., 48)` rejected non-48k frame periods. | Relaxed step constraint to `1`. |
| **Static DAPM Clock** | [`usr/src/linux-source-6.12/sound/soc/intel/boards/cht_bsw_rt5672.c`](usr/src/linux-source-6.12/sound/soc/intel/boards/cht_bsw_rt5672.c) | Hardcoded `48000 * 512` sysclk broke codec PLL setup when DAPM clock widget powered on. | Removed static PLL/sysclk calls from `platform_clock_control()`. |
| **SST DSP Stream Allocation** | [`usr/src/linux-source-6.12/sound/soc/intel/boards/cht_bsw_rt5672.c`](usr/src/linux-source-6.12/sound/soc/intel/boards/cht_bsw_rt5672.c) | Forcing raw 44.1k to `fw_sst_22a8.bin` caused IPC error `0x80006`. | Fixed `cht_codec_fixup()` rate to `48000` Hz for DSP stability. |

---

## 🧪 Verification & Testing Matrix

Tested on Dell Wyse 3040 running Linux kernel `6.12.100+deb13-amd64`:

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
