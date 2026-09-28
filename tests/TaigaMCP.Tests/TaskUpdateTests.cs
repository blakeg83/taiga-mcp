using System.Text.Json;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class TaskUpdateTests
{
    [Fact]
    public void TaskUpdatePayload_OmitsUnselectedFieldsAndPreservesExplicitEmptyValues()
    {
        var update = new TaskUpdateDto
        {
            Version = 2,
            Description = string.Empty,
            Tags = [],
            IsBlocked = false,
            BlockedNote = string.Empty,
            Comment = "Dependency resolved."
        };

        using var document = JsonDocument.Parse(JsonSerializer.Serialize(update.ToPatchPayload(false)));
        var body = document.RootElement;

        Assert.Equal(
            new[] { "blocked_note", "comment", "description", "is_blocked", "tags", "version" },
            body.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal));
        Assert.Equal(string.Empty, body.GetProperty("description").GetString());
        Assert.Empty(body.GetProperty("tags").EnumerateArray());
        Assert.False(body.GetProperty("is_blocked").GetBoolean());
        Assert.Equal(string.Empty, body.GetProperty("blocked_note").GetString());
        Assert.Equal(2, body.GetProperty("version").GetInt32());
        Assert.False(body.TryGetProperty("assigned_to", out _));
        Assert.False(body.TryGetProperty("subject", out _));
        Assert.False(body.TryGetProperty("status", out _));
    }

    [Fact]
    public void TaskUpdatePayload_UsesExplicitNullOnlyForAssignmentClear()
    {
        var update = new TaskUpdateDto
        {
            Version = 3,
            AssignedTo = null,
            IsBlocked = true
        };

        using var document = JsonDocument.Parse(JsonSerializer.Serialize(update.ToPatchPayload(true)));
        var body = document.RootElement;

        Assert.Equal(JsonValueKind.Null, body.GetProperty("assigned_to").ValueKind);
        Assert.True(body.GetProperty("is_blocked").GetBoolean());
        Assert.Equal(3, body.GetProperty("version").GetInt32());
        Assert.False(body.TryGetProperty("blocked_note", out _));
    }
}
