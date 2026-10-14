# Shared UTC timestamp construction for story-performance events and metadata.
# Dot-source this file from a production script or workflow example before use.

function Format-StoryPerformanceUtcTimestamp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [DateTimeOffset] $Timestamp
    )

    return $Timestamp.ToUniversalTime().ToString(
        "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
        [Globalization.CultureInfo]::InvariantCulture)
}
