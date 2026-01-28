---
title: "C#으로 경량 Actor 구현하기"
date: 2026-01-28
categories:
  - Programming
tags:
  - Actor Pattern
  - C#
  - Game Server
  - Concurrency
---

## 들어가며

[이전 글](/2026/01/27/Applying-the-Actor-Pattern-to-MMO-Servers/)에서 Actor 패턴을 MMO 서버에 적용하는 방법을 살펴보았습니다. Zone 단위의 Coarse-grained 방식과 게임 오브젝트 단위의 Fine-grained 방식을 비교했고, 각각의 장단점을 분석했습니다.

이번 글에서는 실제로 C#에서 경량 Actor를 구현한 사례를 살펴봅니다. 기존 Actor 프레임워크들과 비교하여 어떤 설계 결정을 내렸는지, 그리고 게임 서버에 특화된 요구사항들을 어떻게 해결했는지 다룹니다.

## 기존 Actor 프레임워크들

C#/.NET 생태계에는 이미 검증된 Actor 프레임워크들이 존재합니다. 대표적인 세 가지를 살펴보겠습니다.

### Akka.NET

Akka.NET은 JVM의 Akka를 .NET으로 포팅한 프레임워크입니다. 가장 전통적인 Actor 모델을 따르며, 메시지 클래스를 정의하고 `Receive<T>` 핸들러로 처리하는 방식을 사용합니다.

```csharp
public class GreetingActor : ReceiveActor
{
    public GreetingActor()
    {
        Receive<Greet>(greet => Console.WriteLine($"Hello {greet.Who}"));
    }
}

// 메시지 전송
actorRef.Tell(new Greet("World"));
```

분산 시스템, 클러스터링, 지속성(Persistence) 등 엔터프라이즈급 기능을 제공하지만, 그만큼 학습 곡선이 가파르고 설정이 복잡합니다.

### Microsoft Orleans

Orleans는 Microsoft Research에서 시작된 "Virtual Actor" 모델을 구현합니다. Actor를 Grain이라고 부르며, 프레임워크가 Grain의 생성, 배치, 생명주기를 자동으로 관리합니다.

```csharp
public interface IHelloGrain : IGrainWithStringKey
{
    Task<string> SayHello(string greeting);
}

public class HelloGrain : Grain, IHelloGrain
{
    public Task<string> SayHello(string greeting)
    {
        return Task.FromResult($"Hello, {greeting}!");
    }
}
```

클라우드 환경에 최적화되어 있고 Azure와의 통합이 뛰어납니다. 하지만 Virtual Actor 모델 특성상 Actor의 생명주기를 직접 제어하기 어렵고, 상태 관리가 제한적입니다.

### Proto.Actor

Proto.Actor는 Akka의 원 저자 중 한 명이 만든 프레임워크로, Akka.NET보다 가볍고 현대적인 설계를 목표로 합니다. gRPC를 기본 통신 프로토콜로 사용하여 언어 간 상호운용성이 좋습니다.

```csharp
public class HelloActor : IActor
{
    public Task ReceiveAsync(IContext context)
    {
        if (context.Message is Hello hello)
        {
            Console.WriteLine($"Hello {hello.Who}");
        }
        return Task.CompletedTask;
    }
}
```

### 왜 직접 구현했나?

이들 프레임워크는 모두 훌륭하지만, 게임 서버 개발에는 몇 가지 아쉬운 점이 있습니다.

1. **무거운 의존성** - 클러스터링, 분산 시스템 지원 등 게임 서버에 불필요한 기능들이 포함되어 있습니다
2. **메시지 클래스 보일러플레이트** - 모든 통신에 별도의 메시지 클래스를 정의해야 합니다
3. **생명주기 제어 제한** - 게임 오브젝트의 세밀한 생명주기 관리가 어렵습니다
4. **디버깅 정보 부족** - 어떤 코드에서 메시지를 보냈는지 추적하기 어렵습니다

