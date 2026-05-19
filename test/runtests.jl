using Test

include(joinpath(@__DIR__, "..", "src", "LCMClosedMining.jl"))
using .LCMClosedMining

function all_subsets(items::Vector{Int})
    n = length(items)
    out = Vector{Vector{Int}}()
    for mask in 0:(2^n - 1)
        s = Int[]
        for i in 1:n
            if ((mask >> (i - 1)) & 1) == 1
                push!(s, items[i])
            end
        end
        push!(out, s)
    end
    return out
end

function brute_closed_frequent(transactions::Vector{Vector{Int}}, minsup::Int)
    items = sort(unique(vcat(transactions...)))
    txsets = [Set(t) for t in transactions]
    candidates = all_subsets(items)
    out = Dict{Tuple{Vararg{Int}}, Int}()

    for s in candidates
        sset = Set(s)
        tids = [i for (i, t) in enumerate(txsets) if all(x in t for x in sset)]
        supp = length(tids)
        supp < minsup && continue

        closed = true
        for x in items
            x in sset && continue
            if all(x in txsets[i] for i in tids)
                closed = false
                break
            end
        end
        closed || continue
        out[Tuple(sort(s))] = supp
    end
    return out
end

@testset "LCM closed itemset mining correctness" begin
    datasets = [
        (
            [[1,2,3],[1,2],[1,3],[2,3],[1,2,3]],
            2
        ),
        (
            [[1,2],[1,2],[1,2,3],[1,3],[2,3],[3]],
            2
        ),
        (
            [[1,4],[2,4],[1,2,4],[1,2],[2],[1]],
            2
        ),
        (
            [[1,2,3,4],[1,2,4],[2,3,4],[2,4],[1,4]],
            2
        ),
        (
            [[10,20],[10,30],[20,30],[10,20,30],[10],[20],[30]],
            2
        )
    ]

    for (txs, minsup) in datasets
        expected = brute_closed_frequent(txs, minsup)
        got_base = results_to_dict(mine_closed_itemsets_baseline(txs, minsup))
        got_opt = results_to_dict(mine_closed_itemsets_optimized(txs, minsup))
        @test got_base == expected
        @test got_opt == expected
    end
end

@testset "SPMF LCM example compatibility (content)" begin
    txs = [
        [1,3,4],
        [2,3,5],
        [1,2,3,5],
        [2,5],
        [1,2,3,5],
    ]
    minsup = 2
    expected = Dict(
        (3,) => 4,
        (1,3) => 3,
        (2,5) => 4,
        (2,3,5) => 3,
        (1,2,3,5) => 2,
    )
    @test results_to_dict(mine_closed_itemsets_baseline(txs, minsup)) == expected
    @test results_to_dict(mine_closed_itemsets_optimized(txs, minsup)) == expected

    @test parse_minsup_to_absolute("40%", 5) == 2
    @test parse_minsup_to_absolute("0.4", 5) == 2
    @test parse_minsup_to_absolute("2", 5) == 2
end

@testset "SPMF I/O parser compatibility" begin
    path = joinpath(@__DIR__, "..", "data", "contextPasquier99.txt")
    txs = read_spmf_transactions(path)
    @test txs == [[1,3,4],[2,3,5],[1,2,3,5],[2,5],[1,2,3,5]]

    out_path = joinpath(@__DIR__, "..", "data", "output_lcm_contextPasquier99.txt")
    results = mine_closed_itemsets_optimized(txs, 2)
    write_spmf_closed_itemsets(out_path, results)
    lines = readlines(out_path)
    @test length(lines) == 5
    @test all(occursin("#SUP:", ln) for ln in lines)
    expected_lines = readlines(joinpath(@__DIR__, "..", "data", "expected_output_contextPasquier99_spmf.txt"))
    @test lines == expected_lines
end

@testset "Baseline vs optimized on generated toy" begin
    for fn in ("toy1.txt", "toy2.txt", "toy3.txt", "toy4.txt", "toy5.txt")
        path = joinpath(@__DIR__, "..", "toy", fn)
        txs = read_spmf_transactions(path)
        minsup = 2
        @test results_to_dict(mine_closed_itemsets_baseline(txs, minsup)) ==
              results_to_dict(mine_closed_itemsets_optimized(txs, minsup))
    end
end
