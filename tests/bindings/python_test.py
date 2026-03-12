import os
import sys
import unittest

# Add bindings/python to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../bindings/python')))

import qwd

class TestPythonBindings(unittest.TestCase):
    def test_qc_stub(self):
        # We test with a dummy path since it is a stub in the ABI for now
        res = qwd.qc("dummy.fastq")
        self.assertIn("status", res)
        self.assertEqual(res["status"], "processed")
        self.assertEqual(res["file"], "dummy.fastq")

    def test_bamstats_stub(self):
        res = qwd.bamstats("dummy.bam")
        self.assertIn("status", res)
        self.assertEqual(res["status"], "processed")

if __name__ == '__main__':
    unittest.main()
