---
title: Implementing Lightweight Actor in C# (1) - 기본 구조와 스케줄링
date: 2026-01-29 10:00:00
tags:
- actor
- multithread
- csharp
- gameserver
---

{% asset_img header.png %}

## 들어가며

지난 글({% post_link Applying-the-Actor-Pattern-to-MMO-Servers "링크" %})에서는 Actor 패턴을 MMO 서버에 적용할 때의 두 가지 접근 방식 — Zone 단위의 Coarse-grained 방식과 Object 단위의 Fine-grained 방식 — 을 비교해 보았습니다.

이제 드디어 실제 코드를 살펴볼 차례입니다. 이번 글에서는 현재 프로젝트에서 사용 중인 **경량 Actor 구현체**의 핵심 구조를 소개합니다. 주로 스레드가 어떻게 운용되는지, 그리고 c#의 비동기 메서드(async/await)로 인해 끊겼다 이어지는 스레드 흐름을 어떻게 다루는지에 대해 적어보겠습니다. 다음 주제들을 하나씩 다뤄볼게요. 

- **Symmetric 스레드 모델**: 역할이 고정된 스레드가 아닌, 모든 스레드가 모든 일을 처리하는 방식
- **메시지 큐와 스케줄링**: `JobDispatcher`를 중심으로 한 작업 분배
- **Starvation 방지**: `readyQueue`를 통한 공정한 처리
- **동기/비동기 메시지 분리**: `await` 키워드와 함께 자연스럽게 동작하는 구조

<!--more-->
---

## 왜 직접 만드는가?

본격적인 설명에 앞서, 한 가지 의문을 먼저 다루어 보겠습니다.

> **C#에는 Akka.NET, Orleans 같은 검증된 Actor 프레임워크가 있는데, 왜 직접 만들어 쓰나요?**

분명 바퀴를 다시 발명하지 말라고 했는데. 게임 만들기도 바쁜 와중에 Actor까지 직접 구현을 하는 걸까요.

`게임 개발`이라는 이름으로 모든 게임 프로젝트를 통틀어 이야기할 수는 없습니다. 모든 상황에는 필요와 목적이 다 다를테니까요.  하지만 기존의 훌륭한 프레임워크들은 적어도 제가 필요한 용도로 활용하기에는 조금 **목적이 달랐기 때문**입니다.

### 분산 시스템이 목표가 아니다

Akka.NET이나 Microsoft Orleans는 많은 곳에서 사용되는 검증된 범용적인 Actor 프레임워크입니다. 다양한 프로젝트에 사용할 수 있도록 말 그대로의 범용성(generality)을 중시하는 프레임워크면서, 다분히 **네트워크를 넘어 여러 노드에 걸쳐 동작하는 분산 Actor 시스템**을 목표로 합니다. 클러스터 관리, 원격 메시징, 장애 복구, 퍼시스턴스 등 엔터프라이즈급 기능들을 제공합니다.

하지만 제가 필요한 것은 그런 게 아닙니다. **단일 프로세스 내에서 게임 오브젝트들 간의 동시성을 관리**하는 것이 목표입니다. 네트워크를 넘어가는 분산 처리도 물론 필요한 부분이 있습니다만, 그건 제가 별도의 스택으로 만들어 올리는 것이 모듈화 면에서도 더 낫다고 판단했습니다.

이런 상황에서 분산 시스템용 프레임워크를 사용한다면 뭐랄까.. 체형보다 좀 큰 사이즈의 헐거운 옷을 입는 느낌이 듭니다.

- 필요 없는 기능들이 오버헤드로 작용
- 프레임워크의 추상화들은 학습 곡선을 높임
- 디버깅과 성능 튜닝이 어려워짐

### 검증된 구현에서 출발하기

저는 운이 좋게도 이전의 몇몇 프로젝트들에서 출중하신 고수 동료님들이 계신 좋은 환경에서 자체 구현한 lock-free Actor 기반으로 게임을 만들어본 경험이 있었습니다. 다행히 지금의 아키텍처가 어느 정도 익숙하고 부담이 없는 편이었습니다. 

