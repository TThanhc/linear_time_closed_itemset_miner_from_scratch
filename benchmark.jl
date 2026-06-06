#!/usr/bin/env julia
# benchmark.jl: Bộ benchmark rút gọn cho Chương 4
# Bỏ qua các điểm minsup mà a0 trên chess mất >30s; dùng best_of 2.
using Printf, Statistics, Dates

include("src/LCM_A0_PaperBaseline.jl")
include("src/LCM_A1_TIDList.jl")
include("src/LCM_A2_BitVector.jl")

const JAVA = Sys.which("java")
isnothing(JAVA) && error("Khong tim thay 'java' trong PATH. Hay cai dat JDK 21+ va them vao PATH.")
const SPMF_JAR = joinpath(@__DIR__, "spmf.jar")

using .LCM_A0_PaperBaseline
using .LCM_A1_TIDList
using .LCM_A2_BitVector

const RESULTS = joinpath(@__DIR__, "results")
const IMAGE   = joinpath(@__DIR__, "Report", "image")
isdir(RESULTS) || mkpath(RESULTS)
isdir(IMAGE)   || mkpath(IMAGE)

# Lưới minsup khả thi, đã rút gọn
const DATASETS = [
    ("chess",     "data/chess.txt"),
    ("mushrooms", "data/mushrooms.txt"),
    ("retail",    "data/retail.txt"),
    ("accidents", "data/accidents.txt"),
]

# Chọn 6 điểm bao phủ cao --> thấp cho mỗi tập dữ liệu
const MINSUPS = Dict(
    "chess"     => [0.95, 0.90, 0.85, 0.80, 0.70, 0.60],   # dày đặc --> chỉ chạy minsup cao
    "mushrooms" => [0.70, 0.50, 0.30, 0.20, 0.10, 0.05],
    "retail"    => [0.10, 0.05, 0.01, 0.005, 0.002, 0.001],
    "accidents" => [0.95, 0.90, 0.85, 0.80, 0.70, 0.60],   # dày đặc + rất lớn, lưới giống Chess
)

const VERSIONS = ["a0", "a1", "a2"]

# Lấy bộ nhớ RSS hiện tại của tiến trình Julia (MB)
function mem_mb()
    try
        if Sys.iswindows()
            return round(Int, Base.Sys.maxrss() / 1024 / 1024)
        else
            return round(Int, parse(Int, read("/proc/self/status", String) |> s ->
                match(r"VmRSS:\s+(\d+)", s)[1]) / 1024)
        end
    catch
        return -1
    end
end

# Timeout per-dataset: accidents rất lớn nên cần nhiều thời gian hơn
const TIMEOUT_S = Dict(
    "chess"     => 60.0,
    "mushrooms" => 60.0,
    "retail"    => 60.0,
    "accidents" => 600.0,
)

# Chạy khai thác một lần theo phiên bản, trả về (giây, |out|, RSS MB, bytes cấp phát)
function run_once(version, file, absms, minsup_pct=nothing)
    if version == "a0"
        txs = LCM_A0_PaperBaseline.read_spmf_transactions(file)
        t0 = time()
        out = Ref{Any}(nothing)
        bytes = @allocated (out[] = LCM_A0_PaperBaseline.mine_closed_itemsets_paper(txs, absms))
        t  = time() - t0
    elseif version == "a1"
        txs = LCM_A1_TIDList.read_spmf_transactions(file)
        t0 = time()
        out = Ref{Any}(nothing)
        bytes = @allocated (out[] = LCM_A1_TIDList.mine_closed_itemsets_baseline(txs, absms))
        t  = time() - t0
    else
        txs = LCM_A2_BitVector.read_spmf_transactions(file)
        t0 = time()
        out = Ref{Any}(nothing)
        bytes = @allocated (out[] = LCM_A2_BitVector.mine_closed_itemsets_optimized(txs, absms))
        t  = time() - t0
    end
    GC.gc()
    return t, length(out[]), mem_mb(), bytes
end

