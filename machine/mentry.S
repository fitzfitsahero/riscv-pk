// See LICENSE for license details.

#include "mtrap.h"
#include "bits.h"
#include "config.h"

  .data
  .align 6
trap_table:
#define BAD_TRAP_VECTOR 0
  /* 00 */ .dc.a bad_trap
  /* 01 */ .dc.a pmp_trap
  /* 02 */ .dc.a illegal_insn_trap
  /* 03 */ .dc.a bad_trap
  /* 04 */ .dc.a misaligned_load_trap
  /* 05 */ .dc.a pmp_trap
  /* 06 */ .dc.a misaligned_store_trap
  /* 07 */ .dc.a pmp_trap
  /* 08 */ .dc.a bad_trap
  /* 09 */ .dc.a mcall_trap
  /* 10 */ .dc.a bad_trap
#ifdef BBL_BOOT_MACHINE
  /* 11 */ .dc.a mcall_trap
#else
  /* 11 */ .dc.a bad_trap
#endif /* BBL_BOOT_MACHINE */
  /* 12 */ .dc.a bad_trap
#define TRAP_FROM_MACHINE_MODE_VECTOR 13
  /* 13 */ .dc.a __trap_from_machine_mode
  /* 14 */ .dc.a bad_trap
  /* 15 */ .dc.a bad_trap
  /* 16 */ .dc.a bad_trap
  /* 17 */ .dc.a bad_trap
  /* 18 */ .dc.a bad_trap

  .option norvc
  .section .text.init,"ax",@progbits
  .globl reset_vector
reset_vector:
  j do_reset

trap_vector:
  csrrw sp, mscratch, sp
  beqz sp, .Ltrap_from_machine_mode

  STORE a0, 10*REGBYTES(sp)
  STORE a1, 11*REGBYTES(sp)

  csrr a1, mcause
  bgez a1, .Lhandle_trap_in_machine_mode

  # This is an interrupt.  Discard the mcause MSB and decode the rest.
  sll a1, a1, 1

  # Is it a machine timer interrupt?
  li a0, IRQ_M_TIMER * 2
  bne a0, a1, 1f

  # Yes.  Simply clear MTIE and raise STIP.
  li a0, MIP_MTIP
  csrc mie, a0
  li a0, MIP_STIP
  csrs mip, a0

.Lmret:
  # Go back whence we came.
  LOAD a0, 10*REGBYTES(sp)
  LOAD a1, 11*REGBYTES(sp)
  csrrw sp, mscratch, sp
  mret

1:
  # Is it an IPI?
  li a0, IRQ_M_SOFT * 2
  bne a0, a1, .Lbad_trap

  # Yes.  First, clear the MIPI bit.
  LOAD a0, MENTRY_IPI_OFFSET(sp)
  sw x0, (a0)
  fence

  # Now, decode the cause(s).
#ifdef __riscv_atomic
  addi a0, sp, MENTRY_IPI_PENDING_OFFSET
  amoswap.w a0, x0, (a0)
#else
  lw a0, MENTRY_IPI_PENDING_OFFSET(sp)
  sw x0, MENTRY_IPI_PENDING_OFFSET(sp)
#endif
  and a1, a0, IPI_SOFT
  beqz a1, 1f
  csrs mip, MIP_SSIP
1:
  andi a1, a0, IPI_FENCE_I
  beqz a1, 1f
  fence.i
1:
  andi a1, a0, IPI_SFENCE_VMA
  beqz a1, 1f
  sfence.vma
1:
  andi a1, a0, IPI_HALT
  beqz a1, 1f
  wfi
  j 1b
1:
  j .Lmret


.Lhandle_trap_in_machine_mode:
  # Preserve the registers.  Compute the address of the trap handler.
  STORE ra, 1*REGBYTES(sp)
  STORE gp, 3*REGBYTES(sp)
  STORE tp, 4*REGBYTES(sp)
  STORE t0, 5*REGBYTES(sp)
