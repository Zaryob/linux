/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * This file contains low level CPU setup functions.
 *    Copyright (C) 2003 Benjamin Herrenschmidt (benh@kernel.crashing.org)
 */

#include <linux/linkage.h>

#include <asm/processor.h>
#include <asm/page.h>
#include <asm/cputable.h>
#include <asm/ppc_asm.h>
#include <asm/asm-offsets.h>
#include <asm/cache.h>
#include <asm/mmu.h>
#include <asm/feature-fixups.h>

_GLOBAL(__setup_cpu_603)
	mflr	r5
BEGIN_MMU_FTR_SECTION
	li	r10,0
	mtspr	SPRN_SPRG_603_LRU,r10		/* init SW LRU tracking */
END_MMU_FTR_SECTION_IFSET(MMU_FTR_NEED_DTLB_SW_LRU)

BEGIN_FTR_SECTION
	bl	__init_fpu_registers
END_FTR_SECTION_IFCLR(CPU_FTR_FPU_UNAVAILABLE)
	bl	setup_common_caches

	/*
	 * This assumes that all cores using __setup_cpu_603 with
	 * MMU_FTR_USE_HIGH_BATS are G2_LE compatible
	 */
BEGIN_MMU_FTR_SECTION
	bl      setup_g2_le_hid2
END_MMU_FTR_SECTION_IFSET(MMU_FTR_USE_HIGH_BATS)

	mtlr	r5
	blr
_GLOBAL(__setup_cpu_604)
	mflr	r5
	bl	setup_common_caches
	bl	setup_604_hid0
	mtlr	r5
	blr
_GLOBAL(__setup_cpu_750)
	mflr	r5
	bl	__init_fpu_registers
	bl	setup_common_caches
	bl	setup_750_7400_hid0
	mtlr	r5
	blr
_GLOBAL(__setup_cpu_750cx)
	mflr	r5
	bl	__init_fpu_registers
	bl	setup_common_caches
	bl	setup_750_7400_hid0
	bl	setup_750cx
	mtlr	r5
	blr
_GLOBAL(__setup_cpu_750fx)
	mflr	r5
	bl	__init_fpu_registers
	bl	setup_common_caches
	bl	setup_750_7400_hid0
	bl	setup_750fx
	mtlr	r5
	blr
_GLOBAL(__setup_cpu_7400)
	mflr	r5
	bl	__init_fpu_registers
	bl	setup_7400_workarounds
	bl	setup_common_caches
	bl	setup_750_7400_hid0
	mtlr	r5
	blr
_GLOBAL(__setup_cpu_7410)
	mflr	r5
	bl	__init_fpu_registers
	bl	setup_7410_workarounds
	bl	setup_common_caches
	bl	setup_750_7400_hid0
	li	r3,0
	mtspr	SPRN_L2CR2,r3
	mtlr	r5
	blr
_GLOBAL(__setup_cpu_745x)
	mflr	r5
	bl	setup_common_caches
	bl	setup_745x_specifics
	mtlr	r5
	blr

/* Enable caches for 603's, 604, 750 & 7400 */
SYM_FUNC_START_LOCAL(setup_common_caches)
	mfspr	r11,SPRN_HID0
	andi.	r0,r11,HID0_DCE
	ori	r11,r11,HID0_ICE|HID0_DCE
	ori	r8,r11,HID0_ICFI
	bne	1f			/* don't invalidate the D-cache */
	ori	r8,r8,HID0_DCI		/* unless it wasn't enabled */
1:	sync
	mtspr	SPRN_HID0,r8		/* enable and invalidate caches */
	sync
	mtspr	SPRN_HID0,r11		/* enable caches */
	sync
	isync
	blr
SYM_FUNC_END(setup_common_caches)

/* 604, 604e, 604ev, ...
 * Enable superscalar execution & branch history table
 */
