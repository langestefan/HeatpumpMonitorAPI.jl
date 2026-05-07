using HeatpumpMonitorAPI
using Dates: DateTime, unix2datetime
using Test

@testset "as_number" begin
    @test as_number(nothing) === nothing
    @test as_number(false) === nothing
    @test as_number(true) === nothing
    @test as_number(0) === 0.0
    @test as_number(42) === 42.0
    @test as_number(3.14) === 3.14
    @test as_number("3.14") === 3.14
    @test as_number("  42  ") === 42.0
    @test as_number("-1.5e2") === -150.0
    @test as_number("") === nothing
    @test as_number("   ") === nothing
    @test as_number("not a number") === nothing

    # AnyOfAPIModel wrapper: codegen produces these for `type: [..., ...]` fields.
    api_mod = HeatpumpMonitorAPI.HeatpumpMonitorAPIAPI
    if isdefined(api_mod, :SystemStatsCombinedDataLength)
        T = getfield(api_mod, :SystemStatsCombinedDataLength)
        @test as_number(T(86400)) === 86400.0
        @test as_number(T("86400")) === 86400.0
        @test as_number(T(nothing)) === nothing
        @test as_number(T()) === nothing   # value field undefined
    end
end

@testset "parse_daily_stats" begin
    @testset "happy path" begin
        csv = """
        id,timestamp,combined_cop,combined_data_length
        1,1641945600,2.4,86400
        1,1642032000,2.1,86400
        """
        rows = parse_daily_stats(csv)
        @test length(rows) == 2
        @test rows[1]["id"] === 1.0
        @test rows[1]["timestamp"] === 1.641945600e9
        @test rows[1]["combined_cop"] === 2.4
        @test rows[2]["combined_cop"] === 2.1
    end

    @testset "missing values" begin
        csv = """
        id,timestamp,combined_cop
        1,1641945600,
        1,1642032000,2.1
        """
        rows = parse_daily_stats(csv)
        @test rows[1]["combined_cop"] === nothing
        @test rows[2]["combined_cop"] === 2.1
    end

    @testset "short row gets padded with nothings" begin
        csv = "id,timestamp,combined_cop,combined_heat_kwh\n1,1641945600,2.4\n"
        rows = parse_daily_stats(csv)
        @test rows[1]["combined_cop"] === 2.4
        @test rows[1]["combined_heat_kwh"] === nothing
    end

    @testset "empty input" begin
        @test parse_daily_stats("") == Dict{String, Union{Float64, Nothing}}[]
        @test parse_daily_stats("   \n  ") == Dict{String, Union{Float64, Nothing}}[]
    end

    @testset "header-only input" begin
        rows = parse_daily_stats("id,timestamp,combined_cop\n")
        @test isempty(rows)
    end
end

@testset "flatten_timeseries" begin
    @testset "happy path with mix of values and nothings" begin
        raw = Dict{String, Vector{Vector{Any}}}(
            "heatpump_elec" => [[1641945600000, 19.5],
                                [1641949200000, nothing],
                                [1641952800000, 21.0]],
        )
        out = flatten_timeseries(raw)
        @test haskey(out, "heatpump_elec")
        rows = out["heatpump_elec"]
        @test length(rows) == 3
        @test rows[1][1] == unix2datetime(1641945600)
        @test rows[1][2] === 19.5
        @test rows[2][2] === nothing
        @test rows[3][2] === 21.0
    end

    @testset "string-encoded values are coerced" begin
        raw = Dict{String, Vector{Vector{Any}}}(
            "heatpump_heat" => [[1641945600000, "2.4"]],
        )
        out = flatten_timeseries(raw)
        @test out["heatpump_heat"][1][2] === 2.4
    end

    @testset "sub-second precision survives" begin
        # 1641945600250 ms = 2022-01-12T00:00:00.250 UTC
        raw = Dict{String, Vector{Vector{Any}}}(
            "f" => [[1641945600250, 1.0]],
        )
        out = flatten_timeseries(raw)
        @test out["f"][1][1] == DateTime("2022-01-12T00:00:00.250")
    end

    @testset "malformed rows raise ArgumentError" begin
        @test_throws ArgumentError flatten_timeseries(
            Dict("f" => [[1641945600000]]))                 # length 1
        @test_throws ArgumentError flatten_timeseries(
            Dict("f" => [[1641945600000, 1.0, 2.0]]))       # length 3
        @test_throws ArgumentError flatten_timeseries(
            Dict("f" => [["not a number", 1.0]]))           # bad timestamp
    end
end
