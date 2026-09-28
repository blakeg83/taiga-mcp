using TaigaMCP.Api;
using TaigaMCP.Caching;
using TaigaMCP.Config;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Net.Http.Headers;

namespace TaigaMCP.Hosting;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddTaigaServices(this IServiceCollection services, IConfiguration config)
    {
        services.AddLogging(b => b.AddConsole(o => o.LogToStandardErrorThreshold = LogLevel.Information));
        services
            .AddOptions<TaigaOptions>()
            .Bind(config.GetSection("Taiga"))
            .Validate(o => !string.IsNullOrEmpty(o.Username) && !string.IsNullOrEmpty(o.Password),
                "Taiga credentials are required")
            .Validate(o => o.MetadataTtlSeconds > 0, "Taiga metadata TTL must be positive")
            .ValidateOnStart();

        services.AddHttpClient("taiga", (sp, client) =>
        {
            var opts = sp.GetRequiredService<IOptions<TaigaOptions>>().Value;
            var baseUrl = opts.BaseUrl ?? "https://api.taiga.io/api/v1/";
            client.BaseAddress = new Uri(baseUrl.EndsWith("/") ? baseUrl : baseUrl + "/");
            client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        });

        services.AddSingleton(TimeProvider.System);
        services.AddSingleton<AuthClient>();
        services.AddSingleton<TaigaTransport>();
        services.AddSingleton<ProjectApi>();
        services.AddSingleton<IssueMetadataCache>();
        services.AddSingleton<IssueApi>();
        services.AddSingleton<UserStoryApi>();
        services
            .AddMcpServer()
            .WithStdioServerTransport()
            .WithToolsFromAssembly();

        return services;
    }
}
