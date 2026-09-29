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
            .Validate(o => !string.IsNullOrWhiteSpace(o.Username) && !string.IsNullOrWhiteSpace(o.Password),
                "Taiga credentials are required")
            .Validate(o => TaigaOptions.IsValidBaseUrl(o.BaseUrl), "Taiga base URL must be absolute HTTP/HTTPS without credentials, query or fragment")
            .PostConfigure(o => { if (TaigaOptions.IsValidBaseUrl(o.BaseUrl)) o.BaseUrl = o.BaseUrl.TrimEnd('/') + "/"; })
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
        services.AddSingleton<UserApi>();
        services.AddSingleton<IssueMetadataCache>();
        services.AddSingleton<IssueApi>();
        services.AddSingleton<UserStoryApi>();
        services.AddSingleton<TaskApi>();
        services.AddSingleton<EpicApi>();
        services.AddSingleton<SprintApi>();
        services.AddSingleton<WorkItemResolverApi>();
        services
            .AddMcpServer()
            .WithStdioServerTransport()
            .WithToolsFromAssembly();

        return services;
    }
}