1:auipc t0, %pcrel_hi(trap_table)  # t0 <- %hi(trap_table)
  STORE t1, 6*REGBYTES(sp)
  sll t1, a1, LOG_REGBYTES         # t1 <- mcause * ptr size
  STORE t2, 7*REGBYTES(sp)
  add t1, t0, t1                   # t1 <- %hi(trap_table)[mcause]
  STORE s0, 8*REGBYTES(sp)
  LOAD t1, %pcrel_lo(1b)(t1)       # t1 <- trap_table[mcause]
  STORE s1, 9*REGBYTES(sp)
  mv a0, sp                        # a0 <- regs
  STORE a2,12*REGBYTES(sp)
  csrr a2, mepc                    # a2 <- mepc
  STORE a3,13*REGBYTES(sp)
  csrrw t0, mscratch, x0           # t0 <- user sp
  STORE a4,14*REGBYTES(sp)
  STORE a5,15*REGBYTES(sp)
  STORE a6,16*REGBYTES(sp)
  STORE a7,17*REGBYTES(sp)
  STORE s2,18*REGBYTES(sp)
  STORE s3,19*REGBYTES(sp)
  STORE s4,20*REGBYTES(sp)
  STORE s5,21*REGBYTES(sp)
  STORE s6,22*REGBYTES(sp)
  STORE s7,23*REGBYTES(sp)
  STORE s8,24*REGBYTES(sp)
  STORE s9,25*REGBYTES(sp)
  STORE s10,26*REGBYTES(sp)
  STORE s11,27*REGBYTES(sp)
  STORE t3,28*REGBYTES(sp)
  STORE t4,29*REGBYTES(sp)
  STORE t5,30*REGBYTES(sp)
  STORE t6,31*REGBYTES(sp)
  STORE t0, 2*REGBYTES(sp)         # sp

#ifndef __riscv_flen
  lw tp, (sp) # Move the emulated FCSR from x0's save slot into tp.
#endif
  STORE x0, (sp) # Zero x0's save slot.

  # Invoke the handler.
  jalr t1

#ifndef __riscv_flen
  sw tp, (sp) # Move the emulated FCSR from tp into x0's save slot.
#endif

restore_mscratch:
  # Restore mscratch, so future traps will know they didn't come from M-mode.
  csrw mscratch, sp

restore_regs:
  # Restore all of the registers.
  LOAD ra, 1*REGBYTES(sp)
  LOAD gp, 3*REGBYTES(sp)
  LOAD tp, 4*REGBYTES(sp)
  LOAD t0, 5*REGBYTES(sp)
  LOAD t1, 6*REGBYTES(sp)
  LOAD t2, 7*REGBYTES(sp)
  LOAD s0, 8*REGBYTES(sp)
  LOAD s1, 9*REGBYTES(sp)
  LOAD a0,10*REGBYTES(sp)
  LOAD a1,11*REGBYTES(sp)
  LOAD a2,12*REGBYTES(sp)
  LOAD a3,13*REGBYTES(sp)
  LOAD a4,14*REGBYTES(sp)
  LOAD a5,15*REGBYTES(sp)
  LOAD a6,16*REGBYTES(sp)
  LOAD a7,17*REGBYTES(sp)
  LOAD s2,18*REGBYTES(sp)
  LOAD s3,19*REGBYTES(sp)
  LOAD s4,20*REGBYTES(sp)
  LOAD s5,21*REGBYTES(sp)
  LOAD s6,22*REGBYTES(sp)
  LOAD s7,23*REGBYTES(sp)
  LOAD s8,24*REGBYTES(sp)
  LOAD s9,25*REGBYTES(sp)
  LOAD s10,26*REGBYTES(sp)
  LOAD s11,27*REGBYTES(sp)
  LOAD t3,28*REGBYTES(sp)
  LOAD t4,29*REGBYTES(sp)
  LOAD t5,30*REGBYTES(sp)
  LOAD t6,31*REGBYTES(sp)
  LOAD sp, 2*REGBYTES(sp)
  mret

.Ltrap_from_machine_mode:
  csrr sp, mscratch
  addi sp, sp, -INTEGER_CONTEXT_SIZE
  STORE a0,10*REGBYTES(sp)
  STORE a1,11*REGBYTES(sp)
  li a1, TRAP_FROM_MACHINE_MODE_VECTOR
  j .Lhandle_trap_in_machine_mode

.Lbad_trap:
  li a1, BAD_TRAP_VECTOR
  j .Lhandle_trap_in_machine_mode

  .globl __redirect_trap
__redirect_trap:
  # reset sp to top of M-mode stack
  li t0, MACHINE_STACK_SIZE
  add sp, sp, t0
  neg t0, t0
  and sp, sp, t0
  addi sp, sp, -MENTRY_FRAME_SIZE
  j restore_mscratch

__trap_from_machine_mode:
  jal trap_from_machine_mode
  j restore_regs

#define HTIF_TOHOST 0x40008000

putstring:
  li a2, HTIF_TOHOST
  li a3, (1 << 24) | (1 << 16)
1:
  lbu a1, (a0)
  beqz a1, 2f
/* Note: we use 32 bit accesses to work in all base isa modes */
  sw a1, 0(a2)
  sw a3, 4(a2)
