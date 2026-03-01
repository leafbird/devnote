---
title: Implementing Lightweight Actor in C# (2) - 생명주기 제어 및 언어적 특성들
date: 2026-00-00 10:00:00
tags:
- actor
- multithread
- csharp
- gameserver
---

{% asset_img header.png %}

## 들어가며

지난 글({% post_link Implementing-Lightweight-Actor-in-CSharp-Part1 "링크" %})에서는 경량 Actor 구현체의 핵심 구조를 살펴보았습니다. `JobDispatcher`를 중심으로 스레드가 어떻게 운용되는지, `readyQueue`로 Starvation을 어떻게 방지하는지, 그리고 `async/await`와 어떻게 통합되는지를 다루었습니다.

이번 글에서는 실제로 이 구조를 사용하는 과정에서 은근히 고민하게 만들었던 세부적인 주제들을 다루어 보겠습니다. C++에서 C#으로 이식하면서 마주친 언어적 차이, 그리고 그 차이를 어떻게 풀어냈는지에 대한 이야기입니다.

- **람다를 이용한 작업 효율 향상**: 메시지 타입을 일일이 정의하지 말고, 컴파일러가 제공하는 편의성을 누려봅시다.
- **생명주기 제어**: C#은 GC가 있는 대신 C++의 `std::shared_ptr<>`에 "꼭 맞는" 동작이 없더라고요.
- **클로저 캡처 문제**: C++의 람다는 캡쳐리스트가 좀 더 명시적인 반면, C#의 람다는 암묵적인 캡쳐가 너무 쉽게 일어나더라고요.
- **C# 단일 상속 제약**: C#에서는 단일상속만 지원을 해요. 부모클래스가 두 개일 수 없더라고요.

<!--more-->
---

## 람다를 이용한 메시지 전달

### 전통적인 방식의 번거로움

전통적인 Actor 패턴에서는 Actor에게 보내는 메시지마다 별도의 클래스를 정의해야 합니다.

```csharp
// 체력 변경 메시지
public class UpdateHealthMessage : IMessage
{
    private Player player;
    private int amount;

    public UpdateHealthMessage(Player player, int amount)
    {
        this.player = player;
        this.amount = amount;
    }

    public bool Continuable => true;

    public void Execute()
    {
        this.player.Health += this.amount;
    }
}

// 사용
player.Post(new UpdateHealthMessage(player, 10));
```

한 줄짜리 로직을 위해 클래스 하나를 정의하고, 필드를 선언하고, 생성자를 만들고, `Execute()`를 구현합니다. 게임 서버에서 Actor에게 보내야 할 메시지 종류는 수백, 수천 가지입니다. 이걸 하나하나 다 이렇게?

### 람다로 간결하게

C#의 람다를 활용하면 이 모든 보일러플레이트가 사라집니다.

```csharp
// 같은 동작을 한 줄로
player.Post(self => self.Health += 10);
```

끝입니다. 메시지 클래스를 정의할 필요가 없습니다. 람다가 곧 메시지입니다.

이를 가능하게 하는 API는 다음과 같습니다:

```csharp
public static class ActorExt
{
    // 동기 메시지
    public static void Post(this IActor actor, Action action,
        [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
    {
        var implementor = actor.ActorImplementor;
        var message = implementor.BuildMessage(action, TagBuilder.Build(file, line));
        implementor.Dispatcher.Post(message);
    }

    // 타입 안전한 동기 메시지 (JobOwner를 인자로 전달)
    public static void Post<T>(this IActor<T> actor, Action<T> job,
        [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
        where T : class
    {
        var implementor = actor.ActorImplementor;
        var message = implementor.BuildMessage(job, actor.JobOwner, TagBuilder.Build(file, line));
        implementor.Dispatcher.Post(message);
    }

    // 비동기 메시지
    public static void Post<T>(this IActor<T> actor, Func<T, Task> job,
        [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
        where T : class
    {
        // ...
    }
}
```

Extension Method 형태로 제공되기 때문에, `IActor`를 구현한 어떤 객체에서든 `this.Post(...)` 형태로 자연스럽게 사용할 수 있습니다.

`[CallerFilePath]`와 `[CallerLineNumber]`는 호출 위치를 자동으로 추적합니다. 메시지가 실행될 때 어디서 보낸 메시지인지를 로그에 기록하기에 디버깅에 유용합니다.

