/*
 * vtype immediate (zimm) bit layout, cross-checked against
 * GET_VTA/GET_VMA/GET_VSEW/GET_VLMUL in src/rv32_template.c:3247-3250:
 *   bit[2:0] = vlmul, bit[5:3] = vsew, bit[6] = vta, bit[7] = vma
 * For e32,m1 the base value (vta=0,vma=0) is (vsew=2)<<3 = 0x10.
 * If the assembler rejects the `vsetvli rd, rs1, e32, m1, ta, ma`
 * mnemonic form (no "v" extension support), the vsetvli lines below can
 * be replaced with `li a4, <zimm>` + `vsetvl rd, rs1, a4` using these
 * precomputed immediates instead:
 *   e32, m1, ta, mu -> zimm = 0x50
 *   e32, m1, tu, ma -> zimm = 0x90
 *   e32, m1, tu, mu -> zimm = 0x10
 */

.section .text

/*
 * void vec_add_vta(const int32_t *a, const int32_t *b, uint32_t *out)
 *
 * Computes out[0..2] = b[i] + a[i] with vl=3 (< vlmax=4) and vta=1, then
 * re-issues vsetvli with AVL=x0 (rd != x0 -> vl = vlmax) before the store
 * so the tail element (out[3]) is also written out for inspection.
 */
.globl vec_add_vta
.type vec_add_vta, @function
vec_add_vta:
    li      t0, 3
    vsetvli t1, t0, e32, m1, ta, mu
    vle32.v v1, (a0)
    vle32.v v2, (a1)
    vadd.vv v3, v2, v1
    vsetvli t1, x0, e32, m1, ta, mu
    vse32.v v3, (a2)
    ret

/*
 * void vec_add_vma(const int32_t *a, const int32_t *b,
 *                   const uint32_t *mask, uint32_t *out)
 *
 * Computes out[i] = b[i] + a[i] for active lanes (mask bit = 1) and
 * out[i] = 0xFFFFFFFF for inactive lanes (mask bit = 0, vma=1), with
 * vl=4=vlmax so there is no tail.
 */
.globl vec_add_vma
.type vec_add_vma, @function
vec_add_vma:
    li      t0, 4
    vsetvli t1, t0, e32, m1, tu, ma
    vle32.v v0, (a2)
    vle32.v v1, (a0)
    vle32.v v2, (a1)
    vadd.vv v3, v2, v1, v0.t
    vse32.v v3, (a3)
    ret

/*
 * void vec_sub(const int32_t *a, const int32_t *b, int32_t *out)
 *
 * Computes out[i] = b[i] - a[i], vl=4=vlmax, unmasked.
 */
.globl vec_sub
.type vec_sub, @function
vec_sub:
    li      t0, 4
    vsetvli t1, t0, e32, m1, tu, mu
    vle32.v v1, (a0)
    vle32.v v2, (a1)
    vsub.vv v4, v2, v1
    vse32.v v4, (a2)
    ret

/* ---- vta/vma boundary-condition cases ---- */

/*
 * void vec_add_vl0_vta(uint32_t *out)
 *
 * Boundary: AVL=0 -> vl=0, vta=1, LMUL=1. No element is ever active, so
 * the whole destination register (all 4 words) must be produced entirely
 * by the "entire word is tail" branch of sew_32b_handler.
 */
.globl vec_add_vl0_vta
.type vec_add_vl0_vta, @function
vec_add_vl0_vta:
    li      t0, 0
    vsetvli t1, t0, e32, m1, ta, mu
    vadd.vv v3, v2, v1
    vsetvli t1, x0, e32, m1, ta, mu
    vse32.v v3, (a0)
    ret

/*
 * void vec_add_full_vta_noop(const int32_t *a, const int32_t *b,
 *                             uint32_t *out)
 *
 * Boundary: vl=4=vlmax, vta=1, but there is no tail at all. Regression
 * check that vta being set does not spuriously clobber fully-active
 * lanes: result must equal the plain unmasked sum.
 */
.globl vec_add_full_vta_noop
.type vec_add_full_vta_noop, @function
vec_add_full_vta_noop:
    li      t0, 4
    vsetvli t1, t0, e32, m1, ta, mu
    vle32.v v1, (a0)
    vle32.v v2, (a1)
    vadd.vv v3, v2, v1
    vse32.v v3, (a2)
    ret