SYM_FUNC_START_LOCAL(setup_604_hid0)
	mfspr	r11,SPRN_HID0
	ori	r11,r11,HID0_SIED|HID0_BHTE
	ori	r8,r11,HID0_BTCD
	sync
	mtspr	SPRN_HID0,r8	/* flush branch target address cache */
	sync			/* on 604e/604r */
	mtspr	SPRN_HID0,r11
	sync
	isync
	blr
SYM_FUNC_END(setup_604_hid0)

/* Enable high BATs for G2_LE and derivatives like e300cX */
SYM_FUNC_START_LOCAL(setup_g2_le_hid2)
	mfspr	r11,SPRN_HID2_G2_LE
	oris	r11,r11,HID2_G2_LE_HBE@h
	mtspr	SPRN_HID2_G2_LE,r11
	sync
	isync
	blr
SYM_FUNC_END(setup_g2_le_hid2)

/* 7400 <= rev 2.7 and 7410 rev = 1.0 suffer from some
 * erratas we work around here.
 * Moto MPC710CE.pdf describes them, those are errata
 * #3, #4 and #5
 * Note that we assume the firmware didn't choose to
 * apply other workarounds (there are other ones documented
 * in the .pdf). It appear that Apple firmware only works
 * around #3 and with the same fix we use. We may want to
 * check if the CPU is using 60x bus mode in which case
 * the workaround for errata #4 is useless. Also, we may
 * want to explicitly clear HID0_NOPDST as this is not
 * needed once we have applied workaround #5 (though it's
 * not set by Apple's firmware at least).
 */
SYM_FUNC_START_LOCAL(setup_7400_workarounds)
	mfpvr	r3
	rlwinm	r3,r3,0,20,31
	cmpwi	0,r3,0x0207
	ble	1f
	blr
SYM_FUNC_END(setup_7400_workarounds)
SYM_FUNC_START_LOCAL(setup_7410_workarounds)
	mfpvr	r3
	rlwinm	r3,r3,0,20,31
	cmpwi	0,r3,0x0100
	bnelr
1:
	mfspr	r11,SPRN_MSSSR0
	/* Errata #3: Set L1OPQ_SIZE to 0x10 */
	rlwinm	r11,r11,0,9,6
	oris	r11,r11,0x0100
	/* Errata #4: Set L2MQ_SIZE to 1 (check for MPX mode first ?) */
	oris	r11,r11,0x0002
	/* Errata #5: Set DRLT_SIZE to 0x01 */
	rlwinm	r11,r11,0,5,2
	oris	r11,r11,0x0800
	sync
	mtspr	SPRN_MSSSR0,r11
	sync
	isync
	blr
SYM_FUNC_END(setup_7410_workarounds)

/* 740/750/7400/7410
 * Enable Store Gathering (SGE), Address Broadcast (ABE),
 * Branch History Table (BHTE), Branch Target ICache (BTIC)
 * Dynamic Power Management (DPM), Speculative (SPD)
 * Clear Instruction cache throttling (ICTC)
 */
SYM_FUNC_START_LOCAL(setup_750_7400_hid0)
	mfspr	r11,SPRN_HID0
	ori	r11,r11,HID0_SGE | HID0_ABE | HID0_BHTE | HID0_BTIC
	oris	r11,r11,HID0_DPM@h
BEGIN_FTR_SECTION
	xori	r11,r11,HID0_BTIC
END_FTR_SECTION_IFSET(CPU_FTR_NO_BTIC)
BEGIN_FTR_SECTION
	xoris	r11,r11,HID0_DPM@h	/* disable dynamic power mgmt */
END_FTR_SECTION_IFSET(CPU_FTR_NO_DPM)
	li	r3,HID0_SPD
	andc	r11,r11,r3		/* clear SPD: enable speculative */
 	li	r3,0
 	mtspr	SPRN_ICTC,r3		/* Instruction Cache Throttling off */
	isync
	mtspr	SPRN_HID0,r11
	sync
	isync
	blr
SYM_FUNC_END(setup_750_7400_hid0)

/* 750cx specific
 * Looks like we have to disable NAP feature for some PLL settings...
 * (waiting for confirmation)
 */
