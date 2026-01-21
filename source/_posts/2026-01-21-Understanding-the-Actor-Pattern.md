---
title: Prologue - Understanding the Actor Pattern
date: 2026-01-21 10:09:02
tags:
- actor
- multithread
---

{% asset_img actor_prologue.png %}

## 들어가며

동시성 프로그래밍은 현대 소프트웨어 개발에서 피할 수 없는 주제입니다. 멀티코어 프로세서가 보편화되고, 분산 시스템이 일상이 된 지금, 효율적이고 안전한 동시성 처리는 더 이상 선택이 아닌 필수가 되었습니다.

이 글에서는 현재 프로젝트에서 직접 작성해 사용하고 있는 C# Actor 구현체를 소개하기에 앞서, 먼저 Actor 패턴의 이론적 배경을 살펴보고자 합니다. 특히 **POSA 2**에서 소개하는 동시성 패턴들을 중심으로, Actor 패턴이 어떤 맥락에서 등장했는지 이해해 보겠습니다.

<!--more-->
---

## POSA 2: Patterns for Concurrent and Networked Objects

**POSA(Pattern-Oriented Software Architecture)** 는 소프트웨어 아키텍처 패턴을 집대성한 시리즈로, 총 5권으로 구성되어 있습니다. 그 중 2권인 **"Patterns for Concurrent and Networked Objects"** 는 2000년에 출간되어, 동시성과 네트워크 프로그래밍 패턴의 바이블로 자리잡았습니다.

### 저자들

POSA 2는 네 명의 저자가 공동 집필했습니다:

- **Douglas C. Schmidt**: 미국 Vanderbilt 대학 교수이자 **ACE(Adaptive Communication Environment)** 프레임워크의 창시자입니다. ACE는 크로스플랫폼 동시성/네트워킹 프레임워크로, 이 책에서 소개하는 패턴들의 실제 구현체이기도 합니다. 보잉, 모토로라, 시스코 등 수많은 기업의 미션 크리티컬 시스템에 적용되었습니다.

- **Michael Stal**: Siemens 연구소의 수석 엔지니어로, 대규모 분산 시스템 아키텍처 분야의 권위자입니다.

- **Hans Rohnert**: 역시 Siemens 연구소 출신으로, 산업용 소프트웨어 아키텍처 전문가입니다.

- **Frank Buschmann**: POSA 시리즈 전체의 주축이 되는 인물로, 1996년 출간된 POSA 1권의 주 저자이기도 합니다. 현재는 Siemens Technology에서 수석 엔지니어로 활동하고 있습니다.

### 책의 위상

1994년 GoF(Gang of Four)의 **"Design Patterns"** 이 객체지향 설계 패턴의 교과서가 되었다면, POSA 2는 **동시성 패턴의 교과서**입니다. 25년이 지난 지금도 이 책에서 정의한 패턴 용어와 개념들—Reactor, Proactor, Active Object, Half-Sync/Half-Async, Leader/Followers 등—은 업계 표준으로 사용되고 있습니다.

Boost.Asio, libuv, Netty, gRPC 같은 현대 네트워킹 라이브러리들의 설계 철학을 이해하려면, 결국 이 책으로 돌아오게 됩니다.

---

## POSA 2의 동시성 패턴들

POSA 2권은 동시성과 네트워킹을 위한 패턴들을 집중적으로 다룹니다. 그 중에서도 이벤트 처리와 관련된 세 가지 핵심 패턴이 있습니다:

- **Reactor**
- **Proactor**
- **Active Object (Actor)**

이 패턴들은 모두 "이벤트를 어떻게 효율적으로 처리할 것인가"라는 공통된 문제를 다루지만, 각기 다른 접근 방식을 취합니다.

---

## Reactor 패턴

**Reactor**는 동기적 이벤트 디멀티플렉싱(demultiplexing)을 담당하는 패턴입니다. 하나의 스레드가 여러 이벤트 소스를 감시하다가, 이벤트가 발생하면 해당 이벤트 핸들러에게 처리를 위임합니다.

### 핵심 구조

```
[Event Sources] → [Synchronous Event Demultiplexer] → [Dispatcher] → [Event Handlers]
```

### 대표적인 예시: Event Handler 기반 GUI 프레임워크

Windows Forms나 WPF 같은 GUI 프레임워크의 메시지 루프가 전형적인 Reactor 패턴입니다:

```csharp
// 단일 스레드가 메시지 큐를 감시하며 이벤트를 디스패치
while (GetMessage(out msg, IntPtr.Zero, 0, 0))
{
    TranslateMessage(ref msg);
    DispatchMessage(ref msg);  // 적절한 핸들러로 전달
}
```

마우스 클릭, 키보드 입력 등 다양한 이벤트 소스를 하나의 루프에서 감시하고, 이벤트 발생 시 등록된 핸들러를 동기적으로 호출합니다.

### 특징

- **동기적 처리**: 이벤트 핸들러가 완료될 때까지 다음 이벤트를 처리하지 않음
- **단순한 프로그래밍 모델**: 핸들러 내에서 동시성을 고려할 필요가 적음
- **I/O 바운드 작업에 취약**: 핸들러가 블로킹되면 전체 시스템이 멈춤

---

## Proactor 패턴

**Proactor**는 비동기 I/O 완료를 처리하는 패턴입니다. Reactor와 달리 I/O 작업 자체를 OS에게 위임하고, 완료 통지를 받아 처리합니다.

### 핵심 구조

```
[Async Operation] → [OS Kernel] → [Completion Event Queue] → [Proactor] → [Completion Handlers]
```

### 대표적인 예시: IOCP (I/O Completion Port)

