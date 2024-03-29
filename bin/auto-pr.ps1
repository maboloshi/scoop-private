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
    [Switch] $Request,
    [Switch] $Help,
    [string[]] $SpecialSnowflakes,
    [Switch] $SkipUpdated,
    [Switch] $ThrowError
)

if (-not $OriginRepoNwo) {
    $OriginRepoNwo = if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else { ((git remote get-url origin) -replace '\.git').Split('/')[-2,-1] -join '/' }
}
$OriginOwner = $OriginRepoNwo.Split('/')[0]

$Signedoffby = ""

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
  -h,  -help
'@
    exit 0
}

function execute($cmd) {
    Write-Host $cmd -ForegroundColor Green
    $output = Invoke-Command ([scriptblock]::Create($cmd))

    if ($LASTEXITCODE -gt 0) {
        abort "^^^ Error! See above ^^^ (last command: $cmd)"
    }

    return $output
}

function Invoke-GithubRequest {
    <#
    .SYNOPSIS
        Invoke authenticated github API request.
    .PARAMETER Query
        Query to be executed. `https://api/github.com/` is already included.
        If "Query" is graphql, the graphql api will be requested.
    .PARAMETER Method
        Method to be used with request.
    .PARAMETER Body
        Additional body to be send.
    .EXAMPLE
        Invoke-GithubRequest 'repos/User/Repo/pulls' -Method 'Post' -Body @{ 'body' = 'body' }
    .EXAMPLE
        Invoke-GithubRequest 'graphql' -Method 'Post' -Body @{
            query = "mutation (`$input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: `$input) { commit { url } } }"
            variables = @{
                input = @{
                    branch = @{
                        repositoryNameWithOwner = "$RepoNwo"
                        branchName = "$Branch"
                    }
                    message = @{
                        headline = "$MessageHeadline"
                        body = "$MessageBody"
                    }
                    fileChanges = @{
                        additions = @(
                            @{
                                path = "$FilePath"
                                contents = "$encoded_file_content"
                            }
                        )
                    }
                    expectedHeadOid = "$ParentSHA"
                }
            }
        }
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [String] $Query,
        [Microsoft.PowerShell.Commands.WebRequestMethod] $Method = 'Get',
        [Hashtable] $Body
    )

    $GITHUB_API_URL = if ($env:GITHUB_API_URL) { $env:GITHUB_API_URL } else { "https://api.github.com" }
    $GITHUB_GRAPHQL_URL = if ($env:GITHUB_GRAPHQL_URL) { $env:GITHUB_GRAPHQL_URL } else { "https://api.github.com/graphql" }

    if ($Query -eq 'graphql') {
        $Url = "$GITHUB_GRAPHQL_URL"
    } else {
        $Url = "$GITHUB_API_URL/$Query"
    }

    $invokeRestMethodParms = @{
        'Headers' = @{
            # Authorization token is neeeded for posting comments and to increase limit of requests
            'Authorization' = "Bearer $env:GITHUB_TOKEN"
        }
        'Method'  = $Method
        'Uri'     = "$Url"
    }

    Write-Host 'GitHub Request' $invokeRestMethodParms -ForegroundColor DarkCyan

    if ($Body) { $invokeRestMethodParms.Body = ConvertTo-Json $Body -Depth 8 -Compress }

    Write-Host 'Request Body' $invokeRestMethodParms.Body -ForegroundColor DarkCyan

    $env:GH_REQUEST_COUNTER = ([int] $env:GH_REQUEST_COUNTER) + 1

    try {
        return Invoke-RestMethod @invokeRestMethodParms
    } catch {
        throw $_.Exception
    }
}

