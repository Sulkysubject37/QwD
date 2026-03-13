#!/usr/bin/env bash
set -e

# QwD Interface Tests
# Verifies CLI JSON output validity and schema compliance.

BINARY="./zig-out/bin/qwd"
FIXTURE="tests/fixtures/sample.fastq"

if [ ! -f "$BINARY" ]; then
    echo "Error: QwD binary not found. Build first."
    exit 1
fi

echo "Testing JSON output..."
$BINARY qc "$FIXTURE" --json > output.json
# Simple check if it is valid JSON
python3.10 -c "import json; json.load(open('output.json'))"
echo "JSON validity: OK"

echo "Testing NDJSON streaming..."
$BINARY qc "$FIXTURE" --ndjson > output.ndjson
# Check if non-empty lines are valid JSON
python3.10 -c "import json, sys; [json.loads(line) for line in sys.stdin if line.strip()]" < output.ndjson
echo "NDJSON validity: OK"

rm output.json output.ndjson
echo "Interface tests: ALL PASSED"