Windows의 IOCP는 Proactor 패턴의 대표적인 구현입니다:

```csharp
// 비동기 작업 시작
socket.BeginReceive(buffer, 0, buffer.Length, SocketFlags.None,
    OnReceiveCompleted, state);

// OS가 I/O를 수행하고, 완료되면 Completion Port에 통지
// Proactor(IOCP)가 완료 이벤트를 감지하여 핸들러 호출

void OnReceiveCompleted(IAsyncResult ar)
{
    // I/O는 이미 완료된 상태 - 결과만 처리
    int bytesRead = socket.EndReceive(ar);
    ProcessData(buffer, bytesRead);
}
```

### Reactor vs Proactor

| 구분 | Reactor | Proactor |
|------|---------|----------|
| I/O 수행 주체 | 애플리케이션 | OS 커널 |
| 이벤트 의미 | "읽을 준비가 됨" | "읽기가 완료됨" |
| 스레드 블로킹 | I/O 중 블로킹 | 블로킹 없음 |
| 대표 구현 | select, epoll, kqueue | IOCP, io_uring |

---

## Active Object (Actor) 패턴

**Active Object** 패턴은 메서드 호출(invocation)과 메서드 실행(execution)을 분리합니다. 각 Active Object는 자신만의 실행 컨텍스트(스레드)를 가지며, 외부 요청은 메시지 큐에 저장되어 순차적으로 처리됩니다.

### 핵심 구조

```
[Client] → [Proxy] → [Activation Queue] → [Scheduler] → [Servant]
                                              ↑
                                    [자체 스레드에서 실행]
```

### 개념

Active Object는 다음과 같은 구성요소로 이루어집니다:

1. **Proxy**: 클라이언트가 호출하는 인터페이스
2. **Activation Queue**: 요청을 저장하는 메시지 큐
3. **Scheduler**: 큐에서 요청을 꺼내 실행하는 컴포넌트
4. **Servant**: 실제 비즈니스 로직을 수행하는 객체

```csharp
// 개념적인 Active Object 사용 예시
var actor = new BankAccountActor();

// 메시지를 큐에 넣고 즉시 반환 (Fire-and-Forget)
actor.Post(() => actor.Deposit(100));
actor.Post(() => actor.Withdraw(50));

// 결과가 필요한 경우 - 큐잉 후 완료를 대기
var balance = await actor.PostAsync(() => actor.GetBalance());
```

### 장점

**1. 암묵적 동기화 (Implicit Synchronization)**

각 Actor는 자신의 상태에 대해 단일 스레드로 접근하므로, lock이나 mutex 같은 명시적 동기화가 필요 없습니다:

```csharp
// Actor 내부 - lock 없이 안전
private decimal _balance;

public void Deposit(decimal amount)
{
    _balance += amount;  // 단일 스레드 접근 보장
}
```

**2. 논리적 분리 (Logical Separation)**

각 Actor는 독립적인 실행 단위로, 복잡한 시스템을 작은 단위로 분해할 수 있습니다. 각 Actor는 자신의 책임에만 집중하면 됩니다.

**3. 위치 투명성 (Location Transparency)**

메시지 기반 통신은 Actor가 같은 프로세스에 있든, 다른 머신에 있든 동일한 방식으로 작동할 수 있게 합니다.

**4. 장애 격리 (Fault Isolation)**

한 Actor의 실패가 다른 Actor에게 직접적으로 전파되지 않습니다. 이는 탄력적인 시스템 설계를 가능하게 합니다.

**5. 자연스러운 비동기 처리**

메시지 전송은 본질적으로 비동기이므로, 시스템 전체가 논블로킹 방식으로 동작합니다.

---

## 세 패턴의 관계

**동시성 이벤트 처리**

| 구분 | Reactor | Proactor | Active Object |
|:----:|:-------:|:--------:|:-------------:|
| **특성** | 동기 이벤트 디멀티플렉싱 | 비동기 I/O 완료 이벤트 처리 | 메시지 기반 처리, 실행 분리 |
| **대표 구현** | Event Handler | IOCP | Actor, Akka, Erlang |

Reactor와 Proactor가 "이벤트를 어떻게 효율적으로 감지할 것인가"에 집중한다면, Active Object는 "이벤트(메시지)를 어떻게 안전하게 처리할 것인가"에 집중합니다. 실제로 많은 Actor 시스템들은 내부적으로 Reactor나 Proactor를 사용하여 I/O를 처리하고, 그 위에 Actor 모델을 구축합니다.

---

## 마치며

지금까지 POSA 2에서 소개하는 Reactor, Proactor, Active Object 패턴을 살펴보았습니다. 이 패턴들은 동시성 프로그래밍의 복잡성을 다루기 위한 검증된 해법들입니다.

특히 Active Object(Actor) 패턴은 "공유 상태 없이 메시지로 소통한다"는 단순하면서도 강력한 원칙으로, 복잡한 동시성 문제를 우아하게 해결할 수 있게 합니다.

첫 번째 글에서는 공감대 형성을 위해 간단한 소개만 적어 보았습니다. **다음 포스팅에서는 현재 프로젝트에서 구현하여 사용하고 있는 C# Actor 구현기를 적어보겠습니다.** 이론적 배경을 바탕으로, 실제로 어떻게 Actor 패턴을 C#에서 구현하고 활용할 수 있는지 구체적인 코드와 함께 살펴봅니다. 게임서버에서 중요하게 여기는 빠른 응답성, 게임객체들의 수명주기와 관련한 고려사항, 대량의 트래픽을 소화하기 위한 가벼운 구현 등의 이슈를 정리해 보겠습니다.

---

*다음 글: 게임서버를 위한 경량 액터모델 구현기 (예정)*
