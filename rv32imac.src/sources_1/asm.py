import re, sys

def reg(s):
    s = s.strip()
    if s.startswith('x') or s.startswith('X'):
        return int(s[1:])
    abi = {'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,'t0':5,'t1':6,'t2':7,
           's0':8,'fp':8,'s1':9,'a0':10,'a1':11,'a2':12,'a3':13,
           'a4':14,'a5':15,'a6':16,'a7':17,'s2':18,'s3':19,'s4':20,
           's5':21,'s6':22,'s7':23,'s8':24,'s9':25,'s10':26,'s11':27,
           't3':28,'t4':29,'t5':30,'t6':31}
    return abi.get(s.lower(), int(s))

def imm(s):
    s = s.strip()
    if s.startswith('0x') or s.startswith('0X'): return int(s, 16)
    return int(s)

def sext12(x): return x - 0x1000 if x & 0x800 else x

def encode_i(funct3, opcode, rd, rs1, imm_val):
    return ((imm_val & 0xfff) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_r(funct7, funct3, opcode, rd, rs1, rs2):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_s(funct3, opcode, rs2, rs1, imm_val):
    return ((imm_val >> 5 & 0x7f) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm_val & 0x1f) << 7) | opcode

def encode_b(funct3, opcode, rs2, rs1, imm_val):
    return ((imm_val >> 12 & 1) << 31) | ((imm_val >> 5 & 0x3f) << 25) | (rs2 << 20) | (rs1 << 15) \
         | (funct3 << 12) | ((imm_val >> 1 & 0xf) << 8) | ((imm_val >> 11 & 1) << 7) | opcode

def encode_u(opcode, rd, imm_val):
    return (imm_val & 0xfffff000) | (rd << 7) | opcode

def encode_j(opcode, rd, imm_val):
    return ((imm_val >> 20 & 1) << 31) | ((imm_val >> 1 & 0x3ff) << 21) | ((imm_val >> 11 & 1) << 20) \
         | ((imm_val >> 12 & 0xff) << 12) | (rd << 7) | opcode

alu_r = {
    'add':(0x00,0,0x33), 'sub':(0x20,0,0x33), 'sll':(0x00,1,0x33),
    'slt':(0x00,2,0x33), 'sltu':(0x00,3,0x33), 'xor':(0x00,4,0x33),
    'srl':(0x00,5,0x33), 'sra':(0x20,5,0x33), 'or':(0x00,6,0x33), 'and':(0x00,7,0x33),
}

alu_i = {
    'addi':(0,0x13), 'slti':(2,0x13), 'sltiu':(3,0x13),
    'xori':(4,0x13), 'ori':(6,0x13), 'andi':(7,0x13),
    'slli':(1,0x13), 'srli':(5,0x13), 'srai':(5,0x13),
    'jalr':(0,0x67),
}

load = {'lb':(0,0x03), 'lh':(1,0x03), 'lw':(2,0x03),
        'lbu':(4,0x03), 'lhu':(5,0x03)}
br = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}
st = {'sb':0,'sh':1,'sw':2}

def emit_li(rd, val):
    """Generate instruction list for li pseudo-instruction."""
    if val == 0: return [f'addi {rd}, x0, 0']
    upper = (val >> 12) & 0xfffff
    lower = val & 0xfff
    if lower & 0x800:
        upper = (upper + 1) & 0xfffff
        lower = sext12(lower)
    instrs = []
    if upper == 0:
        instrs.append(f'addi {rd}, x0, {lower}')
    else:
        instrs.append(f'lui {rd}, 0x{upper:X}')
        if lower != 0:
            instrs.append(f'addi {rd}, {rd}, {lower}')
    return instrs

