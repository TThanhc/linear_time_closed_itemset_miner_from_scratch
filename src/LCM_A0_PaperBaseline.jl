module LCM_A0_PaperBaseline

export read_spmf_transactions,
       write_spmf_closed_itemsets,
       mine_closed_itemsets_paper,
       parse_minsup_to_absolute,
       results_to_dict

struct MiningResult
    itemset::Vector{Int32}
    support::Int
end

# --- I/O Functions ---
function read_spmf_transactions(path::AbstractString)::Vector{Vector{Int32}}
    txs = Vector{Vector{Int32}}()
    open(path, "r") do io
        for raw in eachline(io)
            line = strip(raw)
            isempty(line) && continue
            (startswith(line, "#") || startswith(line, "%") || startswith(line, "@")) && continue
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

function results_to_dict(results::Vector{MiningResult})
    d = Dict{Tuple{Vararg{Int32}}, Int}()
    for r in results
        d[Tuple(r.itemset)] = r.support
    end
    return d
end

# --- LCM Algorithm (Paper Baseline) ---

function intersect_sorted(a::Vector{Int32}, b::Vector{Int32})::Vector{Int32}
    i, j = 1, 1
    na, nb = length(a), length(b)
    out = Int32[]
    sizehint!(out, min(na, nb))

    @inbounds while i <= na && j <= nb
        av, bv = a[i], b[j]
        if av == bv
            push!(out, av)
            i += 1
            j += 1
        elseif av < bv
            i += 1
        else
            j += 1
        end
    end
    return out
end

function intersect_all(txs::Vector{Vector{Int32}})::Vector{Int32}
    isempty(txs) && return Int32[]
    c = copy(txs[1])
    for i in 2:length(txs)
        isempty(c) && break
        c = intersect_sorted(c, txs[i])
    end
    return c
end

@inline function _insorted(val::Int32, arr::Vector{Int32})::Bool
    @inbounds for x in arr
        if x == val
            return true
        elseif x > val
            return false
        end
    end
    return false
end

"""
Thuật toán LCM chuẩn theo Paper LCM.
Sử dụng PPCE (Prefix Preserving Closure Extension) và Occurrence Deliver.
KHÔNG sử dụng bộ nhớ để lưu trữ các itemset đã tìm thấy (no seen set).
"""
function mine_closed_itemsets_paper(transactions::Vector{Vector{T}}, minsup::Int)::Vector{MiningResult} where {T<:Integer}
    # 1. Đếm tần suất toàn cục (Global frequency counting)
    item_counts = Dict{Int32, Int}()
    for t in transactions
        for x in t
            x32 = Int32(x)
            item_counts[x32] = get(item_counts, x32, 0) + 1
        end
    end
    
    # 2. Lọc các item phổ biến và tạo mapping (Item Renaming)
    freq_items = Int32[]
    for (k, v) in item_counts
        if v >= minsup
            push!(freq_items, k)
        end
    end
    sort!(freq_items)
    
    item_to_dense = Dict{Int32, Int32}()
    for (idx, item) in enumerate(freq_items)
        item_to_dense[item] = Int32(idx)
    end
    
    num_freq_items = length(freq_items)
    n = length(transactions)
    n == 0 && return MiningResult[]
    
    # 3. Tạo database gốc đã lọc (chỉ chứa các item phổ biến, chuyển sang dense ID)
    root_txs = Vector{Vector{Int32}}()
    sizehint!(root_txs, n)
    
    for t in transactions
        new_t = Int32[]
        for x in t
            x32 = Int32(x)
            if haskey(item_to_dense, x32)
                push!(new_t, item_to_dense[x32])
            end
        end
        if !isempty(new_t)
            sort!(new_t)
            push!(root_txs, new_t)
        end
    end
    
    # Tập đóng gốc là giao của tất cả các giao dịch
    root_closure = Int32[]
    if length(root_txs) == n && n > 0
        root_closure = intersect_all(root_txs)
    end
    
    results = MiningResult[]
    
    # Hàm đệ quy duyệt cây PPCE
    function recurse(P::Vector{Int32}, T_P::Vector{Vector{Int32}}, tail::Int32)
        supp = length(T_P)
        supp < minsup && return
        
        # Ánh xạ ngược lại ID thật để lưu kết quả
        orig_P = Int32[freq_items[i] for i in P]
        if !isempty(orig_P)
            push!(results, MiningResult(orig_P, supp))
        end
        
        # Local buckets cho Occurrence Deliver ở tầng đệ quy này
        buckets = Dict{Int32, Vector{Vector{Int32}}}()
        
        @inbounds for t in T_P
            for e in t
                if e > tail && !_insorted(e, P)
                    if !haskey(buckets, e)
                        buckets[e] = Vector{Vector{Int32}}()
                    end
                    push!(buckets[e], t)
                end
            end
        end
        
        # Xử lý các item mở rộng (e) vừa tìm được
        for (e, T_Pe) in buckets
            if length(T_Pe) >= minsup
                # Closure Operation: Giao tất cả các giao dịch chứa (P U {e})
                C = intersect_all(T_Pe)
                
                # PPCE Check: P'(e - 1) == P(e - 1)
                is_ppce = true
                for x in C
                    if x < e && !_insorted(x, P)
                        is_ppce = false
                        break
                    end
                end
                
                if is_ppce
                    recurse(C, T_Pe, e)
                end
            end
        end
    end
    
    if n > 0
        recurse(root_closure, root_txs, Int32(0))
    end
    
    sort!(results, by = r -> (length(r.itemset), r.itemset, r.support))
    return results
end

end # module