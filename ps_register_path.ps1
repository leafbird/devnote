# 현재 스크립트의 실행 경로를 얻는다.
$blog_path = (Get-Item -Path ".\" -Verbose).FullName

# 경로 확인
"blog path : $blog_path"

# 실행 경로를 환경변수에 등록(유저 레벨)
[Environment]::SetEnvironmentVariable("blogpath", $blog_path, "User")

# output result
"Environment Variable update. {0} = {1}" -f "blogpath", $blog_path

# pause
Write-Host "Press any key to continue ..."
$x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
