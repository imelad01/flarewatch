param (
    [switch]$AutoPush = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=== FlareWatch Upstream Sync ===" -ForegroundColor Cyan

# 1. Verify remotes
$remotes = git remote
if ($remotes -notcontains "upstream") {
    Write-Host "Adding upstream remote https://github.com/saminnet/flarewatch.git..." -ForegroundColor Yellow
    git remote add upstream https://github.com/saminnet/flarewatch.git
}

# 2. Check for dirty working tree
$status = git status --porcelain
$stashed = $false
if ($status) {
    Write-Host "Stashing uncommitted local changes..." -ForegroundColor Yellow
    git stash push -m "flarewatch-autostash-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $stashed = $true
}

try {
    # 3. Fetch upstream
    Write-Host "Fetching latest changes from upstream repository..." -ForegroundColor Yellow
    git fetch upstream --tags

    $currentBranch = (git branch --show-current).Trim()
    if (-not $currentBranch) {
        $currentBranch = "main"
    }

    Write-Host "Current branch: $currentBranch" -ForegroundColor Gray

    # 4. Check if upstream has new commits
    $aheadBehind = git rev-list --left-right --count "$currentBranch...upstream/main" | Out-String
    $counts = $aheadBehind.Trim() -split "\s+"
    $behind = [int]$counts[1]
    $ahead = [int]$counts[0]

    if ($behind -eq 0) {
        Write-Host "Already up to date with upstream/main! (Ahead: $ahead commits)" -ForegroundColor Green
    } else {
        Write-Host "Found $behind new commit(s) from upstream. Merging into $currentBranch..." -ForegroundColor Yellow
        
        # Perform merge
        $mergeOutput = git merge upstream/main -m "Merge upstream updates into $currentBranch" 2>&1 | Out-String
        Write-Host $mergeOutput -ForegroundColor Gray

        # If conflicts occurred in config files, keep local edits
        $conflictFiles = git diff --name-only --diff-filter=U | Out-String
        if ($conflictFiles) {
            $conflicts = $conflictFiles.Trim() -split "`n"
            foreach ($f in $conflicts) {
                $f = $f.Trim()
                if ($f -like "packages/config/src/*") {
                    Write-Host "Preserving local configuration for $f..." -ForegroundColor Cyan
                    git checkout --ours $f
                    git add $f
                }
            }
            # Check if all conflicts resolved
            $remaining = git diff --name-only --diff-filter=U | Out-String
            if (-not $remaining.Trim()) {
                git commit -m "Resolve merge conflicts keeping local config"
                Write-Host "All config conflicts automatically resolved preserving your settings!" -ForegroundColor Green
            } else {
                Write-Host "Conflicts remaining in: $remaining" -ForegroundColor Red
                Write-Host "Please resolve them manually, then run 'git commit'." -ForegroundColor Yellow
            }
        }
    }

    # 5. Reapply stash if any
    if ($stashed) {
        Write-Host "Restoring stashed local changes..." -ForegroundColor Yellow
        git stash pop
    }

    # 6. Ensure KV Namespace ID in apps/status-page/wrangler.jsonc
    $kvId = "2240fb69338b431ea0e7ed752d01ce47"
    $wranglerJsonPath = "apps/status-page/wrangler.jsonc"
    if (Test-Path $wranglerJsonPath) {
        $content = Get-Content $wranglerJsonPath -Raw
        if ($content -match "__FLAREWATCH_STATE_KV_NAMESPACE_ID__") {
            Write-Host "Re-applying flarewatch-state KV namespace ID..." -ForegroundColor Cyan
            $content = $content -replace "__FLAREWATCH_STATE_KV_NAMESPACE_ID__", $kvId
            Set-Content -Path $wranglerJsonPath -Value $content -NoNewline
        }
    }

    # 7. Update dependencies if needed
    Write-Host "Ensuring dependencies are up to date..." -ForegroundColor Yellow
    pnpm install

    # 8. Auto-push if requested
    if ($AutoPush) {
        Write-Host "Pushing updates to origin $currentBranch..." -ForegroundColor Yellow
        git push origin $currentBranch
    }

    Write-Host "`n✓ Upstream sync complete!" -ForegroundColor Green
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  - To deploy to Cloudflare directly: pnpm run deploy:all" -ForegroundColor White
    Write-Host "  - To push to your GitHub fork:     git push origin $currentBranch" -ForegroundColor White

} catch {
    Write-Host "`nError during sync: $_" -ForegroundColor Red
    if ($stashed) {
        Write-Host "Note: Your uncommitted changes are safely stashed. Run 'git stash pop' when ready." -ForegroundColor Yellow
    }
    exit 1
}
