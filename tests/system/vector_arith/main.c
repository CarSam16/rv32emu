#define printstr(ptr, length)                   \
    do {                                        \
        asm volatile(                           \
            "add a7, x0, 0x40;"                 \
            "add a0, x0, 0x1;" /* stdout */     \
            "add a1, x0, %0;"                   \
            "mv a2, %1;" /* length character */ \
            "ecall;"                            \
            :                                   \
            : "r"(ptr), "r"(length)             \
            : "a0", "a1", "a2", "a7");          \
    } while (0)

#define TEST_OUTPUT(msg, length) printstr(msg, length)

#define TEST_LOGGER(msg)                     \
    {                                        \
        char _msg[] = msg;                   \
        TEST_OUTPUT(_msg, sizeof(_msg) - 1); \
    }

#define SUCCESS 0
#define FAIL 1

extern void _exit(int status);

extern void vec_add_vta(const int *a, const int *b, unsigned int *out);
extern void vec_add_vma(const int *a,
                         const int *b,
                         const unsigned int *mask,
                         unsigned int *out);
extern void vec_sub(const int *a, const int *b, int *out);

/* vta/vma boundary-condition cases */
extern void vec_add_vl0_vta(unsigned int *out);
extern void vec_add_full_vta_noop(const int *a,
                                   const int *b,
                                   unsigned int *out);
extern void vec_add_vta0_undisturbed(const int *a,
                                      const int *b,
                                      const unsigned int *preload,
                                      unsigned int *out);
extern void vec_add_mask_allzero_vma(const int *a,
                                      const int *b,
                                      const unsigned int *mask,
                                      unsigned int *out);
extern void vec_add_mask_allone_vma(const int *a,
                                     const int *b,
                                     const unsigned int *mask,
                                     unsigned int *out);
extern void vec_add_vma0_undisturbed(const int *a,
                                      const int *b,
                                      const unsigned int *mask,
                                      const unsigned int *preload,
                                      unsigned int *out);
extern void vec_add_lmul2_vta(const int *a, const int *b, unsigned int *out);

static const int a_data[4] = {1, 2, 3, 4};
static const int b_data[4] = {10, 20, 30, 40};
/* lanes 0 and 2 active, lanes 1 and 3 inactive */
static const unsigned int mask_mixed[1] = {0x5};
static const unsigned int mask_allzero[1] = {0x0};
static const unsigned int mask_allone[1] = {0xF};
static const unsigned int sentinel_vma[4] = {0xDEAD0001, 0xDEAD0002,
                                              0xDEAD0003, 0xDEAD0004};
static const unsigned int sentinel_vta[4] = {0xCAFE0001, 0xCAFE0002,
                                              0xCAFE0003, 0xCAFE0004};
static const int a2_data[8] = {1, 2, 3, 4, 5, 6, 7, 8};
static const int b2_data[8] = {100, 200, 300, 400, 500, 600, 700, 800};

static unsigned int out_vta[4];
static unsigned int out_vma[4];
static unsigned int out_sub[4];
static unsigned int out_vl0[4];
static unsigned int out_full_vta[4];
static unsigned int out_vta0[4];
static unsigned int out_mask_allzero[4];
static unsigned int out_mask_allone[4];
static unsigned int out_vma0[4];
static unsigned int out_lmul2[8];

static int arrays_equal(const unsigned int *got,
                         const unsigned int *want,
                         int n)
{
    for (int i = 0; i < n; i++) {
        if (got[i] != want[i])
            return 0;
    }
    return 1;
}

