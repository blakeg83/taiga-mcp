using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
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
}
