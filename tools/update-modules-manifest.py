"""Regenerate module SHA-256 values after editing src/*.ps1."""

from hashlib import sha256
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = [
    'src/Core/Runtime.ps1',
    'src/Core/Output.ps1',
    'src/Core/Http.ps1',
    'src/Dependencies/Manifest.ps1',
    'src/Dependencies/WindowsFeatures.ps1',
    'src/Dependencies/VisualCpp.ps1',
    'src/Dependencies/DotNet.ps1',
    'src/Dependencies/IisRewrite.ps1',
    'src/Dependencies/RabbitMq.ps1',
    'src/Operations/Install.ps1',
    'src/Operations/Verify.ps1',
    'src/Operations/Cleanup.ps1',
    'src/Operations/Repair.ps1',
    'src/Operations/Diagnostics.ps1',
    'src/Operations/Mago4.ps1',
    'src/UI/InstallMenu.ps1',
    'src/UI/CleanupMenu.ps1',
    'src/UI/MainMenu.ps1',
]


def module_hash(path: str) -> str:
    content = (ROOT / path).read_bytes()
    if not content.startswith(b'\xef\xbb\xbf'):
        raise SystemExit(f'{path} must be UTF-8 with BOM for Windows PowerShell 5.1')
    return sha256(content).hexdigest()

manifest = {
    'schema': 1,
    'modules': [
        {'path': path, 'sha256': module_hash(path)}
        for path in MODULES
    ],
}
(ROOT / 'modules.json').write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8'
)
