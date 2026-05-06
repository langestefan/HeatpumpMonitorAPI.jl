using HeatpumpMonitorAPI
using Test

const _NO_SLEEP = (_::Real) -> nothing
const _ONE_JITTER = () -> 1.0

@testset "with_retry returns first success" begin
    calls = Ref(0)
    result = HeatpumpMonitorAPI.with_retry(; sleep_fn = _NO_SLEEP) do
        calls[] += 1
        :ok
    end
    @test result === :ok
    @test calls[] == 1
end

@testset "with_retry retries on retryable status then succeeds" begin
    attempts = Ref(0)
    sleeps = Float64[]
    sink(d) = push!(sleeps, d)
    result = HeatpumpMonitorAPI.with_retry(;
        policy = HeatpumpMonitorAPI.RetryPolicy(; max_attempts = 4, base_delay = 1.0),
        sleep_fn = sink,
        jitter = _ONE_JITTER,
    ) do
        attempts[] += 1
        attempts[] < 3 && throw(HeatpumpMonitorAPI.ServerError(503, "down"))
        :recovered
    end
    @test result === :recovered
    @test attempts[] == 3
    @test sleeps == [1.0, 2.0]
end

@testset "with_retry exhausts attempts then rethrows" begin
    attempts = Ref(0)
    @test_throws HeatpumpMonitorAPI.ServerError HeatpumpMonitorAPI.with_retry(;
        policy = HeatpumpMonitorAPI.RetryPolicy(; max_attempts = 3, base_delay = 0.01),
        sleep_fn = _NO_SLEEP,
        jitter = _ONE_JITTER,
    ) do
        attempts[] += 1
        throw(HeatpumpMonitorAPI.ServerError(503, "down"))
    end
    @test attempts[] == 3
end

@testset "with_retry skips non-retryable status" begin
    attempts = Ref(0)
    @test_throws HeatpumpMonitorAPI.ClientError HeatpumpMonitorAPI.with_retry(; sleep_fn = _NO_SLEEP) do
        attempts[] += 1
        throw(HeatpumpMonitorAPI.ClientError(404, "missing"))
    end
    @test attempts[] == 1
end

@testset "RateLimitError honors Retry-After when longer than backoff" begin
    attempts = Ref(0)
    sleeps = Float64[]
    sink(d) = push!(sleeps, d)
    HeatpumpMonitorAPI.with_retry(;
        policy = HeatpumpMonitorAPI.RetryPolicy(; max_attempts = 3, base_delay = 0.1),
        sleep_fn = sink,
        jitter = _ONE_JITTER,
    ) do
        attempts[] += 1
        attempts[] < 3 && throw(HeatpumpMonitorAPI.RateLimitError(; retry_after = 5.0))
        :ok
    end
    @test all(>=(5.0), sleeps)
end

@testset "is_retryable defaults" begin
    p = HeatpumpMonitorAPI.RetryPolicy()
    @test HeatpumpMonitorAPI.is_retryable(p, HeatpumpMonitorAPI.NetworkError(ErrorException("x")))
    @test HeatpumpMonitorAPI.is_retryable(p, HeatpumpMonitorAPI.ServerError(503, ""))
    @test !HeatpumpMonitorAPI.is_retryable(p, HeatpumpMonitorAPI.ClientError(404, ""))
    @test HeatpumpMonitorAPI.is_retryable(p, HeatpumpMonitorAPI.RateLimitError())
    @test HeatpumpMonitorAPI.is_retryable(p, HeatpumpMonitorAPI.TimeoutError(:read))
    @test !HeatpumpMonitorAPI.is_retryable(p, ErrorException("not an APIError"))
end

@testset "non-APIError is not retried" begin
    attempts = Ref(0)
    @test_throws ErrorException HeatpumpMonitorAPI.with_retry(; sleep_fn = _NO_SLEEP) do
        attempts[] += 1
        error("boom")
    end
    @test attempts[] == 1
end