### 분산 시스템이 포기한 대가

그런데 왜 Akka.NET이나 Orleans 같은 프레임워크에서는 이런 간결한 방식을 제공하지 않을까요?

답은 **직렬화(Serialization)** 에 있습니다.

분산 Actor 시스템에서 메시지는 네트워크를 넘어갑니다. Node A의 Actor가 Node B의 Actor에게 메시지를 보내려면, 그 메시지를 바이트 스트림으로 직렬화해서 전송하고, 상대편에서 역직렬화해야 합니다.

```
[Node A]                            [Node B]
Actor.Tell(message)
    → Serialize(message)
    → Network Transfer  ─────────→ Deserialize(message)
                                    → Actor.Receive(message)
```

그런데 람다는 직렬화할 수 없습니다. 람다가 캡처하는 것들을 생각해보면:

```csharp
int localVariable = 42;
actor.Post(() => {
    Console.WriteLine(localVariable);  // localVariable 캡처
    this.DoSomething();                // this 캡처
});
```

이 람다는 `localVariable`의 참조, `this` 포인터, 메서드 컨텍스트 등을 캡처합니다. 이것들은 현재 프로세스의 메모리에 존재하는 것들이라 다른 머신으로 보낼 수 없습니다. Akka 공식 문서에서도 이렇게 경고합니다:

> "Using lambda-based actor creation is not recommended because it encourages closing over the enclosing scope, resulting in **non-serializable Props**."

그래서 분산 프레임워크들은 메시지를 반드시 직렬화 가능한 별도의 클래스로 정의하도록 강제합니다.

| 비교 항목 | 자체 구현 (단일 프로세스) | Akka.NET / Orleans |
|----------|------------------------|-------------------------------|
| **메시지 전송** | 메모리 내 참조 전달 | 네트워크를 통한 직렬화 전송 |
| **람다 사용** | ✅ 자유롭게 가능 | ❌ 직렬화 불가능 |
| **메시지 정의** | `actor.Post(self => ...)` | 별도 클래스 정의 필수 |
| **보일러플레이트** | ✅ 최소 | ❌ 많음 |

우리는 분산 시스템에 대한 욕심을 내려놓은 대신, 단일 프로세스 안에서의 개발 효율성을 극대화합니다. 직렬화 오버헤드 제로, 네트워크 레이턴시 제로, 메시지 타입 정의 불필요. 단일 서버 게임이라면 이쪽이 훨씬 실용적인 선택입니다.

---

## 생명주기 제어: Reference Counting

### GC만으로는 부족하다

C++에서는 `std::shared_ptr<>`가 참조 카운트를 관리하고, 카운트가 0이 되는 **즉시** 소멸자가 호출됩니다. 자원이 언제 정리되는지 정확히 알 수 있습니다.

C#에는 GC가 있습니다. 메모리는 알아서 수거해 줍니다. 하지만 문제는 **언제** 수거하는지 모른다는 것입니다.

Actor를 생각해보면, 단순히 메모리만 정리하면 되는 게 아닙니다. 네트워크 연결을 끊고, 컨테이너에서 자신을 제거하고, 다른 Actor들에게 퇴장을 알리고... 이런 정리 작업은 **결정적인 타이밍**에 이루어져야 합니다. GC가 "나중에 편할 때" 처리하도록 맡길 수 없습니다.

### ScopedActor와 참조 카운트

그래서 C++의 `shared_ptr`처럼 **참조 카운트(Reference Count)** 를 직접 관리합니다. 일반적인 방식으로 `Interlocked` 연산을 통해 스레드 안전하게 카운트를 증감시키고, 카운트가 0에 도달하면 정리 콜백이 호출됩니다.

흐름을 정리하면 다음과 같습니다:

```
[Actor 생성]
    ↓
referenceCount = 1 (초기 소유권)
    ↓
[사용 중]
LifeGuard.Guard() → AddReference() → refCount++
메시지 생성 → AddReference() → refCount++
    ↓
[비활성화 요청]
Deactivate() → ReleaseReference() → refCount--
    ↓
[참조 해제]
LifeGuard.Dispose() → ReleaseReference() → refCount--
메시지 실행 완료 → ReleaseReference() → refCount--
    ↓
[refCount == 0]
OnZeroReferenceAsync() 호출 → 리소스 정리
    ↓
[GC 대기]
남은 Strong Reference 모두 해제 → GC 메모리 수거
```

