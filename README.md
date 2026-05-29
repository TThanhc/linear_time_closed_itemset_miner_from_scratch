# Linear Time Closed Itemset Miner From Scratch (Julia)

Khai phá **Closed Frequent Itemsets** và sinh **Association Rules** bằng Julia, tương thích định dạng dữ liệu và đầu ra của SPMF.

Project triển khai:

* Phiên bản A1: Vertical TID-list
* Phiên bản A2: BitVector tối ưu theo chunk-level operations

Mục tiêu:

* Kết quả khớp với SPMF
* Tối ưu hóa rõ ràng và có benchmark
* Hỗ trợ luật kết hợp
* I/O chuẩn SPMF
* Unit tests tự động

---

# 1. Cấu trúc thư mục

```text
.
│   LICENSE
│   README.md
│   run_lcm.jl
│
├───data 
│       accidents.txt
│       chess.txt
│       contextPasquier99.txt
│       expected_output_contextPasquier99_spmf.txt
│       mushrooms.txt
│       output_lcm_contextPasquier99.txt
│       retail.txt
│
├───results
│
├───src
│       AssociationRules.jl
│       LCM_A1_TIDList.jl
│       LCM_A2_BitVector.jl
│
├───test
│       generate_samples.jl
│       runtests.jl
│
└───toy
        toy1.txt
        toy2.txt
        toy3.txt
        toy4.txt
        toy5.txt
```

---

# 2. Yêu cầu hệ thống

* Julia >= 1.9
* Windows / Linux / macOS

Kiểm tra version:

```bash
julia --version
```

---

# 3. Chạy chương trình

## Cú pháp tổng quát
```bash
julia --project run_lcm.jl <input_file> <minsup> <task> <version> [minconf]
```
---

# 4. Tham số dòng lệnh

| Tham số        | Ý nghĩa                                              |
| -------------- | ---------------------------------------------------- |
| `<input_file>` | File dữ liệu định dạng SPMF                          |
| `<minsup>`     | Minimum support (`10%`, `0.1`, `500`, ...)           |
| `<task>`       | `mine` hoặc `rules`                                  |
| `<version>`    | `a1` hoặc `a2`                                       |
| `[minconf]`    | Minimum confidence cho luật kết hợp (mặc định `0.5`) |

---

# 5. Các phiên bản thuật toán

## A1 — TID-list Vertical Mining

File:

```text
src/LCM_A1_TIDList.jl
```

Đặc điểm:

* Vertical database representation
* Sorted TID-list intersection
* Closure checking bằng inclusion test
* PPC-style pruning
* Tương thích cao với logic LCM cổ điển

Phù hợp:

* Sparse datasets
* Datasets vừa và lớn

---

## A2 — BitVector Optimized Mining

File:

```text
src/LCM_A2_BitVector.jl
```

Đặc điểm:

* BitVector representation
* Chunk-level bit operations
* Bitwise intersection (`AND`)
* Closure checking bằng subset-bit test
* Tối ưu mạnh cho dense datasets

Phù hợp:

* Dense datasets
* Dataset có nhiều giao nhau

---

# 6. Ví dụ sử dụng

## 6.1. Khai phá closed frequent itemsets

```bash
julia --project run_lcm.jl data/retail.txt "1%" mine a1
```

Kết quả:

```text
results/retail_mine_a1.txt
```

---

## 6.2. Sinh association rules

```bash
julia --project run_lcm.jl data/mushrooms.txt "5%" rules a1 0.6
```

Kết quả:

```text
results/mushrooms_rules_a1.txt
```

---

## 6.3. Chạy phiên bản BitVector

```bash
julia --project run_lcm.jl data/mushrooms.txt "5%" rules a2 0.6
```

---

# 9. Chạy Unit Tests

```bash
julia --project test/runtests.jl
```

Các test bao gồm:

* Correctness của closed itemsets
* So sánh với output chuẩn SPMF
* Association rule generation
* Parsing minsup
* SPMF I/O compatibility

---

# 10. Datasets sử dụng

| Dataset           | Mô tả                           |
| ----------------- | ------------------------------- |
| mushrooms         | Dense dataset                   |
| retail            | Sparse market basket dataset    |
| chess             | Dense combinational dataset     |
| accidents         | Large sparse dataset            |
| contextPasquier99 | Dataset kinh điển trong FCA/LCM |

---

# 11. Các tối ưu hóa đã áp dụng

## A1

* Sorted TID-list intersection
* Int32 compression
* Early pruning bằng support
* PPC-style canonical expansion
* Closure-based mining

## A2

* BitVector compression
* Chunk-level subset checking
* Bitwise intersection
* Reduced allocation strategy

---

# 12. Benchmark mẫu

Ví dụ benchmark trên dataset mushrooms:

| Version | Time               | Closed Itemsets |
| ------- | ------------------ | --------------- |
| A1      | ~4s                | ~4.1M           |
| A2      | phụ thuộc cấu hình | tương đương     |

(Lưu ý: thời gian thực tế phụ thuộc CPU/RAM.)

---

# 13. Mục tiêu học thuật

Project hướng đến:

* Hiểu cơ chế hoạt động của LCM
* Vertical mining
* Closure systems
* Association rule generation
* Tối ưu hóa thuật toán khai phá dữ liệu bằng Julia

Đây không phải bản re-implementation đầy đủ của LCM research-grade gốc, nhưng giữ các ý tưởng cốt lõi:

* Closure mining
* PPC-style pruning
* Vertical database representation

---

# 14. License

MIT License
