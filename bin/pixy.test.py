#!/usr/bin/python3
"""Offline protocol, UVC ABI and preset preservation checks."""
import ctypes
from pathlib import Path
import runpy
import tempfile

m = runpy.run_path(str(Path(__file__).with_name('pixy')))
assert m['frame'](bytes.fromhex('09 63 01 01'), b'\x01') == bytes.fromhex('09 63 01 01 00 01 00 01 01') + bytes(23)
assert ctypes.sizeof(m['ExtControl']) == 20
assert ctypes.sizeof(m['ExtControls']) == 32
cam = object.__new__(m['Camera'])
cam.query = lambda report: bytes.fromhex('09 04 02 01 00 02 00 02 02 01') + bytes(22)
assert cam.state('gesture') is True
cam.query = lambda report: bytes.fromhex('09 04 02 01 00 02 00 02 02 00') + bytes(22)
assert cam.state('gesture') is False
cam.query = lambda report: bytes.fromhex('09 01 01 01 00 01 00 01 03') + bytes(23)
assert cam.state('camera') == 'idle'
sent = []
cam.query = lambda report: sent.append(report)
cam.state = lambda kind: 'nc' if kind == 'audio' else False
cam.mode(5, 1)
cam.mode(4, 0)
assert sent == [m['frame'](bytes.fromhex('09 05 00 03'), b'\x01'),
                m['frame'](bytes.fromhex('09 04 02 00'), b'\x02\x00')]
cam.motor = lambda motor: 7 if motor == 1 else 12
cam.video = -1
submitted = []
original_ioctl = m['fcntl'].ioctl
try:
    def capture(fd, request, controls):
        submitted.append({controls.controls[i].id: controls.controls[i].value for i in range(controls.count)})
    m['fcntl'].ioctl = capture
    cam.move({'pan': 5})
    assert submitted == [{m['IDS']['pan']: 18000, m['IDS']['tilt']: 43200}]
    try:
        cam.move({'zoom': float('nan')})
    except ValueError:
        pass
    else:
        raise AssertionError('Nonfinite PTZ must be rejected')
    assert len(submitted) == 1
finally:
    m['fcntl'].ioctl = original_ioctl
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'presets.json'
    m['save'].__globals__['PRESETS'] = path
    m['presets'].__globals__['PRESETS'] = path
    data = {'version': 1, 'presets': {'name with spaces': {'image': {'gain': 4}, 'pan': 5, 'tilt': 2, 'zoom': 110}}}
    m['save'](data)
    assert m['presets']() == data
    path.write_text('{broken')
    try:
        m['presets']()
    except ValueError:
        pass
    else:
        raise AssertionError('Malformed presets must not be overwritten')
print('pixy offline checks passed')
