"""Build a deterministic mod ZIP and verify every packaged byte."""
from pathlib import Path
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "builds" / "FS25_z_StorageAlertMonitor.zip"
FILES = ["Data.lua", "README.md", "icon_StorageAlertMonitor.dds", "main.lua",
         "modDesc.xml", "tabIcon.dds"]
FILES += [p.relative_to(ROOT).as_posix() for p in (ROOT / "gui").rglob("*") if p.is_file()]

def build():
    payload = {name: (ROOT / name).read_bytes() for name in sorted(FILES)}
    for name, data in payload.items():
        if name.endswith((".lua", ".xml", ".md")) and b"\r" in data:
            raise ValueError(f"{name}: use LF line endings as specified in .gitattributes")
        if name.endswith(".xml"):
            ET.fromstring(data)
    OUTPUT.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(OUTPUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in payload.items():
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data, compresslevel=9)
    with zipfile.ZipFile(OUTPUT) as archive:
        assert archive.testzip() is None, "ZIP integrity check failed"
        assert set(archive.namelist()) == set(payload), "ZIP file list differs"
        for name, data in payload.items():
            assert archive.read(name) == data, f"ZIP content differs: {name}"
    print(f"Built and verified {OUTPUT.name}: {len(payload)} files, {OUTPUT.stat().st_size} bytes")

if __name__ == "__main__":
    build()
