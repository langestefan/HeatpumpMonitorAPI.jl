using HeatpumpMonitorAPI
using OpenAPI
using Test

@testset "Client construction" begin
    c = HeatpumpMonitorAPI.Client("https://example.test/api")
    @test c isa HeatpumpMonitorAPI.Client
    @test c.base_url == "https://example.test/api"
    @test c.auth isa HeatpumpMonitorAPI.NoAuth
    @test c.inner isa OpenAPI.Clients.Client
end

@testset "Client with auth" begin
    c = HeatpumpMonitorAPI.Client("https://example.test"; auth = HeatpumpMonitorAPI.BearerToken("abc"))
    @test c.auth isa HeatpumpMonitorAPI.BearerToken
    @test c.auth.token == "abc"
end