function pull_requests($json, [String] $app, [String] $upstream, [String] $manifest, [String] $commitMessage) {
    $version = $json.version
    $homepage = $json.homepage
    $branch = "manifest/$app-$version"
    $UpstreamRepoNwo, $UpstreamBranch = $Upstream -split ':'

    execute "git checkout $OriginBranch"
    # Detecting the existence of the "manifest/$app-$version" remote branch
    Write-Host "git ls-remote --exit-code origin $branch" -ForegroundColor Green
    git ls-remote --exit-code origin $branch

    # Skip if "manifest/$app-$version" remote branch already exists
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Skipping update $app ($version) ..." -ForegroundColor Yellow
        return
    }

    if ($env:CI -and $env:GITHUB_TOKEN) {
        Write-Host "Create remote branch 'manifest/$app-$version'" -ForegroundColor Green
        $ParentSHA = $((git ls-remote --refs --quiet origin $OriginBranch).Split()[0])
        $response = execute "Invoke-GithubRequest -Query 'repos/$UpstreamRepoNwo/git/refs' -Method Post -Body @{
            ref = 'refs/heads/$branch'
            sha = '$ParentSHA'
        }"
        if (!$response.ref) {
            error "Create remote branch 'manifest/$app-$version' via the GitHub API failed! (`n'$( $response | ConvertTo-Json -Depth 8 )'`n)"
            return
        }
        Write-Host "Creating and Pushing update $app ($version) via the GitHub GraphQL API ..." -ForegroundColor DarkCyan
        $response = execute "graphql_commit_push @{
            RepoNwo   = '$OriginRepoNwo'
            Branch    = '$branch'
            FilePath  = '$manifest'
            Title     = '$CommitMessage'
            ParentSHA = '$ParentSHA'
        }"
        if (!$response.data.createCommitOnBranch.commit.url) {
            error "Commit and push $app ($version) via the GitHub GraphQL API failed! (`n'$( $response | ConvertTo-Json -Depth 8 )'`n)"
            execute 'git reset'
            return
        }
    } else {
        execute "git checkout -b $branch"

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

    $response = execute "Invoke-GithubRequest -Query 'repos/$UpstreamRepoNwo/pulls' -Method Post -Body @{
        title = '$commitMessage'
        body  = @'
Hello lovely humans,
a new version of [$app]($homepage) is available.

| State       | Update :rocket: |
| :---------- | :-------------- |
| New version | $version        |
'@
        base  = '$UpstreamBranch'
        head  = '${OriginOwner}:${branch}'
    }"

    if (!$response.html_url) {
        execute 'git reset'
        abort "Pull Request failed! ( (`n'$( $response | ConvertTo-Json -Depth 8 )'`n)"
    }
}

function set_dco_signature {
    $CommitBot = ''
    $id = ''

    if ($env:GITHUB_TOKEN -like "ghp_*") {
        # https://github.blog/2021-04-05-behind-githubs-new-authentication-token-formats/
        # 'ghp_'开头的是 GitHub 个人访问令牌

        $response = Invoke-GithubRequest 'user'
    } elseif ($env:APP_SLUG) {
        $CommitBot = $env:APP_SLUG
    } else {
        $CommitBot = "github-actions"
    }

    if ($CommitBot) {
        $response = Invoke-GithubRequest "users/$CommitBot[bot]"
    }

    $CommitBot = $response.login
    $id = $response.id
    return "Signed-off-by: $CommitBot <$id+$CommitBot@users.noreply.github.com>"
}

function graphql_commit_push($params) {

    if (-not $Signedoffby) {
        $Signedoffby = set_dco_signature
    }
    if ($params.Body) {
        $params.Body +="`n"
    }
    $params.Body += "$Signedoffby"

    # Note that the line breaks in the cummitted file are LF style
    $EncodedFileContent = (Get-Content -Path $params.FilePath -Raw -Encoding UTF8) -replace "`r`n", "`n" | ForEach-Object { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_)) }

    $Body = @{
        query = "mutation (`$input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: `$input) { commit { url } } }"
        variables = @{
            input = @{
                branch = @{
                    repositoryNameWithOwner = $params.RepoNwo
                    branchName = $params.Branch
                }
                message = @{
                    headline = $params.Title
                    body = $params.Body
                }
                fileChanges = @{
                    additions = @(
                        @{
                            path = $params.FilePath
                            contents = $EncodedFileContent
                        }
                    )
                }
                expectedHeadOid = $params.ParentSHA
            }
        }
    }

    return Invoke-GithubRequest 'graphql' -Method 'Post' -Body $Body
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

git diff --name-only | ForEach-Object {
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
            if ($env:CI -and $env:GITHUB_TOKEN) {
                Write-Host "Creating and Pushing update $app ($version) via the GitHub GraphQL API ..." -ForegroundColor DarkCyan
                $response = execute "graphql_commit_push @{
                    RepoNwo   = '$OriginRepoNwo'
                    Branch    = '$OriginBranch'
                    FilePath  = '$manifest'
                    Title     = '$commitMessage'
                    ParentSHA = '$((git ls-remote --refs --quiet origin $OriginBranch).Split()[0])'
                }"
                if ($response.data.createCommitOnBranch.commit.url) {
                    execute "git fetch origin $OriginBranch"
                } else {
                    error "Commit and push $app ($version) via the GitHub GraphQL API failed! (`n'$( $response | ConvertTo-Json -Depth 8 )'`n)"
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

if ($Push -and !($env:CI -and $env:GITHUB_TOKEN)) {
    Write-Host 'Pushing updates ...' -ForegroundColor DarkCyan
    execute "git push origin $OriginBranch"
} else {
    Write-Host "Returning to $OriginBranch branch and removing unstaged files ..." -ForegroundColor DarkCyan
    execute "git checkout -f $OriginBranch"
}

execute "git reset --hard"
