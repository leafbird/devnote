---
title: '[pwsh] PsFzf가 프로필 로딩을 너무 느리게 만든다'
date: 2025-02-01 13:45:31
tags:
- powershell
- fzf
---


{% asset_img psfzf_00.png %}

매번 터미널을 열 때마다 2 ~ 3초가 걸리는 것은 부담스럽다. 

방법을 찾아야 한다.

<!--more-->

기존에 사용하던 프로필은 아래와 같다. 

```pwsh
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\atomic.omp.json" | Invoke-Expression

# 실행시간이 너무 길어서 제거
# neofetch

# Ensure posh-git module is installed and loaded
if (-not (Get-Module -ListAvailable -Name PsFzf)) {
    Install-Module -Name PsFzf -Scope CurrentUser -Force
}

Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
Set-PsFzfOption -TabExpansion

# replace 'Ctrl+t' and 'Ctrl+r' with your preferred bindings:
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'

# Ensure posh-git module is installed and loaded
if (-not (Get-Module -ListAvailable -Name posh-git)) {
    Install-Module -Name posh-git -Scope CurrentUser -Force
}
Import-Module -Name posh-git
```

기존에도 이미 간지를 위해 호출하던 `neofetch`를 시간이 너무 오래 걸리는 문제 때문에 포기하고 있었는데

이제 다른 처리만 해도 너무 답답한 로딩시간이 되었다. 

### 원인 확인

우선은 각 줄마다 `Write-Host` 찍으면서 수행시간을 확인해보았다. Import-Module이나 Get-Module이 오래 걸리는게 아닐까 생각했는데

가장 오래 걸리는 것은 line 11, `Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }` 이었다.

PsFzf는 명시적으로 `Import-Module`하지 않더라도, fzf관련 기능이 처음 호출되는 순간 자동으로 모듈이 로드된다. 

line 11이 그 자체로 오래 걸리는 것이 아니라, 가장 처음 수행하는 fzf 설정이기 때문에 implicit하게 모듈을 임포트하는 시간이 발생했기 때문이다. 실제로 앞에서 미리 명시적으로 `Import-Module`을 수행하면 로딩시간이 줄어든다.

### 해결

해결이라기 보단 타협에 가까운데, 매번 초기화 하지 않는 대신 필요한 경우 쉽게 초기화할 수 있게 준비만 해두는 식으로 처리했다.

* 매번 터미널이 뜰 때마다 모듈을 임포트하지 않게 한다. 
* 대신 필요한 경우 설정 함수를 불러 간단하게 셋업되도록 한다.

변경된 스크립트는 아래와 같다. 

```pwsh
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\atomic.omp.json" | Invoke-Expression

$script:enableFzf = $false

function Enable-Fzf {
    if ($script:enableFzf) {
        Write-Host "Fzf가 이미 활성화되어 있습니다."
        return
    }

    $script:enableFzf = $true

    $script:stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    if (-not (Get-Module -ListAvailable -Name PsFzf)) {
        Write-Host "PsFzf 모듈을 설치합니다..."
        Install-Module -Name PsFzf -Scope CurrentUser -Force
    }

    Write-Host "탭 완성을 위한 설정을 추가합니다..."
    Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
    Set-PsFzfOption -TabExpansion

    Write-Host "Ctrl+t / Ctrl+r 키 입력을 설정합니다..."
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'

    # Ensure posh-git module is installed and loaded
    if (-not (Get-Module -ListAvailable -Name posh-git)) {
        Write-Host "posh-git 모듈을 설치합니다..."
        Install-Module -Name posh-git -Scope CurrentUser -Force
    }

    Write-Host "posh-git 모듈을 로드합니다..."
    Import-Module -Name posh-git

    Write-Host "Fzf 활성화가 완료되었습니다."
    $script:stopwatch.Stop()
    Write-Host "소요 시간: $($script:stopwatch.ElapsedMilliseconds)ms"
}
```

oh-my-posh 초기화 외에는 모두 함수로 묶어두기만 했다. 

터미널 사용 도중 fzf 기능이 필요한 경우는 `Enable-Fzf` 함수를 호출한다. history에 들어 있으므로 `ena + →`만 입력해도 호출 가능하다. 

file scope의 변수를 추가해서 여러 번 초기화 함수를 부를 땐 중복 실행하지 않게 막았다.

{% asset_img psfzf_01.png %}

짠. 이제 새 터미널 창 여는 시간이 쾌적해졌다 :)