using System.Net;
using System.Security;
using System.Text.Json;

namespace TaigaMCP.Api;

public sealed class TaigaRequestException : HttpRequestException
{
    public TaigaRequestException(
        string message,
        HttpStatusCode? status = null,
        bool isDuplicateRelationship = false)
        : base(message, null, status)
    {
        IsDuplicateRelationship = isDuplicateRelationship;
    }

    internal bool IsDuplicateRelationship { get; }
}

internal sealed class TaigaReadResult : IDisposable
{
    public TaigaReadResult(
        JsonDocument document,
        IReadOnlyDictionary<string, string[]> headers,
        Uri requestUri)
    {
        Document = document;
        Headers = headers;
        RequestUri = requestUri;
    }

    public JsonDocument Document { get; }
    public IReadOnlyDictionary<string, string[]> Headers { get; }
    public Uri RequestUri { get; }

    public void Dispose() => Document.Dispose();
}

public sealed class TaigaTransport(IHttpClientFactory clients, AuthClient auth)
{
    // Caller owns the request and returned document; transport owns every response.
    public async Task<JsonDocument> ReadAsync(HttpRequestMessage request, CancellationToken cancellationToken = default)
    {
        var result = await ReadWithHeadersAsync(request, cancellationToken);
        return result.Document;
    }

