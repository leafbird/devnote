---
layout: post
title: "Octopress Tips on windows"
date: 2014-07-21 16:44:48 +0900
comments: true
tags: [octopress, windows]
---

개인적으로 Octopress를 윈도우에서 사용하도록 구성하면서 도움이 되었던 팁들을 몇가지 정리해 보려고 합니다. 
앞으로 계속 사용해 가면서 추가적인 팁이 생길 때에도 이 포스팅에 업데이트 할 생각이예요. 

<!-- more -->

## 윈도우 실행 (Windows + R) 창에서 블로그 패스로 바로 이동 하기

{% img center /images/140721_00.png %}

이거야 뭐... 환경변수에 블로그 경로를 넣어주면 된다. 이렇게 하면 실행 창에 `%변수이름%`만 입력하면 바로 탐색기를 열 수 있다. 
환경 변수 설정을 해주는 PowerShell 스크립트를 만들어서 블로그 폴더의 루트에 놔두면 경로를 옮기거나 depot을 새로 받아도 편하게 셋팅할 수 있다. 

{% codeblock ps_register_path.ps1 lang:powershell https://github.com/leafbird/devnote/blob/master/ps_register_path.ps1 code from github %}
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
{% endcodeblock %}


## %blogpath% 이외에 자주 접근하는 경로는 바로가기를 만든다

{% img center /images/140721_01.PNG %}

octopress를 쓰면서 커맨드를 실행하는 주된 경로는 root path다. 이외에도 첨부파일 경로나 글 본문을 저장하는 `./source/_posts` 등이 흔히 쓰이는데, 이런 경로에 대한 .lnk 파일을 만들어두면 훨씬 편하다.
위 스샷처럼 바로가기를 만들어두고 `po`정도 타이핑하고 엔터하면 `./source/_posts`로 이동한다.

나는 탐색기를 주로 이용하고자 이렇게 했지만 cmd창에서 바로가기 하고 싶다면 symbolic link를 만들면 될거다. 

웹페이지 바로가기도 만들어 두면 편하게 이동 가능. (웹 바로가기는 .url 확장자. 브라우저 주소창에서 슥 끌어다 놓으면 생김)


## 자주 쓰는 동작들은 스크립트로 자동화한다

{% img center /images/140721_02.PNG %}

**Note : 이 항목이 이 포스팅의 핵심 입니다.**

Octopress를 쓰면서 마음에 드는 점 중에 하나인데, 마음만 먹으면 조작 과정을 내맘대로 스크립팅할 수 있다는 점이다.
처음 octopress를 이용하려면 갖가지 명령어들을 일일이 숙지하고 사용하기가 불편한 것이 사실이지만,
batch파일과 PowerShell을 통해서 얼마든지 내 입맛대로 자동화 할 수 있다. 
PowerShell을 한 번 다뤄보고 싶었지만 딱히 기회가 없었는데 이참에 다뤄보게 되어 재미있었다. 
지금은 몇 개 안되긴 하지만 개인적으로 만들어 사용중인 스크립트들은 http://github.com/leafbird/devnote/ 에서 확인할 수 있다. 

예제로 한 가지만 살펴보자.


### 자동화 예시 : 새글 작성을 간편하게

ocotpress에서 새 글을 적으려면 아래의 순서대로 실행해야 한다. 

 1. blog path로 이동.
 1. cmd창 오픈
 1. `rake new_post['포스팅 제목']` 명령 실행
 1. `./source/_posts`로 이동
 1. 자동으로 생성된 .markdown 파일을 찾아서 오픈
 1. 글 작성 시작

이 절차를 아래처럼 PowerShell로 스크립팅한다.

{% codeblock lang:powershell ps_rake_new_post.ps1 %}
# 환경변수 BLOG_PATH에 설정된 블로그 root 경로로 이동
cd $env:blogpath

#input으로 새 글의 제목을 받는다. 
$title = Read-Host 'Enter Title'

# 실행 : rake new_post['제목']
$argument = [string]::Format("new_post[{0}]", $title)
$out = rake.bat $argument

# 생성된 파일의 이름과 경로를 추출한다.
$out = $out.Replace("Creating new post: ", "")

# 생성된 파일을 gvim으로 오픈!
$new_file_path = [System.IO.Path]::Combine($PSScriptRoot, $out)
gvim.exe $new_file_path
{% endcodeblock %}

커맨드 창에 `PowerShell ./ps_rake_new_post.ps1` 입력하는 것도 귀찮으니 이것도 batch파일로 만들자.

{% codeblock lang:bat 02_ps_rake_new_post.bat %}
@echo off
powershell ./ps_rake_new_post.ps1
{% endcodeblock %}

이제 이 batch를 실행해서 새 글 제목을 입력하면 에디터까지 자동으로 열린다. 


## git conflict : 여러 머신에서 하나의 블로그에 번갈아 포스팅 하는 경우 

git을 사용할 때 불편한 점 중의 하나가 머지(merge)다. 여러 머신을 사용할 경우엔 다른 곳에서 수정했던 사항을 미리 pull 받고 난 후 작업해야 하는데, 이걸 혹시나 깜박 잊고 새 글을 써서 generate했다면 conflict 대 참사가 일어난다. 

blog root경로는 보통의 git repository를 사용하는 것과 유사하기 때문에 큰 문제가 없는데 `_deploy`폴더가 문제다. 이 폴더는 블로그 엔진이 generate한 블로그 리소스를 배포하기 위해 사용하는데, 실제로는 `gh-pages` 브랜치의 clone이기 때문이다. 그래서 서로 다른 여러 개의 depot clone을 가지고 블로깅을 할 땐 blog root와 함께 `_deploy`도 함께 `git pull` 해주어야 문제가 없다. 

하지만 `_deploy`폴더는 굳이 동기화까지 받을 필요는 없다. 어차피 블로그 엔진이 배포하는 과정에서 새로 만들기 때문이다.
어떻게 활용하든 상관없지만 만약 `_deploy`폴더가 충돌이나서 html파일을 한땀 한땀 머지해야 하는 상황이 되었다면 주저없이 삭제해 버리고 새로 만들자.

```
cd %blogpath%
rmdir /s /q _deploy
mkdir _deploy
cd _deploy
git init
git remote add origin https://....
git pull
git check --track origin/gh-pages
```
