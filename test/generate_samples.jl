#!/usr/bin/env julia

using Random

function generate_dataset(path::String; ntrans::Int=20, nitems::Int=12, avglen::Int=4, seed::Int=42)
    rng = MersenneTwister(seed)
    open(path, "w") do io
        for _ in 1:ntrans
            len = clamp(round(Int, randn(rng) + avglen), 1, nitems)
            items = sort!(randperm(rng, nitems)[1:len])
            println(io, join(items, " "))
        end
    end
end

mkpath(joinpath(@__DIR__, "..", "toy"))
generate_dataset(joinpath(@__DIR__, "..", "toy", "toy_random_small.txt"), ntrans=30, nitems=15, avglen=5, seed=14004)
generate_dataset(joinpath(@__DIR__, "..", "toy", "toy_random_dense.txt"), ntrans=40, nitems=20, avglen=10, seed=14005)

println("Generated sample datasets in toy/")