SYM_FUNC_START_LOCAL(setup_750cx)
	mfspr	r10, SPRN_HID1
	rlwinm	r10,r10,4,28,31
	cmpwi	cr0,r10,7
	cmpwi	cr1,r10,9
	cmpwi	cr2,r10,11
	cror	4*cr0+eq,4*cr0+eq,4*cr1+eq
	cror	4*cr0+eq,4*cr0+eq,4*cr2+eq
	bnelr
	lwz	r6,CPU_SPEC_FEATURES(r4)
	li	r7,CPU_FTR_CAN_NAP
	andc	r6,r6,r7
	stw	r6,CPU_SPEC_FEATURES(r4)
	blr
SYM_FUNC_END(setup_750cx)

/* 750fx specific
 */
SYM_FUNC_START_LOCAL(setup_750fx)
	blr
SYM_FUNC_END(setup_750fx)

/* MPC 745x
 * Enable Store Gathering (SGE), Branch Folding (FOLD)
 * Branch History Table (BHTE), Branch Target ICache (BTIC)
 * Dynamic Power Management (DPM), Speculative (SPD)
 * Ensure our data cache instructions really operate.
 * Timebase has to be running or we wouldn't have made it here,
 * just ensure we don't disable it.
 * Clear Instruction cache throttling (ICTC)
 * Enable L2 HW prefetch
 */
SYM_FUNC_START_LOCAL(setup_745x_specifics)
	/* We check for the presence of an L3 cache setup by
	 * the firmware. If any, we disable NAP capability as
	 * it's known to be bogus on rev 2.1 and earlier
	 */
BEGIN_FTR_SECTION
	mfspr	r11,SPRN_L3CR
	andis.	r11,r11,L3CR_L3E@h
	beq	1f
END_FTR_SECTION_IFSET(CPU_FTR_L3CR)
	lwz	r6,CPU_SPEC_FEATURES(r4)
	andis.	r0,r6,CPU_FTR_L3_DISABLE_NAP@h
	beq	1f
	li	r7,CPU_FTR_CAN_NAP
	andc	r6,r6,r7
	stw	r6,CPU_SPEC_FEATURES(r4)
1:
	mfspr	r11,SPRN_HID0

	/* All of the bits we have to set.....
	 */
	ori	r11,r11,HID0_SGE | HID0_FOLD | HID0_BHTE
	ori	r11,r11,HID0_LRSTK | HID0_BTIC
	oris	r11,r11,HID0_DPM@h
BEGIN_MMU_FTR_SECTION
	oris	r11,r11,HID0_HIGH_BAT@h
END_MMU_FTR_SECTION_IFSET(MMU_FTR_USE_HIGH_BATS)
BEGIN_FTR_SECTION
	xori	r11,r11,HID0_BTIC
END_FTR_SECTION_IFSET(CPU_FTR_NO_BTIC)
BEGIN_FTR_SECTION
	xoris	r11,r11,HID0_DPM@h	/* disable dynamic power mgmt */
END_FTR_SECTION_IFSET(CPU_FTR_NO_DPM)

	/* All of the bits we have to clear....
	 */
	li	r3,HID0_SPD | HID0_NOPDST | HID0_NOPTI
	andc	r11,r11,r3		/* clear SPD: enable speculative */
 	li	r3,0

 	mtspr	SPRN_ICTC,r3		/* Instruction Cache Throttling off */
	isync
	mtspr	SPRN_HID0,r11
	sync
	isync

	/* Enable L2 HW prefetch, if L2 is enabled
	 */
	mfspr	r3,SPRN_L2CR
	andis.	r3,r3,L2CR_L2E@h
	beqlr
	mfspr	r3,SPRN_MSSCR0
	ori	r3,r3,3
	sync
	mtspr	SPRN_MSSCR0,r3
	sync
	isync
	blr
SYM_FUNC_END(setup_745x_specifics)

/*
 * Initialize the FPU registers. This is needed to work around an errata
 * in some 750 cpus where using a not yet initialized FPU register after
 * power on reset may hang the CPU
 */