def assemble_one(line):
    line = re.sub(r'#.*', '', line).strip()
    if not line: return None
    m = re.match(r'(\w+(?:\.\w+)?)(?:\s+(.*))?', line)
    if not m: return None
    opc = m.group(1).lower()
    rest = m.group(2) or ''
    args = [a.strip() for a in rest.split(',')]

    if opc == 'ebreak': return 0x00100073
    if opc == 'nop': return 0x00000013
    if opc == 'li':
        rd = reg(args[0]); val = imm(args[1])
        seq = emit_li(rd, val)
        return [assemble_one(s) for s in seq]

    if opc in load:
        f3, op = load[opc]
        rd = reg(args[0])
        m2 = re.match(r'(\w+)\((\w+)\)', args[1])
        if m2:
            imm_val = imm(m2.group(1)); rs1 = reg(m2.group(2))
        else:
            rs1 = reg(args[1]); imm_val = 0
        return encode_i(f3, op, rd, rs1, imm_val)

    if opc in alu_i:
        f3, op = alu_i[opc]
        rd = reg(args[0]); rs1 = reg(args[1])
        if opc in ('slli','srli','srai'):
            shamt = imm(args[2])
            if opc == 'srai': shamt |= 0x400
            return encode_i(f3, op, rd, rs1, shamt)
        imm_val = imm(args[2])
        return encode_i(f3, op, rd, rs1, imm_val)

    if opc in alu_r:
        f7, f3, op = alu_r[opc]
        rd = reg(args[0]); rs1 = reg(args[1]); rs2 = reg(args[2])
        return encode_r(f7, f3, op, rd, rs1, rs2)

    if opc in br:
        f3 = br[opc]
        rs1 = reg(args[0]); rs2 = reg(args[1]); bimm = imm(args[2])
        return encode_b(f3, 0x63, rs2, rs1, bimm)

    if opc in st:
        f3 = st[opc]
        m2 = re.match(r'(\w+)\((\w+)\)', args[1])
        if m2:
            imm_val = imm(m2.group(1)); rs1 = reg(m2.group(2))
        else:
            rs1 = reg(args[1]); imm_val = 0
        rs2 = reg(args[0])
        return encode_s(f3, 0x23, rs2, rs1, imm_val)

    if opc in ('csrrw','csrrs','csrrc','csrrwi','csrrsi','csrrci'):
        csr_f3 = {'csrrw':1,'csrrs':2,'csrrc':3,'csrrwi':5,'csrrsi':6,'csrrci':7}[opc]
        rd = reg(args[0]); csr_addr = imm(args[1])
        if opc in ('csrrw','csrrs','csrrc'):
            rs1 = reg(args[2])
        else:
            rs1 = imm(args[2])
        return encode_i(csr_f3, 0x73, rd, rs1, csr_addr)

    if opc in ('csrr','csrw','csrs','csrc','csrwi','csrsi','csrci'):
        if opc == 'csrr':
            rd = reg(args[0]); csr_addr = imm(args[1])
            return encode_i(2, 0x73, rd, 0, csr_addr)
        elif opc in ('csrw','csrs','csrc'):
            csr_f3 = {'csrw':1,'csrs':2,'csrc':3}[opc]
            csr_addr = imm(args[0]); rs1 = reg(args[1])
            return encode_i(csr_f3, 0x73, 0, rs1, csr_addr)
        else:  # csrwi, csrsi, csrci
            csr_f3 = {'csrwi':5,'csrsi':6,'csrci':7}[opc]
            csr_addr = imm(args[0]); uimm = imm(args[1])
            return encode_i(csr_f3, 0x73, 0, uimm, csr_addr)

    if opc == 'lui':
        rd = reg(args[0]); imm_val = imm(args[1])
        return (imm_val << 12) | (rd << 7) | 0x37

    if opc == 'auipc':
        rd = reg(args[0]); imm_val = imm(args[1])
        return (imm_val << 12) | (rd << 7) | 0x17

    if opc == 'jal':
        rd = reg(args[0]); jimm = imm(args[1])
        return encode_j(0x6f, rd, jimm)

    return None

def assemble(src):
    """Assemble source lines into list of hex values. Handles pseudo-ops."""
    codes = []
    for line in src.split('\n') if isinstance(src, str) else src:
        if isinstance(line, int):
            codes.append(line)
            continue
        if not isinstance(line, str):
            continue
        result = assemble_one(line)
        if result is None: continue
        if isinstance(result, list):
            codes.extend(result)
        else:
            codes.append(result)
    return codes