# Lấy thời gian tốt nhất sau n lần chạy; nếu lần đầu đã vượt timeout thì bỏ lần sau
function best_of(version, file, absms, minsup_pct; n=2, timeout_s=120.0)
    ts, ns, ms, bys = Float64[], Int[], Int[], Int[]
    for i in 1:n
        t, nclosed, m, b = run_once(version, file, absms, minsup_pct)
        push!(ts, t); push!(ns, nclosed); push!(ms, m); push!(bys, b)
        if t > timeout_s && i == 1
            # Một lần đã quá chậm; ghi nhận rồi bỏ lần lặp tiếp
            break
        end
    end
    return minimum(ts), ns[argmin(ts)], maximum(ms), bys[argmin(ts)]
end

# Benchmark thời gian chạy theo minsup trên 3 tập dữ liệu
function benchmark_runtime()
    open(joinpath(RESULTS, "runtime.csv"), "w") do io
        println(io, "dataset,minsup,version,time_s,n_closed,memory_mb,bytes_alloc")
        for (name, file) in DATASETS
            txs = LCM_A0_PaperBaseline.read_spmf_transactions(file)
            ntrans = length(txs)
            for ms in MINSUPS[name]
                # Dùng cùng hàm parse như driver sản xuất để minsup tuyệt đối
                # khớp với verify_spmf.jl / run_lcm.jl.
                absms = LCM_A0_PaperBaseline.parse_minsup_to_absolute(string(ms * 100) * "%", ntrans)
                for v in VERSIONS
                    t, n, m, b = best_of(v, file, absms, ms; n=2, timeout_s=TIMEOUT_S[name])
                    @printf("  %-10s ms=%.3f v=%s  t=%.3fs  #closed=%d  mem=%dMB  alloc=%.1fMB\n",
                            name, ms, v, t, n, m, b/1024/1024)
                    println(io, "$name,$ms,$v,$t,$n,$m,$b")
                end
            end
        end
    end
end

# Benchmark bộ nhớ tại minsup trung vị của mỗi tập dữ liệu (peak RSS toàn process)
function benchmark_memory()
    open(joinpath(RESULTS, "memory.csv"), "w") do io
        println(io, "dataset,version,time_s,n_closed,memory_mb")
        for (name, file) in DATASETS
            txs = LCM_A0_PaperBaseline.read_spmf_transactions(file)
            ntrans = length(txs)
            ms = MINSUPS[name][max(1, length(MINSUPS[name])÷2)]
            absms = LCM_A0_PaperBaseline.parse_minsup_to_absolute(string(ms * 100) * "%", ntrans)
            for v in VERSIONS
                t, n, m, _ = best_of(v, file, absms, ms; n=1, timeout_s=2*TIMEOUT_S[name])
                @printf("  %-10s v=%s  t=%.3fs  #closed=%d  mem=%dMB\n",
                        name, v, t, n, m)
                println(io, "$name,$v,$t,$n,$m")
            end
        end
    end
end

# Benchmark bộ nhớ cấp phát bởi thuật toán (`@allocated`) trên toàn bộ lưới minsup
function benchmark_memory_alloc()
    open(joinpath(RESULTS, "memory_alloc.csv"), "w") do io
        println(io, "dataset,minsup,version,bytes_alloc,time_s,n_closed")
        for (name, file) in DATASETS
            txs = LCM_A0_PaperBaseline.read_spmf_transactions(file)
            ntrans = length(txs)
            for ms in MINSUPS[name]
                absms = LCM_A0_PaperBaseline.parse_minsup_to_absolute(string(ms * 100) * "%", ntrans)
                for v in VERSIONS
                    t, n, _, b = best_of(v, file, absms, ms; n=2, timeout_s=TIMEOUT_S[name])
                    @printf("  %-10s ms=%.3f v=%s  alloc=%.2fMB  t=%.3fs  #closed=%d\n",
                            name, ms, v, b/1024/1024, t, n)
                    println(io, "$name,$ms,$v,$b,$t,$n")
                end
            end
        end
    end
end

# Trích tập con gồm frac phần đầu của tập dữ liệu (theo thứ tự dòng)
function take_subset(input, frac)
    lines = readlines(input)
    keep  = max(1, round(Int, frac * length(lines)))
    tmp   = tempname() * ".txt"
    open(tmp, "w") do io
        for l in lines[1:keep]
            println(io, l)
        end
    end
    return tmp
end

