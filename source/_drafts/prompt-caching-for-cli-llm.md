---
title: "CLI LLM, OpenClaw 쓸 때 프롬프트 캐싱 알고 쓰세요"
date: 2026-03-01
categories:
  - AI
tags:
  - Prompt Caching
  - LLM
  - OpenClaw
  - Vibe Coding
  - Cost Optimization
---

Claude Code, OpenClaw, Pi 같은 CLI 기반 LLM 도구를 쓰다 보면, 같은 작업을 하는데도 비용이 들쑥날쑥한 경험을 하게 됩니다. 어떤 때는 호출당 $0.05인데, 어떤 때는 $0.62. 12배 차이. 원인은 **프롬프트 캐싱**입니다.

이 글은 실제 바이브코딩 세션에서 $27을 쓰면서 배운 교훈을 정리한 것입니다. "아 그냥 비싸네" 하고 넘어가기엔 아까운 내용이라 공유합니다.

<!--more-->

## 프롬프트 캐싱이 뭔데?

CLI LLM 도구는 매 호출마다 **전체 대화를 API에 다시 보냅니다**. 시스템 프롬프트, 지금까지의 대화 히스토리, 그리고 새 메시지까지 전부요. 대화가 길어질수록 입력 토큰이 어마어마해지는 구조입니다.

Anthropic API의 프롬프트 캐싱은 이 문제를 해결합니다. 이전 호출과 동일한 프롬프트 접두사(prefix)가 있으면, 서버 측에서 캐시해둔 결과를 재활용해서 **입력 비용을 90% 절감**합니다.

{% asset_img vibe-coding-2026-02-27-slide3.jpg 프롬프트 캐싱 구조와 비용 차이 %}

핵심은 간단합니다:

<div style="display:grid; grid-template-columns:1fr 1fr; gap:20px; margin:25px 0;">
  <div style="background:#e8f5e9; padding:20px; border-radius:12px; border:2px solid #28a745;">
    <h4 style="margin:0 0 10px; text-align:center; color:#2e7d32;">캐시 활성 (Warm)</h4>
    <div style="text-align:center; font-size:36px;">💚</div>
    <p style="text-align:center; font-weight:bold; color:#2e7d32; font-size:24px; margin:10px 0;">$0.05/호출</p>
    <p style="font-size:14px; color:#555; text-align:center;">이전 대화를 캐시에서 읽음<br>입력 비용 1/10</p>
  </div>
  <div style="background:#fff3e0; padding:20px; border-radius:12px; border:2px solid #ff9800;">
    <h4 style="margin:0 0 10px; text-align:center; color:#e65100;">캐시 만료 (Cold)</h4>
    <div style="text-align:center; font-size:36px;">🔥</div>
    <p style="text-align:center; font-weight:bold; color:#e65100; font-size:24px; margin:10px 0;">$0.62/호출</p>
    <p style="font-size:14px; color:#555; text-align:center;">전체 대화를 캐시에 다시 기록<br>12배 더 비쌈</p>
  </div>
</div>

## 컨텍스트 윈도우 ≠ 프롬프트 캐시

여기서 많은 분들이 헷갈리는 부분이 있습니다. **컨텍스트 윈도우와 프롬프트 캐시는 별개**입니다.

<div style="display:grid; grid-template-columns:1fr 1fr; gap:20px; margin:25px 0;">
  <div style="border:2px solid #0066cc; border-radius:12px; overflow:hidden;">
    <div style="background:#0066cc; padding:12px 15px;">
      <h4 style="margin:0; color:#fff; font-size:16px;">컨텍스트 윈도우</h4>
    </div>
    <div style="padding:15px;">
      <p style="font-size:14px; color:#555; margin:0; line-height:1.8;">
        API 요청의 messages 배열<br>
        세션 내내 유지 (<code>/new</code> 하면 초기화)<br>
        <b>역할:</b> 대화 맥락 유지
      </p>
    </div>
  </div>
  <div style="border:2px solid #6f42c1; border-radius:12px; overflow:hidden;">
    <div style="background:#6f42c1; padding:12px 15px;">
      <h4 style="margin:0; color:#fff; font-size:16px;">프롬프트 캐시</h4>
    </div>
    <div style="padding:15px;">
      <p style="font-size:14px; color:#555; margin:0; line-height:1.8;">
        Anthropic 서버 인프라<br>
        마지막 사용 후 <b>~5분</b> (TTL 기반)<br>
        <b>역할:</b> 입력 토큰 비용 90% 절감
      </p>
    </div>
  </div>
