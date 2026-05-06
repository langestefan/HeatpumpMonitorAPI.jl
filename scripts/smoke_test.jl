#!/usr/bin/env julia
# Smoke-test the generated client against the live HeatpumpMonitor.org API.
# Run from the package root: `julia --project scripts/smoke_test.jl`.
#
# Calls every operation declared in the spec, deserializing through OpenAPI.jl,
# and reports whether each call succeeds. The point is to surface any drift
# between the spec types and OpenAPI.jl's runtime deserializer before we layer
# helpers on top.

using HeatpumpMonitorAPI
using OpenAPI
using OpenAPI.Clients: Client as RawClient
using Dates

const BASE = "https://heatpumpmonitor.org"

raw = RawClient(BASE)
system = SystemApi(raw)
ts = TimeseriesApi(raw)

results = Tuple{String, Symbol, String}[]   # (name, :ok|:err, detail)

function record(f::Function, name::AbstractString)
    print(rpad(name, 38))
    try
        result, response = f()
        kind = result === nothing ? "Nothing" : string(typeof(result))
        # Truncate long type names for terminal readability
        length(kind) > 60 && (kind = kind[1:60] * "…")
        println("OK  ($(response.status))  $kind")
        push!(results, (name, :ok, kind))
    catch e
        msg = sprint(showerror, e)
        first_line = split(msg, '\n')[1]
        length(first_line) > 100 && (first_line = first_line[1:100] * "…")
        println("ERR $first_line")
        push!(results, (name, :err, first_line))
    end
end

# Pick a known-active system for the per-id endpoints. id=1 is the first system
# in the list and has been there for years — safe to hard-code for a smoke test.
const PROBE_ID = Int64(1)

record("list_public_systems")          do; list_public_systems(system)               end
record("get_system(id=$PROBE_ID)")     do; get_system(system, PROBE_ID)               end
record("stats_last7")                  do; stats_last7(system)                        end
record("stats_last30")                 do; stats_last30(system)                       end
record("stats_last90")                 do; stats_last90(system)                       end
record("stats_last365")                do; stats_last365(system)                      end
record("stats_all")                    do; stats_all(system)                          end
record("stats_last90 (id=$PROBE_ID)")  do; stats_last90(system; id = PROBE_ID)        end
record("stats_custom_window")          do
    stats_custom_window(system; id = PROBE_ID, start = "2026-01-01", var"__end__" = "2026-02-01")
end
record("stats_daily(id=$PROBE_ID)")    do; stats_daily(system, PROBE_ID)              end
record("stats_monthly(id=$PROBE_ID)")  do; stats_monthly(system, PROBE_ID)            end
record("timeseries_available")         do; timeseries_available(ts, PROBE_ID)         end

# Probe timeseries_data with valid feed names discovered above. We only run
# this if /timeseries/available succeeded and gave us names to work with.
let avail_result = nothing
    try
        result, _ = timeseries_available(ts, PROBE_ID)
        avail_result = result
    catch
    end
    if avail_result !== nothing
        feed_names = if avail_result isa Dict
            collect(keys(get(avail_result, "feeds", Dict())))
        elseif hasproperty(avail_result, :feeds) && avail_result.feeds !== nothing
            collect(keys(avail_result.feeds))
        else
            String[]
        end
        if !isempty(feed_names)
            picked = join(feed_names[1:min(3, length(feed_names))], ",")
            now_ts = round(Int, datetime2unix(now(UTC)))
            record("timeseries_data ($picked)") do
                timeseries_data(ts, PROBE_ID, picked;
                                start = string(now_ts - 86400),
                                var"__end__" = string(now_ts),
                                interval = 3600,
                                average = 1)
            end
        else
            println(rpad("timeseries_data", 38), "SKIP — no feed names discovered")
        end
    else
        println(rpad("timeseries_data", 38), "SKIP — /timeseries/available failed")
    end
end

# Summary
println()
n_ok = count(r -> r[2] == :ok, results)
n_err = count(r -> r[2] == :err, results)
println("Summary: $n_ok OK, $n_err errors (out of $(length(results)) calls)")
n_err == 0 || exit(1)
