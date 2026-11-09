"""GPU enumeration from PCI sysfs.

Every display-class PCI function (PCI base class 0x03) is reported with its
vendor, model, kernel driver, DRM nodes, boot-VGA flag and runtime power
state. The ``uevent`` file is the primary source because it carries DRIVER,
PCI_CLASS and PCI_ID in one read; the individual ``class``/``vendor``/
``device`` files are used as a fallback.

Model names come from ``lspci`` when available, then from the hwdata
``pci.ids`` database (Fedora: package ``hwdata``), and finally fall back to
the raw vendor:device ID — nothing is guessed.
"""

from __future__ import annotations

import re
from typing import Dict, List, Optional, Tuple

from ..util import Context

VENDORS = {
    "10de": "nvidia",
    "1002": "amd",
    "1022": "amd",
    "8086": "intel",
    "1af4": "virtio",
    "15ad": "vmware",
    "1234": "qemu",
    "1b36": "qxl",
    "80ee": "virtualbox",
    "1414": "microsoft",
    "1a03": "aspeed",
    "102b": "matrox",
}

VENDOR_LABELS = {
    "nvidia": "NVIDIA",
    "amd": "AMD",
    "intel": "Intel",
    "virtio": "VirtIO (virtual)",
    "vmware": "VMware (virtual)",
    "qemu": "QEMU (virtual)",
    "qxl": "QXL (virtual)",
    "virtualbox": "VirtualBox (virtual)",
    "microsoft": "Hyper-V (virtual)",
    "aspeed": "ASPEED (server BMC)",
    "matrox": "Matrox",
}

_PCI_IDS_PATHS = ("/usr/share/hwdata/pci.ids", "/usr/share/misc/pci.ids", "/usr/share/pci.ids")

# AMD APU code names as they appear in pci.ids device names. Used only to
# classify integrated vs. discrete when nothing better is available.
_AMD_APU_HINTS = (
    "renoir", "cezanne", "lucienne", "barcelo", "rembrandt", "phoenix", "hawk point",
    "raphael", "granite ridge", "strix", "krackan", "mendocino", "van gogh", "picasso",
    "raven", "dali", "pollock", "kaveri", "carrizo", "stoney", "radeon graphics",
    "radeon vega mobile", "radeon 610m", "radeon 680m", "radeon 760m", "radeon 780m",
    "radeon 880m", "radeon 890m",
)


class GPU(dict):
    """A detected GPU. Plain dict so it serialises straight to JSON."""

    @property
    def slot(self) -> str:
        return self["slot"]

    @property
    def vendor(self) -> str:
        return self["vendor"]


def _parse_uevent(text: str) -> Dict[str, str]:
    out = {}
    for line in text.splitlines():
        k, sep, v = line.partition("=")
        if sep:
            out[k.strip()] = v.strip()
    return out


def _class_code(raw: Optional[str]) -> Optional[int]:
    if not raw:
        return None
    try:
        return int(raw, 16)
    except ValueError:
        return None


def _lookup_pci_ids(ctx: Context, vendor_id: str, device_id: str) -> Tuple[Optional[str], Optional[str]]:
    vendor_id = vendor_id.lower()
    device_id = device_id.lower()
    for path in _PCI_IDS_PATHS:
        text = ctx.read(path)
        if not text:
            continue
        vendor_name = None
        in_vendor = False
        for line in text.splitlines():
            if not line or line.startswith("#"):
                continue
            if not line.startswith("\t"):
                if in_vendor:
                    break  # left our vendor block without finding the device
                if line[:4].lower() == vendor_id:
                    in_vendor = True
                    vendor_name = line[4:].strip()
                continue
            if in_vendor and not line.startswith("\t\t") and line[1:5].lower() == device_id:
                return vendor_name, line[5:].strip()
        if vendor_name:
            return vendor_name, None
    return None, None


def _lspci_name(ctx: Context, slot: str) -> Optional[str]:
    res = ctx.run(["lspci", "-vmm", "-s", slot], timeout=5)
    if not res.ok:
        return None
    for line in res.out.splitlines():
        if line.startswith("Device:"):
            return line.split(":", 1)[1].strip()
    return None


def _classify(vendor: str, name: str, boot_vga: bool, multi_gpu: bool) -> str:
    """'integrated', 'discrete', 'virtual' or 'unknown'."""
    lname = name.lower()
    if vendor in ("virtio", "vmware", "qemu", "qxl", "virtualbox", "microsoft"):
        return "virtual"
    if vendor == "nvidia":
        return "integrated" if "tegra" in lname else "discrete"
    if vendor == "intel":
        if re.search(r"\barc\b|dg1|dg2|battlemage|alchemist", lname):
            return "discrete"
        return "integrated"
    if vendor == "amd":
        if any(h in lname for h in _AMD_APU_HINTS) and not re.search(r"\brx\b|radeon pro|instinct|firepro", lname):
            return "integrated"
        if re.search(r"\brx\b|radeon pro|navi|vega 56|vega 64|polaris|ellesmere|instinct|firepro", lname):
            return "discrete"
        # An AMD GPU that is not the boot device next to another GPU is
        # almost always a dGPU; on a single-GPU machine we can't tell.
        if multi_gpu and not boot_vga:
            return "discrete"
        return "unknown"
    return "unknown"


