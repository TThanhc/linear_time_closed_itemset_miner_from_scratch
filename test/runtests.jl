using Test

include(joinpath(@__DIR__, "..", "src", "LCM_A1_TIDList.jl"))
include(joinpath(@__DIR__, "..", "src", "LCM_A2_BitVector.jl"))

function results_to_dict(results)
    d = Dict{Tuple{Vararg{Int32}}, Int}()
    for r in results
        isempty(r.itemset) && continue
        d[Tuple(sort(r.itemset))] = r.support
    end
    return d
end

function all_subsets(items::Vector{T}) where T<:Integer
    n = length(items)
    out = Vector{Vector{T}}()
    for mask in 0:(2^n - 1)
        s = T[]
        for i in 1:n
            if ((mask >> (i - 1)) & 1) == 1 push!(s, items[i]) end
        end
        push!(out, s)
    end
    return out
end

function global_brute_force_baseline(transactions::Vector{Vector{Int32}}, minsup::Int)
    items = sort(unique(vcat(transactions...)))
    txsets = [Set(t) for t in transactions]
    candidates = all_subsets(items)
    out = Dict{Tuple{Vararg{Int32}}, Int}()
    
    for s in candidates
        isempty(s) && continue
        sset = Set(s)
        tids = [i for (i, t) in enumerate(txsets) if all(x in t for x in sset)]
        supp = length(tids)
        supp < minsup && continue
        
        closed = true
        for x in items
            x in sset && continue
            if all(x in txsets[i] for i in tids) closed = false; break end
        end
        closed || continue
        out[Tuple(sort(s))] = supp
    end
    return out
end

# ==============================================================================
# SUMMARY BLOCK 1: BRUTE-FORCE CORRECTNESS
# ==============================================================================
@testset "LCM closed itemset mining correctness" begin
    dense_datasets = [
        ([[1,2,3],[1,2],[1,3],[2,3],[1,2,3]], 2),
        ([[1,2],[1,2],[1,2,3],[1,3],[2,3],[3]], 2),
        ([[1,4],[2,4],[1,2,4],[1,2],[2],[1]], 2),
        ([[1,2,3,4],[1,2,4],[2,3,4],[2,4],[1,4]], 2),
        ([[10,20],[10,30],[20,30],[10,20,30],[10],[20],[30]], 2)
    ]

    for (idx, (raw_txs, minsup)) in enumerate(dense_datasets)
        txs = [Int32.(t) for t in raw_txs]
        expected = global_brute_force_baseline(txs, minsup)
        
        got_a1 = results_to_dict(LCM_A1_TIDList.mine_closed_itemsets_optimized(txs, minsup))
        @test got_a1 == expected
        
        got_a2 = results_to_dict(LCM_A2_BitVector.mine_closed_itemsets_optimized(txs, minsup))
        @test got_a2 == expected
    end
end

# ==============================================================================
# SUMMARY BLOCK 2: SPMF COMPATIBILITY & FILE I/O
# ==============================================================================
@testset "SPMF LCM example compatibility and I/O" begin
    raw_txs = [[1,3,4], [2,3,5], [1,2,3,5], [2,5], [1,2,3,5]]
    txs = [Int32.(t) for t in raw_txs]
    minsup = 2

    expected_spmf = Dict{Tuple{Vararg{Int32}}, Int}(
        (3,) => 4,
        (1,3) => 3,
        (2,5) => 4,
        (2,3,5) => 3,
        (1,2,3,5) => 2,
    )

    got_a1 = results_to_dict(LCM_A1_TIDList.mine_closed_itemsets_optimized(txs, minsup))
    @test got_a1 == expected_spmf

    got_a2 = results_to_dict(LCM_A2_BitVector.mine_closed_itemsets_optimized(txs, minsup))
    @test got_a2 == expected_spmf

    @test LCM_A1_TIDList.parse_minsup_to_absolute("40%", 5) == 2
    @test LCM_A2_BitVector.parse_minsup_to_absolute("0.4", 5) == 2
    @test LCM_A2_BitVector.parse_minsup_to_absolute("2", 5) == 2

    path = joinpath(@__DIR__, "..", "data", "contextPasquier99.txt")
    if !ispath(dirname(path)) mkpath(dirname(path)) end
    if !isfile(path)
        open(path, "w") do io write(io, "1 3 4\n2 3 5\n1 2 3 5\n2 5\n1 2 3 5\n") end
    end

    txs_disk = LCM_A2_BitVector.read_spmf_transactions(path)
    @test txs_disk == [[1,3,4],[2,3,5],[1,2,3,5],[2,5],[1,2,3,5]]

    out_path = joinpath(@__DIR__, "..", "data", "output_lcm_contextPasquier99.txt")
    results = LCM_A2_BitVector.mine_closed_itemsets_optimized(txs_disk, 2)
    LCM_A2_BitVector.write_spmf_closed_itemsets(out_path, results)
    
    lines = readlines(out_path)
    @test length(lines) == 5
    @test all(occursin("#SUP:", ln) for ln in lines)
end

# ==============================================================================
# SUMMARY BLOCK 3: TOY FILES CROSS-VALIDATION
# ==============================================================================
@testset "LCM cross-validation on toy datasets" begin
    for fn in ("toy1.txt", "toy2.txt", "toy3.txt", "toy4.txt", "toy5.txt")
        path = joinpath(@__DIR__, "..", "toy", fn)
        !isfile(path) && continue
        
        txs_a1 = LCM_A1_TIDList.read_spmf_transactions(path)
        txs_a2 = LCM_A2_BitVector.read_spmf_transactions(path)
        minsup = 2
        
        res_a1 = results_to_dict(LCM_A1_TIDList.mine_closed_itemsets_optimized(txs_a1, minsup))
        res_a2 = results_to_dict(LCM_A2_BitVector.mine_closed_itemsets_optimized(txs_a2, minsup))
        
        @test res_a1 == res_a2
    end
end

