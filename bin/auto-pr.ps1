<#
.SYNOPSIS
    Updates manifests and pushes them or creates pull-requests.
.DESCRIPTION
    Updates manifests and pushes them directly to the origin branch or creates pull-requests for upstream.
.PARAMETER Upstream
    Upstream repository with the target branch.
    Must be in format '<user>/<repo>:<branch>'
.PARAMETER OriginRepoNwo
    Origin (local) repository name.
    Must be in format '<user>/<repo>'
.PARAMETER OriginBranch
    Origin (local) branch name.
.PARAMETER App
    Manifest name to search.
    Placeholders are supported.
.PARAMETER CommitMessageFormat
    The format of the commit message.
    <app> will be replaced with the file name of manifest.
    <version> will be replaced with the version of the latest manifest.
.PARAMETER Dir
    The directory where to search for manifests.
.PARAMETER Push
    Push updates directly to 'origin branch'.
.PARAMETER Bot
    Use the GitHub GraphQL API for commit and push.
.PARAMETER TOKEN
    The bot needs to use TOKEN for login verification.
.PARAMETER Request
    Create pull-requests on 'upstream branch' for each update.
.PARAMETER Help
    Print help to console.
.PARAMETER SpecialSnowflakes
    An array of manifests, which should be updated all the time. (-ForceUpdate parameter to checkver)
.PARAMETER SkipUpdated
    Updated manifests will not be shown.
.PARAMETER ThrowError
    Throw error as exception instead of just printing it.
.EXAMPLE
    PS BUCKETROOT > .\bin\auto-pr.ps1 'someUsername/repository:branch' -Request
.EXAMPLE
    PS BUCKETROOT > .\bin\auto-pr.ps1 -Push
    Update all manifests inside 'bucket/' directory.
#>

param(
    # overwrite upstream param
    [ValidateScript( {
        if (!($_ -match '^(.*)\/(.*):(.*)$')) {
            throw 'Upstream must be in this format: <user>/<repo>:<branch>'
        }
        $true
    })]
    [String] $Upstream = "maboloshi/scoop-private:master",
    [ValidateScript( {
        if (!($_ -match '^(.*)\/(.*)$')) {
            throw 'Origin (local) repository name must be in this format: <user>/<repo>'
        }
        $true
    })]
    [String] $OriginRepoNwo,
    [String] $OriginBranch = 'master',
    [String] $App = '*',
    [String] $CommitMessageFormat = '<app>: Update to version <version>',
    [ValidateScript( {
        if (!(Test-Path $_ -Type Container)) {
            throw "$_ is not a directory!"
        } else {
            $true
        }
    })]
    [String] $Dir = "$PSScriptRoot/../bucket", # checks the parent dir
    [Switch] $Push,
    [Switch] $Bot,
    [String] $TOKEN,
    [Switch] $Request,
    [Switch] $Help,
    [string[]] $SpecialSnowflakes,
    [Switch] $SkipUpdated,
    [Switch] $ThrowError
)

if (-not $OriginRepoNwo) {
    $OriginRepoNwo = if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else { (git remote get-url origin -replace '\.git').Split('/')[-2,-1] -join '/' }
}

if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Convert-Path (scoop prefix scoop) }
. (Join-Path $env:SCOOP_HOME "lib\core.ps1")
. (Join-Path $env:SCOOP_HOME "lib\manifest.ps1")
. (Join-Path $env:SCOOP_HOME "lib\json.ps1")

if ($App -ne '*' -and (Test-Path $App -PathType Leaf)) {
    $Dir = Split-Path $App
} elseif ($Dir) {
    $Dir = Convert-Path $Dir
} else {
    throw "'-Dir' parameter required if '-App' is not a filepath!"
}

if ($Request -and !$Upstream) {
    throw "The '-Request' parameter needs to also set the upstream repository with target branch.
The upstream repository with target branch must be in the format '<user>/<repo>:<branch>'"
    exit 0
}

if ((!$Push -and !$Request) -or $Help) {
    Write-Host @'
Usage: auto-pr.ps1 [OPTION]

Mandatory options:
  -p,  -push                       push updates directly to 'origin branch'
  -r,  -request                    create pull-requests on 'upstream branch' for each update

Optional options:
  -u,  -upstream                   upstream repository with target branch
  -o,  -originbranch               origin (local) branch name
  -b,  -bot                        use the GitHub GraphQL API for commit and push
  -h,  -help
'@
    exit 0
}

# 使用 git 和 gh 代替 hub
if ($IsLinux -or $IsMacOS) {
    if (!(which gh)) {
        Write-Host "Please install gh ('brew install gh' or visit: https://cli.github.com/)" -ForegroundColor Yellow
        exit 1
    }
} else {
    if (!(which gh) && !(scoop which gh)) {
        Write-Host "Please install gh 'scoop install gh'" -ForegroundColor Yellow
        exit 1
    }
}