# ── Two-pass assembler with labels ────────────────────────────

BRANCH_OPS = {'beq','bne','blt','bge','bltu','bgeu'}
JUMP_OPS   = {'jal'}

def _instr_count(line):
    """Count how many 4-byte instructions a line expands to."""
    parts = line.split(None, 1)
    if not parts: return 0
    opc = parts[0].lower()
    if opc == 'li':
        rd = parts[1].split(',')[0].strip()
        val_str = parts[1].split(',')[1].strip()
        val = int(val_str, 16) if val_str.startswith('0x') else int(val_str)
        return len(emit_li(rd, val))
    if opc == 'nop': return 1
    return 1

def _resolve_label(line, pc, labels):
    """Replace a branch/jump label with the computed offset."""
    parts = line.split(None, 1)
    if not parts: return line
    opc = parts[0].lower()
    rest = parts[1] if len(parts) > 1 else ''
    if opc in BRANCH_OPS:
        args = [a.strip() for a in rest.split(',')]
        if len(args) == 3 and args[2] in labels:
            offset = labels[args[2]] - pc
            return f'{opc} {args[0]}, {args[1]}, {offset}'
    if opc == 'j':
        target = rest.strip()
        if target in labels:
            offset = labels[target] - pc
            return f'jal x0, {offset}'
    if opc in JUMP_OPS:
        args = [a.strip() for a in rest.split(',')]
        if len(args) == 2 and args[1] in labels:
            offset = labels[args[1]] - pc
            return f'{opc} {args[0]}, {offset}'
    return line

def assemble_labels(src):
    """
    Two-pass assembler with label support.
    Labels are written as 'name:' on their own line.
    Returns list of hex instruction codes.
    """
    raw_lines = src.split('\n') if isinstance(src, str) else src

    # First pass: collect labels and compute addresses
    labels = {}
    passthrough = []  # (original_line, pc_at_end_of_expansion) or None for labels
    pc = 0
    for line in raw_lines:
        line = re.sub(r'#.*', '', line).strip()
        if not line: continue
        if ':' in line and not line.startswith('0x'):
            label = line.split(':')[0].strip()
            if re.match(r'^[a-zA-Z_]\w*$', label):
                labels[label] = pc
                rest = line.split(':', 1)[1].strip()
                if rest:
                    pc += _instr_count(rest) * 4
                    passthrough.append(rest)
                continue
        pc += _instr_count(line) * 4
        passthrough.append(line)

    # Second pass: resolve labels and assemble
    codes = []
    pc = 0
    for line in passthrough:
        resolved = _resolve_label(line, pc, labels)
        result = assemble_one(resolved)
        n = _instr_count(line)
        pc += n * 4
        if result is None: continue
        if isinstance(result, list):
            codes.extend(result)
        else:
            codes.append(result)
    return codes

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--test':
        tests = [
            ('addi x1,x0,5', 0x00500093),
            ('addi x2,x0,10', 0x00a00113),
            ('add x3,x1,x2', 0x002081b3),
            ('sub x4,x2,x1', 0x40110233),
            ('ebreak', 0x00100073),
            ('nop', 0x00000013),
            ('lui x1, 0x12345', 0x123450b7),
            ('auipc x2, 0x100', 0x00100117),
            ('li x5, 0x12345678', [0x123452b7, 0x67828293]),
            ('li x5, 0', [0x00000293]),
        ]
        for src, exp in tests:
            got = assemble_one(src)
            if isinstance(got, list):
                status = 'OK' if got == exp else 'FAIL'
                print(f'{status}: {src:30s} -> {["0x%08x"%c for c in got]}')
            else:
                status = 'OK' if got == exp else f'FAIL (got 0x{got:08x})'
                print(f'{status}: {src:30s} -> 0x{got:08x}')
        sys.exit(0)

    for line in sys.stdin:
        result = assemble_one(line)
        if result is None: continue
        if isinstance(result, list):
            for c in result: print(f'{c:08x}')
        else:
            print(f'{result:08x}')