이러한 이유로 게임 서버에 특화된 경량 Actor를 직접 구현하게 되었습니다.

## 상속 대신 인터페이스: 유연한 설계

C#은 단일 상속만 지원합니다. 만약 Actor 기능을 제공하기 위해 특정 베이스 클래스를 상속받아야 한다면, 이미 다른 클래스를 상속받고 있는 타입은 Actor가 될 수 없습니다.

```csharp
// 이미 MonoBehaviour를 상속받고 있다면?
public class GameCharacter : MonoBehaviour  // BaseActor를 상속받을 수 없음
{
}
```

이 문제를 해결하기 위해 **인터페이스 + Implementor + 확장 메서드** 패턴을 사용했습니다.

### IActor 인터페이스

```csharp
public interface IActor
{
    ActorImplementor ActorImplementor { get; }
}

public interface IActor<T> : IActor
    where T : class, IActor
{
    T JobOwner { get; }
}
```

Actor가 되고 싶은 클래스는 `IActor` 인터페이스만 구현하면 됩니다. 실제 Actor 기능은 `ActorImplementor`가 담당합니다.

### ActorImplementor

```csharp
public sealed class ActorImplementor
{
    private readonly JobDispatcher dispatcher = new();

    public JobDispatcher Dispatcher => this.dispatcher;

    public bool IsInActorThread()
    {
        return JobDispatcher.Current == this.dispatcher;
    }
}
```

실제 메시지 큐와 디스패칭 로직을 담고 있는 클래스입니다. Actor를 구현하는 클래스는 이 객체를 멤버로 들고 있기만 하면 됩니다.

### 확장 메서드로 기능 제공

```csharp
public static class ActorExt
{
    public static void Post(this IActor actor, Action action,
        [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
    {
        var message = new ActorMessage.Sync(action, actor.ActorImplementor, TagBuilder.Build(file, line));
        actor.ActorImplementor.Dispatcher.Post(message);
    }

    public static void Post<T>(this IActor<T> actor, Action<T> action,
        [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
        where T : class, IActor
    {
        var message = new ActorMessage.Sync<T>(action, actor.JobOwner, actor.ActorImplementor, TagBuilder.Build(file, line));
        actor.ActorImplementor.Dispatcher.Post(message);
    }
}
```

확장 메서드를 통해 `Post`, `Reserve`, `Repeat` 등의 기능을 제공합니다. 이렇게 하면 어떤 클래스든 `IActor` 인터페이스만 구현하면 Actor의 모든 기능을 사용할 수 있습니다.

```csharp
public class Player : IActor
{
    private readonly ActorImplementor actorImplementor = new();
    public ActorImplementor ActorImplementor => this.actorImplementor;

    public void TakeDamage(int damage)
    {
        // 어디서든 Post로 메시지를 보낼 수 있습니다
        this.Post(() => this.ApplyDamage(damage));
    }
}
```

## 메시지 클래스 vs 람다: 보일러플레이트의 차이

전통적인 Actor 프레임워크에서는 모든 통신에 메시지 클래스를 정의해야 합니다.

```csharp
// Akka.NET 스타일
public class TakeDamageMessage
{
    public int Damage { get; }
    public TakeDamageMessage(int damage) => Damage = damage;
}

public class PlayerActor : ReceiveActor
{
    public PlayerActor()
    {
        Receive<TakeDamageMessage>(msg => ApplyDamage(msg.Damage));
    }
}

// 메시지 전송
playerRef.Tell(new TakeDamageMessage(10));
```

반면 람다 기반 방식은 훨씬 간결합니다.

```csharp
// 람다 기반
player.Post(() => player.ApplyDamage(10));
```

메시지 클래스를 정의할 필요도 없고, 핸들러를 등록할 필요도 없습니다. 보내고 싶은 동작을 람다로 바로 표현하면 됩니다.

