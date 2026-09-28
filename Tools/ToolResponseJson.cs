using System.Text.Json;
using System.Text.Json.Serialization;

namespace TaigaMCP.Tools;

internal static class ToolResponseJson
{
    private static readonly JsonSerializerOptions Options = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Options);
}
