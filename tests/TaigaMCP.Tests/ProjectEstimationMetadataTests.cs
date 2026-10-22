using System.Net;
using System.Text.Json;
using TaigaMCP.Api;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class ProjectEstimationMetadataTests
{
    [Fact]
    public async Task ListPointsAsync_MapsOrderingProjectAndFractionalOrNullValues()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/points",
                ProjectEstimationMetadataFixtures.Points,
                headers: new Dictionary<string, string>
                {
                    ["x-paginated"] = "true",
                    ["x-pagination-count"] = "4",
                    ["x-pagination-next"] = "/api/v1/points?project=123&page=3"
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);

            var page = await api.ListPointsPageAsync(123, 2);
            var points = page.Items;

            Assert.Equal(3, points.Count);
            Assert.Equal(21, points[0].Id);
            Assert.Equal("Not estimated", points[0].Name);
            Assert.Null(points[0].Value);
            Assert.Equal(0, points[0].Order);
            Assert.Equal(123, points[0].Project);
            Assert.Equal(0.5, points[1].Value);
            Assert.Equal(5d, points[2].Value);
            Assert.Equal(2, page.Page);
            Assert.Equal(4, page.Total);
            Assert.Equal(3, page.NextPage);
            Assert.True(page.HasMore);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/points"));
            Assert.Equal("?project=123&page=2", request.Uri.Query);

            var serialized = JsonSerializer.Deserialize<JsonElement>(await new ProjectTools(api).ListPoints(123, 1));
            Assert.Equal(1, serialized.GetProperty("page").GetInt32());
            Assert.Equal(4, serialized.GetProperty("total").GetInt32());
            Assert.Equal(3, serialized.GetProperty("next_page").GetInt32());
            Assert.True(serialized.GetProperty("has_more").GetBoolean());
            var items = serialized.GetProperty("items");
            Assert.Equal(JsonValueKind.Null, items[0].GetProperty("value").ValueKind);
            Assert.Equal(0.5, items[1].GetProperty("value").GetDouble());
            Assert.False(items[0].TryGetProperty("description", out _));
            Assert.Equal("?project=123&page=1", handler.Requests.Last(item => item.Uri.AbsolutePath.EndsWith("/points")).Uri.Query);
        }
    }

    [Fact]
    public async Task ListProjectRolesAsync_MapsEstimationFlagsAndPermissionsAndOmitsMemberCounts()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(
                HttpMethod.Get,
                "/api/v1/roles",
                ProjectEstimationMetadataFixtures.Roles,
                headers: new Dictionary<string, string>
                {
                    ["x-paginated"] = "true",
                    ["x-pagination-count"] = "4",
                    ["x-pagination-next"] = "/api/v1/roles?project=123&page=3"
                });
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);

            var page = await api.ListProjectRolesPageAsync(123, 2);
            var roles = page.Items;

            Assert.Equal(2, roles.Count);
            Assert.Equal(7, roles[0].Id);
            Assert.Equal("Developer", roles[0].Name);
            Assert.True(roles[0].Computable);
            Assert.False(roles[1].Computable);
            Assert.Equal(2, page.Page);
            Assert.Equal(4, page.Total);
            Assert.Equal(3, page.NextPage);
            Assert.True(page.HasMore);

            var request = Assert.Single(handler.Requests, item => item.Uri.AbsolutePath.EndsWith("/roles"));
            Assert.Equal("?project=123&page=2", request.Uri.Query);

            var serialized = JsonSerializer.Deserialize<JsonElement>(await new ProjectTools(api).ListProjectRoles(123, 1));
            Assert.Equal(1, serialized.GetProperty("page").GetInt32());
            Assert.Equal(4, serialized.GetProperty("total").GetInt32());
            Assert.Equal(3, serialized.GetProperty("next_page").GetInt32());
            Assert.True(serialized.GetProperty("has_more").GetBoolean());
            var items = serialized.GetProperty("items");
            Assert.Equal(7, items[0].GetProperty("id").GetInt32());
            Assert.True(items[0].GetProperty("computable").GetBoolean());
            Assert.Equal("view_project", Assert.Single(items[0].GetProperty("permissions").EnumerateArray()).GetString());
            Assert.False(items[1].TryGetProperty("permissions", out _));
            Assert.False(items[0].TryGetProperty("members_count", out _));
            Assert.Equal("?project=123&page=1", handler.Requests.Last(item => item.Uri.AbsolutePath.EndsWith("/roles")).Uri.Query);
        }
    }

    [Theory]
    [InlineData("")]
    [InlineData(",\"permissions\":null")]
    [InlineData(",\"permissions\":[]")]
    [InlineData(",\"permissions\":[\"add_us\",\"modify_us\",\"future_permission\"]")]
    public async Task ListProjectRolesAsync_PreservesUnknownEmptyAndExplicitPermissions(string permissionsField)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/roles",
                "[{\"id\":7,\"name\":\"Developer\",\"computable\":true" + permissionsField + "}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var json = JsonSerializer.Deserialize<JsonElement>(await new ProjectTools(NewApi(handler, auth)).ListProjectRoles(123));
            var role = json.GetProperty("items")[0];
            if (permissionsField.Length == 0 || permissionsField.Contains("null"))
            {
                Assert.False(role.TryGetProperty("permissions", out _));
            }
            else
            {
                var permissions = role.GetProperty("permissions").EnumerateArray().Select(item => item.GetString()).ToArray();
                Assert.Equal(permissionsField.Contains("add_us")
                    ? new[] { "add_us", "modify_us", "future_permission" }
                    : Array.Empty<string>(), permissions);
            }
        }
    }

    [Theory]
    [InlineData("true")]
    [InlineData("\"add_us\"")]
    [InlineData("{}")]
    [InlineData("[null]")]
    [InlineData("[42]")]
    [InlineData("[\"\"]")]
    [InlineData("[\" \"]")]
    [InlineData("[\"add_us\",{\"secret\":\"private-value\"}]")]
    public async Task ListProjectRolesAsync_RejectsMalformedPermissionsWithoutLeakingValues(string permissions)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/roles",
                "[{\"id\":7,\"name\":\"Developer\",\"computable\":true,\"permissions\":" + permissions + "}]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).ListProjectRolesAsync(123));
            Assert.Equal("Taiga returned invalid project role permissions data.", exception.Message);
        }
    }

    [Fact]
    public async Task ListPointsAndRolesAsync_PreserveEmptyResults()
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/points", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/roles", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);

            Assert.Empty(await api.ListPointsAsync(123));
            Assert.Empty(await api.ListProjectRolesAsync(123));
        }
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public async Task ListPointsAndRolesAsync_RejectNonpositiveProjectBeforeHttp(int projectId)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/points", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/roles", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);

            await Assert.ThrowsAsync<ArgumentException>(() => api.ListPointsAsync(projectId));
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListProjectRolesAsync(projectId));
            Assert.Empty(handler.Requests);
        }
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public async Task ListPointsAndRolesPageAsync_RejectNonpositivePageBeforeHttp(int page)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/points", "[]")
            .AddJsonRoute(HttpMethod.Get, "/api/v1/roles", "[]");
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var api = NewApi(handler, auth);

            await Assert.ThrowsAsync<ArgumentException>(() => api.ListPointsPageAsync(123, page));
            await Assert.ThrowsAsync<ArgumentException>(() => api.ListProjectRolesPageAsync(123, page));
            Assert.Empty(handler.Requests);
        }
    }

    [Theory]
    [InlineData("{\"not\":\"an array\"}", "invalid project point list")]
    [InlineData("[{\"id\":21,\"project\":123,\"name\":\"Broken\",\"order\":0,\"value\":\"half\"}]", "project point value")]
    [InlineData("[{\"id\":21,\"project\":123,\"name\":\"Overflow\",\"order\":0,\"value\":1e999}]", "project point value")]
    [InlineData("[{\"id\":21,\"project\":123,\"name\":\"Underflow\",\"order\":0,\"value\":-1e999}]", "project point value")]
    [InlineData("[{\"id\":21,\"project\":999,\"name\":\"Wrong project\",\"order\":0,\"value\":null}]", "different project")]
    public async Task ListPointsAsync_RejectsMalformedOrWrongProjectData(string json, string expectedMessage)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/points", json);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).ListPointsAsync(123));
            Assert.Contains(expectedMessage, exception.Message, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public async Task ListProjectRolesAsync_RejectsMalformedOrWrongProjectData()
    {
        var malformed = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/roles", "[{\"id\":7,\"project\":123,\"name\":\"Developer\",\"computable\":\"yes\"}]");
        var (malformedHttp, malformedAuth) = TaigaTestClient.Create(malformed);
        using (malformedHttp)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(malformed, malformedAuth).ListProjectRolesAsync(123));
            Assert.Contains("project role computable", exception.Message);
        }

        var wrongProject = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/roles", "[{\"id\":7,\"project\":999,\"name\":\"Developer\",\"computable\":true}]");
        var (wrongProjectHttp, wrongProjectAuth) = TaigaTestClient.Create(wrongProject);
        using (wrongProjectHttp)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(wrongProject, wrongProjectAuth).ListProjectRolesAsync(123));
            Assert.Contains("different project", exception.Message);
        }
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "permission denied")]
    [InlineData(HttpStatusCode.NotFound, "resource not found")]
    public async Task ListProjectRolesAsync_ReportsSafeHttpFailures(HttpStatusCode statusCode, string category)
    {
        var handler = new FakeHttpMessageHandler()
            .AddJsonRoute(HttpMethod.Get, "/api/v1/roles", "{\"detail\":\"secret role data\"}", statusCode);
        var (http, auth) = TaigaTestClient.Create(handler);
        using (http)
        {
            var exception = await Assert.ThrowsAsync<TaigaRequestException>(() => NewApi(handler, auth).ListProjectRolesAsync(123));
            Assert.Contains(((int)statusCode).ToString(), exception.Message);
            Assert.Contains(category, exception.Message);
            Assert.DoesNotContain("secret role data", exception.Message);
        }
    }

    private static ProjectApi NewApi(FakeHttpMessageHandler handler, AuthClient auth)
        => new(new TaigaTransport(new TestHttpClientFactory(handler), auth));
}
