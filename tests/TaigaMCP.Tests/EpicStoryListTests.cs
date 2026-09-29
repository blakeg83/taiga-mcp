using System.Text.Json;
using System.Text.Json.Serialization;
using System.Net;
using ModelContextProtocol.Server;
using TaigaMCP.Api;
using TaigaMCP.Models;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

internal static class EpicStoryListFixtures
{
    public const string Empty = "[]";

    public const string Single = """
        [{"epic":301,"user_story":102,"order":0}]
        """;

    public const string Multiple = """
        [{"epic":301,"user_story":102,"order":9223372036854775807},{"epic":301,"user_story":103,"order":17}]
        """;

    // The relationship serializer carries no story project field. A story from
    // another project is therefore represented by its returned ID only; the
    // client must not invent a same-project membership constraint.
    public const string CrossProject = """
        [{"epic":301,"user_story":902,"order":23}]
        """;

    public static IReadOnlyDictionary<string, string> FirstPageHeaders { get; } =
        new Dictionary<string, string>
        {
            ["x-paginated"] = "false",
            ["x-pagination-count"] = "0",
            ["x-pagination-current"] = "1"
        };

    public static IReadOnlyDictionary<string, string> SinglePageHeaders { get; } =
        new Dictionary<string, string>
        {
            ["x-paginated"] = "false",
            ["x-pagination-count"] = "1",
            ["x-pagination-current"] = "1"
        };

    public static IReadOnlyDictionary<string, string> ContinuedPageHeaders { get; } =
        new Dictionary<string, string>
        {
            ["x-paginated"] = "true",
            ["x-pagination-count"] = "3",
            ["x-pagination-current"] = "2",
            ["x-pagination-next"] = "3"
        };

    public static JsonDocument Parse(string json) => JsonDocument.Parse(json);
}

public sealed class EpicStoryListFixtureTests
{
    [Fact]
    public void EmptyRelationshipPageIsAnEmptyArray()
    {
        using var document = EpicStoryListFixtures.Parse(EpicStoryListFixtures.Empty);

        Assert.Equal(JsonValueKind.Array, document.RootElement.ValueKind);
        Assert.Empty(document.RootElement.EnumerateArray());
    }

    [Fact]
    public void SingleRelationshipUsesNestedIdentifiersAndAllowsZeroOrder()
    {
        using var document = EpicStoryListFixtures.Parse(EpicStoryListFixtures.Single);
        var relationship = Assert.Single(document.RootElement.EnumerateArray());

        Assert.Equal(301, relationship.GetProperty("epic").GetInt32());
        Assert.Equal(102, relationship.GetProperty("user_story").GetInt32());
        Assert.Equal(0, relationship.GetProperty("order").GetInt64());
        Assert.DoesNotContain("id", relationship.EnumerateObject().Select(property => property.Name));
    }

    [Fact]
    public void MultipleRelationshipsPreserveServerOrderAndLongOrderValues()
    {
        using var document = EpicStoryListFixtures.Parse(EpicStoryListFixtures.Multiple);
        var relationships = document.RootElement.EnumerateArray().ToArray();

        Assert.Equal(new[] { 102, 103 }, relationships.Select(item => item.GetProperty("user_story").GetInt32()));
        Assert.Equal(new[] { long.MaxValue, 17 }, relationships.Select(item => item.GetProperty("order").GetInt64()));
        Assert.All(relationships, relationship => Assert.Equal(301, relationship.GetProperty("epic").GetInt32()));
    }

    [Fact]
    public void CrossProjectRelationshipCarriesOnlyTheNestedStoryIdentity()
    {
        using var document = EpicStoryListFixtures.Parse(EpicStoryListFixtures.CrossProject);
        var relationship = Assert.Single(document.RootElement.EnumerateArray());

        Assert.Equal(301, relationship.GetProperty("epic").GetInt32());
        Assert.Equal(902, relationship.GetProperty("user_story").GetInt32());
        Assert.False(relationship.TryGetProperty("project", out _));
        Assert.Equal(
            new[] { "epic", "order", "user_story" },
            relationship.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
    }

    [Fact]
    public void RelationshipDtoUsesPublicIdentifiersWithoutCreationReceipt()
    {
        var dto = new EpicUserStoryRelationshipDto
        {
            EpicId = 301,
            UserStoryId = 902,
            Order = long.MaxValue
        };

        var json = JsonSerializer.Serialize(dto, new JsonSerializerOptions
        {
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        });
        using var document = JsonDocument.Parse(json);

        Assert.Equal(301, document.RootElement.GetProperty("epic_id").GetInt32());
        Assert.Equal(902, document.RootElement.GetProperty("user_story_id").GetInt32());
        Assert.Equal(long.MaxValue, document.RootElement.GetProperty("order").GetInt64());
        Assert.False(document.RootElement.TryGetProperty("created", out _));
    }

    [Fact]
    public void PaginationFixturesPreserveEmptyAndContinuedPageMetadata()
    {
        Assert.Equal("0", EpicStoryListFixtures.FirstPageHeaders["x-pagination-count"]);
        Assert.Equal("false", EpicStoryListFixtures.FirstPageHeaders["x-paginated"]);
        Assert.Equal("3", EpicStoryListFixtures.ContinuedPageHeaders["x-pagination-next"]);
        Assert.Equal("3", EpicStoryListFixtures.ContinuedPageHeaders["x-pagination-count"]);
    }
}

public sealed class EpicStoryListApiTests
{
    [Fact]
    public async Task ListEpicUserStoriesAsync_ReturnsOnePageInServerOrderWithHeaders()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories",
                EpicStoryListFixtures.Multiple,
                headers: EpicStoryListFixtures.ContinuedPageHeaders);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListEpicUserStoriesPageAsync(301, page: 2);

