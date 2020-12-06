function Get-ScriptDirectory {
    if ($psise) {
        Split-Path $psise.CurrentFile.FullPath
    }
    else {
        $global:PSScriptRoot
    }
}

Get-ScriptDirectory | Set-Location

#input으로 새 글의 제목을 받는다. 
$title = Read-Host 'Enter Title'

# 실행 : hexo new draft '제목'
hexo new draft "$title"

$fileName = $title.Replace(' ', '-')
# 생성된 파일을 gvim으로 오픈
$newFilePath = Join-Path .\source\_drafts "$fileName.md"
Write-Output "Open gvim $newFilePath"
gvim.exe $newFilePath
