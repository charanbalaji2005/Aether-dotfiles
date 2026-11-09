"""Builders for fake sysfs/procfs trees + canned command output.

Each scenario writes the handful of files the detection code actually
reads, modelled on real Fedora machines (uevent formats, hwmon layout,
lspci -vmm output, mokutil wording). They let the hardware-detection logic
be tested for machines this repository can't physically be tested on —
they are NOT a substitute for running `aether graphics verify` on real
hardware, and the test report says so.
"""

from __future__ import annotations

import os
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "lib"))

from aether.util import Context, fixture_encode  # noqa: E402

FEDORA_41 = 'NAME="Fedora Linux"\nVERSION_ID=41\nID=fedora\nPRETTY_NAME="Fedora Linux 41 (Workstation Edition)"\n'
UBUNTU = 'NAME="Ubuntu"\nVERSION_ID="24.04"\nID=ubuntu\nID_LIKE=debian\nPRETTY_NAME="Ubuntu 24.04 LTS"\n'
KERNEL = "6.11.7-300.fc41.x86_64"
SB_VAR = "sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"


def cpuinfo(vendor: str, model: str, cores: int, threads: int, flags: str) -> str:
    blocks = []
    per_core = threads // cores
    for t in range(threads):
        blocks.append(
            "processor\t: %d\nvendor_id\t: %s\ncpu family\t: 6\nmodel name\t: %s\n"
            "physical id\t: 0\ncore id\t\t: %d\ncpu MHz\t\t: 2400.000\nflags\t\t: fpu sse4_2 avx avx2 %s\n"
            % (t, vendor, model, t // per_core, flags)
        )
    return "\n".join(blocks) + "\n"


class Scenario:
    def __init__(self):
        self.dir = tempfile.TemporaryDirectory(prefix="aether-fixture-")
        self.root = self.dir.name
        self.commands = {}
        self.bins = {"rpm", "lspci", "modinfo", "mokutil", "systemctl", "dnf", "uname", "ldconfig", "systemd-detect-virt"}

    # -- tree helpers ------------------------------------------------------
    def file(self, path: str, content) -> "Scenario":
        full = os.path.join(self.root, fixture_encode(path.lstrip("/")))
        os.makedirs(os.path.dirname(full), exist_ok=True)
        mode = "wb" if isinstance(content, bytes) else "w"
        with open(full, mode) as fh:
            fh.write(content)
        return self

    def dir_(self, path: str) -> "Scenario":
        os.makedirs(os.path.join(self.root, fixture_encode(path.lstrip("/"))), exist_ok=True)
        return self

    def cmd(self, argv: str, out: str = "", rc: int = 0, err: str = "") -> "Scenario":
        self.commands[argv] = {"out": out, "rc": rc, "err": err}
        return self

    def ctx(self, env=None) -> Context:
        return Context(sysroot=self.root, command_fixtures=self.commands, fixture_bins=self.bins, env=env or {})

    def cleanup(self) -> None:
        self.dir.cleanup()

    # -- building blocks ---------------------------------------------------
    def base(self, os_release: str = FEDORA_41, kernel: str = KERNEL) -> "Scenario":
        self.file("/etc/os-release", os_release)
        self.file("/proc/sys/kernel/osrelease", kernel + "\n")
        self.file("/proc/uptime", "12345.67 40000.00\n")
        self.file("/proc/loadavg", "0.52 0.48 0.40 1/900 4242\n")
        self.file(
            "/proc/meminfo",
            "MemTotal:       32768000 kB\nMemFree:         8000000 kB\nMemAvailable:   20000000 kB\n"
            "SwapTotal:       8388604 kB\nSwapFree:        8000000 kB\n",
        )
        self.file("/proc/stat", "cpu  1000 0 500 8000 100 0 0 0 0 0\ncpu0 500 0 250 4000 50 0 0 0 0 0\ncpu1 500 0 250 4000 50 0 0 0 0 0\n")
        self.file("/proc/net/dev",
                  "Inter-|   Receive  |  Transmit\n face |bytes packets errs drop fifo frame compressed multicast|bytes\n"
                  "    lo: 1000 10 0 0 0 0 0 0 1000 10 0 0 0 0 0 0\n"
                  "wlp2s0: 500000 400 0 0 0 0 0 0 100000 300 0 0 0 0 0 0\n")
        self.file("/proc/net/route", "Iface\tDestination\tGateway\nwlp2s0\t00000000\t0101A8C0\n")
        self.cmd("systemd-detect-virt", "none\n")
        return self

    def intel_cpu(self) -> "Scenario":
        self.file("/proc/cpuinfo", cpuinfo("GenuineIntel", "12th Gen Intel(R) Core(TM) i7-12700H", 4, 8, "vmx"))
        for i in range(2):
            c = "/sys/devices/system/cpu/cpu%d/cpufreq/" % i
            self.file(c + "scaling_cur_freq", "2400000\n").file(c + "cpuinfo_max_freq", "4700000\n").file(c + "cpuinfo_min_freq", "400000\n")
            self.file(c + "scaling_driver", "intel_pstate\n").file(c + "scaling_governor", "powersave\n")
            self.file(c + "energy_performance_preference", "balance_performance\n")
        self.file("/sys/devices/system/cpu/intel_pstate/no_turbo", "0\n")
        hw = "/sys/class/hwmon/hwmon3/"
        self.file(hw + "name", "coretemp\n").file(hw + "temp1_label", "Package id 0\n").file(hw + "temp1_input", "48000\n")
        self.file(hw + "temp2_label", "Core 0\n").file(hw + "temp2_input", "45000\n")
        self.file("/dev/kvm", "")
        return self

    def amd_cpu(self) -> "Scenario":
        self.file("/proc/cpuinfo", cpuinfo("AuthenticAMD", "AMD Ryzen 7 7800X3D 8-Core Processor", 8, 16, "svm"))
        c = "/sys/devices/system/cpu/cpu0/cpufreq/"
        self.file(c + "scaling_driver", "amd-pstate-epp\n").file(c + "scaling_governor", "powersave\n").file(c + "scaling_cur_freq", "4200000\n")
        self.file("/sys/devices/system/cpu/cpufreq/boost", "1\n")
        hw = "/sys/class/hwmon/hwmon1/"
        self.file(hw + "name", "k10temp\n").file(hw + "temp1_label", "Tctl\n").file(hw + "temp1_input", "61250\n")
        return self

    def gpu(self, slot, vendor_id, device_id, driver, name, boot_vga=True, runtime=None, cls="30000", card="card0", render="renderD128", hwmon=None, extra=None) -> "Scenario":
        dev = "/sys/bus/pci/devices/%s/" % slot
        uevent = "PCI_CLASS=%s\nPCI_ID=%s:%s\nPCI_SLOT_NAME=%s\n" % (cls, vendor_id.upper(), device_id.upper(), slot)
        if driver:
            uevent = "DRIVER=%s\n" % driver + uevent
        self.file(dev + "uevent", uevent)
        self.file(dev + "boot_vga", "1\n" if boot_vga else "0\n")
        if runtime:
            self.file(dev + "power/runtime_status", runtime + "\n")
        if driver:
            self.dir_(dev + "drm/" + card).dir_(dev + "drm/" + render)
        if hwmon:
            for k, v in hwmon.items():
                self.file(dev + "hwmon/hwmon5/" + k, v)
        for k, v in (extra or {}).items():
            self.file(dev + k, v)
        self.cmd("lspci -vmm -s %s" % slot, "Slot:\t%s\nClass:\tVGA compatible controller\nDevice:\t%s\n" % (slot[5:], name))
        return self

    def secure_boot(self, enabled: bool) -> "Scenario":
        self.dir_("/sys/firmware/efi")
        self.file(SB_VAR, bytes([6, 0, 0, 0, 1 if enabled else 0]))
        self.cmd("mokutil --sb-state", "SecureBoot %s\n" % ("enabled" if enabled else "disabled"))
        return self

    def rpm(self, installed: dict) -> "Scenario":
        for pkg in ("akmod-nvidia", "akmod-nvidia-580xx", "akmod-nvidia-470xx", "xorg-x11-drv-nvidia",
                    "xorg-x11-drv-nvidia-cuda", "xorg-x11-drv-nvidia-power", "libva-nvidia-driver", "nvidia-vaapi-driver",
                    "mesa-dri-drivers"):
            if pkg in installed:
                self.cmd("rpm -q --qf %%{VERSION}-%%{RELEASE} %s" % pkg, installed[pkg])
                if pkg == "mesa-dri-drivers":
                    self.cmd("rpm -q --qf %{VERSION} mesa-dri-drivers", installed[pkg].split("-")[0])
            else:
                self.cmd("rpm -q --qf %%{VERSION}-%%{RELEASE} %s" % pkg, "package %s is not installed\n" % pkg, rc=1)
        return self


def nvidia_desktop() -> Scenario:
    s = Scenario().base().intel_cpu().secure_boot(True)
    s.gpu("0000:01:00.0", "10de", "2484", "nvidia", "GA104 [GeForce RTX 3070]")
    s.file("/sys/module/nvidia/version", "565.77\n")
    s.file("/sys/module/nvidia_drm/parameters/modeset", "Y\n").file("/sys/module/nvidia_drm/parameters/fbdev", "Y\n")
    s.file("/proc/driver/nvidia/params", "ResmanDebugLevel: 4294967295\nPreserveVideoMemoryAllocations: 1\n")
    s.file("/usr/lib64/gbm/nvidia-drm_gbm.so", "")
    s.file("/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json", '{"ICD": {"library_path": "libGLX_nvidia.so.0"}}')
    s.file("/etc/pki/akmods/certs/public_key.der", "")
    s.rpm({"akmod-nvidia": "565.77-1.fc41", "xorg-x11-drv-nvidia": "565.77-1.fc41", "xorg-x11-drv-nvidia-cuda": "565.77-1.fc41"})
    s.cmd("modinfo -F version nvidia", "565.77\n").cmd("modinfo -F signer nvidia", "akmods local key\n")
    s.cmd("mokutil --test-key /etc/pki/akmods/certs/public_key.der", "/etc/pki/akmods/certs/public_key.der is already enrolled\n")
    s.cmd("systemctl is-enabled nvidia-suspend.service", "enabled\n").cmd("systemctl is-active nvidia-suspend.service", "inactive\n", rc=3)
    s.cmd("systemctl is-enabled nvidia-persistenced.service", "disabled\n", rc=1).cmd("systemctl is-active nvidia-persistenced.service", "inactive\n", rc=3)
    s.cmd("ldconfig -p", "\tlibcuda.so.1 (libc6,x86-64) => /usr/lib64/libcuda.so.1\n")
    s.bins |= {"nvidia-smi", "hyprctl"}
    s.cmd("hyprctl version -j", '{"branch": "", "tag": "v0.46.2"}')
    return s


def amd_desktop() -> Scenario:
    s = Scenario().base().amd_cpu().secure_boot(False)
    s.gpu("0000:03:00.0", "1002", "73df", "amdgpu", "Navi 22 [Radeon RX 6700/6700 XT/6750 XT / 6800M/6850M XT]",
          hwmon={"name": "amdgpu\n", "temp1_input": "52000\n", "power1_average": "35000000\n"},
          extra={"gpu_busy_percent": "37\n", "mem_info_vram_used": "1073741824\n", "mem_info_vram_total": "12884901888\n"})
    s.file("/usr/share/vulkan/icd.d/radeon_icd.x86_64.json", '{"ICD": {"library_path": "/usr/lib64/libvulkan_radeon.so"}}')
    s.file("/usr/lib64/dri/radeonsi_drv_video.so", "")
    s.rpm({"mesa-dri-drivers": "24.2.7-1.fc41"})
    s.bins |= {"vainfo"}
    s.cmd("vainfo --display drm --device /dev/dri/renderD128",
          "vainfo: Driver version: Mesa Gallium driver 24.2.7 for AMD Radeon RX 6700 XT (radeonsi, navi22)\n"
          "vainfo: Supported profile and entrypoints\n"
          "      VAProfileMPEG2Main              : VAEntrypointVLD\n"
          "      VAProfileVP9Profile0            : VAEntrypointVLD\n"
          "      VAProfileAV1Profile0            : VAEntrypointVLD\n"
          "      VAProfileJPEGBaseline           : VAEntrypointVLD\n")
    return s


def intel_laptop() -> Scenario:
    s = Scenario().base().intel_cpu().secure_boot(True)
    s.gpu("0000:00:02.0", "8086", "46a6", "i915", "Alder Lake-P GT2 [Iris Xe Graphics]")
    s.file("/sys/class/drm/card0/gt_cur_freq_mhz", "350\n")
    s.file("/usr/share/vulkan/icd.d/intel_icd.x86_64.json", '{"ICD": {"library_path": "/usr/lib64/libvulkan_intel.so"}}')
    s.file("/sys/class/power_supply/BAT0/type", "Battery\n").file("/sys/class/power_supply/BAT0/capacity", "81\n")
    s.file("/sys/class/power_supply/BAT0/status", "Discharging\n")
    s.file("/sys/class/power_supply/BAT0/energy_full", "50000000\n").file("/sys/class/power_supply/BAT0/energy_full_design", "57000000\n")
    return s


def hybrid_laptop() -> Scenario:
    s = Scenario().base().intel_cpu().secure_boot(True)
    s.gpu("0000:00:02.0", "8086", "9bc4", "i915", "CometLake-H GT2 [UHD Graphics]", runtime="active")
    s.gpu("0000:01:00.0", "10de", "1f99", "nvidia", "TU117M [GeForce GTX 1650 Mobile / Max-Q]", boot_vga=False,
          runtime="suspended", card="card1", render="renderD129")
    s.file("/sys/module/nvidia/version", "565.77\n")
    s.file("/sys/module/nvidia_drm/parameters/modeset", "Y\n")
    s.rpm({"akmod-nvidia": "565.77-1.fc41"})
    s.cmd("modinfo -F version nvidia", "565.77\n")
    s.bins |= {"nvidia-smi"}
    return s


def nvidia_no_driver(arch_name: str = "GP106 [GeForce GTX 1060 6GB]", device: str = "1c03") -> Scenario:
    """NVIDIA card on nouveau, RPM Fusion not enabled, Secure Boot on, no key yet."""
    s = Scenario().base().amd_cpu().secure_boot(True)
    s.gpu("0000:01:00.0", "10de", device, "nouveau", arch_name)
    s.dir_("/sys/module/nouveau")
    s.rpm({})
    s.cmd("modinfo -F version nvidia", "", rc=1, err="modinfo: ERROR: Module nvidia not found.\n")
    s.cmd("dnf repolist --enabled", "repo id                 repo name\nfedora                  Fedora 41 - x86_64\nupdates                 Fedora 41 - x86_64 - Updates\n")
    s.cmd("dnf -q list --available akmod-nvidia-580xx", "", rc=1, err="No matching packages to list\n")
    s.cmd("rpm -q kernel-core --qf %{VERSION}-%{RELEASE}.%{ARCH}\\n", "6.11.7-300.fc41.x86_64\n")
    s.cmd("mokutil --test-key /etc/pki/akmods/certs/public_key.der", "", rc=1)
    return s


def empty_system() -> Scenario:
    """No /sys, no /proc, no tools: everything must degrade to 'unavailable'."""
    s = Scenario()
    s.bins = set()
    return s
