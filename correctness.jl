#!/usr/bin/env julia
# correctness.jl: So sánh support theo từng tập phổ biến giữa LCM Julia của
# nhóm (A0/A1/A2) và SPMF Java tham chiếu.
#
# So sánh số lượng tập phổ biến VÀ support của
# từng tập giữa cài đặt nhóm và SPMF. Báo cáo tỷ lệ khớp hoàn toàn;
# phân tích nguyên nhân nếu sai lệch.
#
# Xuất: results/correctness.csv với các cột
#   dataset,minsup,version,n_spmf,n_julia,n_intersect,
#   n_support_match,recall,precision,jaccard,exact_match_rate

using Printf, Dates, Downloads

const JAVA = Sys.which("java")
isnothing(JAVA) && error("Khong tim thay 'java' trong PATH. Hay cai dat JDK 21+ va them vao PATH.")
const SPMF_URL = "https://www.philippe-fournier-viger.com/spmf/spmf.jar"
const RESULTS  = joinpath(@__DIR__, "results")
isdir(RESULTS) || mkpath(RESULTS)

# Tập dữ liệu và lưới minsup (trùng benchmark.jl)
# Dùng cùng lưới 4-minsup để bảng đối chiếu khớp trực tiếp với
# bảng thời gian chạy.
const DATASETS = [
    ("chess",     "data/chess.txt"),
    ("mushrooms", "data/mushrooms.txt"),
    ("retail",    "data/retail.txt"),
    ("accidents", "data/accidents.txt"),
]
const MINSUPS = Dict(
    "chess"     => [0.95, 0.90, 0.85, 0.80, 0.70, 0.60],
    "mushrooms" => [0.70, 0.50, 0.30, 0.20, 0.10, 0.05],
    "retail"    => [0.10, 0.05, 0.01, 0.005, 0.002, 0.001],
    "accidents" => [0.95, 0.90, 0.85, 0.80, 0.70, 0.60],
)
const VERSIONS = ["a0", "a1", "a2"]

# Thêm: stress test tại minsup thấp nhất khả thi của mỗi tập dữ liệu để
# chủ động dò lỗi.  Bỏ qua các điểm quá tốn kém cho a1/a2.
const STRESS = Dict(
    "chess"     => 0.50,   # ~145s cho a0 tại 0.5; vẫn thử
    "mushrooms" => 0.01,   # mushrooms tại 0.01 khả thi
    "retail"    => 0.0005, # retail@0.0005; đẩy tới biên
    "accidents" => 0.50,   # accidents@0.5 tương tự Chess (chỉ A0 baseline)
)

# Khởi tạo
# Tải spmf.jar nếu chưa có
function ensure_spmf()
    if !isfile(joinpath(@__DIR__, "spmf.jar"))
        println("=> Đang tải spmf.jar ...")
        Downloads.download(SPMF_URL, joinpath(@__DIR__, "spmf.jar"))
    end
end

# Bộ phân tích
"""
Phân tích file định dạng SPMF thành `Dict{Vector{Int}, Int}` ánh xạ tập mục
(đã sắp xếp) --> support.  Bỏ qua dòng trống và header @CONVERTED_FROM (nếu có).
"""
function parse_spmf_output(path::AbstractString)
    out = Dict{Vector{Int}, Int}()
    isfile(path) || return out
    for line in eachline(path)
        line = strip(line)
        isempty(line) && continue
        startswith(line, "@") && continue
        # Định dạng: "5 29 34 #SUP: 2964"
        sup_idx = findfirst("#SUP:", line)
        if sup_idx === nothing
            continue
        end
        left  = strip(line[1:sup_idx[1]-1])
        right = strip(line[sup_idx[1]+5:end])
        items = isempty(left) ? Int[] :
                parse.(Int, split(left))
        sup   = parse(Int, right)
        sort!(items)
        out[items] = sup
    end
    return out
end

# Đếm số giao dịch trong file SPMF
function n_transactions(file::AbstractString)
    n = 0
    open(file) do io
        for _ in eachline(io)
            n += 1
        end
    end
    return n
end

# Tính minsup tuyệt đối từ minsup tương đối (theo số giao dịch)
function abs_minsup(ms::Float64, n::Int)
    return max(1, round(Int, ms * n))
end

# Bộ chạy
# Gọi SPMF Java: tham số minsup là tương đối (0,1]; 0.9 nghĩa là 0.9%
function run_spmf(input, minsup_rel, spmf_out)
    cmd = `$(JAVA) -jar spmf.jar run LCM $(input) $(spmf_out) $(minsup_rel)`
    return @elapsed run(ignorestatus(cmd))
end

# Gọi Julia LCM thông qua run_lcm.jl (driver sản xuất)
function run_julia(input, minsup_pct, version, jl_out)
    cmd = `julia --project run_lcm.jl $(input) $(minsup_pct) mine $(version)`
    return @elapsed run(cmd)
end

