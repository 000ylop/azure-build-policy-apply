from functools import reduce

utf16le_hex = lambda name_part: reduce(
    lambda s,next: s+next, (("%02x" % ch) for ch in name_part.encode("utf-16le"))
)

result = '/'.join(utf16le_hex(part) for part in input().split('/'))
print(result)
