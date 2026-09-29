using System.Text.Json;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class EpicUpdateContractTests
{
    [Theory]
    [InlineData("status-only", false)]
    [InlineData("unassignment", true)]
    [InlineData("empty-description-and-tags", false)]
    [InlineData("color-change", false)]
    [InlineData("comment-only", false)]
    public void EpicUpdateDto_UsesPresenceAwarePatchPayload(string fixtureName, bool clearAssignedTo)
    {
        var update = fixtureName switch
        {
            "status-only" => new EpicUpdateDto { Status = 7, Version = 4 },
            "unassignment" => new EpicUpdateDto { Version = 4 },
            "empty-description-and-tags" => new EpicUpdateDto { Description = "", Tags = [], Version = 4 },
            "color-change" => new EpicUpdateDto { Color = "#336699", Version = 4 },
            "comment-only" => new EpicUpdateDto { Comment = "Delivery complete.", Version = 4 },
            _ => throw new InvalidOperationException($"Unknown fixture '{fixtureName}'.")
        };

        var actual = JsonSerializer.SerializeToElement(update.ToPatchPayload(clearAssignedTo));
        var expected = JsonSerializer.Deserialize<JsonElement>(EpicUpdateFixtures.ExpectedRequest(fixtureName));

        Assert.True(JsonElement.DeepEquals(expected, actual));
    }
}

internal static class EpicUpdateFixtures
{
    public static string ExpectedRequest(string name)
        => name switch
        {
            "status-only" => StatusOnlyRequest,
            "unassignment" => UnassignmentRequest,
            "empty-description-and-tags" => EmptyDescriptionAndTagsRequest,
            "color-change" => ColorChangeRequest,
            "comment-only" => CommentOnlyRequest,
            _ => throw new ArgumentException($"Unknown fixture '{name}'.", nameof(name))
        };

    private const string StatusOnlyRequest = """
        {"status":7,"version":4}
        """;

    private const string UnassignmentRequest = """
        {"assigned_to":null,"version":4}
        """;

    private const string EmptyDescriptionAndTagsRequest = """
        {"description":"","tags":[],"version":4}
        """;

    private const string ColorChangeRequest = """
        {"color":"#336699","version":4}
        """;

    private const string CommentOnlyRequest = """
        {"comment":"Delivery complete.","version":4}
        """;
}
