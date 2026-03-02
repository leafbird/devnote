---
title: hexo-design-cards 플러그인 테스트
tags:
  - hexo
  - plugin
categories:
  - blog
date: 2026-03-02 00:00:00
---


어제는 뜬금없이 제가, npm 레지스트리에 패키지를 하나 올리게 되었습니다. 

{% asset_img npm-readme.png hexo-design-cards %}

hexo 블로그 엔진으로 글을 쓸 때, 디자인 요소를 추가하는 태그 정의를 플러그인으로 만들었어요. 
저의 개인비서 오픈클로와 함께 정리해서 배포했습니다. 
제 깃헙 repo에, 순수 javascript로만 작성된 첫 프로젝트가 되었습니다 :)

npm : https://www.npmjs.com/package/hexo-design-cards
github : https://github.com/leafbird/hexo-design-cards

<!--more-->

---

플러그인을 설치할 때 추가적으로 제공하는 태그는 7개 입니다. 5가지 컬러 팔레트가 기본으로 들어있고, 포스팅을 만들 떄마다 프론트매터에서 색상 테마를 변경할 수 있어서, 글의 분위기에 맞는 컬러를 골라 사용할 수 있습니다.


## 설치

```bash
npm install hexo-design-cards
```

설치하면 별도 설정 없이 바로 사용할 수 있습니다. CSS는 자동으로 주입돼요.


## 태그 소개

### 배너 : Banner

섹션 구분용 배너입니다. 글이 길 때 파트를 나누기 좋아요.

```markdown
{% banner "Section 1: Getting Started" %}
```

{% banner "Section 1: Getting Started" %}

### 카드 : Cards

컬러 헤더가 있는 카드 그리드입니다. 첫 번째 인자는 세로로 만들어질 컬럼(열) 수예요.

```markdown
{% cards 2 %}
  {% card "Title A" %}
  Description with **markdown** support. `code snippets` work too.
  {% endcard %}
  {% card "Title B" %}Another card's content.{% endcard %}
{% endcards %}
```

{% cards 2 %}
  {% card "Title A" %}Description with **markdown** support. `code snippets` work too.{% endcard %}
  {% card "Title B" %}Another card's content.{% endcard %}
{% endcards %}

### 액센트 카드 : Accent Cards

왼쪽에 색띠가 붙는 카드입니다. 핵심 포인트 정리에 적합해요.

```markdown
{% accents 2 %}
  {% accent "Point 1" %}Description of the first point{% endaccent %}
  {% accent "Point 2" %}Description of the second point{% endaccent %}
  {% accent "Point 3" %}Third point here{% endaccent %}
  {% accent "Point 4" %}Fourth point here{% endaccent %}
{% endaccents %}
```

{% accents 2 %}
  {% accent "Point 1" %}Description of the first point{% endaccent %}
  {% accent "Point 2" %}Description of the second point{% endaccent %}
  {% accent "Point 3" %}Third point here{% endaccent %}
  {% accent "Point 4" %}Fourth point here{% endaccent %}
{% endaccents %}

### 비교 : Compare

두 가지를 나란히 비교할 때 사용합니다. 비교 옵션중 더 추천하고 싶은 항목에 `recomended` 를 적으면 테두리를 더 두껍게 표시하여 시각적으로 강조를 더해줍니다.

```markdown
{% compare %}
  {% option "Option A" "🔧" %}Description of option A.{% endoption %}
  {% option "Option B" "🚀" recommended %}
    Description of option B. This one is **recommended**.
  {% endoption %}
{% endcompare %}
```

{% compare %}
  {% option "Option A" "🔧" %}Description of option A.{% endoption %}
  {% option "Option B" "🚀" recommended %}
    Description of option B. This one is **recommended**.
  {% endoption %}
{% endcompare %}

### 알림 : Alert

정보, 경고, 팁 박스입니다. `|`로 제목과 본문을 구분해요.

```markdown
{% alert info %}Title|Body text with **markdown**{% endalert %}
{% alert warning %}Warning title|Warning body{% endalert %}
{% alert tip %}Tip title|Tip body{% endalert %}
```

{% alert info %}Title|Body text with **markdown**{% endalert %}

{% alert warning %}Warning title|Warning body{% endalert %}

{% alert tip %}Tip title|Tip body{% endalert %}

### 인용 : Quotes

인용 모음입니다. 출처별로 정리할 수 있어요.

```markdown
{% quotes "Section Title" %}
  {% dcquote "Source 1" %}Quote text here{% enddcquote %}
  {% dcquote "Source 2" %}Another quote{% enddcquote %}
{% endquotes %}
```

{% quotes "Section Title" %}
  {% dcquote "Source 1" %}Quote text here{% enddcquote %}
  {% dcquote "Source 2" %}Another quote{% enddcquote %}
{% endquotes %}

### 미니 카드 : Mini Cards

3열 미니 카드입니다. 짧은 항목을 나열할 때 유용해요.

```markdown
{% minicards %}
  {% mini "Item A" %}Short description{% endmini %}
  {% mini "Item B" %}Short description{% endmini %}
  {% mini "Item C" %}Short description{% endmini %}
{% endminicards %}
```

{% minicards %}
  {% mini "Item A" %}Short description{% endmini %}
  {% mini "Item B" %}Short description{% endmini %}
  {% mini "Item C" %}Short description{% endmini %}
{% endminicards %}

### 플로우 : Flow

수평 플로우 다이어그램입니다. `*`을 붙이면 강조 스텝이 돼요.

```markdown
{% flow "Step A|description" "*Step B|description" "Step C|description" %}
```

{% flow "Step A|description" "*Step B|description" "Step C|description" %}

캡션을 추가하려면 `|` 뒤에 텍스트를 넣으면 됩니다:

```markdown
{% flow "Request" "*Process" "Response" | Data flow overview %}
```

{% flow "Request" "*Process" "Response" | Data flow overview %}


## 커스터마이징

### 폰트 사이즈 : Font Size

대부분의 태그에서 마지막 숫자 인자로 폰트 사이즈(px)를 지정할 수 있습니다. 디자인 요소의 본문에 해당하는 글씨의 크기만 조정합니다. 자신의 블로그 기본 크기에 어울리도록 조절해 사용할 수 있어요. 

```markdown
{% cards 2 15 %}...{% endcards %}       → 2 columns, 15px body text
{% accents 2 14 %}...{% endaccents %}   → 2 columns, 14px body text
{% compare 16 %}...{% endcompare %}     → 16px body text
{% alert warning 17 %}...{% endalert %} → 17px body text
```

### 컬러웨이 : Colorway

5가지 내장 컬러웨이가 있습니다. 포스팅 문서 제일 앞 front matter에서 글별로 지정할 수 있어요.

```yaml
---
title: "my awsome blah blah posting"
date: 2026-03-02
tags:
  - hexo
  - plugin
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
