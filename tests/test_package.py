import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('package', Path(__file__).parents[1] / 'scripts/package.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackagingTests(unittest.TestCase):
    def test_mismatched_windows_architecture_is_rejected(self):
        for arch, machine in [('x64', 0x8664), ('arm64', 0xAA64)]:
            data = bytearray(128)
            data[:2] = b'MZ'
            data[60:64] = (64).to_bytes(4, 'little')
            data[64:68] = b'PE\0\0'
            data[68:70] = machine.to_bytes(2, 'little')
            package.verify_pe_architecture(data, arch)
            with self.assertRaises(RuntimeError):
                package.verify_pe_architecture(data, 'arm64' if arch == 'x64' else 'x64')

    def test_epoch_notice_is_preserved_with_zip_safe_timestamp(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bundle = root / 'bundle'
            bundle.mkdir()
            notice = bundle / 'LICENSE'
            notice.write_text('Example license notice')
            os.utime(notice, (0, 0))
            first, second = root / 'a.zip', root / 'b.zip'
            package.write_bundle(bundle, first)
            package.write_bundle(bundle, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(archive.read('LICENSE'), b'Example license notice')
                self.assertEqual(archive.getinfo('LICENSE').date_time[0], 1980)

    def test_unknown_licenses_are_not_silently_allowed(self):
        for value in (None, '', 'Proprietary', 'MIT OR Proprietary', 'Apache-2.0 WITH Unknown-exception'):
            self.assertFalse(package.license_allowed(value), value)
        self.assertTrue(package.license_allowed('MIT OR Apache-2.0'))


if __name__ == '__main__':
    unittest.main()
