module LCM_A2_BitVector

export read_spmf_transactions,
       write_spmf_closed_itemsets,
       mine_closed_itemsets_baseline,
       mine_closed_itemsets_optimized,
       parse_minsup_to_absolute,
       results_to_dict

struct MiningResult
    itemset::Vector{Int32}
    support::Int
end

function read_spmf_transactions(path::AbstractString)::Vector{Vector{Int32}}
    txs = Vector{Vector{Int32}}()
    open(path, "r") do io
        for raw in eachline(io)
            line = strip(raw)
            isempty(line) && continue
            startswith(line, "#") && continue
            startswith(line, "%") && continue
            startswith(line, "@") && continue
            items = parse.(Int32, split(line))
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

function _collect_items(transactions::Vector{Vector{Int32}})::Vector{Int32}
    seen = Set{Int32}()
    for t in transactions
        for x in t
            push!(seen, x)
        end
    end
    items = collect(seen)
    sort!(items)
    return items
end

function _build_tidsets(transactions::Vector{Vector{Int32}}, items::Vector{Int32})
    n = length(transactions)
    tids = Dict{Int32, BitVector}()
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

# --- HÀM KIỂM TRA BAO ĐÓNG TẦNG THẤP: KHÔNG SINH ALLOCATIONS ---
@inline function _is_subset_bit(tidset::BitVector, item_bits::BitVector)::Bool
    c1 = tidset.chunks
    c2 = item_bits.chunks
    @inbounds for i in eachindex(c1)
        # Nếu (chunk_gốc AND chunk_item) khác chunk_gốc 
        # nghĩa là item_bits không chứa trọn vẹn tidset tại cụm bit này
        (c1[i] & c2[i]) == c1[i] || return false
    end
    return true
end

function _closure_from_tidset(
    tidset::BitVector,
    tids::Dict{Int32, BitVector},
    item_supports::Dict{Int32, Int},
    tx_sizes::Vector{Int32},
    transactions::Vector{Vector{Int32}}
)::Vector{Int32}
    c = Int32[]
    nt = count(tidset)
    nt == 0 && return c

    min_tx_idx = -1
    min_sz = typemax(Int32)

    c_chunks = tidset.chunks
    @inbounds for i in eachindex(c_chunks)
        chunk = c_chunks[i]
        while chunk != 0
            tz = trailing_zeros(chunk)
            idx = (i - 1) * 64 + tz + 1
            sz = tx_sizes[idx]
            if sz < min_sz
                min_sz = sz
                min_tx_idx = idx
            end
            chunk &= chunk - 1 # clear lowest set bit
        end
    end

    min_tx_idx == -1 && return c

    cand_items = transactions[min_tx_idx]
    @inbounds for item in cand_items
        item_supports[item] < nt && continue
        if _is_subset_bit(tidset, tids[item])
            push!(c, item)
        end
    end
    sort!(c)
    return c
end

function mine_closed_itemsets_optimized(transactions::Vector{Vector{Int32}}, minsup::Int)::Vector{MiningResult}
    n = length(transactions)
    n == 0 && return MiningResult[]

    items = _collect_items(transactions)
    tids = _build_tidsets(transactions, items)
    
    item_supports = Dict{Int32, Int}()
    for item in items
        item_supports[item] = _support(tids[item])
    end
    
    tx_sizes = Int32[length(t) for t in transactions]

    universe = trues(n)
    root = _closure_from_tidset(universe, tids, item_supports, tx_sizes, transactions)
    
    results = MiningResult[]

    function recurse(P::Vector{Int32}, T::BitVector, tail::Int32)
        supp = _support(T)
        supp < minsup && return

        if !isempty(P)
            push!(results, MiningResult(copy(P), supp))
        end

        for e in items
            e <= tail && continue
            e in P && continue

            Te = T .& tids[e]
            se = _support(Te)
            se < minsup && continue

            C = _closure_from_tidset(Te, tids, item_supports, tx_sizes, transactions)
            
            # Allocation-free PPC check (Two-pointers)
            # Find minimum item in C that is not in P
            i = 1
            j = 1
            len_C = length(C)
            len_P = length(P)
            min_new_item = -1
            
            while i <= len_C
                if j <= len_P
                    if C[i] == P[j]
                        i += 1
                        j += 1
                    elseif C[i] < P[j]
                        min_new_item = C[i]
                        break
                    else
                        j += 1
                    end
                else
                    min_new_item = C[i]
                    break
                end
            end
            
            min_new_item == e || continue

            recurse(C, Te, e)
        end
    end

    recurse(root, universe, Int32(0))
    sort!(results, by = r -> (length(r.itemset), r.itemset, r.support))
    return results
end

function results_to_dict(results::Vector{MiningResult})
    d = Dict{Tuple{Vararg{Int32}}, Int}()
    for r in results
        d[Tuple(r.itemset)] = r.support
    end
    return d
end

end # module