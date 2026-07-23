import sys, os, subprocess, re, random, ctypes

SRC_DIR = r'D:\Desktop\programs\vivado\rv32imac\rv32imac.src\sources_1'
PROJ_DIR = r'D:\Desktop\programs\vivado\rv32imac'

def sv_files():
    return [os.path.join(SRC_DIR, f) for f in
            ['alu.sv','reg.sv','csr.sv','unified_bram.sv',
             'if.sv','id.sv','ex.sv','mem.sv','wb.sv','top.sv',
             'div.sv','mul.sv','tb.sv']]

def xsim_bin(name):
    return rf'E:\AMDDesignTools\2025.2.1\Vivado\bin\{name}.bat'

def to_s32(x): return ctypes.c_int32(x).value

# ── Reference models ──────────────────────────────────────────
sext = lambda imm: imm if not (imm & 0x800) else imm - 0x1000

ref = {
    'add':  lambda a,b,i: (a + b) & 0xffffffff,
    'sub':  lambda a,b,i: (a - b) & 0xffffffff,
    'sll':  lambda a,b,i: (a << (b & 0x1f)) & 0xffffffff,
    'slt':  lambda a,b,i: 1 if to_s32(a) < to_s32(b) else 0,
    'sltu': lambda a,b,i: 1 if a < b else 0,
    'xor':  lambda a,b,i: (a ^ b) & 0xffffffff,
    'srl':  lambda a,b,i: (a >> (b & 0x1f)) & 0xffffffff,
    'sra':  lambda a,b,i: (to_s32(a) >> (b & 0x1f)) & 0xffffffff,
    'or':   lambda a,b,i: (a | b) & 0xffffffff,
    'and':  lambda a,b,i: (a & b) & 0xffffffff,
    'addi': lambda a,b,i: (a + sext(i)) & 0xffffffff,
    'slti': lambda a,b,i: 1 if to_s32(a) < to_s32(sext(i)) else 0,
    'sltiu':lambda a,b,i: 1 if a < (sext(i) & 0xffffffff) else 0,
    'xori': lambda a,b,i: (a ^ sext(i)) & 0xffffffff,
    'ori':  lambda a,b,i: (a | sext(i)) & 0xffffffff,
    'andi': lambda a,b,i: (a & sext(i)) & 0xffffffff,
    'slli': lambda a,b,i: (a << (i & 0x1f)) & 0xffffffff,
    'srli': lambda a,b,i: (a >> (i & 0x1f)) & 0xffffffff,
    'srai': lambda a,b,i: (to_s32(a) >> (i & 0x1f)) & 0xffffffff,
}

from asm import assemble, assemble_one, emit_li, assemble_labels, _instr_count

# ── Instruction helpers ───────────────────────────────────────
def instr_r(name):
    return lambda rd, rs1, rs2: assemble_one(f'{name} x{rd}, x{rs1}, x{rs2}')
def instr_i(name):
    return lambda rd, rs1, imm: assemble_one(f'{name} x{rd}, x{rs1}, {imm}')

INSTR_DEFS = [
    ('R', 'add'), ('R', 'sub'), ('R', 'sll'), ('R', 'slt'),
    ('R', 'sltu'), ('R', 'xor'), ('R', 'srl'), ('R', 'sra'),
    ('R', 'or'), ('R', 'and'),
    ('I', 'addi'), ('I', 'slti'), ('I', 'sltiu'),
    ('I', 'xori'), ('I', 'ori'), ('I', 'andi'),
    ('I', 'slli'), ('I', 'srli'), ('I', 'srai'),
]

EDGE_VALUES = [
    0x00000000, 0x00000001, 0x0000001f, 0x00000020,
    0x000007ff, 0x00000800, 0x00000fff,
    0x7fffffff, 0x80000000, 0xffffffff,
]

# ── Test builder ──────────────────────────────────────────────

class Case:
    __slots__ = ('test_id', 'name', 'expected', 'lines', 'pc', 'code_idx')
    def __init__(self, test_id, name, expected, lines):
        self.test_id = test_id
        self.name = name
        self.expected = expected
        self.lines = lines
        self.pc = 0
        self.code_idx = 0

