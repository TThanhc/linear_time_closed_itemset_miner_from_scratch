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
|   final-report.pdf
│   run_lcm.jl
│   benchmark.jl
│   correctness.jl
│   gen_synthetic.jl
│   verify_spmf.jl
├───data 
│       accidents.txt
│       chess.txt
│       contextPasquier99.txt
│       expected_output_contextPasquier99_spmf.txt
│       mushrooms.txt
│       output_lcm_contextPasquier99.txt
│       retail.txt
│       synthetic_l50.txt
│       synthetic_l60.txt
│       synthetic_l70.txt
│       synthetic_l80.txt
│
├───results
│       runtime.csv
│       memory.csv
│       memory_alloc.csv
│       correctness.csv
│       scalability.csv
│       txn_length.csv
│       spmf_runtime.csv
│       <dataset>_mine_a{0,1,2}.txt   (12 file)
│       <dataset>_spmf.txt           (4 file)
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

# 7. Benchmark và đánh giá

Ba script bổ sung dùng để tái sản xuất toàn bộ số liệu (4 dataset × 6 minsup × 3 version + 4 stress test = 76 trường hợp, tất cả đạt 100% khớp SPMF).

## 7.1. `benchmark.jl`, đo runtime và bộ nhớ

Chạy toàn bộ benchmark trên 4 dataset (`chess`, `mushrooms`, `retail`, `accidents`) với 6 điểm minsup/tập và cả 3 phiên bản (A0, A1, A2) = 72 trường hợp Julia, cộng SPMF-Java baseline 24 trường hợp. Đo runtime, peak RSS, byte cấp phát (`@allocated`), số closed itemsets.

```bash
julia --project benchmark.jl       # khoảng 4 giờ
```

Output:

| File                       | Nội dung                                                             |
| -------------------------- | -------------------------------------------------------------------- |
| `results/runtime.csv`      | (dataset, minsup, version, time_s, n_closed, memory_mb, bytes_alloc) |
| `results/memory.csv`       | peak RSS tại minsup trung bình của mỗi dataset                       |
| `results/memory_alloc.csv` | byte cấp phát qua tất cả các ngưỡng (72 dòng)                        |
| `results/spmf_runtime.csv` | runtime SPMF-Java tương ứng (24 dòng)                                |

## 7.2. `correctness.jl`, đối chiếu per-itemset với SPMF

Tự động tải `spmf.jar` (~16MB) về thư mục gốc nếu chưa có. Với mỗi (dataset, minsup, version), sinh output Julia rồi so sánh từng itemset + support với SPMF-Java. Ghi 4 chỉ số recall / precision / Jaccard / exact-match.

```bash
julia --project correctness.jl     # cần Java 21+ trên PATH
```

Output: `results/correctness.csv`, 76 dòng (72 + 4 stress), **tất cả 100% exact match**, tổng ~937K itemsets so sánh.

## 7.3. `gen_synthetic.jl`, CSDL tổng hợp

Sinh 4 CSDL Bernoulli độc lập với m = 8124 giao dịch, n = 119 item, seed = 42, độ dài giao dịch L ∈ {50, 60, 70, 80} (xác suất mỗi item xuất hiện p = L/n). Minsup tuyệt đối = 2438 (= 30% × 8124).

```bash
julia --project gen_synthetic.jl
```

Output: `data/synthetic_l{50,60,70,80}.txt`, dùng cho thí nghiệm ảnh hưởng độ dài giao dịch.

## 7.4. Yêu cầu Java 21+

`correctness.jl` và `verify_spmf.jl` gọi SPMF thông qua `java`. Script tự động phát hiện `java` trên PATH:

```julia
const JAVA = Sys.which("java")
isnothing(JAVA) && error("Khong tim thay 'java' trong PATH. Hay cai dat JDK 21+ va them vao PATH.")
```

Nếu không có Java trên PATH, script báo lỗi rõ ràng. Ngoài ra có thể đặt biến `JAVA_HOME` rồi thêm `$(JAVA_HOME)/bin` vào PATH.

