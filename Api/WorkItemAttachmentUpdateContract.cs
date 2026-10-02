using System.Text.Json;

namespace TaigaMCP.Api;

internal static class WorkItemAttachmentUpdateContract
{
    public static Dictionary<string, object?> Parse(JsonElement fields)
    {
        if (fields.ValueKind != JsonValueKind.Object)
            throw new ArgumentException("fields must be a JSON object.", nameof(fields));

        var payload = new Dictionary<string, object?>(StringComparer.Ordinal);
        foreach (var property in fields.EnumerateObject())
        {
            if (payload.ContainsKey(property.Name))
                throw new ArgumentException($"fields contains duplicate field '{property.Name}'.", nameof(fields));

            switch (property.Name)
            {
                case "description":
                    if (property.Value.ValueKind != JsonValueKind.String)
                        throw new ArgumentException("fields.description must be a string, including an empty string to clear it.", nameof(fields));

                    payload[property.Name] = property.Value.GetString();
                    break;

                case "order":
                    if (property.Value.ValueKind != JsonValueKind.Number ||
                        !property.Value.TryGetInt32(out var order))
                        throw new ArgumentException("fields.order must be a 32-bit integer.", nameof(fields));

                    payload[property.Name] = order;
                    break;

                case "is_deprecated":
                    if (property.Value.ValueKind is not JsonValueKind.True and not JsonValueKind.False)
                        throw new ArgumentException("fields.is_deprecated must be a boolean.", nameof(fields));

                    payload[property.Name] = property.Value.GetBoolean();
                    break;

                default:
                    throw new ArgumentException($"fields contains unsupported field '{property.Name}'.", nameof(fields));
            }
        }

        if (payload.Count == 0)
            throw new ArgumentException("fields must contain at least one editable attachment field.", nameof(fields));

        return payload;
    }
}
