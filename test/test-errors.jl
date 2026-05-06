using HeatpumpMonitorAPI
using Test

@testset "Error type hierarchy" begin
    @test HeatpumpMonitorAPI.NetworkError(ErrorException("dns")) isa HeatpumpMonitorAPI.APIError
    @test HeatpumpMonitorAPI.ClientError(404, "not found") isa HeatpumpMonitorAPI.APIError
    @test HeatpumpMonitorAPI.ServerError(500, "boom") isa HeatpumpMonitorAPI.APIError
    @test HeatpumpMonitorAPI.AuthError(401, "nope") isa HeatpumpMonitorAPI.APIError
    @test HeatpumpMonitorAPI.RateLimitError(; retry_after = 5.0) isa HeatpumpMonitorAPI.APIError
    @test HeatpumpMonitorAPI.TimeoutError(:read) isa HeatpumpMonitorAPI.APIError
end

@testset "parse_retry_after" begin
    @test HeatpumpMonitorAPI.parse_retry_after("5") == 5.0
    @test HeatpumpMonitorAPI.parse_retry_after(" 12 ") == 12.0
    @test HeatpumpMonitorAPI.parse_retry_after("Wed, 21 Oct 2015 07:28:00 GMT") === nothing
    @test HeatpumpMonitorAPI.parse_retry_after("") === nothing
    @test HeatpumpMonitorAPI.parse_retry_after(nothing) === nothing
end

@testset "check_response 2xx returns nothing" begin
    for s in (200, 201, 204, 299)
        @test HeatpumpMonitorAPI.check_response(s, "") === nothing
    end
end

@testset "check_response classifies by status" begin
    @test_throws HeatpumpMonitorAPI.AuthError HeatpumpMonitorAPI.check_response(401, "")
    @test_throws HeatpumpMonitorAPI.AuthError HeatpumpMonitorAPI.check_response(403, "")
    @test_throws HeatpumpMonitorAPI.ClientError HeatpumpMonitorAPI.check_response(404, "missing")
    @test_throws HeatpumpMonitorAPI.ServerError HeatpumpMonitorAPI.check_response(503, "")
    @test_throws HeatpumpMonitorAPI.ClientError HeatpumpMonitorAPI.check_response(600, "weird")
end

@testset "check_response 429 surfaces RateLimitError" begin
    headers = Dict("Retry-After" => "7")
    err = try
        HeatpumpMonitorAPI.check_response(429, "", headers)
        nothing
    catch e
        e
    end
    @test err isa HeatpumpMonitorAPI.RateLimitError
    @test err.retry_after == 7.0
end
