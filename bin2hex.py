import struct, sys
fname = sys.argv[1] if len(sys.argv) > 1 else "test_lb_simple.bin"
with open(fname, "rb") as f:
    data = f.read()
while len(data) % 4:
    data += b"\x00"
with open("test_prog.hex", "w") as f:
    for i in range(0, len(data), 4):
        word = struct.unpack("<I", data[i:i+4])[0]
        f.write("%08x\n" % word)
nwords = len(data) // 4
print(f"Wrote {nwords} words from {fname} to test_prog.hex")
