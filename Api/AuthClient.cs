using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using TaigaMCP.Config;

namespace TaigaMCP.Api;

internal interface IReplayableHttpContent
{
    HttpContent CreateReplay();
}

public sealed class AuthClient(IOptions<TaigaOptions> options, ILogger<AuthClient> log) : IDisposable
{
    private sealed record TokenState(string Token, string? Refresh);
    private readonly SemaphoreSlim _gate = new(1, 1);
    private TokenState? _state;

    private async Task<TokenState> GetStateAsync(HttpClient http, TokenState? rejected, CancellationToken cancellationToken)
    {
        var state = Volatile.Read(ref _state);
        if (state is not null && !ReferenceEquals(state, rejected)) return state;
        await _gate.WaitAsync(cancellationToken);
        try
        {
            state = _state;
            if (state is not null && !ReferenceEquals(state, rejected)) return state;
            TokenState? replacement = null;
            if (state?.Refresh is { Length: > 0 } refresh)
                replacement = await AuthenticateAsync(http, "auth/refresh", new { refresh }, true, cancellationToken);
            replacement ??= await AuthenticateAsync(http, "auth", new
            {
                type = "normal",
                username = options.Value.Username,
                password = options.Value.Password
            }, false, cancellationToken);
            Volatile.Write(ref _state, replacement);
            log.LogDebug("Taiga authentication state replaced");
            return replacement!;
        }
        finally { _gate.Release(); }
    }

    private static async Task<TokenState?> AuthenticateAsync(HttpClient http, string path, object payload,
        bool refresh, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = JsonContent.Create(payload) };
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (refresh && !response.IsSuccessStatusCode) return null;
        await TaigaTransport.EnsureSuccessAsync(response, cancellationToken);
        try
        {
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
            if (doc.RootElement.ValueKind == JsonValueKind.Object && doc.RootElement.TryGetProperty("auth_token", out var token) && token.ValueKind == JsonValueKind.String &&
                !string.IsNullOrWhiteSpace(token.GetString()))
            {
                var nextRefresh = doc.RootElement.TryGetProperty("refresh", out var value) && value.ValueKind == JsonValueKind.String
                    ? value.GetString() : null;
                return new TokenState(token.GetString()!, nextRefresh);
            }
        }
        catch (JsonException) { }
        if (refresh) return null;
        throw new TaigaRequestException("Taiga authentication returned an invalid token response.");
    }

    // Caller owns original request and returned response. Only received 401s permit a replay.
    public async Task<HttpResponseMessage> SendAsync(HttpClient http, HttpRequestMessage request,
        CancellationToken cancellationToken = default)
    {
        var state = await GetStateAsync(http, null, cancellationToken);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", state.Token);
        var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (response.StatusCode != HttpStatusCode.Unauthorized) return response;
        response.Dispose();
        var replacement = await GetStateAsync(http, state, cancellationToken);
        using var retry = await CloneAsync(request, cancellationToken);
        retry.Headers.Authorization = new AuthenticationHeaderValue("Bearer", replacement.Token);
        return await http.SendAsync(retry, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
    }

    private static async Task<HttpRequestMessage> CloneAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var clone = new HttpRequestMessage(request.Method, request.RequestUri)
        {
            Version = request.Version,
            VersionPolicy = request.VersionPolicy
        };
        try
        {
            foreach (var header in request.Headers) clone.Headers.TryAddWithoutValidation(header.Key, header.Value);
            foreach (var option in request.Options) clone.Options.Set(new HttpRequestOptionsKey<object?>(option.Key), option.Value);
            if (request.Content is not null)
            {
                clone.Content = request.Content is IReplayableHttpContent replayable
                    ? replayable.CreateReplay()
                    : new ByteArrayContent(await request.Content.ReadAsByteArrayAsync(cancellationToken));
                foreach (var header in request.Content.Headers)
                    if (!clone.Content.Headers.Contains(header.Key))
                        clone.Content.Headers.TryAddWithoutValidation(header.Key, header.Value);
            }
            return clone;
        }
        catch { clone.Dispose(); throw; }
    }

    public void Dispose() => _gate.Dispose();
}
