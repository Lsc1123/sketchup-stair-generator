"""Build a reproducible RBZ from an explicit runtime allowlist."""
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = [
    'lsc_stairs.rb', 'lsc_stairs/version.rb', 'lsc_stairs/core.rb',
    'lsc_stairs/main.rb', 'lsc_stairs/geometry.rb', 'lsc_stairs/tools.rb',
    'lsc_stairs/LICENSE.txt', 'lsc_stairs/NOTICE.txt', 'lsc_stairs/icons/stairs.png',
    'lsc_stairs/ui/index.html', 'lsc_stairs/ui/style.css', 'lsc_stairs/ui/app.js',
    'lsc_stairs/ui/demo.js',
]

def build():
    version = re.search(r"VERSION = '([^']+)'", (ROOT/'src/lsc_stairs/version.rb').read_text()).group(1)
    out = ROOT/'dist'
    out.mkdir(exist_ok=True)
    package = out/f'lsc-stairs-{version}.rbz'
    manifest = {}
    with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in RUNTIME:
            path = ROOT/'src'/name
            if path.is_symlink() or not path.is_file():
                raise ValueError(f'Missing or unsafe runtime file: {name}')
            data = path.read_bytes()
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
            manifest[name] = hashlib.sha256(data).hexdigest()
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    (out/'SHA256SUMS.txt').write_text(f'{digest}  {package.name}\n')
    (out/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(package)
    return package

if __name__ == '__main__':
    build()
