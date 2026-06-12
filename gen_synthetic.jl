using Random
using Printf

const SEED = 42
const NTRANS = 8124
const NITEMS = 119
const LENGTHS = [50, 60, 70, 80]

Random.seed!(SEED)

println("=== Sinh CSDL tổng hợp (Bernoulli, p = L/119) ===")
for L in LENGTHS
    p = L / NITEMS
    fname = joinpath(@__DIR__, "data", "synthetic_l$(L).txt")
    total_len = 0
    nlines = 0
    open(fname, "w") do io
        for _ in 1:NTRANS
            items = Int32[]
            for i in 1:NITEMS
                if rand() < p
                    push!(items, Int32(i))
                end
            end
            if isempty(items)
                push!(items, Int32(rand(1:NITEMS)))
            end
            sort!(items)
            unique!(items)
            println(io, join(items, " "))
            total_len += length(items)
            nlines += 1
        end
    end
    avg = total_len / nlines
    @printf("L=%3d  p=%.4f  ->  %s  (avg_len=%.2f, m=%d, n=%d)\n",
            L, p, fname, avg, nlines, NITEMS)
end
println("=== Hoàn tất ===")
