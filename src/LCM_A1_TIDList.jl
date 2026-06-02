module LCM_A1_TIDList

export read_spmf_transactions,
       write_spmf_closed_itemsets,
       mine_closed_itemsets_baseline,
       parse_minsup_to_absolute,
       results_to_dict

# --- Structs ---
struct MiningResult
    itemset::Vector{Int32}
    support::Int
end

# --- I/O Functions ---
"""
    read_spmf_transactions(path::AbstractString) -> Vector{Vector{Int32}}
Đọc và chuẩn hóa dữ liệu giao dịch từ file định dạng SPMF.
"""
function read_spmf_transactions(path::AbstractString)::Vector{Vector{Int32}}
    txs = Vector{Vector{Int32}}()
    
    open(path, "r") do io
        for raw in eachline(io)
            line = strip(raw)
            isempty(line) && continue
            
            # Bỏ qua các dòng comment/metadata phổ biến
            (startswith(line, "#") || startswith(line, "%") || startswith(line, "@")) && continue
            
            items = parse.(Int32, split(line))
            sort!(items)
            unique!(items)
            push!(txs, items)
        end
    end
    
    return txs
end

"""
Ghi kết quả khai phá tập phổ biến đóng ra file theo định dạng SPMF.
"""
function write_spmf_closed_itemsets(path::AbstractString, results::Vector{MiningResult})
    open(path, "w") do io
        for r in results
            isempty(r.itemset) && continue
            println(io, join(r.itemset, " "), " #SUP: ", r.support)
        end
    end
end

# --- Helpers ---
"""
    parse_minsup_to_absolute(minsup_raw::AbstractString, ntransactions::Int) -> Int
Chuyển đổi chuỗi minsup (dạng phần trăm hoặc số thực) sang dạng số lượng giao dịch tuyệt đối.
"""
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

function _collect_items(transactions::Vector{Vector{T}})::Vector{T} where {T<:Integer}
    seen = Set{T}()
    @inbounds for t in transactions
        for x in t
            push!(seen, x)
        end
    end
    
    items = collect(seen)
    sort!(items)
    return items
end

function _contains_all(tids::Vector{Int32}, item_tids::Vector{Int32})::Bool
    i, j = 1, 1
    nt, ni = length(tids), length(item_tids)

    @inbounds while i <= nt && j <= ni
        tv = tids[i]
        iv = item_tids[j]

        if tv == iv
            i += 1
            j += 1
        elseif tv > iv
            j += 1
        else
            return false
        end
    end

    return i > nt
end

function _closure_full(
    tids::Vector{Int32}, 
    items::Vector{Int32}, 
    item_tidlists::Dict{Int32, Vector{Int32}}
)::Vector{Int32}
    C = Int32[]
    nt = length(tids)

    @inbounds for item in items
        Ti = item_tidlists[item]
        length(Ti) < nt && continue
        _contains_all(tids, Ti) && push!(C, item)
    end

    return C
end

# --- Mining Algorithms ---
"""
Thuật toán LCM tối ưu hóa khai phá tập phổ biến đóng bằng mảng chỉ mục giao dịch (TID-lists).
"""
function mine_closed_itemsets_baseline(
    transactions::Vector{Vector{T}}, 
    minsup::Int
)::Vector{MiningResult} where {T<:Integer}
    
    # Ép kiểu dữ liệu đầu vào sang Int32 một cách an toàn
    txs32 = Vector{Vector{Int32}}(undef, length(transactions))
    @inbounds for i in eachindex(transactions)
        txs32[i] = Int32.(transactions[i])
    end
    transactions = txs32

    n = length(transactions)
    n == 0 && return MiningResult[]

    items = _collect_items(transactions)

    # Khởi tạo TID-lists
    tids = Dict{Int32, Vector{Int32}}()
    for item in items
        tids[item] = Int32[]
    end

    @inbounds for (tid, t) in enumerate(transactions)
        tid32 = Int32(tid)
        for item in t
            push!(tids[item], tid32)
        end
    end

    # Hàm inline hỗ trợ giao các danh sách TID đã sắp xếp
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

    results = MiningResult[]
    seen = Set{BitSet}()

    rootT = collect(Int32(1):Int32(n))
    rootClosure = _closure_full(rootT, items, tids)

    # Hàm DFS đệ quy tìm kiếm tập đóng
    function dfs(P::Vector{Int32}, T::Vector{Int32}, tail::Int32)
        supp = length(T)
        supp < minsup && return

        key = BitSet(P)
        key in seen && return
        push!(seen, key)

        push!(results, MiningResult(copy(P), supp))

        @inbounds for e in items
            e <= tail && continue
            e in P && continue

            Te = intersect_sorted(T, tids[e])
            length(Te) < minsup && continue

            C = _closure_full(Te, items, tids)
            added_min = typemax(Int32)

            for x in C
                if !(x in P)
                    added_min = min(added_min, x)
                end
            end

            added_min == e || continue
            dfs(C, Te, e)
        end
    end

    dfs(rootClosure, rootT, Int32(0))
    sort!(results, by = r -> (length(r.itemset), r.itemset, r.support))

    return results
end

# --- Utility Functions ---
"""
    results_to_dict(results::Vector{MiningResult}) -> Dict
Chuyển đổi danh sách `MiningResult` thành một `Dict` phục vụ so sánh hoặc test.
"""
function results_to_dict(results::Vector{MiningResult})
    d = Dict{Tuple{Vararg{Int32}}, Int}()
    for r in results
        d[Tuple(r.itemset)] = r.support
    end
    return d
end

end # module