def nvidia_codename(name: Optional[str]) -> Optional[str]:
    """Chip code name from a pci.ids/lspci device string, e.g. 'GA104'."""
    if not name:
        return None
    # pci.ids appends variant suffixes: TU117M (mobile), GA104GL (workstation),
    # GP107GLM, GK208B. The generation lives in the base name, which we return.
    m = re.search(r"\b(G[FKMPV]\d{3}|TU\d{3}|GA\d{3}|GH\d{3}|AD\d{3}|GB\d{3}|GN\d{2,3})(?:[A-Z]{1,3})?\b", name)
    return m.group(1) if m else None


def _drm_nodes(ctx: Context, dev: str) -> Dict[str, Optional[str]]:
    card = render = None
    for entry in ctx.listdir(dev + "/drm"):
        if entry.startswith("card") and card is None:
            card = entry
        elif entry.startswith("renderD") and render is None:
            render = entry
    return {"card": card, "render": render}


def detect(ctx: Context) -> List[GPU]:
    raw = []
    for dev in ctx.glob("/sys/bus/pci/devices/*"):
        uevent = _parse_uevent(ctx.read(dev + "/uevent") or "")
        cls = _class_code(uevent.get("PCI_CLASS")) or _class_code(ctx.read_line(dev + "/class"))
        if cls is None or (cls >> 16) != 0x03:
            continue
        pci_id = uevent.get("PCI_ID", "")
        if ":" in pci_id:
            vendor_id, device_id = [p.lower() for p in pci_id.split(":", 1)]
        else:
            vendor_id = (ctx.read_line(dev + "/vendor") or "").lower().replace("0x", "")
            device_id = (ctx.read_line(dev + "/device") or "").lower().replace("0x", "")
        slot = uevent.get("PCI_SLOT_NAME") or dev.rstrip("/").split("/")[-1]
        driver = uevent.get("DRIVER") or ctx.readlink_base(dev + "/driver")
        raw.append((dev, slot, vendor_id, device_id, driver, cls))

    multi = len(raw) > 1
    gpus: List[GPU] = []
    for dev, slot, vendor_id, device_id, driver, cls in raw:
        vendor = VENDORS.get(vendor_id, "other")
        name = _lspci_name(ctx, slot)
        if not name:
            _, name = _lookup_pci_ids(ctx, vendor_id, device_id)
        if not name:
            name = "%s device %s:%s" % (VENDOR_LABELS.get(vendor, "Unknown"), vendor_id, device_id)
        boot_vga = ctx.read_line(dev + "/boot_vga") == "1"
        gpu = GPU(
            slot=slot,
            sysfsPath=dev,
            vendor=vendor,
            vendorLabel=VENDOR_LABELS.get(vendor, "Unknown (%s)" % vendor_id),
            vendorId=vendor_id,
            deviceId=device_id,
            name=name,
            pciClass="0x%06x" % cls,
            driver=driver,
            bootVga=boot_vga,
            kind=_classify(vendor, name, boot_vga, multi),
            runtimeStatus=ctx.read_line(dev + "/power/runtime_status"),
            drm=_drm_nodes(ctx, dev),
            byPath="/dev/dri/by-path/pci-%s-card" % slot,
        )
        if vendor == "nvidia":
            gpu["codename"] = nvidia_codename(name)
        gpus.append(gpu)

    # Boot GPU first, then integrated before discrete, then PCI order.
    order = {"integrated": 0, "unknown": 1, "virtual": 1, "discrete": 2}
    gpus.sort(key=lambda g: (not g["bootVga"], order.get(g["kind"], 1), g["slot"]))
    return gpus


def topology(gpus: List[GPU]) -> Dict[str, object]:
    """Summarise the multi-GPU arrangement (hybrid laptop, desktop, ...)."""
    integrated = [g for g in gpus if g["kind"] == "integrated"]
    discrete = [g for g in gpus if g["kind"] == "discrete"]
    nvidia = [g for g in gpus if g["vendor"] == "nvidia"]
    hybrid = bool(integrated and discrete)
    if not gpus:
        layout = "none"
    elif hybrid:
        layout = "hybrid"
    elif len(gpus) == 1:
        layout = "single"
    else:
        layout = "multi"
    primary = next((g for g in gpus if g["bootVga"]), gpus[0] if gpus else None)
    return {
        "layout": layout,
        "hybrid": hybrid,
        "primarySlot": primary["slot"] if primary else None,
        "primaryVendor": primary["vendor"] if primary else None,
        "integratedSlots": [g["slot"] for g in integrated],
        "discreteSlots": [g["slot"] for g in discrete],
        "hasNvidia": bool(nvidia),
        "nvidiaIsPrimary": bool(primary and primary["vendor"] == "nvidia"),
    }
