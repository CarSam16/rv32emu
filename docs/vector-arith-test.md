# vadd/vsub vta/vma 測試程式：改動說明

本文件記錄這次在 `vector` branch 上為了「撰寫一個能執行 vadd/vsub、並驗證 vta/vma 政策的測試程式」所做的所有改動，以及每一項改動背後的原因。

## 1. 背景

在動手寫測試程式前，先對照 `docs/spec.md.md` 的需求逐項檢查了目前 `vector` branch 的實作現況（結論見另一份文件），其中發現 `src/rv32_template.c:3252` 有一行語法錯誤會直接擋住 `make ENABLE_EXT_V=1` 的編譯。這代表在寫任何測試程式之前，這個問題必須先解決，否則測試永遠無法建置。

## 2. 修正 `src/rv32_template.c:3252`

**改動內容**：
```diff
-Agnostic fill values based on SEW 
+/* Agnostic fill values based on SEW */
```

**原因**：這一行是一句沒有 `/* */` 或 `//` 包裹的裸英文說明文字，卡在兩個 `#define` 巨集（`GET_VLMUL` 與 `AGNOSTIC_FILL_8b`）之間，語法上不是合法的前置處理指令或 C 陳述式。研判是最新一次 commit（`f9afa41` "modify vta and vma implementation"）新增 `GET_VTA`/`GET_VMA`/`AGNOSTIC_FILL_*` 巨集時漏刪或漏打註解符號留下的痕跡。只把它補成合法註解，不改變任何邏輯行為，是這次唯一對 `src/` 既有邏輯的修改。

## 3. 新增測試程式 `tests/system/vector_arith/`

比照既有的 `tests/system/alignment`、`tests/system/mmu` 這兩個 bare-metal 測試的結構與慣例（獨立 `Makefile`、手寫 `_start`、透過 `ecall` 的 `write`(64)/`exit`(93) syscall 印出結果並結束），新增以下 5 個檔案：

| 檔案 | 用途 |
|---|---|
| `linker.ld` | 簡單的 flat memory layout（`.text`/`.rodata`/`.data`/`.bss`，起始位址 `0x10000`），比照 alignment 測試 |
| `start.S` | `_start`：呼叫 `main()`，並提供 `_exit(status)` 供 `main.c` 呼叫來結束程式 |
| `vecops.S` | 10 個獨立的向量組合語言測試函式（見下方表格） |
| `main.c` | 依序呼叫 `vecops.S` 的函式、比對預期結果、印出對應的 PASS/FAIL 訊息 |
| `Makefile` | 比照 alignment 的建置骨架，`-march=rv32im_zicsr_zve32x`（整數向量子集，不需要 F/D 浮點） |

### 為什麼選 SEW=32、而不是 SEW=8/16

先前的落差分析發現 `vle8_v`（`rv32_template.c:3641`）的 tail 清除邏輯有 `%=`/`&=` 的 bug，只影響 8-bit 寬度的 load 指令。為了不讓測試同時卡在兩個獨立問題上（一個是這次要驗證的 vta/vma，另一個是那個既有 bug），測試全程只用 `vle32.v`/`vse32.v`/SEW=32，完全避開那條有問題的路徑。

## 4. vta/vma 位元編碼參考（寫測試時反覆用到的事實）

依 `rv32_template.c:3247-3250`（`GET_VTA`/`GET_VMA`/`GET_VSEW`/`GET_VLMUL`）與 `:3105-3135`（`vsetvli` 如何把整個 `zimm` 原封不動寫進 `csr_vtype`）確認：

- `zimm`/`vtype` 的 bit 配置：`bit[2:0]=vlmul`、`bit[5:3]=vsew`、`bit[6]=vta`、`bit[7]=vma`
- SEW=32 對應 `vsew=0b010`，因此 `e32,m1` 基準值（vta=0,vma=0）為 `0x10`
- 測試組語一律用 `vsetvli rd, rs1, e32, m1, ta/tu, ma/mu` 助記符讓組譯器自己算好這個立即值，`vecops.S` 開頭另外用註解列出手算好的 `0x50`/`0x90`/`0x10` 供組譯器不支援該助記符語法時當作 `.word`/`vsetvl` 手動編碼的備援

## 5. 10 個測試案例與其目的

前 3 個是最初版本就有的基本案例，後 7 個是這次依 `sew_32b_handler`（`rv32_template.c:3564-3601`）與 `VV_LOOP`（`:3335-3362`）的實際邏輯分析出來、原本 3 個案例覆蓋不到的邊界情況：

