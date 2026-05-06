# HeatpumpMonitor.org-specific helpers layered on top of the generated API
# client and the template-provided `Client` overlay. Lives outside `src/api/`
# so it survives `gen/regenerate.jl` runs unchanged.

using OpenAPI: OpenAPI

include("helpers.jl")

const DEFAULT_BASE_URL = "https://heatpumpmonitor.org"

"""
    HeatpumpMonitorClient(; base_url = DEFAULT_BASE_URL,
                            session_cookie = nothing,
                            kwargs...) -> Client

Build a [`Client`](@ref) pre-configured for HeatpumpMonitor.org.

All endpoints in the published API except `/system/list/user.json` are public;
no token is required. Pass `session_cookie` to populate the `PHPSESSID`
cookie used by that single authenticated endpoint — obtain the value by
logging in via the web UI at `<base_url>/user/login` and copying it from
your browser.

Extra `kwargs...` are forwarded verbatim to `OpenAPI.Clients.Client`
(useful for `timeout`, `httplib`, etc.).

```julia
client = HeatpumpMonitorClient()
apis = heatpumpmonitor_apis(client)
systems, _ = list_public_systems(apis.system)
```
"""
function HeatpumpMonitorClient(;
        base_url::AbstractString = DEFAULT_BASE_URL,
        session_cookie::Union{Nothing, AbstractString} = nothing,
        kwargs...,
    )
    url = String(base_url)
    inner = OpenAPI.Clients.Client(
        url;
        pre_request_hook = _heatpumpmonitor_pre_request_hook(session_cookie),
        kwargs...,
    )
    return Client(inner, NoAuth(), url)
end

# `OpenAPI.Clients` calls the pre-request hook with two different signatures
# during a request lifecycle:
#   1. `(ctx::Ctx)` before URL/query assembly — chance to mutate `ctx.query`
#      or `ctx.header`. We use this to inject the session cookie when the
#      operation declares the `sessionCookie` security scheme.
#   2. `(resource_path, body, headers)` just before the HTTP call. Pass-through.
function _heatpumpmonitor_pre_request_hook(
        session_cookie::Union{Nothing, AbstractString},
    )
    cookie = session_cookie === nothing ? nothing : String(session_cookie)
    function hook(ctx::OpenAPI.Clients.Ctx)
        if cookie !== nothing && "sessionCookie" in ctx.auth
            ctx.header["Cookie"] = "PHPSESSID=$cookie"
        end
        return ctx
    end
    function hook(
            resource_path::AbstractString,
            body,
            headers::Dict{String, String},
        )
        return resource_path, body, headers
    end
    return hook
end

"""
    heatpumpmonitor_apis(c::Client) -> NamedTuple

Bundle the generated API instances so callers don't have to construct
each one manually:

```julia
apis = heatpumpmonitor_apis(client)
apis.system        # SystemApi
apis.timeseries    # TimeseriesApi

list_public_systems(apis.system)
timeseries_available(apis.timeseries, system_id)
```
"""
heatpumpmonitor_apis(c::Client) = (
    system = SystemApi(c.inner),
    timeseries = TimeseriesApi(c.inner),
)
