module LCMClosedMining

export read_spmf_transactions,
       write_spmf_closed_itemsets,
       mine_closed_itemsets_baseline,
       mine_closed_itemsets_optimized,
       parse_minsup_to_absolute,
       results_to_dict

struct MiningResult
    itemset::Vector{Int}
    support::Int
end

function read_spmf_transactions(path::AbstractString)::Vector{Vector{Int}}
    txs = Vector{Vector{Int}}()
    open(path, "r") do io
        for raw in eachline(io)
            line = strip(raw)
            isempty(line) && continue
            startswith(line, "#") && continue
            startswith(line, "%") && continue
            startswith(line, "@") && continue
            items = parse.(Int, split(line))
            sort!(items)
            unique!(items)
            push!(txs, items)
        end
    end
    return txs
end

function write_spmf_closed_itemsets(path::AbstractString, results::Vector{MiningResult})
    open(path, "w") do io
        for r in results
            isempty(r.itemset) && continue
            println(io, join(r.itemset, " "), " #SUP: ", r.support)
        end
    end
end

function parse_minsup_to_absolute(minsup_raw::AbstractString, ntransactions::Int)::Int
    s = strip(minsup_raw)
    if endswith(s, "%")
        p = parse(Float64, chop(s; tail=1))
        p <= 0 && error("minsup percentage must be > 0")
        return max(1, ceil(Int, (p / 100.0) * ntransactions))
    end

    v = parse(Float64, s)
    if v <= 0
        error("minsup must be > 0")
    elseif v < 1
        return max(1, ceil(Int, v * ntransactions))
    else
        return floor(Int, v)
    end
end

function _collect_items(transactions::Vector{Vector{Int}})::Vector{Int}
    seen = Set{Int}()
    for t in transactions
        for x in t
            push!(seen, x)
        end
    end
    items = collect(seen)
    sort!(items)
    return items
end

function _build_tidsets(transactions::Vector{Vector{Int}}, items::Vector{Int})
    n = length(transactions)
    tids = Dict{Int, BitVector}()
    for item in items
        tids[item] = falses(n)
    end
    @inbounds for (tid, t) in enumerate(transactions)
        for item in t
            tids[item][tid] = true
        end
    end
    return tids
end

@inline function _support(bits::BitVector)::Int
    return count(bits)
end

function _closure_from_tidset(
    tidset::BitVector,
    items::Vector{Int},
    tids::Dict{Int, BitVector}
)::Vector{Int}
    c = Int[]
    for item in items
        # item is in closure iff every transaction of tidset contains item
        if isempty(findfirst(tidset)) || all((!tidset[i]) || tids[item][i] for i in eachindex(tidset))
            push!(c, item)
        end
    end
    return c
end

function mine_closed_itemsets_optimized(transactions::Vector{Vector{Int}}, minsup::Int)::Vector{MiningResult}
    n = length(transactions)
    n == 0 && return MiningResult[]

    items = _collect_items(transactions)
    tids = _build_tidsets(transactions, items)
    universe = trues(n)

    root = _closure_from_tidset(universe, items, tids)
    results = MiningResult[]
    seen = Set{Tuple{Vararg{Int}}}()

    function recurse(P::Vector{Int}, T::BitVector, tail::Int)
        supp = _support(T)
        supp < minsup && return

        if !isempty(P)
            key = Tuple(P)
            if !(key in seen)
                push!(seen, key)
                push!(results, MiningResult(copy(P), supp))
            end
        end

        for e in items
            e <= tail && continue
            e in P && continue

            Te = T .& tids[e]
            se = _support(Te)
            se < minsup && continue

            C = _closure_from_tidset(Te, items, tids)
            Pset = Set(P)
            new_items = [x for x in C if !(x in Pset)]
            isempty(new_items) && continue

            # PPC extension condition: smallest new item must be current extension item.
            minimum(new_items) == e || continue

            recurse(C, Te, e)
        end
    end

    recurse(root, universe, 0)
    sort!(results, by = r -> (length(r.itemset), r.itemset, r.support))
    return results
end

function mine_closed_itemsets_baseline(transactions::Vector{Vector{Int}}, minsup::Int)::Vector{MiningResult}
    n = length(transactions)
    n == 0 && return MiningResult[]

    txsets = [Set(t) for t in transactions]
    items = _collect_items(transactions)
    supp_map = Dict{Tuple{Vararg{Int}}, Int}()

    function support_of(itemset::Vector{Int})::Int
        sset = Set(itemset)
        c = 0
        @inbounds for t in txsets
            ok = true
            for x in sset
                if !(x in t)
                    ok = false
                    break
                end
            end
            c += ok
        end
        return c
    end

    function enum_subsets(prefix::Vector{Int}, start_idx::Int)
        s = support_of(prefix)
        if s >= minsup
            if !isempty(prefix)
                supp_map[Tuple(prefix)] = s
            end
            for i in start_idx:length(items)
                push!(prefix, items[i])
                enum_subsets(prefix, i + 1)
                pop!(prefix)
            end
        end
    end

    enum_subsets(Int[], 1)

    results = MiningResult[]
    keys_list = collect(keys(supp_map))
    for k in keys_list
        s = supp_map[k]
        closed = true
        ks = Set(k)
        for k2 in keys_list
            length(k2) <= length(k) && continue
            supp_map[k2] == s || continue
            if all(x in Set(k2) for x in ks)
                closed = false
                break
            end
        end
        closed && push!(results, MiningResult(collect(k), s))
    end

    sort!(results, by = r -> (length(r.itemset), r.itemset, r.support))
    return results
end

function results_to_dict(results::Vector{MiningResult})
    d = Dict{Tuple{Vararg{Int}}, Int}()
    for r in results
        d[Tuple(r.itemset)] = r.support
    end
    return d
end

end # module
