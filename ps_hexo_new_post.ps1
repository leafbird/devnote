# 환경변수 BLOG_PATH에 설정된 블로그 root 경로로 이동
cd $env:blogpath

#input으로 새 글의 제목을 받는다. 
$title = Read-Host 'Enter Title'

# 실행 : hexo new draft '제목'
$command = [string]::Format('hexo new draft "{0}"', $title)
$out = Invoke-Expression $command

# 생성된 파일의 이름과 경로를 추출한다.
$out = $out.Replace("INFO  Created: ", "")

# 생성된 파일을 gvim으로 오픈!
$new_file_path = [System.IO.Path]::Combine($PSScriptRoot, $out)
gvim.exe $new_file_path