핵심은 참조 카운트의 **증감 시점**입니다. **누군가 이 Actor를 사용하려 할 때** 카운트를 올리고, **사용이 끝나면** 내립니다. 카운트가 0이 되는 순간은 곧 "더 이상 아무도 이 Actor를 필요로 하지 않는다"는 뜻이고, 그때 정리 작업이 시작됩니다.

### LifeGuard: using 패턴으로 안전하게

참조 카운트를 수동으로 올리고 내리는 건 실수하기 쉽습니다. `AddReference()`를 호출하고 `ReleaseReference()`를 깜빡하면 Actor가 영원히 살아남습니다. C++의 `shared_ptr`이 RAII로 이 문제를 해결한 것처럼, C#에서는 `IDisposable`과 `using`으로 해결합니다.

```csharp
public sealed class LifeGuard<T> : IDisposable where T : class, IScopedActor
{
    public T Target { get; }

    public static LifeGuard<T> Guard(T actor)
    {
        // 참조 증가 시도. Actor가 이미 종료되었으면 null 반환.
        if (actor.ScopedActorImplementor.AddReference() == false)
            return null;

        return new LifeGuard<T>(actor);
    }

    public void Dispose()
    {
        this.Target.ScopedActorImplementor.ReleaseReference();
    }
}
```

사용하는 쪽에서는:

```csharp
using (var guard = targetActor.Guard())
{
    if (guard == null)
    {
        // Actor가 이미 종료됨. 포기.
        return;
    }

    // 안전하게 사용
    guard.Target.Post(self => self.DoSomething());
}
// using 블록을 벗어나면 자동으로 ReleaseReference()
```

`using` 블록이 끝나면 `Dispose()`가 호출되어 참조가 자동으로 해제됩니다. 예외가 발생해도 마찬가지입니다. 참조 카운트 관리를 깜빡할 여지가 없습니다.

`Guard()`가 `null`을 반환하는 것도 중요합니다. Actor가 이미 비활성화된 상태라면 참조를 획득하는 것 자체가 실패하여, 종료된 Actor에게 무의미한 작업을 시도하는 것을 방지합니다.

---

## 클로저 캡처 문제

### C++은 명시적, C#은 암묵적

앞서 람다의 편리함을 이야기했지만, 편리함에는 그에 상응하는 함정이 따릅니다. C++과 C#의 람다를 비교해 봅시다.

C++의 람다는 캡처 리스트가 명시적입니다:

```cpp
auto lambda = [=]()  { /* 값 캡처 */ };
auto lambda = [&]()  { /* 참조 캡처 */ };
auto lambda = [this](){ /* this만 캡처 */ };
auto lambda = [x, &y](){ /* x는 값으로, y는 참조로 */ };
```

무엇을 캡처하는지 코드에 드러납니다. 코드 리뷰에서도 "아, 여기서 this를 캡처하는구나" 하고 바로 보입니다.

반면 C#의 람다는 암묵적으로 캡처합니다:

```csharp
var lambda = () => { this.DoSomething(); };  // this가 자동으로 캡처됨
```

편리하지만, 의도치 않은 캡처가 너무 쉽게 일어납니다.

### 문제: this 캡처와 생명주기

Actor 환경에서 이게 왜 문제가 될까요?

```csharp
public class Player : ScopedActorBase<Player>
{
    public void ProcessDamage(int amount)
    {
        this.Post(() => {
            this.Health -= amount;  // 여기서 this를 캡처!
        });
    }
}
```

이 코드에서 람다는 `this`(Player 객체)를 캡처합니다. 컴파일러가 생성하는 클로저 객체가 Player에 대한 강한 참조를 보유하게 됩니다. 메시지가 큐에서 대기하는 동안 Player 객체는 이 참조 때문에 GC되지 않습니다.

단순히 `Post()` 한두 번이면 큰 문제가 아닐 수 있지만, 타이머나 반복 작업에서 `this`를 캡처하면 Actor의 참조 카운트가 0이 되어도 클로저가 붙들고 있어서 메모리가 해제되지 않는 상황이 생길 수 있습니다.

### 해결: IActor\<T\>와 명시적 인자 전달

해결책은 `this`를 캡처하는 대신, **메시지 객체가 실행 대상을 명시적으로 보관**하도록 하는 것입니다.