# So sánh theo (tập dữ liệu, minsup, phiên bản)
# Trả về các chỉ số: recall, precision, Jaccard, tỷ lệ khớp support hoàn toàn
function compare_one(dataset, file, minsup_pct, version; stress=false)
    n       = n_transactions(file)
    absms   = abs_minsup(minsup_pct, n)
    spmf_o  = joinpath(RESULTS, "$(dataset)_spmf.txt")
    jl_o    = joinpath(RESULTS, "$(dataset)_mine_$(version).txt")

    t_spmf = run_spmf(file, minsup_pct, spmf_o)
    t_jl   = run_julia(file, string(minsup_pct * 100) * "%", version, jl_o)

    A = parse_spmf_output(spmf_o)   # SPMF (tham chiếu)
    B = parse_spmf_output(jl_o)     # Julia (của nhóm)

    nA, nB        = length(A), length(B)
    n_intersect   = count(k -> haskey(B, k), keys(A))
    n_sup_match   = count(k -> get(B, k, -1) == A[k], keys(A))
    recall        = nA == 0 ? 1.0 : n_intersect / nA
    precision     = nB == 0 ? 1.0 : n_intersect / nB
    jaccard       = (nA + nB - n_intersect) == 0 ? 1.0 :
                    n_intersect / (nA + nB - n_intersect)
    exact_rate    = nA == 0 ? 1.0 : n_sup_match / nA

    # Chẩn đoán sai lệch (chỉ phát ra log khi có)
    only_in_spmf = filter(k -> !haskey(B, k), keys(A))
    only_in_jl   = filter(k -> !haskey(A, k), keys(B))
    sup_diff     = filter(k -> haskey(B, k) && B[k] != A[k], keys(A))

    @printf("  %-10s ms=%.4f v=%s  |SPMF|=%5d  |JL|=%5d  |∩|=%5d  sup↔=%5d  exact=%.4f  (%.2fs+%.2fs)\n",
            dataset, minsup_pct, version, nA, nB, n_intersect, n_sup_match,
            exact_rate, t_spmf, t_jl)

    return (dataset=dataset, minsup=minsup_pct, version=version,
            n_spmf=nA, n_julia=nB, n_intersect=n_intersect,
            n_support_match=n_sup_match,
            recall=recall, precision=precision, jaccard=jaccard,
            exact_match_rate=exact_rate,
            n_only_spmf=length(only_in_spmf),
            n_only_julia=length(only_in_jl),
            n_sup_diff=length(sup_diff),
            t_spmf=t_spmf, t_julia=t_jl,
            stress=stress)
end

# Hàm chính
function main()
    ensure_spmf()
    rows = []
    spmf_rows = Dict{Tuple{String,Float64}, NamedTuple{(:t_spmf, :n_spmf), Tuple{Float64,Int}}}()
    println("=== So sánh support từng tập: Julia LCM vs Java SPMF ===\n")
    for (name, file) in DATASETS
        for ms in MINSUPS[name]
            for v in VERSIONS
                result = compare_one(name, file, ms, v)
                push!(rows, result)
                # Ghi nhận thời gian SPMF (một lần duy nhất cho mỗi (dataset, minsup))
                key = (name, ms)
                if !haskey(spmf_rows, key)
                    # Đọc lại từ file SPMF vừa tạo để lấy n_spmf
                    spmf_o = joinpath(RESULTS, "$(name)_spmf.txt")
                    n_spmf = length(parse_spmf_output(spmf_o))
                    spmf_rows[key] = (t_spmf=result.t_spmf, n_spmf=n_spmf)
                end
            end
        end
    end
    # Stress test (chỉ A0: baseline sạch nhất)
    for (name, file) in DATASETS
        try
            result = compare_one(name, file, STRESS[name], "a0"; stress=true)
            push!(rows, result)
            key = (name, STRESS[name])
            if !haskey(spmf_rows, key)
                spmf_o = joinpath(RESULTS, "$(name)_spmf.txt")
                n_spmf = length(parse_spmf_output(spmf_o))
                spmf_rows[key] = (t_spmf=result.t_spmf, n_spmf=n_spmf)
            end
        catch e
            @warn "Stress test thất bại cho $name @ $(STRESS[name])" exception=e
        end
    end

    out = joinpath(RESULTS, "correctness.csv")
    open(out, "w") do io
        println(io, "dataset,minsup,version,n_spmf,n_julia,n_intersect,n_support_match,recall,precision,jaccard,exact_match_rate,n_only_spmf,n_only_julia,n_sup_diff,stress")
        for r in rows
            println(io, join([
                r.dataset, r.minsup, r.version, r.n_spmf, r.n_julia,
                r.n_intersect, r.n_support_match,
                round(r.recall, digits=6), round(r.precision, digits=6),
                round(r.jaccard, digits=6), round(r.exact_match_rate, digits=6),
                r.n_only_spmf, r.n_only_julia, r.n_sup_diff, r.stress
            ], ","))
        end
    end
    println("\nĐã ghi $out")

    # Ghi thời gian SPMF (Java) cho mỗi (dataset, minsup), dùng để vẽ đường SPMF
    spmf_out = joinpath(RESULTS, "spmf_runtime.csv")
    open(spmf_out, "w") do io
        println(io, "dataset,minsup,t_spmf_s,n_spmf")
        # Sắp xếp theo thứ tự DATASETS rồi MINSUPS để ổn định
        for (name, _) in DATASETS
            for ms in MINSUPS[name]
                key = (name, ms)
                if haskey(spmf_rows, key)
                    r = spmf_rows[key]
                    println(io, "$name,$ms,$(r.t_spmf),$(r.n_spmf)")
                end
            end
            # Thêm stress test point nếu có
            key = (name, STRESS[name])
            if haskey(spmf_rows, key) && !(STRESS[name] in MINSUPS[name])
                r = spmf_rows[key]
                println(io, "$name,$(STRESS[name]),$(r.t_spmf),$(r.n_spmf)")
            end
        end
    end
    println("Đã ghi $spmf_out")
end

main()
