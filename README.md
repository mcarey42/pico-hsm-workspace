# pico-hsm-workspace

Meta-repository for the Pico HSM project. Contains all source repositories as
git submodules so the full toolchain can be cloned and set up from a single place.

**Device:** Waveshare RP2350-One
**Firmware:** pico-hsm v6.4
**Target use:** Hardware Security Module + OpenBao auto-unseal

---

## Submodules

| Submodule | Remote | Purpose |
|-----------|--------|---------|
| [`pico-hsm`](pico-hsm/) | `git@github.com:mcarey42/pico-hsm.git` | Firmware source, build scripts, HSM management tool, runbooks |
| [`py-picohsm`](py-picohsm/) | `git@github.com:mcarey42/py-picohsm.git` | Python library for HSM communication (forked, patched) |
| [`pypicokey`](pypicokey/) | `git@github.com:mcarey42/pypicokey.git` | Low-level PCSC/USB transport (forked, patched) |
| [`pico-sdk`](pico-sdk/) | `https://github.com/raspberrypi/pico-sdk.git` | Raspberry Pi Pico SDK v2.2.0 |
| [`picotool`](picotool/) | `https://github.com/raspberrypi/picotool.git` | Firmware signing, OTP programming, flash tool |

> **pico-hsm** also contains `pico-keys-sdk` as its own nested submodule.
> Run `git submodule update --init --recursive` to pull it in.

---

## Quick Start

### 1. Clone the workspace

```bash
git clone git@github.com:mcarey42/pico-hsm-workspace.git ~/Projects/pico-hsm-workspace
cd ~/Projects/pico-hsm-workspace
git submodule update --init --recursive
# These are needed to talk to the device once provisioned.
sudo apt install pcscd pcsc-tools
# Needed to tell the build where the pick-sdk lives.
export PICO_SDK_PATH=~/Projects/pico-hsm-workspace/pico-sdk/
```

### 2. Build and install picotool

```bash
cd picotool
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install        # installs to /usr/local/bin/picotool
```

### 3. Set up the Python runtime environment

The `build-picohsm-venv.sh` script lives **alongside** this workspace in `~/Projects/`.
It clones the three Python packages and builds a self-contained venv.

```bash
cd ~/Projects
curl -O https://raw.githubusercontent.com/mcarey42/pico-hsm-workspace/main/build-picohsm-venv.sh
# or copy it from the workspace if already cloned
chmod +x build-picohsm-venv.sh
./build-picohsm-venv.sh
```

After the script completes:

```bash
source ~/Projects/picohsm-runtime/venv/bin/activate
alias hsm="python3 ~/Projects/pico-hsm/tools/pico-hsm-tool.py"
```

### 4. Generate the firmware signing key

> **The key must NOT be committed to any repository.**
> Store it at `~/Projects/ec_private_key.pem` — the build system reads it from there.

```bash
openssl ecparam -name secp256k1 -genkey -noout -out ~/Projects/ec_private_key.pem
chmod 600 ~/Projects/ec_private_key.pem
```

Then derive the `BOOTKEY` hash and update `pico-hsm/tools/pico-hsm-tool.py`:

```bash
python3 - <<'EOF'
from cryptography.hazmat.primitives.serialization import load_pem_private_key, Encoding, PublicFormat
import hashlib
with open('/home/mcarey/Projects/ec_private_key.pem', 'rb') as f:
    key = load_pem_private_key(f.read(), password=None)
raw = key.public_key().public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)
digest = hashlib.sha256(raw[1:]).digest()
print("BOOTKEY =", list(digest))
EOF
```

Edit `pico-hsm/tools/pico-hsm-tool.py` line ~60 and replace the `BOOTKEY = [...]` value.

> ⚠️ The key **must use the `secp256k1` curve** — the RP2350 boot ROM does not
> support P-256/prime256v1. Using the wrong curve produces a silent
> `Signature verification failed` at build time.

### 5. Build the firmware

```bash
cd pico-hsm
./build_pico_hsm.sh
```

Signed UF2 files are written to `pico-hsm/release/`.
OTP programming data is written to `pico-hsm/build_release/pico_hsm.otp.json`.

### 6. First-time device provisioning

Flash the signed firmware (hold BOOTSEL, plug in, device mounts as USB drive):

```bash
cp pico-hsm/release/pico_hsm_waveshare_rp2350_one-6.4.uf2 /media/$USER/RP2350/
```

Initialize the HSM (erases all keys, generates AES-256 unseal key at slot 1):

```bash
source ~/Projects/picohsm-runtime/venv/bin/activate
cd pico-hsm/tools
./hsm-setup.sh --so-pin <YOUR_SO_PIN> --pin 648219
```

---

## Documentation

All detailed documentation lives inside the submodules:

### Firmware & HSM operations
**`pico-hsm/tools/`**
| File | Contents |
|------|----------|
| [`SECURE-BOOT-RUNBOOK.md`](pico-hsm/tools/SECURE-BOOT-RUNBOOK.md) | Complete guide: key generation, build, sign, flash, OTP programming, locking, recovery |
| [`PICO-HSM-OPENBAO.md`](pico-hsm/tools/PICO-HSM-OPENBAO.md) | HSM operations reference + OpenBao auto-unseal setup |

**`pico-hsm/doc/`** — upstream pico-hsm documentation:
- [`usage.md`](pico-hsm/doc/usage.md) — General HSM usage
- [`sign-verify.md`](pico-hsm/doc/sign-verify.md) — Signing and verification
- [`aes.md`](pico-hsm/doc/aes.md) — AES cipher operations
- [`backup-and-restore.md`](pico-hsm/doc/backup-and-restore.md) — Key backup/restore

### Python libraries
- [`py-picohsm/README.md`](py-picohsm/README.md) — Python HSM library API
- [`pypicokey/README.md`](pypicokey/README.md) — Low-level transport layer

### SDK & toolchain
- [`pico-sdk`](pico-sdk/) — Raspberry Pi Pico SDK (see its own README)
- [`picotool`](picotool/) — Flash, sign, OTP tool (see its own README)

---

## Key File Locations (not in this repo)

| File | Location | Notes |
|------|----------|-------|
| Signing private key | `~/Projects/ec_private_key.pem` | secp256k1, chmod 600, **never commit** |
| OpenBao config | `~/openbao/config.hcl` | File storage, localhost:8200 |
| Encrypted unseal key | `~/openbao/unseal/unseal.enc` + `unseal.iv` | Decrypted by HSM slot 1 |
| Unseal script | `~/openbao/unseal/hsm-unseal.sh` | Run on every OpenBao restart |
| Python venv | `~/Projects/picohsm-runtime/venv/` | Built by `build-picohsm-venv.sh` |

---

## Notes on the forked Python packages

`py-picohsm` and `pypicokey` are forks with three bug fixes applied that are not
present in the upstream or PyPI versions. The `build-picohsm-venv.sh` script
installs from the local clones to ensure these fixes are always in effect.

See `pico-hsm/tools/PICO-HSM-OPENBAO.md` § *Keeping local packages current* for
the reinstall command if you ever need to reset the venv manually.

---

## .gitignore

The signing key is explicitly excluded:

```
ec_private_key.pem
ec_private_key.pem.enc
ec_key.iv
```
