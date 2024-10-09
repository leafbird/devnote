---
title: '[wpf] MultiValueConverter - 상황에 따라 Button 컨텐츠를 Image와 Text로 변환'
tags:
 - wpf
---

이번엔 이걸 한 번 정리해 볼게요. 
버튼의 컨텐츠를 상황에 따라 Image와 Text로 변환하는 방법입니다.


{% asset_img image.png %}

<!--more-->

일단 버튼의 컨텐츠를 이미지로 채우는 방법은 간단합니다. 

```xml
<Button>
    <Image Source="image.png"/>
</Button>
```

이번에 만들려고 하는 개발툴에서, 버튼을 눌러 선택한 리소스가 있으면 해당 리소스의 이미지를 버튼에 표시해 주고자 했습니다. 개발툴에서는 WPF UI를 사용하고 있어서, 처음엔 일단 간단하게 아래처럼 이미지를 출력했습니다.

```xml
<ui:Button Grid.Column="1" Grid.Row="0" Grid.RowSpan="2" Margin="0,0,10,0"
            Command="{Binding PickUnitCommand}" Padding="0" CornerRadius="8">
    <ui:Image
            Grid.RowSpan="2"
            Width="80"
            CornerRadius="8"
            BorderThickness="1"
            BorderBrush="Black"
            Source="{Binding Cut.Unit.ImageFullPath}"/>
</ui:Button>
```

