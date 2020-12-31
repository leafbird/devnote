---
title: 'C# 고성능 서버 - __FILE__, __LINE__ 대체제'
date: 2020-12-26 11:11:05
tags: [c#, 고성능, 게임서버, 메모리, string interning]
---


## 들어가며

C++에서 가장 기본적으로 사용했던 `__FILE__, __LINE__, __FUNCTION__` 등의 매크로와 유사한 효과를 내는 방법에 대해 적어본다. 이와 함께 나에게는 생소했던 string interning 개념에 대해서도 살짝 소개해본다. 자바 같은 managed 언어를 깊이 다뤄본 적이 없는 네이티브 개발자에게는 생소한 개념일 것이다. 
UI가 없는 서버에서 동작의 내용을 확인하는 가장 기본적인 방법은 file로 남기는 log다. 정상 동작이나 오류상황에 대한 상세한 로그가 남아야 문제가 생겼을 때 파악하기가 쉽기 때문에, 간단한 동작이지만 아주 빈번하게 호출되는 부분이다. 로그 출력에서 성능을 많이 빼앗기지 않도록 기반을 다져놓으면 비즈니스 로직 구현을 위해 더 많은 H/W 리소스를 배분할 수 있다.

성능을 굳이 신경쓰지 않는다면 아래 있는 내용을 끝까지 모두 적용할 필요는 없다. 

<!-- more -->

## 콜스택을 얻어와서 가장 마지막 함수를 찍는 방법

현재 스레드 컨텍스트에서의 [StackFrame](https://docs.microsoft.com/ko-kr/dotnet/api/system.diagnostics.stackframe?redirectedfrom=MSDN&view=net-5.0) 정보를 얻어온 후, 프레임 데이터의 가장 마지막 부분을 읽어 호출자의 정보를 얻어낼 수 있다. C#으로 함수 호출 위치를 얻어올 때 가장 많이 쓰이는 방법이다. 가장 태초부터 있었던 방법이기 때문이다. 다음에 설명할 CompilerServices attribute는 .Net Framework 4.5부터 사용이 가능해졌기 때문에, 초창기 C#에서는 콜스택에서 읽어내는 방법 말고는 딱히 다른 선택지도 없었다.

``` csharp
StackTrace st = new StackTrace(new StackFrame(true)); 

Console.WriteLine(" Stack trace for current level: {0}", st.ToString()); 

StackFrame sf = st.GetFrame(0); 
Console.WriteLine(" File: {0}", sf.GetFileName()); 
Console.WriteLine(" Method: {0}", sf.GetMethod().Name); 
Console.WriteLine(" Line Number: {0}", sf.GetFileLineNumber()); 
Console.WriteLine(" Column Number: {0}", sf.GetFileColumnNumber()); 
```

C#에서 흔하게 사용하는 로깅 라이브러리인 [Log4Net](https://logging.apache.org/log4net/), [NLog](https://nlog-project.org) 등에서도 이 방법을 사용한다. 



#### 콜스택 기반 장점 : 가장 범용적이다. 프레임워크 호환성이 가장 좋음

.Net Framework의 태초부터 있었던 방식이므로 가장 범용적이다. 오래된 버전의 닷넷 프레임워크나 mono 프레임워크 등을 지원해야 하는 상황이라면 이 방법 말고는 마땅한 대안이 없다. 그래서 Log4Net, NLog 등의 유명한 라이브러리도 이 방법을 사용하고 있다. 이들은 불특정 다수의 환경에서 실행되어야 할 범용성이 중요한 모듈이기 때문이다. 

#### 콜스택 기반 단점 : 말해서 무엇하랴. 비용이 비싸고 느리다. 

지금 회사에서 사용하는 게임서버 엔진은 처음에 Log4Net을 쓰다가, 나중에 NLog로 바꾸었다가, 현재는 자체 구현한 파일로그 모듈을 쓰고 있다. 외부 모듈로는 내가 만족하는 성능을 얻지 못했기 때문이다. 

Log4Net, NLog 모두 아주 좋은 로그 모듈인 것은 분명하다. Log4Net은 apache 소프트웨어 재단의 모듈인 만큼 아주 많은 곳에서 쓰이고 있을것이다. 두 모듈 모두 설정 문서만 읽어봐도 정말 기능이 많다. 로그파일을 사이즈나 시간에 맞춰 새 파일로 나눠주는 것은 물론이고, 메일로 로그를 전송할 수도 있고, 로그 레벨 설정도 자유롭고, 파일 생성 정책도 디테일하게 조절할 수 있고... 아무튼 아주 많다. 

내가 이 두 모듈을 떠나서 직접 만들어 사용하는 가장 큰 이유는 `성능` 때문이다. 나에게는 굳이 내가 사용도 하지 않을 것 같은 다수의 편의기능들보다도 딱 내가 필요한 동작만 가지고 있더라도 가볍고 빠른 로그 모듈이 필요했다. Log4Net은 오래되서 잘 기억이 나지 않지만 NLog같은 경우 모듈 자체에서 스레드도 제법 많이 만들어서 운용하는걸 디버깅하다 본 기억이 있는데, 이런 내부 구조도 고성능 엔진을 만든다는 측면에서 부담스러웠다. (고성능을 위한 File IO 전략은 이 글의 주제에서 벗어나니까 다음 기회에 별도의 포스트로 다뤄보겠다.)

범용적인 로그 모듈들은 성능 또한 일반적이다. 크게 좋지도 않고 아주 나쁘지도 않는 수준을 보여준다. NLog를 사용할 때 설정에서 파일 이름과 라인 위치를 출력하는 동작을 끈 채로 사용해도 성능에는 별반 차이가 없었는데, 아마도 파일로 출력만 하지 않을 뿐  내부에서는 동일하게 `StacFrame` 을 얻어오는 동작이 실행되고 있을거라고 추측했다. 혹은 StackFrame 때문이 아닌, 다른 많은 부수 기능들 때문일 수도 있을 텐데, 아무튼 나의 기대치에는 맞지 않았다.



## System.Runtime.CompilerServices

.NET Framework 4.5부터 새로운 방식으로 함수 호출자의 정보를 가져올 수 있게 되었다. 요즘 .NET 6에 대한 뉴스도 돌고 있는 현시점에서 보면 충분히 오래된 방식이다. 만들어야 하는 프로그램의 런타임을 특정 프레임워크만 사용하도록 한정할 수 있다면 이 방식을 사용하는 것을 추천한다. 게임서버는 런타임 환경을 단 하나의 프레임워크로 고정할 수 있으니, 크게 문제될 것이 없다.

```csharp
public void DoProcessing()
{
    TraceMessage("Something happened.");
}

public void TraceMessage(string message,
    [CallerMemberName] string memberName = "",
    [CallerFilePath] string sourceFilePath = "",
    [CallerLineNumber] int sourceLineNumber = 0)
{
    Trace.WriteLine("message: " + message);
    Trace.WriteLine("member name: " + memberName);
    Trace.WriteLine("source file path: " + sourceFilePath);
    Trace.WriteLine("source line number: " + sourceLineNumber);
}
```

함수 인자에 기본값이 있기 때문에 작업자가 함수를 호출할 때 값을 전달하지는 않지만, 그래도 보이지 않게 뒤쪽 인자를 통해 호출자의 파일명, 라인수 등이 넘어가는 방식이다. 인자에 붙어있는 attribute로 인해 함수 호출 위치에 맞는 값들이 `런타임에` 채워진다.

과거의 오래된 프레임워크를 지원할 수 없다는 점이 거꾸로 단점이 될텐데, 사실 NLog같이 누구나 어디서나 사용해야할 로그모듈을 만들게 아니고, 게임서버처럼 특정 비즈니스 프로젝트로 사용처를 한정한다면 오래된 프레임워크 미지원은 그렇게 큰 단점은 아니다. 



#### CompilerServices 장점 : 가볍고 빠르다.

위에서 언급했던 StackFramek 클래스를 사용하는 방식보다 훨씬 빠르다. C++의 `__FILE__, __LINE__` 은 매크로니까 이미 컴파일 타임에 문자열과 숫자로 치환되어 코드에 포함된다. CompilerServices 사용 방식은 런타임에 함수의 인자로 넘어가는 방식이니까 이것만큼 optimal할 수는 없지만, 콜스택을 긁어오는 것보다는 훨씬 빠르다.



#### CompilerService 단점 : 가변인자 인터페이스 사용이 불가능 해진다.

 ```csharp
public void DoProcessing()
{
  WriteLog("invalid value:{0}", value); // 불가능합니다.
}

public void WriteLog(string format,
  params object[] list,
  [CallerFilePath] string sourceFilePath = "",
  [CallerLineNumber] int sourceLineNumber = 0)
{
  ...
}
 ```

함수의 뒷부분 인자를 사용하게 되니까, 위와 같은 사용이 불가능하다. 예시처럼 formatting이 될 문자열을 처음에 받고 두번째부터 가변 인자를 받는 방법은  C++에서 로그 인터페이스를 만드는 가장 익숙한 방식이다. 

하지만 C#은 나름대로의 해결법이 있다. [보간 문자열](https://docs.microsoft.com/ko-kr/dotnet/csharp/language-reference/tokens/interpolated)을 이용해 문자열을 포매팅하면 된다. .NET Framework 4.6 과 함께 C# 문법이 6.0으로 올라갔고 이 때부터 보간 문자열이 사용 가능해졌다. 최신의 C#에서는 String.Format보다 보간 문자열의 사용이 더 권장된다. - Effective C#, 빌 와그너. Chapter 1.4 `string.Format()을 보간 문자열로 대체하라` 

```csharp
public void DoProcessing()
{
  // WriteLog("invalid value:{0}", value); // C++스러워 보이지만, 촌스러운 방식이예요.
  WriteLog($"invalid value:{value}"); // 가능합니다. 권장됩니다. Effective C# 읽어보세요.
}

public void WriteLog(string message,
  [CallerFilePath] string sourceFilePath = "",
  [CallerLineNumber] int sourceLineNumber = 0)
{
  ...
}
```

C#이 5.0이었을 시점만 해도 이건 큰 단점이었다. 하지만 현 시점에서 이것도 그리 문제될 것이 없다.



## C++은 코드영역을 사용하지만, C#은 힙을 사용한다.

좀 더 성능에 집착해보자(?).

윗부분에서 잠시 언급했듯이, C++의 `__FILE__, __LINE__` 은 컴파일 시점에 이미 실제 값으로 변환을 완료하는 preprocessing 이다. 런타임에 함수 호출자 정보를 얻기 위해 추가로 들이는 비용이 거의 없다.

{% asset_img 00.jpg %}

(이미지 출처 : [wikipedia](https://en.wikipedia.org/wiki/Data_segment))

이미지에서 text로 표현된 부분이 코드영역이다. 이 공간은 고정적인 읽기 전용의 공간이다. C++의 `__FILE__` 매크로를 다르게 표현하면 결국 이 코드영역의 특정 위치를 가르키는 char*로 변환될 뿐이다. 추가적인 객체 할당은 없다.

하지만 C#은 코드영역을 사용하지 않는다. `[CallerFilepath] string filePath` 는 **함수 호출이 일어날 때마다 heap 영역에 스트링 객체를 할당한다**. 디버그를 위해 상세하게 로그를 달면 달 수록 heap에는 동일한 텍스트가 반복적으로 할당되어 메모리에 압력을 가하게 된다. 

C#에서는 C++처럼 코드영역을 참조하는 문자열을 만드는 방법이 없다. 모든 참조형식의 객체는 heap이 아닌 공간을 사용할 수 없기 때문으로 추측이 된다. value type을 object 형식으로 가리키면 굳이 비싼 비용을 들이면서까지 heap에 추가할당을 만드는 boxing을 하는 이유와 같을 것이다. 

반복적으로 사용하는 똑같은 문자열인데도, 매번 함수가 불릴 때마다 이걸 heap에 재할당을 할까? 하고 나도 처음엔 그렇게 생각했다. C++을 하면서 생긴 사고의 관성일 것이다. C#의 string은 참조 타입이고, immutable해서 한 번 할당하면 변경도 불가한 성격을 갖고 있기 때문에 충분히 착각할 만한 상황이기도 하다 - 라고 자기 합리화를 해본다.  하지만 windbg를 이용해 heap을 디버깅 하던 중 무수히 많은 파일 경로 텍스트가 중복으로 잔뜩 들어있는걸 보고 나서야 아닌 것을 깨달았다. 



## Interned String

완전하게 내용이 같은 string을 pooling하여 heap에 한 번만 할당하고 돌려쓰는 방법이 없는 것은 아니다. 이렇게 언어 자체적으로 문자열을 풀링하는 처리를 Java와 C#에서는 모두 Interning이라고 부른다. 

* Java - [String Intern()](https://www.javatpoint.com/java-string-intern)
* C# - [String Intern()](https://docs.microsoft.com/ko-kr/dotnet/api/system.string.intern?view=net-5.0)

사용법은 간단하다. 풀링하고 싶은 문자열을 사용할 때 `string.Intern()` 메소드를 한 번 더 감싸주면 된다. 현재 회사에서 실제 사용중인 모듈의 인터페이스 부분만 보면 아래처럼 되어있다. 

```csharp
using System;
using System.IO;
using System.Runtime.CompilerServices;

public static class Log
{
  public static void Debug(string message, [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
  {
    // ... 중략...
    provider.Debug($"{message} ({BuildTag(file, line)})");
  }

  private static string BuildTag(string file, int line)
  {
    return string.Intern($"{Path.GetFileName(file)}:{line.ToString()}");
  }
}
```

전달받은 파일명을 바로 사용하지 않고 string.Intern()으로 한 번 감싸서 사용한다. 로그를 출력하면 아래처럼 찍힌다. 

```
2020-12-21 12:08:02.144 [Debug] [ConnectionMonitor] add uid:1 #connection:1 (ConnectionMonitor.cs:32)
2020-12-21 12:08:02.145 [Info] [Send] [20017] kREGISTER_GAME_SERVER_REQ actionId:3 (SerializableExt.cs:92)
2020-12-21 12:08:02.205 [Info] db connection Initialized. type:Auth server:localhost count:16 (DbPool.cs:40)
2020-12-21 12:08:02.221 [Info] db connection Initialized. type:Contents server:localhost count:16 (DbPool.cs:40)
2020-12-21 12:08:02.238 [Info] db connection Initialized. type:Game server:localhost count:16 (DbPool.cs:40)
```

interning은 입구만 있고, 출구는 없는 string pool이다. 풀에 등록은 할 수 있지만 해제할 수는 없다. 한 번 쓰고 마는 동적인 문자열은 당연히 interning해서는 안된다. 반복적으로 사용하더라도 빈도가 낮아서, heap의 할당과 해제에 큰 압력을 주지 않는다면 이것도 굳이 interning할 필요는 없다. 이런 문자열들을 interning하면 장시간 떠있어야 하는 서버 프로그램의 경우 오히려 더 악영향을 끼칠 수 있다. 용도에 맞게 적절하게 적용해야 한다. 

C#에서 코드에 함께 적혀있는 literl text들은 기본적으로 interning된다. C++처럼 code segment를 직접 가르키지는 않지만, 비슷한 효과를 내기 위함이다. 그 외에 프로그램이 사용하는 나머지 문자열에 대해서는 어떤 것을 interning할지 직접 판단하고 선별 적용해야 한다. 로그 메세지에 반복적으로 찍히는 소스코드 파일명은 interning하기에 적합한 대상이다. 



## 마치면서

로그파일에서 로그 출력 위치를 남기는 방식에 관련해 성능 위주의 고려사항을 정리해 보았다. 

* 함수 호출자 정보를 얻고 싶을 땐 StackFrame 사용 보다 CompileServices 하위 어트리뷰트를 쓰는게 낫다. 
* C#은 파일명같이 정적인 위치라 하더라도 메모리 코드영역의 참조 등을 불가하다. 문자열은 항상 heap에 할당한다.
* 로그를 찍을 때마다 heap에 불필요한 객체 할당이 발생하는 것을 줄이고 싶다면 문자열을 Interning하면 된다.