</div>

컨텍스트 윈도우는 "뭘 기억하고 있느냐"이고, 프롬프트 캐시는 "기억하는 걸 얼마나 싸게 보내느냐"입니다. 세션을 이어가고 있어도 5분 이상 조용하면 캐시는 사라집니다.

## 실전: $27 바이브코딩 세션에서 배운 것

실제로 약 5.5시간 동안 React + Scala 프로젝트를 바이브코딩한 세션입니다. Claude Opus 4 기준 총 $27.07.

여기서 눈에 띄는 건, **캐시가 날아간 두 번의 사건**이 전체 비용의 40%를 차지했다는 점입니다.

<div style="display:grid; grid-template-columns:1fr 1fr; gap:15px; margin:25px 0;">
  <div style="background:#fff3e0; padding:15px; border-radius:8px; border-left:4px solid #ff9800;">
    <b>💥 사건 1: Context Compaction (11:37)</b>
    <p style="font-size:13px; margin:5px 0 0; color:#555;">컨텍스트가 143k→21k로 압축됨. 프롬프트 구조가 바뀌어 캐시 전량 miss. 직후 호출 비용 $0.26 (평소의 5배)</p>
  </div>
  <div style="background:#ffebee; padding:15px; border-radius:8px; border-left:4px solid #dc3545;">
    <b>💥 사건 2: 점심시간 2.5시간 (14:32)</b>
    <p style="font-size:13px; margin:5px 0 0; color:#555;">5분 TTL 초과로 캐시 완전 만료. ~97k 토큰을 Cache Write로 재전송. 직후 호출 비용 $0.62, $0.77</p>
  </div>
</div>

이 두 사건에서만 **$10.39** — 전체의 40%가 날아갔습니다. 캐시가 warm 상태였다면 $3~4 수준이었을 겁니다.

### 토큰 단가: 왜 이렇게까지 차이가 나나

Claude Opus 4 기준 단가를 보면 이해가 됩니다:

| 토큰 종류 | 단가 (per 1M) | 비고 |
|-----------|-------------|------|
| Cache Read | **$1.50** | 캐시 활성 시 적용 |
| Input (신규) | $15.00 | Cache Read의 10배 |
| Cache Write | $18.75 | 처음 캐시에 쓸 때 |
| Output | **$75.00** | 가장 비쌈 (50배!) |

캐시가 살아있으면 대화 히스토리 수만~수십만 토큰이 $1.50/M으로 처리되지만, 캐시가 죽으면 이게 전부 $18.75/M Cache Write로 바뀝니다.

## 직관과 반대되는 핵심 인사이트

여기가 이 글에서 제일 중요한 부분입니다.

<div style="background:#ffebee; border:2px solid #dc3545; border-radius:12px; padding:20px; margin:25px 0;">
  <h4 style="margin:0 0 10px; color:#c62828;">⚠️ "컨텍스트가 채워져 있으니 이어서 하자"는 함정</h4>
  <p style="margin:0; font-size:14px; line-height:1.8;">
    점심 먹고 돌아왔는데 캐시는 이미 만료. 하지만 컨텍스트 윈도우에는 지금까지의 작업이 가득 차 있습니다.<br><br>
    "다행이다, 맥락이 살아있으니 이어서 하자" — <b>이 순간이 가장 비쌉니다.</b><br><br>
    가득 찬 컨텍스트(~156k 토큰) 전체를 캐시에 다시 써야 하기 때문입니다.
  </p>
</div>

비용 비교:

| 선택 | 첫 호출 Cache Write 비용 |
|------|------------------------|
| 기존 세션 이어가기 (~156k 토큰) | **~$2.93** |
| `/new`로 새 세션 시작 (~17k 토큰) | **~$0.32** |

**약 10배 차이.** 기존 맥락이 반드시 필요한 게 아니라면, `/new`가 압도적으로 유리합니다.

그리고 또 하나 — "빨리 돌아오면 절약된다"도 오해입니다. 캐시가 이미 만료(5분 초과)된 후에는, 30분 후에 돌아오든 2시간 후에 돌아오든 cold start 비용은 동일합니다. "점심을 빨리 먹고 돌아와야지"는 캐시 절약 관점에서는 의미 없는 다짐이에요.

