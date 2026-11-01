"""Generate the project's own small stair glyph, without external assets."""
import math
from pathlib import Path
import struct
import zlib

N = 64
segments = [((17, 46), (27, 46)), ((27, 46), (27, 35)),
            ((27, 35), (38, 35)), ((38, 35), (38, 24)),
            ((38, 24), (48, 24))]

def distance(x, y, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]
    t = max(0, min(1, ((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)))
    return math.hypot(x-a[0]-t*dx, y-a[1]-t*dy)

rows = []
for y in range(N):
    row = bytearray()
    for x in range(N):
        cx, cy = max(13, min(50, x)), max(13, min(50, y))
        alpha = max(0, min(1, 13.5-math.hypot(x-cx, y-cy)))
        white = max(0, min(1, 2.8-min(distance(x, y, a, b) for a, b in segments)))
        row.extend((round(0+255*white), round(122+133*white), 255, round(alpha*255)))
    rows.append(b'\0'+row)

def chunk(kind, data):
    return struct.pack('!I', len(data))+kind+data+struct.pack('!I', zlib.crc32(kind+data)&0xffffffff)

png = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('!IIBBBBB', N, N, 8, 6, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(b''.join(rows)))+chunk(b'IEND', b'')
(Path(__file__).resolve().parents[1]/'src/lsc_stairs/icons/stairs.png').write_bytes(png)
