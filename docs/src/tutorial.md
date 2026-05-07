```@meta
CurrentModule = HeatpumpMonitorAPI
```

# Tutorial: a Dutch heat pump in winter

This page walks through a full, end-to-end query against the live
[HeatpumpMonitor.org](https://heatpumpmonitor.org) API and plots the
results with [CairoMakie](https://docs.makie.org/stable/explanations/backends/cairomakie).
Every code block runs at documentation-build time, so what you see
below is real data fetched at the moment this page was last built.

The example uses **system 499** — a 5 kW Vaillant aroTHERM plus
(R290 propane) installed in a semi-detached Dutch home. The
corresponding dashboard is at
[heatpumpmonitor.org/dashboard?id=499](https://heatpumpmonitor.org/dashboard?id=499).

## Connecting and inspecting the system

Build a client and pull the system metadata:

```@example tutorial
using HeatpumpMonitorAPI

client = HeatpumpMonitorClient()
apis   = heatpumpmonitor_apis(client)

sys, _ = get_system(apis.system, Int64(499))
(; location = sys.location,
   hp_model = sys.hp_model,
   hp_type = sys.hp_type,
   hp_output_kW = sys.hp_output,
   refrigerant = sys.refrigerant,
   property = sys.property,
   floor_area_m2 = sys.floor_area,
   heat_loss_kW = sys.heat_loss,
   design_flow_C = sys.flow_temp)
```

Available timeseries feeds and their reporting intervals:

```@example tutorial
avail, _ = timeseries_available(apis.timeseries, Int64(499))
sort(collect(keys(avail.feeds)))
```

## 90-day performance summary

Stats endpoints always return a `Dict` keyed by system ID (as a
string), even when an `id=...` query parameter is supplied. The
[`as_number`](@ref) helper coerces the response field into `Float64`
regardless of whether the upstream wrapped it as a number, a numeric
string, or `false`:

```@example tutorial
stats, _ = stats_last90(apis.system; id = Int64(499))
s = stats["499"]

(; combined_cop = as_number(s.combined_cop),
   running_cop = as_number(s.running_cop),
   space_cop = as_number(s.space_cop),
   water_cop = as_number(s.water_cop),
   covered_days = as_number(s.combined_data_length) / 86400,
   mean_flow_C = as_number(s.combined_flowT_mean),
   mean_outside_C = as_number(s.combined_outsideT_mean),
   total_heat_kWh = as_number(s.combined_heat_kwh),
   total_elec_kWh = as_number(s.combined_elec_kwh))
```

## Daily COP over the last few months

`/system/stats/daily` returns CSV (one row per day, ~91 columns).
[`parse_daily_stats`](@ref) parses it into a vector of dicts, then we
plot the most recent 90 days of combined COP together with the mean
outside temperature on a twin axis:

```@example tutorial
using CairoMakie
using Dates: unix2datetime, datetime2unix, DateTime, now, UTC

CairoMakie.activate!(type = "png")

csv, _ = stats_daily(apis.system, Int64(499))
rows   = parse_daily_stats(csv)

# Last 90 days, sorted oldest → newest.
recent = sort(rows[max(end - 89, 1):end], by = r -> r["timestamp"])

times = [unix2datetime(r["timestamp"]) for r in recent]
cop   = [r["combined_cop"]            for r in recent]
out_T = [r["combined_outsideT_mean"]  for r in recent]

fig = Figure(size = (900, 400))

ax1 = Axis(fig[1, 1];
    xlabel = "date",
    ylabel = "daily COP",
    ylabelcolor = :tomato,
    title = "System 499 — daily COP and outside temperature",
)
ax2 = Axis(fig[1, 1];
    ylabel = "mean outside °C",
    yaxisposition = :right,
    ylabelcolor = :steelblue,
)
hidespines!(ax2)
hidexdecorations!(ax2)

scatterlines!(ax1, times, cop;
    color = :tomato, markersize = 6, label = "combined COP")
lines!(ax2, times, out_T;
    color = :steelblue, linestyle = :dash, label = "outside °C")

# Reference line at COP = 3 (a useful "rule of thumb" target for ASHPs).
hlines!(ax1, [3.0]; color = (:black, 0.3), linestyle = :dot)

axislegend(ax1; position = :lt)
fig
```

Cold days drag COP down — exactly what you'd expect for an
air-source heat pump: the temperature lift compressor has to do
grows as outside drops.

## A 24-hour timeseries window

`/timeseries/data` returns `Dict{feed_name, [[unix_ms, value], ...]}`.
[`flatten_timeseries`](@ref) converts the nested arrays into
`(DateTime, value)` pairs, with millisecond timestamps already
converted. We pick a recent winter day for which all feeds have data:

```@example tutorial
# A January 2026 day — pick a fixed window so this page is reproducible.
start_ts = 1737936000          # 2025-01-27 00:00 UTC
end_ts   = start_ts + 86400    # 2025-01-28 00:00 UTC

raw, _ = timeseries_data(apis.timeseries, Int64(499),
    "heatpump_elec,heatpump_heat,heatpump_flowT,heatpump_returnT,heatpump_outsideT";
    start = string(start_ts),
    var"__end__" = string(end_ts),
    interval = 600,            # 10-minute samples
    average = 1)

ts = flatten_timeseries(raw)
length(ts["heatpump_flowT"])
```

### Temperatures

Plot flow / return / outside on one axis. The flow-minus-outside
gap is the temperature lift the compressor has to deliver.

```@example tutorial
function clean(pairs)
    keep = filter(p -> p[2] !== nothing, pairs)
    [p[1] for p in keep], [Float64(p[2]) for p in keep]
end

t_flow,    v_flow    = clean(ts["heatpump_flowT"])
t_return,  v_return  = clean(ts["heatpump_returnT"])
t_outside, v_outside = clean(ts["heatpump_outsideT"])

fig = Figure(size = (900, 400))
ax = Axis(fig[1, 1];
    xlabel = "UTC time",
    ylabel = "temperature (°C)",
    title = "System 499 — flow / return / outside, 2025-01-27",
)
lines!(ax, t_flow,    v_flow;    color = :tomato,     label = "flow")
lines!(ax, t_return,  v_return;  color = :darkorange, label = "return")
lines!(ax, t_outside, v_outside; color = :steelblue,  label = "outside")
axislegend(ax; position = :rt)
fig
```

### Power and instantaneous COP

The same window, but plotting electrical input vs heat output. The
ratio at any instant is the running COP:

```@example tutorial
t_elec, v_elec = clean(ts["heatpump_elec"])
t_heat, v_heat = clean(ts["heatpump_heat"])

fig = Figure(size = (900, 500))

ax1 = Axis(fig[1, 1];
    ylabel = "power (W)",
    title = "System 499 — power and instantaneous COP, 2025-01-27",
)
lines!(ax1, t_elec, v_elec; color = :purple,    label = "electrical input")
lines!(ax1, t_heat, v_heat; color = :seagreen,  label = "heat output")
axislegend(ax1; position = :lt)
hidexdecorations!(ax1; ticks = false, grid = false)

# Sample the heat / elec ratio at the elec timestamps. This is the
# instantaneous COP — only valid when the unit is actually running.
running = [(t, v / w) for ((t, v), (_, w)) in zip(zip(t_elec, v_heat), zip(t_elec, v_elec))
           if w > 50.0]   # tiny standby draw shouldn't be counted
t_cop = [p[1] for p in running]
v_cop = [p[2] for p in running]

ax2 = Axis(fig[2, 1];
    xlabel = "UTC time",
    ylabel = "instantaneous COP",
)
scatterlines!(ax2, t_cop, v_cop; color = :tomato, markersize = 4)
hlines!(ax2, [as_number(s.combined_cop)]; color = (:black, 0.3),
    linestyle = :dot, label = "90-day combined COP")
axislegend(ax2; position = :lt)

linkxaxes!(ax1, ax2)
fig
```

## Weather-compensation curve

Air-source heat pumps run a *weather compensation* curve: the target
flow temperature drops linearly with the outside temperature. Plotting
running flow temperature against outside temperature for the last 90
days reveals the curve in scatter form.

```@example tutorial
# Pull a longer window with hourly resolution.
end_ts2   = round(Int, datetime2unix(now(UTC)))
start_ts2 = end_ts2 - 90 * 86400

raw90, _ = timeseries_data(apis.timeseries, Int64(499),
    "heatpump_flowT,heatpump_outsideT,heatpump_elec";
    start = string(start_ts2),
    var"__end__" = string(end_ts2),
    interval = 3600,
    average = 1)

ts90 = flatten_timeseries(raw90)

# Pair flow / outside / elec by timestamp, drop standby intervals.
flow_by_ts    = Dict(t => v for (t, v) in ts90["heatpump_flowT"]    if v !== nothing)
outside_by_ts = Dict(t => v for (t, v) in ts90["heatpump_outsideT"] if v !== nothing)
elec_by_ts    = Dict(t => v for (t, v) in ts90["heatpump_elec"]     if v !== nothing)

xs = Float64[]; ys = Float64[]
for (t, oT) in outside_by_ts
    haskey(flow_by_ts, t)            || continue
    haskey(elec_by_ts, t)            || continue
    elec_by_ts[t] > 50.0             || continue   # only running hours
    push!(xs, Float64(oT))
    push!(ys, Float64(flow_by_ts[t]))
end

fig = Figure(size = (700, 500))
ax = Axis(fig[1, 1];
    xlabel = "outside temperature (°C)",
    ylabel = "flow temperature (°C)",
    title = "System 499 — weather compensation, last 90 days",
)
scatter!(ax, xs, ys; color = (:tomato, 0.4), markersize = 4)
fig
```

The downward trend from right to left is the weather-compensation
curve: as it gets colder outside, the controller asks for hotter
flow water to keep the indoor temperature stable. The flat shelf at
the design flow temperature on the coldest days is where the unit
hits the ceiling configured in the controller (`flow_temp` in the
metadata above).

## Where to next

- Browse the full set of generated endpoints in the
  [REST API](api/index.md) reference.
- Read [Getting Started](getting_started.md) for a tour of the
  client overlay (auth, retry, rate-limit, pagination).
- See the helper docstrings: [`as_number`](@ref),
  [`parse_daily_stats`](@ref), [`flatten_timeseries`](@ref),
  [`HeatpumpMonitorClient`](@ref), [`heatpumpmonitor_apis`](@ref).
