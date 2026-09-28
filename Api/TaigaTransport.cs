using System.Net;
using System.Text.Json;

namespace TaigaMCP.Api;

public sealed class TaigaRequestException : HttpRequestException
{
    public TaigaRequestException(string message, HttpStatusCode? status = null)
        : base(message, null, status) { }
}

public sealed class TaigaTransport(IHttpClientFactory clients, AuthClient auth)
{
    // Caller owns the request and returned document; transport owns every response.
    public async Task<JsonDocument> ReadAsync(HttpRequestMessage request, CancellationToken cancellationToken = default)
    {
        var write = request.Method != HttpMethod.Get;
        var applied = false;
        try
        {
            using var http = clients.CreateClient("taiga");
            using var response = await auth.SendAsync(http, request, cancellationToken);
            await EnsureSuccessAsync(response, cancellationToken);
            applied = write;
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            return await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        }
        catch (OperationCanceledException) { throw; }
        catch (TaigaRequestException) { throw; }
        catch (JsonException)
        {
            throw new TaigaRequestException(applied
                ? "Taiga write may already have applied; its response was invalid. Read the entity before retrying."
                : "Taiga returned invalid JSON.");
        }
        catch (HttpRequestException)
        {
            throw new TaigaRequestException(write
                ? "Taiga transport failure; the write may already have applied. Read the entity before retrying."
                : "Taiga transport failure.");
        }
    }

    internal static async Task EnsureSuccessAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode) return;
        // Bound bytes read, and never echo arbitrary upstream text (which can contain secrets).
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var bytes = new byte[4096];
        var count = 0;
        while (count < bytes.Length)
        {
            var read = await stream.ReadAsync(bytes.AsMemory(count), cancellationToken);
            if (read == 0) break;
            count += read;
        }
        var details = new List<string>();
        try
        {
            using var doc = JsonDocument.Parse(bytes.AsMemory(0, count));
            if (doc.RootElement.ValueKind == JsonValueKind.Object)
            {
                string[] fields = ["version", "subject", "project", "status", "type", "priority", "severity", "assigned_to", "tags", "description", "comment"];
                foreach (var field in fields)
                    if (doc.RootElement.TryGetProperty(field, out _)) details.Add($"{field}: rejected");
                if (doc.RootElement.TryGetProperty("detail", out var detail) &&
                    detail.ValueKind == JsonValueKind.String &&
                    detail.GetString()!.Contains("version", StringComparison.OrdinalIgnoreCase))
                    details.Add("version conflict");
            }
        }
        catch (JsonException) { }
        var category = response.StatusCode switch
        {
            HttpStatusCode.BadRequest => "validation failed",
            HttpStatusCode.Unauthorized => "authentication rejected",
            HttpStatusCode.Forbidden => "permission denied",
            HttpStatusCode.NotFound => "resource not found",
            HttpStatusCode.Conflict => "conflict",
            HttpStatusCode.TooManyRequests => "rate limited",
            _ => "upstream failure"
        };
        throw new TaigaRequestException($"Taiga HTTP {(int)response.StatusCode}: {category}" +
            (details.Count == 0 ? "." : $" ({string.Join("; ", details)})."), response.StatusCode);
    }
}