내부 구현을 보면:

```csharp
internal sealed class ActorSync<T> : IMessage
{
    private Action<T> action;
    private T arg;  // 실행 대상을 여기에 보관

    public bool Continuable => true;

    public void Execute()
    {
        this.action.Invoke(this.arg);

        // 실행 완료 후 참조 해제
        this.action = null;
        this.arg = default;
    }
}
```

`Action<T>`는 인자를 하나 받는 델리게이트입니다. 실행 대상(`T`)은 람다가 캡처하는 것이 아니라 메시지 객체의 `arg` 필드에 저장됩니다. 실행이 끝나면 `null`로 초기화하여 참조를 해제합니다.

사용하는 쪽에서는:

```csharp
public class Player : ScopedActorBase<Player>, IActor<Player>
{
    public Player JobOwner => this;

    public void ProcessDamage(int amount)
    {
        // this 대신 self를 인자로 받는다
        this.Post(self => {
            self.Health -= amount;
        });

        // 이 람다가 캡처하는 것: amount (int, 값 타입)
        // 캡처하지 않는 것: this (메시지의 arg 필드로 전달됨)
    }
}
```

`self => self.Health -= amount`에서 `self`는 캡처된 것이 아니라 메시지 실행 시 인자로 전달되는 것입니다. 람다가 실제로 캡처하는 것은 `amount`뿐이고, `amount`는 `int`이므로 값 복사됩니다. `this`에 대한 강한 참조가 사라집니다.

이 패턴이 가능하려면 Actor가 `IActor<T>` 인터페이스를 구현해야 합니다. `T`는 자기 자신의 타입이고, `JobOwner` 프로퍼티를 통해 메시지에 전달될 실행 대상을 제공합니다. 다음 섹션에서 이 인터페이스에 대해 더 자세히 다루겠습니다.

### 추가 팁: 꼭 필요한 것만 캡처하기

`IActor<T>` 패턴을 사용하더라도, 캡처 대상에 항상 주의를 기울이는 습관은 중요합니다.

```csharp
// 객체 전체가 캡처됨
var otherActor = GetSomeActor();
this.Post(self => {
    Log.Info($"Other actor ID: {otherActor.Id}");
});

// 필요한 값만 캡처
int otherId = otherActor.Id;
this.Post(self => {
    Log.Info($"Other actor ID: {otherId}");
});
```

위의 예시에서 첫 번째 람다는 `otherActor` 객체 전체를 캡처합니다. 두 번째는 `int` 값 하나만 캡처합니다. 불필요한 객체 참조를 피하면 GC 압력도 줄이고, 의도치 않은 생명주기 연장도 방지할 수 있습니다.

---

## C# 단일 상속 제약: 인터페이스 + Implementor 패턴

### 부모가 두 명일 수 없다

C++에서는 다중 상속이 가능합니다:

```cpp
// C++: 가능
class Player : public GameObject, public Actor {
    // GameObject의 기능도, Actor의 기능도 모두 가짐
};
```

C#에서는 불가능합니다:

```csharp
// C#: 컴파일 에러!
public class Player : GameObject, Actor
{
    // 단일 상속만 지원
}
```

게임 오브젝트들은 대체로 이미 어떤 기반 클래스를 상속받고 있습니다. `GameObject`, `MonoBehaviour`, 혹은 프로젝트 고유의 `EntityBase` 같은 것들이요. 여기에 Actor 기능까지 상속으로 추가하고 싶지만, 상속 슬롯은 이미 차 있습니다.

### 해결: 인터페이스 + 조합

상속 대신 **인터페이스와 조합(Composition)** 으로 해결합니다. Actor의 "능력"을 인터페이스로 정의하고, 실제 구현은 별도의 Implementor 객체에 위임합니다.

```csharp
public interface IActor
{
    IActorImplementor ActorImplementor { get; }
}

public interface IActor<T> : IActor where T : class
{
    T JobOwner { get; }
}
```

`IActor`는 Actor로서의 능력을 나타내는 인터페이스입니다. 실제 동작은 `ActorImplementor`가 수행합니다. `IActor<T>`는 여기에 타입 안전한 메시지 전달을 위한 `JobOwner`를 추가합니다. `T`는 자기 자신의 타입으로, C++의 CRTP(Curiously Recurring Template Pattern)와 유사한 패턴입니다.

