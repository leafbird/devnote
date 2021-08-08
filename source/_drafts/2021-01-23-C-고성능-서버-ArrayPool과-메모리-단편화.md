---
title: C# 고성능 서버 - ArrayPool과 메모리 단편화
date: 2021-01-23 17:44:36
tags: [c#, 고성능, 게임서버, ArrayPool, Memory, Fragmentation]
---

{% asset_img memory_02.jpg %}

C++로만 만들어 오던 온라인 게임 서버를 처음 C#으로 만들려고 했을 때, 성능적인 측면에서 가장 신경이 쓰였던 부분을 꼽으라면 단연코 메모리였다. C++과 C#의 개발 환경은 닮은 점도, 다른 점도 많겠지만 가장 다른 점을 꼽으라면 단연코 메모리일 것이다. 

자료조사 중 접하게 되는 각종 도시괴담(?)들과 책으로만 공부한 GC를 보면서, 2세대 GC가 한 번씩 발생할 때마다 모든 게임 월드가 먹통이 되는 것 아닌가 하면서 많이 쫄았던 기억이 난다.
이제는 C#으로 게임서버를 만들기 시작한 지도 4년이 되어간다. 이번 포스팅에서는 그동안 메모리에 관련해 경험했던 이슈들에 대해 간단히 정리해본다.

<!-- more -->



## 무난하게 관리되는 메모리

오랜 세월 발전을 거듭해온 요즈음 .Net의 GC는 꽤나 쓸만하다. 대부분의 경우에 C#의 메모리는 굳이 신경쓰지 않아도 알아서 잘 관리된다. 게임월드가 모두 먹통이 되는 "Stop-the-world" 현상은 사실 거의 만나기 어렵다. 게임서버인 경우 `Workstation GC` 대신 `Server GC`를 사용하도록 설정해 주는는 것 만으로도 나쁘지 않은 동작을 보인다. 

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <ServerGarbageCollection>true</ServerGarbageCollection>
  </PropertyGroup>

</Project>
```

요즈음의 .Net이라고. 표현한 이유는 아마 처음부터 이런 수준은 아니었을 것이기 때문이다. 도시괴담처럼 들리는 몇몇 실패담들이 있다. 다른 게임 프로젝트에서 c#으로 서버를 만들다가 메모리에서 낭패를 보았다 같은 류의 썰인데, 아마 과거의 닷넷 프레임워크 버전에서 발생했던 사례들이 뜬소문처럼 돌아다니는 거라고 생각한다. .Net Framework 4.5에 들어서면서 GC가 크게 한 번 개선되었기 때문에, 이 때를 기점으로 큰 체감상의 차이가 있었을 것이다(나는 이보다 과거 버전의 프레임워크는 경험해 보지 못했다).

https://devblogs.microsoft.com/dotnet/the-net-framework-4-5-includes-new-garbage-collector-enhancements-for-client-and-server-apps/

.Net 4.5부터는 GC를 제어할 수 있는 옵션들도 많이 추가되었는데, 우리 프로젝트의 경우 다른 설정은 건드린 것 없이 기본값으로 사용해도 큰 무리가 없다. 서버의 비즈니스 로직 구현에 따라 많은 차이가 있을테니 일반화해서 말하긴 어렵다. 여러가지 사례 중의 하나로 참고하기 바란다.

##### GC를 써보니 좋은 점 : 객체 재활용은 크게 의미가 없다.
부하테스트를 진행하면서, C++ 시절을 생각하며 어줍잖게 직접 만들어 사용하던 각종 오브젝트 풀링 처리들도 거의 다 떼버렸다. 메모리 동작 상황을 직접 추적하면서 보니까 나름대로 신경쓴다고 구현해둔 풀링 동작이 오히려 GC의 수행 부담을 높이는 경우가 많았다. `객체를 재사용하면 할당과 해제는 줄어들겠지만 객체의 수명이 길어진다`. 수명이 길어진 객체들은 모두 2세대 객체로 넘어간다. 2세대 객체가 많아질수록 GC에겐 큰 부담이 된다. 웬만하면 그냥 객체가 필요한 시점에 바로 할당해서 쓰는게 더 나을만큼 현시점의 GC는 믿을만하다. (우리 프로젝트는 런칭 당시 .Net framework 4.7.2를 사용했고, 현재는 .Net core 3.1를 사용중이다.)

##### GC를 써보니 나쁜 점 : 생각보다 일을 열심히 하지 않는다.

앞서 적었던 것처럼 C#으로 게임서버를 짜면 월드가 턱턱 멈추는게 아닐까 걱정을 했었다. 실제로 서버를 짜고 돌려보니 GC가 너무 일을 열심해 해서 문제되는 일은 거의 없고, 생각보다 GC가 일을 덜해서 생기는 문제가 많았다. 내가 다 썼다고 생각한 메모리를 GC는 아직 쓰고 있다고 생각해 수거하지 않는 경우가 많고, 내생각엔 힙 용량을 이렇게 크게 잡을 필요가 없는데 GC는 자꾸만 관리힙을 키워 Out-of-memory 예외를 발생하기도 했다.

##### 메모리릭은 C++에만 있는 것이 아니다. 

닷넷으로 작성한 게임서버에서 좀 더 성능을 끌어올려 보기로 마음을 먹는다면 신경써야 할 점들이 있다. 게임서버에 부하를 점점 더 강하게, 점점 더 오래 가하면 메모리 누수(leak)와 단편화(fragmentation)를 겪게 된다. `아니 내가 그런 꼴 안 보려고 C#으로 왔는데 무슨소리요` 라고 생각하겠지만... 특히 누수(leak)에 대해서 만큼은 더욱 그런 생각이 들겠지만, 실제로 그런 일이 일어난다.

{% asset_img memory_04.png %}

MSDN에는 [.Net core에서 메모리 누수를 디버깅하는 방법에 대한 소개](https://docs.microsoft.com/en-us/dotnet/core/diagnostics/debug-memory-leak)도 정리되어 있다. 닷넷의 메모리 누수는 조금만 검색해보면 제법 많은 사례들이 있고 솔루션과 예방법들을 찾을 수 있는데, 이 글에서는 단편화에 대해서 먼저 이야기 해본다.


## ArrayPool< T > 간단한 소개

`ArrayPool<T>`는 .Net Core에 들어오면서 제공되기 시작한 배열 타입 풀링 라이브러리다. .Net standard 2.1 기준으로 구현되어있어 .Net Framework 를 사용중인 프로젝트에도 사용이 가능하다. 공식으로 지원하는 라이브러리인 만큼 무한한 신뢰를 보내며 프로젝트에 시험 적용하고 변화를 체크해 보았다. 내가 만든 객체 풀링 로직보다야 단연 훌륭한 라이브러리이지만, 두 가지 이유로 우리 프로젝트에서는 크게 쓸모가 없었다. 

##### 1. 비즈니스 로직의 어지간한 객체들은 사실 풀링이 거의 필요가 없다. 

이건 경우에 따라 다를것이다. 우리 프로젝트에서는 비즈니스로직의 메모리 압력은 그리 문제될 수준이 아니었다. 초반에 적용했던 객체 풀링 기법들도 거의 다 제거한 상태여서, `ArrayPool<T>`가 개입해 성능 향상을 이룰만한 여지가 크게 없었다.

##### 2. 네트워크 레이어의 로우레벨은 ArrayPool< T >로는 역부족이다.

문제는 네트워크 레이어. `Socket`, `SocketAsyncEventArgs` 및 IO에 쓰이는 `바이트 버퍼`들이다. 이런 객체들의 관리에도 `ArrayPool<T>`를 적용하고 압력을 가해봤는데 큰 개선이 없었다.



## 메모리가 새나? 자꾸 늘어가는 메모리 사용량



## 관리힙 내의 알박기 : Pinned Memory



## 해결법1 : POH in .NET5



## 해결법2 : LOH를 이용한 버퍼 풀링



## 정리







<img src="/Users/florist/dev/devnote/source/_posts/2021-01-23-C-고성능-서버-ArrayPool과-메모리-단편화/memory_00.png" alt="image-20210123183313364" style="zoom:50%;" />



참고 : 

* https://tooslowexception.com/pinned-object-heap-in-net-5/
* https://docs.microsoft.com/ko-kr/dotnet/api/system.buffers.arraypool-1?view=net-5.0
* https://docs.microsoft.com/en-us/aspnet/core/performance/memory?view=aspnetcore-3.0
* https://docs.microsoft.com/en-us/dotnet/standard/garbage-collection/performance#Pinned
* https://ayende.com/blog/181761-C/the-curse-of-memory-fragmentation
* https://github.com/Microsoft/Microsoft.IO.RecyclableMemoryStream