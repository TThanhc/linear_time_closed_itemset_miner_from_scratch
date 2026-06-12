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

function merge_sorted(a::Vector{Int32}, b::Vector{Int32})::Vector{Int32}
    i, j = 1, 1
    na, nb = length(a), length(b)
    out = Int32[]
    sizehint!(out, na + nb)
    @inbounds while i <= na && j <= nb
        av, bv = a[i], b[j]
        if av == bv
            push!(out, av)
            i += 1
            j += 1
        elseif av < bv
            push!(out, av)
            i += 1
        else
            push!(out, bv)
            j += 1
        end
    end
    @inbounds while i <= na
        push!(out, a[i])
        i += 1
    end
    @inbounds while j <= nb
        push!(out, b[j])
        j += 1
    end
    return out
end

function intersect_items_indices(T_P::Vector{Tuple{Vector{Int32}, Vector{Int32}, Int}}, indices::Vector{Int})::Vector{Int32}
    isempty(indices) && return Int32[]
    c = copy(T_P[indices[1]][1])
    for i in 2:length(indices)
        isempty(c) && break
        c = intersect_sorted(c, T_P[indices[i]][1])
    end
    return c
end

function intersect_in_idx_indices(T_P::Vector{Tuple{Vector{Int32}, Vector{Int32}, Int}}, indices::Vector{Int})::Vector{Int32}
    isempty(indices) && return Int32[]
    c = copy(T_P[indices[1]][2])
    for i in 2:length(indices)
        isempty(c) && break
        c = intersect_sorted(c, T_P[indices[i]][2])
    end
    return c
end

function merge_transactions(T_reduced::Vector{Tuple{Vector{Int32}, Vector{Int32}, Int}})::Vector{Tuple{Vector{Int32}, Vector{Int32}, Int}}
    isempty(T_reduced) && return T_reduced
    
    # Sort lexicographically by items, then by in_idx (though in_idx is intersected later)
    sort!(T_reduced, by = x -> (x[1], x[2]))
    
    merged = Vector{Tuple{Vector{Int32}, Vector{Int32}, Int}}()
    sizehint!(merged, length(T_reduced))
    
    curr_items, curr_in_idx, curr_w = T_reduced[1]
    
    for i in 2:length(T_reduced)
        items, in_idx, w = T_reduced[i]
        if items == curr_items
            # Intersect the interior intersections of merged transactions
            curr_in_idx = intersect_sorted(curr_in_idx, in_idx)
            curr_w += w
        else
            push!(merged, (curr_items, curr_in_idx, curr_w))
            curr_items, curr_in_idx, curr_w = items, in_idx, w
        end
    end
    push!(merged, (curr_items, curr_in_idx, curr_w))
    return merged
end

function reduce_database(T::Vector{Tuple{Vector{Int32}, Vector{Int32}, Int}}, P::Vector{Int32}, tail::Int32, minsup::Int)::Vector{Tuple{Vector{Int32}, Vector{Int32}, Int}}
    projected = Vector{Tuple{Vector{Int32}, Vector{Int32}, Int}}()
    sizehint!(projected, length(T))
    
    for (items, in_idx, w) in T
        remaining_items = Int32[]
        removed_items = Int32[]
        
        for x in items
            if !_insorted(x, P)
                if x > tail
                    push!(remaining_items, x)
                elseif x < tail
                    push!(removed_items, x)
                end
            end
        end
        
        # Filter in_idx: only keep items not in P (since P might have expanded)
        filtered_in_idx = Int32[]
        for x in in_idx
            if !_insorted(x, P)
                push!(filtered_in_idx, x)
            end
        end
        
        new_in_idx = merge_sorted(filtered_in_idx, removed_items)
        push!(projected, (remaining_items, new_in_idx, w))
    end
    
    # 2. Count support of all remaining items (in items AND in_idx)
    counts = Dict{Int32, Int}()
    for (items, in_idx, w) in projected
        for x in items
            counts[x] = get(counts, x, 0) + w
        end
        for x in in_idx
            counts[x] = get(counts, x, 0) + w
        end
    end
    
    # 3. Filter out infrequent items from both items and in_idx
    final_txs = Vector{Tuple{Vector{Int32}, Vector{Int32}, Int}}()
    sizehint!(final_txs, length(projected))
    for (items, in_idx, w) in projected
        new_items = filter(x -> get(counts, x, 0) >= minsup, items)
        new_in_idx = filter(x -> get(counts, x, 0) >= minsup, in_idx)
        push!(final_txs, (new_items, new_in_idx, w))
    end
    
    # 4. Merge identical transactions
    return merge_transactions(final_txs)
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
    function recurse(P::Vector{Int32}, T_P::Vector{Tuple{Vector{Int32}, Vector{Int32}, Int}}, tail::Int32)
        supp = sum(x[3] for x in T_P)
        supp < minsup && return
        
        # Ánh xạ ngược lại ID thật để lưu kết quả
        orig_P = Int32[freq_items[i] for i in P]
        if !isempty(orig_P)
            push!(results, MiningResult(orig_P, supp))
        end
        
        # Local buckets cho Occurrence Deliver ở tầng đệ quy này
        buckets = Dict{Int32, Vector{Int}}()
        
        @inbounds for (idx, (items, in_idx, w)) in enumerate(T_P)
            for e in items
                push!(get!(buckets, e, Int[]), idx)
            end
        end
        
        # Xử lý các item mở rộng (e) vừa tìm được
        sorted_keys = sort(collect(keys(buckets)))
        
        for e in sorted_keys
            indices = buckets[e]
            supp_e = sum(T_P[idx][3] for idx in indices)
            
            if supp_e >= minsup
                # Closure Operation: Giao tất cả các giao dịch chứa (P U {e})
                intersect_its = intersect_items_indices(T_P, indices)
                intersect_in = intersect_in_idx_indices(T_P, indices)
                
                # PPCE Check: P'(e - 1) == P(e - 1)
                is_ppce = isempty(intersect_in)
                if is_ppce
                    for x in intersect_its
                        if x < e
                            is_ppce = false
                            break
                        end
                    end
                end
                
                if is_ppce
                    # P_new = P U {e} U {y > e | y in intersect_its}
                    P_new = copy(P)
                    push!(P_new, e)
                    for y in intersect_its
                        if y > e
                            push!(P_new, y)
                        end
                    end
                    sort!(P_new)
                    
                    # Chiếu và rút gọn CSDL cho tầng đệ quy tiếp theo
                    proj_T = [ T_P[idx] for idx in indices ]
                    T_new = reduce_database(proj_T, P_new, e, minsup)
                    
                    recurse(P_new, T_new, e)
                end
            end
        end
    end
    
    if n > 0
        # Khởi tạo CSDL dạng Tuple (items, in_idx, weight)
        T_root = [ (t, Int32[], 1) for t in root_txs ]
        T_root_reduced = reduce_database(T_root, root_closure, Int32(0), minsup)
        recurse(root_closure, T_root_reduced, Int32(0))
    end
    
    sort!(results, by = r -> (length(r.itemset), r.itemset, r.support))
    return results
end

end # module
