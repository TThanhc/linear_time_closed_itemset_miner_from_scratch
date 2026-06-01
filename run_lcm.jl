#!/usr/bin/env julia

include(joinpath(@__DIR__, "src", "LCM_A1_TIDList.jl"))
include(joinpath(@__DIR__, "src", "LCM_A2_BitVector.jl"))
include(joinpath(@__DIR__, "src", "AssociationRules.jl"))

using .LCM_A1_TIDList
using .LCM_A2_BitVector
using .AssociationRules

function parse_args(args::Vector{String})
    if length(args) < 4
        error("""
        Danh sach tham so khong hop le!
        
        Cu phap chay chuong trinh moi (Tu dong luu vao thu muc results/):
        julia --project run_lcm.jl <input_file> <minsup> <task> <version> [minconf]

        Trong do:
          <input_file>  : Duong dan file du lieu (vi du: data/mushrooms.txt)
          <minsup>      : Nguong pho bien toi thieu (vi du: 10% hoac 0.1 hoac 842)
          <task>        : Tieu chi chay ('mine' de tim tap dong, 'rules' de sinh luat)
          <version>     : Phien ban thuat toan ('a1' cho TID-list, 'a2' cho BitVector)
          [minconf]     : (Tuy chon) Nguong tin cay cho luat, mac dinh la 0.5 (vi du: 0.6)
        """)
    end

    input = args[1]
    minsup_raw = args[2]
    task = lowercase(args[3])
    version = lowercase(args[4])

    task in ("mine", "rules") || error("Tham so <task> phai la 'mine' hoac 'rules'")
    version in ("a1", "a2") || error("Tham so <version> phai la 'a1' hoac 'a2'")
    
    minconf = task == "rules" ? (length(args) >= 5 ? parse(Float64, args[5]) : 0.5) : 0.0

    # --- LOGIC TỰ ĐỘNG SINH TÊN FILE OUTPUT ---
    # Lấy tên file gốc loại bỏ đường dẫn và đuôi định dạng (ví dụ: "data/mushrooms.txt" -> "mushrooms")
    base_name = splitext(basename(input))[1]
    
    # Tạo tên file output có cấu trúc rõ ràng: results/tênfile_tácvụ_phiênbản.txt
    output_dir = joinpath(@__DIR__, "results")
    output = joinpath(output_dir, "$(base_name)_$(task)_$(version).txt")

    return input, minsup_raw, task, version, output, minconf
end

function main()
    input, minsup_raw, task, version, output, minconf = parse_args(ARGS)
    
    println("--- KHOI DONG HE THONG ---")
    println("File du lieu: ", input)
    println("Tac vu       : ", task)
    println("Phien ban    : ", version == "a1" ? "A1 (TID-list)" : "A2 (BitVector Toi Uu Chunk)")

    # 1. Doc du lieu giao dich
    if version == "a1"
        txs = LCM_A1_TIDList.read_spmf_transactions(input)
        abs_minsup = LCM_A1_TIDList.parse_minsup_to_absolute(minsup_raw, length(txs))
        
        println("Transactions : ", length(txs))
        println("MinSup tuyet doi: ", abs_minsup)
        println("-> Dang chay thuat toan khai pha...")
        
        @time results = LCM_A1_TIDList.mine_closed_itemsets_baseline(txs, abs_minsup)
    else
        txs = LCM_A2_BitVector.read_spmf_transactions(input)
        abs_minsup = LCM_A2_BitVector.parse_minsup_to_absolute(minsup_raw, length(txs))
        
        println("Transactions : ", length(txs))
        println("MinSup tuyet doi: ", abs_minsup)
        println("-> Dang chay thuat toan khai pha...")
        
        @time results = LCM_A2_BitVector.mine_closed_itemsets_optimized(txs, abs_minsup)
    end

    println("Closed frequent itemsets tim thay: ", length(results))

    # Tự động tạo thư mục results/ nếu chưa có trên máy tính
    if !ispath(dirname(output))
        mkpath(dirname(output))
    end
    
    # 2. Xu ly dau ra dua tren Tac vu (Task)
    if task == "mine"
        if version == "a1"
            LCM_A1_TIDList.write_spmf_closed_itemsets(output, results)
        else
            LCM_A2_BitVector.write_spmf_closed_itemsets(output, results)
        end
        println("Ket qua tap dong da duoc luu tai: ", output)
    else
        println("-> Dang tien hanh sinh luat ket hop...")
        @time rules = generate_association_rules(results, txs, minconf)
        println("Association rules thu thap (da gioi han budget): ", length(rules))
        
        print_top_rules(rules, 10)
        write_rules_to_file(output, rules)
        println("Ket qua luat da duoc luu tai: ", output)
    end
    println("--- HOAN THANH ---")
end

main()