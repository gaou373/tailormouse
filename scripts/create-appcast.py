#!/usr/bin/env python3
"""Create a public update feed from an already-signed local release archive."""
import datetime
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

config_path, archive_path, version, build, signature, output = sys.argv[1:]
config = json.loads(Path(config_path).read_text())
archive = Path(archive_path)
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
root = ET.Element('rss', version='2.0')
channel = ET.SubElement(root, 'channel')
ET.SubElement(channel, 'title').text = 'TailorMouse Updates'
ET.SubElement(channel, 'link').text = 'https://github.com/gaou373/tailormouse'
ET.SubElement(channel, 'description').text = 'Signed TailorMouse releases for macOS.'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'TailorMouse {version}'
ET.SubElement(item, f'{{{ns}}}version').text = build
ET.SubElement(item, f'{{{ns}}}shortVersionString').text = version
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = '13.0'
ET.SubElement(item, 'pubDate').text = datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')
ET.SubElement(item, 'description').text = 'In-app updates, universal drag-to-Applications installer, and existing Naga Pro mappings. Updates preserve local settings and reopen stopped. This preview is not Apple notarized; see the release page for installation guidance.'
ET.SubElement(item, 'enclosure', attrib={
    'url': f'{config["downloadBaseURL"]}/v{version}/{archive.name}',
    f'{{{ns}}}edSignature': signature,
    'length': str(archive.stat().st_size),
    'type': 'application/octet-stream'
})
ET.ElementTree(root).write(output, encoding='utf-8', xml_declaration=True)