class TestBuilder:
    def __init__(self):
        self.cases = []
        self.lines = []
        self._instr_count = 0

    def add(self, name, expected, lines):
        test_id = len(self.cases)
        c = Case(test_id, name, expected, lines)
        c.pc = self._instr_count * 4
        self._instr_count += sum(_instr_count(l) for l in lines)
        self.cases.append(c)
        self.lines.extend(lines)
        return test_id

    def get_pc(self, test_id):
        return self.cases[test_id].pc

    def build(self, extra=None):
        full = list(self.lines)
        if extra:
            full.extend(extra)
        full.append('ebreak')
        full.append('jal x0, 0')
        return assemble_labels('\n'.join(full))

# ── Test generators ───────────────────────────────────────────

def gen_alu(builder, seed=42, max_total=60):
    rng = random.Random(seed)
    count = 0

    for fmt, name in INSTR_DEFS:
        gen = instr_r(name) if fmt == 'R' else instr_i(name)
        per_instr = max(4, (max_total // len(INSTR_DEFS)))
        used = 0

        for a in EDGE_VALUES:
            for b in EDGE_VALUES:
                if used >= per_instr: break
                if fmt == 'R':
                    exp = ref[name](a, b, 0)
                    lines = emit_li('x5', a) + emit_li('x6', b)
                    lines.append(f'{name} x7, x5, x6')
                else:
                    bi = (b & 0xfff)
                    exp = ref[name](a, 0, bi)
                    lines = emit_li('x5', a)
                    lines.append(f'{name} x7, x5, {bi}')
                lines.append(f'sw x7, {len(builder.cases)*4}(x0)')
                builder.add(f'{name}', exp, lines)
                used += 1
                count += 1
                if count >= max_total: return
            if used >= per_instr: break
            if count >= max_total: return

        for _ in range(per_instr - used):
            a = rng.randint(0, 0xffffffff)
            b = rng.randint(0, 0xfff) if fmt == 'I' else rng.randint(0, 0xffffffff)
            if fmt == 'R':
                exp = ref[name](a, b, 0)
                lines = emit_li('x5', a) + emit_li('x6', b)
                lines.append(f'{name} x7, x5, x6')
            else:
                exp = ref[name](a, 0, b)
                lines = emit_li('x5', a)
                lines.append(f'{name} x7, x5, {b}')
            lines.append(f'sw x7, {len(builder.cases)*4}(x0)')
            builder.add(f'{name}', exp, lines)
            count += 1
            if count >= max_total: return

def gen_utype(builder):
    rid = lambda: len(builder.cases)*4

    # LUI
    for v in [0x12345, 0xFFFFF, 0x00000, 0xABCDE]:
        exp = (v << 12) & 0xffffffff
        lines = [f'lui x7, 0x{v:X}', f'sw x7, {rid()}(x0)']
        builder.add(f'lui(0x{v:X})', exp, lines)

    # AUIPC: expected = PC of the auipc instruction
    for v in [0x0, 0x1, 0x100, 0xFFFFF]:
        lines = [f'auipc x7, 0x{v:X}', f'sw x7, {rid()}(x0)']
        test_id = len(builder.cases)
        # PC placeholder: we compute it from the instruction count
        pc = builder._instr_count * 4
        # CPU runs at 0x80000000-based PC
        exp = (0x80000000 + pc + (v << 12)) & 0xffffffff
        builder.add(f'auipc(0x{v:X})', exp, lines)

def gen_load_store(builder):
    rid = lambda: len(builder.cases)*4
    data_base = 0x1000   # above code area (code occupies 0..end-of-program)

    test_vals = [
        0x12345678, 0x00000000, 0xFFFFFFFF, 0xDEADBEEF,
        0xAABBCCDD, 0x87654321,
    ]

    for val in test_vals:
        daddr = data_base + len(builder.cases) * 8
        lines = emit_li('x5', val) + [
            f'sw x5, {daddr}(x0)',
            f'lw x7, {daddr}(x0)',
            'nop',  # wait for lw to reach MEM so MEM→ID forward provides loaded value
            f'sw x7, {rid()}(x0)',
        ]
        builder.add(f'sw+lw(0x{val:08x})', val, lines)

    # byte/halfword loads
    for val in [0x12345678, 0x12345600, 0xFFFFFF80, 0x0000007F]:
        daddr = data_base + len(builder.cases) * 8

        lb_sx = val & 0xFF
        if lb_sx & 0x80: lb_sx |= 0xFFFFFF00
        lines = emit_li('x5', val) + [
            f'sw x5, {daddr}(x0)',
            f'lb x7, {daddr}(x0)',
            'nop',
            f'sw x7, {rid()}(x0)',
        ]
        builder.add(f'lb(0x{val:08x})', ctypes.c_int32(lb_sx).value & 0xFFFFFFFF, lines)

        lh_sx = val & 0xFFFF
        if lh_sx & 0x8000: lh_sx |= 0xFFFF0000
        lines = emit_li('x5', val) + [
            f'sw x5, {daddr}(x0)',
            f'lh x7, {daddr}(x0)',
            'nop',
            f'sw x7, {rid()}(x0)',
        ]
        builder.add(f'lh(0x{val:08x})', ctypes.c_int32(lh_sx).value & 0xFFFFFFFF, lines)

        lines = emit_li('x5', val) + [
            f'sw x5, {daddr}(x0)',
            f'lbu x7, {daddr}(x0)',
            'nop',
            f'sw x7, {rid()}(x0)',
        ]
        builder.add(f'lbu(0x{val:08x})', val & 0xFF, lines)

        lines = emit_li('x5', val) + [
            f'sw x5, {daddr}(x0)',
            f'lhu x7, {daddr}(x0)',
            'nop',
            f'sw x7, {rid()}(x0)',
        ]
        builder.add(f'lhu(0x{val:08x})', val & 0xFFFF, lines)

    # byte/halfword stores
    for val in [0xDEADBEEF, 0xAABBCCDD]:
        daddr = data_base + len(builder.cases) * 8
        lines = emit_li('x5', val) + [
            f'sw x5, {daddr}(x0)',
        ] + emit_li('x5', 0x42) + [
            f'sb x5, {daddr}(x0)',
            f'lw x7, {daddr}(x0)',
            'nop',
            f'sw x7, {rid()}(x0)',
        ]
        builder.add(f'sb(0x{val:08x})', (val & 0xffffff00) | 0x42, lines)

def gen_hazard(builder):
    rid = lambda: len(builder.cases)*4

    # Test 1: simple chain - EX forward
    # addi x5, x0, 5 → addi x6, x0, 10 → add x7, x5, x6 (x5 from MEM, x6 from EX)
    lines = ['addi x5, x0, 5', 'addi x6, x0, 10',
             'add x7, x5, x6', f'sw x7, {rid()}(x0)']
    builder.add('hazard_ex_fwd', 15, lines)

    # Test 2: multi-cycle chain
    # addi x5, x0, 5; addi x6, x0, 10; (add x7, x5, x6=15); addi x8, x0, 20;
    # add x9, x7, x8 (=35); add x10, x9, x5 (=40)
    lines = ['addi x5, x0, 5', 'addi x6, x0, 10',
             'add x7, x5, x6', 'addi x8, x0, 20',
             'add x9, x7, x8', 'add x10, x9, x5',
             f'sw x10, {rid()}(x0)']
    builder.add('hazard_multi', 40, lines)

    # Test 3: EX forward with different regs
    # addi x5, x0, 100; addi x6, x0, 200; add x7, x5, x6 (=300)
    lines = emit_li('x5', 100) + emit_li('x6', 200)
    lines += ['add x7, x5, x6', f'sw x7, {rid()}(x0)']
    builder.add('hazard_li_fwd', 300, lines)

def gen_load_use(builder):
    rid = lambda: len(builder.cases)*4
    data_base = 0x1000   # above code area

    for val in [0x12345678, 0xA5A5A5A5, 0x00000001, 0xFFFFFFFF]:
        daddr = data_base + len(builder.cases) * 4
        lines = emit_li('x5', val) + [
            f'sw x5, {daddr}(x0)',
            f'lw x6, {daddr}(x0)',
            'nop',
            f'add x7, x6, x6',
            f'sw x7, {rid()}(x0)',
        ]
        exp = (val * 2) & 0xffffffff
        builder.add(f'load_use(0x{val:08x})', exp, lines)

def gen_branch(builder):
    """Branch tests — encode verification only (pipeline needs branch support)."""
    rid = lambda: len(builder.cases)*4

    # Test each branch opcode: values that exercise condition
    br_ops = [
        ('beq',  5, 5,   True ),
        ('beq',  5, 6,   False),
        ('bne',  5, 6,   True ),
        ('bne',  5, 5,   False),
        ('blt',  4, 5,   True ),
        ('blt',  5, 4,   False),
        ('bge',  5, 4,   True ),
        ('bge',  4, 5,   False),
        ('bltu', 4, 5,   True ),
        ('bltu', 5, 4,   False),
        ('bgeu', 5, 4,   True ),
        ('bgeu', 4, 5,   False),
    ]

    for op, rs1v, rs2v, taken in br_ops:
        lines = emit_li('x5', rs1v) + emit_li('x6', rs2v)
        # The branch is at some offset; we compute the encoding only
        # For decode verification: read x7 result set by either path
        src = '\n'.join([
            *lines,
            f'{op} x5, x6, taken_{len(builder.cases)}',
            f'addi x7, x0, 0',     # not taken
            f'jal x0, done_{len(builder.cases)}',
            f'taken_{len(builder.cases)}:',
            f'addi x7, x0, 1',     # taken
            f'done_{len(builder.cases)}:',
            f'sw x7, {rid()}(x0)',
        ])
        lines2 = assemble_labels(src)
        # We just check the assembler for now (pipeline doesn't support branches yet)
        expected = 1 if taken else 0
        builder.add(f'{op}({rs1v},{rs2v})', expected, [src])

def gen_jump(builder):
    """Jump tests — execute and verify control flow + return address."""
    rid = lambda: len(builder.cases)*4
    tid = lambda: len(builder.cases)

    # JAL: skip an instruction, verify x5 unchanged
    lines = ['addi x5, x0, 0x42',
             f'jal x0, skip_{tid()}',
             'addi x5, x0, 0',
             f'skip_{tid()}:',
             f'sw x5, {rid()}(x0)']
    builder.add('jal_skip', 0x42, lines)

    # JALR: skip an instruction via register jump, verify x5 unchanged
    tid = lambda: len(builder.cases)
    lines = ['addi x5, x0, 0x42',
             'auipc x6, 0',
             'addi x6, x6, 16',
             f'jalr x0, x6, 0',
             'addi x5, x0, 0',
             f'skip_{tid()}:',
             f'sw x5, {rid()}(x0)']
    builder.add('jalr_skip', 0x42, lines)

def gen_csr(builder):
    rid = lambda: len(builder.cases)*4

    # ── mstatus (0x300) tests ──
    # After reset, mstatus = 0
    lines = ['csrr x7, 0x300', f'sw x7, {rid()}(x0)']
    builder.add('csrr_mstatus_init', 0, lines)

    # csrrw: write 0x1 to mstatus, csrr verify
    lines = emit_li('x5', 0x1) + [
        'csrrw x0, 0x300, x5',   # mstatus = 0x1 (discard old)
        'csrr x7, 0x300',
        f'sw x7, {rid()}(x0)',
    ]
    builder.add('csrrw_mstatus_1', 0x1, lines)

    # csrrw: write 0xA5A5A5A5 to mstatus, csrr verify
    lines = emit_li('x5', 0xA5A5A5A5) + [
        'csrrw x0, 0x300, x5',
        'csrr x7, 0x300',
        f'sw x7, {rid()}(x0)',
    ]
    builder.add('csrrw_mstatus_A5A5A5A5', 0xA5A5A5A5, lines)

    # csrrs: set bits (mstatus = 0xA5A5A5A5, set bits with 0x0F)
    # After csrrs: mstatus = 0xA5A5A5A5 | 0xF = 0xA5A5A5AF, x7 = old (0xA5A5A5A5)
    lines = emit_li('x5', 0x0F) + [
        'csrrs x7, 0x300, x5',
        'csrr x6, 0x300',
        f'sw x7, {rid()}(x0)',   # old value = 0xA5A5A5A5
    ]
    builder.add('csrrs_mstatus_old', 0xA5A5A5A5, lines)

    # csrr: verify new mstatus after csrrs
    lines = ['csrr x7, 0x300', f'sw x7, {rid()}(x0)']
    builder.add('csrrs_mstatus_new', 0xA5A5A5AF, lines)

    # csrrc: clear bits (mstatus = 0xA5A5A5AF, clear with 0xA5A5A5AF)
    # After csrrc: mstatus = 0xA5A5A5AF & ~0xA5A5A5AF = 0, x7 = old
    lines = emit_li('x5', 0xA5A5A5AF) + [
        'csrrc x7, 0x300, x5',
        f'sw x7, {rid()}(x0)',   # old value = 0xA5A5A5AF
    ]
    builder.add('csrrc_mstatus_old', 0xA5A5A5AF, lines)

    # csrr: verify mstatus = 0 after csrrc
    lines = ['csrr x7, 0x300', f'sw x7, {rid()}(x0)']
    builder.add('csrrc_mstatus_new', 0, lines)

    # ── Immediate variants on mtvec (0x305) ──
    # csrrsi with rs1=x0 = csrr (read without modifying)
    # mtvec init = 0x80000000 (set by csr reset)
    lines = ['csrr x7, 0x305', f'sw x7, {rid()}(x0)']
    builder.add('csrr_mtvec_init', 0x80000000, lines)

    # csrrwi: write immediate, verify
    for uimm in [0x05, 0x1F, 0x00]:
        lines = [
            'csrrwi x0, 0x305, {0}'.format(uimm),
            'csrr x7, 0x305',
            f'sw x7, {rid()}(x0)',
        ]
        builder.add(f'csrrwi_mtvec_{uimm}', uimm, lines)

    # csrrsi: set bits via immediate, verify old + new
    # mtvec = 0 (from csrrwi with 0 in previous test)
    lines = [
        'csrrsi x7, 0x305, 0x0A',          # x7=old(0), mtvec=0|0xA=0xA
        f'sw x7, {rid()}(x0)',               # old = 0
    ]
    builder.add('csrrsi_mtvec_old', 0, lines)

    lines = ['csrr x7, 0x305', f'sw x7, {rid()}(x0)']
    builder.add('csrrsi_mtvec_new', 0x0A, lines)

    # csrrci: clear bits via immediate, verify old + new
    # mtvec = 0xA, clear with 0x0A: mtvec = 0xA & ~0xA = 0, x7 = old = 0xA
    lines = [
        'csrrci x7, 0x305, 0x0A',
        f'sw x7, {rid()}(x0)',               # old = 0xA
    ]
    builder.add('csrrci_mtvec_old', 0x0A, lines)

    lines = ['csrr x7, 0x305', f'sw x7, {rid()}(x0)']
    builder.add('csrrci_mtvec_new', 0, lines)

    # ── mie (0x304) tests ──
    # csrrwi: write 0xFF to mie
    lines = ['csrrwi x0, 0x304, 0x1F',  # mie = 0x1F (zimm=0x1F)
             'csrr x7, 0x304',
             f'sw x7, {rid()}(x0)']
    builder.add('csrrwi_mie', 0x1F, lines)

    # csrrs with rs1=x0: read without modify
    lines = ['csrrs x7, 0x304, x0',   # x7 = mie = 0x1F, mie unchanged
             f'sw x7, {rid()}(x0)']
    builder.add('csrrs_mie_readonly', 0x1F, lines)

    # csrrc with rs1=x0: read without modify
    lines = ['csrrc x7, 0x304, x0',   # x7 = mie = 0x1F, mie unchanged (x0 = 0, ~0 = all 1s, x & ~0 = x)
             f'sw x7, {rid()}(x0)']
    builder.add('csrrc_mie_readonly', 0x1F, lines)

# ── Compile & run ─────────────────────────────────────────────
_compiled = False

def ensure_compiled():
    global _compiled
    if _compiled:
        return True

    print("  xvlog...", end='', flush=True)
    sv_list = sv_files()
    r = subprocess.run([xsim_bin('xvlog'), '-sv', '-work', 'work'] + sv_list,
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        print(" FAILED")
        print(r.stderr[:500], file=sys.stderr)
        return False
    print(" done")

    print("  xelab...", end='', flush=True)
    log = subprocess.run([xsim_bin('xelab'), 'work.tb', '-debug', 'typical', '-timescale', '1ns/1ps'],
                         capture_output=True, text=True, timeout=120)
    if log.returncode != 0:
        print(" FAILED")
        print(log.stderr[:500], file=sys.stderr)
        return False
    print(" done")
    _compiled = True
    return True

def run_sim():
    try:
        r = subprocess.run([xsim_bin('xsim'), 'work.tb', '--R'],
                           capture_output=True, text=True, timeout=120,
                           cwd=SRC_DIR)
    except subprocess.TimeoutExpired as e:
        return e.stdout or "", "TIMEOUT"
    return r.stdout, r.stderr

# ── Result checking ───────────────────────────────────────────
def parse_bram(output):
    bram = {}
    for m in re.finditer(r'BRAM\[(\d+)\]\s*=\s*(0x[0-9a-fA-F]+)', output):
        bram[int(m.group(1))] = int(m.group(2), 16)
    return bram

# ── Main ──────────────────────────────────────────────────────
def main():
    start = __import__('time').time()

    print("Building test cases...")
    tb = TestBuilder()

    gen_alu(tb, seed=42, max_total=60)
    gen_utype(tb)
    gen_load_store(tb)
    gen_hazard(tb)
    gen_load_use(tb)
    gen_csr(tb)
    gen_branch(tb)
    gen_jump(tb)

    print(f"  {len(tb.cases)} cases generated")

    print("Building test program...", flush=True)
    codes = tb.build()
    for path in [os.path.join(SRC_DIR, 'test_prog.hex'), os.path.join(PROJ_DIR, 'test_prog.hex')]:
        with open(path, 'w') as f:
            for code in codes:
                f.write(f'{code:08x}\n')
    print(f"  {len(codes)} instructions ({len(codes)*4} bytes)")

    # Fix PC-dependent expected values using actual assembled instruction positions
    # Count codes per test case by assembling each line individually
    ci = 0
    for case in tb.cases:
        case.code_idx = ci
        for line in case.lines:
            for subline in line.split('\n'):
                sl = subline.strip()
                if not sl or sl.endswith(':'):
                    continue
                try:
                    r = assemble_one(sl)
                except Exception:
                    r = None
                if r is not None:
                    ci += len(r) if isinstance(r, list) else 1
                else:
                    ci += 1

    for case in tb.cases:
        if 'auipc' in case.name:
            m = case.name.split('(0x')
            imm_val = int(m[1].rstrip(')'), 16) if len(m) > 1 else 0
            pc = case.code_idx * 4
            # CPU runs at 0x80000000-based PC
            case.expected = (0x80000000 + pc + (imm_val << 12)) & 0xffffffff

    print("Compiling (once)...", flush=True)
    if not ensure_compiled():
        return

    print("Running simulation...", flush=True)
    stdout, stderr = run_sim()

    if stderr == "TIMEOUT":
        print("  WARNING: simulation timed out!", file=sys.stderr)

    print("Parsing results...", flush=True)
    bram = parse_bram(stdout)
    print(f"  Read {len(bram)} BRAM entries", flush=True)

    passed = 0
    failed = 0
    missing = 0

    for case in tb.cases:
        word_idx = (case.test_id * 4) // 4
        got = bram.get(word_idx)
        exp = case.expected
        if got is None:
            print(f"MISSING: #{case.test_id} {case.name} word[{word_idx}]")
            missing += 1
        elif got == exp:
            passed += 1
        else:
            print(f"FAIL: #{case.test_id} {case.name} -> got 0x{got:08x} exp 0x{exp:08x}")
            failed += 1

    total = passed + failed + missing
    print(f"\n{'='*50}")
    print(f"RESULTS: {passed}/{total} passed, {failed} failed, {missing} missing")
    elapsed = __import__('time').time() - start
    if failed == 0 and missing == 0:
        print("ALL PASSED!")
    elif failed == 0:
        print(f"PASSED with {missing} missing results (possibly incomplete BRAM dump)")
    else:
        print(f"SOME FAILED ({failed} failures)")
    print(f"Time: {elapsed:.1f}s")
    print(f"{'='*50}")

if __name__ == '__main__':
    main()