특히 github에 공개된 [zeliard/Dispatcher](https://github.com/zeliard/Dispatcher) 구현은 큰 바탕이 되었습니다. 현재 사용 중인 코드는 zeliard님의 구현을 상당부분 C#으로 그대로 이식해온 단계에서 시작했다고 할 수 있어요. 본 포스팅에서 초반부에 설명할 스레드 운용 방식은 완전히 동일합니다. 좋은 자료를 공유해주시는 zeliard님 감사드립니다 _ _) 

제가 필요한 기능들은 몇백 줄이면 충분히 작성할 수 있습니다. 직접 만들어둔 기반 코드는 프로젝트를 진행하여 변화해가는 필요에 따라 민첩하게 개량하기에도 용이합니다.

**필요한 것:**
- 메시지 큐와 단일 스레드 실행 보장
- `async/await`와의 자연스러운 통합
- 가벼운 메모리 풋프린트
- 빠른 메시지 처리

**필요 없는 것:**
- 원격 Actor 지원
- 클러스터링
- Actor 퍼시스턴스
- 복잡한 감독(Supervision) 전략

몇가지 관점에서 서로간의 특징을 간단히 정리해보면 다음과 같습니다.

| 비교 항목 | 자체 구현 | Akka.NET | Orleans |
|----------|----------|----------|---------|
| **코드 복잡도** | ✅ 낮음 (수백 줄) | ❌ 높음 | ❌ 높음 |
| **외부 의존성** | ✅ 없음 | ❌ 많음 | ❌ 많음 |
| **학습 곡선** | ✅ 낮음 | ❌ 높음 | ⚠️ 중간 |
| **분산 시스템** | ❌ | ✅ | ✅ |
| **클러스터링** | ❌ | ✅ | ✅ |
| **퍼시스턴스** | ❌ | ✅ | ✅ |
| **적합 용도** | 단일 서버 게임 | 분산 시스템 | 클라우드 분산 |

---

## 고전적 스레드 모델 vs Symmetric 모델

코드로 들어가기 전에, 먼저 스레드 운용 방식에 대한 배경을 짚고 넘어가겠습니다.

### Role-based Threading (고전적 방식)

전통적인 게임 서버에서는 스레드에 **역할(Role)** 을 부여하는 방식이 흔합니다.

![](thread_00.png)

이 방식은 직관적이고 이해하기 쉽습니다. 네트워크 패킷은 I/O 스레드가, 게임 로직은 로직 스레드가, DB 쿼리는 DB 스레드가 담당합니다. 각 스레드가 자기 일만 하면 됩니다.

하지만 문제가 있습니다. **부하가 불균형**할 때 비효율이 발생합니다. 로직이 폭주하는 상황에서 I/O 스레드는 놀고 있을 수 있고, 반대의 경우도 마찬가지입니다.

### Symmetric Threading (Actor 방식)

Actor 모델에서는 다른 접근을 취합니다. 스레드에 역할을 부여하지 않고, **모든 스레드가 모든 종류의 일을 처리**합니다.

![](thread_01.png)

"일을 스레드에 배정"하는 것이 아니라, "일을 큐에 넣으면 아무 스레드나 가져가서 처리"하는 방식입니다. 이렇게 하면 **모든 코어를 균등하게 활용**할 수 있습니다. 한쪽이 바쁠 때 놀고 있는 스레드가 없습니다.

이렇게 서로간에 affinity가 없는 워커와 잡을 어떻게 연결할 것인가. 
누가 어떤 일을 하게 할 것인가.
얼마나 가볍고(lock-free) 간결하게(simplicity) 스케줄링할 것인가.

아쉽게도 전체 코드를 공개하긴 어렵지만 맥락을 이해할 수 있는 적절한 단계의 코드들과 함께 차례대로 살펴보겠습니다.

---

## Actor의 핵심: JobDispatcher

이제 실제 코드를 살펴보겠습니다. 이 Actor 구현체의 핵심은 `JobDispatcher` 클래스입니다.

### 기본 구조

```csharp
public sealed class JobDispatcher
{
    // 현재 스레드가 처리 중인 dispatcher 추적
    private static AsyncLocal<JobDispatcher> asyncLocalDispatcher = new AsyncLocal<JobDispatcher>();

    // 대기 중인 dispatcher들의 큐
    private static ConcurrentQueue<JobDispatcher> readyQueue = new ConcurrentQueue<JobDispatcher>();

    // 이 dispatcher의 메시지 큐
    private readonly ConcurrentQueue<IMessage> jobQueue = new ConcurrentQueue<IMessage>();

    // 현재 대기 중인 메시지 수
    private volatile int jobCount;

    // 비동기 메시지 실행 중일 때 보관
    private IMessage pending;
}
```

핵심 필드들을 살펴보면:

- **`asyncLocalDispatcher`**: `AsyncLocal`을 사용하여 현재 스레드가 어떤 dispatcher를 처리 중인지 추적합니다. 이것이 "이 스레드는 지금 이 Actor의 일을 하고 있다"를 나타내는 표식입니다.
- **`readyQueue`**: 처리 대기 중인 dispatcher들을 담는 전역 큐입니다. Starvation을 방지하기 위해 사용합니다.
- **`jobQueue`**: 이 dispatcher에 쌓인 메시지들입니다. `ConcurrentQueue`를 사용하여 lock-free로 동작합니다.
- **`jobCount`**: 현재 큐에 있는 메시지 수입니다. `Interlocked` 연산으로 관리됩니다.

> **Note:** Concurrent Collections in C#
>
> C#에는 `ConcurrentDictionary`, `ConcurrentQueue`, `ConcurrentBag` 등 여러 Concurrent Collection들이 기본 라이브러리로 제공됩니다. 이들은 모두 스레드 안전성을 보장하지만, 모든 컬렉션이 lock-free로 만들어진 것은 아닙니다. 대표적으로 `ConcurrentDictionary`는 멀티스레드 환경에 사용하기 아주편리한 api를 갖고 있으나, 내부적으로 잠금을 사용하며 상대적으로 무겁습니다. 
반면 `ConcurrentQueue`는 내부 잠금 없이 동작하여 가볍습니다. C++의 경우 MPSC(Multi-Producer Single-Consumer) Queue를 직접 구현하여 사용했었지만, C#의 `ConcurrentQueue`는 충분히 대체 가능한 수준의 성능을 제공합니다.
>
> - C++ MPSC Queue 는 [zeliard/Dispatcher](https://github.com/zeliard/Dispatcher) 저장소에 참고할 만한 코드가 있습니다.

### Post() - 메시지 전송

Actor에게 메시지를 보내는 것은 `Post()` 메서드를 통해 이루어집니다. 이 부분이 스레드 스케줄링 방식을 가장 직접적으로 담고 있는 곳입니다.

```csharp
// class JobDispatcher의 멤버 메서드입니다.
internal void Post(IMessage message)
{
    if (message == null)
        return;

    // 1. 메시지 수 증가 & 큐에 추가
    int incremented = Interlocked.Increment(ref this.jobCount);
    this.jobQueue.Enqueue(message);

    // 2. 이미 다른 메시지가 처리 중이면 리턴
    if (incremented != 1)
        return;

    // 3. 현재 스레드가 다른 dispatcher를 처리 중이면
    if (asyncLocalDispatcher.Value != null)
    {
        // 대기열에 넣고 나중에 처리
        readyQueue.Enqueue(this);
        BackgroundJob.Execute(() => TryConsumeReadyQueue());
        return;
    }

    // 4. 바로 실행 시작
    this.Execute();
}
```

흐름을 따라가 보면:

1. 먼저 `jobCount`를 증가시키고 메시지를 큐에 넣습니다.
2. `incremented`가 1이 아니면, 이미 다른 메시지가 처리 중이므로 그냥 리턴합니다. 나중에 차례가 오면 처리됩니다.
3. 현재 스레드가 이미 다른 dispatcher를 처리 중이라면, `readyQueue`에 넣어둡니다.
4. 그렇지 않으면 바로 `Execute()`를 호출하여 실행을 시작합니다.

이 로직의 핵심은 Post() 메서드를 처리중인 스레드의 입장에서, **"큐의 맨 앞에 메시지를 넣은 것이 내가 맞는지"** 확인하는 것입니다. `incremented == 1`이면 내가 방금 넣은 메시지가 큐의 첫 번째이므로, 실행을 시작해야 합니다.

`Post()` 메서드를 처리중인 스레드를 `나`라고 표현하고 순서도를 그려보면 다음과 같습니다. 개념을 이해할 때에도 스레드의 입장에서 따라가보는 것이 좀 더 쉽습니다.

![](flowchart_post.png)

---

## Starvation 방지: readyQueue

`readyQueue`의 존재 이유를 좀 더 자세히 살펴보겠습니다.

### 문제 상황

Actor A의 메시지를 처리하는 도중에, 처리 로직이 Actor B에게 메시지를 보낸다고 가정해 봅시다.

```csharp
// Actor A의 메시지 핸들러 내부
void HandleSomething()
{
    // ... 처리 ...
    actorB.Post(() => DoSomething());  // B에게 메시지 전송
    // ... 계속 처리 ...
}
```

B의 `Post()`가 호출될 때, 현재 스레드는 A를 처리 중입니다. 만약 B의 메시지도 즉시 실행한다면?

```
A 처리 중 → B.Post() → B 처리 시작 → B가 C에게 Post → C 처리 시작 → ...
```

이런 식이라면 **스택이 끝도없이 깊어질 수 있습니다.** 또한 특정 호출 체인에 있는 Actor들만 계속 처리되고, 다른 Actor들은 굶주리는(starve) 상황이 발생할 수 있습니다. 우리가 잠금없는 가벼운 actor를 구현하는 목적을 다시 생각해볼까요. 게임 월드내에 밀집된 공간에서 수많은 유저들이 주고받는 상호작용들도 충분히 소화할 수 있는 가벼운 기반을 만드는 것이었잖아요. 하지만 게임 오브젝트간 인터랙션이 인텐시브 해질수록 처리못한 메시지가 쌓이기만 하는 식이라면 맘편히 이 위에 게임 로직을 쌓아올릴 수 없을 것입니다.

### 해결책: readyQueue

그래서 `readyQueue`를 사용합니다. 현재 스레드가 이미 dispatcher를 하나 소유하고 처리하고 있는 중이라면(on busy), 새로 활성화된 dispatcher가 생기더라도 `readyQueue`에 넣어두고 나중에 처리합니다.

```csharp
// class JobDispatcher의 멤버 메서드입니다.
private void Execute()
{
    JobDispatcher target = this;
    asyncLocalDispatcher.Value = this;  // 이 스레드가 이 dispatcher를 소유

    do
    {
        target.InvokeMessages();  // 메시지들 처리
        readyQueue.TryDequeue(out target);  // 대기 중인 다른 dispatcher
        asyncLocalDispatcher.Value = target;
    }
    while (target != null);

    // 모든 처리 완료
    asyncLocalDispatcher.Value = null;
}
```

`Execute()`는 단순히 자신의 메시지만 처리하고 끝나는 것이 아닙니다. 처리가 끝나면 `readyQueue`에서 대기 중인 다른 dispatcher를 꺼내서 연속으로 처리합니다. 그래야 스레드를 할당받지 못하는 Actor가 없이 모든 메세지들을 소화할 수 있게 됩니다.

또한 스레드의 불필요한 반환을 줄이는 역할도 합니다. 작업을 마친 스레드가 ThreadPool로 돌아갔다가 다시 깨어나는 과정에는 비용이 듭니다. `readyQueue`에 처리할 dispatcher가 남아있다면 스레드를 바로 반환하지 않고 연속으로 처리하여, 이런 왕복 비용을 줄입니다. OS의 타임 슬라이스 만료로 인한 컨텍스트 스위칭은 피할 수 없지만, 그 외에 우리 코드에서 발생시키는 부가적인 스위칭 비용은 최소화합니다.

![](flowchart_execute.png)

여기까지. 스레드가 어떤 식으로 자기 할 일을 찾게 되는지 조금 전달이 되었나요? 이제 우리는 충분히 가볍고 빠르면서 문제없이 동작하는 스레드 스케줄링 방식을 알아보았습니다.

---

## 동기/비동기 메시지 분리

마지막으로, 동기 메시지와 비동기 메시지의 분리에 대해 살펴보겠습니다.
포스팅의 길이상 여기에서 한 번 끊어갈까, 생각도 했습니다만... 스레드 운용 측면에서 c#의 await 분절 이후 처리까지 같이 이야기 되어야 온전한 세트가 됩니다. 글이 조금 길어지지만 조금만 더 따라가 봅시다.

### 왜 분리가 필요한가?

C#의 `async/await`를 사용하면, `await` 키워드를 만나는 순간 실행 컨텍스트가 "끊깁니다". 메서드가 중간에 리턴하고, 나중에 비동기 작업이 완료되면 이어서 실행됩니다.

```csharp
async Task DoSomethingAsync()
{
    Console.WriteLine("시작");
    await SomeAsyncOperation();  // 여기서 리턴됨. 아주 매끄럽게 아랫줄 실행할 것처럼 생겼지만 훼이크임.
    Console.WriteLine("끝");     // 나중에 실행됨. 사실 언제 어느 스레드가 이어서 실행할지 알 수도 없음.
}
```

Actor에게 전달한 메시지(job)의 로직이 `async`라면, 실행 도중 `await`를 만났을 때 `JobDispatcher.InvokeMessages()` 입장에서는 메서드가 이미 리턴한 것입니다. 아직 실제 처리는 다 끝나지 않았지만 말이예요!

이 상태에서 잡큐에 들어있는 다음 메시지를 꺼내 이어서 처리하면, **동일한 Actor에 대해 두 개의 메시지가 동시에 실행**되는 문제가 발생합니다. Actor의 가장 핵심 원칙인 "단일 스레드 접근"이 깨져 버리는 순간입니다.

### IMessage 인터페이스

이 문제를 해결하기 위해 메시지에 `Continuable` 플래그를 둡니다.

```csharp
public interface IMessage
{
    bool Continuable { get; }
    string Tag { get; }
    void Execute();
}
```

- **`Continuable = true`**: 동기 메시지. `Execute()` 호출 후 바로 다음 메시지로 넘어가도 됨.
- **`Continuable = false`**: 비동기 메시지. `Execute()` 호출 후 await 완료를 기다려야 함.

### 동기 메시지 (ActorSync)

```csharp
internal sealed class ActorSync : IMessage
{
    private Action action;

    public bool Continuable => true;

    public void Execute()
    {
        this.action.Invoke();  // 실행하고 끝
    }
}
```

동기 메시지는 단순합니다. `Execute()`가 리턴하면 처리가 완료된 것입니다.

### 비동기 메시지 (ActorAsync)

```csharp
internal sealed class ActorAsync : IMessage
{
    private Func<Task> func;

    public bool Continuable => false;

    public async void Execute()
    {
        try
        {
            await this.func.Invoke();
        }
        finally
        {
            // await가 완료된 후 다음 메시지 처리 재개
            JobDispatcher.AsyncLocalDispatcher.ContinueAfterAwait();
        }
    }
}
```

비동기 메시지는 `async void Execute()`입니다. `await`가 완료된 후에 `ContinueAfterAwait()`를 호출하여 다음 메시지 처리를 재개합니다.

### InvokeMessages()에서의 처리 분기

다시 JobDispatcher로 돌아옵니다. `InvokeMessages()`는 이 `Continuable` 플래그에 따라 다르게 동작합니다.

```csharp
// class JobDispatcher의 멤버 메서드입니다.
private void InvokeMessages()
{
    while (true)
    {
        this.jobQueue.TryPeek(out IMessage message);

        this.pending = message;
        message.Execute();

        if (!message.Continuable)
        {
            // 비동기 메시지: await 완료 대기
            return;
        }

        // 동기 메시지: 바로 다음으로
        this.jobQueue.TryDequeue(out _);
        this.pending = null;

        int decremented = Interlocked.Decrement(ref this.jobCount);
        if (decremented == 0)
            return;
    }
}
```

메세지를 하나씩 꺼내서 처리할 때 비동기 메시지라면, `IMessage.Execute()` 호출 후 다음 메세지를 꺼내지 않고 바로 리턴합니다. 멤버변수 `this.pending`에 지금 처리중인 메시지의 참조를 기억해 두었습니다. 나중에 처리중인 메시지 내부의 `await`가 완료되어 `JobDispatcher.ContinueAfterAwait()`가 호출되면 그때 `this.pending`을 정리하고 다음 메시지 처리를 재개합니다.

![](flowchart_invokemessages.png)

---

## 마치며

지금까지 경량 Actor 구현체의 핵심 구조를 살펴보았습니다. 이번 글은 여러가지 주제를 언급하는 대신 가장 기본이라 할만한 스레드의 흐름을 위주로 정리했습니다. 이렇게만 해도 내용이 제법 적지 않네요. 좀 더 소개하고 싶은 구현상의 이슈들은 분량 조절의 실패로 인해... 다음 포스팅에서 정리 해보겠습니다.

**핵심 정리:**

1. **Symmetric 스레드 모델**: 모든 스레드는 모든 일을 처리. 작업 분배의 불균형 없이 리소스 활용 극대화.
2. **JobDispatcher**: Actor의 메시지 큐와 실행을 담당. `AsyncLocal`로 소유권 추적.
3. **readyQueue**: 현재 스레드가 바쁠 때 다른 dispatcher를 대기열에 넣어 Starvation 방지.
4. **Continuable 플래그**: 동기/비동기 메시지 구분. `await`후 안전하게 진행을 재개.

다음 글에서는 실제 구현하고 직접 사용하는 과정에서 은근히 고민하게 만들거나 신경이 쓰였던 세부적인 내용 주제들을 다룹니다:

- **람다를 이용한 작업 효율 향상**: 액터에 전달할 메세지타입을 일일이 정의하지 말고, 컴파일러가 제공하는 편의성을 누려봅시다.
- **생명주기 제어**: C#은 GC가 있는 대신 C++의 `std::shared_ptr<>`에 "꼭 맞는" 동작이 없더라고요.
- **클로저 캡처 문제**: C++의 람다는 캡쳐리스트가 좀 더 명시적인 반면, C#의 람다는 암묵적인 캡쳐가 너무 쉽게 일어나더라고요.
- **C# 단일 상속 제약**: C#에서는 단일상속만 지원을 해요. 부모클래스가 두 개일 수 없더라고요.

---

*다음 글: C#으로 구현하는 경량 Actor (2) - 생명주기 제어 및 언어적 특성들 (예정)*
