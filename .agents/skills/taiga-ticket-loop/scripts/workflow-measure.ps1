[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('record-phase','summarize-timing','import-usage','cost-report','comparison-report')]
    [string] $Operation,
    [Parameter(Mandatory = $true)]
    [string] $InputPath,
    [string] $StateRoot
)

$ErrorActionPreference = 'Stop'

function Read-Object {
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw 'Input was not found.' }
    try { $value = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $InputPath) -AsHashtable -Depth 100 } catch { throw "Input is not valid JSON: $($_.Exception.Message)" }
    if ($value -isnot [System.Collections.IDictionary]) { throw 'Input JSON must be an object.' }
    return $value
}

function Need { param([System.Collections.IDictionary]$Object,[string]$Name); if (-not $Object.Contains($Name) -or $null -eq $Object[$Name] -or [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { throw "$Name is required." }; return [string]$Object[$Name] }
function Get-Stamp { param([string]$Value,[string]$Name); $parsed = [DateTimeOffset]::MinValue; if (-not [DateTimeOffset]::TryParse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsed)) { throw "$Name must be an ISO-8601 timestamp." }; return $parsed }
function Get-Sha256 { param([string]$Text); $sha=[Security.Cryptography.SHA256]::Create(); try { return ([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).ToLowerInvariant() } finally { $sha.Dispose() } }
function Get-FileSha256 { param([string]$Path); $sha=[Security.Cryptography.SHA256]::Create();$stream=[IO.File]::OpenRead($Path);try{return ([Convert]::ToHexString($sha.ComputeHash($stream))).ToLowerInvariant()}finally{$stream.Dispose();$sha.Dispose()} }
function Get-Root { if ([string]::IsNullOrWhiteSpace($StateRoot)) { throw 'StateRoot is required.' }; $root=[IO.Path]::GetFullPath($StateRoot); [IO.Directory]::CreateDirectory($root)|Out-Null; return $root }
function Write-AtomicJson { param([string]$Path,[object]$Value);$tmp="$Path.$([Guid]::NewGuid().ToString('N')).tmp";try{[IO.File]::WriteAllText($tmp,($Value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $tmp -Destination $Path -Force}finally{if(Test-Path -LiteralPath $tmp -PathType Leaf){Remove-Item -LiteralPath $tmp -Force}} }
function Read-Registry { param([string]$Root,[string]$RunId);$path=Join-Path $Root 'measurement-registry.json';if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [ordered]@{schemaVersion=1;runId=$RunId;events=@();updatedAtUtc=$null}};try{$state=ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $path) -AsHashtable -Depth 100}catch{throw 'Measurement registry is malformed.'};if([int]$state.schemaVersion -ne 1 -or [string]$state.runId -cne $RunId){throw 'Measurement registry schema or run binding is invalid.'};return $state}

function Invoke-RecordPhase {
    param([System.Collections.IDictionary]$InputObject)
    $root=Get-Root;$runId=Need $InputObject 'runId';$kind=Need $InputObject 'eventKind';$at=Get-Stamp (Need $InputObject 'atUtc') 'atUtc'
    $allowed=@('dispatch','result_observed','receipt_accepted','phase_change','wait','repair','publication','pause','resume');if($allowed -notcontains $kind){throw "Unsupported eventKind: $kind"}
    $state=Read-Registry $root $runId;$eventId=if($InputObject.Contains('eventId')){Need $InputObject 'eventId'}else{'evt-'+[Guid]::NewGuid().ToString('N')};if(@($state.events|Where-Object{$_.eventId -eq $eventId}).Count -gt 0){throw 'Measurement event IDs are immutable.'}
    $duration=$null;if($InputObject.Contains('workerReportedDurationSeconds') -and $null -ne $InputObject.workerReportedDurationSeconds){$duration=[double]$InputObject.workerReportedDurationSeconds;if($duration -lt 0){throw 'workerReportedDurationSeconds must be nonnegative.'}}
    $event=[ordered]@{schemaVersion=1;eventId=$eventId;runId=$runId;eventKind=$kind;phase=if($InputObject.Contains('phase')){[string]$InputObject.phase}else{$null};atUtc=$InputObject.atUtc;source=if($InputObject.Contains('source')){[string]$InputObject.source}else{'coordinator_observation'};workerReportedDurationSeconds=$duration;actionId=if($InputObject.Contains('actionId')){[string]$InputObject.actionId}else{$null};workerId=if($InputObject.Contains('workerId')){[string]$InputObject.workerId}else{$null};metadata=if($InputObject.Contains('metadata')){$InputObject.metadata}else{@{}}}
    $state.events=@($state.events)+@($event);$state.updatedAtUtc=$InputObject.atUtc; if(@($state.events).Count -gt 1000){$state.events=@($state.events | Select-Object -Last 1000)};Write-AtomicJson (Join-Path $root 'measurement-registry.json') $state
    $auditPath=Join-Path $root 'measurement-audit.ndjson';[IO.File]::AppendAllText($auditPath,(($event|ConvertTo-Json -Depth 100 -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    $last=@($state.events|Where-Object{$_.runId -eq $runId}|Sort-Object {Get-Stamp $_.atUtc 'event.atUtc'})|Select-Object -Last 2;$alerts=@();if($InputObject.Contains('stallAfterMinutes') -and $last.Count -eq 2){$gap=([DateTimeOffset]::Parse([string]$last[1].atUtc)-[DateTimeOffset]::Parse([string]$last[0].atUtc)).TotalMinutes;if($gap -gt [double]$InputObject.stallAfterMinutes){$alerts+=([ordered]@{kind='stalled_phase';gapMinutes=$gap;action='observe_or_escalate';cancelsWorker=$false;changesModel=$false})}}
    return [ordered]@{event=$event;alerts=$alerts;registryEventCount=@($state.events).Count;auditPath=$auditPath}
}

function Invoke-SummarizeTiming {
    param([System.Collections.IDictionary]$InputObject)
    $root=Get-Root;$runId=Need $InputObject 'runId';$state=Read-Registry $root $runId;$events=@($state.events|Where-Object{$_.runId -eq $runId}|Sort-Object {Get-Stamp $_.atUtc 'event.atUtc'});$find={param([string]$Kind) @($events|Where-Object{$_.eventKind -eq $Kind}|Select-Object -First 1)}
    $dispatch=&$find 'dispatch';$observed=&$find 'result_observed';$receipt=&$find 'receipt_accepted';$phaseEvents=@($events|Where-Object{$_.eventKind -eq 'phase_change'});$intervals=@();for($i=1;$i -lt $phaseEvents.Count;$i++){ $from=$phaseEvents[$i-1];$to=$phaseEvents[$i];$intervals+=[ordered]@{from=[string]$from.phase;to=[string]$to.phase;seconds=([DateTimeOffset]::Parse([string]$to.atUtc)-[DateTimeOffset]::Parse([string]$from.atUtc)).TotalSeconds} }
    return [ordered]@{runId=$runId;eventCount=$events.Count;dispatchToObservationSeconds=if($dispatch -and $observed){([DateTimeOffset]::Parse([string]$observed.atUtc)-[DateTimeOffset]::Parse([string]$dispatch.atUtc)).TotalSeconds}else{$null};observationToReceiptSeconds=if($observed -and $receipt){([DateTimeOffset]::Parse([string]$receipt.atUtc)-[DateTimeOffset]::Parse([string]$observed.atUtc)).TotalSeconds}else{$null};wallClockPhaseIntervals=$intervals;workerReportedDurations=@($events|Where-Object{$null -ne $_.workerReportedDurationSeconds}|ForEach-Object{[ordered]@{eventId=$_.eventId;seconds=$_.workerReportedDurationSeconds}});unknownWorkerDurationCount=@($events|Where-Object{$null -eq $_.workerReportedDurationSeconds}).Count;alerts=@()}
}

function Read-Snapshots { param([System.Collections.IDictionary]$InputObject);if(-not $InputObject.Contains('snapshots') -or $InputObject.snapshots -is [string]){throw 'snapshots must be an array.'};return @($InputObject.snapshots)}
function Get-Counters { param([System.Collections.IDictionary]$Snapshot);if(-not $Snapshot.Contains('counters') -or $Snapshot.counters -isnot [System.Collections.IDictionary]){return $null};$names=@('inputTokens','cachedInputTokens','outputTokens','reasoningTokens');$result=[ordered]@{};foreach($name in $names){if(-not $Snapshot.counters.Contains($name)){return $null};$number=0L;if(-not [long]::TryParse([string]$Snapshot.counters[$name],[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)-or $number -lt 0){throw "Counter $name is invalid."};$result[$name]=$number};return $result}
function Invoke-ImportUsage {
    param([System.Collections.IDictionary]$InputObject)
    $start=Get-Stamp (Need $InputObject 'startedAtUtc') 'startedAtUtc';$end=Get-Stamp (Need $InputObject 'endedAtUtc') 'endedAtUtc';if($end -le $start){throw 'endedAtUtc must be after startedAtUtc.'};$snapshots=Read-Snapshots $InputObject;$seen=@{};$rows=@();$duplicates=0;$later=0
    foreach($snapshot in $snapshots){foreach($name in @('role','model','effort','atUtc')){Need $snapshot $name|Out-Null};$stamp=Get-Stamp $snapshot.atUtc 'snapshot.atUtc';$counters=Get-Counters $snapshot;$identity=Get-Sha256 ("$($snapshot.role)|$($snapshot.model)|$($snapshot.effort)|"+($counters|ConvertTo-Json -Depth 20 -Compress));if($seen.ContainsKey($identity)){$duplicates++;continue};$seen[$identity]=$true;if($stamp -gt $end){$later++};$rows+=[ordered]@{snapshot=$snapshot;stamp=$stamp;counters=$counters;identity=$identity}}
    $groups=@($rows|Group-Object {"$($_.snapshot.role)|$($_.snapshot.model)|$($_.snapshot.effort)"});$roles=@()
    foreach($group in $groups){$ordered=@($group.Group|Sort-Object stamp);$previous=$null;$segment=0;$deltas=@();$unknown=$false;foreach($row in $ordered){$counter=$row.counters;if($null -eq $counter){$unknown=$true;continue};if($null -ne $previous){$reset=$false;$delta=[ordered]@{};foreach($key in $counter.Keys){if($counter[$key] -lt $previous[$key]){$reset=$true};$delta[$key]=$counter[$key]-$previous[$key]};if($reset){$segment++;$deltas+=[ordered]@{segment=$segment;atUtc=$row.snapshot.atUtc;delta=$null;reset=$true};$unknown=$true}else{$deltas+=[ordered]@{segment=$segment;atUtc=$row.snapshot.atUtc;delta=$delta;reset=$false}}};$previous=$counter}
        $inRange=@($ordered|Where-Object{$_.stamp -ge $start -and $_.stamp -le $end});$roles+=[ordered]@{role=$group.Group[0].snapshot.role;model=$group.Group[0].snapshot.model;effort=$group.Group[0].snapshot.effort;segments=$segment+1;deltas=$deltas;inRangeSamples=$inRange.Count;unknown=$unknown -or ($inRange.Count -eq 0);requestCountsProven=$false}
    }
    return [ordered]@{schemaVersion=1;startedAtUtc=$InputObject.startedAtUtc;endedAtUtc=$InputObject.endedAtUtc;roles=$roles;duplicateSnapshots=$duplicates;postRunSnapshots=$later;counterResets=@($roles|ForEach-Object{@($_.deltas|Where-Object reset)}|Measure-Object|Select-Object -ExpandProperty Count);missingUsageIsUnknown=$true;requestCountsProven=$false;source=if($InputObject.Contains('source')){[string]$InputObject.source}else{'explicit_usage_export'}}
}

function Invoke-CostReport {
    param([System.Collections.IDictionary]$InputObject)
    if(-not $InputObject.Contains('usage')){throw 'usage is required.'};$usage=$InputObject.usage;$estimates=@();$actual=if($InputObject.Contains('actualConsumption')){$InputObject.actualConsumption}else{$null};$subscription=if($InputObject.Contains('subscriptionUsage')){$InputObject.subscriptionUsage}else{$null}
    foreach($item in @($usage)){foreach($name in @('role','model','effort')){Need $item $name|Out-Null};$rate=$null;if($InputObject.Contains('rates') -and $InputObject.rates.Contains([string]$item.model)){$rate=$InputObject.rates[[string]$item.model]};$raw=if($item.Contains('tokens')){$item.tokens}else{@{}};$estimate=$null;if($null -ne $rate -and $item.Contains('inputTokens') -and $item.Contains('outputTokens')){$input=[double]$item.inputTokens;$cached=if($item.Contains('cachedInputTokens')){[double]$item.cachedInputTokens}else{0};$output=[double]$item.outputTokens;$estimate=(($input-$cached)*[double]$rate.inputPerMillion+$cached*[double]$rate.cachedInputPerMillion+$output*[double]$rate.outputPerMillion)/1000000};$estimates+=[ordered]@{role=$item.role;model=$item.model;effort=$item.effort;rawUsage=$item;apiEstimateUsd=$estimate;estimateSource=if($null -ne $rate){$rate.source}else{$null};reasoningIncludedInOutput=if($item.Contains('reasoningIncludedInOutput')){$item.reasoningIncludedInOutput}else{$null}}
    }
    return [ordered]@{usage=$estimates;actualMonetaryConsumption=$actual;subscriptionConsumption=$subscription;actualCostAvailable=($null -ne $actual);subscriptionAttributionAvailable=($null -ne $subscription);rawTokensAreNotCost=$true;automaticModelChange=$false}
}

function Invoke-Comparison {
    param([System.Collections.IDictionary]$InputObject)
    if(-not $InputObject.Contains('runs') -or @($InputObject.runs).Count -ne 2){throw 'runs must contain exactly two comparison runs.'};$runs=@($InputObject.runs);$same=$true;$reasons=@();foreach($field in @('scopeHash','repositoryRequirementsHash','profilesHash')){if([string]$runs[0][$field] -cne [string]$runs[1][$field]){$same=$false;$reasons+="$field differs"}};return [ordered]@{comparable=$same;nonComparableReasons=$reasons;runs=@($runs|ForEach-Object{[ordered]@{name=$_.name;quality=$_.quality;acceptedDefects=$_.acceptedDefects;wallClockSeconds=$_.wallClockSeconds;usage=$_.usage;coordinationActions=$_.coordinationActions;repairCounts=$_.repairCounts;actualCost=if($_.Contains('actualCost')){$_.actualCost}else{$null};estimatedCost=if($_.Contains('estimatedCost')){$_.estimatedCost}else{$null}}});rawTokenDifference=if($same){[double]$runs[1].totalTokens-[double]$runs[0].totalTokens}else{$null};qualityGate='acceptance_and_quality';rawTokenReductionIsNotAReleaseGate=$true;costUnknownWhenUnattributed=$true;modelSelection='explicit_only'}
}

try{$inputObject=Read-Object;$data=switch($Operation){'record-phase'{Invoke-RecordPhase $inputObject};'summarize-timing'{Invoke-SummarizeTiming $inputObject};'import-usage'{Invoke-ImportUsage $inputObject};'cost-report'{Invoke-CostReport $inputObject};'comparison-report'{Invoke-Comparison $inputObject}};[ordered]@{ok=$true;operation=$Operation;data=$data}|ConvertTo-Json -Depth 100;exit 0}catch{[ordered]@{ok=$false;operation=$Operation;error=[ordered]@{category='workflow_measure';message=$_.Exception.Message}}|ConvertTo-Json -Depth 20;exit 1}
