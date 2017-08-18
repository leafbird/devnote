---
layout: post
title: "C++ 코드 정리 자동화 - 2. 불필요한 #include 찾기 下"
date: 2014-09-17 20:30:24 +0900
comments: true
tags: c++
---
[이전 포스트 'C++ 코드 정리 자동화 - 1. 불필요한 #include 찾기 上']({% post_url 2014-09-12-claenup-cpp-project-1st %})에서 이어진다.

## 지워도 되는 인클루드를 찾아냈다

개별 파일 하나씩을 컴파일 할 수 있다면 이제 모든 인클루드를 하나씩 삭제하면서 컴파일 가능 여부를 확인해보면 된다. 이 부분은 간단한 file seeking과 string 처리 작업일 뿐이니 굳이 부연 설명은 필요 없다. 카페에서 여유롭게 음악을 들으며 즐겁게 툴을 만들자. 뚝딱뚝딱.

이정도 하고 나니 이제 vcxproj파일 경로를 주면 해당 프로젝트에 들어있는 소스코드에서 불필요한 인클루드를 색출해 위치정보를 출력해주는 물건이 만들어졌다.

```
작업 대상으로 1개의 프로젝트가 입력 되었습니다.
-------------------------------------------------
Service : 프로젝트 정리.
Service : PCH 생성.
컴파일 : stdafx.cpp ... 성공. 걸린 시간 : 1.04초
Client.cpp의 인클루드를 검사합니다.
 - process #1 Client.cpp (1/2) ... X
 - process #1 Client.cpp (2/2) ... X
ClientAcceptor.cpp의 인클루드를 검사합니다.
 - process #1 ClientAcceptor.cpp (1/2) ... 컴파일 가능!
 - process #1 ClientAcceptor.cpp (2/2) ... X
ClientConnection.cpp의 인클루드를 검사합니다.
 - process #1 ClientConnection.cpp (1/3) ... X
 - process #1 ClientConnection.cpp (2/3) ... X
 - process #1 ClientConnection.cpp (3/3) ... X
Start.cpp의 인클루드를 검사합니다.
 - process #1 Start.cpp (1/4) ... X
 - process #1 Start.cpp (2/4) ... X
 - process #1 Start.cpp (3/4) ... X
 - process #1 Start.cpp (4/4) ... X
ThreadEntry.cpp의 인클루드를 검사합니다.
 - process #1 ThreadEntry.cpp (1/1) ... X
-------------------------------------------------
Project : Service 모두 1개의 인클루드가 불필요한 것으로 의심됩니다.
D:\Dev\uni\World\Service\ClientAcceptor.cpp
 - 2 line : #include "World/Service/Client.h"

총 소요 시간 : 13.289 sec
```

이 정도 만들어서 회사에서 만들고 있는 프로젝트에 조금 돌려 보았는데, **덕분에 꽤나 많은 불필요 인클루드를 색출해 내었다.** 회사 프로젝트는 덩치가 제법 크고, 아직 서비스 중이지 않은 코드여서 용감무쌍한 리팩토링이 자주 일어나기 때문에 관리가 잘 안되는 파일이 제법 있더라. 아무튼 덕을 톡톡히 보았다.

## 튜닝 : 솔루션 단위로 검사할 수 있게 만들자

프로젝트 파일 단위로 어느 정도 돌아가니까, 솔루션 파일 단위로도 돌릴수 있게 확장했다. sln 파일을 파싱해서 프로젝트 리스트만 얻어오면 끝나는 일이다. 

하지만 sln 파일은 vcxproj 파일처럼 쉽게 파싱할 수는 없다. 이녀석은 xml 포맷이 아니라, 자체적인 포맷을 가지고 있다. 사실 sln 파일을 파싱해 본 게 이번이 처음이 아닌데, 예전에는 lua를 써서 직접 노가다 파싱을 했더니 별로 재미도 없고 잘 돌아가지도 않고 코딩하는 재미도 별로 없더라. 

```
 // 솔루션 파일은 이렇게 생겼다. 왜죠...

Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio 2013
VisualStudioVersion = 12.0.30723.0
MinimumVisualStudioVersion = 10.0.40219.1
... 중략 ...
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "External", "External", "{F95C61E3-AF95-4CA9-8837-A203762B2B29}"
EndProject
Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "gtest", "External\gtest\gtest.vcxproj", "{C7A81BFC-6E28-4859-A8B5-2FEA80E012B2}"
EndProject
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "Test", "Test", "{042F2157-2118-44AA-8BB9-8B5DD01FA3A9}"
EndProject
Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "unittest", "Test\unittest.vcxproj", "{24A57754-D332-4575-AEBF-2AFCBC0A7E4B}"
EndProject
... 후략 ...
```

C#으로 sln 파일을 파싱해주는 적당히 괜찮은 코드가 인터넷 어딘가에 돌아다닌다. [이곳](http://stackoverflow.com/questions/707107/library-for-parsing-visual-studio-solution-files)에 있는 놈을 가져다 붙였다. build configuration 같은 걸 얻어올 순 없지만 프로젝트 리스트 얻는 데에는 충분하다.

## 튜닝 : 느리다. 멀티 스레드로 돌리자

한때는 툴을 만들때 lua도 써보고 python도 써봤지만 요즘은 C#만 쓰게된다. 디버깅 하기도 편하고, **특히 멀티스레딩으로 돌리기가 너무 편하다.** TPL, Concurrent Collection조금 갖다 끄적거리면 금방 병렬처리된다.

특히나 이런 식으로 병렬성이 좋은 툴은 훨씬 빠르게 돌릴 수 있게 된다. 커맨드 라인 인자로 `--multi-thread`를 주면 주요 작업을 `Parallel.ForEach`로 돌리도록 처리했다. 다만 멀티스레드로 돌리면 파일로 남기는 로그가 엉망이 되기 때문에... 단일 스레드로도 돌 수 있도록 남겨둠. 

이번엔 병렬처리할 때 thread-safe한 container가 필요했는데, [System.Collections.Concurrent](http://msdn.microsoft.com/ko-kr/library/system.collections.concurrent.aspx)에 가면 queue, stack, dictionary등 종류별로 잔뜩 들어있으니 적당한 놈으로 바로 갖다 쓰면 된다. 편하다 C#. 네이티브 코더는 그냥 웁니다 ㅠㅠ...

지금 내가 가진 개인 코드 중에는 덩치큰 cpp 프로젝트가 없어서, 조그만 솔루션 하나 시험삼아 돌려봤다.

{% img center /images/140917_00.PNG %}

87초 걸리던 것이 24초로 빨리짐. 대충 4배 가량 빨라졌다. 내일 회사에서 대빵 큰 프로젝트에 한 번 돌려봐야지. 생각하니 기대된다.

## More Improvement : 불필요한 전방선언(forward declaration) 색출.

툴을 좀 더 확장할 수 있을거 같다. 클래스와 구조체 전방선언을 써놓고 지우지 않아서 찌꺼기가 된 부분을 이것으로 찾아낼 수 있을 것 같다. 이건 파일을 일일이 컴파일 하지 않아도 되니까 훨씬 빠르게 가능할 듯.

전방선언 확인 작업도 따지고 보면 단순 string 처리니까... 시간될 때 카페에 가서 찬찬히 코딩하다보면 금방 짤 수 있겠지. cpp 파일을 write하는 작업도 없어서 read만 하면 되기 때문에 아마 병렬성도 훨씬 더 좋을 것이다.  
