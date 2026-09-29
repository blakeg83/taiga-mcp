using System.Text.Json;
using System.Text.Json.Serialization;
using TaigaMCP.Models;
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
