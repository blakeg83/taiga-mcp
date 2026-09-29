using System.Text.Json;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class WorkItemCommentTests
{
    [Fact]
    public void WorkItemKind_IsClosedToTheFourWireValues()
    {
        Assert.Equal(
            new[] { "issue", "user_story", "task", "epic" },
            Enum.GetNames<WorkItemKind>());
    }

    [Fact]
    public void WorkItemCommentReceipt_UsesTheStableSubmissionShape()
    {
        var receipt = new WorkItemCommentReceipt
        {
            Kind = WorkItemKind.user_story.ToString(),
            Id = 102,
            Version = 8,
            CommentSubmitted = true
        };

        using var document = JsonDocument.Parse(JsonSerializer.Serialize(receipt));
        var properties = document.RootElement.EnumerateObject()
            .Select(property => property.Name)
            .OrderBy(name => name, StringComparer.Ordinal);

        Assert.Equal(new[] { "comment_submitted", "id", "kind", "version" }, properties);
        Assert.Equal("user_story", document.RootElement.GetProperty("kind").GetString());
        Assert.Equal(102, document.RootElement.GetProperty("id").GetInt32());
        Assert.Equal(8, document.RootElement.GetProperty("version").GetInt32());
        Assert.True(document.RootElement.GetProperty("comment_submitted").GetBoolean());
    }
}
