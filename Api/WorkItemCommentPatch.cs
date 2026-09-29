using System.Text;
using System.Text.Json;

namespace TaigaMCP.Api;

internal static class WorkItemCommentPatch
{
    public static async Task<int> SendAsync(
        TaigaTransport transport,
        string route,
        string resourceName,
        int version,
        string text,
        CancellationToken cancellationToken)
    {
        var payload = JsonSerializer.Serialize(new Dictionary<string, object?>
        {
            ["comment"] = text,
            ["version"] = version
        });
        using var request = new HttpRequestMessage(HttpMethod.Patch, route)
        {
            Content = new StringContent(payload, Encoding.UTF8, "application/json")
        };
        request.Headers.Accept.ParseAdd("application/json");

        using var document = await transport.ReadAsync(request, cancellationToken);
        try
        {
            return ReadReturnedVersion(document.RootElement, resourceName);
        }
        catch (OperationCanceledException)
        {
            throw new OperationCanceledException(
                $"Taiga {resourceName} comment write may already have applied; response parsing was cancelled. Read the entity before retrying.",
                cancellationToken);
        }
        catch (Exception)
        {
            throw new TaigaRequestException(
                $"Taiga {resourceName} comment write may already have applied; the returned version was invalid. Read the entity before retrying.");
        }
    }

    private static int ReadReturnedVersion(JsonElement element, string resourceName)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty("version", out var version) ||
            version.ValueKind != JsonValueKind.Number ||
            !version.TryGetInt32(out var number) ||
            number < 0)
            throw new TaigaRequestException($"Taiga returned invalid {resourceName} version data.");

        return number;
    }
}