_GLOBAL(__init_fpu_registers)
	mfmsr	r10
	ori	r11,r10,MSR_FP
	mtmsr	r11
	isync
	addis	r9,r3,empty_zero_page@ha
	addi	r9,r9,empty_zero_page@l
	REST_32FPRS(0,r9)
	sync
	mtmsr	r10
	isync
	blr
_ASM_NOKPROBE_SYMBOL(__init_fpu_registers)


/* Definitions for the table use to save CPU states */
#define CS_HID0		0
#define CS_HID1		4
#define CS_HID2		8
#define	CS_MSSCR0	12
#define CS_MSSSR0	16
#define CS_ICTRL	20
#define CS_LDSTCR	24
#define CS_LDSTDB	28
#define CS_SIZE		32

	.data
	.balign	L1_CACHE_BYTES
cpu_state_storage:
	.space	CS_SIZE
	.balign	L1_CACHE_BYTES,0
	.text

/* Called in normal context to backup CPU 0 state. This
 * does not include cache settings. This function is also
 * called for machine sleep. This does not include the MMU
 * setup, BATs, etc... but rather the "special" registers
 * like HID0, HID1, MSSCR0, etc...
 */
_GLOBAL(__save_cpu_setup)
	/* Some CR fields are volatile, we back it up all */
	mfcr	r7

	/* Get storage ptr */
	lis	r5,cpu_state_storage@h
	ori	r5,r5,cpu_state_storage@l

	/* Save HID0 (common to all CONFIG_PPC_BOOK3S_32 cpus) */
	mfspr	r3,SPRN_HID0
	stw	r3,CS_HID0(r5)

	/* Now deal with CPU type dependent registers */
	mfspr	r3,SPRN_PVR
	srwi	r3,r3,16
	cmplwi	cr0,r3,0x8000	/* 7450 */
	cmplwi	cr1,r3,0x000c	/* 7400 */
	cmplwi	cr2,r3,0x800c	/* 7410 */
	cmplwi	cr3,r3,0x8001	/* 7455 */
	cmplwi	cr4,r3,0x8002	/* 7457 */
	cmplwi	cr5,r3,0x8003	/* 7447A */
	cmplwi	cr6,r3,0x7000	/* 750FX */
	cmplwi	cr7,r3,0x8004	/* 7448 */
	/* cr1 is 7400 || 7410 */
	cror	4*cr1+eq,4*cr1+eq,4*cr2+eq
	/* cr0 is 74xx */
	cror	4*cr0+eq,4*cr0+eq,4*cr3+eq
	cror	4*cr0+eq,4*cr0+eq,4*cr4+eq
	cror	4*cr0+eq,4*cr0+eq,4*cr1+eq
	cror	4*cr0+eq,4*cr0+eq,4*cr5+eq
	cror	4*cr0+eq,4*cr0+eq,4*cr7+eq
	bne	1f
	/* Backup 74xx specific regs */
	mfspr	r4,SPRN_MSSCR0
	stw	r4,CS_MSSCR0(r5)
	mfspr	r4,SPRN_MSSSR0
	stw	r4,CS_MSSSR0(r5)
	beq	cr1,1f
	/* Backup 745x specific registers */
	mfspr	r4,SPRN_HID1
	stw	r4,CS_HID1(r5)
	mfspr	r4,SPRN_ICTRL
	stw	r4,CS_ICTRL(r5)
	mfspr	r4,SPRN_LDSTCR
	stw	r4,CS_LDSTCR(r5)
	mfspr	r4,SPRN_LDSTDB
	stw	r4,CS_LDSTDB(r5)
1:
	bne	cr6,1f
	/* Backup 750FX specific registers */
	mfspr	r4,SPRN_HID1
	stw	r4,CS_HID1(r5)
	/* If rev 2.x, backup HID2 */
	mfspr	r3,SPRN_PVR
	andi.	r3,r3,0xff00
	cmpwi	cr0,r3,0x0200
	bne	1f
	mfspr	r4,SPRN_HID2_750FX
	stw	r4,CS_HID2(r5)