/*
 * void vec_add_vta0_undisturbed(const int32_t *a, const int32_t *b,
 *                                const uint32_t *preload, uint32_t *out)
 *
 * Boundary: vl=3 (< vlmax=4), vta=0 (tail-undisturbed). The destination
 * register is preloaded with a sentinel pattern before the vadd.vv so the
 * untouched tail word (index 3) must retain that exact sentinel rather
 * than being zeroed or filled.
 */
.globl vec_add_vta0_undisturbed
.type vec_add_vta0_undisturbed, @function
vec_add_vta0_undisturbed:
    li      t0, 3
    vsetvli t1, t0, e32, m1, tu, mu
    vle32.v v1, (a0)
    vle32.v v2, (a1)
    vle32.v v3, (a2)
    vadd.vv v3, v2, v1
    vsetvli t1, x0, e32, m1, tu, mu
    vse32.v v3, (a3)
    ret

/*
 * void vec_add_mask_allzero_vma(const int32_t *a, const int32_t *b,
 *                                const uint32_t *mask, uint32_t *out)
 *
 * Boundary: vl=4=vlmax, vma=1, mask=0x0 (every lane inactive). Every lane
 * must be filled with 0xFFFFFFFF; none of the arithmetic result should
 * survive.
 */
.globl vec_add_mask_allzero_vma
.type vec_add_mask_allzero_vma, @function
vec_add_mask_allzero_vma:
    li      t0, 4
    vsetvli t1, t0, e32, m1, tu, ma
    vle32.v v0, (a2)
    vle32.v v1, (a0)
    vle32.v v2, (a1)
    vadd.vv v3, v2, v1, v0.t
    vse32.v v3, (a3)
    ret

/*
 * void vec_add_mask_allone_vma(const int32_t *a, const int32_t *b,
 *                               const uint32_t *mask, uint32_t *out)
 *
 * Boundary: vl=4=vlmax, vma=1, mask=0xF (every lane active). vma must
 * have no effect when nothing is actually inactive: result must equal
 * the plain unmasked sum.
 */
.globl vec_add_mask_allone_vma
.type vec_add_mask_allone_vma, @function
vec_add_mask_allone_vma:
    li      t0, 4
    vsetvli t1, t0, e32, m1, tu, ma
    vle32.v v0, (a2)
    vle32.v v1, (a0)
    vle32.v v2, (a1)
    vadd.vv v3, v2, v1, v0.t
    vse32.v v3, (a3)
    ret

/*
 * void vec_add_vma0_undisturbed(const int32_t *a, const int32_t *b,
 *                                const uint32_t *mask,
 *                                const uint32_t *preload, uint32_t *out)
 *
 * Boundary: vl=4=vlmax, vma=0 (mask-undisturbed), mixed mask. The
 * destination register is preloaded with a sentinel pattern before the
 * masked vadd.vv, so inactive lanes must retain that exact sentinel
 * while active lanes still get the computed sum.
 */
.globl vec_add_vma0_undisturbed
.type vec_add_vma0_undisturbed, @function
vec_add_vma0_undisturbed:
    li      t0, 4
    vsetvli t1, t0, e32, m1, tu, mu
    vle32.v v0, (a2)
    vle32.v v1, (a0)
    vle32.v v2, (a1)
    vle32.v v3, (a3)
    vadd.vv v3, v2, v1, v0.t
    vse32.v v3, (a4)
    ret

/*
 * void vec_add_lmul2_vta(const int32_t *a, const int32_t *b,
 *                         uint32_t *out)
 *
 * Boundary: LMUL=2 (vlmax=8), AVL=3, vta=1. Exercises both the
 * intra-register tail word (element 3, inside the first register of the
 * group) and the "entirely tail" second register of the group (elements
 * 4-7), i.e. the num_regs while-loop in sew_32b_handler that is never
 * reached at LMUL=1. Registers v8/v16/v24 (multiples of 8) are used to
 * stay clear of the LMUL=1 cases above.
 */
.globl vec_add_lmul2_vta
.type vec_add_lmul2_vta, @function
vec_add_lmul2_vta:
    li      t0, 3
    vsetvli t1, t0, e32, m2, ta, mu
    vle32.v v8, (a0)
    vle32.v v16, (a1)
    vadd.vv v24, v16, v8
    vsetvli t1, x0, e32, m2, ta, mu
    vse32.v v24, (a2)
    ret
