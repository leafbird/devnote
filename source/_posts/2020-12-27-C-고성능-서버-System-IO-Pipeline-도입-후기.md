---
title: C# 고성능 서버 - System.IO.Pipeline 도입 후기
date: 2020-12-27 17:34:58
tags: c#, 고성능, 게임서버, Network, Socket, Pipeline
---
{% asset_img 00.jpg %}

## 들어가며

2018년에 네트워크 레이어 성능을 끌어올리기 위해 도입했던 System.IO.Pipeline을 간단히 소개하고, 도입 후기를 적어본다. 

윈도우 OS에서 고성능을 내기 위한 소켓 프로그래밍을 할 때 IOCP 의 사용은 오래도록 변하지 않는 정답의 자리를 유지하고 있다. 여기에서 좀 더 성능에 욕심을 내고자 한다면 Windows Server 2012부터 등장한 [Registerd IO](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/hh997032(v=ws.11)) 라는 새로운 선택지가 있다. 하지만 API가 C++ 로만 열려 있어서, C# 구현에서는 사용하기가 쉽지 않다. 

하지만 C#에도 고성능 IO를 위한 새로운 API가 있다. [Pipeline](https://docs.microsoft.com/ko-kr/dotnet/standard/io/pipelines) 이다.



## System.IO.Pipeline 소개.

pipeline을 처음 들었을 때는 IOCP의 뒤를 잇는 새로운 소켓 API인줄 알았다. C++의 RIO가 iocp를 완전히 대체할 수 있는 것처럼.

