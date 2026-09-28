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
            .ValidateOnStart();

        services.AddHttpClient("taiga", (sp, client) =>
        {
            var opts = sp.GetRequiredService<IOptions<TaigaOptions>>().Value;
            var baseUrl = opts.BaseUrl ?? "https://api.taiga.io/api/v1/";
            client.BaseAddress = new Uri(baseUrl.EndsWith("/") ? baseUrl : baseUrl + "/");
            client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        });

        services.AddSingleton<AuthClient>();
        services.AddSingleton<ProjectApi>(sp =>
            new ProjectApi(sp.GetRequiredService<IHttpClientFactory>().CreateClient("taiga"),
                sp.GetRequiredService<AuthClient>()));

        services.AddSingleton<IssueMetadataCache>(sp =>
            new IssueMetadataCache(sp.GetRequiredService<IHttpClientFactory>().CreateClient("taiga"),
                sp.GetRequiredService<AuthClient>()));

        services.AddSingleton<IssueApi>(sp =>
            new IssueApi(sp.GetRequiredService<IHttpClientFactory>().CreateClient("taiga"),
                sp.GetRequiredService<AuthClient>(),
                sp.GetRequiredService<IssueMetadataCache>()));

        services.AddSingleton<UserStoryApi>(sp =>
            new UserStoryApi(sp.GetRequiredService<IHttpClientFactory>().CreateClient("taiga"),
                sp.GetRequiredService<AuthClient>()));

        services
            .AddMcpServer()
            .WithStdioServerTransport()
            .WithToolsFromAssembly();

        return services;
    }
}
