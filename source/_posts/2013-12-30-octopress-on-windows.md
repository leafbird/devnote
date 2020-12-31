---
layout: post
title: "octopress on windows"
date: 2013-12-30 23:06:15 +0900
comments: true
tags: [octopress, windows, encoding]
---

{% img center /images/octopress.jpeg %}

octopress도 대게는 ruby가 기본 설치된 mac에서 많이들 사용하는 듯 하다. 검색해보면 대부분 OS X를 기준으로 한 셋팅법이다. 윈도우에서 사용하는 것도 많이 어렵진 않지만 **한글 인코딩 때문에 많이 헤맸음 ㅜㅠ**...

일단 기본적으로 아래 두 개의 글을 참고해 설치했는데,

1. http://stb.techelex.com/setup-octopress-on-windows7/
2. http://chulhankim.github.io/blog/2013/07/31/octopress-and-github.html

ruby는 생소한 언어이기도 하고 링크가 사라지면 다시 헤맬수도 있으니 간략하게 다시 정리.

<!-- more -->

# Ruby 설치

일단 윈도우에는 Ruby가 없기 때문에 먼저 설치를 해야 한다.
[다운로드 페이지](http://rubyinstaller.org/downloads/)에서 Ruby와 DevKit을 다운받는다. 
내가 사용한 버전은 Ruby 2.0.0-p353 (x64)와 DevKit-mingw64-64-4.7.2-20130224-1432-sfx.exe

DevKit을 사용하기 전에 install 과정이 필요하다. 이 단계를 실행하기 전에 ruby의 bin 폴더가 path에 잡혀 있는 것이 좋다. 그러면 DevKit 초기화 과정에서 ruby의 경로를 알아서 감지하므로, config.yml을 수정할 필요가 없다. 

```bash
cd C:/RubyDevKit
ruby dk.rb init # 이 때 config.yml이 생김. 이 전에 ruby bin을 path에 넣자.
ruby dk.rb install
```

# python 설치

python은 없어도 상관없다. 하지만 syntax highlighting을 하려거든 python이 필요하다. 이것도 OS X는 기본 설치되어 있어서 크게 이슈가 없는듯. 나는 한참 써보다가 알았는데, 나중에 python을 설치하면 [뭔가 더 해주어야 하는 것 같아 귀찮다](https://github.com/imathis/octopress/issues/262). 그냥 처음부터 python을 설치해놓고 path에 python이 포함되도록 해두는게 좋겠다. 

# Octopress 받기

```bash
cd c:/github
git clone git://github.com/imathis/octopress.git octopress 
cd octopress      #replace octopress with username.github.com  
ruby --version  # Should report Ruby 1.9.3
```

ruby 패키지들 (dependencies) 설치:

```bash
cd c:/github/octopress       #replace octopress with username.github.com
gem install bundler
bundle install
```
octporess의 기본 테마 설치:

```bash
$ rake install
```

이부분에서 말을 안들을 수가 있는데, 뭔가 모듈의 버전이 맞지 않는 문제다.

```bash
  D:\Blog\DevNote>rake install
  rake aborted!
  You have already activated rake 0.9.6, but your Gemfile requires rake 0.9.2.2. P
  repending `bundle exec` to your command may solve this.
  D:/Blog/DevNote/Rakefile:2:in `<top (required)>'
  (See full trace by running task with --trace)
```

이 때 `bundle update rake` 해주면 해결. [다음 글을 참고했다.](http://stackoverflow.com/questions/6080040/you-have-already-activated-rake-0-9-0-but-your-gemfile-requires-rake-0-8-7)

```bash
D:\Blog\DevNote>bundle update rake
Fetching gem metadata from https://rubygems.org/.......
Fetching additional metadata from https://rubygems.org/..
Resolving dependencies...
Using rake (0.9.6)
...(중략)...
Your bundle is updated!
```

# Octopress를 Github Pages용으로 설정

```bash
    $ rake setup_github_pages
```

Github Pages는 계정 페이지와 프로젝트 페이지로 나뉜다.
각각의 경우에 따라 수동설정을 해주어야 하는데(이 부분은 두 번째 글에 잘 설명되어 있다.), 프로젝트 페이지의 경우가 조금 더 손댈 곳이 많다.

* 계정 페이지 설정인 경우

`_config.yml`에서 url, title, subtitle, author 정도만 수정해주면 된다.

* 프로젝트 페이지 설정의 경우

먼저 `git remote` 추가.

```bash
  $ git remote add origin `https://github.com/username/projectname.git
  $ git config branch.master.remote origin
```

`_config.yml, config.rb, Rakefile` 을 열어서 `/github`라고 된 부분을 repository 명으로 수정.

# 한글 인코딩 문제 해결

이제 부푼 꿈을 안고 첫 포스팅을 만들어보면 잘 동작한다. 
하지만.. 한글을 사용하면 다시 인코딩 관련 에러를 만나게 된다. 
**여기서 엄청난 시간을 소모**했는데, octopress 안에서 해결을 보려고 하니 힘들다. ruby는 한 번도 안써봐서 코드 보기도 힘들고 ㅡㅠ...
[검색해보면](http://www.qstata.com/blog/2013/06/20/rake-generate-utf-8-errors-on-windows/) jekyll 코드 일부를 직접 수정하는 방법도 있는데,
그것보다 cmd창의 코드 페이지를 변경해주면 간단하게 해결된다. 

```bash
    chcp 65001 # 다시 되돌리려면 chcp 949
```

`rake generate`를 하거나 `rake preview`를 하기 전에, 코드페이지를 항상 변경해주고 실행한다. batch파일을 미리 만들어두니 편하다.

markdown 문법은 [검색하면](https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet) 어렵지 않게 찾을 수 있다. 

# 블로그 내부 링크 만들기

기본으로 제공되는 기능이 없는듯? 플러그인 폴더에 아래 파일 하나 넣어주어야 한다.

* https://github.com/michael-groble/jekyll/blob/master/lib/jekyll/tags/post_url.rb

[여기](http://kqueue.org/blog/2012/01/05/hello-world/#internal-post-linking) 에서 참고했다. 아래 문법을 사용한다.

```
[link to this post]({% post_url 2012-01-05-hello-world %})
```

eof.

