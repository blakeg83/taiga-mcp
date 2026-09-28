using TaigaMCP.Api;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class EpicDetailTests
{
    [Fact]
    public async Task GetEpicAsync_MapsRichDetailWithoutRelationshipReads()
    {
        var handler = EpicRoutes(EpicDetailFixtures.Rich, 301);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var epic = await NewApi(handler, auth).GetEpicAsync(301);

            Assert.Equal(301, epic.Id);
            Assert.Equal(12, epic.Ref);
            Assert.Equal(123, epic.Project);
            Assert.Equal("Saved search epic — ✓", epic.Subject);
            Assert.Equal("**Acceptance:** preserve Markdown and Unicode — ✓", epic.Description);
            Assert.Equal(7, epic.StatusId);
            Assert.Equal("Ready", epic.Status);
            Assert.Null(epic.AssignedTo);
            Assert.Equal("#336699", epic.Color);
            Assert.Equal(2, epic.Tags!.Count);
            Assert.Equal("2026-09-28T12:03:00Z", epic.Modified);
            Assert.False(epic.IsClosed);
            Assert.True(epic.IsBlocked);
            Assert.Equal("Waiting for the saved-search API.", epic.BlockedNote);
            Assert.True(epic.ClientRequirement);
            Assert.False(epic.TeamRequirement);
            Assert.Equal(3, epic.UserStoriesCounts!.Value.GetProperty("total").GetInt32());
            Assert.Equal(4, epic.Version);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/epics/301"));
            Assert.Equal(HttpMethod.Get, request.Method);
            Assert.DoesNotContain(handler.Requests, item => item.Uri.AbsolutePath.Contains("related_userstories"));
            Assert.DoesNotContain(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/epic-statuses"));
        }
    }

    [Theory]
    [InlineData(EpicDetailFixtures.MissingVersion)]
    [InlineData(EpicDetailFixtures.InvalidIdentity)]
    [InlineData(EpicDetailFixtures.InvalidReference)]
    [InlineData(EpicDetailFixtures.InvalidProject)]
    [InlineData(EpicDetailFixtures.InvalidVersion)]
    public async Task GetEpicAsync_RejectsMalformedRequiredDetailFields(string payload)
    {
        var handler = EpicRoutes(payload, 301);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).GetEpicAsync(301));

            Assert.Contains("epic", exception.Message);
        }
    }

    [Fact]
    public async Task GetEpicAsync_RejectsNonpositiveIdBeforeHttp()
    {
        var handler = new FakeHttpMessageHandler();
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => NewApi(handler, auth).GetEpicAsync(0));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task GetEpicAsync_PreservesStatusIdWhenLabelIsUnavailable()
    {
        var handler = EpicRoutes(
            """{"id":301,"ref":12,"project":123,"status":99,"status_extra_info":null,"version":1}""",
            301);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var epic = await NewApi(handler, auth).GetEpicAsync(301);

            Assert.Equal(99, epic.StatusId);
            Assert.Null(epic.Status);
            Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/epics/301"));
        }
    }

    private static EpicApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));

    private static FakeHttpMessageHandler EpicRoutes(string epic, int epicId)
        => new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, $"/api/v1/epics/{epicId}", epic);
}