이 방식은 특히 게임 서버처럼 다양한 종류의 상호작용이 빈번하게 발생하는 환경에서 개발 생산성을 크게 높여줍니다.

## 클로저 함정과 IActor&lt;T&gt;

람다 기반 방식에는 한 가지 함정이 있습니다. 바로 클로저 캡처 문제입니다.

```csharp
public class Monster : IActor
{
    private Player target;

    public void Attack()
    {
        // 문제: 람다가 실행될 때 this.target이 이미 바뀌어 있을 수 있습니다
        this.target.Post(() => this.target.TakeDamage(10));  // this.target 캡처
    }
}
```

위 코드에서 람다는 `this.target`을 캡처합니다. 하지만 `Post`는 비동기적으로 실행되므로, 람다가 실행될 시점에는 `this.target`이 이미 다른 값으로 바뀌어 있을 수 있습니다.

이 문제를 해결하기 위해 `IActor<T>`를 도입했습니다.

```csharp
public interface IActor<T> : IActor
    where T : class, IActor
{
    T JobOwner { get; }
}

public static void Post<T>(this IActor<T> actor, Action<T> action,
    [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
    where T : class, IActor
{
    var message = new ActorMessage.Sync<T>(action, actor.JobOwner, ...);
    actor.ActorImplementor.Dispatcher.Post(message);
}
```

`JobOwner`를 통해 메시지의 목적지를 명시적으로 지정하고, 람다에는 파라미터로 전달받도록 강제합니다.

```csharp
// JobOwner를 사용한 안전한 방식
Player currentTarget = this.target;
currentTarget.Post(p => p.TakeDamage(10));  // p는 Post 시점에 캡처된 currentTarget
```

람다의 파라미터 `p`는 `Post`를 호출한 시점에 캡처되므로, 나중에 `this.target`이 바뀌더라도 영향을 받지 않습니다.

## 게임 오브젝트 생명주기 관리

게임 서버에서 가장 까다로운 문제 중 하나는 오브젝트의 생명주기 관리입니다. 플레이어가 접속을 끊거나, 몬스터가 죽거나, 아이템이 사라질 때 해당 오브젝트로 예약된 메시지들을 어떻게 처리할 것인가?

### C++의 shared_ptr/weak_ptr

C++에서는 이 문제를 `shared_ptr`와 `weak_ptr`로 해결합니다. `shared_ptr`의 참조 카운트가 0이 되면 소멸자가 호출되어 정리 작업을 수행할 수 있습니다. `weak_ptr`로는 이미 해제된 객체에 대한 안전한 접근이 가능합니다.

하지만 C#의 GC 환경에서는 이런 방식을 그대로 사용할 수 없습니다.

- 소멸자(Finalizer) 호출 시점이 불확정적입니다
- GC가 언제 실행될지 예측할 수 없습니다
- `WeakReference`만으로는 "마지막 참조가 해제되는 시점"을 알 수 없습니다

### IScopedActor: 명시적 참조 카운팅

이 문제를 해결하기 위해 `IScopedActor`를 도입했습니다.

```csharp
public interface IScopedActor : IActor
{
    ScopedActorImplementor ScopedActorImplementor { get; }
    Task OnZeroReferenceAsync();
}
```

`OnZeroReferenceAsync()`는 C++의 소멸자 역할을 대신합니다. 참조 카운트가 0이 되는 시점에 명시적으로 호출되어, 정리 작업을 수행할 기회를 제공합니다.

### LifeGuard: 참조 카운팅 RAII

```csharp
public readonly struct LifeGuard<T> : IDisposable
    where T : class, IScopedActor
{
    private readonly WeakReference<IScopedActor<T>> actorRef;

    public static LifeGuard<T> Guard(T actor) { ... }

    public void Dispose()
    {
        // 참조 카운트 감소
        // 0이 되면 OnZeroReferenceAsync() 호출
    }
}
```