| # | 函式 | 情境 | 驗證重點 |
|---|---|---|---|
| 1 | `vec_add_vta` | `vl=3`（`<vlmax=4`），`vta=1` | tail 元素（index 3）被填 `0xFFFFFFFF` |
| 2 | `vec_add_vma` | `vl=4`，`vma=1`，mask=`0b0101` | inactive lane 被填 `0xFFFFFFFF`，active lane 正常算出結果 |
| 3 | `vec_sub` | `vl=4`，unmasked | 確認 `vsub.vv vd,vs2,vs1 = vs2-vs1` 語意正確 |
| 4 | `vec_add_vl0_vta` | `AVL=0`（`vl=0`），`vta=1` | 完全沒有 active 元素時，整個目的暫存器（4 個 word）要靠「entirely-tail」分支全部填成 `0xFFFFFFFF` |
| 5 | `vec_add_full_vta_noop` | `vl=4=vlmax`（無 tail），`vta=1` | 迴歸測試：確認沒有 tail 時 `vta=1` 不會誤填任何正常算出的值 |
| 6 | `vec_add_vta0_undisturbed` | `vl=3`，**`vta=0`**（undisturbed） | 預先用 `vle32.v` 把 sentinel 值載進目的暫存器，驗證 tail word 完全不被 `vadd.vv` 動到、保留原值 |
| 7 | `vec_add_mask_allzero_vma` | `vl=4`，`vma=1`，mask=`0x0` | 全部 lane 都 inactive 時，全部都要被填 `0xFFFFFFFF` |
| 8 | `vec_add_mask_allone_vma` | `vl=4`，`vma=1`，mask=`0xF` | 沒有任何 lane inactive 時，`vma=1` 不該有任何效果，結果要等於純加法 |
| 9 | `vec_add_vma0_undisturbed` | `vl=4`，**`vma=0`**，混合 mask | 預先載入 sentinel，驗證 inactive lane 保留 sentinel、active lane 正常算出結果 |
| 10 | `vec_add_lmul2_vta` | `LMUL=2`（`vlmax=8`），`AVL=3`，`vta=1` | 同時驗證「暫存器內的 tail word」（index 3）與「整個暫存器都是 tail」（第二個暫存器，index 4-7）兩種填法，這是 `LMUL=1` 測不到的分支 |

每個案例都有獨立的 `TEST_LOGGER` 訊息，任一組不符就印出對應的 `[XXX TEST] mismatch` 並以 `FAIL`（exit code 1）結束；全部通過則印出 `VECTOR ARITH TEST PASSED!` 並以 `SUCCESS`（exit code 0）結束。

## 6. Makefile / CI 整合

- `Makefile`：新增 `EXPECTED_vector_arith` 與 `vector-arith-test` target，比照既有的 `mmu-test`/`misalign-in-blk-emu` 寫法，用 `check-test` 巨集比對 rv32emu 輸出的最後一行是否等於 `VECTOR ARITH TEST PASSED!`
- `.github/workflows/main.yml`：在既有的「MMU test」step 之後新增「vector arithmetic test」step，流程比照 alignment/mmu：先 `make -C tests/system/vector_arith/` 建置 ELF，再用 `make ENABLE_EXT_V=1 VLEN=128 ENABLE_ELF_LOADER=1 ENABLE_SYSTEM=1 vector-arith-test` 建置模擬器並執行

## 7. 已知限制

這次撰寫的所有測試檔案**都還沒有在真正的 RISC-V 工具鏈上組譯、連結、執行過**——目前的工作環境（Windows，無 WSL 發行版、無 Docker、無 `riscv-none-elf-gcc`）找不到可用的交叉工具鏈，所以 `vsetvli`/`vadd.vv`/`vle32.v` 等組語助記符是否能被組譯器正確接受、`LMUL=2` 的暫存器分組語法是否正確，都還沒有實測驗證過。建議在你自己有工具鏈的 Linux 環境跑：
```
make -C tests/system/vector_arith/
make distclean && make ENABLE_EXT_V=1 VLEN=128 ENABLE_ELF_LOADER=1 ENABLE_SYSTEM=1 vector-arith-test
```
如果某個 `TEST PASSED!` 沒印出來，訊息裡的名稱就直接對應到上表第幾個案例。
