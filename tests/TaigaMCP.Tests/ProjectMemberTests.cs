using System.Text.Json;
using System.Net;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class ProjectMemberTests
{
    [Fact]
    public void MixedFixtureCapturesOrdinaryAndAdminMembershipShapes()
    {
        using var document = JsonDocument.Parse(ProjectMemberFixtures.MixedPage);
        var members = document.RootElement.EnumerateArray().ToArray();

        Assert.Equal(4, members.Length);
        Assert.Equal(42, members[0].GetProperty("user").GetInt32());
        Assert.True(members[0].GetProperty("is_user_active").GetBoolean());
        Assert.Equal(JsonValueKind.Null, members[1].GetProperty("role").ValueKind);
        Assert.False(members[1].GetProperty("is_user_active").GetBoolean());
        Assert.Equal(JsonValueKind.Null, members[2].GetProperty("user").ValueKind);
        Assert.Equal(JsonValueKind.Null, members[3].GetProperty("role").ValueKind);

        foreach (var member in members)
        {
            Assert.True(member.TryGetProperty("email", out _));
            Assert.True(member.TryGetProperty("user_email", out _) ||
                        member.TryGetProperty("invitation_extra_text", out _));
        }
    }

    [Fact]
    public async Task ListProjectMembersPage_MapsAllowlistedFieldsAndPreservesPagination()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/memberships",
                ProjectMemberFixtures.MixedPage,
                headers: new Dictionary<string, string>
                {
                    ["x-pagination-count"] = "8",
                    ["x-pagination-next"] = "/api/v1/memberships?project=123&page=3",
                    ["x-paginated"] = "true"
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new ProjectApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var page = await api.ListProjectMembersPageAsync(123, page: 2);

            Assert.Equal(2, page.Page);
            Assert.Equal(8, page.Total);
            Assert.Equal(3, page.NextPage);
            Assert.True(page.HasMore);
            Assert.Equal(4, page.Items.Count);
            Assert.Equal(501, page.Items[0].MembershipId);
            Assert.Equal(123, page.Items[0].Project);
            Assert.Equal(42, page.Items[0].UserId);
            Assert.Equal(7, page.Items[0].RoleId);
            Assert.Equal("Product Owner", page.Items[0].RoleName);
            Assert.Equal("Active User", page.Items[0].FullName);
            Assert.True(page.Items[0].IsUserActive);
            Assert.True(page.Items[0].IsAdmin);
            Assert.True(page.Items[0].IsOwner);
            Assert.Null(page.Items[1].RoleId);
            Assert.False(page.Items[1].IsUserActive);
            Assert.Null(page.Items[2].UserId);
            Assert.Equal(8, page.Items[2].RoleId);
            Assert.Null(page.Items[2].FullName);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/memberships"));
            Assert.Equal("?project=123&page=2", request.Uri.Query);
            var json = JsonSerializer.Deserialize<JsonElement>(ToolResponseJson.Serialize(page.Items[0]));
            Assert.Equal(501, json.GetProperty("membership_id").GetInt32());
            Assert.Equal(42, json.GetProperty("user_id").GetInt32());
            Assert.False(json.TryGetProperty("email", out _));
            Assert.False(json.TryGetProperty("user_email", out _));
            Assert.False(json.TryGetProperty("invitation_extra_text", out _));
        }
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(123, 0)]
    public async Task ListProjectMembersAsync_RejectsInvalidInputBeforeHttp(int projectId, int page)
    {
        var handler = new FakeHttpMessageHandler().AddJsonRoute(HttpMethod.Get, "/api/v1/memberships", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new ProjectApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            await Assert.ThrowsAsync<ArgumentException>(() => api.ListProjectMembersAsync(projectId, page));

            Assert.Empty(handler.Requests);
        }
    }

    [Fact]
    public async Task ListProjectMembersAsync_RejectsMalformedRequiredIdentityData()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/memberships",
                "[{\"id\":0,\"project\":123,\"user\":42}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new ProjectApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => api.ListProjectMembersAsync(123));

            Assert.Contains("project member id", exception.Message);
        }
    }

    [Fact]
    public async Task ListProjectMembersAsync_PropagatesSafePermissionError()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/memberships",
                "{\"detail\":\"membership secret\"}",
                HttpStatusCode.Forbidden);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = new ProjectApi(new TaigaTransport(new TestHttpClientFactory(handler), auth));

            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => api.ListProjectMembersAsync(123));

            Assert.Contains("403", exception.Message);
            Assert.Contains("permission denied", exception.Message);
            Assert.DoesNotContain("membership secret", exception.Message);
        }
    }
}