`using`과 함께 사용하여 RAII 스타일의 참조 관리가 가능합니다.

```csharp
using var guard = player.Guard();
// player 사용
// 스코프를 벗어나면 자동으로 참조 카운트 감소
```

### Strong vs Weak 메시지

`IScopedActor`에는 두 가지 종류의 메시지 전송 방식이 있습니다.

**Strong 메시지 (Post, Reserve, Repeat)**
- Actor에 대한 참조를 유지합니다
- 메시지가 처리될 때까지 Actor가 해제되지 않습니다
- Actor의 생존이 보장되어야 하는 중요한 작업에 사용합니다

**Weak 메시지 (WeakPost, WeakReserve, WeakRepeat)**
- Actor에 대한 약한 참조만 유지합니다
- Actor가 이미 해제되었으면 메시지가 무시됩니다
- 주기적인 업데이트, 타이머 등 Actor 해제 시 취소되어도 되는 작업에 사용합니다

```csharp
public class Player : IScopedActor<Player>
{
    public async Task OnZeroReferenceAsync()
    {
        // 정리 작업 수행
        await SaveToDatabase();
        UnregisterFromWorld();
    }
}

// 사용 예
player.Post(() => player.ImportantWork());      // Strong: 반드시 실행
player.WeakRepeat(TimeSpan.FromSeconds(1),      // Weak: 해제되면 자동 취소
    p => p.UpdatePosition());
```

## 작고 빠르게: 설계 원칙

### Lock-free 구현

메시지 큐는 `ConcurrentQueue<T>`를 사용하여 lock-free로 구현했습니다.

```csharp
public sealed class JobDispatcher
{
    private readonly ConcurrentQueue<IMessage> messageQueue = new();
    private int processing;

    public void Post(IMessage message)
    {
        this.messageQueue.Enqueue(message);
        this.TryStartProcess();
    }

    private void TryStartProcess()
    {
        if (Interlocked.CompareExchange(ref this.processing, 1, 0) != 0)
        {
            return;  // 이미 다른 스레드가 처리 중
        }

        // 처리 시작
        this.ProcessMessages();
    }
}
```

`Interlocked.CompareExchange`를 사용하여 lock 없이도 하나의 스레드만 메시지를 처리하도록 보장합니다.

### 디버깅을 위한 호출 위치 태그

모든 메시지 전송 메서드는 `[CallerFilePath]`와 `[CallerLineNumber]` 어트리뷰트를 사용하여 호출 위치를 기록합니다.

```csharp
public static void Post(this IActor actor, Action action,
    [CallerFilePath] string file = "",
    [CallerLineNumber] int line = 0)
{
    var tag = TagBuilder.Build(file, line);  // "PlayerController.cs:42"
    var message = new ActorMessage.Sync(action, actor.ActorImplementor, tag);
    // ...
}
```

문제가 발생했을 때 어떤 코드에서 해당 메시지를 보냈는지 즉시 확인할 수 있습니다.

### 분산 시스템: 프레임워크 레벨 미지원

이 구현은 분산 시스템을 프레임워크 레벨에서 지원하지 않습니다. 이는 의도된 설계 결정입니다.

**분산 시스템 지원의 비용**

- 직렬화/역직렬화 오버헤드
- 네트워크 실패 처리 복잡성
- 메시지 순서 보장 어려움
- 디버깅 난이도 증가

**대신 선택한 방식**

- 단일 프로세스 내에서 최적화된 성능 제공
- 필요시 네트워크 레이어를 직접 구현하여 동일한 비동기 패턴 달성 가능
- 게임 서버의 특성상 Zone 서버 간 통신은 별도 프로토콜로 처리하는 경우가 많음

