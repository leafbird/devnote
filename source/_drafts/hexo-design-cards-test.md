---
title: "hexo-design-cards 플러그인 테스트"
date: 2026-03-01
categories:
  - blog
tags:
  - hexo
  - plugin
---

{% asset_img hexo-test-header.webp hexo-design-cards %}


Hexo 블로그에서 반복적으로 쓰는 디자인 요소들을 인라인 HTML 대신 간결한 태그 문법으로 쓸 수 있게 플러그인을 만들었습니다. 8개 태그를 지원하고, 5가지 컬러 팔레트가 기본으로 들어있어요.

<!--more-->

## 설치

```bash
npm install @leafbird/hexo-design-cards
```

설치하면 별도 설정 없이 바로 사용할 수 있습니다. CSS는 자동으로 주입돼요.

---

## 배너 — Banner

섹션 구분용 배너입니다. 글이 길 때 파트를 나누기 좋아요.

```markdown
{% raw %}{% banner "Section 1: Getting Started" %}{% endraw %}
```

{% banner "Section 1: Getting Started" %}

## 카드 — Cards

컬러 헤더가 있는 카드 그리드입니다. 첫 번째 인자가 열 수예요.

```markdown
{% raw %}{% cards 2 %}
{% card "Title A" %}
Description with **markdown** support.
`code snippets` work too.
{% endcard %}
{% card "Title B" %}
Another card's content.
{% endcard %}
{% endcards %}{% endraw %}
```

{% cards 2 %}
{% card "Title A" %}Description with **markdown** support. `code snippets` work too.{% endcard %}
{% card "Title B" %}Another card's content.{% endcard %}
{% endcards %}

## 액센트 카드 — Accent Cards

왼쪽에 색띠가 붙는 카드입니다. 핵심 포인트 정리에 적합해요.

```markdown
{% raw %}{% accents 2 %}
{% accent "Point 1" %}Description of the first point{% endaccent %}
{% accent "Point 2" %}Description of the second point{% endaccent %}
{% accent "Point 3" %}Third point here{% endaccent %}
{% accent "Point 4" %}Fourth point here{% endaccent %}
{% endaccents %}{% endraw %}
```

{% accents 2 %}
{% accent "Point 1" %}Description of the first point{% endaccent %}
{% accent "Point 2" %}Description of the second point{% endaccent %}
{% accent "Point 3" %}Third point here{% endaccent %}
{% accent "Point 4" %}Fourth point here{% endaccent %}
{% endaccents %}

## 비교 — Compare

두 가지를 나란히 비교할 때 사용합니다.

```markdown
{% raw %}{% compare %}
{% option "Option A" "🔧" %}
Description of option A.
{% endoption %}
{% option "Option B" "🚀" recommended %}
Description of option B.
This one is **recommended**.
{% endoption %}
{% endcompare %}{% endraw %}
```

{% compare %}
{% option "Option A" "🔧" %}Description of option A.{% endoption %}
{% option "Option B" "🚀" recommended %}Description of option B. This one is **recommended**.{% endoption %}
{% endcompare %}

## 알림 — Alert

정보, 경고, 팁 박스입니다. `|`로 제목과 본문을 구분해요.

```markdown
{% raw %}{% alert info %}Title|Body text with **markdown**{% endalert %}
{% alert warning %}Warning title|Warning body{% endalert %}
{% alert tip %}Tip title|Tip body{% endalert %}{% endraw %}
```

{% alert info %}Title|Body text with **markdown**{% endalert %}

{% alert warning %}Warning title|Warning body{% endalert %}

{% alert tip %}Tip title|Tip body{% endalert %}

## 인용 — Quotes

인용 모음입니다. 출처별로 정리할 수 있어요.

```markdown
{% raw %}{% quotes "Section Title" %}
{% dcquote "Source 1" %}Quote text here{% enddcquote %}
{% dcquote "Source 2" %}Another quote{% enddcquote %}
{% endquotes %}{% endraw %}
```

{% quotes "Section Title" %}
{% dcquote "Source 1" %}Quote text here{% enddcquote %}
{% dcquote "Source 2" %}Another quote{% enddcquote %}
{% endquotes %}

## 미니 카드 — Mini Cards

3열 미니 카드입니다. 짧은 항목을 나열할 때 유용해요.

```markdown
{% raw %}{% minicards %}
{% mini "Item A" %}Short description{% endmini %}
{% mini "Item B" %}Short description{% endmini %}
{% mini "Item C" %}Short description{% endmini %}
{% endminicards %}{% endraw %}
```

{% minicards %}
{% mini "Item A" %}Short description{% endmini %}
{% mini "Item B" %}Short description{% endmini %}
{% mini "Item C" %}Short description{% endmini %}
{% endminicards %}

## 플로우 — Flow

수평 플로우 다이어그램입니다. `*`을 붙이면 강조 스텝이 돼요.

```markdown
{% raw %}{% flow "Step A|description" "*Step B|description" "Step C|description" %}{% endraw %}
```

{% flow "Step A|description" "*Step B|description" "Step C|description" %}

캡션을 추가하려면 `|` 뒤에 텍스트를 넣으면 됩니다:

```markdown
{% raw %}{% flow "Request" "*Process" "Response" | Data flow overview %}{% endraw %}
```

{% flow "Request" "*Process" "Response" | Data flow overview %}

{% banner "Part 2: Customization" %}

## 폰트 사이즈 — Font Size

대부분의 태그에서 마지막 숫자 인자로 폰트 사이즈(px)를 지정할 수 있습니다.

```markdown
{% raw %}{% cards 2 15 %}...{% endcards %}       → 2 columns, 15px body text
{% accents 2 14 %}...{% endaccents %}   → 2 columns, 14px body text
{% compare 16 %}...{% endcompare %}     → 16px body text
{% alert warning 17 %}...{% endalert %} → 17px body text{% endraw %}
```

## 컬러웨이 — Colorway

5가지 내장 컬러웨이가 있습니다. front matter에서 글별로 지정할 수 있어요.

```yaml
---
colorway: fiery-ocean
---
```

| Colorway | Vibe |
|----------|------|
| `olive-garden` (default) | Warm olive-gold |
| `deep-sea` | Calm blue-grey |
| `fiery-ocean` | Bold red-blue contrast |
| `rustic-earth` | Natural earth tones |
| `sunny-beach` | Vivid orange-teal |

Color palettes from [Coolors.co](https://coolors.co).

---

소스코드: [GitHub](https://github.com/leafbird/hexo-design-cards) · 라이선스: MIT
