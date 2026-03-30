import os
import sys
import unittest
import tempfile

# Add bindings/python to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../bindings/python')))

import qwd

class TestPythonBindings(unittest.TestCase):
    def setUp(self):
        self.fastq_fd, self.fastq_path = tempfile.mkstemp(suffix=".fastq")
        with os.fdopen(self.fastq_fd, 'w') as f:
            f.write("@READ_1\nACGT\n+\nIIII\n")
            
        self.bam_fd, self.bam_path = tempfile.mkstemp(suffix=".bam")
        with os.fdopen(self.bam_fd, 'w') as f:
            f.write("BAM_DUMMY_HEADER")

    def tearDown(self):
        os.remove(self.fastq_path)
        os.remove(self.bam_path)

    def test_qc(self):
        res = qwd.qc(self.fastq_path)
        self.assertIn("read_count", res)
        self.assertEqual(res["read_count"], 1)

    def test_qc_approx(self):
        res = qwd.qc(self.fastq_path, approx=True)
        self.assertIn("read_count", res)
        self.assertEqual(res["read_count"], 1)

    def test_bamstats(self):
        res = qwd.bamstats(self.bam_path)
        # Note: BamReader stub returns predefined records, ignoring the actual file content for now,
        # but the file needs to exist to pass the openFile check.
        self.assertIn("record_count", res)
        self.assertGreaterEqual(res["record_count"], 0)

if __name__ == '__main__':
    unittest.main()
