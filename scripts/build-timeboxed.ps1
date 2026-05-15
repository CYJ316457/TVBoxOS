param(
    [string]$GradleTask = ":app:assembleNormalDebug",
    [int]$TimeoutMinutes = 5
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function New-DirectoryIfMissing {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-GradleDaemonPids {
    $matched = @()
    $javaProcesses = Get-Process -Name java -ErrorAction SilentlyContinue
    foreach ($proc in $javaProcesses) {
        try {
            $output = & "C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot\bin\jcmd.exe" $proc.Id VM.command_line 2>$null
            $commandText = $output -join "`n"
            if ($commandText -like "*org.gradle.launcher.daemon.bootstrap.GradleDaemon 7.3.3*") {
                $matched += $proc.Id
            }
        } catch {
        }
    }
    return $matched
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$buildRoot = Join-Path $repoRoot ".codex-build"
$logRoot = Join-Path $buildRoot "logs"
$sharedTempRoot = Join-Path $env:TEMP "tvboxos-one-build"
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path (Join-Path $sharedTempRoot "runs") $runId
$gradleHome = Join-Path $sharedTempRoot "gradle-home"
$androidUserHome = Join-Path $sharedTempRoot "android-user-home"
$logPath = Join-Path $logRoot ("build-" + $runId + ".log")
$stdoutLogPath = Join-Path $logRoot ("build-" + $runId + ".stdout.log")
$stderrLogPath = Join-Path $logRoot ("build-" + $runId + ".stderr.log")
 $seedWrapperDist = "C:\Users\YL\.gradle\wrapper\dists\gradle-7.3.3-bin"
 $targetWrapperDist = Join-Path $gradleHome "wrapper\dists\gradle-7.3.3-bin"

@($buildRoot, $logRoot, $runRoot, $sharedTempRoot, $gradleHome, $androidUserHome) | ForEach-Object {
    New-DirectoryIfMissing -Path $_
}

if ((Test-Path -LiteralPath $seedWrapperDist) -and (-not (Test-Path -LiteralPath $targetWrapperDist))) {
    Write-Host "[构建] 预热临时 Gradle 缓存"
    New-DirectoryIfMissing -Path (Split-Path $targetWrapperDist -Parent)
    New-DirectoryIfMissing -Path $targetWrapperDist
    Copy-Item -Path (Join-Path $seedWrapperDist "*") -Destination $targetWrapperDist -Recurse -Force -Exclude "*.lck"
}

$runnerScript = Join-Path $runRoot "run-gradle.ps1"
$runnerContent = @"
`$ErrorActionPreference = 'Stop'
`$env:GRADLE_USER_HOME = '$gradleHome'
`$env:ANDROID_USER_HOME = '$androidUserHome'
Remove-Item Env:ANDROID_SDK_HOME -ErrorAction SilentlyContinue
Remove-Item Env:ANDROID_PREFS_ROOT -ErrorAction SilentlyContinue
`$env:TVBOX_BUILD_ROOT = '$runRoot'
Set-Location '$repoRoot'
& '$repoRoot\gradlew.bat' '$GradleTask' '--stacktrace' '--info' '--no-daemon'
exit `$LASTEXITCODE
"@
[System.IO.File]::WriteAllText($runnerScript, $runnerContent, [System.Text.UTF8Encoding]::new($false))

Write-Host ("[构建] 任务: " + $GradleTask)
Write-Host ("[构建] 超时: " + $TimeoutMinutes + " 分钟")
Write-Host ("[构建] 日志: " + $logPath)

$staleGradleDaemons = Get-GradleDaemonPids
if ($staleGradleDaemons.Count -gt 0) {
    Write-Host ("[构建] 预清理旧 Gradle daemon: " + (($staleGradleDaemons | ForEach-Object { $_.ToString() }) -join ", "))
    foreach ($daemonPid in $staleGradleDaemons) {
        try {
            Stop-Process -Id $daemonPid -Force -ErrorAction SilentlyContinue
        } catch {
        }
    }
    Start-Sleep -Seconds 2
}

$beforeJavaPids = @(Get-Process -Name java -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
$proc = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runnerScript) `
    -WorkingDirectory $repoRoot `
    -RedirectStandardOutput $stdoutLogPath `
    -RedirectStandardError $stderrLogPath `
    -PassThru

$finished = $proc.WaitForExit($TimeoutMinutes * 60 * 1000)

if (-not $finished) {
    Write-Host ("[构建] 超过 " + $TimeoutMinutes + " 分钟，开始取消")
    try {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    } catch {
    }
    Start-Sleep -Seconds 2
    $javaPids = @(Get-Process -Name java -ErrorAction SilentlyContinue | Where-Object { $beforeJavaPids -notcontains $_.Id } | ForEach-Object { $_.Id })
    foreach ($javaPid in $javaPids) {
        try {
            Stop-Process -Id $javaPid -Force -ErrorAction SilentlyContinue
        } catch {
        }
    }
    Write-Host ("[构建] 已取消。相关 Java 进程: " + (($javaPids | ForEach-Object { $_.ToString() }) -join ", "))
    @(
        "===== STDOUT ====="
        ((Get-Content $stdoutLogPath -Tail 60 -ErrorAction SilentlyContinue) -join "`n")
        "===== STDERR ====="
        ((Get-Content $stderrLogPath -Tail 60 -ErrorAction SilentlyContinue) -join "`n")
    ) | Set-Content -Path $logPath -Encoding UTF8
    Write-Host "[构建] 日志末尾："
    Get-Content $logPath -Tail 80
    exit 124
}

$proc.Refresh()
$exitCode = if ($null -eq $proc.ExitCode) { 1 } else { [int]$proc.ExitCode }
if ($exitCode -ne 0) {
    $newJavaPids = @(Get-Process -Name java -ErrorAction SilentlyContinue | Where-Object { $beforeJavaPids -notcontains $_.Id } | ForEach-Object { $_.Id })
    foreach ($javaPid in $newJavaPids) {
        try {
            Stop-Process -Id $javaPid -Force -ErrorAction SilentlyContinue
        } catch {
        }
    }
}
@(
    "===== STDOUT ====="
    ((Get-Content $stdoutLogPath -Tail 200 -ErrorAction SilentlyContinue) -join "`n")
    "===== STDERR ====="
    ((Get-Content $stderrLogPath -Tail 200 -ErrorAction SilentlyContinue) -join "`n")
) | Set-Content -Path $logPath -Encoding UTF8
$combinedLog = Get-Content $logPath -Raw
if ($combinedLog -like "*BUILD SUCCESSFUL*") {
    $exitCode = 0
} elseif ($combinedLog -like "*BUILD FAILED*") {
    $exitCode = 1
}
Write-Host ("[构建] 退出码: " + $exitCode)
Write-Host "[构建] 日志末尾："
Get-Content $logPath -Tail 80
exit $exitCode