function execute($cmd) {
    Write-Host $cmd -ForegroundColor Green
    $output = Invoke-Command ([scriptblock]::Create($cmd))

    if ($LASTEXITCODE -gt 0) {
        abort "^^^ Error! See above ^^^ (last command: $cmd)"
    }

    return $output
}

function pull_requests($json, [String] $app, [String] $upstream, [String] $manifest, [String] $commitMessage) {
    $version = $json.version
    $homepage = $json.homepage
    $branch = "manifest/$app-$version"

    execute "git checkout $OriginBranch"
    # Detecting the existence of the "manifest/$app-$version" remote branch
    Write-Host "git ls-remote --exit-code origin $branch" -ForegroundColor Green
    git ls-remote --exit-code origin $branch

    # Skip if "manifest/$app-$version" remote branch already exists
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Skipping update $app ($version) ..." -ForegroundColor Yellow
        return
    }

    execute "git checkout -b $branch"
    execute "git push origin $branch"

    if ($Bot) {
        Write-Host "Creating and Pushing update $app ($version) via the GitHub GraphQL API ..." -ForegroundColor DarkCyan
        $response = graphql_commit_push -t $TOKEN -RepoNwo $OriginRepoNwo -b $branch -f $manifest `
         -MessageTitle $CommitMessage `
         -MessageBody 'Signed-off-by: github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>' `
         -ParentSHA $((git ls-remote --refs --quiet origin $OriginBranch).Split()[0])

        if (!$response.data.createCommitOnBranch.commit.url) {
            error "Commit and push $app ($version) via the GitHub GraphQL API failed! (`n'$( $response | ConvertTo-Json -Depth 100 )'`n)"
            execute 'git reset'
            return
        }
    } else {
        Write-Host "Creating update $app ($version) ..." -ForegroundColor DarkCyan
        execute "git add $manifest"
        execute "git commit -m '$commitMessage"
        Write-Host "Pushing update $app ($version) ..." -ForegroundColor DarkCyan
        execute "git push origin $branch"

        if ($LASTEXITCODE -gt 0) {
            error "Push failed! (git push origin $branch)"
            execute 'git reset'
            return
        }
    }

    Start-Sleep 1
    Write-Host "Pull-Request update $app ($version) ..." -ForegroundColor DarkCyan
    # Write-Host "hub pull-request -m '<msg>' -b '$upstream' -h '${OriginRepoNwo}:$branch'" -ForegroundColor Green
    Write-Host "gh pr create -t '<MessageTitle>' -b '<MessageBody>' -B '$upstream' -H '${OriginRepoNwo}:$branch'" -ForegroundColor Green

    $MessageTitle = $commitMessage
    $MessageBody = @"
Hello lovely humans,
a new version of [$app]($homepage) is available.

| State       | Update :rocket: |
| :---------- | :-------------- |
| New version | $version        |
"@

    # hub pull-request -m "$msg" -b "$upstream" -h "${OriginRepoNwo}:$branch"
    gh pr create -t $MessageTitle -b $MessageBody -B "$upstream" -H "${OriginRepoNwo}:$branch"
    if ($LASTEXITCODE -gt 0) {
        execute 'git reset'
        # abort "Pull Request failed! (hub pull-request -m '$commitMessage' -b '$upstream' -h '${OriginRepoNwo}:$branch')"
        abort "Pull Request failed! (gh pr create -t '$MessageTitle' -b '$MessageBody' -B '$upstream' -H '${OriginRepoNwo}:$branch')"
    }
}

function graphql_commit_push {
    # Note that you cannot push to an empty branch
    param (
        # Remote repository name with owner requested by the GitHub GraphQL API
        [String] $RepoNwo,
        # Repository branch name requested by the GitHub GraphQL API
        [String] $Branch,
        # Name of the file committed via the GitHub GraphQL API (relative to the repository root)
        [String] $FilePath,
        # Commit message head line committed via the GitHub GraphQL API
        [String] $MessageTitle,
        # Commit message body committed via the GitHub GraphQL API
        [String] $MessageBody = '',
        # TOKEN for authentication via the GitHub GraphQL API
        [String] $Token,
        # The sha of the last commit on the target branch of the remote repository.
        # It is also the SHA of the parent commit of the commit about to be created.
        [String] $ParentSHA
    )

    if ($env:GITHUB_GRAPHQL_URL) {
        $GITHUB_GRAPHQL_URL = $env:GITHUB_GRAPHQL_URL
    } else {
        $GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"
    }
    # Note that the line breaks in the cummitted file are LF style
    $encoded_file_content = (Get-Content -Path $FilePath -Raw -Encoding UTF8) -replace "`r`n", "`n" | ForEach-Object { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_)) }

    $query = @"
    {
      "query": "mutation (`$input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: `$input) { commit { url } } }",
      "variables": {
        "input": {
          "branch": {
            "repositoryNameWithOwner": "$RepoNwo",
            "branchName": "$Branch"
          },
          "message": {
            "headline": "$MessageTitle",
            "body": "$MessageBody"
          },
          "fileChanges": {
            "additions": [
              {
                "path": "$FilePath",
                "contents": "$encoded_file_content"
              }
            ]
          },
          "expectedHeadOid": "$ParentSHA"
        }
      }
    }
"@

    $headers = @{ "Authorization" = "bearer $Token" }

    Write-Host "Invoke-RestMethod -Method Post -Uri $GITHUB_GRAPHQL_URL -ContentType 'application/json' -Headers $headers -Body $query"
    Invoke-RestMethod -Method Post -Uri $GITHUB_GRAPHQL_URL -ContentType 'application/json' -Headers $headers -Body $query
}

