"""Recover the two already-public synthetic specimens; never execute issue text."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import urllib.request

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
records = [
    ("issues/66", "binary.rds", 1545,
     "3dccdf709354cb94b115fb5702a3a4887c9d10c3989b3b0688e75d3f787d9f68"),
    ("issues/comments/6048562178", "ordinal.rds", 2888,
     "a38357f279676a1aae0aafc7f60ca51d041ff06f56a0bd2e60fb86e4de7d98ce"),
]
identities = []
for endpoint, name, size, digest in records:
    url = "https://api.github.com/repos/Veronica0206/Gtheory4LLM/" + endpoint
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": "Bearer " + os.environ["GH_TOKEN"],
    })
    with urllib.request.urlopen(request, timeout=60) as response:
        record = json.load(response)
    (out / (name + ".source.json")).write_text(json.dumps(record, indent=2) + "\n")
    matches = re.findall(r"<<'SPECIMEN'\s*\n([A-Za-z0-9+/=\s]+)\nSPECIMEN", record["body"])
    assert len(matches) == 1, (endpoint, "ambiguous specimen")
    data = base64.b64decode("".join(matches[0].split()), validate=True)
    assert len(data) == size and hashlib.sha256(data).hexdigest() == digest
    (out / name).write_bytes(data)
    identities.append(dict(name=name, bytes=size, sha256=digest, source=url))
(out / "identities.json").write_text(json.dumps(identities, indent=2) + "\n")
print(json.dumps(identities, indent=2))
