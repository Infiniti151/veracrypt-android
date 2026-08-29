# veracrypt-android

[![Build](https://img.shields.io/github/actions/workflow/status/Infiniti151/veracrypt-android/build.yml?branch=main\&style=for-the-badge\&logo=github-actions\&logoColor=white\&label=Build)](https://github.com/Infiniti151/veracrypt-android/actions/workflows/build.yml) [![Android](https://img.shields.io/badge/Android-9%E2%80%9317-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/Infiniti151/veracrypt-android) [![License](https://img.shields.io/github/license/Infiniti151/veracrypt-android?style=for-the-badge&logo=spdx&logoColor=white&color=yellow&label=License)](https://github.com/Infiniti151/veracrypt-android/blob/main/LICENSE)

[VeraCrypt](https://github.com/veracrypt/VeraCrypt) is a tool for creating and accessing VeraCrypt-encrypted volumes and containers on Windows, Linux, and other Unix-like systems. This project provides VeraCrypt cross-compiled for Android ARM64 and packaged for [Termux](https://termux.dev/).

The package provides the VeraCrypt command-line utilities and uses the existing Termux FUSE 3 userspace tools provided by the `libfuse3` package.

It was created because VeraCrypt is not currently available as a package in the official Termux repositories. Although Termux provides cryptsetup with VeraCrypt (TrueCrypt) support, cryptsetup relies on the Linux `AF_ALG` kernel crypto API, which is generally disabled or heavily restricted on Android kernels (even though `dm-crypt` itself is present). This custom-compiled VeraCrypt bypasses that limitation by handling the cryptography entirely in userspace, allowing you to access VeraCrypt volumes on rooted Android devices.

This project provides a convenient way to install and update VeraCrypt through a dedicated APT repository for Termux.

> [!NOTE]
> This is an unofficial build of VeraCrypt for Termux/Android.
> VeraCrypt is a trademark of IDRIX. This project is not affiliated with or endorsed by IDRIX.

## 📋 Requirements

* Android device with an **ARM64 (`aarch64`)** CPU
* [Termux](https://termux.dev/)
* Root access
* A VeraCrypt-encrypted volume
* The appropriate VeraCrypt password, PIM, and/or keyfiles

## 📦 Installation

### 1. Install Termux

Install Termux from [F-Droid](https://f-droid.org/packages/com.termux/) or another official Termux distribution source.

> [!important]
> Do not mix Termux packages or add-ons from different distribution sources. Termux and its add-ons should come from the same source.

### 2. Update Termux packages

Open Termux and update the package repositories:

```bash
pkg update
pkg upgrade
```

### 3. Import the repository signing key

The repository is signed using an OpenPGP key published through the Ubuntu keyserver.

**Install `gnupg` (if not installed):**
```bash
pkg install gnupg
```

**Retrieve the public key using its full fingerprint:**

```bash
gpg --keyserver keyserver.ubuntu.com \
    --recv-keys 77E6A5281DF5538DB12A98F2B31498758A8AF8A5
```

**Verify that the imported key has the expected fingerprint:**

```bash
gpg --fingerprint 77E6A5281DF5538DB12A98F2B31498758A8AF8A5
```

***The fingerprint should be:***

```text
77E6 A528 1DF5 538D B12A 98F2 B314 9875 8A8A F8A5
```

> [!important]
> Verify the fingerprint before trusting the key. It should match the fingerprint published by the repository maintainer.

**Export the verified key as an APT keyring:**

```bash
mkdir -p "$PREFIX/etc/apt/keyrings"

gpg --export 77E6A5281DF5538DB12A98F2B31498758A8AF8A5 \
    > "$PREFIX/etc/apt/keyrings/veracrypt-android.gpg"
```

### 4. Add the veracrypt APT repository

**Add the repository to your Termux APT sources:**

```bash
echo "deb [signed-by=$PREFIX/etc/apt/keyrings/veracrypt-android.gpg] https://Infiniti151.github.io/veracrypt-android stable main" \
    > "$PREFIX/etc/apt/sources.list.d/veracrypt-android.list"
```

**Update the package lists:**

```bash
pkg update
```

### 5. Install `veracrypt`

**Install with:**

```bash
pkg install veracrypt
```

**Verify the installation:**

```bash
veracrypt --version
```

You should see the installed VeraCrypt version.

## 🔧 Usage

### Global vs. Termux-only access

On Android, mount namespaces determine which processes can see filesystems and FUSE mounts.

Choose the workflow based on where you intend to access the decrypted volume:

- **Termux-only:** Use `tsu` to enter a root shell configured for the Termux environment. Run the entire VeraCrypt workflow from that shell. The resulting mounts remain isolated from Android applications and file managers.

- **Global / Android access:** Use `gsu` to enter a root shell in the **global mount namespace**, then run the entire VeraCrypt workflow from that shell. This allows resulting mounts to be accessed by Android processes that share that namespace, including compatible root-capable file managers.

`tsu` and `gsu` serve different purposes:

- `tsu` — enters a Termux-configured root shell.
- `gsu` — enters a Termux-configured root shell in the global mount namespace.

Install `tsu` with:

```bash
pkg install tsu
````

`gsu` is a small helper function provided by this documentation:

```bash
gsu() {
    /system/bin/su -M -c \
        'export PATH=/data/data/com.termux/files/usr/bin:$PATH
         export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:$LD_LIBRARY_PATH
         exec /data/data/com.termux/files/usr/bin/bash'
}
```

Add this function to your shell configuration (for example, `~/.bashrc` or `~/.config/fish/config.fish`, depending on your shell) to make it available in future sessions.

> [!important]
> `gsu` is a convenience function provided by this documentation; it is not a standard Android or Termux command.

> [!note]
> The `-M` (`--mount-master`) option is provided by KernelSU and some other Android root solutions. It runs the shell in the global mount namespace, allowing mounts created from that shell to be visible to other processes that share that namespace.

> [!warning]
> Choose either `tsu` or `gsu` for the entire VeraCrypt workflow. Do not switch between them, as they use different mount namespaces. Use `gsu` when the decrypted volume needs to be accessible outside Termux, including from compatible Android file managers.

### 1. Identify the Encrypted Volume

First identify the block device containing the BitLocker volume with `lsblk` (requires `blk-utils` package).

For example:

```bash
gsu
lsblk
```

Depending on your Android device, storage may appear under paths such as:

```text
/dev/block/sd[a-z][1-9]...
```

**Do not assume a device path.** Verify the correct block device before proceeding.

### 2. Unlocking the Volume

> [!important]
> Do not mount directly via VeraCrypt. You should always map the volume without mounting it by using the `--filesystem=none` flag, and then mount the resulting decrypted block device manually. Letting VeraCrypt handle the filesystem mount natively will likely fail on Android for two reasons:
> - NTFS: VeraCrypt only looks for in-kernel NTFS drivers. It is unaware of the `ntfs-3g` package available in Termux, causing the mount operation to fail outright.
> - POSIX Filesystems (EXT4, F2FS): VeraCrypt does not mount Linux filesystems with Android's specific media permissions (UID/GID 1023). If VeraCrypt handles the mount, files created on a PC will be inaccessible or unreadable due to strict permission mismatching in the Android environment.

Use standard input to pass the password for automated unlocking without interactive prompts.

**Basic Unlocking (Password only):**
```bash
printf 'your_password' | veracrypt --text --non-interactive --stdin --filesystem=none /dev/block/sdX
```

**Advanced Unlocking (Password, PIM, and Keyfile):**
```bash
printf 'your_password' | veracrypt --text --non-interactive --stdin --filesystem=none --pim=123 --keyfiles=/path/to/key.file /dev/block/sdX
```

- `--text`: Forces command-line mode (required).
- `--non-interactive`: Prevents VeraCrypt from pausing to prompt for missing information.
- `--stdin`: Reads the volume password from standard input (safely piped via `printf` to avoid shell history logging).
- `--filesystem=none`: Unlocks and maps the volume via `dmsetup` but skips mounting the internal filesystem.
- `--pim=<value> / --keyfiles=<path>`: Specifies PIM and keyfiles.

### 3. Manual Mounting

Once unlocked, the decrypted block device will be available at `/dev/mapper/veracrypt1` (or whichever slot was assigned). You must mount it manually using Android's `media_rw` user/group ID (1023).

**For POSIX Filesystems (EXT4 / F2FS / EXT3):**

To ensure correct permissions for PC-transferred files, you must mount the raw partition to a staging directory first, and then overlay it with `bindfs` to virtualize the ownership to Android's media user:
```bash
# 1. Mount raw partition to a staging directory
mkdir -p /mnt/raw_otg/veracrypt1 /mnt/media_rw/veracrypt1
mount -t ext4 /dev/mapper/veracrypt1 /mnt/raw_otg/veracrypt1

# 2. Virtualize permissions with bindfs to your final mount point
bindfs -u 1023 -g 1023 --perms=a+rwX \
       --create-for-user=1023 --create-for-group=1023 \
       /mnt/raw_otg/veracrypt1 /mnt/media_rw/veracrypt1
```

**For NTFS Filesystems:**

Use either the newer kernel `ntfs3` driver or Termux's `ntfs-3g` userspace driver:
```bash
# Using ntfs3 (if supported by kernel)
mount -t ntfs3 -o uid=1023,gid=1023,fmask=000,dmask=000 /dev/mapper/veracrypt1 /mnt/media_rw/veracrypt1

# OR using Termux ntfs-3g
ntfs-3g /dev/mapper/veracrypt1 /mnt/media_rw/veracrypt1 -o uid=1023,gid=1023,fmask=000,dmask=000
```

**For FAT32 / exFAT:**
```bash
mount -t exfat -o uid=1023,gid=1023,fmask=000,dmask=000 /dev/mapper/veracrypt1 /mnt/media_rw/veracrypt1
```

### 5. Accessing the mounted volume

If the filesystem was mounted with `gsu`, the mount is placed in the global mount namespace and can be accessed by Android processes that share that namespace.

This allows the mounted folder to be accessed using compatible root-capable file managers such as Solid Explorer and File Manager+.

If you mounted the filesystem using `tsu`, it is intended for **Termux-only access**.

### 6. Dismounting and Cleanup

> [!note]
> Unmount the filesystem from the same mount namespace in which it was mounted. Use `gsu` for filesystems mounted with `gsu`, and `tsu` for filesystems mounted with `tsu`.

To safely close the volume, you must reverse the mounting process in the exact opposite order. You must unmount the filesystems first before instructing VeraCrypt to lock the mapped volume.

**Unmount the final mount point:**

Release the primary mount point where the files are accessible:
```bash
umount /mnt/media_rw/veracrypt1
```

**Unmount the raw staging directory (POSIX / bindfs only):**

If you used `bindfs` for a POSIX filesystem (EXT4/F2FS), you must also unmount the underlying raw partition:
```bash
umount /mnt/raw_otg/veracrypt1
```

**Lock and unmap the volume:**

Instruct VeraCrypt to lock the encrypted volume and remove the `/dev/mapper/veracrypt1` device map:
```bash
veracrypt --text --dismount
```

**Clean up directories (Optional):**

Remove the empty mount points to keep your system directories clean:
```bash
rmdir /mnt/media_rw/veracrypt1
rmdir /mnt/raw_otg/veracrypt1
```

## 🤖 Android / Termux considerations

### Root access

VeraCrypt requires root access to read Android block devices. Use `tsu` for a Termux-only workflow or `gsu` when the decrypted volume needs to be accessible outside Termux.

### Storage permissions

Android's normal storage permissions are separate from Linux root permissions.

For access to shared storage, Termux may need storage permission:

```bash
termux-setup-storage
```

This creates:

```text
$HOME/storage/
```

with links to accessible Android shared-storage locations.

For block devices, however, root permissions are normally required.

## 🔄 Update

**Update all Termux packages:**

```bash
pkg update
pkg upgrade
```

or:

**Upgrade `veracrypt`:**

```bash
pkg upgrade veracrypt
```

## 🗑️ Uninstallation

**Uninstall `veracrypt`:**

```bash
pkg uninstall veracrypt
```

**Remove the repository:**

```bash
rm "$PREFIX/etc/apt/sources.list.d/veracrypt-android.list"
```

**Remove the repository signing key:**

```bash
rm "$PREFIX/etc/apt/keyrings/veracrypt-android.gpg"
```

**Update**:

```bash
pkg update
```

## 🏗️ Building

This repository builds VeraCrypt for Android ARM64 using the Android NDK.

The build script:

1. Downloads and sets up the Android NDK.
2. Builds wxWidgets for Android ARM64 using the Android NDK.
3. Builds VeraCrypt for Android ARM64 using the Android NDK, linking against the locally built wxWidgets and Termux's `libfuse3` and `libpcsclite`.
4. Packages the resulting binaries and libraries into a Termux-compatible `.deb`.
5. Generates an APT repository.
6. Generates `Packages` and `Packages.gz`.
7. Generates and signs the `Release` metadata.
8. Generates a signed `InRelease`.

GitHub Actions runs the build script and publishes the generated APT repository using GitHub Pages.

The resulting repository is structured as:

```text
apt-repo/
├── dists/
│   └── stable/
│       ├── InRelease
│       ├── Release
│       ├── Release.gpg
│       └── main/
│           └── binary-aarch64/
│               ├── Packages
│               └── Packages.gz
└── pool/
    └── main/
        └── v/
            └── veracrypt/
                └── veracrypt_*.deb
```

### Local build

Local builds use the same containerized build environment as CI, but disable
APT repository generation and signing.

**Requirements:**

- [Podman](https://podman.io/) — runs the containerized build environment.
- [Task](https://taskfile.dev/) — provides the commands defined in `Taskfile.yml`.

For the first build, rebuild the container image and VeraCrypt:

```bash
task rebuild
```
Available tasks:

| Task | Description |
| --- | --- |
| `task build` | Build VeraCrypt using the existing builder image |
| `task image` | Build the local builder image |
| `task rebuild` | Rebuild the builder image and VeraCrypt |
| `task clean` | Remove local build output, sources, and cache |

Run `task --list` to see all available tasks.

## 📚 Source

This project packages [VeraCrypt](https://github.com/veracrypt/VeraCrypt) for Android ARM64.

Original VeraCrypt project:

https://github.com/veracrypt/VeraCrypt

## 📄 License

See the original [VeraCrypt](https://github.com/veracrypt/VeraCrypt) project for its licensing information.

The Android build and packaging files in this repository are provided separately from the upstream VeraCrypt source.

