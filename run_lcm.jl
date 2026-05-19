#!/usr/bin/env julia

include(joinpath(@__DIR__, "src", "LCMClosedMining.jl"))
using .LCMClosedMining

function parse_args(args::Vector{String})
    length(args) < 3 && error("Usage: julia --project run_lcm.jl <input.txt> <minsup|40%|0.4|2> <output.txt> [baseline|optimized]")
    input = args[1]
    minsup_raw = args[2]
    output = args[3]
    mode = length(args) >= 4 ? lowercase(args[4]) : "optimized"
    mode in ("baseline", "optimized") || error("Mode must be baseline or optimized")
    return input, minsup_raw, output, mode
end

function main()
    input, minsup_raw, output, mode = parse_args(ARGS)
    txs = read_spmf_transactions(input)
    abs_minsup = parse_minsup_to_absolute(minsup_raw, length(txs))
    results = mode == "baseline" ?
        mine_closed_itemsets_baseline(txs, abs_minsup) :
        mine_closed_itemsets_optimized(txs, abs_minsup)
    write_spmf_closed_itemsets(output, results)
    println("Mode: ", mode)
    println("Transactions: ", length(txs))
    println("Absolute minsup: ", abs_minsup)
    println("Closed frequent itemsets: ", length(results))
    println("Output: ", output)
end

main()