```
┌─────────────────┐         ┌──────────────────────┐
│   IActor<T>     │────────>│ IActorImplementor    │
│  (인터페이스)    │         │  (구현 위임)          │
└─────────────────┘         └──────────────────────┘
         △                            △
         │                            │
┌─────────────────┐  has-a  ┌──────────────────────┐
│  MyGameObject   │ ──────> │ ActorImplementor     │
│ (구상 클래스)    │         │  (실제 구현체)        │
└─────────────────┘         └──────────────────────┘
         │
    extends
         ▼
┌─────────────────┐
│   GameObject    │
│  (기존 부모)     │
└─────────────────┘
```

이제 기존 상속 구조를 건드리지 않고 Actor 기능을 추가할 수 있습니다:

```csharp
public class MyGameObject : GameObject, IActor<MyGameObject>
{
    // 1. JobOwner는 자기 자신
    public MyGameObject JobOwner => this;

    // 2. ActorImplementor를 조합으로 보유
    public IActorImplementor ActorImplementor { get; } = new ActorImplementor();

    // 3. Extension Method를 통해 Actor 기능 사용
    public void Initialize()
    {
        this.Post(self => self.DoSomething());
    }
}
```

`GameObject`를 상속받으면서 동시에 `IActor<MyGameObject>`를 구현합니다. Actor의 실제 동작은 `ActorImplementor` 인스턴스에 위임됩니다.

### Extension Method가 이어주는 것들

`Post()`, `Reserve()`, `RepeatVoid()` 등 Actor의 기능들은 모두 Extension Method로 제공됩니다:

```csharp
public static class ActorExt
{
    public static void Post<T>(this IActor<T> actor, Action<T> job, ...)
        where T : class
    {
        var implementor = actor.ActorImplementor;
        var message = implementor.BuildMessage(job, actor.JobOwner, ...);
        implementor.Dispatcher.Post(message);
    }

    public static void Reserve<T>(this IActor<T> actor, int msec, Action<T> job, ...)
        where T : class
    {
        // 지정한 시간 후에 실행
    }

    public static void RepeatVoid<T>(this IActor<T> actor, TimeSpan interval, Action<T> job, ...)
        where T : class
    {
        // 주기적으로 반복 실행
    }
}
```

이 구조 덕분에 `IActor<T>`를 구현하기만 하면 어떤 클래스든 Actor의 전체 기능을 사용할 수 있습니다. 상속 트리가 어떻게 생겼든 상관없습니다.

### 편의를 위한 기본 클래스

물론 다른 상속이 필요 없는 경우에는, 이 모든 것을 미리 구현해둔 기본 클래스를 상속받으면 됩니다:

```csharp
// 다른 상속이 없다면: 기본 클래스 상속이 편리
public class Player : ScopedActorBase<Player>
{
    // ActorImplementor, JobOwner 등 자동 제공
    // Reference Counting + LifeGuard도 포함

    public override Task OnZeroReferenceAsync()
    {
        // 참조 카운트 0일 때의 정리 로직
        return Task.CompletedTask;
    }
}

// 다른 상속이 필요하다면: 인터페이스 직접 구현
public class NpcObject : GameObject, IScopedActor<NpcObject>
{
    public NpcObject JobOwner => this;
    public ScopedActorImplementor ScopedActorImplementor { get; }
    public IActorImplementor ActorImplementor => this.ScopedActorImplementor;

    public NpcObject()
    {
        this.ScopedActorImplementor = new ScopedActorImplementor(this);
    }

    public Task OnZeroReferenceAsync()
    {
        // 정리 로직
        return Task.CompletedTask;
    }
}
```

두 가지 선택지를 제공하여, 상속 구조에 관계없이 Actor 기능을 사용할 수 있도록 합니다.

---

## Strong vs Weak Reference 메시지

### 메시지도 생명주기를 생각해야 한다

지금까지 참조 카운트로 Actor의 생명주기를 관리한다고 했습니다. 그런데 메시지 큐에 들어있는 메시지는 어떨까요? 메시지가 큐에서 실행을 기다리는 동안 Actor에 대한 참조를 들고 있다면, 참조 카운트가 0이 될 수 없습니다.

이 문제를 해결하기 위해 메시지를 **Strong**과 **Weak** 두 가지로 나눕니다.

### Strong Reference 메시지

