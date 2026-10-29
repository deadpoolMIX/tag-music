"""Read libmpv runtime versions without creating a window or playing audio."""
import ctypes
import hashlib
import json
import pathlib
import re
import sys

library = pathlib.Path(sys.argv[1]).resolve()
mpv = ctypes.CDLL(str(library))
mpv.mpv_create.restype = ctypes.c_void_p
mpv.mpv_set_option_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
mpv.mpv_initialize.argtypes = [ctypes.c_void_p]
mpv.mpv_get_property_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
mpv.mpv_get_property_string.restype = ctypes.c_void_p
mpv.mpv_free.argtypes = [ctypes.c_void_p]
mpv.mpv_terminate_destroy.argtypes = [ctypes.c_void_p]
handle = mpv.mpv_create()
if not handle:
    raise RuntimeError('mpv_create failed')
result = {'file': str(library), 'sha256': hashlib.sha256(library.read_bytes()).hexdigest()}
try:
    mpv.mpv_set_option_string(handle, b'ao', b'null')
    mpv.mpv_set_option_string(handle, b'vo', b'null')
    mpv.mpv_set_option_string(handle, b'config', b'no')
    if mpv.mpv_initialize(handle) < 0:
        raise RuntimeError('mpv_initialize failed')
    for name in ['mpv-version', 'ffmpeg-version', 'mpv-configuration']:
        value = mpv.mpv_get_property_string(handle, name.encode())
        if value:
            result[name] = ctypes.string_at(value).decode(errors='replace')
            mpv.mpv_free(value)
    strings = re.findall(rb'[\x20-\x7e]{12,}', library.read_bytes())
    result['build_strings'] = [s.decode() for s in strings if b'--disable-gpl' in s or b'--enable-gpl' in s or b'--enable-version3' in s or b'LGPL' in s or b'License version' in s]
finally:
    mpv.mpv_terminate_destroy(handle)
print(json.dumps(result, indent=2, ensure_ascii=False))
