---
title: C# 고성능 서버 - Thread Local Storage
date: 2021-01-01 16:00:49
tags: [c#, 고성능, 게임서버, Thread, AsyncLocal, TLS]
---

프로그래밍에서 각 스레드별로 고유한 상태를 설정할 수 있는 공간을 [Thread Local Storage](https://en.wikipedia.org/wiki/Thread-local_storage) (이하 TLS. transport layer security 아님) 라고 한다. VC++에서는 `__declspec(thread)` 키워드를 이용해서 tls 변수를 선언할 수 있다. 

C#에도 `ThreadLocal<T>` 라는 클래스를 이용해 tls를 사용할 수 있지만, 막상 실제로 사용해보면 C++에서는 존재하지 않았던 큰 차이점이 있다. C# 5.0부터 들어온 async / await 문법을 이용해 비동기 프로그래밍을 구현했다면, await 대기 시점 이전과 이후에 스레드가 달라지기 때문이다. 

이를 해결하는 방법과 주의해야 할 사항을 정리해본다. 

<!--more-->

## async / await 을 절대 가볍게 접근하면 안된다

주제와 약간 벗어날 수 있지만 서두에 미리 한 번 짚고 넘어갈 부분이 있다. **절대로 async / await를 이용한 비동기 프로그래밍을 만만하게 보아서는 안된다**는 것이다.

나도 그랬지만 누구든지 제일 처음 비동기 메서드를 접했을 땐 이해하기 쉽고 간단한 기능이라는 첫인상을 가지게 될 것이다. 개인적으로는 비동기 메서드를 적용하고 난 후의 코드가 동기 프로그래밍과 너무 비슷해져 버리는 점이 착각을 유발하는 큰 원인이라고 생각한다 (MS: 얘는 뭐 좋게 해줘도 불만이 많네..) 

이전에 DB 쿼리나 네트워크 통신같은 IO 작업에서 비동기로 받는 결과값을 처리하기 위해서는 하나의 동일한 주제(single concern)를 위한 로직임에도 불구하고 비동기 요청 이전과 이후의 코드가 분절되어야 했다. 이를테면 비동기 요청 전의 코드와 응답 후의 코드를 서로 다른 메서드로 나누어서 짜야 했다는 뜻이다. 코드의 가독성에 대해 고민을 좀 해봤던 개발자라면 람다를 써서 어떻게든 읽기 좋고 관리하기 좋도록 애써 보았을 수도 있으나, 가독성에서 정도의 차이가 있을 뿐 명백하게 존재하는 코드상의 분절을 피할 수 없었다. 

비동기 메서드의 등장으로 이런 상황은 옛날 이야기가 되었다. 안간힘을 써보아도 완전하게 붙이기 힘들었던 분절된 코드들은 이제 하나의 async 함수 안에서 seamless하게 구현할 수 있게 되었다. 작성한 코드를 읽을 때에도 (신경써서 읽지 않는다면) 어디가 동기 처리이고, 어디가 비동기 처리인지도 잘 모르고 넘어갈만큼 술술 읽어내려가게 되었다. 좋게 해석하자면 어플리케이션 개발자가 좀 더 로직에만 집중 할 수 있는 환경이 되었다.

이것은 호수에 떠있는 백조와 같다. 일단 겉으로 보기에는 아주 우아하게 비동기 코드를 표현했으나, 조금만 안을 들여다보면 비동기 요청을 기준으로 발생하는 여전한 로직의 분절, 그에 따른 **실행 시점 시간차 및 실행 환경상의 차이** 등은 당연게도 여전히 존재하고 있기 때문이다. 이로 인한 이슈들은 동시성(concurrency)이 있는 멀티스레드 환경에서 더 잘 드러난다. MS는 실제로 프로그래머들이 하부의 복잡한 메커니즘을 잘 모르더라도 쉽고 편하게 비동기 로직을 다룰 수 있는 유토피아를 꿈꾸었을지 모르겠다. 하지만 싱글 스레드로 간단한 툴 한두개 짜는거면 몰라도... C#이란 언어로 고성능 서버를 만들겠다고 한다면, 이에 대한 충분한 이해가 없이는 런타임에서 예상못한 오작동을 피할 수 없을 것이다.

이후 글에서 언급할 내용도 비동기 함수의 실행 시점차와 관련되어 있으므로, 비동기 메서드에 대한 어느 정도의 이해가 필요하다.



## ThreadLocal 

우선 잠깐 언급했던 `ThreadLocal<T>` 클래스를 간단히 알아보자. 이를 이용해 일반적인 tls 변수를 선언하고 사용할 수 있다. 이보다 전부터 있었던 `[ThreadStatic]` 어트리뷰트로도 똑같이 tls를 선언할 수 있지만, 변수의 초기화 처리에서 `ThreadLocal<T>` 가 좀 더 매끄러운 처리를 지원한다. 일반적인 tls가 필요할 때는 좀 더 최신의 방식인 `ThreadLocal<T>` 를 사용하면 된다.

모든 tls 변수에 동일한 값을 저장해 두려는 경우가 있다. 예를들어 스레드가 3개 있으면, 메모리 공간상에 각 스레드를 위한 변수 3개가 있고, 이들 모두가 같은 값을 같는 경우를 말한다. **서로 다른 스레드끼리 공유해야 할 자원이 있을 때, 해당 자원에 lock이 없이 접근하고 싶다면** tls를 이용해 각 스레드마다 자원을 따로 만들어 각자 자기 리소스를 쓰게 하면 된다.

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

이런 경우는 비동기 메서드의 실행중 스레드의 교체가 발생하더라도 아무 문제가 되지 않는다. 어차피 어떤 스레드로 바뀌더라도 tls 변수의 상태는 동일하기 때문이다. 0번 스레드가 불러다 쓰는 `Random` 객체가 어느순간 2번 스레드의 `Random` 객체로 바뀐다 해도 동작에 큰 영향이 없다.



## AsyncLocal

문제는 스레드별로 tls의 상태가 서로 달라야 할 때 발생한다. 0번 스레드에는 tls에 "철수"가, 2번 스레드에는 "영희"가 적혀있어야 하고, 이를 사용해 스레드마다 다른 동작을 해야 하는 경우. 그런데 거기다 async/await를 이용한 비동기 프로그래밍을 함께 사용한 경우. 0번 철수 스레드가 코드 수행 도중 await 구문을 만나 task의 완료를 기다리고 있었지만, 대기가 풀렸을 때는 2번 스레드로 갈아타게 되면서 철수가 영희가 되버리는 경우다.

{% asset_img 00.png %}

스레드별로 서로 다른 상태값을 사용해야 하는 예를 구승모 교수님의 [Dispatcher](https://github.com/zeliard/Dispatcher) 구현에서 찾아볼 수 있다. ([ThreadLocal.h](https://github.com/zeliard/Dispatcher/blob/master/JobDispatcher/ThreadLocal.h)) Dispatcher는 고성능 멀티스레드 로직 수행을 위한 Actor 패턴 구현체다. 스레드에 lock을 걸지 않으면서도 서로 다른 스레드간 간섭 없이 순차실행을 가능하게 하기 위해, 스레드는 현재 자신의 수행상태 일부를 tls에 기록해 두어야 한다. 

친절한 ms 형들이 이런 경우를 위해 [AsyncLocal](https://docs.microsoft.com/ko-kr/dotnet/api/system.threading.asynclocal-1?view=net-5.0) 클래스도 미리 만들어 두었다. 생긴것도 서로 비슷해서  `ThreadLocal<T>` 를 사용했던 변수에 대신 `AsyncLocal<T>` 로 바꿔주면 위에서 말한 문제를 해결할 수 있다. 0번 스레드가 먼저 코드를 수행하다가 await 구문을 만나서 대기하고, 대기가 풀려날 때 2번 스레드로 변경이 되었더라도 `AsyncLocal<T>` 가 2번 스레드의 tls 값을 알아서 "영희" -> "철수"로 바꿔주는 것이다. 

이러면 문제는 해결된 것 같지만, 또다른 문제가 있다. 여기가 이 글의 핵심이다 집중해주기 바란다. `AsyncLocal<T>` 는 **비동기 메서드 수행 도중 스레드가 바뀌면 새로 바톤을 이어받은 스레드에게 tls의 상태를 자동으로 동기화 시켜 주기는 하지만, 바톤을 넘겨주고 떠나는 원래 스레드의 tls 상태를 초기화 시켜주지는 않는다.** 중요하니까 그림까지 그려서 한 번 더 말한다. 0번 "철수" 스레드가 await 구문 전까지 수행을 하고, 대기가 끝난 후 2번 "영희" 스레드로 변경되어 수행이 재개 될 때 `AsyncLocal<T>`를 사용하면 2번 스레드의 tls 상태가 "철수"가 되긴 하지만, 여전히 0번 스레드의 tls에도 "철수"가 남아있는 것이다. 

{% asset_img 01.png %}

실행을 재개하는 2번 스레드에서는 AsyncLocal 덕분에 큰 문제가 없지만, 0번 스레드는 이후  ThreadPool로 들어온 새로운 요청을 수행하러 나가게 될텐데, 그곳에서는 전혀 관련없는 과거의 tls 변수값을 가진 채로 수행될 가능성이 있으므로 주의해야 한다. 

TPL에 관심을 갖고 공부해둔 개발자라면 혹시 [SynchronizationContext](https://docs.microsoft.com/ko-kr/dotnet/api/system.threading.synchronizationcontext?view=net-5.0) 를 떠올릴 지도 모르겠다. 이를 이용해 await 대기가 풀려날 때 어떤 스레드로 재개할 것인지를 직접 컨트롤 할 수 있기 때문이다. 0번 스레드가 await 대기를 시작했다면, 대기가 풀려날 때도 0번 스레드가 다시 수행할 수 있게 스레드 스케줄링을 직접 해줄 수 있다.

하지만 웬만해서는 SynchromizationContext까지 이용해 스레드의 스케줄링을 제어할 생각은 하지 않을 것을 권하고 싶다. 성능, 사용성, 생산성 어느 방향으로든 기존보다 큰 개선을 이루기 어려울 것이다. 스레드 스케줄링은 프로그램의 가장 코어한 부분이기에 정말 꼭 필요한 경우에 한해 혹독한 테스트를 거쳐 변경해야 할 것이다.



## 해결방안 : 직접 AsyncLocal 뒷정리 해주기

비동기 메서드 실행중 스레드 교체가 발생했을 때, 바톤을 넘겨 주고 난 이전 스레드는 tls 값이 알아서 모두 초기화 되기를 기대했지만 그렇게 동작하지 않는다. 초기화를 하고 싶다면 내가 직접 해주어야 한다.

좀 단순하고 무식하지만 ThreadPool에서 스레드가 새로운 작업 요청을 수행할 수 있는 `모든 시작점`에서 tls 상태 초기화를 해주면 된다. 이 `모든 시작점`이라는 부분은 어떤 프로그램이냐에 따라 다를텐데, 현재 프로젝트에서 쓰고있는 게임서버의 경우 크게 2종류의 시작점으로 나눌 수 있다. 

1. 소켓 API 에서 발생하는 각종 이벤트들의 핸들링 메서드가 불리는 경우.
2. Fire-and-forgot 으로 돌릴 백그라운드 작업이 필요해서 직접 ThreadPool에 요청하는 경우. 

2번 명시적인 작업 요청의 경우는 추가적으로 설명해야 할 점도 있고, 보다 무난한 해결 방법도 있기에 다음의 별도 섹션에서 추가적으로 다룬다.

1번 네트워크 이벤트 핸들링 메서드들에서는 별다른 뾰족한 수가 없어서 직접 tls 변수를 정리해 주는 식으로 해결했다. 네트워크 이벤트란 구체적으로 아래의 5가지 경우를 말한다.

* Socket.ConnectAsync 이후 호출되는 콜백
* Socket.DisconnectAsync 이후 호출되는 콜백
* Socket.AcceptAsync 이후 호출되는 콜백
* Socket.ReceiveAsync 이후 호출되는 콜백
* Socket.SendAsync 이후 호출되는 콜백

이 곳에서 수동으로 tls를 정리해주면 된다. 코드로 표현해보면 이렇게 된다. 

```csharp
public sealed class JobDispatcher
{
  private static AsyncLocal<JobDispatcher> asynclocalDispatcher = new AsyncLocal<JobDispatcher>();
  
  public static void ClearAsyncLocal()
  {
    asyncLocalDispatcher.Value = null;
  }
  
  // ... Actor 구현...
}

public sealed class TcpConnection // 소켓 구현체
{
  private Socket socket;
  
  private void OnRecvCompleted(object sender, SocketAsyncEventArgs args)
  {
    JobDispatcher.ClearAsyncLocal();
    // ... 소켓 수신 처리
  }
  
  private void OnSendCompleted(object sender, SocketAsyncEventArgs args)
  {
    JobDispatcher.ClearAsyncLocal();
    // ... 소켓 송신 처리
  }

  // ... 이런 식으로 모든 콜백 앞에서 명시적 초기화.
}
```

썩 만족스러운 솔루션은 아니지만 우리 게임서버는 이렇게 조치하여 별 탈 없이 서비스를 진행하고 있다. 이렇게 해주지 않으면 AsyncLocal 값들이 제대로 정리되지 않는다. 

스레드가 코드를 수행하다 비동기 스레드에 들어가 아직 완료하지 않은 task의 반환을 기다린다. 어느 정도 기다리다가 반환을 받는데 실패하면 스레드는 프로그래머가 hooking하거나 snipping할 아무런 여지도 남기지 않은채로 ThreadPool로 복귀하는데, 이 때까지는 정리되지 않은 tls 값에 손을 댈 수 있는 마땅한 타이밍이나 인터페이스가 없기 때문이다. 결국 스레드가 새로운 일감을 받아들고 다시 유저모드로 깨어나게 될 때를 노려 값을 초기화 해주는 것이다.



## 자식 스레드에도 복사되는 AsyncLocal 변수

직접 스레드를 생성하는게 아니기에 엄밀히 말하면 틀린 말이겠지만 소제목에 쓸 간결한 표현이 없어서 자식 스레드라고 적었다. 보다 정확히는 `Task.Run()`, `ThreadPool.QueueUserWorkItem()` 등을 이용해 스레드 풀에 새로운 작업을 요청하는 경우를 말한다. 이건 여지껏 설명한 비동기 함수 재개 시점의 이슈와는 조금 다르지만 똑같은 현상을 추가 발생시킨다. 새 작업을 수행하는 스레드가 부모(=작업 요청자) 스레드의 AsyncLocal 과 동일한 변수값을 복사해서 가져가기 때문이다.  

다행이 이 동작은 ExecutionContext.SuppressFlow / RestoreFlow 라는 메서드가 있어 쉽게 조절할 수 있다. 새 작업을 요청하기 전에 `SuppressFlow` 를 호출하면 tls의 값을 복사하지 않는다.

```csharp
namespace Cs.Messaging
{
  public static class BackgroundJob
  {
    public static void Execute(Action action)
    {
      using var control = ExecutionContext.SuppressFlow();
      ThreadPool.QueueUserWorkItem(_ => action());
    }
  }
  
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

`RestoreFlow` 호출로 인해서 백그라운드 작업을 수행하는 스레드의 tls는 부모(=작업요청자)에 할당한 AsyncLocal 변수를 물려받지 않는 것에 더해서, 이전 작업이 할당했던 AsyncLocal 변수의 상태값도 모두 초기화된 상태로 새로운 작업을 실행하게 된다. 



## 마치면서

* C#의 비동기 메서드는 코드상으로는 매끈하게 이어져 있는듯 보이지만 실은 비동기 요청 지점을 전후로 분리 실행되며, 실행 스레드가 서로 다를 수도 있다.
* 이로 인해 `ThreadLocal<T>` 로는 비대칭적(asymmetric)인 tls 데이터를 다루기가 어렵기 때문에 `AsyncLocal<T>`라는 클래스가 별도로 존재한다.
* `AsyncLocal<T>`는 비동기 메서드를 실행하다 스레드가 바뀔때 새 스레드에게 tls값을 복사는 해주지만, 기존 스레드의 tls값을 초기화 해주지는 않으므로 직접 해주어야 한다.
* `Task.Run()` 등으로 새로운 백그라운드 작업을 요청할 때에도 기본적으로 `AsyncLocal<T>` 의 값이 복사된다. `ExecutionContext.SuppressFlow()` 로 제어가 가능하다.



현재 사용중인 게임서버의 스레드 모델도 승모님의 JobDispatcher와 유사한 Actor 기반 구조를 채택해서 락 없이 구현하고 있다. 지금 서버 구현 기준에서 정리되지 않은 tls 변수가 문제되는 케이스는 액터를 구현하기 위한 용도 한 군데 뿐이기는 하다. 일반적으로 게임 서버를 구현할 때 스레드별로 비대칭적인(asymmetric) tls 변수를 유지해야 하는 경우가 흔치는 않을 것이다. 액터 패턴을 구현한다고 해서 tls 변수가 반드시 필수적인 것도 아니다. 이전 프로젝트에서는 tls를 사용하지 않는 액터 구현을 사용했었기 때문이다.

하지만 고성능 서버를 목표로 스레드 효율성을 튜닝한다면 반드시 사용을 염두에 두게 되는 도구가 TLS이므로, 본 글에서 언급한 내용을 숙지하고 있으면 성능 튜닝에서 많은 삽질을 세이브 하게 될것이다.