Strong 메시지는 생성 시 Actor의 참조 카운트를 올리고, 실행 완료 시 내립니다. 메시지가 큐에 있는 동안 Actor가 종료되지 않음을 보장합니다.

```csharp
internal sealed class StrongSync : IMessage
{
    private ScopedActorImplementor actorImplementor;  // Strong Reference
    private Action action;

    public static IMessage Create(ScopedActorImplementor impl, Action action, ...)
    {
        // 메시지 생성 시 참조 카운트 증가
        return impl.AddReference()
            ? new StrongSync(impl, action, ...)
            : null;  // Actor가 이미 종료 → 메시지 생성 자체를 거부
    }

    public void Execute()
    {
        this.action.Invoke();
        this.actorImplementor.ReleaseReference();  // 실행 후 참조 해제

        // 참조 정리
        this.actorImplementor = null;
        this.action = null;
    }
}
```

### Weak Reference 메시지

Weak 메시지는 `WeakReference`를 사용하여 Actor를 약하게 참조합니다. Actor의 참조 카운트에 영향을 주지 않으므로, Actor가 종료되면 메시지는 실행되지 않고 자연스럽게 무시됩니다.

```csharp
internal sealed class WeakSync : IWeakMessage
{
    private WeakReference<ScopedActorImplementor> actorImplRef;  // Weak Reference
    private Action action;

    public void Execute()
    {
        // Actor가 아직 살아있는지 확인
        if (this.actorImplRef.TryGetTarget(out var impl) == false)
        {
            // Actor가 이미 사라짐 - 메시지를 조용히 무시
            this.action = null;
            return;
        }

        // 실행 시점에만 잠깐 참조를 획득
        if (impl.AddReference())
        {
            this.action.Invoke();
            impl.ReleaseReference();
        }
    }
}
```

### 어떤 걸 쓸까?

| 시나리오 | 메시지 타입 | 이유 |
|---------|------------|------|
| 일반 `Post()` | Strong | 보낸 메시지는 반드시 실행되어야 함 |
| 주기적 반복 (`Repeat`) | Weak | Actor 종료 시 자동으로 반복 중단 |
| 지연 실행 (`Reserve`) | Strong | 예약된 작업은 실행이 보장되어야 함 |
| 타이머 갱신 | Weak | Actor가 없으면 갱신도 무의미 |

`Repeat`이나 타이머처럼 **Actor가 살아있는 동안만 의미 있는 작업**은 Weak 메시지로 보냅니다. Actor가 종료되면 별도의 취소 로직 없이도 메시지가 자연스럽게 사라집니다.

반면 일반적인 `Post()`나 `Reserve()`처럼 **반드시 실행되어야 하는 작업**은 Strong 메시지로 보내어, 메시지가 큐에서 대기하는 동안 Actor가 살아있음을 보장합니다.

---

## 마치며

이번 글에서는 경량 Actor 구현체를 실전에서 사용하면서 마주친 C# 언어적 특성들을 다루어 보았습니다.

**핵심 정리:**

1. **람다 활용**: 메시지 클래스를 일일이 정의하지 않고 `self => ...` 한 줄로. 분산 시스템의 직렬화 제약이 없기에 가능한 이점.
2. **Reference Counting**: GC만으로는 부족한 결정적 소멸. `LifeGuard`의 `using` 패턴으로 안전하게.
3. **클로저 캡처**: `IActor<T>`와 `Action<T>` 패턴으로 `this` 캡처 방지.
4. **단일 상속 해결**: 인터페이스 + Implementor 패턴으로 어떤 상속 구조에서도 Actor 사용 가능.
5. **Strong/Weak 메시지**: 시나리오에 맞는 생명주기 관리.

이 시리즈를 통해 Actor 모델의 이론적 배경(1편)부터, 설계 선택(2편), 기본 구현(3편), 그리고 실전에서의 세부 이슈(이번 글)까지 살펴보았습니다. 몇백 줄의 코드로 시작한 구현이지만, 실제 프로젝트에서 수년간 사용되면서 하나씩 필요에 의해 다듬어진 것들입니다. 이 글이 비슷한 고민을 하시는 분들에게 도움이 되길 바랍니다.

---

*이전 글: {% post_link Implementing-Lightweight-Actor-in-CSharp-Part1 "C#으로 구현하는 경량 Actor (1) - 기본 구조와 스케줄링" %}*
