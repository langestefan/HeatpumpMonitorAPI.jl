# Julia API Reference

```@meta
CurrentModule = HeatpumpMonitorAPI
```

## Client

```@docs
Client
```

## Auth

```@docs
Auth
NoAuth
BearerToken
APIKey
BasicAuth
resolve_credentials
HeatpumpMonitorAPI.apply!
HeatpumpMonitorAPI.build_pre_request_hook
```

## Errors

```@docs
APIError
NetworkError
ClientError
ServerError
AuthError
RateLimitError
TimeoutError
check_response
HeatpumpMonitorAPI.parse_retry_after
```

## Reliability

```@docs
RetryPolicy
with_retry
HeatpumpMonitorAPI.is_retryable
HeatpumpMonitorAPI.backoff_delay
TokenBucket
acquire!
with_rate_limit
with_timeout
with_logging
redact_headers
DefaultMiddleware
default_middleware
with_defaults
```

## Pretty printing

```@docs
Base.show(::IO, ::MIME"text/plain", ::T) where T <: OpenAPI.APIModel
```

## Pagination

```@docs
paginate_cursor
paginate_offset
paginate_pagenum
```

## HeatpumpMonitor conveniences

```@docs
HeatpumpMonitorClient
heatpumpmonitor_apis
DEFAULT_BASE_URL
```

## Helpers

```@docs
as_number
parse_daily_stats
flatten_timeseries
```