## 실전 절약 팁 4가지

{% asset_img vibe-coding-2026-02-27-slide4-v2.jpg 프롬프트 캐싱 절약 팁 %}

<div style="display:grid; grid-template-columns:repeat(2,1fr); gap:15px; margin:25px 0;">
  <div style="background:#e8f5e9; padding:15px; border-radius:8px; border-left:4px solid #28a745;">
    <b>1. 세션을 오래 유지하기</b>
    <p style="font-size:13px; margin:5px 0 0; color:#555;">자주 <code>/new</code>로 초기화하지 말 것. 대화가 길어져도 캐시가 warm이면 추가 비용은 미미합니다. 리셋할 때마다 캐시도 날아갑니다.</p>
  </div>
  <div style="background:#e3f2fd; padding:15px; border-radius:8px; border-left:4px solid #0066cc;">
    <b>2. 자리 비우기 전 킵얼라이브</b>
    <p style="font-size:13px; margin:5px 0 0; color:#555;">화장실, 커피 타임 전에 가벼운 요청 한 마디. "현재 상태 요약해줘" 같은 거면 충분합니다. 캐시 TTL이 5분 연장됩니다.</p>
  </div>
  <div style="background:#f3e5f5; padding:15px; border-radius:8px; border-left:4px solid #6f42c1;">
    <b>3. 요청을 모아서 보내기</b>
    <p style="font-size:13px; margin:5px 0 0; color:#555;">작은 수정 3번 = $0.15. 한번에 모아서 = $0.07. 여러 변경사항을 한 턴에 묶어서 요청하면 API 호출 횟수가 줄어듭니다.</p>
  </div>
  <div style="background:#fff3e0; padding:15px; border-radius:8px; border-left:4px solid #ff9800;">
    <b>4. 캐시 만료 후엔 /new 고려</b>
    <p style="font-size:13px; margin:5px 0 0; color:#555;">캐시가 죽은 상태에서 컨텍스트가 가득 차 있다면? 기존 맥락이 꼭 필요한 게 아니면 <code>/new</code>로 새로 시작하는 게 10배 저렴합니다.</p>
  </div>
</div>

## 캐시가 무효화되는 3가지 경우

정리하면, 프롬프트 캐시가 날아가는 경우는 딱 세 가지입니다:

<div style="display:grid; grid-template-columns:repeat(3,1fr); gap:15px; margin:20px 0;">
  <div style="border:1px solid #dc3545; border-radius:8px; padding:15px; background:#fff5f5;">
    <h5 style="margin:0 0 8px; color:#c62828;">⏰ TTL 만료</h5>
    <p style="font-size:13px; color:#666; margin:0;">5분 이상 API 호출이 없으면 캐시 소멸</p>
  </div>
  <div style="border:1px solid #ff9800; border-radius:8px; padding:15px; background:#fff8f0;">
    <h5 style="margin:0 0 8px; color:#e65100;">🔄 Context Compaction</h5>
    <p style="font-size:13px; color:#666; margin:0;">컨텍스트가 한계에 도달해 압축되면 프롬프트 구조가 변경</p>
  </div>
  <div style="border:1px solid #6f42c1; border-radius:8px; padding:15px; background:#faf5ff;">
    <h5 style="margin:0 0 8px; color:#6f42c1;">🆕 세션 리셋</h5>
    <p style="font-size:13px; color:#666; margin:0;"><code>/new</code>, <code>/reset</code>으로 대화를 초기화하면 프롬프트가 완전히 바뀜</p>
  </div>
</div>

## 마무리

프롬프트 캐싱은 "알면 절약, 모르면 낭비"의 전형적인 케이스입니다. 특히 CLI LLM 도구는 매 호출마다 전체 대화를 다시 보내는 구조라, 캐시의 영향이 체감됩니다.

핵심은 **무조건 세션을 재사용하는 것이 능사가 아니라는 점**입니다. 캐시가 살아있을 땐 이어가고, 캐시가 죽었을 땐 상황에 따라 `/new`를 선택하는 판단이 필요합니다.

이 팁들만 의식해도 하루 $5~10은 아낄 수 있습니다. 바이브코딩 많이 하시는 분들, 한번 신경 써보세요.