int main()
{
    unsigned int expect_vta[4] = {11u, 22u, 33u, 0xFFFFFFFFu};
    unsigned int expect_vma[4] = {11u, 0xFFFFFFFFu, 33u, 0xFFFFFFFFu};
    unsigned int expect_sub[4] = {9u, 18u, 27u, 36u};
    unsigned int expect_vl0[4] = {0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu,
                                   0xFFFFFFFFu};
    unsigned int expect_full_vta[4] = {11u, 22u, 33u, 44u};
    unsigned int expect_vta0[4] = {11u, 22u, 33u, 0xCAFE0004u};
    unsigned int expect_mask_allzero[4] = {0xFFFFFFFFu, 0xFFFFFFFFu,
                                            0xFFFFFFFFu, 0xFFFFFFFFu};
    unsigned int expect_mask_allone[4] = {11u, 22u, 33u, 44u};
    unsigned int expect_vma0[4] = {11u, 0xDEAD0002u, 33u, 0xDEAD0004u};
    unsigned int expect_lmul2[8] = {101u,        202u,        303u,
                                     0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu,
                                     0xFFFFFFFFu, 0xFFFFFFFFu};

    vec_add_vta(a_data, b_data, out_vta);
    if (!arrays_equal(out_vta, expect_vta, 4)) {
        TEST_LOGGER("[VTA TEST] mismatch\n");
        _exit(FAIL);
    }
    TEST_LOGGER("VTA TEST PASSED!\n");

    vec_add_vma(a_data, b_data, mask_mixed, out_vma);
    if (!arrays_equal(out_vma, expect_vma, 4)) {
        TEST_LOGGER("[VMA TEST] mismatch\n");
        _exit(FAIL);
    }
    TEST_LOGGER("VMA TEST PASSED!\n");

    vec_sub(a_data, b_data, (int *) out_sub);
    if (!arrays_equal(out_sub, expect_sub, 4)) {
        TEST_LOGGER("[VSUB TEST] mismatch\n");
        _exit(FAIL);
    }
    TEST_LOGGER("VSUB TEST PASSED!\n");

    /* --- vta/vma boundary conditions --- */

    vec_add_vl0_vta(out_vl0);
    if (!arrays_equal(out_vl0, expect_vl0, 4)) {
        TEST_LOGGER("[VL=0 + VTA TEST] mismatch\n");
        _exit(FAIL);
    }
    TEST_LOGGER("VL=0 VTA TEST PASSED!\n");

    vec_add_full_vta_noop(a_data, b_data, out_full_vta);
    if (!arrays_equal(out_full_vta, expect_full_vta, 4)) {
        TEST_LOGGER("[FULL VL + VTA NOOP TEST] mismatch\n");
        _exit(FAIL);
    }
    TEST_LOGGER("FULL VL VTA NOOP TEST PASSED!\n");

    vec_add_vta0_undisturbed(a_data, b_data, sentinel_vta, out_vta0);
    if (!arrays_equal(out_vta0, expect_vta0, 4)) {
        TEST_LOGGER("[VTA=0 UNDISTURBED TEST] mismatch\n");
        _exit(FAIL);
    }
    TEST_LOGGER("VTA=0 UNDISTURBED TEST PASSED!\n");

    vec_add_mask_allzero_vma(a_data, b_data, mask_allzero, out_mask_allzero);
    if (!arrays_equal(out_mask_allzero, expect_mask_allzero, 4)) {
        TEST_LOGGER("[MASK ALL-ZERO VMA TEST] mismatch\n");
        _exit(FAIL);
    }
    TEST_LOGGER("MASK ALL-ZERO VMA TEST PASSED!\n");

    vec_add_mask_allone_vma(a_data, b_data, mask_allone, out_mask_allone);
    if (!arrays_equal(out_mask_allone, expect_mask_allone, 4)) {
        TEST_LOGGER("[MASK ALL-ONE VMA TEST] mismatch\n");
        _exit(FAIL);
    }
    TEST_LOGGER("MASK ALL-ONE VMA TEST PASSED!\n");

    vec_add_vma0_undisturbed(a_data, b_data, mask_mixed, sentinel_vma,
                              out_vma0);
    if (!arrays_equal(out_vma0, expect_vma0, 4)) {
        TEST_LOGGER("[VMA=0 UNDISTURBED TEST] mismatch\n");
        _exit(FAIL);
    }
    TEST_LOGGER("VMA=0 UNDISTURBED TEST PASSED!\n");

    vec_add_lmul2_vta(a2_data, b2_data, out_lmul2);
    if (!arrays_equal(out_lmul2, expect_lmul2, 8)) {
        TEST_LOGGER("[LMUL=2 VTA TEST] mismatch\n");
        _exit(FAIL);
    }
    TEST_LOGGER("LMUL=2 VTA TEST PASSED!\n");

    TEST_LOGGER("VECTOR ARITH TEST PASSED!\n");
    _exit(SUCCESS);
}
