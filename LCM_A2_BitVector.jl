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
    items::Vector{Int32},
    tids::Dict{Int32, BitVector}
)::Vector{Int32}
    c = Int32[]
    nt = count(tidset)
    nt == 0 && return c

    @inbounds for item in items
        # Cắt tỉa sớm (Early Pruning) bằng phần mềm giống Bản A1
        count(tids[item]) < nt && continue
        
        # Kiểm tra đóng bằng hàm duyệt chunk không tốn RAM
        if _is_subset_bit(tidset, tids[item])
            push!(c, item)
        end
    end
    return c
end

function mine_closed_itemsets_optimized(transactions::Vector{Vector{Int32}}, minsup::Int)::Vector{MiningResult}
    n = length(transactions)
    n == 0 && return MiningResult[]

    items = _collect_items(transactions)
    tids = _build_tidsets(transactions, items)
    universe = trues(n)

    root = _closure_from_tidset(universe, items, tids)
    results = MiningResult[]
    seen = Set{Tuple{Vararg{Int32}}}()

    function recurse(P::Vector{Int32}, T::BitVector, tail::Int32)
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

            # Phép AND này tạo nhánh mới, bắt buộc phải sinh mảng tạm Te
            Te = T .& tids[e]
            se = _support(Te)
            se < minsup && continue

            C = _closure_from_tidset(Te, items, tids)
            Pset = Set(P)
            new_items = [x for x in C if !(x in Pset)]
            isempty(new_items) && continue

            # Điều kiện mở rộng PPC
            minimum(new_items) == e || continue

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