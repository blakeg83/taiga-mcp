using System.Text.Json.Serialization;

namespace TaigaMCP.Models;

public sealed record WorkItemAttachmentDto
{
    [JsonPropertyName("id")]
    public int Id { get; init; }

    [JsonPropertyName("project")]
    public int Project { get; init; }

    [JsonPropertyName("object_id")]
    public int ObjectId { get; init; }

    [JsonPropertyName("owner")]
    public int? Owner { get; init; }

    [JsonPropertyName("name")]
    public string? Name { get; init; }

    [JsonPropertyName("description")]
    public string? Description { get; init; }

    [JsonPropertyName("order")]
    public int? Order { get; init; }

    [JsonPropertyName("size")]
    public int? Size { get; init; }

    [JsonPropertyName("attached_file")]
    public string? AttachedFile { get; init; }

    [JsonPropertyName("url")]
    public string? Url { get; init; }

    [JsonPropertyName("preview_url")]
    public string? PreviewUrl { get; init; }

    [JsonPropertyName("thumbnail_card_url")]
    public string? ThumbnailCardUrl { get; init; }

    [JsonPropertyName("sha1")]
    public string? Sha1 { get; init; }

    [JsonPropertyName("is_deprecated")]
    public bool? IsDeprecated { get; init; }

    [JsonPropertyName("from_comment")]
    public bool? FromComment { get; init; }

    [JsonPropertyName("created_date")]
    public string? CreatedDate { get; init; }

    [JsonPropertyName("modified_date")]
    public string? ModifiedDate { get; init; }
}
