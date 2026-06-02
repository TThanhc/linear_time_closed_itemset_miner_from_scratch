using Downloads

# Khởi tạo thư mục kết quả
if !ispath("results")
    mkpath("results")
end

function check_java()
    try
        # Bắt output của java -version (thường in ra ở stderr)
        out = Pipe()
        err = Pipe()
        process = run(pipeline(`java -version`, stdout=out, stderr=err), wait=false)
        wait(process)
        close(out.in)
        close(err.in)
        
        java_info = String(read(err))
        
        # Nếu đang dùng bản Java 8 (1.8) thì cảnh báo luôn
        if occursin("1.8.", java_info) || occursin("version 52.0", java_info)
            println("⚠️  CANH BAO: Ban dang dung Java 8. SPMF moi nhat yeu cau Java 21!")
            println("   Neu chay loi, vui long nang cap Java (JDK 21) nhe.\n")
        end
        return true
    catch
        return false
    end
end

function download_spmf()
    if !isfile("spmf.jar")
        println("=> Dang tai spmf.jar tu trang chu SPMF...")
        Downloads.download("https://www.philippe-fournier-viger.com/spmf/spmf.jar", "spmf.jar")
        println("=> Tai hoan tat spmf.jar!")
    end
end

function count_lines(filename)
    if !isfile(filename) return 0 end
    count = 0
    open(filename) do f
        for _ in eachline(f)
            count += 1
        end
    end
    return count
end

function format_spmf_minsup(minsup_raw)
    # SPMF nhận minsup ở dạng số thập phân (ví dụ 1% thì phải là 0.01) hoặc số tuyệt đối nguyên
    if endswith(minsup_raw, "%")
        val = parse(Float64, minsup_raw[1:end-1]) / 100.0
        return string(val)
    end
    return minsup_raw
end

function parse_args(args::Vector{String})
    if length(args) < 3
        println("""
        ❌ Loi: Danh sach tham so khong hop le!
        
        Cu phap chay:
        julia verify_spmf.jl <input_file> <minsup> <version>

        Trong do:
          <input_file>  : Duong dan file du lieu (vi du: data/retail.txt)
          <minsup>      : Nguong pho bien toi thieu (vi du: "1%", "0.01", hoac "882")
          <version>     : Phien ban ban muon test doi chieu ('a0', 'a1', hoac 'a2')
        """)
        exit(1)
    end

    input = args[1]
    minsup_raw = args[2]
    version = lowercase(args[3])

    version in ("a0", "a1", "a2") || error("Tham so <version> phai la 'a0', 'a1' hoac 'a2'")
    isfile(input) || error("Khong tim thay file du lieu: $input")

    return input, minsup_raw, version
end

function run_test(input_file, minsup_raw, version)
    dataset = splitext(basename(input_file))[1]
    spmf_out = "results/$(dataset)_spmf.txt"
    jl_out = "results/$(dataset)_mine_$(version).txt"
    
    minsup_spmf = format_spmf_minsup(minsup_raw)

    println("\n" * "="^60)
    println(" KIEM CHUNG: ", dataset, " | MINSUP: ", minsup_raw, " | PHIEN BAN: ", version)
    println("="^60)

    # 1. Chạy SPMF bằng Java
    println("\n[1] Dang chay thu vien SPMF (Java)...")
    spmf_cmd = `java -jar spmf.jar run LCM $input_file $spmf_out $minsup_spmf`
    
    spmf_time = @elapsed begin
        try
            # Chạy lệnh và bắt output để xử lý lỗi
            result = read(ignorestatus(spmf_cmd), String)
            if occursin("UnsupportedClassVersionError", result) || occursin("class file version 65.0", result)
                println("❌ LOI PHIEN BAN JAVA:")
                println("File spmf.jar nay yeu cau Java 21 (class file version 65.0).")
                println("Tuy nhien, may ban dang cai dat Java cu (thuong la Java 8 - version 52.0).")
                println("=> CACH FIX: Vui long go bo Java cu va tai Java 21 (JDK 21) tai:")
                println("   https://adoptium.net/ hoac https://www.oracle.com/java/technologies/downloads/")
                return
            end
        catch e
            println("❌ Loi khong xac dinh khi chay SPMF: ", e)
            return
        end
    end
    spmf_count = count_lines(spmf_out)
    println("=> SPMF hoan thanh trong $(round(spmf_time, digits=2)) giay. Tim thay: $spmf_count tap dong.")

    # 2. Chạy Julia LCM
    println("\n[2] Dang chay Julia LCM ($version)...")
    jl_cmd = `julia --project run_lcm.jl $input_file $minsup_raw mine $version`
    
    jl_time = @elapsed begin
        run(jl_cmd)
    end
    jl_count = count_lines(jl_out)
    # Lấy thông số từ kết quả output thực tế của file run_lcm
    println("=> Julia LCM hoan thanh trong $(round(jl_time, digits=2)) giay. Tim thay: $jl_count tap dong.")

    # 3. So sánh
    println("\n[3] KET QUA SO SANH:")
    if spmf_count == jl_count
        println("✅ KHOP NHAU HOAN TOAN! ($spmf_count == $jl_count)")
    else
        println("❌ KHAC BIET! (SPMF tim duoc: $spmf_count, Julia tim duoc: $jl_count)")
    end
end

function main()
    input, minsup_raw, version = parse_args(ARGS)

    println("=== CONG CU KIEM CHUNG VOI THU VIEN SPMF GOC ===")
    
    if !check_java()
        println("❌ LOI: Khong tim thay 'java' tren he thong!")
        println("Ban can phai cai dat Java (JRE hoac JDK) de chay duoc spmf.jar.")
        println("Vui long tai Java tai: https://www.java.com/en/download/")
        return
    end

    download_spmf()
    run_test(input, minsup_raw, version)
    
    println("\n=== HOAN THANH KIEM CHUNG ===")
end

main()
