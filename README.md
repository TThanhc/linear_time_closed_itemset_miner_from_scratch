# Linear Time Closed Itemset Miner From Scratch (Julia)

Khai phá **Closed Frequent Itemsets** và sinh **Association Rules** bằng Julia, tương thích định dạng dữ liệu và đầu ra của SPMF.

Project triển khai:

* Phiên bản A0: Cài đặt chuẩn theo lý thuyết bài báo LCM (PPCE + Occurrence Deliver)
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
│       LCM_A0_PaperBaseline.jl
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
| `<version>`    | `a0`, `a1` hoặc `a2`                                 |
| `[minconf]`    | Minimum confidence cho luật kết hợp (mặc định `0.5`) |

---

# 5. Các phiên bản thuật toán

## A0 — LCM Paper Baseline (Original LCM)

File:

```text
src/LCM_A0_PaperBaseline.jl
```

Đặc điểm:

* Bám sát 100% thuật toán gốc trong bài báo LCM FIMI'03.
* Sử dụng PPCE (Prefix Preserving Closure Extension) để sinh cây tìm kiếm không trùng lặp mà không cần dùng bộ nhớ.
* Tích hợp Occurrence Deliver đếm tần suất với chi phí thời gian tuyến tính $\mathcal{O}(\|T\|)$.
* KHÔNG sử dụng cấu trúc lưu trữ kết quả (no `seen` array/storage method).
* Tự động lọc và đổi tên items (Item Renaming) giúp tối ưu hóa Buckets.
* **Chuẩn hóa SPMF:** Tự động loại bỏ tập rỗng (Empty Set) ngay từ trong RAM để đồng bộ hoàn toàn với thuật toán quốc tế.

Phù hợp:

* Benchmark tốc độ cốt lõi chuẩn LCM.
* Dữ liệu có cực nhiều tập đóng (chống tràn RAM).

---

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
* **Chuẩn hóa SPMF:** Tự động loại bỏ tập rỗng (Empty Set) khỏi kết quả để khớp 100% với SPMF.

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
* **Chuẩn hóa SPMF:** Tự động loại bỏ tập rỗng (Empty Set) khỏi kết quả để khớp 100% với SPMF.

Phù hợp:

* Dense datasets
* Dataset có nhiều giao nhau

---

# 6. Ví dụ sử dụng

## 6.1. Khai phá closed frequent itemsets

```bash
julia --project run_lcm.jl data/retail.txt "1%" mine a0
```

Kết quả:

```text
results/retail_mine_a0.txt
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

# 9. Kiểm thử và Đối chiếu

## 9.1. Chạy Unit Tests tự động

```bash
julia --project test/runtests.jl
```

Các test bao gồm:

* Correctness của closed itemsets
* So sánh với output chuẩn SPMF
* Association rule generation
* Parsing minsup
* SPMF I/O compatibility

## 9.2. Kiểm chứng chéo với thư viện Java gốc (SPMF)

Dự án tích hợp sẵn công cụ tự động tải thư viện Java SPMF và chạy đối chiếu số lượng tập đóng 1-1 với phiên bản Julia (yêu cầu máy tính cài đặt Java 21 trở lên).

Cú pháp:
```bash
julia verify_spmf.jl <input_file> <minsup> <version>
```

Ví dụ kiểm chứng A0 trên tập Retail:
```bash
julia verify_spmf.jl data/retail.txt "1%" a0
```

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

## A0

* Kỹ thuật Occurrence Deliver cho frequency counting tuyến tính
* Kỹ thuật Prefix Preserving Closure Extension (PPCE)
* Kỹ thuật Item Renaming để tiết kiệm RAM
* Loại bỏ hoàn toàn chi phí lưu trữ (Storage Method) chống trùng lặp

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
| A0      | nhanh nhất         | ~4.1M           |
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