/* wait until the char is handled */
3:
  lw a1, 0(a2)
  lw a4, 4(a2)
  or a1, a1, a4
  bnez a1, 3b
  addi a0, a0, 1
  j 1b
2:
  ret
fatal_error:
  jal putstring
  # exit the emulator if possible
  li a2, HTIF_TOHOST
  li a1, 1
  sw a1, 0(a2)
  sw zero, 4(a2)
1:
  wfi
  j 1b

rv32_expected_str:
  .asciz "Must run this program on a 32 bit RISCV CPU - aborting\n"
rv64_expected_str:
  .asciz "Must run this program on a 64 bit RISCV CPU - aborting\n"
rv128_expected_str:
  .asciz "128 bit RISCV CPU detected: setting XLEN to 64 bits\n"
  .align 4

do_reset:
  li x1, 0
  li x2, 0
  li x3, 0
  li x4, 0
  li x5, 0
  li x6, 0
  li x7, 0
  li x8, 0
  li x9, 0
// save a0 and a1; arguments from previous boot loader stage:
//  li x10, 0
//  li x11, 0
  li x12, 0
  li x13, 0
  li x14, 0
  li x15, 0
  li x16, 0
  li x17, 0
  li x18, 0
  li x19, 0
  li x20, 0
  li x21, 0
  li x22, 0
  li x23, 0
  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x29, 0
  li x30, 0
  li x31, 0
  csrw mscratch, x0

  # check MXL value and abort if it is not what we expect
  mv s0, a0
  mv s1, a1
  csrr a0, misa
  bgez a0, misa_rv32
#if __riscv_xlen == 32
  la a0, rv32_expected_str
  j fatal_error
#else
  slli a0, a0, 1
  bgez a0, misa_ok
  # we are on a 128 bit CPU: we force MXL to 64 bit as a test
  la a0, rv128_detected_str
  jal putstring
  li a0, 1
  li a1, 126
  # cannot use slli because no 128 bit support in gas
  sll a0, a0, a1
  csrc misa, a0
  # also set MSTATUS.SXL and MSTATUS.UXL to 64 bits
  li a0, (3 << 32) | (3 << 34)
  csrs mstatus, a0
  li a0, (1 << 32) | (1 << 34)
  csrc mstatus, a0
  j misa_ok
#endif
  misa_rv32:
#if __riscv_xlen == 64
  la a0, rv64_expected_str
  j fatal_error
#endif
misa_ok:
  mv a0, s0
  mv a1, s1

#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
  # fixup endianness before making any loads or stores
#if __riscv_xlen == 32
  li t0, MSTATUSH_MBE
  csrs CSR_MSTATUSH, t0
#else
  li t0, MSTATUS_MBE
  csrs CSR_MSTATUS, t0
#endif
#endif

  # write mtvec and make sure it sticks
  la t0, trap_vector
  csrw mtvec, t0
  csrr t1, mtvec
1:bne t0, t1, 1b

  la sp, stacks + RISCV_PGSIZE - MENTRY_FRAME_SIZE

  csrr a3, mhartid
  slli a2, a3, RISCV_PGSHIFT
  add sp, sp, a2

  bnez a3, .LmultiHartInit

#ifdef ZERO_BSS
  # Zero out BSS; linker script provides alignment and padding
  la t0, _fbss
  la t1, _end
  beq t0, t1, 2f
1:STORE zero, 0(t0)
  addi t0, t0, REGBYTES
  bne t0, t1, 1b
2:
#endif

  # Boot on the first hart
#ifdef CUSTOM_DTS
  csrr a0, mhartid
  la a1, dtb_start
#endif
  j init_first_hart

.LmultiHartInit:
  # set MSIE bit to receive IPI
  li a2, MIP_MSIP
  csrw mie, a2

.LmultiHart:
#if MAX_HARTS > 1
  # wait for an IPI to signal that it's safe to boot
  wfi

  # masked harts never start
  la a4, disabled_hart_mask
  LOAD a4, 0(a4)
  srl a4, a4, a3
  andi a4, a4, 1
  bnez a4, .LmultiHart

  # only start if mip is set
  csrr a2, mip
  andi a2, a2, MIP_MSIP
  beqz a2, .LmultiHart

  # make sure our hart id is within a valid range
  fence
  li a2, MAX_HARTS
  bgeu a3, a2, .Lcont
  j init_other_hart
.Lcont:
#endif
  wfi
  j .LmultiHart

#ifdef CUSTOM_DTS
.section .dtb
.align 3
.global dtb_start, dtb_end
dtb_start:
.incbin "custom.dtb"
dtb_end:
#endif

  .bss
  .align RISCV_PGSHIFT
stacks:
  .skip RISCV_PGSIZE * MAX_HARTS
