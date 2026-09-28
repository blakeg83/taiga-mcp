using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO.Pipelines;
using System.Text;
using System.Text.Json;
using ModelContextProtocol.Protocol;

namespace TaigaMCP.Tests;

public sealed class StrictMcpProcess : IAsyncDisposable
{
    private readonly Process _process;
    private readonly Pipe _stdoutPipe;
    private readonly Stream _clientOutput;
    private readonly StreamClientTransport _transport;
    private Task _stdoutPump;
    private Task _stderrPump;
    private int _disposed;

    private StrictMcpProcess(
        Process process,
        Pipe stdoutPipe,
        Stream clientOutput,
        StreamClientTransport transport,
        Task stdoutPump,
        Task stderrPump)
    {
        _process = process;
        _stdoutPipe = stdoutPipe;
        _clientOutput = clientOutput;
        _transport = transport;
        _stdoutPump = stdoutPump;
        _stderrPump = stderrPump;
    }

    public StreamClientTransport Transport => _transport;

    public ConcurrentQueue<string> RawStdoutLines { get; } = [];

    public ConcurrentQueue<string> StderrLines { get; } = [];

    public Exception? ValidationFailure { get; private set; }

    public Task ValidationCompleted => _stdoutPump;

    public static StrictMcpProcess Start(
        string command,
        IEnumerable<string> arguments,
        IReadOnlyDictionary<string, string> environment,
        string? workingDirectory = null)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = command,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = workingDirectory ?? Environment.CurrentDirectory
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        foreach (var pair in environment)
        {
            startInfo.Environment[pair.Key] = pair.Value;
        }

        var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        if (!process.Start())
        {
            process.Dispose();
            throw new InvalidOperationException($"Could not start MCP process '{command}'.");
        }

        var stdoutPipe = new Pipe();
        var clientOutput = stdoutPipe.Reader.AsStream(leaveOpen: true);
        var transport = new StreamClientTransport(process.StandardInput.BaseStream, clientOutput);
        var strictProcess = new StrictMcpProcess(
            process,
            stdoutPipe,
            clientOutput,
            transport,
            Task.CompletedTask,
            Task.CompletedTask);
        strictProcess._stdoutPump = strictProcess.PumpStdoutAsync();
        strictProcess._stderrPump = strictProcess.PumpStderrAsync();
        return strictProcess;
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
        {
            return;
        }

        try
        {
            _process.StandardInput.Close();
        }
        catch (ObjectDisposedException)
        {
        }

        try
        {
            await _process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(2));
        }
        catch (TimeoutException)
        {
            try
            {
                _process.Kill(entireProcessTree: true);
                await _process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(2));
            }
            catch (InvalidOperationException)
            {
            }
            catch (TimeoutException)
            {
            }
        }

        try
        {
            await _stdoutPump.WaitAsync(TimeSpan.FromSeconds(2));
        }
        catch (TimeoutException)
        {
        }

        try
        {
            await _stderrPump.WaitAsync(TimeSpan.FromSeconds(2));
        }
        catch (TimeoutException)
        {
        }

        await _stdoutPipe.Writer.CompleteAsync();
        await _stdoutPipe.Reader.CompleteAsync();
        await _clientOutput.DisposeAsync();
        _process.Dispose();
    }

    private async Task PumpStdoutAsync()
    {
        try
        {
            using var reader = new StreamReader(
                _process.StandardOutput.BaseStream,
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true),
                detectEncodingFromByteOrderMarks: false,
                bufferSize: 1024,
                leaveOpen: true);
            while (await reader.ReadLineAsync() is { } line)
            {
                RawStdoutLines.Enqueue(line);
                McpProtocolLineValidator.ValidateLine(line);
                var bytes = Encoding.UTF8.GetBytes(line + "\n");
                await _stdoutPipe.Writer.WriteAsync(bytes);
            }

            await _stdoutPipe.Writer.CompleteAsync();
        }
        catch (Exception exception)
        {
            ValidationFailure = exception;
            await _stdoutPipe.Writer.CompleteAsync(exception);
        }
    }

    private async Task PumpStderrAsync()
    {
        using var reader = _process.StandardError;
        while (await reader.ReadLineAsync() is { } line)
        {
            StderrLines.Enqueue(line);
        }
    }
}

public static class McpProtocolLineValidator
{
    public static void ValidateLine(string line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            throw new InvalidDataException("MCP STDOUT contained a blank line.");
        }

        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(line);
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException($"MCP STDOUT line is not JSON: {line}", exception);
        }

        using (document)
        {
            ValidateDocument(line, document.RootElement);
        }
    }

    private static void ValidateDocument(string line, JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object ||
            !root.TryGetProperty("jsonrpc", out var version) ||
            version.ValueKind != JsonValueKind.String ||
            version.GetString() != "2.0")
        {
            throw new InvalidDataException($"MCP STDOUT line is not a JSON-RPC 2.0 object: {line}");
        }

        var hasMethod = root.TryGetProperty("method", out var method) && method.ValueKind == JsonValueKind.String;
        var hasId = root.TryGetProperty("id", out var id);
        var hasResult = root.TryGetProperty("result", out _);
        var hasError = root.TryGetProperty("error", out _);
        var validId = !hasId || id.ValueKind is JsonValueKind.String or JsonValueKind.Number or JsonValueKind.Null;
        var isRequestOrNotification = hasMethod && !hasResult && !hasError;
        var isResponse = !hasMethod && hasId && validId && hasResult != hasError;

        if (!isRequestOrNotification && !isResponse)
        {
            throw new InvalidDataException($"MCP STDOUT line is not a JSON-RPC message: {line}");
        }
    }
}
