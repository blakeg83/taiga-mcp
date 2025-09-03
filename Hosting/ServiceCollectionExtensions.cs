using System.Net.Http.Headers;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Server;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddTaigaServices(this IServiceCollection services, IConfiguration config)
    {
        services.AddLogging(b => b.AddConsole(o => o.LogToStandardErrorThreshold = LogLevel.Information));

        var taigaBase = config["TAIGA_BASE_URL"] ?? "https://api.taiga.io/api/v1/";
        var taigaUser = config["TAIGA_USERNAME"] ?? "";
        var taigaPass = config["TAIGA_PASSWORD"] ?? "";

        services.AddHttpClient("taiga", client =>
        {
            client.BaseAddress = new Uri(taigaBase.EndsWith("/") ? taigaBase : taigaBase + "/");
            client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        });

        services.AddSingleton(new TaigaConfig(taigaUser, taigaPass));
        services.AddSingleton<TaigaApi>();

        services
            .AddMcpServer()
            .WithStdioServerTransport()
            .WithToolsFromAssembly();

        return services;
    }
}
