using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;

namespace TaigaMCP.Api;

/// <summary>Creates a fresh disk-backed multipart body for each permitted 401 replay.</summary>
internal sealed class AttachmentMultipartContent : HttpContent, IReplayableHttpContent
{
    private readonly AttachmentFileSource _source;
    private readonly int _objectId;
    private readonly int _projectId;
    private readonly string? _description;
    private readonly long _maxBytes;
    private readonly string _boundary;

    public AttachmentMultipartContent(
        AttachmentFileSource source,
        int objectId,
        int projectId,
        string? description,
        long maxBytes)
    {
        _source = source;
        _objectId = objectId;
        _projectId = projectId;
        _description = description;
        _maxBytes = maxBytes;
        _boundary = Guid.NewGuid().ToString();
        var contentType = new MediaTypeHeaderValue("multipart/form-data");
        contentType.Parameters.Add(new NameValueHeaderValue("boundary", $"\"{_boundary}\""));
        Headers.ContentType = contentType;
    }

    public HttpContent CreateReplay()
        => new AttachmentMultipartContent(_source, _objectId, _projectId, _description, _maxBytes);

    protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context)
        => SerializeToStreamAsync(stream, context, CancellationToken.None);

    protected override async Task SerializeToStreamAsync(
        Stream stream,
        TransportContext? context,
        CancellationToken cancellationToken)
    {
        using var multipart = CreateMultipart(cancellationToken);
        await multipart.CopyToAsync(stream, context, cancellationToken);
    }

    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        return false;
    }

    private MultipartFormDataContent CreateMultipart(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var info = new FileInfo(_source.FullPath);
        info.Refresh();
        if (!info.Exists)
            throw new FileNotFoundException("Attachment source file is no longer available.", _source.FullPath);
        if (info.Length > _maxBytes)
            throw new IOException("Attachment source file grew beyond the configured maximum size.");

        var multipart = new MultipartFormDataContent(_boundary);
        try
        {
            multipart.Add(new StringContent(_objectId.ToString(CultureInfo.InvariantCulture)), "object_id");
            multipart.Add(new StringContent(_projectId.ToString(CultureInfo.InvariantCulture)), "project");
            if (_description is not null)
                multipart.Add(new StringContent(_description, Encoding.UTF8), "description");

            var file = new FileStream(
                _source.FullPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 64 * 1024,
                options: FileOptions.Asynchronous | FileOptions.SequentialScan);
            var limited = new MaximumLengthReadStream(file, _maxBytes);
            var fileContent = new StreamContent(limited);
            fileContent.Headers.ContentType = new MediaTypeHeaderValue(_source.MediaType);
            multipart.Add(fileContent, "attached_file", _source.FileName);
            return multipart;
        }
        catch
        {
            multipart.Dispose();
            throw;
        }
    }

    private sealed class MaximumLengthReadStream(Stream inner, long maximumLength) : Stream
    {
        private readonly Stream _inner = inner;
        private readonly long _maximumLength = maximumLength;
        private long _read;

        public override bool CanRead => _inner.CanRead;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => _inner.Length;
        public override long Position { get => _read; set => throw new NotSupportedException(); }

        public override int Read(byte[] buffer, int offset, int count)
        {
            var read = _inner.Read(buffer, offset, Limit(count));
            _read += read;
            EnsureNoMoreBytes(read == 0);
            return read;
        }

        public override async ValueTask<int> ReadAsync(
            Memory<byte> buffer,
            CancellationToken cancellationToken = default)
        {
            var read = await _inner.ReadAsync(buffer[..Limit(buffer.Length)], cancellationToken);
            _read += read;
            await EnsureNoMoreBytesAsync(read == 0, cancellationToken);
            return read;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) _inner.Dispose();
            base.Dispose(disposing);
        }

        public override ValueTask DisposeAsync() => _inner.DisposeAsync();
        public override void Flush() => throw new NotSupportedException();
        public override Task FlushAsync(CancellationToken cancellationToken) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        private int Limit(int requested)
        {
            if (_read >= _maximumLength) return 0;
            return (int)Math.Min(requested, _maximumLength - _read);
        }

        private void EnsureNoMoreBytes(bool atEnd)
        {
            if (!atEnd || _read < _maximumLength) return;
            if (_inner.ReadByte() >= 0)
                throw new IOException("Attachment source file grew beyond the configured maximum size.");
        }

        private async ValueTask EnsureNoMoreBytesAsync(bool atEnd, CancellationToken cancellationToken)
        {
            if (!atEnd || _read < _maximumLength) return;
            var probe = new byte[1];
            if (await _inner.ReadAsync(probe, cancellationToken) > 0)
                throw new IOException("Attachment source file grew beyond the configured maximum size.");
        }
    }
}