```csharp
// 원격 서버의 Player에게 메시지를 보내야 할 때
// 프레임워크가 자동으로 처리하지 않고, 명시적으로 네트워크 레이어를 거침
if (targetPlayer.IsRemote)
{
    await networkLayer.SendAsync(targetPlayer.ServerId, new DamagePacket(damage));
}
else
{
    targetPlayer.Post(p => p.TakeDamage(damage));
}
```

이렇게 하면 로컬과 원격의 차이를 개발자가 인지하고 적절히 처리할 수 있습니다.

## 핵심 구현 살펴보기

### JobDispatcher: 심장부

`JobDispatcher`는 Actor 시스템의 심장부입니다. 메시지 큐, 처리 스레드 추적, 메시지 실행을 담당합니다.

```csharp
public sealed class JobDispatcher
{
    private static readonly AsyncLocal<JobDispatcher?> Processor = new();
    private readonly ConcurrentQueue<IMessage> messageQueue = new();
    private int processing;

    public static JobDispatcher? Current => Processor.Value;

    public void Post(IMessage message)
    {
        this.messageQueue.Enqueue(message);
        this.TryStartProcess();
    }

    private void TryStartProcess()
    {
        if (Interlocked.CompareExchange(ref this.processing, 1, 0) != 0)
        {
            return;
        }

        BackgroundJob.Execute(this.ProcessMessages);
    }

    private async Task ProcessMessages()
    {
        Processor.Value = this;  // 현재 스레드의 Dispatcher 설정
        try
        {
            while (this.messageQueue.TryDequeue(out var message))
            {
                await message.Execute();
            }
        }
        finally
        {
            Processor.Value = null;
            this.processing = 0;

            // 처리 중에 새 메시지가 들어왔을 수 있음
            if (!this.messageQueue.IsEmpty)
            {
                this.TryStartProcess();
            }
        }
    }
}
```

핵심 포인트는 다음과 같습니다.

1. `AsyncLocal<JobDispatcher?>`로 현재 실행 중인 Dispatcher를 추적합니다
2. `Interlocked.CompareExchange`로 lock-free 단일 처리자를 보장합니다
3. 처리 완료 후 새 메시지 확인으로 유실을 방지합니다

### GlobalTimer: Timing Wheel

예약된 메시지 실행을 위해 Timing Wheel 알고리즘을 사용합니다.

```csharp
public sealed class GlobalTimer
{
    private readonly CircularBuffer<LinkedList<IMessage>> shortDurationMessageBuckets;
    private readonly Dictionary<long, LinkedList<IMessage>> longDurationMessages;

    public static void Reserve(int msec, IMessage message)
    {
        InputCommands.Enqueue(new Command(msec, message));
    }
}
```

- 짧은 지연(수백ms)은 CircularBuffer로 O(1) 접근
- 긴 지연(수분 이상)은 Dictionary로 관리
- Resolution 설정으로 정밀도와 성능 트레이드오프 조절 가능

## 마치며

이 글에서는 게임 서버에 특화된 경량 Actor 구현을 살펴보았습니다. 주요 설계 결정을 요약하면 다음과 같습니다.

1. **인터페이스 + Implementor + 확장 메서드** - 단일 상속 제약 우회
2. **람다 기반 메시징** - 보일러플레이트 최소화
3. **IActor&lt;T&gt;와 JobOwner** - 클로저 캡처 함정 방지
4. **IScopedActor와 LifeGuard** - 명시적 생명주기 관리
5. **Strong/Weak 메시지** - 상황에 맞는 참조 정책
6. **Lock-free 구현** - 고성능 메시지 처리
7. **호출 위치 태깅** - 디버깅 용이성
8. **분산 시스템 미지원** - 복잡성 제거, 필요시 직접 구현

기존 프레임워크들이 범용성과 분산 시스템 지원에 초점을 맞추는 반면, 이 구현은 단일 프로세스 내에서의 성능과 게임 개발 편의성에 집중했습니다. 상황에 맞는 도구를 선택하는 것이 중요합니다.
