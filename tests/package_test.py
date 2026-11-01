import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import package

class PackageTest(unittest.TestCase):
    def test_reproducible_and_exact_runtime(self):
        first = package.build().read_bytes()
        second = package.build().read_bytes()
        self.assertEqual(first, second)
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'plugin.rbz'
            path.write_bytes(first)
            with zipfile.ZipFile(path) as archive:
                self.assertEqual(set(package.RUNTIME), set(archive.namelist()))
                for name in package.RUNTIME:
                    self.assertEqual((package.ROOT/'src'/name).read_bytes(), archive.read(name))
                    self.assertFalse('..' in Path(name).parts)
                self.assertIn(b'MIT License', archive.read('lsc_stairs/LICENSE.txt'))
        digest = hashlib.sha256(first).hexdigest()
        self.assertIn(digest, (package.ROOT/'dist/SHA256SUMS.txt').read_text())

if __name__ == '__main__':
    unittest.main()