1:
	mtcr	r7
	blr

/* Called with no MMU context (typically MSR:IR/DR off) to
 * restore CPU state as backed up by the previous
 * function. This does not include cache setting
 */
_GLOBAL(__restore_cpu_setup)
	/* Some CR fields are volatile, we back it up all */
	mfcr	r7

	/* Get storage ptr */
	lis	r5,(cpu_state_storage-KERNELBASE)@h
	ori	r5,r5,cpu_state_storage@l

	/* Restore HID0 */
	lwz	r3,CS_HID0(r5)
	sync
	isync
	mtspr	SPRN_HID0,r3
	sync
	isync

	/* Now deal with CPU type dependent registers */
	mfspr	r3,SPRN_PVR
	srwi	r3,r3,16
	cmplwi	cr0,r3,0x8000	/* 7450 */
	cmplwi	cr1,r3,0x000c	/* 7400 */
	cmplwi	cr2,r3,0x800c	/* 7410 */
	cmplwi	cr3,r3,0x8001	/* 7455 */
	cmplwi	cr4,r3,0x8002	/* 7457 */
	cmplwi	cr5,r3,0x8003	/* 7447A */
	cmplwi	cr6,r3,0x7000	/* 750FX */
	cmplwi	cr7,r3,0x8004	/* 7448 */
	/* cr1 is 7400 || 7410 */
	cror	4*cr1+eq,4*cr1+eq,4*cr2+eq
	/* cr0 is 74xx */
	cror	4*cr0+eq,4*cr0+eq,4*cr3+eq
	cror	4*cr0+eq,4*cr0+eq,4*cr4+eq
	cror	4*cr0+eq,4*cr0+eq,4*cr1+eq
	cror	4*cr0+eq,4*cr0+eq,4*cr5+eq
	cror	4*cr0+eq,4*cr0+eq,4*cr7+eq
	bne	2f
	/* Restore 74xx specific regs */
	lwz	r4,CS_MSSCR0(r5)
	sync
	mtspr	SPRN_MSSCR0,r4
	sync
	isync
	lwz	r4,CS_MSSSR0(r5)
	sync
	mtspr	SPRN_MSSSR0,r4
	sync
	isync
	bne	cr2,1f
	/* Clear 7410 L2CR2 */
	li	r4,0
	mtspr	SPRN_L2CR2,r4
1:	beq	cr1,2f
	/* Restore 745x specific registers */
	lwz	r4,CS_HID1(r5)
	sync
	mtspr	SPRN_HID1,r4
	isync
	sync
	lwz	r4,CS_ICTRL(r5)
	sync
	mtspr	SPRN_ICTRL,r4
	isync
	sync
	lwz	r4,CS_LDSTCR(r5)
	sync
	mtspr	SPRN_LDSTCR,r4
	isync
	sync
	lwz	r4,CS_LDSTDB(r5)
	sync
	mtspr	SPRN_LDSTDB,r4
	isync
	sync
2:	bne	cr6,1f
	/* Restore 750FX specific registers
	 * that is restore HID2 on rev 2.x and PLL config & switch
	 * to PLL 0 on all
	 */
	/* If rev 2.x, restore HID2 with low voltage bit cleared */
	mfspr	r3,SPRN_PVR
	andi.	r3,r3,0xff00
	cmpwi	cr0,r3,0x0200
	bne	4f
	lwz	r4,CS_HID2(r5)
	rlwinm	r4,r4,0,19,17
	mtspr	SPRN_HID2_750FX,r4
	sync
4:
	lwz	r4,CS_HID1(r5)
	rlwinm  r5,r4,0,16,14
	mtspr	SPRN_HID1,r5
		/* Wait for PLL to stabilize */
	mftbl	r5
3:	mftbl	r6
	sub	r6,r6,r5
	cmplwi	cr0,r6,10000
	ble	3b
	/* Setup final PLL */
	mtspr	SPRN_HID1,r4
1:
	mtcr	r7
	blr
_ASM_NOKPROBE_SYMBOL(__restore_cpu_setup)
