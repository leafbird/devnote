---
title: C# 고성능 서버 - Thread Local Storage
date: 2021-01-01 16:00:49
tags: [c#, 고성능, 게임서버, Thread, AsyncLocal, TLS]
---

프로그래밍에서 각 스레드별로 고유한 상태를 설정할 수 있는 공간을 [Thread Local Storage](https://en.wikipedia.org/wiki/Thread-local_storage) (이하 TLS. transport layer security 아님) 라고 한다. VC++에서는 `__declspec(thread)` 키워드를 이용해서 tls 변수를 선언할 수 있다. 

C#에도 `ThreadLocal<T>` 라는 클래스를 이용해 tls를 사용할 수 있지만, 막상 실제로 사용해보면 C++에서는 존재하지 않았던 큰 차이점이 있다. C# 5.0부터 들어온 async / await 문법을 이용해 비동기 프로그래밍을 구현했다면, await 대기 시점 이전과 이후에 스레드가 달라지기 때문이다. 

이를 해결하는 방법과 주의해야 할 사항을 정리해본다. 

<!--more-->

{% blockquote %}

알림 : 이 글을 처음 포스팅한 후 받은 피드백을 통해 보다 명확한 원인과 해결방법을 추가 확인하게 되어 내용을 수정/보완 했습니다. 최초 버전의 글도 유지하려 했으나 글의 문맥이 복잡해지고 읽기가 어려워져 최종 버전만 남겼습니다.

수정한 내용 요약 : 새로 깨어난 스레드인데도 `AsyncLocal<T>`에 값이 남아있던 이유는, 기존의 값이 지워지지 않았기 때문이 아니라, 네트워크 이벤트 콜백으로 깨어난 스레드에도 `AsyncLocal<T>`의 값을 복사하고 있었기 때문이었습니다.

{% endblockquote %}

## async / await 을 절대 가볍게 접근하면 안된다

주제와 약간 벗어날 수 있지만 서두에 미리 한 번 짚고 넘어갈 부분이 있다. **절대로 async / await를 이용한 비동기 프로그래밍을 만만하게 보아서는 안된다**는 것이다.

나도 그랬지만 누구든지 제일 처음 비동기 메서드를 접했을 땐 이해하기 쉽고 간단한 기능이라는 첫인상을 가지게 될 것이다. 개인적으로는 비동기 메서드를 적용하고 난 후의 코드가 동기 프로그래밍과 너무 비슷해져 버리는 점이 착각을 유발하는 큰 원인이라고 생각한다 (MS: 얘는 뭐 좋게 해줘도 불만이 많네..) 

이전에 DB 쿼리나 네트워크 통신같은 IO 작업에서 비동기로 받는 결과값을 처리하기 위해서는 하나의 동일한 주제(single concern)를 위한 로직임에도 불구하고 비동기 요청 이전과 이후의 코드가 분절되어야 했다. 이를테면 비동기 요청 전의 코드와 응답 후의 코드를 서로 다른 메서드로 나누어서 짜야 했다는 뜻이다. 코드의 가독성에 대해 고민을 좀 해봤던 개발자라면 람다를 써서 어떻게든 읽기 좋고 관리하기 좋도록 애써 보았을 수도 있으나, 가독성에서 정도의 차이가 있을 뿐 명백하게 존재하는 코드상의 분절을 피할 수 없었다. 

비동기 메서드의 등장으로 이런 상황은 옛날 이야기가 되었다. 안간힘을 써보아도 완전하게 붙이기 힘들었던 분절된 코드들은 이제 하나의 async 함수 안에서 seamless하게 구현할 수 있게 되었다. 작성한 코드를 읽을 때에도 (신경써서 읽지 않는다면) 어디가 동기 처리이고, 어디가 비동기 처리인지도 잘 모르고 넘어갈만큼 술술 읽어내려가게 되었다. 좋게 해석하자면 어플리케이션 개발자가 좀 더 로직에만 집중 할 수 있는 환경이 되었다.

이것은 호수에 떠있는 백조와 같다. 일단 겉으로 보기에는 아주 우아하게 비동기 코드를 표현했으나, 조금만 안을 들여다보면 비동기 요청을 기준으로 발생하는 여전한 로직의 분절, 그에 따른 **실행 시점 시간차 및 실행 환경상의 차이** 등은 당연게도 여전히 존재하고 있기 때문이다. 이로 인한 이슈들은 동시성(concurrency)이 있는 멀티스레드 환경에서 더 잘 드러난다. MS는 실제로 프로그래머들이 하부의 복잡한 메커니즘을 잘 모르더라도 쉽고 편하게 비동기 로직을 다룰 수 있는 유토피아를 꿈꾸었을지 모르겠다. 하지만 싱글 스레드로 간단한 툴 한두개 짜는거면 몰라도... C#이란 언어로 고성능 서버를 만들겠다고 한다면, 이에 대한 충분한 이해가 없이는 런타임에서 예상못한 오작동을 피할 수 없을 것이다.

이후 글에서 언급할 내용도 비동기 함수의 실행 시점차와 관련되어 있으므로, 비동기 메서드에 대한 어느 정도의 이해가 필요하다.



## ThreadLocal 

우선 잠깐 언급했던 `ThreadLocal<T>` 클래스를 간단히 알아보자. 이를 이용해 일반적인 tls 변수를 선언하고 사용할 수 있다. 이보다 전부터 있었던 `[ThreadStatic]` 어트리뷰트로도 똑같이 tls를 선언할 수 있지만, 변수의 초기화 처리에서 `ThreadLocal<T>` 가 좀 더 매끄러운 처리를 지원한다. 일반적인 tls가 필요할 때는 좀 더 최신의 방식인 `ThreadLocal<T>` 를 사용하면 된다.

모든 tls 변수에 동일한 값의 복제본을 저장해 두려는 경우가 있다. 예를들어 스레드가 3개 있으면, 메모리 공간상에 각 스레드를 위한 변수 3개가 있고, 이들 모두에 같은 의미를 가지는 인스턴스를 하나씩 생성해 할당하는 경우를 말한다. **서로 다른 스레드끼리 공유해야 할 자원이 있을 때, 해당 자원에 lock이 없이 접근하고 싶다면** tls를 이용해 각 스레드마다 자원을 따로 만들어 각자 자기 리소스를 쓰게 하면 된다.

```csharp
namespace Cs.Math
{
  public static class RandomGenerator
  {
    public static int Next(int maxValue)
    {
      return PerThreadRandom.Instance.Next(maxValue);
    }
    
    // ... 중략    
    // 사용 계층에 노출할 인터페이스를 이곳에 정의. 사용자는 tls에 대해 알지 못한다.

    // System.Random 객체는 멀티스레드 사용에 안전하지 않으므로 각 스레드마다 개별 생성.
    private static class PerThreadRandom
    {
      private static readonly ThreadLocal<Random> Random = new ThreadLocal<Random>(() => new Random());

      internal static Random Instance => Random.Value;
    }
  }
}

```

이런 경우는 비동기 메서드의 실행중 스레드의 교체가 발생하더라도 아무 문제가 되지 않는다. 어차피 어떤 스레드로 바뀌더라도 tls 변수가 하는 역할은 동일하기 때문이다. 0번 스레드가 불러다 쓰는 `Random` 객체가 어느순간 2번 스레드의 `Random` 객체로 바뀐다 해도 동작에 큰 영향이 없다. 



## AsyncLocal

문제는 스레드별로 tls의 상태가 서로 달라야 할 때 발생한다. 0번 스레드에는 tls에 "철수"가, 2번 스레드에는 "영희"가 적혀있어야 하고, 이를 사용해 스레드마다 다른 동작을 해야 하는 경우. 그런데 거기다 async/await를 이용한 비동기 프로그래밍을 함께 사용한 경우. 0번 철수 스레드가 코드 수행 도중 await 구문을 만나 task의 완료를 기다리고 있었지만, 대기가 풀렸을 때는 2번 스레드로 갈아타게 되면서 철수가 영희가 되버리는 경우다.

{% asset_img 00.png %}

스레드별로 서로 다른 상태값을 사용해야 하는 예를 구승모 교수님의 [Dispatcher](https://github.com/zeliard/Dispatcher) 구현에서 찾아볼 수 있다. ([ThreadLocal.h](https://github.com/zeliard/Dispatcher/blob/master/JobDispatcher/ThreadLocal.h)) Dispatcher는 고성능 멀티스레드 로직 수행을 위한 Actor 패턴 구현체다. 스레드에 lock을 걸지 않으면서도 서로 다른 스레드간 간섭 없이 순차실행을 가능하게 하기 위해, 스레드는 현재 자신의 수행상태 일부를 tls에 기록해 두어야 한다. 

친절한 ms 형들이 이런 경우를 위해 [AsyncLocal](https://docs.microsoft.com/ko-kr/dotnet/api/system.threading.asynclocal-1?view=net-5.0) 클래스도 미리 만들어 두었다. 생긴것도 서로 비슷해서  `ThreadLocal<T>` 를 사용했던 변수에 대신 `AsyncLocal<T>` 로 바꿔주면 위에서 말한 문제를 해결할 수 있다. 0번 스레드가 먼저 코드를 수행하다가 await 구문을 만나서 대기하고, 대기가 풀려날 때 2번 스레드로 변경이 되었더라도 `AsyncLocal<T>` 가 2번 스레드의 tls 값을 알아서 "영희" -> "철수"로 바꿔주는 것이다. 

{% asset_img 02.png %}



## 문제점 : 의도치 않게 값의 복사 발생

이러면 문제는 해결된 것 같지만, 또 다른 문제가 있다. 여기가 이 글의 핵심이다 집중해주기 바란다. `AsyncLocal<T>`는 **ThreadPool이 다른 새 스레드를 추가로 깨우게 하는 특정 api들 중에 하나를 호출하는 경우, 기본적으로 호출자 스레드의 변수값을 새로운 스레드에게 복사해주는 기본 동작을 갖고 있다.** 현재 스레드에서만 고유하게 유지하려고 기록해 둔 tls의 변수들이 요주의 api중 하나를 호출하는 순간 새로운 다른 스레드로 복사되는 것이다. 현재 우리 프로젝트 구현의 범위 기준에서, AsyncLocal의 값을 복사시키는 메서드들은 아래와 같다.

1. Fire-and-forgot 으로 동작할 백그라운드 작업이 필요해서 직접 ThreadPool에 요청하는 메서드들 

   * Task.Run()
   * ThreadPool.QueueUserWorkItem()

2. 비동기 소켓의 IO 완료통지를 포함해, 네트워크 이벤트 콜백을 유발하는 메서드들

   *  Socket.ConnectAsync() - ConnectEx() in win32
   *  Socket.DisconnectAsync() - DisconnectEx() in win32
   *  Socket.AcceptAsync() - AcceptEx() in win32
   *  Socket.ReceiveAsync() - WSARecv() in win32
   *  Socket.SendAsync() - WSASend() in win32

1번 백그라운드 작업 요청 메서드들은 스레드풀을 대상으로 하는 동작이니까 어느 정도 이해가 된다고 하지만, 2번 네트워크 콜백들은 tls를 복사한다는 점이 선뜻 연결이 잘 되지 않는다. managed 메서드의 이름이 낮설어 보일까 싶어 win32에 해당하는 함수명도 같이 적었는데, 그냥 OVERLAPPED 구조체를 이용해 IOCP에 통지를 요청하는 네트워크 api들 전체를 말한다. 

0번 스레드가 게임 로직을 열심히 수행하다가 클라이언트로 동기화 패킷을 보낼 상황이 되었다. 그래서 패킷을 만들어 소켓에 SendAsync()를 한 번 걸어놓고, 다시 또 다른 로직을 열심히 수행한다. 근데 0번 스레드가 걸었던 send 요청이 완료되어 새롭게 2번 스레드가 OnSendCompleted 메서드를 실행하려고 깨어났는데, 이 때 0번 스레드가 `AsyncLocal<T>`에 저장해두었던 tls 값들을 2번 스레드가 고대로 복사받아서 수행을 시작하는 것이다.

`AsyncLocal<T>`는 자신의 존재 목적과 취지에 충실하고자, 서로 다른 스레드들간에 조금이라도 관련이 있을라 치면 아주 얄짤없이 값을 복사해대는 것 같다. 하지만 win32에서 iocp에 비동기 작업의 완료 통지를 요청하고, 전혀 관련없는 다른 스레드로부터 이를 받아 처리해오던 고전적 처리방식에 익숙해서 그런지 이런 과도한 친절이 부담스럽다. 너 때문에 Dispatcher 동작이 다 깨지잖아. 조치가 필요하다.



## 원치 않는 AsyncLocal 복사는 꺼준다.

다행히 이 동작은 ExecutionContext.SuppressFlow / RestoreFlow 라는 메서드가 있어 쉽게 제어가 가능하다. 우선 스레드풀에 백그라운드 작업을 요청할 때는 `SuppressFlow()` 호출이 묶여있는 별도의 인터페이스를 만들고 이를 사용하게 한다.

```csharp
public static class BackgroundJob
{
  public static void Execute(Action action)
  {
    using var control = ExecutionContext.SuppressFlow();
    ThreadPool.QueueUserWorkItem(_ => action());
  }
}

public static class Program 
{
  public void Foo() 
  {
    int a = 10;
    int b = 20;

    // 백그라운드 작업이 필요할 때. Wrapping한 인터페이스를 사용한다. 
    BackgroundJob.Execute(() => 
    {
      Console.WriteLine($"a + b = {a+b}");
    });
  }  
}
```

작업 요청 후에는 `RestoreFlow` 를 불러 복구해주면 되는데, `SuppressFlow` 메서드가 IDisposable인  [AsyncFlowControl](https://docs.microsoft.com/en-us/dotnet/api/system.threading.asyncflowcontrol?view=net-5.0) 객체를 반환하니까 예시처럼 using을 쓰면 좀 더 심플하게 처리할 수 있다.

네트워크 구현부에도 수정이 필요하다. `SocketAsyncEventArgs` 객체를 사용해 비동기 요청을 수행하는 모든 곳에도 `RestoreFlow` 를 불러준다. (`SocketAsyncEventArgs`는 win32의 `OVERLAPPED` 구조체를 거의 그대로 랩핑해둔 클래스다.) 예시로 하나만 옮겨보면 아래처럼 된다. 

```csharp
public abstract class ConnectionBase
{
  public void ConnectAsync(IPAddress ip, int port)
  {
    var args = new SocketAsyncEventArgs();
    args.Completed += this.OnConnectCompleted; // 이 메서드가 새로운 스레드에서 불리게 될 것이다.
    args.RemoteEndPoint = new IPEndPoint(ip, port);

    using var control = ExecutionContext.SuppressFlow(); // 이걸 넣어주어야 콜백 스레드로 AsyncLocal을 복사하지 않는다.
    if (!this.socket.ConnectAsync(args))
    {
      this.OnConnectCompleted(this.socket, args);
    }
  }
}
```

이런식으로 SendAsync, RecvAsync 등도 다 막아주어야 일반적인 iocp 콜백 사용 방식과 동일해진다. 다른 코드상에서 아무데도 `AsyncLocal<T>`을 사용중이지 않다면 굳이 SuppressFlow 호출이 없어도 동작에는 문제가 없다. 그래도 어차피 사용하지도 않을 암묵적인 실행 컨텍스트간 연결 동작은 그냥 끊어두는 것이 성능상 조금이라도 이득일 듯한 기분이 든다. 



## 정리

* C#의 비동기 메서드는 코드상으로는 매끈하게 이어져 있는듯 보이지만 실은 비동기 요청 지점을 전후로 분리 실행되며, 실행 스레드가 서로 다를 수도 있다.
* 이로 인해 `ThreadLocal<T>` 로는 비대칭적(asymmetric)인 tls 데이터를 다루기가 어렵기 때문에 `AsyncLocal<T>`라는 클래스가 별도로 존재한다.
* `AsyncLocal<T>`는 스레드풀에서 새로운 다른 스레드를 깨어나게 할 때도 값을 복사시킨다. 이는 `ExecutionContext.SuppressFlow()` 로 제어가 가능하다.



현재 사용중인 게임서버의 스레드 모델도 승모님의 JobDispatcher와 유사한 Actor 기반 구조를 채택해서 락 없이 구현하고 있다. 지금 서버 구현 기준에서 값이 복사되는 tls 변수가 문제를 일으키는 케이스는 액터를 구현하기 위한 로직 한 군데 뿐이다. 일반적으로 게임 서버를 구현할 때 스레드별로 비대칭적인(asymmetric) tls 변수를 유지해야 하는 경우가 흔치는 않을 것이다. 액터 패턴을 구현한다고 해서 tls 변수가 반드시 필수적인 것도 아니다. 이전 프로젝트에서 tls를 사용하지 않는 액터 구현도 사용해본 적이 있기 때문이다.

하지만 고성능 서버를 목표로 스레드 효율성을 튜닝한다면 반드시 사용을 염두에 두게 되는 도구가 TLS이므로, 본 글에서 언급한 내용을 숙지하고 있으면 성능 튜닝에서 많은 삽질을 세이브 하게 될것이다.
