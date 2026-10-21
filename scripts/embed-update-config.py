#!/usr/bin/env python3
"""Embed public Sparkle configuration; never reads signing secrets."""
import base64
import json
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlsplit

config = json.loads(Path(sys.argv[1]).read_text())
url = urlsplit(config['feedURL'])
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.fragment:
    raise SystemExit('The update feed must use HTTPS without embedded credentials.')
if len(base64.b64decode(config['publicKey'], validate=True)) != 32:
    raise SystemExit('Expected a 32-byte Ed25519 public key.')
path = Path(sys.argv[2])
with path.open('rb') as stream:
    info = plistlib.load(stream)
info.update(SUFeedURL=config['feedURL'], SUPublicEDKey=config['publicKey'],
            SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False,
            SUAllowsAutomaticUpdates=False, SUEnableSystemProfiling=False,
            SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True,
            SUSignedFeedFailureExpirationInterval=0)
with path.open('wb') as stream:
    plistlib.dump(info, stream)
