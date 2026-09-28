using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using TaigaMCP.Api;
using TaigaMCP.Caching;
using TaigaMCP.Config;
using TaigaMCP.Hosting;
using Xunit;

namespace TaigaMCP.Tests;

[CollectionDefinition("Environment", DisableParallelization = true)]
public sealed class EnvironmentCollection { }

[Collection("Environment")]
public sealed class ConfigurationTests
{
    [Theory]
    [InlineData("http://localhost/api/v1", true)]
    [InlineData("https://example.test/api/v1/", true)]
    [InlineData("relative/path", false)]
    [InlineData("ftp://example.test/api/", false)]
    [InlineData("https://user:password@example.test/", false)]
    [InlineData("https://example.test/?token=x", false)]
    [InlineData("https://example.test/#fragment", false)]
    public void Options_BaseUrl_ValidatesAndNormalizes(string url, bool valid)
    {
        using var provider = Build(url);
        if (!valid) Assert.Throws<OptionsValidationException>(() => provider.GetRequiredService<IOptions<TaigaOptions>>().Value);
        else Assert.EndsWith("/", provider.GetRequiredService<IOptions<TaigaOptions>>().Value.BaseUrl);
    }

    [Theory]
    [InlineData(" ", "password", 300)]
    [InlineData("user", "\t", 300)]
    [InlineData("user", "password", 0)]
    [InlineData("user", "password", -1)]
    public void Options_InvalidCredentialsOrTtl_Rejects(string username, string password, int ttl)
    {
        using var provider = Build("http://localhost/api", username, password, ttl);
        Assert.Throws<OptionsValidationException>(() => provider.GetRequiredService<IOptions<TaigaOptions>>().Value);
    }

    [Fact]
    public void Host_DocumentedEnvironmentKeysAndCommandLinePrecedence_WorkWithoutExtraProvider()
    {
        var values = new Dictionary<string, string>
        {
            ["TAIGA__USERNAME"] = "synthetic-env-user", ["TAIGA__PASSWORD"] = "synthetic-env-password",
            ["TAIGA__BASEURL"] = "http://localhost/api/v1", ["TAIGA__METADATATTLSECONDS"] = "123"
        };
        var original = values.Keys.ToDictionary(key => key, Environment.GetEnvironmentVariable);
        try
        {
            foreach (var pair in values) Environment.SetEnvironmentVariable(pair.Key, pair.Value);
            foreach (var redundantProvider in new[] { false, true })
            {
                var builder = Host.CreateApplicationBuilder(["--Taiga:Username=synthetic-cli-user"]);
                if (redundantProvider) builder.Configuration.AddEnvironmentVariables("TAIGA_");
                builder.Services.AddTaigaServices(builder.Configuration);
                using var host = builder.Build();
                var options = host.Services.GetRequiredService<IOptions<TaigaOptions>>().Value;
                Assert.Equal("synthetic-cli-user", options.Username);
                Assert.Equal("synthetic-env-password", options.Password);
                Assert.Equal("http://localhost/api/v1/", options.BaseUrl);
                Assert.Equal(123, options.MetadataTtlSeconds);
            }
        }
        finally { foreach (var pair in original) Environment.SetEnvironmentVariable(pair.Key, pair.Value); }
    }

    private static ServiceProvider Build(string url, string username = "synthetic", string password = "synthetic", int ttl = 300)
    {
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Taiga:BaseUrl"] = url, ["Taiga:Username"] = username, ["Taiga:Password"] = password,
            ["Taiga:MetadataTtlSeconds"] = ttl.ToString()
        }).Build();
        return new ServiceCollection().AddTaigaServices(config).BuildServiceProvider();
    }
}

public sealed class InputValidationTests
{
    [Theory]
    [InlineData("project")]
    [InlineData("issue")]
    [InlineData("page")]
    [InlineData("story")]
    [InlineData("storyPage")]
    [InlineData("slug")]
    [InlineData("subject")]
    [InlineData("updateSubject")]
    [InlineData("version")]
    [InlineData("emptyUpdate")]
    [InlineData("blankComment")]
    [InlineData("status")]
    [InlineData("assignee")]
    [InlineData("metadata")]
    public async Task InvalidArguments_RejectBeforeAnyHttp(string scenario)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            var issues = new IssueApi(transport, new IssueMetadataCache(transport));
            var projects = new ProjectApi(transport);
            var stories = new UserStoryApi(transport);
            Func<Task> action = scenario switch
            {
                "project" => () => issues.ListIssuesAsync(0, 1),
                "issue" => () => issues.GetIssueAsync(-1),
                "page" => () => projects.ListProjectsAsync(null, 0),
                "story" => () => stories.ListUserStoriesAsync(0),
                "storyPage" => () => stories.ListUserStoriesAsync(1, 0),
                "slug" => () => projects.ResolveProjectIdAsync(" "),
                "subject" => () => issues.CreateIssueAsync(1, " ", null, null, null, null, null, null, null),
                "updateSubject" => () => issues.UpdateIssueAsync(1, 0, subject: ""),
                "version" => () => issues.UpdateIssueAsync(1, -1, subject: "valid"),
                "emptyUpdate" => () => issues.UpdateIssueAsync(1, 0),
                "blankComment" => () => issues.UpdateIssueAsync(1, 0, comment: " "),
                "status" => () => issues.UpdateIssueAsync(1, 0, status: 0),
                "assignee" => () => issues.UpdateIssueAsync(1, 0, assigned_to: -1),
                _ => () => issues.ListIssueStatusesAsync(0)
            };
            await Assert.ThrowsAsync<ArgumentException>(action);
            Assert.Empty(handler.Requests);
        }
    }
}
