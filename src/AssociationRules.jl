module AssociationRules

export AssociationRule,
       generate_association_rules,
       print_top_rules,
       write_rules_to_file

# --- Structs ---

struct AssociationRule
    antecedent::Vector{Int32}
    consequent::Vector{Int32}
    support::Float64
    confidence::Float64
    lift::Float64
end

# --- Rule Generation (Thuật toán Lattice-based Giới Hạn Budget) ---

function generate_association_rules(
    closed_results,
    transactions::Vector{Vector{Int32}},
    minconf::Float64
)::Vector{AssociationRule}

    ntransactions = length(transactions)
    rules = AssociationRule[]
    
    # Sắp xếp các tập đóng theo độ dài tăng dần
    sorted_results = sort(closed_results, by = r -> length(r.itemset))
    num_closed = length(sorted_results)

    # Đặt ngưỡng giới hạn tối đa số luật lưu trong RAM để tránh bị đơ máy khi dữ liệu quá dày
    MAX_RULES_BUDGET = 5000 

    for i in 1:num_closed
        r1 = sorted_results[i]
        itemset1 = r1.itemset
        sup1 = r1.support
        n1 = length(itemset1)
        n1 == 0 && continue

        for j in (i+1):num_closed
            r2 = sorted_results[j]
            itemset2 = r2.itemset
            sup2 = r2.support
            n2 = length(itemset2)

            # Cắt tỉa sớm theo độ dài
            n1 >= n2 && continue

            # Kiểm tra nhanh Confidence
            confidence = sup2 / sup1
            confidence < minconf && continue

            # Kiểm tra tập con thực tế
            if issubset(itemset1, itemset2)
                # Vế phải Y = R2 \ R1
                consequent = filter(x -> !(x in itemset1), itemset2)
                
                # Tính toán các chỉ số
                support = sup2 / ntransactions
                lift = confidence / (sup2 / ntransactions)

                push!(rules, AssociationRule(copy(itemset1), consequent, support, confidence, lift))
                
                # Nếu đã thu thập đủ số luật chất lượng, chủ động dừng sớm để cứu CPU
                if length(rules) >= MAX_RULES_BUDGET
                    @goto budget_reached
                end
            end
        end
    end

    @label budget_reached

    # Sắp xếp các luật theo tiêu chí ưu tiên giảm dần
    sort!(rules, by = r -> (-r.lift, -r.confidence, -r.support, length(r.antecedent)))

    return rules
end

# --- I/O Functions ---

function print_top_rules(rules::Vector{AssociationRule}, k::Int = 10)
    println("\n" * "="^48)
    println("TOP ASSOCIATION RULES")
    println("="^48)

    limit = min(k, length(rules))
    if limit == 0
        println("No rules found.")
        return
    end

    @inbounds for i in 1:limit
        r = rules[i]
        println(
            i, ". ", collect(Int, r.antecedent), " => ", collect(Int, r.consequent),
            " | support=", round(r.support; digits=4),
            " confidence=", round(r.confidence; digits=4),
            " lift=", round(r.lift; digits=4)
        )
    end
    println("="^48)
end

function write_rules_to_file(
    path::AbstractString, 
    rules::Vector{AssociationRule}, 
    k::Int = length(rules)
)
    open(path, "w") do io
        println(io, "TOP ASSOCIATION RULES\n")

        limit = min(k, length(rules))
        if limit == 0
            println(io, "No rules found.")
            return
        end

        @inbounds for i in 1:limit
            r = rules[i]
            println(
                io, i, ". ", collect(Int, r.antecedent), " => ", collect(Int, r.consequent),
                " | support=", round(r.support; digits=4),
                ", confidence=", round(r.confidence; digits=4),
                ", lift=", round(r.lift; digits=4)
            )
        end
    end
end

end # module