    public async Task SendNoContentAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken = default)
    {
        var applied = false;
        try
        {
            using var http = clients.CreateClient("taiga");
            using var response = await auth.SendAsync(http, request, cancellationToken);
            await EnsureSuccessAsync(response, cancellationToken);
            applied = true;
            if (response.StatusCode != HttpStatusCode.NoContent)
                throw new TaigaRequestException(
                    $"Taiga returned unexpected HTTP {(int)response.StatusCode} for a no-content write; the write may already have applied. Read the relationship before retrying.",
                    response.StatusCode);
        }
        catch (OperationCanceledException exception) when (IsHttpTimeout(exception, cancellationToken))
        {
            throw new TaigaRequestException(
                "Taiga request timed out; the write may already have applied. Read the relationship before retrying.");
        }
        catch (OperationCanceledException) when (applied)
        {
            throw new OperationCanceledException(
                "Taiga write may already have applied; response handling was cancelled. Read the relationship before retrying.",
                cancellationToken);
        }
        catch (OperationCanceledException) { throw; }
        catch (TaigaRequestException) { throw; }
        catch (Exception ex) when (ex is HttpRequestException or IOException)
        {
            throw new TaigaRequestException(
                "Taiga transport failure; the write may already have applied. Read the relationship before retrying.");
        }
    }

    internal async Task<TaigaDownloadResult> DownloadAsync(
        AttachmentDownloadPlan plan,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(plan);
        InputValidation.Positive(plan.MaximumBytes, nameof(plan.MaximumBytes));

        var temporaryPath = CreateTemporaryPath(plan.DestinationPath);
        var completed = false;
        try
        {
            var currentUri = plan.SourceUri;
            var authenticationOrigin = plan.AuthenticationOrigin;
            for (var redirect = 0; ; redirect++)
            {
                using var http = clients.CreateClient("taiga");
                using var request = new HttpRequestMessage(HttpMethod.Get, currentUri);
                using var response = await SendDownloadRequestAsync(
                    http,
                    request,
                    authenticationOrigin is not null && IsSameOrigin(currentUri, authenticationOrigin),
                    cancellationToken);

                if (IsRedirect(response.StatusCode))
                {
                    if (redirect >= 5 || response.Headers.Location is null)
                        throw new TaigaRequestException("Taiga attachment returned too many or invalid redirects.");

                    currentUri = ResolveRedirect(currentUri, response.Headers.Location);
                    continue;
                }

                await EnsureSuccessAsync(response, cancellationToken);
                var contentLength = response.Content.Headers.ContentLength;
                if (contentLength.HasValue && contentLength.Value > plan.MaximumBytes)
                    throw new TaigaRequestException($"attachment exceeds the configured maximum size of {plan.MaximumBytes} bytes.");
                if (!plan.ExpectedBytes.HasValue)
                    throw new TaigaRequestException("Taiga attachment metadata did not provide a declared size.");

                var bytesWritten = await WriteDownloadAsync(response, temporaryPath, plan.MaximumBytes, cancellationToken);
                if (plan.ExpectedBytes.HasValue && bytesWritten != plan.ExpectedBytes.Value)
                    throw new TaigaRequestException("Taiga attachment response did not match its declared attachment size.");

                if (contentLength.HasValue && bytesWritten != contentLength.Value)
                    throw new TaigaRequestException("Taiga attachment response ended before its declared content length.");

                try
                {
                    File.Move(temporaryPath, plan.DestinationPath);
                    completed = true;
                    return new TaigaDownloadResult(plan.DestinationPath, bytesWritten);
                }
                catch (IOException)
                {
                    throw new TaigaRequestException("attachment download could not be placed at the requested destination; an existing file was not overwritten.");
                }
            }
        }
        catch (OperationCanceledException) { throw; }
        catch (TaigaRequestException) { throw; }
        catch (Exception ex) when (ex is HttpRequestException or IOException or UnauthorizedAccessException or SecurityException)
        {
            throw new TaigaRequestException("Taiga attachment download failed while accessing the network or local destination.");
        }
        finally
        {
            if (!completed)
                TryDelete(temporaryPath);
        }
    }

    internal async Task<TaigaReadResult> ReadWithHeadersAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken = default)
    {
        var write = request.Method != HttpMethod.Get;
        var applied = false;
        try
        {
            using var http = clients.CreateClient("taiga");
            var requestUri = request.RequestUri is { IsAbsoluteUri: true } absolute
                ? absolute
                : new Uri(http.BaseAddress ?? new Uri("http://localhost/"), request.RequestUri ?? new Uri("", UriKind.Relative));
            using var response = await auth.SendAsync(http, request, cancellationToken);
            await EnsureSuccessAsync(response, cancellationToken);
            applied = write;
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
            var headers = response.Headers
                .Concat(response.Content.Headers)
                .GroupBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(
                    group => group.Key,
                    group => group.SelectMany(pair => pair.Value).ToArray(),
                    StringComparer.OrdinalIgnoreCase);
            return new TaigaReadResult(document, headers, requestUri);
        }
        catch (OperationCanceledException exception) when (IsHttpTimeout(exception, cancellationToken))
        {
            throw new TaigaRequestException(
                "Taiga request timed out; the write may already have applied. Read the entity before retrying.");
        }
        catch (OperationCanceledException) when (write && applied)
        {
            throw new OperationCanceledException("Taiga write may already have applied; response reading was cancelled. Read the entity before retrying.", cancellationToken);
        }
        catch (OperationCanceledException) { throw; }
        catch (TaigaRequestException) { throw; }
        catch (JsonException)
        {
            throw new TaigaRequestException(applied
                ? "Taiga write may already have applied; its response was invalid. Read the entity before retrying."
                : "Taiga returned invalid JSON.");
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException)
        {
            throw new TaigaRequestException(write
                ? "Taiga transport failure; the write may already have applied. Read the entity before retrying."
                : "Taiga transport failure.");
        }
    }

    private static bool IsHttpTimeout(OperationCanceledException exception, CancellationToken cancellationToken)
        => !cancellationToken.IsCancellationRequested &&
           exception is TaskCanceledException &&
           exception.InnerException is TimeoutException;

    private async Task<HttpResponseMessage> SendDownloadRequestAsync(
        HttpClient http,
        HttpRequestMessage request,
        bool useAuthentication,
        CancellationToken cancellationToken)
        => useAuthentication
            ? await auth.SendAsync(http, request, cancellationToken)
            : await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);

    private static async Task<long> WriteDownloadAsync(
        HttpResponseMessage response,
        string temporaryPath,
        long maximumBytes,
        CancellationToken cancellationToken)
    {
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var target = new FileStream(
            temporaryPath,
            FileMode.Open,
            FileAccess.Write,
            FileShare.None,
            bufferSize: 64 * 1024,
            options: FileOptions.SequentialScan);

        var buffer = new byte[64 * 1024];
        long total = 0;
        while (true)
        {
            var read = await source.ReadAsync(buffer.AsMemory(), cancellationToken);
            if (read == 0) break;
            total = checked(total + read);
            if (total > maximumBytes)
                throw new TaigaRequestException($"attachment exceeds the configured maximum size of {maximumBytes} bytes.");
            await target.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
        }

        await target.FlushAsync(cancellationToken);
        return total;
    }

    private static string CreateTemporaryPath(string destinationPath)
    {
        var directory = Path.GetDirectoryName(destinationPath);
        var fileName = Path.GetFileName(destinationPath);
        if (string.IsNullOrWhiteSpace(directory) || string.IsNullOrWhiteSpace(fileName))
            throw new ArgumentException("destination must identify a file in an existing directory.", nameof(destinationPath));

        for (var attempt = 0; attempt < 10; attempt++)
        {
            var candidate = Path.Combine(directory, $".{fileName}.{Guid.NewGuid():N}.download");
            try
            {
                using var reservation = new FileStream(candidate, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                return candidate;
            }
            catch (IOException) when (attempt < 9) { }
        }

        throw new TaigaRequestException("attachment download could not create a temporary destination file.");
    }

    private static Uri ResolveRedirect(Uri currentUri, Uri location)
    {
        var nextUri = location.IsAbsoluteUri ? location : new Uri(currentUri, location);
        if (!IsHttpScheme(nextUri) || string.IsNullOrEmpty(nextUri.Host) || !string.IsNullOrEmpty(nextUri.UserInfo))
            throw new TaigaRequestException("Taiga attachment returned an unsupported redirect URL.");

        return nextUri;
    }

    private static bool IsRedirect(HttpStatusCode statusCode)
        => statusCode is HttpStatusCode.Moved or
            HttpStatusCode.Redirect or
            HttpStatusCode.SeeOther or
            HttpStatusCode.TemporaryRedirect or
            HttpStatusCode.PermanentRedirect;

    private static bool IsSameOrigin(Uri source, Uri origin)
        => string.Equals(source.Scheme, origin.Scheme, StringComparison.OrdinalIgnoreCase) &&
           string.Equals(source.Host, origin.Host, StringComparison.OrdinalIgnoreCase) &&
           source.Port == origin.Port;

    private static bool IsHttpScheme(Uri uri)
        => string.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) ||
           string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase);

    private static void TryDelete(string path)
    {
        try { File.Delete(path); }
        catch (Exception) { }
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
        var isDuplicateRelationship = false;
        try
        {
            using var doc = JsonDocument.Parse(bytes.AsMemory(0, count));
            if (doc.RootElement.ValueKind == JsonValueKind.Object)
            {
                string[] fields = ["version", "subject", "project", "status", "type", "priority", "severity", "assigned_to", "tags", "description", "milestone", "comment", "color", "epic", "user_story", "order"];
                foreach (var field in fields)
                    if (doc.RootElement.TryGetProperty(field, out _)) details.Add($"{field}: rejected");
                if (doc.RootElement.TryGetProperty("detail", out var detail) &&
                    detail.ValueKind == JsonValueKind.String &&
                    detail.GetString()!.Contains("version", StringComparison.OrdinalIgnoreCase))
                    details.Add("version conflict");

                isDuplicateRelationship = IsDuplicateRelationshipError(doc.RootElement);
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
            (details.Count == 0 ? "." : $" ({string.Join("; ", details)})."), response.StatusCode, isDuplicateRelationship);
    }

    private static bool IsDuplicateRelationshipError(JsonElement root)
    {
        foreach (var property in root.EnumerateObject())
        {
            if (property.Name is not ("non_field_errors" or "__all__" or "epic" or "user_story"))
                continue;

            if (ContainsDuplicateMarker(property.Value))
                return true;
        }

        return false;
    }

    private static bool ContainsDuplicateMarker(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.String)
            return HasDuplicateMarker(value.GetString());

        if (value.ValueKind != JsonValueKind.Array)
            return false;

        foreach (var item in value.EnumerateArray())
            if (item.ValueKind == JsonValueKind.String && HasDuplicateMarker(item.GetString()))
                return true;

        return false;
    }

    private static bool HasDuplicateMarker(string? value)
        => value is not null &&
           (value.Contains("unique", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("already exists", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("already linked", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("already related", StringComparison.OrdinalIgnoreCase));
}

internal sealed record TaigaDownloadResult(string DestinationPath, long BytesWritten);
