using HeatpumpMonitorAPI
using Test

@testset "with_timeout returns fast result" begin
    @test HeatpumpMonitorAPI.with_timeout(() -> 42, 1.0) == 42
end

@testset "with_timeout with Inf is a pass-through" begin
    @test HeatpumpMonitorAPI.with_timeout(() -> "ok", Inf) == "ok"
end

@testset "with_timeout throws TimeoutError when slow" begin
    err = nothing
    try
        HeatpumpMonitorAPI.with_timeout(() -> (sleep(0.5); :late), 0.05; phase = :read)
    catch e
        err = e
    end
    @test err isa HeatpumpMonitorAPI.TimeoutError
    @test err.phase === :read
end

@testset "with_timeout rethrows fn errors" begin
    @test_throws ErrorException HeatpumpMonitorAPI.with_timeout(() -> error("boom"), 1.0)
end
