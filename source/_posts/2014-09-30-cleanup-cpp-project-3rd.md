---
layout: post
title: "C++ 코드 정리 자동화 - 3. pch 사이즈 확인, #include 순서정리"
date: 2014-09-30 15:17:15 +0900
comments: true
tags: c++
---

## pch 파일 사이즈

팀에서 만지는 코드에서는, 290Mb에 육박하는 pch파일을 본 적이 있다(...) 그 땐 코드를 정리하면서 pch 사이즈 변화를 자주 확인해봐야 했는데, 탐색기나 커맨드 창에서 매번 사이즈를 조회하기가 불편했던 기억이 있어서 pch 사이즈 확인하는 걸 만들어봤다.



<!--more-->

MSBuild로 단일 cpp 파일을 컴파일하면 이런 메시지가 나오는데,

```
C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\bin\amd64\CL.exe 
/c 
/ID:\Dev\uni\External\ 
/ID:\Dev\uni\Test\ 
/ID:\Dev\uni\ 
/Zi 
/nologo 
/W4 
/WX 
/sdl 
/Od 
/D WIN32 
/D _DEBUG 
/D _CONSOLE 
/D _LIB 
/D _UNICODE 
/D UNICODE 
/Gm 
/EHsc 
/RTC1 
/MDd 
/GS 
/fp:precise 
/Zc:wchar_t 
/Zc:forScope 
/Yc"stdafx.h" 
/Fp"x64\Debug\unittest.pch" 
/Fo"x64\Debug\\" 
/Fd"x64\Debug\vc120.pdb" 
/Gd 
/TP 
/errorReport:queue 
stdafx.cpp
```

여기 `cl.exe`로 들어가는 인자 중에 `/Fp"x64\Debug\unittest.pch"` 요 부분에 pch 경로가 있음. 그러니까 결국 툴에서 pch사이즈를 구하려면

1. 프로젝트 리빌드하고
2. pch 생성 헤더를 cl.exe로 컴파일하면서 /Fp 스위치를 읽어 경로 파악.
3. 위에서 새로 생성된 pch파일의 사이즈를 확인.

... 해주면 된다.

## #include 순서 자동 정렬

구글의 C++ 스타일 가이드 문서 중에 [include 의 이름과 순서](http://jongwook.github.io/google-styleguide/trunk/cppguide.xml#include%EC%9D%98_%EC%9D%B4%EB%A6%84%EA%B3%BC_%EC%88%9C%EC%84%9C) 항목에 보면 헤더 인클루드에 몇가지 카테고리와 순서를 정해 두었는데, 

{% blockquote %}
주된 목적이 dir2/foo2.h에 있는 것들을 구현하거나 테스트하기 위한 dir/foo.cc나 dir/foo_test.cc에서 include를 아래처럼 순서에 따라 배열하라.

1. dir2/foo2.h (아래 설명 참조).
2. C 시스템 파일
3. C++ 시스템 파일
4. 다른 라이브러리의 .h 파일
5. 현재 프로젝트의 .h 파일
{% endblockquote %}

팀에서 정한 컨벤션도 이 규칙을 그대로 따라야 해서.. 매번 코딩할 때마다 인클루드 순서에 신경쓰기 싫어서 자동화 처리를 작성. 더불어 경로 없이 파일명만 적은 경우나 상대경로를 사용한 인클루드도 지정된 path를 모두 적어주도록 컨버팅하는 처리도 만듦. 만드는 과정이야 대단한 건 없다. sln, vcxproj파일 파싱하는 것은 만들어 두었으니, 그냥 스트링 처리만 좀 더 해주면 금방 만들어진다. 툴로 sorting하고나면 아래처럼 만들어줌.

``` cpp TestCode.cpp
#include "stdafx.h"
#include "TestAsset/ProjRoot/TestCode.h"

// system headers
#include <vector>

// other project's headers
#include "TestAsset/OuterProject.h"
#include "TestAsset/OuterProjectX.h"

// inner project's headers
#include "TestAsset/ProjRoot/InterProject.h"
#include "TestAsset/ProjRoot/InterProjectA.h"
#include "TestAsset/ProjRoot/InterProjectB.h"
#include "TestAsset/ProjRoot/InterProjectC.h"

void main() {
  return;
}
```

## epilog

대충 이정도 돌아가는 툴을 만들어서 개인 pc에 셋팅해둔 jenkins에 물려놓고 사용중. 원래는 필요없는 include찾아주는 기능만 만들려다가 include sorting 기능은 그냥 한 번 추가나 해볼까 싶어 넣은건데, 아주 편하다. 코딩할 땐 순서 상관 없이 상대경로로 대충 넣어놓고 툴을 돌리면 컨벤션에 맞게 예쁘게 수정해준다.

불필요 인클루드를 찾는 동작은 회사 코드 기준으로 컨텐츠 코드 전체 검색시 50분 정도 걸리는 듯. 이건 매일 새벽에 jenkins가 한 번씩 돌려놓게 해놓고, 매일 아침에 출근해서 확인한다.

pch사이즈는 baseline 구축을 생각하고 만들어 본건데.. (박일, [사례로 살펴보는 디버깅](http://www.slideshare.net/parkpd/in-ndc2010) 참고) baseline을 만들려면 지표들을 좀 더 모아야 하고, db도 붙여야 하니 이건 제대로 만들려면 시간이 필요할 것 같다(..라고 쓰고 '더이상 업데이트 되지 않는다' 라고 읽는다.)

### 그리고 C#.

C#은 재미있다. 이번에 툴 만들때도 한참 빠져들어서 재미있게 만들었다. Attribute를 달아서 xml 파일을 자동으로 로딩하는 처리를 만들어 보았는데, cpp에서 하기 힘든 깔끔한 이런 가능성들이 마음에 든다. 규모 큰 프로젝트는 안해봐서 모르겠지만 개인적으로 가지고 놀기에는 제일 맘에 듬. 디버깅 하기 좋고 코드 짜기도 좋고.

### Visual Stuio Online

코드 관리를 [visual studio online](http://www.visualstudio.com/en-us/products/what-is-visual-studio-online-vs.aspx)에서 해봤다. 비공개 코드는 주로 개인 Nas나 bitbucket에 올려놓는데, VS IDE에서 링크가 있길래 한 번 눌러봤다가 한 번 써봄. 
bitbucket보다 좀 더 많은 기능이 있다. 빌드나 단위테스트를 돌려볼 수 있고(하지만 유료), backlog, splint관리용 보드가 좀 더 디테일하다. 개인 코딩 말고 팀을 꾸려서 작업을 한다면 한 번 제대로 사용해 보는 것을 고려해 볼 순 있겠으나... 왠지 그냥 마음이 안간다. 나같으면 그냥 github 유료 결제해서 쓸 거 같애 'ㅅ')


이제 이건 고마하고 다음 toy project로 넘어가야지.