## 7.5. Bảng đầu ra CSV (data source cho báo cáo)

| File                       | Cột chính                                        | Dùng cho mục |
| -------------------------- | ------------------------------------------------ | ------------ |
| `results/runtime.csv`      | dataset, minsup, version, time_s, n_closed       | 4.4          |
| `results/spmf_runtime.csv` | dataset, minsup, t_spmf_s, n_spmf                | 4.4          |
| `results/memory.csv`       | dataset, version, time_s, n_closed, memory_mb    | 4.6          |
| `results/memory_alloc.csv` | dataset, minsup, version, bytes_alloc            | 4.6          |
| `results/correctness.csv`  | dataset, minsup, version, recall, precision, ... | 4.3          |
| `results/scalability.csv`  | (Retail prefix 10/25/50/75/100%)                 | 4.7          |
| `results/txn_length.csv`   | (Synthetic Bernoulli L = 50/60/70/80)            | 4.8          |

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
julia --project verify_spmf.jl <input_file> <minsup> <version>
```

Ví dụ kiểm chứng A0 trên tập Retail:

```bash
julia --project verify_spmf.jl data/retail.txt "1%" a0
```

---

# 10. Datasets sử dụng

| Dataset                    | #Trans  | #Items | AvgLen  | Đặc điểm             | Lưới minsup                               | Kích thước   |
| -------------------------- | ------- | ------ | ------- | -------------------- | ----------------------------------------- | ------------ |
| `chess`                    | 3,196   | 75     | 37.0    | Dày đặc              | `[0.95, 0.90, 0.85, 0.80, 0.70, 0.60]`    | 337 KB       |
| `mushrooms`                | 8,124   | 119    | 23.0    | Dày đặc              | `[0.70, 0.50, 0.30, 0.20, 0.10, 0.05]`    | 598 KB       |
| `retail`                   | 88,162  | 16,470 | 10.3    | Thưa                 | `[0.10, 0.05, 0.01, 0.005, 0.002, 0.001]` | 4.0 MB       |
| `accidents`                | 340,183 | 468    | 33.8    | Rất lớn, dày đặc     | `[0.95, 0.90, 0.85, 0.80, 0.70, 0.60]`    | 34.2 MB      |
| `contextPasquier99`        | 10      | 5      | N/A     | Toy / unit test      | (chỉ test)                                | 35 B         |
| `synthetic_l{50,60,70,80}` | 8,124   | 119    | 50 - 80 | Bernoulli, p = L/119 | minsup = 30% tuyệt đối (= 2438 giao dịch) | 1.2 - 2.0 MB |

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

Số liệu trích từ `results/runtime.csv` (đo trên Windows 11, AMD CPU, 16 GB RAM, Julia 1.10, Java 26):

| Dataset   | minsup | A0 (ms) | A1 (ms) | A2 (ms) | SPMF (ms) | #Closed |
| --------- | ------ | ------- | ------- | ------- | --------- | ------- |
| chess     | 0.60   | 52,216  | 11,118  | 1,066   | 15,184    | 98,392  |
| chess     | 0.95   | 14      | 16      | 2       | 215       | 73      |
| mushrooms | 0.05   | 2,941   | 2,467   | 190     | 1,660     | 12,789  |
| retail    | 0.001  | 1,061   | 60,650  | 204,588 | 13,654    | 7,572   |
| retail    | 0.10   | 43      | 3,176   | 632     | 487       | 9       |
| accidents | 0.60   | 89,549  | 197,383 | 6,636   | 35,616    | 2,074   |
| accidents | 0.95   | 861     | 2,703   | 316     | 1,206     | 15      |

Tổng quan: trên dữ liệu dày (chess, mushrooms, accidents), A2 nhanh nhất và vượt SPMF 3 - 200 lần; trên dữ liệu thưa (retail), A0 nhanh nhất và vượt SPMF 6 - 13 lần. Đầy đủ 24 dòng ở `results/runtime.csv`.

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
