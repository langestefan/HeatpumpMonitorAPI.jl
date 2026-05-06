using Dates: DateTime, unix2datetime

"""
    as_number(x) -> Union{Float64, Nothing}

Coerce a SystemStats field value into `Float64`, returning `nothing` for
missing-like inputs.

The HeatpumpMonitor.org API serializes numeric stats fields differently
across endpoints: `/system/stats/last90` and friends return raw JSON
numbers, but `/system/stats/monthly` stringifies every numeric column
(`"40.4423"`, `"2.19036"`, …). `timestamp` can additionally come back as
the boolean `false` for systems that have never been scored. This helper
papers over those representations so downstream code can do arithmetic
without case-by-case branching.

```julia
as_number(2.4)        # 2.4
as_number("2.4")      # 2.4
as_number(nothing)    # nothing
as_number(false)      # nothing  — sentinel for "unscored"
as_number("")         # nothing
as_number("garbage")  # nothing
```
"""
function as_number end

as_number(::Nothing) = nothing
as_number(::Bool) = nothing
as_number(x::Real) = Float64(x)
function as_number(x::AbstractString)
    s = strip(x)
    isempty(s) && return nothing
    return tryparse(Float64, s)
end

"""
    parse_daily_stats(csv::AbstractString) -> Vector{Dict{String, Union{Float64, Nothing}}}

Parse the CSV body returned by `/system/stats/daily` into one dict per row.

The endpoint returns plain CSV (`Content-Type: text/plain`) with a header
row naming each column and one data row per day. Empty fields become
`nothing`; everything else is parsed as `Float64`. The `id` and `timestamp`
columns round-trip losslessly through `Float64` for the value ranges the
API ever produces (system IDs and unix epoch seconds).

```julia
text = stats_daily(apis.system, 1)[1]
rows = parse_daily_stats(text)
rows[end]["combined_cop"]            # 2.4 :: Float64
rows[end]["combined_data_length"]    # 86400.0 (seconds in a full day)
```
"""
function parse_daily_stats(csv::AbstractString)
    lines = split(strip(csv), '\n'; keepempty = false)
    isempty(lines) && return Dict{String, Union{Float64, Nothing}}[]

    header = String.(split(first(lines), ','))
    data_lines = @view lines[(begin + 1):end]
    out = Vector{Dict{String, Union{Float64, Nothing}}}(undef, length(data_lines))
    for (i, line) in enumerate(data_lines)
        fields = split(line, ',')
        # Pad short rows with empty strings so the dict still has every key.
        if length(fields) < length(header)
            fields = vcat(fields, fill("", length(header) - length(fields)))
        end
        row = Dict{String, Union{Float64, Nothing}}()
        for (name, field) in zip(header, fields)
            row[name] = as_number(field)
        end
        out[i] = row
    end
    return out
end

"""
    flatten_timeseries(data::AbstractDict) -> Dict{String, Vector{Tuple{DateTime, Union{Float64, Nothing}}}}

Convert the raw `/timeseries/data` response into per-feed `(DateTime, value)`
pairs. The wire format is `Dict{String, Vector{Vector{Any}}}` where each
inner vector is `[unix_epoch_milliseconds, value_or_nothing]`. This helper
converts the millisecond timestamp to a UTC `DateTime` and coerces the
value via [`as_number`](@ref) so a `nothing`-valued sample stays `nothing`.

```julia
raw, _ = timeseries_data(apis.timeseries, 1, "heatpump_elec";
                         start = "1748000000", var"__end__" = "1748086400",
                         interval = 3600, average = 1)
ts = flatten_timeseries(raw)
ts["heatpump_elec"][1]   # (DateTime("2025-05-23T...") , 19.5)
```
"""
function flatten_timeseries(data::AbstractDict)
    out = Dict{String, Vector{Tuple{DateTime, Union{Float64, Nothing}}}}()
    for (feed, rows) in data
        out[String(feed)] = [_flatten_row(row) for row in rows]
    end
    return out
end

function _flatten_row(row)
    length(row) == 2 || throw(ArgumentError(
        "expected [timestamp_ms, value]; got vector of length $(length(row))"
    ))
    ts_ms = row[1]
    ts_ms isa Real || throw(ArgumentError(
        "timestamp must be numeric (unix epoch ms); got $(typeof(ts_ms))"
    ))
    return (unix2datetime(ts_ms / 1000), as_number(row[2]))
end
