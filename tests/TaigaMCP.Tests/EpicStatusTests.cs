using System.Text.Json;
using TaigaMCP.Models;
using TaigaMCP.Tools;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class EpicStatusTests
{
    [Fact]
    public void StatusContractPreservesLocalizedNamesAndClosureFlags()
    {
        var statuses = JsonSerializer.Deserialize<EpicStatusDto[]>(
            EpicStatusFixtures.LocalizedProjectStatuses)!;

        Assert.Collection(
            statuses,
            open =>
            {
                Assert.Equal(30, open.Id);
                Assert.Equal(123, open.Project);
                Assert.Equal("En revisión", open.Name);
                Assert.Equal("en-revision", open.Slug);
                Assert.Equal(0, open.Order);
                Assert.Equal("#336699", open.Color);
                Assert.False(open.IsClosed);
            },
            closed =>
            {
                Assert.Equal(31, closed.Id);
                Assert.Equal(123, closed.Project);
                Assert.Equal("Terminé", closed.Name);
                Assert.Equal("termine", closed.Slug);
                Assert.Null(closed.Order);
                Assert.Null(closed.Color);
                Assert.True(closed.IsClosed);
            });
    }

    [Fact]
    public void StatusResponseOmitsOnlyMissingOptionalValues()
    {
        var status = new EpicStatusDto
        {
            Id = 31,
            Name = "Terminé",
            Order = 0,
            IsClosed = true
        };

        using var json = JsonDocument.Parse(ToolResponseJson.Serialize(status));
        var root = json.RootElement;

        Assert.Equal(31, root.GetProperty("id").GetInt32());
        Assert.Equal("Terminé", root.GetProperty("name").GetString());
        Assert.Equal(0, root.GetProperty("order").GetInt32());
        Assert.True(root.GetProperty("is_closed").GetBoolean());
        Assert.False(root.TryGetProperty("project", out _));
        Assert.False(root.TryGetProperty("color", out _));
    }
}
