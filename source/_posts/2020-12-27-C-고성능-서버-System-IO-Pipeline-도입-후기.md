---
title: C# 고성능 서버 - System.IO.Pipeline 도입 후기
date: 2020-12-27 17:34:58
tags: c#, 고성능, 게임서버, Network, Socket, Pipeline
---
{% asset_img 00.jpg %}

## 들어가며

2018년에 네트워크 레이어 성능을 끌어올리기 위해 도입했었던 System.IO.Pipeline을 간단히 소개하고, 도입 후기에 대해 적어본다. 

윈도우 OS에서 고성능을 고려한 소켓 프로그래밍을 하고자 할 때 IOCP api는 오래도록 변하지 않는 정답의 자리를 유지하고 있다. 여기에서 좀 더 성능에 욕심을 내고자 한다면 Windows Server 2012부터 등장한 [Registerd IO](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/hh997032(v=ws.11)) 라는 새로운 선택지가 있다. 하지만 API가 C++ 로만 열려 있어서, C# 구현에서는 사용하기가 쉽지 않다. 

하지만 C#에도 고성능 IO를 위한 새로운 API가 있다. [Pipeline](https://docs.microsoft.com/ko-kr/dotnet/standard/io/pipelines) 이다.



## System.IO.Pipeline 소개.

pipeline을 처음 들었을 때는 IOCP의 뒤를 잇는 새로운 소켓 API인줄 알았다. C++의 RIO가 iocp를 완전히 대체할 수 있는 것처럼.

RIO는 가장 핵심 요소인 `등록된 버퍼(registered buffer)` 와 함께, 새로운 IO 요청방식 및 완료 통지 방식을 모두 제공하여 iocp를 완전히 대체할 수 있는 api다. 이벤트 통지 모델은 iocp를 이용하고 버퍼 작업만 RIO를 적용할 수도 있다. 하지만 이것은 적용상황에 따라 선택할 수도 있는 옵션의 하나일 뿐이고, 최적의 성능을 위해서는 RIODequeueCompletion을 이용하는 것이 권장된다.

반면 Pipeline은 RIO보다는 커버하는 범위가 더 좁아서, IOCP를 완전히 대체하는 물건은 아니다. 이벤트 통지 모델은 기존의 방식들을 그대로 이용하면서, 오직 버퍼의 운용 방식만을 담당하는 라이브러리기 때문에 IOCP와 반드시 함께 사용해야 한다. 



## 장점 : 효율적인 버퍼 운용. 

## 단점 : 너무 많은 waiting task	

## 마치면서



참고

* https://www.slideshare.net/sm9kr/windows-registered-io-rio
* https://docs.microsoft.com/ko-kr/dotnet/standard/io/pipelines