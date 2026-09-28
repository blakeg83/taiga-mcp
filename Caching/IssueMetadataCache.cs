using System.Collections.Frozen;
using Microsoft.Extensions.Options;
using TaigaMCP.Api;
using TaigaMCP.Config;

namespace TaigaMCP.Caching;

public sealed class IssueMetadataCache
{
    private sealed class Entry
    {
        public readonly SemaphoreSlim Gate = new(1, 1);
        public IReadOnlyDictionary<int, string>? Value;
        public DateTimeOffset Expires;
        public int Users;
    }

    private readonly object _sync = new();
    private readonly Dictionary<(string Kind, int Project), Entry> _entries = new();
    private readonly TaigaTransport _transport;
    private readonly TimeProvider _clock;
    private readonly TimeSpan _ttl;
    private const int MaxIdleEntries = 256;

    public IssueMetadataCache(TaigaTransport transport, IOptions<TaigaOptions>? options = null, TimeProvider? clock = null)
    {
        _transport = transport;
        _clock = clock ?? TimeProvider.System;
        var seconds = options?.Value.MetadataTtlSeconds ?? 300;
        if (seconds <= 0) throw new ArgumentOutOfRangeException(nameof(options), "Metadata TTL must be positive.");
        _ttl = TimeSpan.FromSeconds(seconds);
    }

    private async Task<IReadOnlyDictionary<int, string>> GetMapAsync(string kind, int projectId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Entry entry;
        lock (_sync)
        {
            EvictIdle();
            var key = (kind, projectId);
            if (!_entries.TryGetValue(key, out entry!)) _entries[key] = entry = new Entry();
            entry.Users++;
        }
        var entered = false;
        try
        {
            await entry.Gate.WaitAsync(cancellationToken);
            entered = true;
            if (entry.Value is not null && entry.Expires > _clock.GetUtcNow()) return entry.Value;
            using var request = new HttpRequestMessage(HttpMethod.Get, $"{kind}?project={projectId}");
            using var doc = await _transport.ReadAsync(request, cancellationToken);
            var map = new Dictionary<int, string>();
            foreach (var item in doc.RootElement.EnumerateArray())
                if (item.TryGetProperty("id", out var id) && id.TryGetInt32(out var number) &&
                    item.TryGetProperty("name", out var name) && name.GetString() is { } label)
                    map[number] = label;
            entry.Value = map.ToFrozenDictionary();
            entry.Expires = _clock.GetUtcNow() + _ttl;
            return entry.Value;
        }
        finally
        {
            if (entered) entry.Gate.Release();
            lock (_sync)
            {
                entry.Users--;
                EvictIdle();
            }
        }
    }

    // In-flight entries are pinned, including waiters; idle entries are bounded even
    // if the process stops receiving traffic. Expired entries are swept on access.
    private void EvictIdle()
    {
        var idle = _entries.Where(pair => pair.Value.Users == 0).OrderBy(pair => pair.Value.Expires).ToArray();
        var surplus = Math.Max(0, idle.Length - MaxIdleEntries);
        foreach (var pair in idle)
        {
            if (pair.Value.Value is not null && pair.Value.Expires > _clock.GetUtcNow() && surplus <= 0) continue;
            _entries.Remove(pair.Key);
            pair.Value.Gate.Dispose();
            surplus--;
        }
    }

    public Task<IReadOnlyDictionary<int, string>> GetStatusesAsync(int projectId, CancellationToken cancellationToken = default)
        => GetMapAsync("issue-statuses", projectId, cancellationToken);
    public Task<IReadOnlyDictionary<int, string>> GetSeveritiesAsync(int projectId, CancellationToken cancellationToken = default)
        => GetMapAsync("severities", projectId, cancellationToken);
    public Task<IReadOnlyDictionary<int, string>> GetTypesAsync(int projectId, CancellationToken cancellationToken = default)
        => GetMapAsync("issue-types", projectId, cancellationToken);
    public Task<IReadOnlyDictionary<int, string>> GetPrioritiesAsync(int projectId, CancellationToken cancellationToken = default)
        => GetMapAsync("priorities", projectId, cancellationToken);
}