            Assert.Equal(2, page.Page);
            Assert.Equal(3, page.Total);
            Assert.Equal(3, page.NextPage);
            Assert.True(page.HasMore);
            Assert.Equal(new[] { 102, 103 }, page.Items.Select(item => item.UserStoryId));
            Assert.Equal(new[] { long.MaxValue, 17 }, page.Items.Select(item => item.Order));
            Assert.All(page.Items, item => Assert.Equal(301, item.EpicId));

            var request = Assert.Single(handler.Requests, item => item.Method == HttpMethod.Get &&
                item.Uri.AbsolutePath == "/api/v1/epics/301/related_userstories");
            Assert.Equal("?page=2", request.Uri.Query);
            Assert.DoesNotContain(handler.Requests, item => item.Uri.AbsolutePath.Contains("/userstories/"));
        }
    }

    [Fact]
    public async Task ListEpicUserStoriesAsync_AllowsCrossProjectStoryIdentityWithoutDetailExpansion()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories",
                EpicStoryListFixtures.CrossProject,
                headers: EpicStoryListFixtures.FirstPageHeaders);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListEpicUserStoriesPageAsync(301);

            var relationship = Assert.Single(page.Items);
            Assert.Equal(902, relationship.UserStoryId);
            Assert.Equal(23, relationship.Order);
            Assert.Equal(1, handler.Requests.Count(item => item.Method == HttpMethod.Get));
        }
    }

    [Fact]
    public async Task ListEpicUserStoriesAsync_ReturnsEmptyPageAndUnknownMissingMetadata()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories",
                EpicStoryListFixtures.Empty);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var page = await NewApi(handler, auth).ListEpicUserStoriesPageAsync(301);

            Assert.Empty(page.Items);
            Assert.Equal(1, page.Page);
            Assert.Null(page.Total);
            Assert.Null(page.NextPage);
            Assert.Null(page.HasMore);
        }
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(301, 0)]
    public async Task ListEpicUserStoriesAsync_RejectsNonpositiveInputsBeforeHttp(int epicId, int page)
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() =>
                NewApi(handler, auth).ListEpicUserStoriesPageAsync(epicId, page));

            Assert.Empty(handler.Requests);
        }
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("[{\"epic\":301,\"user_story\":0,\"order\":1}]")]
    [InlineData("[{\"epic\":301,\"user_story\":902,\"order\":\"later\"}]")]
    public async Task ListEpicUserStoriesAsync_RejectsMalformedSuccessfulResponses(string responseBody)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories",
                responseBody);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).ListEpicUserStoriesPageAsync(301));

            Assert.Contains("invalid epic", exception.Message, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public async Task ListEpicUserStoriesAsync_RejectsRelationshipForAnotherEpic()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories",
                "[{\"epic\":302,\"user_story\":902,\"order\":1}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).ListEpicUserStoriesPageAsync(301));

            Assert.Contains("different epic", exception.Message);
        }
    }

    [Fact]
    public async Task ListEpicUserStoriesAsync_PropagatesPermissionFailureSafely()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories",
                "{\"detail\":\"synthetic relationship secret\"}",
                HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).ListEpicUserStoriesPageAsync(301));

            Assert.Contains("403", exception.Message);
            Assert.Contains("permission denied", exception.Message);
            Assert.DoesNotContain("synthetic relationship secret", exception.Message);
        }
    }

    [Fact]
    public async Task ListEpicUserStoriesAsync_ReportsTransportFailureWithoutSecretDetails()
    {
        var handler = new FakeHttpMessageHandler()
            .AddExceptionRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories",
                new IOException("synthetic relationship transport secret"));
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() =>
                NewApi(handler, auth).ListEpicUserStoriesPageAsync(301));

            Assert.Contains("transport failure", exception.Message);
            Assert.DoesNotContain("synthetic relationship transport secret", exception.Message);
        }
    }

    [Fact]
    public async Task ListEpicUserStoriesAsync_PropagatesPreCancellationWithoutHttp()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories",
                EpicStoryListFixtures.Single);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                NewApi(handler, auth).ListEpicUserStoriesPageAsync(301, cancellationToken: cancellation.Token));

            Assert.Empty(handler.Requests);
        }
    }

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}

public sealed class EpicStoryListToolTests
{
    [Fact]
    public async Task ListEpicUserStoriesToolReturnsPageEnvelopeWithoutCreationReceipt()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/epics/301/related_userstories",
                EpicStoryListFixtures.Single,
                headers: EpicStoryListFixtures.SinglePageHeaders);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var json = JsonSerializer.Deserialize<JsonElement>(
                await new EpicTools(NewApi(handler, auth)).ListEpicUserStories(301));

            Assert.Equal(1, json.GetProperty("page").GetInt32());
            Assert.Equal(102, json.GetProperty("items")[0].GetProperty("user_story_id").GetInt32());
            Assert.Equal(0, json.GetProperty("items")[0].GetProperty("order").GetInt64());
            Assert.False(json.GetProperty("items")[0].TryGetProperty("created", out _));
            Assert.Equal(1, json.GetProperty("total").GetInt32());
            Assert.False(json.GetProperty("has_more").GetBoolean());
        }
    }

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}
