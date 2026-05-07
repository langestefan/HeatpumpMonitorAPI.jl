using HeatpumpMonitorAPI
using Test

# BrokenRecord lets tests record an HTTP interaction once and replay it
# deterministically afterwards.
#
# Mode is decided by file existence (no env vars):
#
#   - Cassette file does NOT exist  → recording mode: real HTTP call,
#                                     request + response saved to disk.
#   - Cassette file exists          → playback mode: response replayed,
#                                     request shape verified against the
#                                     recorded one. No network is touched.
#
# Re-record a cassette by deleting its file (or the whole directory) and
# re-running the tests once on a machine with network + valid credentials.
#
# Storage: BrokenRecord defaults to `.yml` (human-readable, diffable).
# Pass `extension="bson"` for binary BSON if cassettes get large; both
# work the same way at the call site.
#
# `path = "test/cassettes"` is a VCR-style convention; BrokenRecord's own
# docs suggest `test/fixtures` — pick whichever you prefer and update
# `mkpath` and `_run_cassette_tests` together.

const _CASSETTES_DIR = joinpath(@__DIR__, "cassettes")

# All BrokenRecord interaction lives inside this function. Loading
# BrokenRecord at runtime via `Base.require` advances the Julia world,
# so any `BrokenRecord.*` call has to be reached via a function invocation
# (`Base.invokelatest`) — bare calls inside the same scope would fail with
# `MethodError: ... method too new to be called from this world context`.
function _run_cassette_tests(BrokenRecord)
    BrokenRecord.configure!(;
        path = _CASSETTES_DIR,
        # Strip credential-bearing fields before they hit disk. Header
        # matching is case-sensitive, so list common case variants of
        # the same name (`api_key` vs `X-API-Key`).
        # Headers that vary by environment (Julia/HTTP.jl version, OS)
        # are ignored so cassettes recorded on one version replay on
        # another. Credential-bearing headers are also stripped before
        # they hit disk.
        ignore_headers = ["Authorization", "X-API-Key", "api_key",
                          "X-Api-Key", "Cookie", "Set-Cookie",
                          "Proxy-Authorization", "User-Agent",
                          "Accept-Encoding"],
        ignore_query = ["api_key", "token", "access_token"],
    )

    @testset "cassettes directory wired up" begin
        @test isdir(_CASSETTES_DIR)
    end

    client = HeatpumpMonitorClient()
    apis = heatpumpmonitor_apis(client)

    @testset "get_system" begin
        sys, response = BrokenRecord.playback("get_system.yml") do
            get_system(apis.system, Int64(1))
        end
        @test response.status == 200
        @test sys.id == 1
        @test sys.location !== nothing
        @test sys.hp_type !== nothing
    end

    @testset "stats_last90 (single system)" begin
        body, response = BrokenRecord.playback("stats_last90_id1.yml") do
            stats_last90(apis.system; id = Int64(1))
        end
        @test response.status == 200
        @test body isa Dict{String}
        @test haskey(body, "1")
        s = body["1"]
        @test hasproperty(s, :combined_cop)
        @test hasproperty(s, :combined_data_length)
    end

    @testset "timeseries_available" begin
        avail, response = BrokenRecord.playback("timeseries_available_id1.yml") do
            timeseries_available(apis.timeseries, Int64(1))
        end
        @test response.status == 200
        @test avail.feeds !== nothing
        @test !isempty(avail.feeds)
        @test "heatpump_elec" in keys(avail.feeds)
    end

    # Use a fixed, historical 24h window so the request URL is stable
    # across recording sessions — BrokenRecord matches request shape.
    # `start` and `end` are unix epoch seconds; system 1 has data going
    # back to early 2022 so May 2025 will always have samples.
    let start_ts = 1748000000, end_ts = start_ts + 86400
        @testset "timeseries_data" begin
            data, response = BrokenRecord.playback("timeseries_data_id1.yml") do
                timeseries_data(apis.timeseries, Int64(1),
                    "heatpump_elec,heatpump_heat,heatpump_flowT";
                    start = string(start_ts),
                    var"__end__" = string(end_ts),
                    interval = 3600,
                    average = 1)
            end
            @test response.status == 200
            @test haskey(data, "heatpump_elec")
            @test haskey(data, "heatpump_heat")
            @test haskey(data, "heatpump_flowT")
            # Each row is [timestamp_ms, value_or_nothing].
            for row in data["heatpump_elec"]
                @test length(row) == 2
                @test row[1] isa Number   # timestamp always present
            end
        end
    end

    return nothing
end

let id = Base.identify_package("BrokenRecord")
    if id === nothing
        @info "BrokenRecord not installed; skipping cassette tests. " *
            "`pkg> add BrokenRecord@0.1` in `test/` to enable."
    else
        BrokenRecord = Base.require(id)
        mkpath(_CASSETTES_DIR)
        Base.invokelatest(_run_cassette_tests, BrokenRecord)
    end
end
