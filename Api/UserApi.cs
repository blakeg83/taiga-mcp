using System.Text.Json;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Authenticated-user operations.</summary>
public sealed class UserApi
{
    private readonly TaigaTransport _transport;

    public UserApi(TaigaTransport transport)
    {
        _transport = transport;
    }

    public async Task<UserIdentityDto> GetCurrentUserAsync(CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "users/me");
        using var document = await _transport.ReadAsync(request, cancellationToken);
        return MapIdentity(document.RootElement);
    }

    private static UserIdentityDto MapIdentity(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty("id", out var idElement) ||
            idElement.ValueKind != JsonValueKind.Number ||
            !idElement.TryGetInt32(out var id) ||
            id <= 0)
        {
            throw new TaigaRequestException("Taiga returned an invalid current-user identity.");
        }

        return new UserIdentityDto
        {
            Id = id,
            Username = OptionalString(element, "username"),
            FullName = OptionalString(element, "full_name"),
            IsActive = OptionalBoolean(element, "is_active")
        };
    }

    private static string? OptionalString(JsonElement element, string propertyName)
        => element.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static bool? OptionalBoolean(JsonElement element, string propertyName)
        => element.TryGetProperty(propertyName, out var value) &&
           (value.ValueKind is JsonValueKind.True or JsonValueKind.False)
            ? value.GetBoolean()
            : null;
}
