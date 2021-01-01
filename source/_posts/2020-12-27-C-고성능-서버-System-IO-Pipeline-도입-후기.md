---
title: C# 고성능 서버 - System.IO.Pipeline 도입 후기
date: 2020-12-27 17:34:58
tags: [c#, 고성능, 게임서버, Network, Socket, Pipeline]
---
{% asset_img 00.jpg %}

2018년에 네트워크 레이어 성능을 끌어올리기 위해 도입했던 System.IO.Pipeline을 간단히 소개하고, 도입 후기를 적어본다. 

윈도우 OS에서 고성능을 내기 위한 소켓 프로그래밍을 할 때 IOCP 의 사용은 오래도록 변하지 않는 정답의 자리를 유지하고 있다. 여기에서 좀 더 성능에 욕심을 내고자 한다면 Windows Server 2012부터 등장한 [Registerd IO](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/hh997032(v=ws.11)) 라는 새로운 선택지가 있다. 하지만 API가 C++ 로만 열려 있어서, C# 구현에서는 사용하기가 쉽지 않다. 

하지만 C#에도 고성능 IO를 위한 새로운 API가 추가되었다. [Pipeline](https://docs.microsoft.com/ko-kr/dotnet/standard/io/pipelines) 이다.

<!-- more -->

## System.IO.Pipeline 소개.

pipeline을 처음 들었을 때는 IOCP의 뒤를 잇는 새로운 소켓 API인줄 알았다. C++의 RIO가 iocp를 완전히 대체할 수 있는 것처럼.

RIO는 가장 핵심 요소인 `등록된 버퍼(registered buffer)` 외에, IO 요청 및 완료 통지 방식도 함께 제공하기 때문에 iocp를 완전히 드러내고 대신 사용할 수 있다. 반면 Pipeline은 RIO보다는 커버하는 범위가 좁아서, IOCP를 완전히 대체하는 물건이 될 수는 없다. 이벤트 통지는 기존의 방법들을 이용하면서, 메모리 버퍼의 운용만을 담당하는 라이브러리 이기 때문에 IOCP와 반드시 함께 사용해야 한다.

Pipeline이라는 이름을 굉장히 잘 지었다. 이름처럼 **메모리 버퍼를 끝없이 연결된 긴 파이프라인처럼 쓸 수 있게 해주는 라이브러리** 이기 때문이다. 단위길이 만큼의 버퍼를 계속 이어붙여서 무한하게 이어진 가상의 버퍼를 만드는데, 이걸 너네가 만들면 시간도 오래 걸리고 버그도 넘나 많을테니 우리가 미리 만들었어. 그냥 가져다 쓰렴. 하고 내놓은 것이 Pipeline이다.

{% asset_img 01.png %}

(이미지 출처 : [devblogs.microsoft.com](https://devblogs.microsoft.com/dotnet/system-io-pipelines-high-performance-io-in-net/))

이미지의 초록색 부분은 `class Pipe` 의 내부 구조를 도식화한다. 일정한 크기의 작은 버퍼들이 링크드 리스트로 연결 되어있다. 내부 구조는 안에 숨겨져있고 외부로는 [ReadOnlySequence<T>](https://docs.microsoft.com/ko-kr/dotnet/api/system.buffers.readonlysequence-1?view=net-5.0) 타입을 이용해 버퍼간 이음매가 드러나지 않는 seamless한 인터페이스만을 제공한다. 이것이 Pipeline의 핵심이다.

이 외의 디테일한 부분은 Pipeline을 이해하기 쉽게 잘 설명한 [MS 블로그의 포스팅](https://devblogs.microsoft.com/dotnet/system-io-pipelines-high-performance-io-in-net/)이 있어 이것으로 대신한다.



## 장점 : 불필요한 메모리 복사를 없앤다. 

고성능 소켓 IO 구현에 관심이 있는 C++ 프로그래머라면 google protobuf의 [ZeroCopyStream](https://developers.google.com/protocol-buffers/docs/reference/cpp/google.protobuf.io.zero_copy_stream) 을 이미 접해봤을지 모른다. 그렇다면 Pipeline의 중요한 장점을 쉽게 이해할 것이다. Pipeline의 버퍼 운용 아이디어는 프로토콜 버퍼의 ZeroCopyStream과 유사하기 때문이다. 소켓으로 데이터를 주고 받는 과정에서 발생하는 불필요한 버퍼간 메모리 복사를 최소한으로 줄여주어 성능향상을 꾀한다는 점에서 두 라이브러리가 추구하는 방향은 동일하다. 

프로그래밍에 미숙한 개발자가 만든 서버일수록 버퍼간 복사 발생이 빈번하게 발생한다. 커널모드 아래에서 일어나는 소켓버퍼와 NIC 버퍼간의 복사까지는 일단 관두더라도, 최소한 유저모드 위에서의 불필요한 버퍼 복사는 없어야 한다. 

 전송할 데이터 타입을 버퍼로 직렬화 하면서 한 번 복사하고, 이걸 소켓에다가 send 요청을 하자니 OVERLAPPED에 연결된 버퍼에다가 넣어줘야 해서 추가로 또 복사하고... send 완료 통지 받고 나면 transferred bytes 뒤에 줄서있을 미전송 데이터들을 다시 앞으로 당겨주느라 또 한번 복사가 발생하기 쉽다. recv 받은 뒤에도 메시지 단위 하나 분량 만큼만 읽어 fetching하고 나면 뒤에 남은 데이터들을 버퍼 맨 앞으로 당겨와야겠으니... 여기서 또 한 번 추가복사 하게 될것이다.

서버가 감당할 통신량이 많아질수록 불필요한 복사들이 누적되어 쓸데없이 cpu power를 낭비하게 될텐데, Pipeline의 도입은 이런 부분을 쉽게 해결해 준다. msdn 블로그에서는 Pipeline을 사용하면 복잡한 버퍼 운용 구현을 대신 해결해주니까 프로그래머가 비즈니스 로직의 구현에 좀 더 집중할 수 있게 도와준다고 ~~약을 팔고~~ 설명하고 있다.



## 장점 : 네트워크 버퍼의 고정길이 제약을 없애준다.

가장 단순하게 소켓 레이어를 구현하면 송/수신용 고정 사이즈 `byte[]` 버퍼를 각각 하나씩 붙여서 만들게 될 것이다. 대략 구현중인 게임이 어느 정도 사이즈의 패킷을 주고 받는지를 **귀납적**으로 파악해서 (주로 게임 서버는 작은 사이즈 패킷을 많이 받고, 큰 사이즈 패킷을 많이 보낸다. 로그인할때, 캐릭터 선택할 때 보내는 패킷이 통상 제일 크다) 버퍼의 크기를 눈치껏 결정해서 `상수로 고정한다`. 버퍼를 거거익선으로 크게크게 잡으면 좋겠지만 대량의 동접을 처리해야 할때 메모리 사용량이 높아져서 부담이 된다. 그러니 적당히 오가는 패킷 사이즈를 봐서 터지지만 않을 정도의 고정길이 버퍼를 걸어두는 식으로 만들게 된다.

이렇게 만들면 불안하다. 컨텐츠를 점점 추가하다가 언젠가 한 두번은 네트워크 버퍼 overflow가 발생해 버퍼 크기를 늘려잡고 다시 빌드해야 하기 일쑤다. 아니면 버퍼를 넘치게 만든 문제 패킷의 구조를 변경하거나 두 개의 패킷으로 쪼개는 등 다이어트를 시켜서 해결할 수도 있겠다. 어느쪽이든 고성능 서버의 네트워크 레이어 구현으로는 적당하지 않은 솔루션이다. 메모리를 더 써서 해결하거나, 개발에 제약(패킷의 최대 크기)을 두어 해결하거나. 모두 석연치 않다.

Pipeline과 ZeroCopyStream 의 무한버퍼 컨셉은 이러한 고정길이 버퍼의 단점을 해결해준다. 처음엔 작은 크기의 버퍼만 가지고 있다가, 공간이 모자라면 추가로 더 할당받아 링크드 리스트 뒤에 붙이기만 하면 된다. 각각의 peer(= single socket)가 실제 사용하는 메모리 공간은 주고받는 데이터의 크기에 따라서 늘어나거나 줄어드는 유연성이 생긴다. 메모리를 효율적으로 사용하면서도 단일 메시지의 사이즈 제약도 없어진다.



## 단점 : 너무 많은 Task를 생성한다.

위의 두가지 장점만으로 Pipeline의 도입을 시도해볼 가치는 충분했다. 그래서 우리는 게임서버의 수신 버퍼를 Pipeline으로 대체하고, MS Azure 에서 F8s 급 인스턴스 수십대를 동원해 10만 동접 스트레스 테스트를 진행해 보았다. 

결과는 기대와 완전히 달랐는데.. **Pipeline 도입 전보다 영 더 못한 성능을 보여줬다**. 이건 뭐... cpu 사용량이 높고 낮아지는 것이 문제가 아니라, 동접이 일정수치 이상 오르면 서버가 아무 일도 처리하지 않고 멈춰버렸다. 반응없는 프로세스에서 덤프를 떠서 디버거로 살펴보면... 대기상태인 스레드가 잔뜩 생겨있고, 일해야 할 스레드가 부족해서 추가 스레드를 계속해서 만들어내고 있는 것처럼 보였다.

```csharp
// msdn 블로그에 소개된 코드 일부 발췌. Pipe를 하나 만들면 읽기/쓰기 Task를 2개 만든다.
async Task ProcessLinesAsync(Socket socket)
{
    var pipe = new Pipe();
    Task writing = FillPipeAsync(socket, pipe.Writer);
    Task reading = ReadPipeAsync(pipe.Reader);

    return Task.WhenAll(reading, writing);
}
```



원인은 Pipeline과 함께 사용하는 task (System.Threading.Tasks.Task) 들이었다.  `class Pipe` 인스턴스 하나를 쓸 때마다 파이프라인에 '읽기'와 '쓰기'를 담당하는 `class Task` 객체 두 개를 사용하게 된다. 수신버퍼에만 Pipe를 달면 소켓의 2배, 송수신 버퍼에 모두 달면 소켓의 4배수 만큼의 task가 생성 되어야 하기 때문이다. 게임서버 프로세스당 5,000 명의 동접을 받는다고 하면 최대 20,000개의 task가 생성되고, 이 중 상당수는 waiting 상태로 IO 이벤트를 기다리게 된다.

task가 아무리 가볍다고 해도 네트워크 레이어에만 몇 만개의 task를 만드는 것은 그리 효율적이지 않다. TPL에 대한 이야기를 시작하면 해야 할 말이 아주 많기 때문에 별도의 포스팅으로 분리해야 할 것이다. 과감히 한 줄로 정리해보면, task는 상대적으로 OS의 커널오브젝트인 스레드보다 가볍다는 것이지 수천 수만개를 만들만큼 깃털같은 물건은 아닌 것이다.

스레드가 코드를 한 단계씩 수행하다가 아직 완료되지 않은 task를 await 하는 구문을 만나면 호출 스택을 한 단계씩 거꾸로 올라가면서 동기 로직의 수행을 재개한다. 하지만 완료되지 않은 task를 만났다고 해서 그 즉시 task의 완료 및 반환값 획득을 포기하고 호출스택을 거슬러 올라가는 것은 아니다. 혹시 금방 task가 완료되지 않을까 하는 기대감으로 조금 대기하다가 완료된 기미가 보이지 않으면 그 제서야 태세를 전환하게 된다. 이 전략은 task가 동시성을 매끄럽게 처리하기 위해서는 바람직한 모습이지만, 아주 많은 개수의 task를 장시간(게임서버에서 다음 패킷을 받을 때까지의 평균 시간) 동안 대기시켜야 하는 네트워크 모델에 사용하기에는 적합하지 않다. 스레드들은 각 pipeline의 write task가 RecvComplete 통지를 받고 깨어나기를 기다리면서 수십만 cpu clock을 낭비하게 된다.



## 의문 : Kestrel은 Pipeline 때문에 엄청 빨라졌는데?

{% asset_img 02.png %}

(이미지 출처 : [stackoverflow.com](https://stackoverflow.com/questions/34440649/iis-vs-kestrel-performance-comparison))

ASP.NET Core는 Pipeline으로 구현한 kestrel 웹서버에서 실행할 때 기존의 iis 기반보다 훨씬 더 향상된 퍼포먼스를 보여준다. Pipeline의 버퍼 운용 효율성으로 인한 이득을 제대로 누리고 있는 것이다. kestrel의 뛰어난 성능 결과를 보여주는 여러 벤치마크 결과들 덕분에 나도 기대를 가득 안고 서둘러 Pipeline을 도입하고 테스트 해보았으나.. 결과는 좋지 않았다.

그럼 우리 게임서버에 도입한 테스트 결과는 왜 이리 처참한 것인가? ms 형들이 잘못 만들었을 리는 없으니 내가 가져다 붙이는 과정에 문제가 있었던 것인가? 

차이가 생기는 원인은 **Kestrel은 http 통신을 하는 웹서버이고, 우리의 게임서버는 연결을 유지하고 있는 TCP 서버이기 때문**이다. Kestrel은 통신량의 거의 전부가 socket이 열린 채로 길게 대기할 필요가 없기 때문에, task을 소켓의 2배수나 4배수만큼 오래도록 유지하고 있을 이유 자체가 없다. 그래서 단점으로 지적한 waiting task가 kestrel에서는 발생하지 않는다. 상술했던 단점을 다시 표현해 보자면 **Pipeline의 사용시 기본적으로 task 대기가 발생하는 것을 성능 하락의 원인으로 볼 수 있지만, 이 task들의 수명 혹은 대기시간이 상당히 길다는 점과 함께 만나면 성능을 더욱 악화시키는 원인이 된다**. Kestrel의 단명하는(?) 소켓들과 task들은 Pipeline와 함께 사용되면서 충분히 좋은 성능을 가져다 줄 것이다. 수많은 벤치마킹 결과들이 증명하듯이.



## 대안 : 불필요한 복사가 없는 가변버퍼를 직접 만들자.

우리는 게임서버에서 Pipeline을 다시 드러냈다. http와 유사하게 single pair request/response 통신 후 소켓을 닫아도 되는 경우가 아니면 Pipeline으로 성능상의 혜택을 보기는 힘들다고 판단했기 때문이다. 그래도 불필요한 메모리복사는 만들고 싶지 않으니 메모리 버퍼 운용하는 부분만 직접 구현해 사용하기로 했다.

{% asset_img 03.png %}

클래스 이름이 Pipeline과 protobuf를 모두 가져다 섞어놓은 느낌이 들겠지만 착각일 뿐이다. 두 api를 모두 사용해본 경험의 영향을 받긴 했지만... *Stream.cs 클래스들은 실제로 `System.IO.Stream`을 상속받아서 이름이 좀 비슷해졌다. 이 Stream 구현들이 단위버퍼들간의 연결을 seamless하게 쓸 수 있게해주는 역할을 한다. 주요 구현을 담고 있으나 사용계층에 노출될 필요는 없기 때문에 Detail 아래로 숨겨두었다. 사용자는 부모타입인 Stream 추상 클래스만 보게 된다.

인터페이스로 `ReadOnlySequence<T>`를 사용하지 않은 이유는 이 구현을 Unity3D로 만든 클라이언트에서도 똑같이 사용하기 위해서였다. 현시점 유니티의 mono framework가 지원하는 C# 문법 버전이 낮아서 `ReadOnlySequence<T>`를 지원하지 않기 때문이다. 그런데 Stream 을 이용해도 어렵지 않게 seamless 를 구현할 수 있었고, 실제 사용하기에도 스트림 형태가 훨씬 익숙하고 편해서 결과적으로는 더 만족스러운 선택이었다. `ReadOnlySequence<T>` 가 뭔지 모르는 프로그래머도 Stream은 알고 있을 것이다.

실제 사용 계층으로 노출하는 클래스는 아래의 세 클래스 만으로 정리했다. 

* `MemoryPipe` : 소켓 수신버퍼 처리 전용. System.IO.Pipeline과 유사하다.
* `SendBuffer` : 소켓 송신버퍼 처리 전용. 
* `ZeroCopyBuffer` : 네트워크 버퍼가 아닌 범용적인 용도의 인터페이스.

패킷을 보낼때는 데이터 타입을 버퍼로 직렬화 한 후, 이 버퍼를 메모리 복사 없이 소켓에 그대로 연결해주기 위한 추가 처리가 있어야 하는데, 이건 송신 버퍼에만 필요한 동작이라서 클래스를 별도로 나누었다. 각 용도에 특화된 메서드가 추가 구현 되어있을 뿐 코어는 모두 비슷하다. 모두 단위 버퍼를 줄줄이 비엔나처럼 연결해 들고 있는 역할을 한다.

이들 중에 가장 기본이 되는 ZeroCopyBuffer 를 조금 보면 아래와 같다. 

```csharp
namespace Cs.ServerEngine.Network.Buffer
{
  public sealed class ZeroCopyBuffer
  {
    private readonly Queue<LohSegment> segments = new Queue<LohSegment>();
    private LohSegment last;

    public int SegmentCount => this.segments.Count;

    public int CalcTotalSize()
    {
      int result = 0;
      foreach (var data in this.segments)
      {
        result += data.DataSize;
      }

      return result;
    }

    public BinaryWriter GetWriter() => new BinaryWriter(new ZeroCopyOutputStream(this));
    public BinaryReader GetReader() => new BinaryReader(new ZeroCopyInputStream(this));

    internal void Write(byte[] buffer, int offset, int count)
    {
      while (count > 0)
      {
        if (this.last == null || this.last.IsFull)
        {
          this.last = LohSegment.Create(LohPool.SegmentSize.Size4k);
          this.segments.Enqueue(this.last);
        }

        int copied = this.last.AddData(buffer, offset, count);

        offset += copied;
        count -= copied;
      }
    }

    internal LohSegment[] Move()
    {
      var result = this.segments.ToArray();
      this.segments.Clear();
      this.last = null;

      return result;
    }

    internal LohSegment Peek()
    {
      return this.segments.Peek();
    }

    internal void PopHeadSegment()
    {
      var segment = this.segments.Dequeue();
      segment.ToRecycleBin();

      if (this.segments.Count == 0)
      {
        this.last = null;
      }
    }
  }
}

```

본 주제와 관련한 인터페이스만 몇 개 간추려 보았다. `Queue<LogSegment>` 가 Pipeline 안에 있는 단위버퍼의 링크드 리스트 역할을 한다. Write()와 Move()는 메모리 복사 없이 데이터를 쓰는 인터페이스가 되고, Peek(), PopHeadSegment()는 데이터를 읽는 인터페이스가 되는데, internal 접근자니까 실제 사용계층에는 노출하지 않는다. Detail 하위의 *Stream 클래스를 위한 메서드들이다.

조각난 버퍼를 하나의 가상버퍼처럼 추상화해주는 로직은 *Stream들이 담고있다. System.IO.Stream을 상속했기 때문에 사용 계층에서는 보통의 파일스트림, 메모리 스트림을 다루던 방식과 똑같이 값을 읽고 쓰면 된다. 사용한 segment들을 새지 않게 잘 pooling하고, 버퍼 오프셋 계산할때 오차없이 더하기 빼기 잘해주는 코드가 전부인지라 굳이 옮겨붙이지는 않는다. 

이렇게 하니 `ZeroCopyBuffer`는 가상의 무한 버퍼 역할을 하고, 사용 계층에는 Stream 형식의 인터페이스를 제공하는 `System.IO.Pipeline`의 유사품이 되었다. 제공되는 메서드 중에는 `async method` 가 하나도 없으니 cpu clock을 불필요하게 낭비할 일도 없다. 이렇게 디자인 하는것이 기존의 iocp 기반 소켓 구현에 익숙한 프로그래머에겐 더 친숙한 모델이면서, 성능상으로도 Pipeline보다 훨씬 낫고(tcp 기반 게임서버 한정), Unity3D처럼 최신의 Memory api가 지원 안되는 환경에서도 문제없이 사용할 수 있다.



## 마치면서

`System.IO.Pipeline`은 ASP.NET Core의 성능을 크게 끌어올린 네트워크 버퍼 운용 라이브러리다. 이를 적용하면 네트워크 버퍼구현의 여러가지 문제점들과 boilerplate한 구현들을 손쉽게 해결할 수 있으나, 최소 2 tasks/peer를 소켓의 수명만큼 열어두어야 하기 때문에 소켓을 긴 시간 유지하는 타입의 TCP서버라면 도입 전에 신중한 성능 테스트를 거쳐야 한다. 

사이즈가 무한인 가상의 버퍼라는 컨셉만을 가져와 직접 만들어 사용중인 `ZeroCopyBuffer` 모듈의 인터페이스도 간단하게 소개해 보았다. Unity3D 클라이언트 네트워크 모듈에도 함께 사용하기 위해 `ReadOnlySequence<T>` 대신 System.IO.Stream으로 추상화한 인터페이스를 제공했는데, 이렇게 하니 요구사항을 충분히 만족하면서도 사용 계층에게는 더 익숙한 형태의 인터페이스를 제공할 수 있어서 만족스러웠다.

본 포스팅에는 단위버퍼로 이용한 구현체인 `LogSegment`에 대한 소개가 없었다. 글 분량 조절에 실패하여 일부로 언급하지 않았는데, 다음에 가비지 컬렉터를 주제로 포스팅하면서 추가로 다뤄볼 예정이다. 



참고:

* https://www.slideshare.net/sm9kr/windows-registered-io-rio
* https://docs.microsoft.com/ko-kr/dotnet/standard/io/pipelines
* https://devblogs.microsoft.com/dotnet/system-io-pipelines-high-performance-io-in-net/