Write-Host 'Updating ...' -ForegroundColor DarkCyan
if ($Push) {
    execute "git pull origin $OriginBranch"
    execute "git checkout $OriginBranch"
} elseif ($Request) {
    $UpstreamRepoNwo, $UpstreamBranch = $Upstream -split ':'
    $UpstreamUrl = "https://github.com/$UpstreamRepoNwo.git"

    # If the upstream is not set or the upstream URL does not match, set a new upstream
    $upstreamStatus = git remote -v | Where-Object { $_ -match '^upstream' }
    if (-not $upstreamStatus) {
        execute "git remote add upstream $UpstreamUrl"
    } elseif ($upstreamStatus -notmatch ($UpstreamUrl -replace "\.git$")) {
        execute "git remote remove upstream"
        execute "git remote add upstream $UpstreamUrl"
    }
    execute "git pull --rebase --autostash upstream $UpstreamBranch"
    execute "git push origin $OriginBranch"
}

. (Join-Path $env:SCOOP_HOME "bin\checkver.ps1") -App $App -Dir $Dir -Update -SkipUpdated:$SkipUpdated -ThrowError:$ThrowError
if ($SpecialSnowflakes) {
    Write-Host "Forcing update on our special snowflakes: $($SpecialSnowflakes -join ',')" -ForegroundColor DarkCyan
    $SpecialSnowflakes -split ',' | ForEach-Object {
        . (Join-Path $env:SCOOP_HOME "bin\checkver.ps1") $_ -Dir $Dir -ForceUpdate -ThrowError:$ThrowError
    }
}

hub diff --name-only | ForEach-Object {
    $manifest = $_
    if (!$manifest.EndsWith('.json')) {
        return
    }

    $app = ([System.IO.Path]::GetFileNameWithoutExtension($manifest))
    $json = parse_json $manifest
    if (!$json.version) {
        error "Invalid manifest: $manifest ..."
        return
    }
    $version = $json.version
    $CommitMessage = $CommitMessageFormat -replace '<app>',$app -replace '<version>',$version

    if ($Push) {
        execute "git add $manifest"

        # detect if file was staged, because it's not when only LF or CRLF have changed
        $status = execute "git status --porcelain -uno"
        $status = $status | Where-Object { $_ -match "M\s{2}.*$app.json" }
        if ($status -and $status.StartsWith('M  ') -and $status.EndsWith("$app.json")) {
            if ($Bot) {
                Write-Host "Creating and Pushing update $app ($version) via the GitHub GraphQL API ..." -ForegroundColor DarkCyan
                $response = graphql_commit_push -t $TOKEN -RepoNwo $OriginRepoNwo -b $OriginBranch -f $manifest `
                 -MessageTitle $CommitMessage `
                 -MessageBody 'Signed-off-by: github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>' `
                 -ParentSHA $((git ls-remote --refs --quiet origin $OriginBranch).Split()[0])

                if ($response.data.createCommitOnBranch.commit.url) {
                    execute "git fetch origin $OriginBranch"
                } else {
                    error "Commit and push $app ($version) via the GitHub GraphQL API failed! (`n'$( $response | ConvertTo-Json -Depth 100 )'`n)"
                }
            } else {
                Write-Host "Creating update $app ($version) ..." -ForegroundColor DarkCyan
                execute "git commit -m '$commitMessage'"
            }
        } else {
            Write-Host "Skipping $app because only LF/CRLF changes were detected ..." -ForegroundColor Yellow
        }
    } elseif ($Request) {
        pull_requests $json $app $Upstream $manifest $CommitMessage
    }
}

if ($Push -and !$Bot) {
    Write-Host 'Pushing updates ...' -ForegroundColor DarkCyan
    execute "git push origin $OriginBranch"
} else {
    Write-Host "Returning to $OriginBranch branch and removing unstaged files ..." -ForegroundColor DarkCyan
    execute "git checkout -f $OriginBranch"
}

execute "git reset --hard"
