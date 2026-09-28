using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class UserStoryListTests
{
    [Fact]
    public async Task BaselineListUserStories_ReturnsLegacyArrayAndUsesVerifiedStatusFlags()
    {
        const string statuses = """
            [{"id":1,"name":"Done","is_closed":false,"is_archived":false},
             {"id":2,"name":"Terminado","is_closed":true,"is_archived":false},
             {"id":3,"name":"Guardado","is_closed":false,"is_archived":true},
             {"id":4,"name":"Archived","is_closed":false,"is_archived":false}]
            """;
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/userstory-statuses", statuses)
            .AddRoute(HttpMethod.Get, "/api/v1/userstories", request =>
            {
                Assert.Equal(
                    "?project=123&page=1&status__is_archived=false&status__is_closed=false",
                    request.Uri.Query);
                var selected = JsonSerializer.Deserialize<JsonElement>(statuses).EnumerateArray()
                    .Where(status => !status.GetProperty("is_closed").GetBoolean() &&
                                     !status.GetProperty("is_archived").GetBoolean())
                    .Select(status => new
                    {
                        id = status.GetProperty("id").GetInt32() + 10,
                        @ref = status.GetProperty("id").GetInt32(),
                        subject = status.GetProperty("name").GetString(),
                        status = status.GetProperty("id").GetInt32()
                    });
                return AuthenticationTests.Json(JsonSerializer.Serialize(selected));
            });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var tools = new UserStoryTools(new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth)));

            using var result = JsonDocument.Parse(await tools.ListUserStories(123));

            Assert.Equal(JsonValueKind.Array, result.RootElement.ValueKind);
            Assert.Equal(new[] { "Done", "Archived" }, result.RootElement.EnumerateArray()
                .Select(story => story.GetProperty("status").GetString())
                .ToArray());
        }
    }

    [Fact]
    public async Task BaselineListUserStories_RejectsNonpositiveProjectAndPageBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new UserStoryApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAsync<ArgumentException>(() => api.ListUserStoriesAsync(0));
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListUserStoriesAsync(123, 0));

            Assert.Empty(handler.Requests);
        }
    }
}
