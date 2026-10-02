using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record WorkItemAttachmentDeleteDto
{
    [JsonPropertyName("kind")]
    public required string Kind { get; init; }

    [JsonPropertyName("attachment_id")]
    public int AttachmentId { get; init; }

    [JsonPropertyName("deleted")]
    public bool Deleted { get; init; }
}
