using System.Text.Json;
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
}
