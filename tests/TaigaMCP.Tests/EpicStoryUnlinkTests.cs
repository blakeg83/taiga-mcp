using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

internal static class EpicStoryUnlinkFixtures
{
    public const int EpicId = 301;
    public const int UserStoryId = 102;

    public const string MissingRelationship = """
        {"detail":"Not found."}
        """;

    public const string PermissionDenied = """
        {"detail":"Permission denied."}
        """;

    public const string AuthenticationRejected = """
        {"detail":"Invalid token."}
        """;

    public const string UnexpectedSuccessfulBody = """
        {"removed":true}
        """;

    public static HttpResponseMessage NoContentResponse()
        => new(HttpStatusCode.NoContent);

    public static JsonElement Parse(string json)
        => JsonDocument.Parse(json).RootElement.Clone();
}

public sealed class EpicStoryUnlinkFixtureTests
{
    [Fact]
    public async Task NoContentFixtureUsesEmpty204Response()
    {
        using var response = EpicStoryUnlinkFixtures.NoContentResponse();

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Empty(await response.Content.ReadAsByteArrayAsync());
    }

    [Theory]
    [InlineData(EpicStoryUnlinkFixtures.MissingRelationship)]
    [InlineData(EpicStoryUnlinkFixtures.PermissionDenied)]
    [InlineData(EpicStoryUnlinkFixtures.AuthenticationRejected)]
    public void ErrorFixturesAreSafeDetailObjects(string body)
    {
        var json = EpicStoryUnlinkFixtures.Parse(body);

        Assert.Equal(JsonValueKind.Object, json.ValueKind);
        Assert.True(json.TryGetProperty("detail", out var detail));
        Assert.Equal(JsonValueKind.String, detail.ValueKind);
    }

    [Fact]
    public void UnexpectedSuccessfulBodyIsNotTheNoContentContract()
    {
        var json = EpicStoryUnlinkFixtures.Parse(EpicStoryUnlinkFixtures.UnexpectedSuccessfulBody);

        Assert.Equal(JsonValueKind.Object, json.ValueKind);
        Assert.True(json.GetProperty("removed").GetBoolean());
    }
}