# Benchmark khả năng mở rộng theo kích thước dữ liệu (Retail, minsup cố định 1%)
function benchmark_scalability()
    file = "data/retail.txt"
    open(joinpath(RESULTS, "scalability.csv"), "w") do io
        println(io, "frac,version,time_s,n_closed")
        for frac in [0.10, 0.25, 0.50, 0.75, 1.00]
            tmp = take_subset(file, frac)
            txs = LCM_A0_PaperBaseline.read_spmf_transactions(tmp)
            ntrans = length(txs)
            ms = 0.01
            absms = LCM_A0_PaperBaseline.parse_minsup_to_absolute("1%", ntrans)
            for v in VERSIONS
                t, n, _, _ = best_of(v, tmp, absms, ms; n=1, timeout_s=90.0)
                @printf("  frac=%.2f v=%s  t=%.3fs  #closed=%d\n", frac, v, t, n)
                println(io, "$frac,$v,$t,$n")
            end
            rm(tmp)
        end
    end
end

# Tính độ dài trung bình của giao dịch trong file SPMF
function avg_transaction_length(file)
    total, n = 0, 0
    for line in eachline(file)
        total += length(split(line))
        n += 1
    end
    return total / max(1, n)
end

# Gọi SPMF Java, trả về thời gian (giây) hoặc -1.0 nếu thất bại
function run_spmf_time(file, absms, ntrans)
    if !isfile(SPMF_JAR) || !isfile(JAVA)
        @warn "SPMF không khả dụng (thiếu spmf.jar hoặc java.exe)"
        return -1.0
    end
    out = tempname() * ".txt"
    minsup_rel = absms / ntrans  # SPMF nhận phân số (0.30 = 30%)
    cmd = `$(JAVA) -jar $(SPMF_JAR) run LCM $file $out $minsup_rel`
    t0 = time()
    ok = false
    err_msg = ""
    try
        run(pipeline(cmd, stdout=devnull, stderr=devnull))
        ok = isfile(out) && filesize(out) > 0
    catch e
        err_msg = sprint(showerror, e)
        ok = false
    end
    t = time() - t0
    rm(out, force=true)
    if !ok && !isempty(err_msg)
        @warn "SPMF thất bại cho $file" err_msg
    end
    return ok ? t : -1.0
end

# Benchmark ảnh hưởng độ dài giao dịch: dùng CSDL tổng hợp sinh bởi gen_synthetic.jl
# (Bernoulli, p = L/119, seed 42, m = 8124, n = 119)
function benchmark_txn_length()
    lengths = [50, 60, 70, 80]
    minsup_str = "30%"  # 2438 giao dịch tuyệt đối trên tổng 8124
    open(joinpath(RESULTS, "txn_length.csv"), "w") do io
        println(io, "L,avg_len,version,time_s,n_closed,time_spmf_s")
        for L in lengths
            file = "data/synthetic_l$(L).txt"
            isfile(file) || error("Thiếu $file; chạy gen_synthetic.jl trước")
            txs = LCM_A0_PaperBaseline.read_spmf_transactions(file)
            ntrans = length(txs)
            avglen = avg_transaction_length(file)
            absms = LCM_A0_PaperBaseline.parse_minsup_to_absolute(minsup_str, ntrans)
            t_spmf = run_spmf_time(file, absms, ntrans)
            for v in VERSIONS
                t, n, _, _ = best_of(v, file, absms, 0.30; n=1, timeout_s=600.0)
                @printf("  L=%3d  avglen=%.2f  v=%s  t=%.3fs  #closed=%d  spmf=%.3fs\n",
                        L, avglen, v, t, n, t_spmf)
                println(io, "$L,$avglen,$v,$t,$n,$t_spmf")
            end
        end
    end
end

println("=== Bộ benchmark Chương 4 (đã rút gọn) ===")
println("Thời gian: ", now())
if abspath(PROGRAM_FILE) == @__FILE__
    println("\n[1/5] Thời gian chạy theo minsup ...")
    benchmark_runtime()
    println("\n[2/5] Bộ nhớ peak RSS tại minsup trung vị ...")
    benchmark_memory()
    println("\n[3/5] Bộ nhớ cấp phát bởi thuật toán (toàn lưới minsup) ...")
    benchmark_memory_alloc()
    println("\n[4/5] Khả năng mở rộng (retail) ...")
    benchmark_scalability()
    println("\n[5/5] Ảnh hưởng độ dài giao dịch (CSDL tổng hợp Bernoulli) ...")
    benchmark_txn_length()
    println("\n=== Hoàn tất. CSV ở results/ ===")
end
