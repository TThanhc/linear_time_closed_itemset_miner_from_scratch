# LCM Closed Frequent Itemset Mining

Dự án tách thành 2 phiên bản: `baseline` và `optimized`.

## Cấu trúc

- `src/LCMClosedMining.jl`: Module thuật toán (đọc file, mining, ghi kết quả).
- `run_lcm.jl`: CLI chạy mining.
- `test/runtests.jl`: Unit test độ đúng (đối chiếu với brute-force trên 5 CSDL mẫu).
- `test/generate_samples.jl`: Sinh thêm CSDL mẫu ngẫu nhiên để bạn tuỳ chỉnh.
- `toy/*.txt`: 5 tập toy mẫu.

## Cách chạy

### 1) Chạy thuật toán

```bash
julia --project run_lcm.jl toy/toy1.txt 2 output_toy1.txt optimized
```

Hoặc minsup theo tỉ lệ (`0.4` hoặc `40%` đều hợp lệ):

```bash
julia --project run_lcm.jl toy/toy1.txt 40% output_toy1.txt baseline
```

- Nếu `minsup < 1`: hiểu là tỉ lệ, tự động đổi sang support tuyệt đối.
- Nếu `minsup` dạng `%` (VD `40%`): tự động đổi sang support tuyệt đối.
- Nếu `minsup >= 1`: hiểu là support tuyệt đối.

- `mode`:
  - `baseline`: bản cơ bản, dễ hiểu và đối chiếu tính đúng.
  - `optimized`: bản tối ưu theo hướng LCM (BitVector + closure + PPC extension).

### 2) Chạy test

```bash
julia --project test/runtests.jl
```

## Kiểm chứng với ví dụ SPMF LCM

Chạy:

```bash
julia --project run_lcm.jl data/contextPasquier99.txt 40% data/output_contextPasquier99_optimized.txt optimized
```

Nội dung kết quả phải trùng khớp theo tập pattern/support với:

`data/expected_output_contextPasquier99_spmf.txt`

### 3) Sinh thêm dữ liệu mẫu

```bash
julia --project test/generate_samples.jl
```

## Định dạng input/output SPMF

- Input: mỗi dòng là 1 giao dịch, item cách nhau bởi dấu cách.
- Output: dạng

```text
1 2 5 #SUP: 7
3 4 #SUP: 9
```

## Ghi chú kỹ thuật

- Tối ưu bộ nhớ/tốc độ bằng `BitVector` cho tidset (bản optimized).
- Dùng ppc-extension condition để tránh sinh trùng closed itemset (bản optimized):
  - `min(C \\ P) == e`, với `C = closure(P ∪ {e})`.
- Bản baseline sử dụng cách liệt kê để đối chiếu tính đúng, không tối ưu cho CSDL lớn.
- Triển khai from-scratch, không dùng thư viện FIM.
