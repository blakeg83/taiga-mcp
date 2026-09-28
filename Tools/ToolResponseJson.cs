using System.Text.Json;
using System.Text.Json.Serialization;

namespace TaigaMCP.Tools;

internal static class ToolResponseJson
{
    private static readonly JsonSerializerOptions Options = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private static readonly JsonSerializerOptions PageOptions = new();

    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Options);

    public static string SerializePage<T>(
        IReadOnlyList<T> items,
        int page,
        int? total,
        int? nextPage,
        bool? hasMore)
    {
        var envelope = new
        {
            items = JsonSerializer.SerializeToElement(items, Options),
            page,
            total,
            next_page = nextPage,
            has_more = hasMore
        };
        return JsonSerializer.Serialize(envelope, PageOptions);
    }
}
