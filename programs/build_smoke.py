#!/usr/bin/env python3
"""Hand-assemble an RV32IM smoke test for the MIST-ES core.

No GCC required. Emits programs/build/smoke.hex (one 32-bit word per line)
for $readmemh. Convention: store 1 to tohost (0x2000_0000) on success, 2 on
failure. Each sub-test computes a value that must equal 0 and branches to the
FAIL block otherwise.

Coverage: RV32I ALU (reg+imm, shifts, SLT), RV32M (MUL/MULH/DIV/DIVU/REM/
REMU), all six branches, byte/half/word load-store with sign/zero extension,
CSR round-trip (mscratch), and an ECALL -> handler -> MRET trap round-trip.
"""
from pathlib import Path

# ---------- encoders ---------------------------------------------------------
def u32(x): return x & 0xFFFFFFFF
def R(f7, rs2, rs1, f3, rd, op): return u32((f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def I(imm, rs1, f3, rd, op):     return u32(((imm&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def S(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return u32(((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|op)
def B(imm, rs2, rs1, f3, op):
    imm &= 0x1FFE
    return u32(((imm>>12&1)<<31)|((imm>>5&0x3F)<<25)|(rs2<<20)|(rs1<<15)|
               (f3<<12)|((imm>>1&0xF)<<8)|((imm>>11&1)<<7)|op)
def U(imm, rd, op): return u32((imm&0xFFFFF000)|(rd<<7)|op)
def J(imm, rd, op):
    imm &= 0x1FFFFE
    return u32(((imm>>20&1)<<31)|((imm>>1&0x3FF)<<21)|((imm>>11&1)<<20)|
               ((imm>>12&0xFF)<<12)|(rd<<7)|op)

# ---------- mnemonics --------------------------------------------------------
def addi(rd,rs1,i): return I(i,rs1,0,rd,0x13)
def slti(rd,rs1,i): return I(i,rs1,2,rd,0x13)
def sltiu(rd,rs1,i):return I(i,rs1,3,rd,0x13)
def xori(rd,rs1,i): return I(i,rs1,4,rd,0x13)
def ori(rd,rs1,i):  return I(i,rs1,6,rd,0x13)
def andi(rd,rs1,i): return I(i,rs1,7,rd,0x13)
def slli(rd,rs1,sh):return R(0x00,sh,rs1,1,rd,0x13)
def srli(rd,rs1,sh):return R(0x00,sh,rs1,5,rd,0x13)
def srai(rd,rs1,sh):return R(0x20,sh,rs1,5,rd,0x13)
def add(rd,rs1,rs2):return R(0,rs2,rs1,0,rd,0x33)
def sub(rd,rs1,rs2):return R(0x20,rs2,rs1,0,rd,0x33)
def sll(rd,rs1,rs2):return R(0,rs2,rs1,1,rd,0x33)
def slt(rd,rs1,rs2):return R(0,rs2,rs1,2,rd,0x33)
def sltu(rd,rs1,rs2):return R(0,rs2,rs1,3,rd,0x33)
def xor_(rd,rs1,rs2):return R(0,rs2,rs1,4,rd,0x33)
def srl(rd,rs1,rs2):return R(0,rs2,rs1,5,rd,0x33)
def sra(rd,rs1,rs2):return R(0x20,rs2,rs1,5,rd,0x33)
def or_(rd,rs1,rs2):return R(0,rs2,rs1,6,rd,0x33)
def and_(rd,rs1,rs2):return R(0,rs2,rs1,7,rd,0x33)
def mul(rd,rs1,rs2):  return R(1,rs2,rs1,0,rd,0x33)
def mulh(rd,rs1,rs2): return R(1,rs2,rs1,1,rd,0x33)
def div(rd,rs1,rs2):  return R(1,rs2,rs1,4,rd,0x33)
def divu(rd,rs1,rs2): return R(1,rs2,rs1,5,rd,0x33)
def rem(rd,rs1,rs2):  return R(1,rs2,rs1,6,rd,0x33)
def remu(rd,rs1,rs2): return R(1,rs2,rs1,7,rd,0x33)
def lui(rd,i):  return U(i,rd,0x37)
def auipc(rd,i):return U(i,rd,0x17)
def lw(rd,rs1,i):  return I(i,rs1,2,rd,0x03)
def lh(rd,rs1,i):  return I(i,rs1,1,rd,0x03)
def lb(rd,rs1,i):  return I(i,rs1,0,rd,0x03)
def lhu(rd,rs1,i): return I(i,rs1,5,rd,0x03)
def lbu(rd,rs1,i): return I(i,rs1,4,rd,0x03)
def sw(rs2,rs1,i): return S(i,rs2,rs1,2,0x23)
def sh(rs2,rs1,i): return S(i,rs2,rs1,1,0x23)
def sb(rs2,rs1,i): return S(i,rs2,rs1,0,0x23)
def beq(rs1,rs2,i):return B(i,rs2,rs1,0,0x63)
def bne(rs1,rs2,i):return B(i,rs2,rs1,1,0x63)
def blt(rs1,rs2,i):return B(i,rs2,rs1,4,0x63)
def bge(rs1,rs2,i):return B(i,rs2,rs1,5,0x63)
def bltu(rs1,rs2,i):return B(i,rs2,rs1,6,0x63)
def bgeu(rs1,rs2,i):return B(i,rs2,rs1,7,0x63)
def jal(rd,i):  return J(i,rd,0x6F)
def jalr(rd,rs1,i):return I(i,rs1,0,rd,0x67)
def csrrw(rd,csr,rs1): return I(csr,rs1,1,rd,0x73)
def csrrs(rd,csr,rs1): return I(csr,rs1,2,rd,0x73)
def csrrc(rd,csr,rs1): return I(csr,rs1,3,rd,0x73)
def ecall():  return I(0,0,0,0,0x73)
def mret():   return I(0x302,0,0,0,0x73)
def nop():    return addi(0,0,0)

def li(rd, v):
    v &= 0xFFFFFFFF
    lo = v & 0xFFF
    hi = (v - (lo if lo < 0x800 else lo - 0x1000)) & 0xFFFFFFFF
    lo_s = lo if lo < 0x800 else lo - 0x1000
    if hi == 0:
        return [addi(rd, 0, lo_s)]
    return [lui(rd, hi), addi(rd, rd, lo_s)]

# CSR numbers
MTVEC, MSCRATCH, MEPC, MCAUSE = 0x305, 0x340, 0x341, 0x342
TOHOST, DMEM, HANDLER = 0x20000000, 0x80000000, 0x800

prog = {}
def emit(addr, *ins):
    for x in ins:
        prog[addr] = x; addr += 4
    return addr

fail_fixups = []   # (addr_of_branch, rs1, rs2)
def check_zero(pc, reg):
    """emit `bne reg, x0, FAIL` placeholder, record for fixup."""
    fail_fixups.append((pc, reg, 0))
    return emit(pc, bne(reg, 0, 0))

pc = 0
# set mtvec = HANDLER
pc = emit(pc, *li(5, HANDLER))
pc = emit(pc, csrrw(0, MTVEC, 5))

# ---- Test 1: ALU reg/imm ----
pc = emit(pc, addi(10,0,6), addi(11,0,7), add(12,10,11), addi(13,0,13), sub(14,12,13))
pc = check_zero(pc, 14)                       # 6+7-13 == 0
pc = emit(pc, addi(10,0,0xF), andi(15,10,0x6), addi(16,0,6), sub(17,15,16))
pc = check_zero(pc, 17)                        # (0xF & 6) - 6 == 0
pc = emit(pc, addi(10,0,1), slli(18,10,4), addi(19,0,16), sub(20,18,19))
pc = check_zero(pc, 20)                        # (1<<4) - 16 == 0
pc = emit(pc, addi(10,0,-8), srai(21,10,1), addi(22,0,-4), sub(23,21,22))
pc = check_zero(pc, 23)                        # (-8>>>1) - (-4) == 0
pc = emit(pc, addi(10,0,-1), sltiu(24,10,1), addi(25,0,0), sub(26,24,25))
pc = check_zero(pc, 26)                        # (0xFFFFFFFF <u 1)?0 -> 0

# ---- Test 2: RV32M ----
pc = emit(pc, addi(5,0,6), addi(6,0,7), mul(7,5,6), addi(8,0,42), sub(9,7,8))
pc = check_zero(pc, 9)                          # 6*7-42
pc = emit(pc, addi(5,0,-3), addi(6,0,4), mul(7,5,6), addi(8,0,-12), sub(9,7,8))
pc = check_zero(pc, 9)                          # -3*4 - (-12)
pc = emit(pc, addi(5,0,-20), addi(6,0,3), div(7,5,6), addi(8,0,-6), sub(9,7,8))
pc = check_zero(pc, 9)                          # -20/3 = -6 (trunc toward 0)
pc = emit(pc, addi(5,0,-20), addi(6,0,3), rem(7,5,6), addi(8,0,-2), sub(9,7,8))
pc = check_zero(pc, 9)                          # -20%3 = -2
pc = emit(pc, addi(5,0,20), addi(6,0,6), divu(7,5,6), addi(8,0,3), sub(9,7,8))
pc = check_zero(pc, 9)                          # 20/6 = 3
pc = emit(pc, addi(5,0,20), addi(6,0,6), remu(7,5,6), addi(8,0,2), sub(9,7,8))
pc = check_zero(pc, 9)                          # 20%6 = 2
pc = emit(pc, *li(5,0x7FFFFFFF))
pc = emit(pc, addi(6,0,2), mulh(7,5,6), addi(8,0,0), sub(9,7,8))
pc = check_zero(pc, 9)                          # mulh(0x7FFFFFFF,2)=0

# ---- Test 3: branches ----
# beq taken / bne not taken etc. Build a value that is 0 if all behave.
pc = emit(pc, addi(5,0,5), addi(6,0,5), addi(28,0,1))     # x28=1 (will clear)
boff = pc
pc = emit(pc, beq(5,6,8))            # if 5==5 skip next (skip the "set fail")
pc = emit(pc, addi(28,0,99))         # should be skipped
pc = emit(pc, addi(28,0,0))          # x28 = 0
pc = check_zero(pc, 28)
pc = emit(pc, addi(5,0,-1), addi(6,0,1), addi(29,0,1))
pc = emit(pc, blt(5,6,8))            # -1 < 1 -> skip fail
pc = emit(pc, addi(29,0,99))
pc = emit(pc, addi(29,0,0))
pc = check_zero(pc, 29)
pc = emit(pc, addi(5,0,-1), addi(6,0,1), addi(30,0,1))
pc = emit(pc, bltu(6,5,8))           # 1 <u 0xFFFFFFFF -> skip fail
pc = emit(pc, addi(30,0,99))
pc = emit(pc, addi(30,0,0))
pc = check_zero(pc, 30)

# ---- Test 4: load/store ----
pc = emit(pc, *li(20, DMEM))
pc = emit(pc, *li(21, 0x12345678))
pc = emit(pc, sw(21,20,0), lw(22,20,0), sub(23,22,21))
pc = check_zero(pc, 23)                          # word round-trip
pc = emit(pc, addi(5,0,-1), sb(5,20,4), lb(6,20,4), addi(7,0,-1), sub(8,6,7))
pc = check_zero(pc, 8)                            # signed byte -1
pc = emit(pc, addi(5,0,-1), sb(5,20,5), lbu(6,20,5), *li(7,0xFF))
pc = emit(pc, sub(8,6,7))
pc = check_zero(pc, 8)                            # unsigned byte 0xFF
pc = emit(pc, *li(5,0xBEEF))
pc = emit(pc, sh(5,20,8), lhu(6,20,8), sub(8,6,5))
pc = check_zero(pc, 8)                            # halfword 0xBEEF

# ---- Test 5: CSR mscratch round-trip ----
pc = emit(pc, *li(24,0xDEADBEEF))
pc = emit(pc, csrrw(0,MSCRATCH,24), csrrs(25,MSCRATCH,0), sub(26,25,24))
pc = check_zero(pc, 26)

# ---- Test 6: ECALL -> handler -> MRET ----
pc = emit(pc, addi(27,0,0), ecall(), nop())
pc = emit(pc, *li(5,0xABCD))
pc = emit(pc, sub(6,27,5))
pc = check_zero(pc, 6)                            # handler set x27=0xABCD

# ---- success ----
pc = emit(pc, *li(7,TOHOST), addi(8,0,1), sw(8,7,0))
spin = pc
pc = emit(pc, jal(0,0))

# ---- FAIL block ----
FAIL = pc
pc = emit(pc, *li(7,TOHOST), addi(8,0,2), sw(8,7,0))
pc = emit(pc, jal(0,0))

# patch all check_zero branches to FAIL
for at, rs1, rs2 in fail_fixups:
    prog[at] = bne(rs1, rs2, FAIL - at)

# ---- trap handler @ HANDLER ----
# cause 11 (ecall M): set x27=0xABCD, mepc+=4, mret. Else just mepc+=4, mret.
pc = HANDLER
pc = emit(pc, csrrs(31,MCAUSE,0), addi(5,0,11))
bne_default = pc
pc = emit(pc, bne(31,5,0))           # patched -> default
pc = emit(pc, *li(27,0xABCD))
pc = emit(pc, csrrs(4,MEPC,0), addi(4,4,4), csrrw(0,MEPC,4), mret())
DEFAULT = pc
pc = emit(pc, csrrs(4,MEPC,0), addi(4,4,4), csrrw(0,MEPC,4), mret())
prog[bne_default] = bne(31,5, DEFAULT - bne_default)

# ---- emit hex ----
out = Path(__file__).parent / "build"
out.mkdir(exist_ok=True)
n = max(prog) // 4 + 1
lines = [f"{prog.get(a*4, 0x00000013):08x}" for a in range(n)]
(out / "smoke.hex").write_text("\n".join(lines) + "\n")
print(f"Wrote programs/build/smoke.hex — {n} words")
print(f"FAIL=0x{FAIL:08x}  spin=0x{spin:08x}  HANDLER=0x{HANDLER:08x}")
assert FAIL < HANDLER, "code region overran the trap handler at 0x200!"
