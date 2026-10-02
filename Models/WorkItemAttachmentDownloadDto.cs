using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record WorkItemAttachmentDownloadDto
{
    [JsonPropertyName("destination")]
    public required string Destination { get; init; }

    [JsonPropertyName("bytes")]
    public long Bytes { get; init; }

    [JsonPropertyName("attachment")]
    public required WorkItemAttachmentDto Attachment { get; init; }
}