RIO는 가장 핵심 요소인 `등록된 버퍼(registered buffer)` 외에도, 새로운 IO 요청 및 완료 통지 방식을 모두 제공하기 때문에 iocp를 완전히 대체할 수 있는 api다. 사용하기에 따라서 이벤트 통지 모델은 iocp를 그대로 이용하고 버퍼 작업만 RIO를 적용할 수도 있다. 하지만 이것은 필요에 따라 선택 가능한 옵션의 하나일 뿐이고, RIO 최적의 성능을 위해서는 RIODequeueCompletion을 이용하는 것이 권장된다. (보다 추가적인 정보는 승모님의 [자료](http://www.slideshare.net/sm9kr/windows-registered-io-rio)와 [소스코드](https://github.com/zeliard/RIOTcpServer)를 참고)

반면 Pipeline은 RIO보다는 커버하는 범위가 더 좁아서, IOCP를 완전히 대체하는 물건은 아니다. 이벤트 통지 기존의 방식들을 그대로 이용하면서, 메모리 버퍼의 운용만을 담당하는 라이브러리 이기 때문에 IOCP와 반드시 함께 사용해야 한다.

Pipeline이라는 이름을 굉장히 잘 지었다. 이름처럼 **메모리 버퍼를 끝없이 연결된 긴 파이프라인처럼 운용해주는 라이브러리** 이기 때문이다. 단위길이 만큼의 버퍼를 계속 이어붙여서 무한하게 이어진 가상의 무한길이 버퍼를 만드는데, 이걸 너네가 만들면 시간도 오래 걸리고 버그도 넘나 많을테니 우리가 미리 만들었어. 그냥 가져다 쓰렴. 하고 내놓은 것이 Pipeline이다.

{% asset_img 01.png %}

(이미지 출처 : [devblogs.microsoft.com](https://devblogs.microsoft.com/dotnet/system-io-pipelines-high-performance-io-in-net/))

이미지의 초록색 부분은 `class Pipe` 의 내부 구조를 도식화한다. 일정한 크기의 작은 버퍼들이 링크드 리스트로 연결 되어있다. 내부 구조는 안에 숨겨져있고 외부로는 [ReadOnlySequence<T>](https://docs.microsoft.com/ko-kr/dotnet/api/system.buffers.readonlysequence-1?view=net-5.0) 타입을 이용해 버퍼간 이음매가 드러나지 않는 seamless한 인터페이스만을 제공한다. 이것이 Pipeline의 핵심이다.

Pipeline에 대한 보다 상세한 설명은 [MS 블로그의 포스팅](https://devblogs.microsoft.com/dotnet/system-io-pipelines-high-performance-io-in-net/)으로 대체한다.



## 장점 : 불필요한 메모리 복사를 없앤다. 

고성능 소켓 IO 구현에 관심이 있는 C++ 프로그래머라면 프로토콜 버퍼의 [ZeroCopyStream](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.io.zero_copy_stream) 을 이미 접해봤을지 모른다. 그렇다면 Pipeline의 가장 주요한 장점을 이해하기 쉽다. Pipeline의 버퍼 운용 아이디어는 프로토콜 버퍼의 ZeroCopyStream과 유사하다. 소켓으로 데이터를 주고 받는 과정에서 불필요한 버퍼간 메모리 복사를 최소한으로 줄여주어 성능향상을 꾀한다. 

프로그래밍에 미숙한 개발자가 만든 서버일수록 버퍼간 복사 발생이 빈번하게 발생한다. 커널모드 아래에서 일어나는 소켓버퍼와 NIC 버퍼간의 복사까지는 일단 관두더라도, 최소한 유저모드 위에서의 불필요한 버퍼 복사는 없어야 한다. 

 전송할 데이터 타입을 버퍼로 serializing하면서 함 복사하고, 이걸 소켓에다가 send 요청을 하자니 다시 OVERLAPPED에 연결된 버퍼에다가 다시 함 복사하고... send 완료 통지 받고 나면 transferred bytes 뒤에 아직 안보인 데이터들 다시 제일 앞으로 당겨주느라 또 복사하기가 쉽다. 통신량이 많은 서버일수록 메모리 복사에서 불필요한 cpu를 낭비하게 되는데, Pipeline의 도입은 이런 부분을 쉽게 줄여줄 수 있다.



## 장점 : 네트워크 버퍼의 고정길이 제약을 없애준다.

가장 단순하게 소켓 레이어를 구현한다면 Send / Recv용 고정 사이즈 버퍼를 하나씩 붙여서 만들게 될 것이다. 대략 구현중인 게임이 어느 정도 사이즈의 패킷을 주고 받는지를 파악해서 (게임 서버는 주로 recv는 작은 사이즈를 많이 하고, send는 큰 사이즈를 하게 된다. 로그인할때, 캐릭터 선택할 때 보내는 패킷이 주로 제일 크다) 소켓에 연결할 버퍼의 길이를 눈치껏 `고정한다`. 버퍼를 거거익선으로 크게크게 잡으면 다수의 동접을 받아야 할때 메모리 사용량이 커서 부담이 된다. 그래서 적당히 오가는 패킷 사이즈를 봐서 터지지만 않을 정도의 고정길이 버퍼를 걸어두는 식으로 많이 만든다.

이렇게 만들면 불안하다. 컨텐츠를 점점 추가하다가 언젠가 한두번은 네트워크 버퍼 overflow가 발생해 버퍼 크기를 늘려잡아 해결해야 한다. 아니면 버퍼를 넘치게 만든 문제 패킷의 구조를 변경하거나 두 개의 패킷으로 쪼개서 다이어트를 시켜야 한다. 어느쪽 방향이든 고성능 서버 레이어 구현과는 거리가 있는 해결법이다. 메모리를 더 써서 해결하거나, 개발에 제약(패킷의 최대 크기)을 두어 해결하거나.

Pipeline과 ZeroCopyStream 모두 이러한 고정길이 버퍼의 제약을 없애준다. 처음엔 기본단위 정도의 작은 버퍼만 가지고 있다가, 필요할 땐 버퍼를 추가 할당받아 링크드 리스트 뒤에 달아주기 때문이다. 실제 사용하는 active한 버퍼의 용량은 작은 데이터를 주고받을 때는 조금만 쓰다가, 큰 데이터일 땐 세그먼트를 추가로 받아 넉넉히 쓰고, 다쓰면 다시 반납하는 유연성을 제공해준다.



## 단점 : 너무 많은 waiting task

위의 두가지 장점만으로 Pipeline의 도입을 시도해볼 가치는 충분했다. 그래서 우리 게임서버의 Recv Buffer를 Pipeline으로 대체하고, MS Azure F8s 급 인스턴스 수십대를 동원해 10만 동접 스트레스 테스트를 진행해 보았다. 



## 대안 : 불필요한 복사가 없는 가변버퍼를 직접 만들자.





## 마치면서



참고

* https://www.slideshare.net/sm9kr/windows-registered-io-rio
* https://docs.microsoft.com/ko-kr/dotnet/standard/io/pipelines