public sealed class EpicStoryUnlinkApiTests
{
    [Fact]
    public async Task UnlinkUserStoryFromEpicAsync_PreservesStoryEpicAndOtherEpicRelationship()
    {
        var firstRelationshipExists = true;
        var secondRelationshipExists = true;
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/epics/301", EpicDetailFixtures.Rich)
            .AddRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories",
                _ => JsonResponse(firstRelationshipExists
                    ? "[{\"epic\":301,\"user_story\":102,\"order\":1}]"
                    : "[]"))
            .AddRoute(
                HttpMethod.Get,
                "/api/v1/userstories/102",
                _ => JsonResponse($"{{\"id\":102,\"ref\":18,\"project\":123,\"subject\":\"Shared story\",\"status\":7,\"status_extra_info\":{{\"name\":\"Ready\"}},\"version\":4,\"epics\":{(firstRelationshipExists ? "[{\"id\":301},{\"id\":302}]" : "[{\"id\":302}]")}}}"))
            .AddRoute(
                HttpMethod.Get,
                "/api/v1/epics/302/related_userstories",
                _ => JsonResponse(secondRelationshipExists
                    ? "[{\"epic\":302,\"user_story\":102,\"order\":2}]"
                    : "[]"))
            .AddRoute(
                HttpMethod.Delete,
                "/api/v1/epics/301/related_userstories/102",
                _ =>
                {
                    if (!firstRelationshipExists)
                        return new HttpResponseMessage(HttpStatusCode.NotFound)
                        {
                            Content = new StringContent(EpicStoryUnlinkFixtures.MissingRelationship)
                        };

                    firstRelationshipExists = false;
                    return EpicStoryUnlinkFixtures.NoContentResponse();
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var transport = new TaigaTransport(new TestHttpClientFactory(handler), auth);
            var epics = new EpicApi(transport);
            var beforeUnlink = handler.Requests.Count(request => request.Method == HttpMethod.Delete);

            var receipt = await epics.UnlinkUserStoryFromEpicAsync(301, 102);

            Assert.True(receipt.Removed);
            var unlinkRequests = handler.Requests
                .Where(request => request.Method == HttpMethod.Delete)
                .Skip(beforeUnlink)
                .ToArray();
            var unlinkRequest = Assert.Single(unlinkRequests);
            Assert.Equal(HttpMethod.Delete, unlinkRequest.Method);
            Assert.Equal("/api/v1/epics/301/related_userstories/102", unlinkRequest.Uri.AbsolutePath);
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Patch);

            var epic = await epics.GetEpicAsync(301);
            var story = await new UserStoryApi(transport).GetUserStoryAsync(102);
            var removedRelationships = await epics.ListEpicUserStoriesAsync(301);
            var otherRelationships = await epics.ListEpicUserStoriesAsync(302);

            Assert.Equal(301, epic.Id);
            Assert.Equal(102, story.Id);
            var remainingEpicIds = story.Epics!.Value.EnumerateArray()
                .Select(item => item.GetProperty("id").GetInt32())
                .ToArray();
            Assert.DoesNotContain(301, remainingEpicIds);
            Assert.Contains(302, remainingEpicIds);
            Assert.Empty(removedRelationships);
            var otherRelationship = Assert.Single(otherRelationships);
            Assert.Equal(302, otherRelationship.EpicId);
            Assert.Equal(102, otherRelationship.UserStoryId);
            Assert.False(firstRelationshipExists);
            Assert.True(secondRelationshipExists);
            Assert.DoesNotContain(handler.Requests, request =>
                request.Method == HttpMethod.Delete &&
                request.Uri.AbsolutePath is "/api/v1/epics/301" or "/api/v1/userstories/102");
        }
    }

    [Fact]
    public async Task UnlinkUserStoryFromEpicAsync_DeletesOnlyNestedRelationshipAndReturnsReceipt()
    {
        var handler = new FakeHttpMessageHandler().AddRoute(
            HttpMethod.Delete,
            "/api/v1/epics/301/related_userstories/102",
            _ => EpicStoryUnlinkFixtures.NoContentResponse());
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var receipt = await NewApi(handler, auth).UnlinkUserStoryFromEpicAsync(301, 102);

            Assert.Equal(301, receipt.EpicId);
            Assert.Equal(102, receipt.UserStoryId);
            Assert.True(receipt.Removed);
            Assert.Single(handler.Requests, request => request.Method == HttpMethod.Delete &&
                request.Uri.AbsolutePath == "/api/v1/epics/301/related_userstories/102");
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Get);
            Assert.DoesNotContain(handler.Requests, request => request.Method == HttpMethod.Patch);
        }
    }

    [Theory]
    [InlineData(0, 102)]
    [InlineData(301, 0)]
    public async Task UnlinkUserStoryFromEpicAsync_RejectsNonpositiveIdsBeforeHttp(int epicId, int userStoryId)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).UnlinkUserStoryFromEpicAsync(epicId, userStoryId));

            Assert.Empty(handler.Requests);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden)]
    [InlineData(HttpStatusCode.NotFound)]
    public async Task UnlinkUserStoryFromEpicAsync_DoesNotTreatFailureAsRemoval(HttpStatusCode statusCode)
    {
        var handler = new FakeHttpMessageHandler().AddTextRoute(
            HttpMethod.Delete,
            "/api/v1/epics/301/related_userstories/102",
            statusCode == HttpStatusCode.Forbidden ? EpicStoryUnlinkFixtures.PermissionDenied : EpicStoryUnlinkFixtures.MissingRelationship,
            statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var error = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).UnlinkUserStoryFromEpicAsync(301, 102));

            Assert.Equal(statusCode, error.StatusCode);
            Assert.DoesNotContain("Permission denied", error.Message, StringComparison.Ordinal);
            Assert.DoesNotContain("Not found", error.Message, StringComparison.Ordinal);
        }
    }

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private static HttpResponseMessage JsonResponse(string body)
        => new(HttpStatusCode.OK) { Content = new StringContent(body) };
}

public sealed class EpicStoryUnlinkToolTests
{
    [Fact]
    public async Task UnlinkUserStoryFromEpicTool_ReturnsSnakeCaseReceipt()
    {
        var handler = new FakeHttpMessageHandler().AddRoute(
            HttpMethod.Delete,
            "/api/v1/epics/301/related_userstories/102",
            _ => EpicStoryUnlinkFixtures.NoContentResponse());
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var json = JsonSerializer.Deserialize<JsonElement>(await new EpicTools(NewApi(handler, auth))
                .UnlinkUserStoryFromEpic(301, 102));

            Assert.Equal(301, json.GetProperty("epic_id").GetInt32());
            Assert.Equal(102, json.GetProperty("user_story_id").GetInt32());
            Assert.True(json.GetProperty("removed").GetBoolean());
        }
    }

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}
