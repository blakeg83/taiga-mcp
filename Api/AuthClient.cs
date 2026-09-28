using TaigaMCP.Config;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace TaigaMCP.Api;

public sealed class AuthClient
{
    private readonly TaigaOptions _cfg;
    private readonly ILogger<AuthClient> _log;
    private string? _token;
    private string? _refresh;

    public AuthClient(IOptions<TaigaOptions> opts, ILogger<AuthClient> log)
    {
        _cfg = opts.Value;
        _log = log;
    }

    public async Task EnsureAuthAsync(HttpClient http)
    {
        if (!string.IsNullOrEmpty(_token))
        {
            // Token present; per-request headers are set in SendAsync.
            return;
        }

        // Ensure auth endpoints are called without any Authorization header.
        http.DefaultRequestHeaders.Authorization = null;
        _log.LogDebug("Auth: logging in via /auth");
        var body = JsonSerializer.Serialize(new { type = "normal", username = _cfg.Username, password = _cfg.Password });
        using var res = await http.PostAsync("auth", new StringContent(body, Encoding.UTF8, "application/json"));
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        _token = doc.RootElement.GetProperty("auth_token").GetString()
                 ?? throw new InvalidOperationException("Taiga auth_token missing");
        _refresh = doc.RootElement.TryGetProperty("refresh", out var r) ? r.GetString() : null;
        _log.LogInformation("Auth: login succeeded");
    }

    public async Task<HttpResponseMessage> SendAsync(HttpClient http, HttpRequestMessage req)
    {
        await EnsureAuthAsync(http);

        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
        var res = await http.SendAsync(req);
        if (res.StatusCode != HttpStatusCode.Unauthorized) return res;

        // token expired -> try refresh then one retry
        _log.LogDebug("Auth: 401 received; attempting refresh via /auth/refresh");
        res.Dispose();
        if (await TryRefreshAsync(http))
        {
            var retry = await CloneAsync(req);
            retry.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
            _log.LogDebug("Auth: refresh succeeded; retrying original request once");
            return await http.SendAsync(retry);
        }

        // fallback: full re-login then retry
        _token = null;
        _log.LogDebug("Auth: refresh failed; attempting full re-login via /auth");
        await EnsureAuthAsync(http);
        var retry2 = await CloneAsync(req);
        retry2.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
        _log.LogDebug("Auth: re-login succeeded; retrying original request once");
        return await http.SendAsync(retry2);
    }

    private async Task<bool> TryRefreshAsync(HttpClient http)
    {
        if (string.IsNullOrEmpty(_refresh)) return false;

        // Ensure refresh is called without any Authorization header.
        http.DefaultRequestHeaders.Authorization = null;
        _log.LogDebug("Auth: calling /auth/refresh");
        var payload = JsonSerializer.Serialize(new { refresh = _refresh });
        using var res = await http.PostAsync("auth/refresh", new StringContent(payload, Encoding.UTF8, "application/json"));
        if (!res.IsSuccessStatusCode)
        {
            _log.LogDebug("Auth: /auth/refresh failed with status {Status}", (int)res.StatusCode);
            return false;
        }

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        _token = doc.RootElement.GetProperty("auth_token").GetString();
        if (doc.RootElement.TryGetProperty("refresh", out var r)) _refresh = r.GetString();
        var ok = !string.IsNullOrEmpty(_token);
        if (ok) _log.LogInformation("Auth: token refresh succeeded");
        else _log.LogDebug("Auth: refresh response missing auth_token");
        return ok;
    }

    private static async Task<HttpRequestMessage> CloneAsync(HttpRequestMessage req)
    {
        var clone = new HttpRequestMessage(req.Method, req.RequestUri);
        foreach (var h in req.Headers) clone.Headers.TryAddWithoutValidation(h.Key, h.Value);
        if (req.Content is not null)
        {
            var bytes = await req.Content.ReadAsByteArrayAsync();
            clone.Content = new ByteArrayContent(bytes);
            foreach (var h in req.Content.Headers) clone.Content.Headers.TryAddWithoutValidation(h.Key, h.Value);
        }
        return clone;
    }
}
